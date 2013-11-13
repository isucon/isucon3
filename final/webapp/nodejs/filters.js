exports.get_user = function(req, res, next) {
    if (req.path == "/signup" || req.path.match(/^\/icon\//)) {
        next();
    }
    else {
        var api_key = req.header("X-API-Key") || req.cookies.api_key;

        res.locals.mysql.query(
            "SELECT * FROM users WHERE api_key=?",
            [api_key],
            function(err, results) {
                if (err) { throw err; }
                res.locals.user = results[0];
                next();
           }
        );
    }
};

exports.require_user = function(req, res, next) {
    if (req.path == "/me") {
        if (! res.locals.user) {
            res.halt(400);
            res.is_halt = true;
        };
    }

    next();
}
