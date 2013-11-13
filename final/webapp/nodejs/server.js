var express = require("express");
var http    = require("http");
var path    = require("path");
var mysql   = require("mysql");
var cluster = require("cluster");
var routes  = require("./routes");
var config  = require("./config");
var filters = require("./filters");

if (cluster.isMaster) {
    for (var i = 0, childProcesses = []; i < 2; ++i) {
        childProcesses[i] = cluster.fork();
    }

    var signals = ["SIGINT", "SIGTERM", "SIGQUIT"];

    for (s in signals) {
        process.on(signals[s], function() {
            for (var j in childProcesses) {
                childProcesses[j].process.kill();
            }

            process.exit(1);
        });
    }

    cluster.on("exit", function(worker) {
        console.log("worker %s died. restart...", worker.pid);
        var child = cluster.fork();
        childProcesses.push(child);
    });
}
else {
    var app = express();

    app.configure("development", function() {
        app.use(express.logger("dev"));
        app.use(express.errorHandler());
    });

    app.configure(function() {
        app.set("port", process.env.PORT || 5000);
        app.use(express.favicon());
        app.use(express.bodyParser());
        app.use(express.methodOverride());
        app.use(express.cookieParser());
        app.use("/favicon.ico", express.static(path.join(__dirname, "public")));
        app.use("/css", express.static(path.join(__dirname, "public/css")));
        app.use("/img", express.static(path.join(__dirname, "public/img")));
        app.use("/js", express.static(path.join(__dirname, "public/js")));

        app.use(function(req, res, next) {
            config.database.database = config.database.dbname;
            res.locals.mysql         = mysql.createClient(config.database);

            next();
        });

        app.use(function(req, res, next) {
            res.locals.uri_for = function(path) {
                var scheme = req.protocol;
                var host   = req.get("X-Forwarded-Host");

                if (! host) { host = req.get("Host"); }

                return scheme + "://" + host + path;
            };

            next();
        });

        app.use(function(req, res, next) {
            res.locals.sendJSON = function(obj) {
                res.setHeader("Content-Type", "application/json");
                res.end(JSON.stringify(obj));
            };

            next();
        });

        app.use(function(req, res, next) {
            res.is_halt = false;
            res.halt    = function(status) {
                res.locals.mysql.end();
                res.is_halt = true;
                res.send(status);
            };

            next();
        });

        app.use(function(req, res, next) {
            var end = res.end;
            res.end = function(chunk, encoding) {
                if (res.locals.mysql.connected) {
                    res.locals.mysql.end();
                }
                end(chunk, encoding);
            };

            next();
        });

        app.use(filters.get_user);
        app.use(filters.require_user);
    });

    app.get("/", routes.get_index);
    app.get("/me", routes.get_me);
    app.get("/icon/:icon", routes.get_icon);
    app.get("/image/:image", routes.get_image);
    app.get("/follow", routes.get_follow);
    app.get("/timeline", routes.get_timeline);

    app.post("/signup", routes.post_signup);
    app.post("/icon", routes.post_icon);
    app.post("/entry", routes.post_entry);
    app.post("/entry/:id", routes.post_entry_id);
    app.post("/follow", routes.post_follow);
    app.post("/unfollow", routes.post_unfollow);

    http.createServer(app).listen(app.get("port"), function() {
        console.log("Express server listening on port " + app.get("port"));
    });
}
