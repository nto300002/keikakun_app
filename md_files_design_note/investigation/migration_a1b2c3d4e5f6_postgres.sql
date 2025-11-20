-- Migration: Add is_test_data flag to all test-related tables
-- Revision ID: a1b2c3d4e5f6
-- Revises: t5u6v7w8x9y0
-- Create Date: 2025-11-19
--
-- 目的: テストデータを識別するための is_test_data フラグを24テーブルに追加

-- ============================================================================
-- UPGRADE: is_test_data カラムとインデックスを追加
-- ============================================================================

BEGIN;
-- 1. offices
ALTER TABLE offices ADD COLUMN is_test_data BOOLEAN NOT NULL DEFAULT false;
CREATE INDEX idx_offices_is_test_data ON offices (is_test_data);
COMMENT ON COLUMN offices.is_test_data IS 'テストデータフラグ。Factory関数で生成されたデータはTrue';

-- 2. staffs
ALTER TABLE staffs ADD COLUMN is_test_data BOOLEAN NOT NULL DEFAULT false;
CREATE INDEX idx_staffs_is_test_data ON staffs (is_test_data);
COMMENT ON COLUMN staffs.is_test_data IS 'テストデータフラグ。Factory関数で生成されたデータはTrue';

-- 3. office_staffs
ALTER TABLE office_staffs ADD COLUMN is_test_data BOOLEAN NOT NULL DEFAULT false;
CREATE INDEX idx_office_staffs_is_test_data ON office_staffs (is_test_data);
COMMENT ON COLUMN office_staffs.is_test_data IS 'テストデータフラグ。Factory関数で生成されたデータはTrue';

-- 4. welfare_recipients
ALTER TABLE welfare_recipients ADD COLUMN is_test_data BOOLEAN NOT NULL DEFAULT false;
CREATE INDEX idx_welfare_recipients_is_test_data ON welfare_recipients (is_test_data);
COMMENT ON COLUMN welfare_recipients.is_test_data IS 'テストデータフラグ。Factory関数で生成されたデータはTrue';

-- 5. office_welfare_recipients
ALTER TABLE office_welfare_recipients ADD COLUMN is_test_data BOOLEAN NOT NULL DEFAULT false;
CREATE INDEX idx_office_welfare_recipients_is_test_data ON office_welfare_recipients (is_test_data);
COMMENT ON COLUMN office_welfare_recipients.is_test_data IS 'テストデータフラグ。Factory関数で生成されたデータはTrue';

-- 6. support_plan_cycles
ALTER TABLE support_plan_cycles ADD COLUMN is_test_data BOOLEAN NOT NULL DEFAULT false;
CREATE INDEX idx_support_plan_cycles_is_test_data ON support_plan_cycles (is_test_data);
COMMENT ON COLUMN support_plan_cycles.is_test_data IS 'テストデータフラグ。Factory関数で生成されたデータはTrue';

-- 7. support_plan_statuses
ALTER TABLE support_plan_statuses ADD COLUMN is_test_data BOOLEAN NOT NULL DEFAULT false;
CREATE INDEX idx_support_plan_statuses_is_test_data ON support_plan_statuses (is_test_data);
COMMENT ON COLUMN support_plan_statuses.is_test_data IS 'テストデータフラグ。Factory関数で生成されたデータはTrue';

-- 8. calendar_event_series
ALTER TABLE calendar_event_series ADD COLUMN is_test_data BOOLEAN NOT NULL DEFAULT false;
CREATE INDEX idx_calendar_event_series_is_test_data ON calendar_event_series (is_test_data);
COMMENT ON COLUMN calendar_event_series.is_test_data IS 'テストデータフラグ。Factory関数で生成されたデータはTrue';

-- 9. calendar_event_instances
ALTER TABLE calendar_event_instances ADD COLUMN is_test_data BOOLEAN NOT NULL DEFAULT false;
CREATE INDEX idx_calendar_event_instances_is_test_data ON calendar_event_instances (is_test_data);
COMMENT ON COLUMN calendar_event_instances.is_test_data IS 'テストデータフラグ。Factory関数で生成されたデータはTrue';

-- 10. notices
ALTER TABLE notices ADD COLUMN is_test_data BOOLEAN NOT NULL DEFAULT false;
CREATE INDEX idx_notices_is_test_data ON notices (is_test_data);
COMMENT ON COLUMN notices.is_test_data IS 'テストデータフラグ。Factory関数で生成されたデータはTrue';

-- 11. role_change_requests
ALTER TABLE role_change_requests ADD COLUMN is_test_data BOOLEAN NOT NULL DEFAULT false;
CREATE INDEX idx_role_change_requests_is_test_data ON role_change_requests (is_test_data);
COMMENT ON COLUMN role_change_requests.is_test_data IS 'テストデータフラグ。Factory関数で生成されたデータはTrue';

