E   sqlalchemy.exc.OperationalError: (psycopg.OperationalError) connection failed: connection to server at "3.218.140.61", port 5432 failed: ERROR:  password authentication failed for user 'main_test'
E   connection to server at "3.218.140.61", port 5432 failed: ERROR:  connection is insecure (try using `sslmode=require`)
E   Multiple connection attempts failed. All failures were:
E   - host: 'ep-ancient-sky-ad8rrscr-pooler.c-2.us-east-1.aws.neon.tech', port: None, hostaddr: '54.156.15.***': connection failed: connection to server at "54.156.15.***", port 5432 failed: ERROR:  password authentication failed for user 'main_test'
E   connection to server at "54.156.15.***", port 5432 failed: ERROR:  connection is insecure (try using `sslmode=require`)
E   - host: 'ep-ancient-sky-ad8rrscr-pooler.c-2.us-east-1.aws.neon.tech', port: None, hostaddr: '44.198.216.75': connection failed: connection to server at "44.198.216.75", port 5432 failed: ERROR:  password authentication failed for user 'main_test'
E   connection to server at "44.198.216.75", port 5432 failed: ERROR:  connection is insecure (try using `sslmode=require`)
E   - host: 'ep-ancient-sky-ad8rrscr-pooler.c-2.us-east-1.aws.neon.tech', port: None, hostaddr: '3.218.140.61': connection failed: connection to server at "3.218.140.61", port 5432 failed: ERROR:  password authentication failed for user 'main_test'
E   connection to server at "3.218.140.61", port 5432 failed: ERROR:  connection is insecure (try using `sslmode=require`)
E   (Background on this error at: https://sqlalche.me/e/20/e3q8)
__________________ ERROR at setup of test_mark_notice_as_read __________________
/opt/hostedtoolcache/Python/3.12.12/x64/lib/python3.12/site-packages/sqlalchemy/engine/base.py:145: in __init__
    self._dbapi_connection = engine.raw_connection()
                             ^^^^^^^^^^^^^^^^^^^^^^^
/opt/hostedtoolcache/Python/3.12.12/x64/lib/python3.12/site-packages/sqlalchemy/engine/base.py:3297: in raw_connection
    return self.pool.connect()
           ^^^^^^^^^^^^^^^^^^^
/opt/hostedtoolcache/Python/3.12.12/x64/lib/python3.12/site-packages/sqlalchemy/pool/base.py:449: in connect
    return _ConnectionFairy._checkout(self)
           ^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^
/opt/hostedtoolcache/Python/3.12.12/x64/lib/python3.12/site-packages/sqlalchemy/pool/base.py:1264: in _checkout
    fairy = _ConnectionRecord.checkout(pool)
            ^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^
/opt/hostedtoolcache/Python/3.12.12/x64/lib/python3.12/site-packages/sqlalchemy/pool/base.py:713: in checkout
    rec = pool._do_get()
          ^^^^^^^^^^^^^^
/opt/hostedtoolcache/Python/3.12.12/x64/lib/python3.12/site-packages/sqlalchemy/pool/impl.py:179: in _do_get
    with util.safe_reraise():
         ^^^^^^^^^^^^^^^^^^^
/opt/hostedtoolcache/Python/3.12.12/x64/lib/python3.12/site-packages/sqlalchemy/util/langhelpers.py:224: in __exit__
    raise exc_value.with_traceback(exc_tb)
/opt/hostedtoolcache/Python/3.12.12/x64/lib/python3.12/site-packages/sqlalchemy/pool/impl.py:177: in _do_get
    return self._create_connection()
           ^^^^^^^^^^^^^^^^^^^^^^^^^
/opt/hostedtoolcache/Python/3.12.12/x64/lib/python3.12/site-packages/sqlalchemy/pool/base.py:390: in _create_connection
    return _ConnectionRecord(self)
           ^^^^^^^^^^^^^^^^^^^^^^^
/opt/hostedtoolcache/Python/3.12.12/x64/lib/python3.12/site-packages/sqlalchemy/pool/base.py:675: in __init__
    self.__connect()
/opt/hostedtoolcache/Python/3.12.12/x64/lib/python3.12/site-packages/sqlalchemy/pool/base.py:901: in __connect
    with util.safe_reraise():
         ^^^^^^^^^^^^^^^^^^^
/opt/hostedtoolcache/Python/3.12.12/x64/lib/python3.12/site-packages/sqlalchemy/util/langhelpers.py:224: in __exit__
    raise exc_value.with_traceback(exc_tb)
/opt/hostedtoolcache/Python/3.12.12/x64/lib/python3.12/site-packages/sqlalchemy/pool/base.py:897: in __connect
    self.dbapi_connection = connection = pool._invoke_creator(self)
                                         ^^^^^^^^^^^^^^^^^^^^^^^^^^
/opt/hostedtoolcache/Python/3.12.12/x64/lib/python3.12/site-packages/sqlalchemy/engine/create.py:646: in connect
    return dialect.connect(*cargs, **cparams)
           ^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^
/opt/hostedtoolcache/Python/3.12.12/x64/lib/python3.12/site-packages/sqlalchemy/engine/default.py:625: in connect
    return self.loaded_dbapi.connect(*cargs, **cparams)  # type: ignore[no-any-return]  # NOQA: E501
           ^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^
/opt/hostedtoolcache/Python/3.12.12/x64/lib/python3.12/site-packages/sqlalchemy/dialects/postgresql/psycopg.py:733: in connect
    await_only(creator_fn(*arg, **kw))
/opt/hostedtoolcache/Python/3.12.12/x64/lib/python3.12/site-packages/sqlalchemy/util/_concurrency_py3k.py:132: in await_only
    return current.parent.switch(awaitable)  # type: ignore[no-any-return,attr-defined] # noqa: E501
           ^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^
/opt/hostedtoolcache/Python/3.12.12/x64/lib/python3.12/site-packages/sqlalchemy/util/_concurrency_py3k.py:196: in greenlet_spawn
    value = await result
            ^^^^^^^^^^^^
/opt/hostedtoolcache/Python/3.12.12/x64/lib/python3.12/site-packages/psycopg/connection_async.py:145: in connect
    raise type(last_ex)("\n".join(lines)).with_traceback(None)
E   psycopg.OperationalError: connection failed: connection to server at "3.218.140.61", port 5432 failed: ERROR:  password authentication failed for user 'main_test'
E   connection to server at "3.218.140.61", port 5432 failed: ERROR:  connection is insecure (try using `sslmode=require`)
E   Multiple connection attempts failed. All failures were:
E   - host: 'ep-ancient-sky-ad8rrscr-pooler.c-2.us-east-1.aws.neon.tech', port: None, hostaddr: '44.198.216.75': connection failed: connection to server at "44.198.216.75", port 5432 failed: ERROR:  password authentication failed for user 'main_test'
E   connection to server at "44.198.216.75", port 5432 failed: ERROR:  connection is insecure (try using `sslmode=require`)
E   - host: 'ep-ancient-sky-ad8rrscr-pooler.c-2.us-east-1.aws.neon.tech', port: None, hostaddr: '54.156.15.***': connection failed: connection to server at "54.156.15.***", port 5432 failed: ERROR:  password authentication failed for user 'main_test'
E   connection to server at "54.156.15.***", port 5432 failed: ERROR:  connection is insecure (try using `sslmode=require`)
E   - host: 'ep-ancient-sky-ad8rrscr-pooler.c-2.us-east-1.aws.neon.tech', port: None, hostaddr: '3.218.140.61': connection failed: connection to server at "3.218.140.61", port 5432 failed: ERROR:  password authentication failed for user 'main_test'
E   connection to server at "3.218.140.61", port 5432 failed: ERROR:  connection is insecure (try using `sslmode=require`)

The above exception was the direct cause of the following exception:
/opt/hostedtoolcache/Python/3.12.12/x64/lib/python3.12/site-packages/pytest_asyncio/plugin.py:458: in setup
    return super().setup()
           ^^^^^^^^^^^^^^^
/opt/hostedtoolcache/Python/3.12.12/x64/lib/python3.12/site-packages/pytest_asyncio/plugin.py:743: in pytest_fixture_setup
    hook_result = yield
                  ^^^^^
/opt/hostedtoolcache/Python/3.12.12/x64/lib/python3.12/site-packages/pytest_asyncio/plugin.py:313: in _asyncgen_fixture_wrapper
    result = runner.run(setup(), context=context)
             ^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^
/opt/hostedtoolcache/Python/3.12.12/x64/lib/python3.12/asyncio/runners.py:118: in run
    return self._loop.run_until_complete(task)
           ^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^
/opt/hostedtoolcache/Python/3.12.12/x64/lib/python3.12/asyncio/base_events.py:691: in run_until_complete
    return future.result()
           ^^^^^^^^^^^^^^^
/opt/hostedtoolcache/Python/3.12.12/x64/lib/python3.12/site-packages/pytest_asyncio/plugin.py:***9: in setup
    res = await gen_obj.__anext__()
          ^^^^^^^^^^^^^^^^^^^^^^^^^
tests/conftest.py:212: in db_session
    async with engine.connect() as connection:
               ^^^^^^^^^^^^^^^^
/opt/hostedtoolcache/Python/3.12.12/x64/lib/python3.12/site-packages/sqlalchemy/ext/asyncio/base.py:121: in __aenter__
    return await self.start(is_ctxmanager=True)
           ^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^
/opt/hostedtoolcache/Python/3.12.12/x64/lib/python3.12/site-packages/sqlalchemy/ext/asyncio/engine.py:274: in start
    await greenlet_spawn(self.sync_engine.connect)
/opt/hostedtoolcache/Python/3.12.12/x64/lib/python3.12/site-packages/sqlalchemy/util/_concurrency_py3k.py:201: in greenlet_spawn
    result = context.throw(*sys.exc_info())
             ^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^
/opt/hostedtoolcache/Python/3.12.12/x64/lib/python3.12/site-packages/sqlalchemy/engine/base.py:3273: in connect
    return self._connection_cls(self)
           ^^^^^^^^^^^^^^^^^^^^^^^^^^
/opt/hostedtoolcache/Python/3.12.12/x64/lib/python3.12/site-packages/sqlalchemy/engine/base.py:147: in __init__
    Connection._handle_dbapi_exception_noconnection(
/opt/hostedtoolcache/Python/3.12.12/x64/lib/python3.12/site-packages/sqlalchemy/engine/base.py:2436: in _handle_dbapi_exception_noconnection
    raise sqlalchemy_exception.with_traceback(exc_info[2]) from e
/opt/hostedtoolcache/Python/3.12.12/x64/lib/python3.12/site-packages/sqlalchemy/engine/base.py:145: in __init__
    self._dbapi_connection = engine.raw_connection()
                             ^^^^^^^^^^^^^^^^^^^^^^^
/opt/hostedtoolcache/Python/3.12.12/x64/lib/python3.12/site-packages/sqlalchemy/engine/base.py:3297: in raw_connection
    return self.pool.connect()
           ^^^^^^^^^^^^^^^^^^^
/opt/hostedtoolcache/Python/3.12.12/x64/lib/python3.12/site-packages/sqlalchemy/pool/base.py:449: in connect
    return _ConnectionFairy._checkout(self)
           ^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^
/opt/hostedtoolcache/Python/3.12.12/x64/lib/python3.12/site-packages/sqlalchemy/pool/base.py:1264: in _checkout
    fairy = _ConnectionRecord.checkout(pool)
            ^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^
/opt/hostedtoolcache/Python/3.12.12/x64/lib/python3.12/site-packages/sqlalchemy/pool/base.py:713: in checkout
    rec = pool._do_get()
          ^^^^^^^^^^^^^^
/opt/hostedtoolcache/Python/3.12.12/x64/lib/python3.12/site-packages/sqlalchemy/pool/impl.py:179: in _do_get
    with util.safe_reraise():
         ^^^^^^^^^^^^^^^^^^^
/opt/hostedtoolcache/Python/3.12.12/x64/lib/python3.12/site-packages/sqlalchemy/util/langhelpers.py:224: in __exit__
    raise exc_value.with_traceback(exc_tb)
/opt/hostedtoolcache/Python/3.12.12/x64/lib/python3.12/site-packages/sqlalchemy/pool/impl.py:177: in _do_get
    return self._create_connection()
           ^^^^^^^^^^^^^^^^^^^^^^^^^
/opt/hostedtoolcache/Python/3.12.12/x64/lib/python3.12/site-packages/sqlalchemy/pool/base.py:390: in _create_connection
    return _ConnectionRecord(self)
           ^^^^^^^^^^^^^^^^^^^^^^^
/opt/hostedtoolcache/Python/3.12.12/x64/lib/python3.12/site-packages/sqlalchemy/pool/base.py:675: in __init__
    self.__connect()
/opt/hostedtoolcache/Python/3.12.12/x64/lib/python3.12/site-packages/sqlalchemy/pool/base.py:901: in __connect
    with util.safe_reraise():
         ^^^^^^^^^^^^^^^^^^^
/opt/hostedtoolcache/Python/3.12.12/x64/lib/python3.12/site-packages/sqlalchemy/util/langhelpers.py:224: in __exit__
    raise exc_value.with_traceback(exc_tb)
/opt/hostedtoolcache/Python/3.12.12/x64/lib/python3.12/site-packages/sqlalchemy/pool/base.py:897: in __connect
    self.dbapi_connection = connection = pool._invoke_creator(self)
                                         ^^^^^^^^^^^^^^^^^^^^^^^^^^
/opt/hostedtoolcache/Python/3.12.12/x64/lib/python3.12/site-packages/sqlalchemy/engine/create.py:646: in connect
    return dialect.connect(*cargs, **cparams)
           ^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^
/opt/hostedtoolcache/Python/3.12.12/x64/lib/python3.12/site-packages/sqlalchemy/engine/default.py:625: in connect
    return self.loaded_dbapi.connect(*cargs, **cparams)  # type: ignore[no-any-return]  # NOQA: E501
           ^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^
/opt/hostedtoolcache/Python/3.12.12/x64/lib/python3.12/site-packages/sqlalchemy/dialects/postgresql/psycopg.py:733: in connect
    await_only(creator_fn(*arg, **kw))
/opt/hostedtoolcache/Python/3.12.12/x64/lib/python3.12/site-packages/sqlalchemy/util/_concurrency_py3k.py:132: in await_only
    return current.parent.switch(awaitable)  # type: ignore[no-any-return,attr-defined] # noqa: E501
           ^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^
/opt/hostedtoolcache/Python/3.12.12/x64/lib/python3.12/site-packages/sqlalchemy/util/_concurrency_py3k.py:196: in greenlet_spawn
    value = await result
            ^^^^^^^^^^^^
/opt/hostedtoolcache/Python/3.12.12/x64/lib/python3.12/site-packages/psycopg/connection_async.py:145: in connect
    raise type(last_ex)("\n".join(lines)).with_traceback(None)
E   sqlalchemy.exc.OperationalError: (psycopg.OperationalError) connection failed: connection to server at "3.218.140.61", port 5432 failed: ERROR:  password authentication failed for user 'main_test'
E   connection to server at "3.218.140.61", port 5432 failed: ERROR:  connection is insecure (try using `sslmode=require`)
E   Multiple connection attempts failed. All failures were:
E   - host: 'ep-ancient-sky-ad8rrscr-pooler.c-2.us-east-1.aws.neon.tech', port: N