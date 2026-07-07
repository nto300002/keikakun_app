FAILED tests/api/v1/test_withdrawal_requests.py::test_create_withdrawal_request_as_owner - sqlalchemy.exc.ResourceClosedError: This Connection is closed
FAILED tests/api/v1/test_withdrawal_requests.py::test_create_withdrawal_request_employee_forbidden - sqlalchemy.exc.ResourceClosedError: This Connection is closed
FAILED tests/api/v1/test_withdrawal_requests.py::test_create_withdrawal_request_manager_forbidden - sqlalchemy.exc.ResourceClosedError: This Connection is closed
FAILED tests/api/v1/test_withdrawal_requests.py::test_create_withdrawal_request_empty_title - sqlalchemy.exc.ResourceClosedError: This Connection is closed
FAILED tests/api/v1/test_withdrawal_requests.py::test_create_withdrawal_request_empty_reason - sqlalchemy.exc.ResourceClosedError: This Connection is closed
FAILED tests/api/v1/test_withdrawal_requests.py::test_create_withdrawal_request_unauthenticated - sqlalchemy.exc.ResourceClosedError: This Connection is closed
FAILED tests/api/v1/test_withdrawal_requests.py::test_get_withdrawal_requests_as_app_admin - sqlalchemy.exc.ResourceClosedError: This Connection is closed
FAILED tests/api/v1/test_withdrawal_requests.py::test_get_withdrawal_requests_as_owner - sqlalchemy.exc.ResourceClosedError: This Connection is closed
FAILED tests/api/v1/test_withdrawal_requests.py::test_get_withdrawal_requests_employee_forbidden - sqlalchemy.exc.ResourceClosedError: This Connection is closed
FAILED tests/api/v1/test_withdrawal_requests.py::test_get_withdrawal_requests_manager_forbidden - sqlalchemy.exc.ResourceClosedError: This Connection is closed
FAILED tests/api/v1/test_withdrawal_requests.py::test_approve_withdrawal_request_as_app_admin - sqlalchemy.exc.ResourceClosedError: This Connection is closed
FAILED tests/api/v1/test_withdrawal_requests.py::test_approve_withdrawal_request_owner_forbidden - sqlalchemy.exc.ResourceClosedError: This Connection is closed
FAILED tests/api/v1/test_withdrawal_requests.py::test_approve_withdrawal_request_not_found - sqlalchemy.exc.ResourceClosedError: This Connection is closed
FAILED tests/api/v1/test_withdrawal_requests.py::test_approve_withdrawal_request_already_processed - sqlalchemy.exc.ResourceClosedError: This Connection is closed
FAILED tests/api/v1/test_withdrawal_requests.py::test_reject_withdrawal_request_as_app_admin - sqlalchemy.exc.ResourceClosedError: This Connection is closed
FAILED tests/api/v1/test_withdrawal_requests.py::test_reject_withdrawal_request_owner_forbidden - sqlalchemy.exc.ResourceClosedError: This Connection is closed
FAILED tests/api/v1/test_withdrawal_requests.py::test_reject_withdrawal_request_not_found - sqlalchemy.exc.ResourceClosedError: This Connection is closed
FAILED tests/test_db_cleanup.py::TestDatabaseCleanupUtility::test_delete_test_data_with_no_factory_data - sqlalchemy.exc.IntegrityError: (psycopg.errors.ForeignKeyViolation) update or delete on table "welfare_recipients" violates foreign ...
FAILED tests/utils/test_safe_cleanup_with_flag.py::TestSafeTestDataCleanupWithFlag::test_delete_only_test_data - sqlalchemy.exc.IntegrityError: (psycopg.errors.ForeignKeyViolation) update or delete on table "offices" violates foreign key constra...
FAILED tests/utils/test_safe_cleanup_with_flag.py::TestSafeTestDataCleanupWithFlag::test_cleanup_with_cascade_relationships - sqlalchemy.exc.IntegrityError: (psycopg.errors.ForeignKeyViolation) update or delete on table "offices" violates foreign key constra...
FAILED tests/utils/test_safe_cleanup_with_flag.py::TestSafeTestDataCleanupWithFlag::test_no_production_data_deleted - sqlalchemy.exc.IntegrityError: (psycopg.errors.ForeignKeyViolation) update or delete on table "offices" violates foreign key constra...
FAILED tests/utils/test_safe_cleanup_with_flag.py::TestSafeTestDataCleanupWithFlag::test_intermediate_tables_cleaned - sqlalchemy.exc.IntegrityError: (psycopg.errors.ForeignKeyViolation) update or delete on table "offices" violates foreign key constra...
FAILED tests/utils/test_safe_cleanup_with_flag.py::TestSafeTestDataCleanupWithFlag::test_delete_test_data_returns_counts - sqlalchemy.exc.IntegrityError: (psycopg.errors.ForeignKeyViolation) update or delete on table "offices" violates foreign key constra...
FAILED tests/utils/test_safe_cleanup_with_flag.py::TestSafeTestDataCleanupWithFlag::test_mixed_test_and_production_data - sqlalchemy.exc.IntegrityError: (psycopg.errors.ForeignKeyViolation) update or delete on table "offices" violates foreign key constra...
FAILED tests/test_db_cleanup.py::TestFinalDatabaseCleanupVerification::test_final_cleanup_verification_and_force_clean - sqlalchemy.exc.OperationalError: (psycopg.errors.DeadlockDetected) deadlock detected

全体テストを行うと発生したりしなかったりするエラー