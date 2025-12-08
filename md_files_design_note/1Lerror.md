

## 問題
- /noticeページの "メッセージ"タブにapp-adminからの返信が全て表示されてしまう　
個別の返信は返信したStaffにのみ表示されるべき

- 未ログインユーザーへの返信が届かない

- MissingGreenlet
2025-12-08 11:42:17,555 - sqlalchemy.pool.impl.AsyncAdaptedQueuePool - ERROR - Exception terminating connection <AdaptedConnection <psycopg.AsyncConnection [IDLE] (host=ep-muddy-smoke-addzyuq6-pooler.c-2.us-east-1.aws.neon.tech user=keikakun_dev database=neondb) at 0xffff78c824b0>>
Traceback (most recent call last):
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

During handling of the above exception, another exception occurred:

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
INFO:     192.168.65.1:16885 - "POST /api/v1/admin/inquiries/d74df5d5-de4a-4d85-b64d-56816db222fe/reply HTTP/1.1" 500 Internal Server Error