-- 12. employee_action_requests
ALTER TABLE employee_action_requests ADD COLUMN is_test_data BOOLEAN NOT NULL DEFAULT false;
CREATE INDEX idx_employee_action_requests_is_test_data ON employee_action_requests (is_test_data);
COMMENT ON COLUMN employee_action_requests.is_test_data IS 'テストデータフラグ。Factory関数で生成されたデータはTrue';

-- 13. service_recipient_details
ALTER TABLE service_recipient_details ADD COLUMN is_test_data BOOLEAN NOT NULL DEFAULT false;
CREATE INDEX idx_service_recipient_details_is_test_data ON service_recipient_details (is_test_data);
COMMENT ON COLUMN service_recipient_details.is_test_data IS 'テストデータフラグ。Factory関数で生成されたデータはTrue';

-- 14. disability_statuses
ALTER TABLE disability_statuses ADD COLUMN is_test_data BOOLEAN NOT NULL DEFAULT false;
CREATE INDEX idx_disability_statuses_is_test_data ON disability_statuses (is_test_data);
COMMENT ON COLUMN disability_statuses.is_test_data IS 'テストデータフラグ。Factory関数で生成されたデータはTrue';

-- 15. disability_details
ALTER TABLE disability_details ADD COLUMN is_test_data BOOLEAN NOT NULL DEFAULT false;
CREATE INDEX idx_disability_details_is_test_data ON disability_details (is_test_data);
COMMENT ON COLUMN disability_details.is_test_data IS 'テストデータフラグ。Factory関数で生成されたデータはTrue';

-- 16. family_of_service_recipients
ALTER TABLE family_of_service_recipients ADD COLUMN is_test_data BOOLEAN NOT NULL DEFAULT false;
CREATE INDEX idx_family_of_service_recipients_is_test_data ON family_of_service_recipients (is_test_data);
COMMENT ON COLUMN family_of_service_recipients.is_test_data IS 'テストデータフラグ。Factory関数で生成されたデータはTrue';

-- 17. medical_matters
ALTER TABLE medical_matters ADD COLUMN is_test_data BOOLEAN NOT NULL DEFAULT false;
CREATE INDEX idx_medical_matters_is_test_data ON medical_matters (is_test_data);
COMMENT ON COLUMN medical_matters.is_test_data IS 'テストデータフラグ。Factory関数で生成されたデータはTrue';

-- 18. employment_related
ALTER TABLE employment_related ADD COLUMN is_test_data BOOLEAN NOT NULL DEFAULT false;
CREATE INDEX idx_employment_related_is_test_data ON employment_related (is_test_data);
COMMENT ON COLUMN employment_related.is_test_data IS 'テストデータフラグ。Factory関数で生成されたデータはTrue';

-- 19. issue_analyses
ALTER TABLE issue_analyses ADD COLUMN is_test_data BOOLEAN NOT NULL DEFAULT false;
CREATE INDEX idx_issue_analyses_is_test_data ON issue_analyses (is_test_data);
COMMENT ON COLUMN issue_analyses.is_test_data IS 'テストデータフラグ。Factory関数で生成されたデータはTrue';

-- 20. calendar_events
ALTER TABLE calendar_events ADD COLUMN is_test_data BOOLEAN NOT NULL DEFAULT false;
CREATE INDEX idx_calendar_events_is_test_data ON calendar_events (is_test_data);
COMMENT ON COLUMN calendar_events.is_test_data IS 'テストデータフラグ。Factory関数で生成されたデータはTrue';

-- 21. plan_deliverables
ALTER TABLE plan_deliverables ADD COLUMN is_test_data BOOLEAN NOT NULL DEFAULT false;
CREATE INDEX idx_plan_deliverables_is_test_data ON plan_deliverables (is_test_data);
COMMENT ON COLUMN plan_deliverables.is_test_data IS 'テストデータフラグ。Factory関数で生成されたデータはTrue';

-- 22. emergency_contacts
ALTER TABLE emergency_contacts ADD COLUMN is_test_data BOOLEAN NOT NULL DEFAULT false;
CREATE INDEX idx_emergency_contacts_is_test_data ON emergency_contacts (is_test_data);
COMMENT ON COLUMN emergency_contacts.is_test_data IS 'テストデータフラグ。Factory関数で生成されたデータはTrue';

-- 23. welfare_services_used
ALTER TABLE welfare_services_used ADD COLUMN is_test_data BOOLEAN NOT NULL DEFAULT false;
CREATE INDEX idx_welfare_services_used_is_test_data ON welfare_services_used (is_test_data);
COMMENT ON COLUMN welfare_services_used.is_test_data IS 'テストデータフラグ。Factory関数で生成されたデータはTrue';

-- 24. history_of_hospital_visits
ALTER TABLE history_of_hospital_visits ADD COLUMN is_test_data BOOLEAN NOT NULL DEFAULT false;
CREATE INDEX idx_history_of_hospital_visits_is_test_data ON history_of_hospital_visits (is_test_data);
COMMENT ON COLUMN history_of_hospital_visits.is_test_data IS 'テストデータフラグ。Factory関数で生成されたデータはTrue';

