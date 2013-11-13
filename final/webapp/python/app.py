from __future__ import with_statement

try:
    import MySQLdb
    from MySQLdb.cursors import DictCursor
except ImportError:
    import pymysql as MySQLdb
    from pymysql.cursors import DictCursor

from flask import (
    Flask, request, redirect, url_for, abort, jsonify,
    _app_ctx_stack, Response,
    after_this_request,
)

import json, os, hashlib, tempfile, subprocess, re, math, shutil, uuid, time

config = {}

app = Flask(__name__, static_url_path='')

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

def url(action, **params):
    path = url_for(action, **params)

    return '%s://%s%s%s' % (request.scheme, request.host, request.script_root, path)

def get_user():
    api_key = request.headers.get('X_API_KEY') or request.cookies.get('api_key')
    user    = None

    if api_key:
        with get_db() as cur:
            cur.execute("SELECT * FROM users WHERE api_key = %s", api_key)
            user = cur.fetchone()

    return user

def require_user(user):
    if not user:
        abort(400)

def convert(orig, ext, w, h):
    with tempfile.NamedTemporaryFile() as temp:
        newfile = temp.name + '.' + ext
        subprocess.check_call(['convert', '-geometry', '%dx%d' % (w, h), orig, newfile])
        with open(newfile, 'rb') as newfh:
            data = newfh.read()
        os.unlink(newfile)
    return data

def crop_square(orig, ext):
    identity = subprocess.getoutput('identify %s' % orig)
    (w, h)   = [int(x) for x in re.split(' +', identity)[2].split('x')]

    if w > h:
        pixels = h
        crop_x = math.floor((w - pixels) / 2)
        crop_y = 0
    elif w < h:
        pixels = w
        crop_x = 0
        crop_y = math.floor((h - pixels) / 2)
    else:
        pixels = w
        crop_x = 0
        crop_y = 0

    with tempfile.NamedTemporaryFile() as temp:
        newfile = temp.name + '.' + ext
        subprocess.check_call(['convert', '-crop', '%sx%s+%s+%s' % (pixels, pixels, crop_x, crop_y), orig, newfile])
    return newfile

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


TIMEOUT  = 30
INTERVAL = 2

ICON_S  =  32
ICON_M  =  64
ICON_L  = 128
IMAGE_S = 128
IMAGE_M = 256
IMAGE_L = None


@app.route('/')
def top_page():
    with open('static/index.html') as f:
        content = f.read()
    return content

@app.route('/signup', methods=['POST'])
def signup_post():
    name = request.form['name']
    if not re.search('\A[0-9a-zA-Z_]{2,16}\Z', name):
        abort(400)

    api_key = hashlib.sha256(uuid.uuid1().bytes).hexdigest()
    with get_db() as cur:
        cur.execute(
            'INSERT INTO users (name, api_key, icon) VALUES (%s, %s, %s)',
            (name, api_key, 'default')
        )
        id = cur.connection.insert_id()
        cur.execute('SELECT * FROM users WHERE id=%s', id)
        user = cur.fetchone()

    return jsonify({
        'id':      user['id'],
        'name':    user['name'],
        'icon':    url('icon', icon=user['icon']),
        'api_key': user['api_key'],
    })

@app.route('/me')
def me():
    user = get_user()
    require_user(user)

    return jsonify({
        'id':   user['id'],
        'name': user['name'],
        'icon': url('icon', icon=user['icon']),
    })

@app.route('/icon/<icon>')
def icon(icon):
    global config
    user = get_user()

    size = request.args.get('size') or 's'
    dir  = config['data_dir']
    file = '%s/icon/%s.png' % (dir, icon)
    if not os.path.exists(file):
        abort(404)

    if size == 's':
        w = ICON_S
    elif size == 'm':
        w = ICON_M
    elif size == 'l':
        w = ICON_L
    else:
        w = ICON_S
    h = w

    data = convert(file, 'png', w, h)
    return Response(
        response=data,
        content_type='image/png'
    )

@app.route('/icon', methods=['POST'])
def icon_post():
    global config
    user = get_user()
    require_user(user)

    upload = request.files['image']
    if not upload:
        abort(400)
    if not re.search('^image/(jpe?g|png)$', upload.content_type):
        abort(400)

    icon = hashlib.sha256(uuid.uuid1().bytes).hexdigest()
    dir  = config['data_dir']
    with tempfile.NamedTemporaryFile() as temp:
        temp.write(upload.stream.read())
        temp.flush()
        file = crop_square(temp.name, 'png')
    shutil.move(file, '%s/icon/%s.png' % (dir, icon)) or abort(500)

    with get_db() as cur:
        cur.execute(
            'UPDATE users SET icon=%s WHERE id=%s',
            (icon, user['id'])
        )

    return jsonify({
        'icon': url('icon', icon=icon)
    })

@app.route('/entry', methods=['POST'])
def entry_post():
    global config
    user = get_user()
    require_user(user)

    upload = request.files['image']
    if not upload:
        abort(400)
    if not re.search('^image/jpe?g$', upload.content_type):
        abort(400)

    image_id = hashlib.sha256(uuid.uuid1().bytes).hexdigest()
    dir      = config['data_dir']
    upload.save(os.path.join(dir, 'image', image_id+'.jpg'))

    publish_level = request.form['publish_level']
    with get_db() as cur:
        cur.execute(
            'INSERT INTO entries (user, image, publish_level, created_at) VALUES (%s, %s, %s, NOW())',
            (user['id'], image_id, publish_level)
        )
        id = cur.connection.insert_id()
        cur.execute('SELECT * FROM entries WHERE id=%s', id)
        entry = cur.fetchone()

    return jsonify({
        'id':            entry['id'],
        'image':         url('image', image=entry['image']),
        'publish_level': entry['publish_level'],
        'user': {
            'id':   user['id'],
            'name': user['name'],
            'icon': url('icon', icon=user['icon']),
        },
    })

