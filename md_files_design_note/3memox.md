FAILED tests/api/v1/test_calendar.py::TestSetupCalendar::test_setup_calendar_duplicate[owner_user_with_office] - assert 500 == 400
FAILED tests/api/v1/test_calendar.py::TestSetupCalendar::test_setup_calendar_invalid_json[owner_user_with_office] - assert 'Missing required field' in "{'detail': [{'type': 'value_error', 'loc': ['body', 'service_account_json'], 'msg': 'Value er...
FAILED tests/api/v1/test_calendar.py::TestUpdateCalendar::test_update_calendar_not_found[owner_user_with_office] - assert 500 == 404
FAILED tests/api/v1/test_calendar.py::TestDeleteCalendar::test_delete_calendar_not_found[owner_user_with_office] - assert 500 == 404
FAILED tests/api/v1/test_recipients.py::test_delete_recipient - AssertionError: assert '利用者を削除しました' == 'Welfare reci... successfully'
FAILED tests/api/v1/test_staff_profile.py::test_change_password_wrong_current[test_staff_user] - assert 500 == 400
FAILED tests/api/v1/test_staff_profile.py::test_change_password_mismatch[test_staff_user] - assert 500 == 400
FAILED tests/api/v1/test_support_plans.py::test_get_support_plan_cycles_not_found - AssertionError: assert 'not found' in '利用者id a287d365-7242-43d9-a66c-8959bf33484d が見つかりません。'
FAILED tests/api/v1/test_support_plans.py::test_get_support_plan_cycles_unauthorized_office - AssertionError: assert ('permission' in 'この利用者の個別支援計画にアクセスする権限がありません。' or 'access' in 'この利用者の個...
FAILED tests/api/v1/test_welfare_recipients.py::test_delete_welfare_recipient - AssertionError: assert '利用者を削除しました' == 'Welfare reci... successfully'
FAILED tests/api/v1/test_welfare_recipients.py::test_delete_welfare_recipient_with_deliverables - AssertionError: assert '利用者を削除しました' == 'Welfare reci... successfully'
FAILED tests/api/v1/test_welfare_recipients_employee_restriction.py::test_manager_delete_welfare_recipient_direct - AssertionError: assert '利用者を削除しました' == 'Welfare reci... successfully'
FAILED tests/integration/test_employee_restriction_api.py::test_manager_cannot_approve_request_from_other_office - AssertionError: assert 'office' in '自分の事業所のリクエストのみ操作できます'
FAILED tests/schemas/test_welfare_recipient_schema.py::test_welfare_recipient_create_future_birth_day_raises_error - AssertionError: assert 'Birth date cannot be in the future' in '1 validation error for WelfareRecipientCreate\nbirth_day\n  Value...
FAILED tests/schemas/test_welfare_recipient_schema.py::test_welfare_recipient_update_future_birth_day_raises_error - AssertionError: assert 'Birth date cannot be in the future' in '1 validation error for WelfareRecipientUpdate\nbirth_day\n  Value...
FAILED tests/security/test_staff_profile_security.py::test_brute_force_protection[test_staff_user] - AssertionError: 試行1回目: パスワードエラー(400)を期待したが 500 が返されました
FAILED tests/services/test_employee_action_service.py::test_approve_create_request_executes_action - sqlalchemy.exc.IntegrityError: (psycopg.errors.ForeignKeyViolation) insert or update on table "notices" violates foreign key cons...
FAILED tests/services/test_employee_action_service.py::test_approve_update_request_executes_action - sqlalchemy.exc.OperationalError: (psycopg.errors.DeadlockDetected) deadlock detected
FAILED tests/services/test_employee_action_service.py::test_no_missing_greenlet_after_approve_action - sqlalchemy.exc.NoResultFound: No row was found when one was required
FAILED tests/services/test_employee_action_service.py::test_reject_employee_action_request_creates_notification - sqlalchemy.exc.NoResultFound: No row was found when one was required
FAILED tests/services/test_employee_action_service.py::test_notification_includes_support_plan_status_details_for_create - assert 0 > 0
FAILED tests/services/test_employee_action_service.py::test_notification_includes_support_plan_status_step_type_variations - sqlalchemy.exc.OperationalError: (psycopg.errors.DeadlockDetected) deadlock detected
FAILED tests/services/test_role_change_service.py::test_owner_approve_manager_to_owner - sqlalchemy.exc.OperationalError: (psycopg.errors.DeadlockDetected) deadlock detected
FAILED tests/services/test_role_change_service.py::test_cannot_approve_twice - sqlalchemy.exc.OperationalError: (psycopg.errors.DeadlockDetected) deadlock detected
FAILED tests/services/test_role_change_service.py::test_no_missing_greenlet_after_reject - sqlalchemy.exc.OperationalError: (psycopg.errors.DeadlockDetected) deadlock detected
FAILED tests/services/test_role_change_service.py::test_create_request_sends_notification_to_requester - sqlalchemy.exc.OperationalError: (psycopg.errors.DeadlockDetected) deadlock detected
FAILED tests/services/test_role_change_service.py::test_approve_request_updates_requester_notification_type - sqlalchemy.exc.OperationalError: (psycopg.errors.DeadlockDetected) deadlock detected
FAILED tests/test_db_cleanup.py::TestDatabaseCleanupUtility::test_delete_test_data_with_no_factory_data - sqlalchemy.exc.IntegrityError: (psycopg.errors.ForeignKeyViolation) update or delete on table "staffs" violates foreign key const...
FAILED tests/test_db_cleanup.py::TestFinalDatabaseCleanupVerification::test_final_cleanup_verification_and_force_clean - sqlalchemy.exc.OperationalError: (psycopg.errors.DeadlockDetected) deadlock detected
FAILED tests/test_db_cleanup.py::TestFinalDatabaseCleanupVerification::test_verify_all_factory_data_removed - sqlalchemy.exc.IntegrityError: (psycopg.errors.ForeignKeyViolation) update or delete on table "offices" violates foreign key cons...