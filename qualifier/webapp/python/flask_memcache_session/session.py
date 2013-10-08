from flask.sessions import SessionInterface, SessionMixin
import os, binascii

class SessionData(dict, SessionMixin): pass

class Session(SessionInterface):
    session_class = SessionData

    def open_session(self, app, request):
        self.cookie_session_id = request.cookies.get(app.session_cookie_name, None)
        self.session_new = False
        if self.cookie_session_id is None:
            self.cookie_session_id = binascii.hexlify(os.urandom(40)).decode('ascii')
            self.session_new = True
        self.memcache_session_id = '@'.join(
                    [
                        request.remote_addr,
                        self.cookie_session_id
                    ]
                )
        app.logger.debug('Open session %s', self.memcache_session_id)
        session = app.cache.get(self.memcache_session_id) or {}
        app.cache.set(self.memcache_session_id, session)
        return self.session_class(session)

    def save_session(self, app, session, response):
        expires = self.get_expiration_time(app, session)
        domain = self.get_cookie_domain(app)
        path = self.get_cookie_path(app)
        httponly = self.get_cookie_httponly(app)
        secure = self.get_cookie_secure(app)
        app.cache.set(self.memcache_session_id, session)
        if self.session_new:
            response.set_cookie(app.session_cookie_name, self.cookie_session_id, path=path,
                                expires=expires, httponly=httponly,
                                secure=secure, domain=domain)
            app.logger.debug('Set session %s with %s', self.memcache_session_id, session)
