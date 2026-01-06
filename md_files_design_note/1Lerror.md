INFO     sqlalchemy.engine.Engine:base.py:2701 ROLLBACK
_____ TestTrialExpirationCheck.test_early_payment_during_trial_not_updated _____
/opt/hostedtoolcache/Python/3.12.12/x64/lib/python3.12/site-packages/sqlalchemy/engine/base.py:1963: in _exec_single_context
    self.dialect.do_execute(
/opt/hostedtoolcache/Python/3.12.12/x64/lib/python3.12/site-packages/sqlalchemy/engine/default.py:943: in do_execute
    cursor.execute(statement, parameters)
/opt/hostedtoolcache/Python/3.12.12/x64/lib/python3.12/site-packages/sqlalchemy/dialects/postgresql/psycopg.py:594: in execute
    result = self.await_(self._cursor.execute(query, params, **kw))
             ^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^
/opt/hostedtoolcache/Python/3.12.12/x64/lib/python3.12/site-packages/sqlalchemy/util/_concurrency_py3k.py:132: in await_only
    return current.parent.switch(awaitable)  # type: ignore[no-any-return,attr-defined] # noqa: E501
           ^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^
/opt/hostedtoolcache/Python/3.12.12/x64/lib/python3.12/site-packages/sqlalchemy/util/_concurrency_py3k.py:196: in greenlet_spawn
    value = await result
            ^^^^^^^^^^^^
/opt/hostedtoolcache/Python/3.12.12/x64/lib/python3.12/site-packages/psycopg/cursor_async.py:117: in execute
    raise ex.with_traceback(None)
E   psycopg.errors.UniqueViolation: duplicate key value violates unique constraint "uq_billings_stripe_subscription_id"
E   DETAIL:  Key (stripe_subscription_id)=(sub_test_active) already exists.

The above exception was the direct cause of the following exception:
tests/tasks/test_billing_check.py:363: in test_early_payment_during_trial_not_updated
    await db_session.commit()
/opt/hostedtoolcache/Python/3.12.12/x64/lib/python3.12/site-packages/sqlalchemy/ext/asyncio/session.py:1014: in commit
    await greenlet_spawn(self.sync_session.commit)
/opt/hostedtoolcache/Python/3.12.12/x64/lib/python3.12/site-packages/sqlalchemy/util/_concurrency_py3k.py:203: in greenlet_spawn
    result = context.switch(value)
             ^^^^^^^^^^^^^^^^^^^^^
/opt/hostedtoolcache/Python/3.12.12/x64/lib/python3.12/site-packages/sqlalchemy/orm/session.py:2032: in commit
    trans.commit(_to_root=True)
<string>:2: in commit
    ???
/opt/hostedtoolcache/Python/3.12.12/x64/lib/python3.12/site-packages/sqlalchemy/orm/state_changes.py:139: in _go
    ret_value = fn(self, *arg, **kw)
                ^^^^^^^^^^^^^^^^^^^^
/opt/hostedtoolcache/Python/3.12.12/x64/lib/python3.12/site-packages/sqlalchemy/orm/session.py:1313: in commit
    self._prepare_impl()
<string>:2: in _prepare_impl
    ???
/opt/hostedtoolcache/Python/3.12.12/x64/lib/python3.12/site-packages/sqlalchemy/orm/state_changes.py:139: in _go
    ret_value = fn(self, *arg, **kw)
                ^^^^^^^^^^^^^^^^^^^^
/opt/hostedtoolcache/Python/3.12.12/x64/lib/python3.12/site-packages/sqlalchemy/orm/session.py:1288: in _prepare_impl
    self.session.flush()
/opt/hostedtoolcache/Python/3.12.12/x64/lib/python3.12/site-packages/sqlalchemy/orm/session.py:4345: in flush
    self._flush(objects)
/opt/hostedtoolcache/Python/3.12.12/x64/lib/python3.12/site-packages/sqlalchemy/orm/session.py:4480: in _flush
    with util.safe_reraise():
         ^^^^^^^^^^^^^^^^^^^
/opt/hostedtoolcache/Python/3.12.12/x64/lib/python3.12/site-packages/sqlalchemy/util/langhelpers.py:224: in __exit__
    raise exc_value.with_traceback(exc_tb)
/opt/hostedtoolcache/Python/3.12.12/x64/lib/python3.12/site-packages/sqlalchemy/orm/session.py:4441: in _flush
    flush_context.execute()
/opt/hostedtoolcache/Python/3.12.12/x64/lib/python3.12/site-packages/sqlalchemy/orm/unitofwork.py:466: in execute
    rec.execute(self)
/opt/hostedtoolcache/Python/3.12.12/x64/lib/python3.12/site-packages/sqlalchemy/orm/unitofwork.py:642: in execute
    util.preloaded.orm_persistence.save_obj(
/opt/hostedtoolcache/Python/3.12.12/x64/lib/python3.12/site-packages/sqlalchemy/orm/persistence.py:85: in save_obj
    _emit_update_statements(
/opt/hostedtoolcache/Python/3.12.12/x64/lib/python3.12/site-packages/sqlalchemy/orm/persistence.py:912: in _emit_update_statements
    c = connection.execute(
/opt/hostedtoolcache/Python/3.12.12/x64/lib/python3.12/site-packages/sqlalchemy/engine/base.py:1415: in execute
    return meth(
/opt/hostedtoolcache/Python/3.12.12/x64/lib/python3.12/site-packages/sqlalchemy/sql/elements.py:523: in _execute_on_connection
    return connection._execute_clauseelement(
/opt/hostedtoolcache/Python/3.12.12/x64/lib/python3.12/site-packages/sqlalchemy/engine/base.py:1637: in _execute_clauseelement
    ret = self._execute_context(
/opt/hostedtoolcache/Python/3.12.12/x64/lib/python3.12/site-packages/sqlalchemy/engine/base.py:1842: in _execute_context
    return self._exec_single_context(
/opt/hostedtoolcache/Python/3.12.12/x64/lib/python3.12/site-packages/sqlalchemy/engine/base.py:1982: in _exec_single_context
    self._handle_dbapi_exception(
/opt/hostedtoolcache/Python/3.12.12/x64/lib/python3.12/site-packages/sqlalchemy/engine/base.py:2351: in _handle_dbapi_exception
    raise sqlalchemy_exception.with_traceback(exc_info[2]) from e
/opt/hostedtoolcache/Python/3.12.12/x64/lib/python3.12/site-packages/sqlalchemy/engine/base.py:1963: in _exec_single_context
    self.dialect.do_execute(
/opt/hostedtoolcache/Python/3.12.12/x64/lib/python3.12/site-packages/sqlalchemy/engine/default.py:943: in do_execute
    cursor.execute(statement, parameters)
/opt/hostedtoolcache/Python/3.12.12/x64/lib/python3.12/site-packages/sqlalchemy/dialects/postgresql/psycopg.py:594: in execute
    result = self.await_(self._cursor.execute(query, params, **kw))
             ^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^
/opt/hostedtoolcache/Python/3.12.12/x64/lib/python3.12/site-packages/sqlalchemy/util/_concurrency_py3k.py:132: in await_only
    return current.parent.switch(awaitable)  # type: ignore[no-any-return,attr-defined] # noqa: E501
           ^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^
/opt/hostedtoolcache/Python/3.12.12/x64/lib/python3.12/site-packages/sqlalchemy/util/_concurrency_py3k.py:196: in greenlet_spawn
    value = await result
            ^^^^^^^^^^^^
/opt/hostedtoolcache/Python/3.12.12/x64/lib/python3.12/site-packages/psycopg/cursor_async.py:117: in execute
    raise ex.with_traceback(None)
E   sqlalchemy.exc.IntegrityError: (psycopg.errors.UniqueViolation) duplicate key value violates unique constraint "uq_billings_stripe_subscription_id"
E   DETAIL:  Key (stripe_subscription_id)=(sub_test_active) already exists.
E   [SQL: UPDATE billings SET stripe_subscription_id=%(stripe_subscription_id)s::VARCHAR, billing_status=%(billing_status)s, trial_end_date=%(trial_end_date)s::TIMESTAMP WITH TIME ZONE, updated_at=%(updated_at)s::TIMESTAMP WITH TIME ZONE WHERE billings.id = %(billings_id)s::UUID]
E   [parameters: ***'stripe_subscription_id': 'sub_test_active', 'billing_status': 'early_payment', 'trial_end_date': datetime.datetime(2026, 2, 4, 5, 57, 41, 762321, tzinfo=datetime.timezone.utc), 'updated_at': datetime.datetime(2026, 1, 5, 5, 57, 41, 834813), 'billings_id': UUID('60011bde-2148-4427-a9cd-915cadbf8fe1')***]
E   (Background on this error at: https://sqlalche.me/e/20/gkpj)






FAILED tests/api/test_billing.py::test_webhook_customer_subscription_created - assert 503 == 200
 +  where 503 = <Response [503 Service Unavailable]>.status_code
FAILED tests/api/test_billing.py::test_webhook_idempotency_duplicate_event_skipped - assert 503 == 200
 +  where 503 = <Response [503 Service Unavailable]>.status_code
FAILED tests/api/test_billing.py::test_webhook_idempotency_different_events_both_processed - assert 503 == 200
 +  where 503 = <Response [503 Service Unavailable]>.status_code
FAILED tests/crud/test_crud_audit_log.py::TestAuditLogAdminImportantActions::test_get_admin_important_logs_pagination - AssertionError: assert False
 +  where False = <built-in method isdisjoint of set object at 0x7f6f99e5f4c0>(***UUID('***bbc23d-386a-4aa9-9d7e-eeed0a2ca12d'), UUID('4c0fd740-7fd8-4a58-9f1c-95dba4bf83dd'), UUID('6c33b015-44bf-4654-8d28-9ae661681349'), UUID('cc34baef-fd5a-4f92-b91a-4a00abc5f0a3'), UUID('d46c218c-5d87-471d-a45a-bdec8e284b9d')***)
 +    where <built-in method isdisjoint of set object at 0x7f6f99e5f4c0> = ***UUID('***bbc23d-386a-4aa9-9d7e-eeed0a2ca12d'), UUID('4c6197f0-d961-4bf7-98cb-b4e1da5fb5ff'), UUID('626f91fa-9e37-463b-b766-ff9d51624d59'), UUID('a327b0c6-dcf2-43f7-90fd-5e57f650e8cf'), UUID('b7413161-9732-4461-8642-7600789deecc')***.isdisjoint
FAILED tests/services/test_withdrawal_service.py::TestOfficeWithdrawalBillingCancellation::test_office_withdrawal_cancels_billing_with_stripe_ids - AssertionError: assert False
 +  where False = <MagicMock name='delete' id='140117417943952'>.called
FAILED tests/tasks/test_billing_check.py::TestTrialExpirationCheck::test_early_payment_during_trial_not_updated - sqlalchemy.exc.IntegrityError: (psycopg.errors.UniqueViolation) duplicate key value violates unique constraint "uq_billings_stripe_subscription_id"
DETAIL:  Key (stripe_subscription_id)=(sub_test_active) already exists.
[SQL: UPDATE billings SET stripe_subscription_id=%(stripe_subscription_id)s::VARCHAR, billing_status=%(billing_status)s, trial_end_date=%(trial_end_date)s::TIMESTAMP WITH TIME ZONE, updated_at=%(updated_at)s::TIMESTAMP WITH TIME ZONE WHERE billings.id = %(billings_id)s::UUID]
[parameters: ***'stripe_subscription_id': 'sub_test_active', 'billing_status': 'early_payment', 'trial_end_date': datetime.datetime(2026, 2, 4, 5, 57, 41, 762321, tzinfo=datetime.timezone.utc), 'updated_at': datetime.datetime(2026, 1, 5, 5, 57, 41, 834813), 'billings_id': UUID('60011bde-2148-4427-a9cd-915cadbf8fe1')***]
(Background on this error at: https://sqlalche.me/e/20/gkpj)