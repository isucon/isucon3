var fs     = require("fs");
var crypto = require("crypto");
var temp   = require("temp");
var exec   = require("child_process").exec;
var config = require("./config");

const ICON_S  = 32;
const ICON_M  = 64;
const ICON_L  = 128;
const IMAGE_S = 128;
const IMAGE_M = 256;
const IMAGE_L = undefined;

const TIMEOUT  = 30;
const INTERVAL = 2;

function convert(params, callback) {
    temp.open("img", function(err, info) {
        exec([
            "convert",
            "-geometry",
            params.w + "x" + params.h,
            params.orig,
            info.path
        ].join(" "), function(err, stdout) {
            var data = fs.readFileSync(info.path, "binary");

            fs.unlink(info.path, function(err) {
                if (err) { throw err; }

                process.nextTick(function() {
                    callback(null, data);
                });
            });
        });
    });
};

function cropSquare(orig, ext, callback) {
    exec("identify " + orig, function(err, stdout) {
        var size = stdout.split(/ +/)[2].split(/x/);
        var w    = size[0] - 0;
        var h    = size[1] - 0;
        var cropX, cropY, pixels;

        if (w > h) {
            pixels = h;
            cropX  = Math.floor((w - pixels) / 2);
            cropY  = 0;
        }
        else if (w < h) {
            pixels = w;
            cropX  = 0;
            cropY  = Math.floor((h - pixels) / 2);
        }
        else {
            pixels = w;
            cropX  = 0;
            cropY  = 0;
        }

        temp.open("img", function(err, info) {
            exec([
                "convert",
                "-crop",
                pixels + "x" + pixels + "+" + cropX + "+" + cropY,
                orig,
                info.path + "." + ext
            ].join(" "), function(err, stdout) {
                fs.unlink(info.path, function(err) {
                    if (err) { throw err; }

                    process.nextTick(function() {
                        callback(null, info.path + "." + ext);
                    });
                });
            });
        });
    });
}

function getFollowing(req, res) {
    var user = res.locals.user;
    var client = res.locals.mysql;

    client.query(
        "SELECT users.* FROM follow_map JOIN users ON (follow_map.target=users.id) WHERE follow_map.user = ? ORDER BY follow_map.created_at DESC",
        [user.id],
        function(err, following) {
            if (err) { throw err; }

            res.setHeader("Cache-Control", "no-cache");
            res.locals.sendJSON({
                users: following.map(function(u) {
                    return {
                        id: u.id,
                        name: u.name,
                        icon: res.locals.uri_for("/icon/" + u.icon)
                    };
                })
            });
        }
    );
};

exports.get_index = function(req, res) {
    var html = fs.readFileSync(__dirname + "/public/index.html", "utf8");
    res.send(html);
};

exports.get_me = function(req, res) {
    if (res.is_halt) { return; }

    var user = res.locals.user;

    res.locals.sendJSON({
        id: user.id,
        name: user.name,
        icon: res.locals.uri_for("/icon/" + user.icon)
    });
};

exports.get_icon = function(req, res) {
    var icon = req.params.icon;
    var size = req.query.size || "s";
    var dir  = config.data_dir;

    if (! fs.existsSync(dir + "/icon/" + icon + ".png")) {
        res.halt(404);
        return;
    };

    var w = size == "s" ? ICON_S
          : size == "m" ? ICON_M
          : size == "l" ? ICON_L
          :               ICON_S;

    var h = w;

    convert({
        orig: dir + "/icon/" + icon + ".png",
        w: w,
        h: h,
    }, function(err, data) {
        if (err) { halt(500); return }
        res.setHeader("Content-Type", "image/png");
        res.end(data, "binary");
    });
};

