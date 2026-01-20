FAILED tests/api/v1/test_push_subscriptions.py::TestSubscriptionCleanup::test_multiple_subscriptions_from_same_user_are_cleaned_up - AssertionError: Expected 1 subscription, but found 3. Old subscriptions should be ...
FAILED tests/tasks/test_deadline_notification.py::test_send_deadline_alert_emails_dry_run - assert 7 == 1
FAILED tests/tasks/test_deadline_notification.py::test_send_deadline_alert_emails_no_alerts - assert 6 == 0
FAILED tests/tasks/test_deadline_notification.py::test_send_deadline_alert_emails_with_threshold_filtering - assert 8 == 1
FAILED tests/tasks/test_deadline_notification.py::test_send_deadline_alert_emails_email_notification_disabled - assert 6 == 0
FAILED tests/tasks/test_deadline_notification.py::test_send_deadline_alert_emails_multiple_thresholds - assert 10 == 2
FAILED tests/tasks/test_deadline_notification.py::test_send_deadline_alert_emails_default_threshold - assert 7 == 1
FAILED tests/tasks/test_deadline_notification_web_push.py::test_push_sent_when_system_notification_enabled - AssertionError: メールが1件送信される
FAILED tests/tasks/test_deadline_notification_web_push.py::test_push_skipped_when_system_notification_disabled - AssertionError: メールは送信される
FAILED tests/tasks/test_deadline_notification_web_push.py::test_push_threshold_filtering - AssertionError: メールは1件（両方の利用者を含む）
FAILED tests/tasks/test_deadline_notification_web_push.py::test_push_multiple_devices - AssertionError: メールが1件送信される
FAILED tests/tasks/test_deadline_notification_web_push.py::test_push_subscription_cleanup_on_expired - AssertionError: メールが1件送信される
FAILED tests/tasks/test_deadline_notification_web_push.py::test_push_failure_does_not_affect_email - AssertionError: メールは送信される
FAILED tests/tasks/test_deadline_notification_web_push.py::test_dry_run_skips_push_sending - AssertionError: メールカウントは1（dry_runでもカウント）