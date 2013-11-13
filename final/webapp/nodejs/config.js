var env = process.env.ISUCON_ENV || "local"
module.exports = require("./../config/" + env);