exports.get_image = function(req, res) {
    if (res.is_halt) { return; }

    var user  = res.locals.user;
    var image = req.params.image;
    var size  = req.query.size || "l";
    var dir   = config.data_dir;

    var returnImage = function() {
        var w = size == "s" ? IMAGE_S
              : size == "m" ? IMAGE_M
              : size == "l" ? IMAGE_L
              :               IMAGE_L;
        var h = w;

        if (w) {
            var file = cropSquare(dir + "/image/" + image + ".jpg", "jpg", function(err, file) {
                convert({
                    orig: file,
                    ext: "jpg",
                    w: w,
                    h: h,
                }, function(err, data) {
                    res.setHeader("Content-Type", "image/jpeg");
                    res.end(data, "binary");
                });
            });
        }
        else {
            var data = fs.readFileSync(dir + "/image/" + image + ".jpg", "binary");
            res.setHeader("Content-Type", "image/jpeg");
            res.end(data, "binary");
        }
    };

    var client = res.locals.mysql;
    var entry = client.query(
        "SELECT * FROM entries WHERE image=?",
        [image],
        function(err, results) {
            if (err) { throw err; }

            if (results.length == 0) {
                res.halt(404);
                return;
            }

            var entry = results[0];
            if (entry.publish_level == 0) {
                if (user && entry.user == user.id) {
                     // publish_level==0 はentryの所有者しか見えない
                     // ok
                     returnImage();
                }
                else {
                    res.halt(404);
                    return;
                }
            }
            else if (entry.publish_level == 1) {
                if (user && entry.user == user.id) {
                    // ok
                    returnImage();
                }
                else if (user) {
                    client.query(
                        "SELECT * FROM follow_map WHERE user=? AND target=?",
                        [user.id, entry.user],
                        function(err, results) {
                            if (err) { throw err; }

                            if (results.length == 0) {
                                res.halt(404);
                                return;
                            }

                            returnImage();
                        }
                    );
                }
                else {
                    res.halt(404);
                    return;
                }
            }
            else {
                returnImage();
            }
        }
    );
};

exports.get_follow = getFollowing;

exports.get_timeline = function(req, res) {
    if (res.is_halt) { return; }

    var user = res.locals.user;
    var latest_entry = req.query.latest_entry;
    var sql, params;

    if (latest_entry) {
        sql    = "SELECT * FROM (SELECT * FROM entries WHERE (user=? OR publish_level=2 OR (publish_level=1 AND user IN (SELECT target FROM follow_map WHERE user=?))) AND id > ? ORDER BY id LIMIT 30) AS e ORDER BY e.id DESC";
        params = [user.id, user.id, latest_entry];
    }
    else {
        sql    = "SELECT * FROM entries WHERE (user=? OR publish_level=2 OR (publish_level=1 AND user IN (SELECT target FROM follow_map WHERE user=?))) ORDER BY id DESC LIMIT 30";
        params = [user.id, user.id];
    }

    var start  = Math.floor(new Date().getTime() / 1000);
    var client = res.locals.mysql;

    var retrieveEntries = function(entries) {
        if (Math.floor(new Date().getTime() / 1000) - start < TIMEOUT) {
            client.query(sql, params, function(err, results) {
                if (err) { throw err; }

                if (results.length == 0) {
                    setTimeout(function() {
                        retrieveEntries(entries);
                    }, INTERVAL * 1000);
                }
                else {
                    entries = results;
                    latest_entry = entries[0].id;
                    response(entries);
                }
            });
        }
        else {
            response(entries);
        }
    };

    var response = function(entries) {
        var createJSON = function(entries, json) {
            if (entries.length == 0) {
                sendJSON(json);
                return;
            }

            var entry = entries.shift();

            client.query(
                "SELECT * FROM users WHERE id=?",
                [entry.user],
                function(err, results) {
                    if (err) { throw err; }

                    var user = results[0];

                    json.entries.push({
                        id: entry.id,
                        image: res.locals.uri_for("/image/" + entry.image),
                        publish_level: entry.publish_level,
                        user: {
                            id: user.id,
                            name: user.name,
                            icon: res.locals.uri_for("/icon/" + user.icon)
                        }
                    });

                    createJSON(entries, json);
                }
            );
        };

        var sendJSON = function(json) {
            res.setHeader("Cache-Control", "no-cache");
            res.locals.sendJSON(json);
        };

        createJSON(entries, {
            latest_entry: latest_entry,
            entries: []
        });
    }

    retrieveEntries([]);
};

exports.post_signup = function(req, res) {
    var name = req.body.name;

    if (! name.match(/^[0-9a-zA-Z_]{2,16}$/)) {
        res.halt(400);
        return;
    };

    var api_key = crypto.createHash("sha256").update(Math.random().toString()).digest("hex");

    var client = res.locals.mysql;
    client.query(
        "INSERT INTO users(name, api_key, icon) VALUES(?, ?, ?)",
        [name, api_key, 'default'],
        function(err, result) {
            if (err) { throw err; }

            var id = result.insertId;
            client.query(
                "SELECT * FROM users WHERE id=?",
                [id],
                function(err, results) {
                    if (err) { throw err; }

                    var user = results[0];
                    res.locals.sendJSON({
                        id: user.id,
                        name: user.name,
                        icon: res.locals.uri_for("/icon/" + user.icon),
                        api_key: user.api_key
                    });
                }
            );
        }
    );
};

