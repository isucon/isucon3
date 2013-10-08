from __future__ import with_statement

try:
    import MySQLdb
    from MySQLdb.cursors import DictCursor
except ImportError:
    import pymysql as MySQLdb
    from pymysql.cursors import DictCursor

from flask import (
    Flask, request, redirect, session, url_for, abort,
    render_template, _app_ctx_stack, Response,
    after_this_request,
)

import memcache
from flask_memcache_session import Session
from werkzeug.contrib.fixers import ProxyFix

import json, os, hashlib, tempfile, subprocess

config = {}

app = Flask(__name__, static_url_path='')
app.cache = memcache.Client(['localhost:11211'], debug=0)
app.session_interface = Session()
app.session_cookie_name = "isucon_session"
app.wsgi_app = ProxyFix(app.wsgi_app)

def load_config():
    global config
    print("Loading configuration")
    env = os.environ.get('ISUCON_ENV') or 'local'
    with open('../config/' + env + '.json') as fp:
        config = json.load(fp)

def connect_db():
    global config
    host = config['database']['host']
    port = config['database']['port']
    username = config['database']['username']
    password = config['database']['password']
    dbname   = config['database']['dbname']
    db = MySQLdb.connect(host=host, port=port, db=dbname, user=username, passwd=password, cursorclass=DictCursor, charset="utf8")
    return db


def get_user():
    user_id = session.get('user_id')
    user = None
    if user_id:
        cur = get_db().cursor()
        cur.execute("SELECT * FROM users WHERE id=%s", user_id)
        user = cur.fetchone()
        cur.close()
    if user:
        @after_this_request
        def add_header(response):
            response.headers['Cache-Control'] = 'private'
            return response

    return user

def anti_csrf():
    if request.form['sid'] != session['token']:
        abort(400)


def require_user(user):
    if not user:
        redirect(url_for("top_page"))
        abort()


def gen_markdown(md):
    temp = tempfile.NamedTemporaryFile()
    temp.write(bytes(md, 'UTF-8'))
    temp.flush()
    html = subprocess.getoutput("../bin/markdown %s" % temp.name)
    temp.close()
    return html

def get_db():
    top = _app_ctx_stack.top
    if not hasattr(top, 'db'):
        top.db = connect_db()
    return top.db


@app.teardown_appcontext
def close_db_connection(exception):
    top = _app_ctx_stack.top
    if hasattr(top, 'db'):
        top.db.close()


@app.route("/")
def top_page():
    user = get_user()

    cur = get_db().cursor()
    cur.execute('SELECT count(*) AS c FROM memos WHERE is_private=0')
    total = cur.fetchone()['c']

    cur.execute("SELECT * FROM memos WHERE is_private=0 ORDER BY created_at DESC, id DESC LIMIT 100")
    memos = cur.fetchall()
    for memo in memos:
        cur.execute('SELECT username FROM users WHERE id=%s', memo["user"])
        memo['username'] = cur.fetchone()['username']

    cur.close()

    return render_template(
        'index.html',
        total=total,
        memos=memos,
        page=0,
        user=user
    )

@app.route("/recent/<int:page>")
def recent(page):
    user = get_user()

    cur = get_db().cursor()
    cur.execute('SELECT count(*) AS c FROM memos WHERE is_private=0')
    total = cur.fetchone()['c']

    cur.execute("SELECT * FROM memos WHERE is_private=0 ORDER BY created_at DESC, id DESC LIMIT 100 OFFSET " + str(page * 100))
    memos = cur.fetchall()
    if len(memos) == 0:
        abort(404)

    for memo in memos:
        cur.execute('SELECT username FROM users WHERE id=%s', memo["user"])
        memo['username'] = cur.fetchone()['username']

    cur.close()

    return render_template(
        'index.html',
        total=total,
        memos=memos,
        page=page,
        user=user
    )


@app.route("/mypage")
def mypage():
    user  = get_user()
    require_user(user)

    cur = get_db().cursor()
    cur.execute('SELECT id, content, is_private, created_at, updated_at FROM memos WHERE user=%s ORDER BY created_at DESC', user["id"])
    memos = cur.fetchall()
    cur.close()

    return render_template(
        'mypage.html',
        user=user,
        memos=memos,
    )

@app.route("/signin", methods=['GET','HEAD'])
def signin():
    user = get_user()
    return render_template('signin.html', user=user)


@app.route("/signin", methods=['POST'])
def signin_post():

    db  = get_db()
    cur = db.cursor()
    username = request.form['username']
    password = request.form['password']
    cur.execute('SELECT id, username, password, salt FROM users WHERE username=%s', username)
    user = cur.fetchone()
    if user and user["password"] == hashlib.sha256(bytes(user["salt"] + password, 'UTF-8')).hexdigest():
        session["user_id"] = user["id"]
        session["token"] = hashlib.sha256(os.urandom(40)).hexdigest()
        cur.execute("UPDATE users SET last_access=now() WHERE id=%s", user["id"])
        cur.close()
        db.commit()
        return redirect(url_for("mypage"))
    else:
        return render_template('signin.html', user=None)


@app.route("/signout", methods=['POST'])
def signout():
    anti_csrf()
    session.clear()

    @after_this_request
    def remove_cookie(response):
        response.set_cookie(app.session_cookie_name, "", expires=0)
        return response

    return redirect(url_for("top_page"))

@app.route("/memo/<int:memo_id>")
def memo(memo_id):
    user = get_user()

    cur  = get_db().cursor()
    cur.execute('SELECT id, user, content, is_private, created_at, updated_at FROM memos WHERE id=%s', memo_id)
    memo = cur.fetchone()
    if not memo:
        abort(404)

    if memo["is_private"] == 1:
        if not user or user["id"] != memo["user"]:
            abort(404)

    cur.execute('SELECT username FROM users WHERE id=%s', memo["user"])
    memo["username"] = cur.fetchone()["username"]
    memo["content_html"] = gen_markdown(memo["content"])
    if user and user["id"] == memo["user"]:
        cond = ""
    else:
        cond = "AND is_private=0"
    memos = []
    older = None
    newer = None
    cur.execute("SELECT * FROM memos WHERE user=%s " + cond + " ORDER BY created_at", memo["user"])
    memos = cur.fetchall()
    for i in range(len(memos)):
        if memos[i]["id"] == memo["id"]:
            if i > 0:
                older = memos[i - 1]
            if i < len(memos) - 1:
                newer = memos[i + 1]
    cur.close()

    return render_template(
        "memo.html",
        user=user,
        memo=memo,
        older=older,
        newer=newer,
    )

@app.route("/memo", methods=['POST'])
def memo_post():
    user = get_user()
    require_user(user)
    anti_csrf()

    db  = get_db()
    cur = db.cursor()
    cur.execute(
        "INSERT INTO memos (user, content, is_private, created_at) VALUES (%s, %s, %s, now())",
        ( user["id"],
          request.form["content"],
          int(request.form.get("is_private") or 0)
        )
    )
    memo_id = db.insert_id()
    cur.close()
    db.commit()

    return redirect(url_for('memo', memo_id=memo_id))


if __name__ == "__main__":
    load_config()
    port = int(os.environ.get("PORT", '5000'))
    app.run(debug=1, host='0.0.0.0', port=port)
else:
    load_config()
