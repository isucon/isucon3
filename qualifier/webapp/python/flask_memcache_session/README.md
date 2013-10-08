Flask memcache session
=========================

Store session data in memcache

Install
-------

For install you can use pip:
```
pip install flask_memcache_session
```

Usage
-------

app.py
```
from flask.ext.memcache_session import Session
from werkzeug.contrib.cache import MemcachedCache
from flask import Flask, session

app = Flask(__name__)
app.cache = MemcachedCache([host, port])
app.session_interface = Session()

@app.route('/')
def main():
    session['x'] = 'The data saved in memcached'
```

Example
-------

```
@app.before_request
def before_request():
    g.db = connect(...)
    user = g.db.query(models.Users).get(u.decode(session.get('uid', -1)))
    g.is_auth = True if user is not None else False

@app.after_request
def after_request(response):
    if session.modified and g.is_auth:
        user = g.db.query(m.Users).get(u.decode(session.get('uid')))
        g.db.add(user)
        g.db.commit()
    g.db.close()
    return response
```