exports.post_icon = function(req, res) {
    if (res.is_halt) { return; }

    var user   = res.locals.user;
    var upload = req.files.image;

    if (! upload) {
        res.halt(400);
        return;
    }

    if (! upload.headers["content-type"].match(/^image\/jp?g|png$/)) {
        res.halt(400);
        return;
    }

    cropSquare(upload.path, "png", function(err, file) {
        var icon = crypto.createHash("sha256").update([
            user.id,
            new Date().getTime(),
            Math.random()
        ].join("")).digest("hex");

        var dir = config.data_dir;

        fs.renameSync(file, dir + "/icon/" + icon + ".png");

        var client = res.locals.mysql;
        client.query(
            "UPDATE users SET icon=? WHERE id = ?",
            [icon, user.id],
            function(err, result) {
                if (err) { throw err; }
                res.locals.sendJSON({
                    icon: res.locals.uri_for("/icon/" + icon)
                });
            }
        );
    });
};

exports.post_entry = function(req, res) {
    if (res.is_halt) { return; }

    var user   = res.locals.user;
    var upload = req.files.image;

    if (! upload) {
        res.halt(400);
        return;
    }

    if (! upload.headers["content-type"].match(/^image\/jpe?g$/)) {
        res.halt(400);
        return;
    }

    var image_id = crypto.createHash("sha256").update(
        new Date().getTime() + "" + Math.random()
    ).digest("hex");

    var dir = config.data_dir;

    fs.renameSync(upload.path, dir + "/image/" + image_id + ".jpg");

    var publish_level = req.body.publish_level;
    var client        = res.locals.mysql;

    client.query(
        "INSERT INTO entries (user, image, publish_level, created_at) VALUES (?, ?, ?, now())",
        [user.id, image_id, publish_level],
        function(err, result) {
            if (err) { throw err; }

            client.query(
                "SELECT * FROM entries WHERE id=?",
                [result.insertId],
                function(err, results) {
                    if (err) { throw err; }

                    var entry = results[0];
                    res.locals.sendJSON({
                        id: entry.id,
                        image: res.locals.uri_for("/image/" + entry.image),
                        publish_level: entry.publish_level,
                        user: {
                            id: user.id,
                            name: user.name,
                            icon: res.locals.uri_for("/icon/" + user.icon)
                        }
                    });
                }
            );
        }
    );
};

exports.post_entry_id = function(req, res) {
    if (res.is_halt) { return; }

    var user   = res.locals.user;
    var id     = req.params.id;
    var dir    = config.data_dir;
    var client = res.locals.mysql;

    client.query(
        "SELECT * FROM entries WHERE id=?",
        [id],
        function(err, results) {
            if (err) { throw err; }

            if (results.length == 0) {
                res.halt(404);
                return;
            }

            var entry = results[0];

            if (entry.user != user.id || req.body.__method != "DELETE") {
                res.halt(400);
                return;
            }

            client.query(
                "DELETE FROM entries WHERE id=?",
                [id],
                function(err, result) {
                    if (err) { throw err; }

                    res.locals.sendJSON({
                        ok: true
                    });
                }
            );
        }
    );
};

exports.post_follow = function(req, res) {
    if (res.is_halt) { return; }

    var client = res.locals.mysql;
    var user   = res.locals.user;
    var target = req.body.target;

    if (target == user.id) {
        getFollowing(req, res);
    }
    else {
        if (target == user.id) { return; }

        client.query(
            "INSERT IGNORE INTO follow_map (user,target, created_at) VALUES (?, ?, now())",
            [user.id, target],
            function(err, result) {
                if (err) { throw err; }
                getFollowing(req, res);
            }
        );
    };
};

exports.post_unfollow = function(req, res) {
    if (res.is_halt) { return; }

    var client = res.locals.mysql;
    var user   = res.locals.user;
    var target = req.body.target;

    if (target == user.id) {
        getFollowing(req, res);
    }
    else {
        client.query(
            "DELETE FROM follow_map WHERE user=? AND target=?",
            [user.id, target],
            function(err, reslut) {
                if (err) { throw err; }

                getFollowing(req, res);
            }
        );
    };
};