-- Alembicのバージョン管理テーブルを更新
UPDATE alembic_version SET version_num = 'a1b2c3d4e5f6' WHERE version_num = 't5u6v7w8x9y0';

COMMIT;

-- ============================================================================
-- DOWNGRADE: is_test_data カラムとインデックスを削除
-- ============================================================================

-- BEGIN;
--
-- DROP INDEX IF EXISTS idx_history_of_hospital_visits_is_test_data;
-- ALTER TABLE history_of_hospital_visits DROP COLUMN IF EXISTS is_test_data;
--
-- DROP INDEX IF EXISTS idx_welfare_services_used_is_test_data;
-- ALTER TABLE welfare_services_used DROP COLUMN IF EXISTS is_test_data;
--
-- DROP INDEX IF EXISTS idx_emergency_contacts_is_test_data;
-- ALTER TABLE emergency_contacts DROP COLUMN IF EXISTS is_test_data;
--
-- DROP INDEX IF EXISTS idx_plan_deliverables_is_test_data;
-- ALTER TABLE plan_deliverables DROP COLUMN IF EXISTS is_test_data;
--
-- DROP INDEX IF EXISTS idx_calendar_events_is_test_data;
-- ALTER TABLE calendar_events DROP COLUMN IF EXISTS is_test_data;
--
-- DROP INDEX IF EXISTS idx_issue_analyses_is_test_data;
-- ALTER TABLE issue_analyses DROP COLUMN IF EXISTS is_test_data;
--
-- DROP INDEX IF EXISTS idx_employment_related_is_test_data;
-- ALTER TABLE employment_related DROP COLUMN IF EXISTS is_test_data;
--
-- DROP INDEX IF EXISTS idx_medical_matters_is_test_data;
-- ALTER TABLE medical_matters DROP COLUMN IF EXISTS is_test_data;
--
-- DROP INDEX IF EXISTS idx_family_of_service_recipients_is_test_data;
-- ALTER TABLE family_of_service_recipients DROP COLUMN IF EXISTS is_test_data;
--
-- DROP INDEX IF EXISTS idx_disability_details_is_test_data;
-- ALTER TABLE disability_details DROP COLUMN IF EXISTS is_test_data;
--
-- DROP INDEX IF EXISTS idx_disability_statuses_is_test_data;
-- ALTER TABLE disability_statuses DROP COLUMN IF EXISTS is_test_data;
--
-- DROP INDEX IF EXISTS idx_service_recipient_details_is_test_data;
-- ALTER TABLE service_recipient_details DROP COLUMN IF EXISTS is_test_data;
--
-- DROP INDEX IF EXISTS idx_employee_action_requests_is_test_data;
-- ALTER TABLE employee_action_requests DROP COLUMN IF EXISTS is_test_data;
--
-- DROP INDEX IF EXISTS idx_role_change_requests_is_test_data;
-- ALTER TABLE role_change_requests DROP COLUMN IF EXISTS is_test_data;
--
-- DROP INDEX IF EXISTS idx_notices_is_test_data;
-- ALTER TABLE notices DROP COLUMN IF EXISTS is_test_data;
--
-- DROP INDEX IF EXISTS idx_calendar_event_instances_is_test_data;
-- ALTER TABLE calendar_event_instances DROP COLUMN IF EXISTS is_test_data;
--
-- DROP INDEX IF EXISTS idx_calendar_event_series_is_test_data;
-- ALTER TABLE calendar_event_series DROP COLUMN IF EXISTS is_test_data;
--
-- DROP INDEX IF EXISTS idx_support_plan_statuses_is_test_data;
-- ALTER TABLE support_plan_statuses DROP COLUMN IF EXISTS is_test_data;
--
-- DROP INDEX IF EXISTS idx_support_plan_cycles_is_test_data;
-- ALTER TABLE support_plan_cycles DROP COLUMN IF EXISTS is_test_data;
--
-- DROP INDEX IF EXISTS idx_office_welfare_recipients_is_test_data;
-- ALTER TABLE office_welfare_recipients DROP COLUMN IF EXISTS is_test_data;
--
-- DROP INDEX IF EXISTS idx_welfare_recipients_is_test_data;
-- ALTER TABLE welfare_recipients DROP COLUMN IF EXISTS is_test_data;
--
-- DROP INDEX IF EXISTS idx_office_staffs_is_test_data;
-- ALTER TABLE office_staffs DROP COLUMN IF EXISTS is_test_data;
--
-- DROP INDEX IF EXISTS idx_staffs_is_test_data;
-- ALTER TABLE staffs DROP COLUMN IF EXISTS is_test_data;
--
-- DROP INDEX IF EXISTS idx_offices_is_test_data;
-- ALTER TABLE offices DROP COLUMN IF EXISTS is_test_data;
--
-- UPDATE alembic_version SET version_num = 't5u6v7w8x9y0' WHERE version_num = 'a1b2c3d4e5f6';
--
-- COMMIT;