@app.route('/entry/<id>', methods=['POST'])
def entry_delete(id):
    global config
    user = get_user()
    require_user(user)

    dir = config['data_dir']
    with get_db() as cur:
        cur.execute('SELECT * FROM entries WHERE id=%s', id)
        entry = cur.fetchone()
        if not entry:
            abort(404)
        if entry['user'] != user['id'] or request.form['__method'] != 'DELETE':
            abort(400)
        cur.execute('DELETE FROM entries WHERE id=%s', id)

    return jsonify({
        'ok': True
    })

@app.route('/image/<image>')
def image(image):
    global config
    user = get_user()

    size  = request.args.get('size') or 'l'
    dir   = config['data_dir']
    with get_db() as cur:
        cur.execute('SELECT * FROM entries WHERE image=%s', image)
        entry = cur.fetchone()
        if not entry:
            abort(404)

        if entry['publish_level'] == 0:
            if user and entry['user'] == user['id']:
                # publish_level==0 はentryの所有者しか見えない
                pass
            else:
                abort(404)
        elif entry['publish_level'] == 1:
            # publish_level==1 はentryの所有者かfollowerしか見えない
            if user and entry['user'] == user['id']:
                pass
            elif user:
                cur.execute(
                    'SELECT * FROM follow_map WHERE user=%s AND target=%s',
                    (user['id'], entry['user'])
                )
                follow = cur.fetchone()
                if not follow:
                    abort(404)
            else:
                abort(404)

    if size == 's':
        w = IMAGE_S
    elif size == 'm':
        w = IMAGE_M
    elif size == 'l':
        w = IMAGE_L
    else:
        w = IMAGE_L
    h = w

    path = '%s/image/%s.jpg' % (dir, image)
    if w:
        file = crop_square(path, 'jpg')
        data = convert(file, 'jpg', w, h)
        os.unlink(file)
    else:
        with open(path, 'rb') as fh:
            data = fh.read()

    return Response(
        response=data,
        content_type='image/jpeg'
    )

def get_following():
    user = get_user()

    with get_db() as cur:
        cur.execute(
            "SELECT users.* FROM follow_map JOIN users ON (follow_map.target=users.id) WHERE follow_map.user = %s ORDER BY follow_map.created_at DESC",
            user['id']
        )
        following = cur.fetchall()

    @after_this_request
    def add_header(response):
        response.headers['Cache-Control'] = 'no-cache'
        return response

    return jsonify({
        'users': [{
            'id':   u['id'],
            'name': u['name'],
            'icon': url('icon', icon=u['icon']),
        } for u in following]
    })

@app.route('/follow', methods=['GET'])
def follow():
    user = get_user()
    require_user(user)

    return get_following()

@app.route('/follow', methods=['POST'])
def follow_post():
    user = get_user()
    require_user(user)

    with get_db() as cur:
        for target in request.form.getlist('target'):
            if target == user['id']:
                continue

            cur.execute(
                'INSERT IGNORE INTO follow_map (user, target, created_at) VALUE (%s, %s, NOW())',
                (user['id'], target)
            )

    return get_following()

@app.route('/unfollow', methods=['POST'])
def unfollow():
    user = get_user()
    require_user(user)

    with get_db() as cur:
        for target in request.form.getlist('target'):
            if target == user['id']:
                continue

            cur.execute(
                'DELETE FROM follow_map WHERE user=%s AND target=%s',
                (user['id'], target)
            )

    return get_following()

@app.route('/timeline')
def timeline():
    user = get_user()
    require_user(user)

    latest_entry = request.args.get('latest_entry')
    if latest_entry:
        sql = 'SELECT * FROM (SELECT * FROM entries WHERE (user=%s OR publish_level=2 OR (publish_level=1 AND user IN (SELECT target FROM follow_map WHERE user=%s))) AND id > %s ORDER BY id LIMIT 30) AS e ORDER BY e.id DESC'
        params = (user['id'], user['id'], latest_entry)
    else:
        sql = 'SELECT * FROM entries WHERE (user=%s OR publish_level=2 OR (publish_level=1 AND user IN (SELECT target FROM follow_map WHERE user=%s))) ORDER BY id DESC LIMIT 30'
        params = (user['id'], user['id'])

    start        = time.time()
    entries = []
    while time.time() - start < TIMEOUT:
        with get_db() as cur:
            cur.execute(sql, params)
            entries = cur.fetchall()
            if len(entries) == 0:
                time.sleep(INTERVAL)
                continue
            else:
                latest_entry = entries[0]['id']
                break

    with get_db() as cur:
        def entry_as_json(entry):
            cur.execute('SELECT * FROM users WHERE id=%s', entry['user'])
            user = cur.fetchone()
            return {
                'id':            entry['id'],
                'image':         url('image', image=entry['image']),
                'publish_level': entry['publish_level'],
                'user': {
                    'id':   user['id'],
                    'name': user['name'],
                    'icon': url('icon', icon=user['icon']),
                },
            }

        res = {
            'latest_entry': latest_entry,
            'entries': [entry_as_json(entry) for entry in entries]
        }

    @after_this_request
    def add_header(response):
        response.headers['Cache-Control'] = 'no-cache'
        return response

    return jsonify(res)


if __name__ == '__main__':
    load_config()
    port = int(os.environ.get('PORT', '5000'))
    app.run(debug=1, host='0.0.0.0', port=port)
else:
    load_config()
