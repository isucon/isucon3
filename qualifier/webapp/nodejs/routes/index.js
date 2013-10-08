
var config  = require('../config');
var filters = require('../filters');
var async   = require('async');
var crypto  = require('crypto');
var temp    = require('temp');
var fs      = require('fs');
var exec    = require('child_process').exec;

function markdown(body, callback) {
    temp.open('mdfile', function(err, info) {
        fs.write(info.fd, body);
        fs.close(info.fd, function(err) {
            exec('../bin/markdown ' + info.path, function(err, stdout) {
                var result = stdout;
                fs.unlink(info.path, function(err) {
                    if (err) { throw err; }
                    process.nextTick(function(){
                        callback(null, result);
                    });
                });
            });
        });
    });
};

exports.index = function(req, res) {
    if (res.is_halt) { return; }

    var client = res.locals.mysql;
    async.series([
        function(cb) {
            client.query('SELECT count(*) AS total FROM memos WHERE is_private=0', cb);
        },
        function(cb) {
            client.query('SELECT * FROM memos WHERE is_private=0 ' +
                         'ORDER BY created_at DESC, id DESC LIMIT 100', cb);
        }
    ], function(err, results) {
        if (err) { throw err; }
        var total = results[0][0][0].total;
        var memos = results[1][0];
        async.mapSeries(memos, function(memo, cb) {
            client.query('SELECT username FROM users WHERE id=?', [ memo.user ], cb);
        }, function (err, results) {
             if (err) { throw err; }
             results.forEach(function(e, i) {
                 memos[i].username = e[0].username;
             });

             res.locals.mysql.end();
             res.render('index.ejs', {
                 memos: memos,
                 page:  0,
                 total: total
             });
        });
    });
}

exports.recent = function(req, res) {
    if (res.is_halt) { return; }

    var client = res.locals.mysql;
    var page = req.params.page;

    async.series([
        function(cb) {
            client.query('SELECT count(*) AS total FROM memos WHERE is_private=0', cb);
        },
        function(cb) {
            client.query('SELECT * FROM memos WHERE is_private=0 ' +
                         'ORDER BY created_at DESC, id DESC LIMIT 100 OFFSET ?',
                         [ page * 100 ], cb);
        }
    ], function(err, results) {
        if (err) { throw err; }
        if (results[0].length == 0) {
            res.halt(404);
            return;
        }
        var total = results[0][0][0].total;
        var memos = results[1][0];
        async.mapSeries(memos, function(memo, cb) {
            client.query('SELECT username FROM users WHERE id=?', [ memo.user ], cb);
        }, function (err, results) {
             if (err) { throw err; }
             results.forEach(function(e, i) {
                 memos[i].username = e.username;
             });

             res.locals.mysql.end();
             res.render('index.ejs', {
                 memos: memos,
                 page:  page,
                 total: total
             });
        });
    });
};

exports.signin = function(req, res) {
    if (res.is_halt) { return; }

    res.locals.mysql.end();
    res.render('signin.ejs');
};

exports.signout = function(req, res) {
    if (res.is_halt) { return; }

    req.session.user_id = null;
    res.locals.mysql.end();
    res.cookie('isucon_session', '', { expires: new Date(Date.now() - 10), httpOnly: true });
    res.redirect('/');
};

exports.request_signin = function(req, res) {
    if (res.is_halt) { return; }

    var client = res.locals.mysql;
    var username = req.body.username;
    var password = req.body.password;

    client.query(
        'SELECT id, username, password, salt FROM users WHERE username=?',
        [ username ],
        function(err, results) {
            if (err) { throw err; }
            var user = results[0];

            if (user && user.password ==
                crypto.createHash('sha256').update(user.salt + password).digest("hex")){
                req.session.regenerate(function(err) {
                    if (err) { throw err; }
                    req.session.user_id = user.id;
                    req.session.token = crypto.createHash('sha256').
                        update(Math.random().toString()).digest("hex");
                    req.session.save(function(err) {
                        if (err) { throw err; }
                        client.query(
                            'UPDATE users SET last_access=now() WHERE id=?',
                            [ user.id ],
                            function(err, results) {
                                if (err) { throw err; }
                                res.locals.mysql.end();
                                res.redirect('/mypage');
                            }
                        );
                    });
               });
            } else {
                res.locals.mysql.end();
                res.redirect('/signin');
            }
        }
    );
};


exports.mypage = function(req, res) {
    if (res.is_halt) { return; }

    var client = res.locals.mysql;
    client.query(
        'SELECT id, content, is_private, created_at, updated_at FROM memos WHERE user=? ORDER BY created_at DESC',
        [ res.locals.user.id ],
        function(err, results) {
            if (err) { throw err; }
            res.locals.mysql.end();
            res.render('mypage.ejs', { memos: results });
        }
    );
};

exports.post_memo = function(req, res) {
    if (res.is_halt) { return; }

    var client = res.locals.mysql;
    client.query(
        'INSERT INTO memos (user, content, is_private, created_at) VALUES (?, ?, ?, now())',
        [
            res.locals.user.id,
            req.body.content,
            req.body.is_private != 0 ? 1 : 0
        ],
        function(err, info) {
            if (err) { throw err; }
            var memo_id = info.insertId;
            res.locals.mysql.end();
            res.redirect('/memo/' + memo_id);
        }
    );
};

exports.memo = function(req, res) {
    if (res.is_halt) { return; }

    var user = res.locals.user;
    var client = res.locals.mysql;
    var memo;
    async.waterfall([
        function(cb) {
            client.query(
                'SELECT id, user, content, is_private, created_at, updated_at FROM memos WHERE id=?',
                [ req.params.id ],
                cb
            );
        },
        function(results, fields, cb) {
            memo = results[0];
            if (!memo) {
                res.halt(404);
                return;
            }
            if (memo.is_private) {
                if ( !user || user.id != memo.user ) {
                    res.halt(404);
                    return;
                }
            }

            markdown(memo.content, cb);
        },
        function(html, cb) {
            if (res.is_halt) {
                cb();
                return;
            }
            memo.content_html = html;
            client.query(
                'SELECT username FROM users WHERE id=?',
                [ memo.user ],
                cb
            );
        },
        function(results, fields, cb) {
            if (res.is_halt) {
                cb();
                return;
            }
            memo.username = results[0].username;

            var cond;
            if (user && user.id == memo.user) {
                cond = "";
            } else {
                cond = "AND is_private=0";
            }

            client.query(
                "SELECT * FROM memos WHERE user=? " + cond + " ORDER BY created_at",
                [ memo.user ],
                cb
            );
        },
        function(results, fields, cb) {
            if (res.is_halt) {
                cb();
                return;
            }
            var memos = results;

            var newer;
            var older;
            memos.forEach(function(e, i) {

                if (memos[i].id == memo.id) {
                    if (i > 0) {
                      older = memos[i - 1];
                    }
                    if (i < memos.length) {
                      newer = memos[i + 1];
                    }
                }
            });


            res.locals.mysql.end();
            res.render('memo.ejs', {
                memo:  memo,
                older: older,
                newer: newer
            });
        }
    ]);
};
