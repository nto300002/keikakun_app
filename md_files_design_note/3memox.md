E   sqlalchemy.exc.IntegrityError: (psycopg.errors.UniqueViolation) duplicate key value violates unique constraint "webhook_events_event_id_key"
E   DETAIL:  Key (event_id)=(evt_test_failed) already exists.
E   [SQL: INSERT INTO webhook_events (event_id, event_type, source, billing_id, office_id, payload, status, error_message) VALUES (%(event_id)s::VARCHAR, %(event_type)s::VARCHAR, %(source)s::VARCHAR, %(billing_id)s::UUID, %(office_id)s::UUID, %(payload)s::JSONB, %(status)s::VARCHAR, %(error_message)s::VARCHAR) RETURNING webhook_events.id, webhook_events.processed_at, webhook_events.created_at]
E   [parameters: {'event_id': 'evt_test_failed', 'event_type': 'invoice.payment_failed', 'source': 'stripe', 'billing_id': None, 'office_id': None, 'payload': Jsonb(None), 'status': 'failed', 'error_message': 'Payment method declined'}]
E   (Background on this error at: https://sqlalche.me/e/20/gkpj)


FAILED tests/crud/test_crud_webhook_event.py::TestWebhookEventCRUD::test_create_failed_event - sqlalchemy.exc.IntegrityError: (psycopg.errors.UniqueViolation) duplicate key value violates unique constraint "webhook_events_event_id_key"