FAILED tests/api/v1/test_messages_api.py::TestPersonalMessageAPI::test_send_personal_message_success - assert 403 == 201
FAILED tests/api/v1/test_messages_api.py::TestPersonalMessageAPI::test_send_personal_message_to_multiple_recipients - assert 403 == 201
FAILED tests/api/v1/test_messages_api.py::TestPersonalMessageAPI::test_send_personal_message_validation_error - assert 403 == 422
FAILED tests/api/v1/test_messages_api.py::TestPersonalMessageAPI::test_send_personal_message_empty_title - assert 403 == 422
FAILED tests/api/v1/test_messages_api.py::TestPersonalMessageAPI::test_send_personal_message_to_nonexistent_recipient - assert 403 == 400
FAILED tests/api/v1/test_messages_api.py::TestPersonalMessageAPI::test_send_personal_message_to_locked_account - assert 403 == 400
FAILED tests/api/v1/test_messages_api.py::TestMarkAsReadAPI::test_mark_message_as_read - assert 403 == 200
FAILED tests/api/v1/test_messages_api.py::TestMarkAsReadAPI::test_mark_other_user_message_as_read_forbidden - assert 403 == 404
FAILED tests/api/v1/test_messages_api.py::TestMarkAsReadAPI::test_mark_nonexistent_message_as_read - assert 403 == 404
FAILED tests/api/v1/test_messages_api.py::TestMarkAsReadAPI::test_read_at_has_timezone_info - assert 403 == 200
FAILED tests/api/v1/test_messages_api.py::TestAnnouncementAPI::test_send_announcement_as_owner - assert 403 == 201
FAILED tests/api/v1/test_messages_api.py::TestAnnouncementAPI::test_send_announcement_as_admin - assert 403 == 201
FAILED tests/api/v1/test_messages_api.py::TestAnnouncementAPI::test_send_announcement_empty_title - assert 403 == 422
FAILED tests/api/v1/test_messages_api.py::TestMarkAllAsReadAPI::test_mark_all_as_read - assert 403 == 200
FAILED tests/api/v1/test_messages_api.py::TestMarkAllAsReadAPI::test_mark_all_as_read_with_zero_unread - assert 403 == 200
FAILED tests/crud/test_crud_calendar_event.py::test_create_calendar_event_for_renewal_deadline - sqlalchemy.exc.OperationalError: (psycopg.OperationalError) consuming input failed: SSL SYSCALL error: EOF detected
FAILED tests/crud/test_crud_calendar_event.py::test_duplicate_prevention_for_cycle_event_type - sqlalchemy.exc.OperationalError: (psycopg.OperationalError) consuming input failed: SSL SYSCALL error: EOF detected
FAILED tests/crud/test_message_limit.py::TestMessageLimit::test_message_count_under_limit - TypeError: CRUDMessage.create_personal_message() got an unexpected keyword argument 'sender_staff_id'
FAILED tests/crud/test_message_limit.py::TestMessageLimit::test_message_count_at_limit - TypeError: CRUDMessage.create_personal_message() got an unexpected keyword argument 'sender_staff_id'
FAILED tests/crud/test_message_limit.py::TestMessageLimit::test_message_count_over_limit - TypeError: CRUDMessage.create_personal_message() got an unexpected keyword argument 'sender_staff_id'
FAILED tests/crud/test_message_limit.py::TestMessageLimit::test_test_data_messages_not_counted_in_limit - TypeError: 'body' is an invalid keyword argument for Message
FAILED tests/schemas/test_message_schema.py::test_message_inbox_item_valid - AttributeError: 'MessageInboxItem' object has no attribute 'sender_name'
FAILED tests/services/test_employee_action_service.py::test_approve_create_request_executes_action - sqlalchemy.exc.OperationalError: (psycopg.errors.DeadlockDetected) deadlock detected
FAILED tests/services/test_employee_action_service.py::test_notification_includes_support_plan_status_step_type_variations - sqlalchemy.exc.IntegrityError: (psycopg.errors.ForeignKeyViolation) insert or update on table "notices" violates foreign key constra...
FAILED tests/services/test_employee_action_service.py::test_create_request_sends_notifications_to_both_requester_and_approvers - sqlalchemy.exc.IntegrityError: (psycopg.errors.ForeignKeyViolation) insert or update on table "notices" violates foreign key constra...
FAILED tests/utils/test_safe_cleanup_with_flag.py::TestSafeTestDataCleanupWithFlag::test_no_production_data_deleted - AssertionError: is_test_data=False のデータは削除されてはいけません