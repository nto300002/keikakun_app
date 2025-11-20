## 不具合1
- 管理者ページ: 個別にMFAの有効化
> MissingGreenlet
上記エラーが発生したときにお決まりの、500エラーが出ているにも関わらず更新すると結果が反映されている
遅延読み込みの影響でしょうが、トランザクション管理やリレーションシップを読み込む際にイーガーローディングを使っているか リフレッシュの使い方が正しいかなど調査　todo/refactoring/requirements.md

Request URL
http://localhost:8000/api/v1/auth/admin/staff/b703a1de-4ccf-4870-993f-14fa6567d189/mfa/enable
Request Method
POST
Status Code
500 Internal Server Error
Referrer Policy
strict-origin-when-cross-origin


Traceback (most recent call last):
  File "/usr/local/lib/python3.12/site-packages/sqlalchemy/pool/base.py", line 374, in _close_connection
    self._dialect.do_terminate(connection)
  File "/usr/local/lib/python3.12/site-packages/sqlalchemy/engine/default.py", line 709, in do_terminate
    self.do_close(dbapi_connection)
  File "/usr/local/lib/python3.12/site-packages/sqlalchemy/engine/default.py", line 712, in do_close
    dbapi_connection.close()
  File "/usr/local/lib/python3.12/site-packages/sqlalchemy/dialects/postgresql/psycopg.py", line 686, in close
    self.await_(self._connection.close())
  File "/usr/local/lib/python3.12/site-packages/sqlalchemy/util/_concurrency_py3k.py", line 123, in await_only
    raise exc.MissingGreenlet(
sqlalchemy.exc.MissingGreenlet: greenlet_spawn has not been called; can't call await_only() here. Was IO attempted in an unexpected place? (Background on this error at: https://sqlalche.me/e/20/xd2s)
INFO:     192.168.65.1:60358 - "POST /api/v1/auth/admin/staff/b703a1de-4ccf-4870-993f-14fa6567d189/mfa/enable HTTP/1.1" 500 Internal Server Error
ERROR:    Exception in ASGI application
Traceback (most recent call last):
  File "/usr/local/lib/python3.12/site-packages/uvicorn/protocols/http/h11_impl.py", line 407, in run_asgi
    result = await app(  # type: ignore[func-returns-value]
             ^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^
  File "/usr/local/lib/python3.12/site-packages/uvicorn/middleware/proxy_headers.py", line 69, in __call__
    return await self.app(scope, receive, send)
           ^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^
  File "/usr/local/lib/python3.12/site-packages/fastapi/applications.py", line 1054, in __call__
    await super().__call__(scope, receive, send)
  File "/usr/local/lib/python3.12/site-packages/starlette/applications.py", line 113, in __call__
    await self.middleware_stack(scope, receive, send)
  File "/usr/local/lib/python3.12/site-packages/starlette/middleware/errors.py", line 187, in __call__
    raise exc
  File "/usr/local/lib/python3.12/site-packages/starlette/middleware/errors.py", line 165, in __call__
    await self.app(scope, receive, _send)
  File "/usr/local/lib/python3.12/site-packages/starlette/middleware/cors.py", line 93, in __call__
    await self.simple_response(scope, receive, send, request_headers=headers)
  File "/usr/local/lib/python3.12/site-packages/starlette/middleware/cors.py", line 144, in simple_response
    await self.app(scope, receive, send)
  File "/usr/local/lib/python3.12/site-packages/starlette/middleware/exceptions.py", line 62, in __call__
    await wrap_app_handling_exceptions(self.app, conn)(scope, receive, send)
  File "/usr/local/lib/python3.12/site-packages/starlette/_exception_handler.py", line 62, in wrapped_app
    raise exc
  File "/usr/local/lib/python3.12/site-packages/starlette/_exception_handler.py", line 51, in wrapped_app
    await app(scope, receive, sender)
  File "/usr/local/lib/python3.12/site-packages/starlette/routing.py", line 715, in __call__
    await self.middleware_stack(scope, receive, send)
  File "/usr/local/lib/python3.12/site-packages/starlette/routing.py", line 735, in app
    await route.handle(scope, receive, send)
  File "/usr/local/lib/python3.12/site-packages/starlette/routing.py", line 288, in handle
    await self.app(scope, receive, send)
  File "/usr/local/lib/python3.12/site-packages/starlette/routing.py", line 76, in app
    await wrap_app_handling_exceptions(app, request)(scope, receive, send)
  File "/usr/local/lib/python3.12/site-packages/starlette/_exception_handler.py", line 62, in wrapped_app
    raise exc
  File "/usr/local/lib/python3.12/site-packages/starlette/_exception_handler.py", line 51, in wrapped_app
    await app(scope, receive, sender)
  File "/usr/local/lib/python3.12/site-packages/starlette/routing.py", line 73, in app
    response = await f(request)
               ^^^^^^^^^^^^^^^^
  File "/usr/local/lib/python3.12/site-packages/fastapi/routing.py", line 301, in app
    raw_response = await run_endpoint_function(
                   ^^^^^^^^^^^^^^^^^^^^^^^^^^^^
  File "/usr/local/lib/python3.12/site-packages/fastapi/routing.py", line 212, in run_endpoint_function
    return await dependant.call(**values)
           ^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^
  File "/app/app/api/v1/endpoints/mfa.py", line 220, in admin_enable_staff_mfa
    qr_code_uri = generate_totp_uri(target_staff.email, secret)
                                    ^^^^^^^^^^^^^^^^^^
  File "/usr/local/lib/python3.12/site-packages/sqlalchemy/orm/attributes.py", line 566, in __get__
    return self.impl.get(state, dict_)  # type: ignore[no-any-return]
           ^^^^^^^^^^^^^^^^^^^^^^^^^^^
  File "/usr/local/lib/python3.12/site-packages/sqlalchemy/orm/attributes.py", line 1086, in get
    value = self._fire_loader_callables(state, key, passive)
            ^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^
  File "/usr/local/lib/python3.12/site-packages/sqlalchemy/orm/attributes.py", line 1116, in _fire_loader_callables
    return state._load_expired(state, passive)
           ^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^
  File "/usr/local/lib/python3.12/site-packages/sqlalchemy/orm/state.py", line 803, in _load_expired
    self.manager.expired_attribute_loader(self, toload, passive)
  File "/usr/local/lib/python3.12/site-packages/sqlalchemy/orm/loading.py", line 1670, in load_scalar_attributes
    result = load_on_ident(
             ^^^^^^^^^^^^^^
  File "/usr/local/lib/python3.12/site-packages/sqlalchemy/orm/loading.py", line 509, in load_on_ident
    return load_on_pk_identity(
           ^^^^^^^^^^^^^^^^^^^^
  File "/usr/local/lib/python3.12/site-packages/sqlalchemy/orm/loading.py", line 694, in load_on_pk_identity
    session.execute(
  File "/usr/local/lib/python3.12/site-packages/sqlalchemy/orm/session.py", line 2365, in execute
    return self._execute_internal(
           ^^^^^^^^^^^^^^^^^^^^^^^
  File "/usr/local/lib/python3.12/site-packages/sqlalchemy/orm/session.py", line 2241, in _execute_internal
    conn = self._connection_for_bind(bind)
           ^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^
  File "/usr/local/lib/python3.12/site-packages/sqlalchemy/orm/session.py", line 2110, in _connection_for_bind
    return trans._connection_for_bind(engine, execution_options)
           ^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^
  File "<string>", line 2, in _connection_for_bind
  File "/usr/local/lib/python3.12/site-packages/sqlalchemy/orm/state_changes.py", line 139, in _go
    ret_value = fn(self, *arg, **kw)
                ^^^^^^^^^^^^^^^^^^^^
  File "/usr/local/lib/python3.12/site-packages/sqlalchemy/orm/session.py", line 1189, in _connection_for_bind
    conn = bind.connect()
           ^^^^^^^^^^^^^^
  File "/usr/local/lib/python3.12/site-packages/sqlalchemy/engine/base.py", line 3273, in connect
    return self._connection_cls(self)
           ^^^^^^^^^^^^^^^^^^^^^^^^^^
  File "/usr/local/lib/python3.12/site-packages/sqlalchemy/engine/base.py", line 145, in __init__
    self._dbapi_connection = engine.raw_connection()
                             ^^^^^^^^^^^^^^^^^^^^^^^
  File "/usr/local/lib/python3.12/site-packages/sqlalchemy/engine/base.py", line 3297, in raw_connection
    return self.pool.connect()
           ^^^^^^^^^^^^^^^^^^^
  File "/usr/local/lib/python3.12/site-packages/sqlalchemy/pool/base.py", line 449, in connect
    return _ConnectionFairy._checkout(self)
           ^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^
  File "/usr/local/lib/python3.12/site-packages/sqlalchemy/pool/base.py", line 1363, in _checkout
    with util.safe_reraise():
         ^^^^^^^^^^^^^^^^^^^
  File "/usr/local/lib/python3.12/site-packages/sqlalchemy/util/langhelpers.py", line 224, in __exit__
    raise exc_value.with_traceback(exc_tb)
  File "/usr/local/lib/python3.12/site-packages/sqlalchemy/pool/base.py", line 1301, in _checkout
    result = pool._dialect._do_ping_w_event(
             ^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^
  File "/usr/local/lib/python3.12/site-packages/sqlalchemy/engine/default.py", line 720, in _do_ping_w_event
    return self.do_ping(dbapi_connection)
           ^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^
  File "/usr/local/lib/python3.12/site-packages/sqlalchemy/dialects/postgresql/_psycopg_common.py", line 177, in do_ping
    dbapi_connection.autocommit = True
    ^^^^^^^^^^^^^^^^^^^^^^^^^^^
  File "/usr/local/lib/python3.12/site-packages/sqlalchemy/dialects/postgresql/psycopg.py", line 694, in autocommit
    self.set_autocommit(value)
  File "/usr/local/lib/python3.12/site-packages/sqlalchemy/dialects/postgresql/psycopg.py", line 697, in set_autocommit
    self.await_(self._connection.set_autocommit(value))
  File "/usr/local/lib/python3.12/site-packages/sqlalchemy/util/_concurrency_py3k.py", line 123, in await_only
    raise exc.MissingGreenlet(
sqlalchemy.exc.MissingGreenlet: greenlet_spawn has not been called; can't call await_only() here. Was IO attempted in an unexpected place? (Background on this error at: https://sqlalche.me/e/20/xd2s)
INFO:     192.168.65.1:56070 - "OPTIONS /api/v1/notices/unread-count HTTP/1.1" 200 OK