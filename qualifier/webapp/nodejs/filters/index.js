var config = require('../config');

exports.session = function(req, res, next) {
    var session = req.session;
    res.locals.session = session;
    next();
};

exports.get_user = function(req, res, next) {
   if (req.path == '/signin' && req.method == 'POST') {
       next();
   } else {
       var user_id = req.session.user_id;
       res.locals.mysql.query(
            'SELECT * FROM users WHERE id=?',
           [ user_id ],
           function(err, results) {
               if (err) { throw err; }
               res.locals.user = results[0];
               if (results[0]) {
                   res.header('Cache-Control', 'private');
               }
               next();
           }
       );
    }
};

exports.require_user = function(req, res, next) {
    if (req.path == '/mypage' || req.path == '/signout' || req.path == '/memo') {
        if (!res.locals.user) {
            res.redirect('/');
            res.is_halt = true;
        }
    }
    next();
};

exports.anti_csrf = function(req, res, next) {
    if (req.path == '/signout' || req.path == '/memo') {
        if (req.body.sid != req.session.token) {
            res.halt(400);
        }
    }
    next();
};



