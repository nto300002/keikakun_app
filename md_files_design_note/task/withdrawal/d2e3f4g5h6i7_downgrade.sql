-- ===========================================
-- Migration: d2e3f4g5h6i7_add_withdrawal_feature_tables
-- Direction: DOWNGRADE
-- Reverts to: c1d2e3f4g5h6
-- Create Date: 2025-11-26
--
-- 退会機能のスキーマを削除し、旧テーブルを復元:
-- - approval_requests → role_change_requests, employee_action_requests に分離
-- - audit_logs テーブル削除
-- - staff_audit_logs, office_audit_logs を復元
-- - officesテーブルから論理削除カラム削除
-- - enum削除
--
-- 注意: withdrawalタイプのデータは移行先がないため削除されます
-- ===========================================


-- ===========================================
-- Part 1: 旧承認リクエストテーブル復元
-- ===========================================
BEGIN;

-- role_change_requests テーブル再作成
CREATE TABLE IF NOT EXISTS role_change_requests (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    requester_staff_id UUID NOT NULL,
    office_id UUID NOT NULL,
    from_role staffrole NOT NULL,
    requested_role staffrole NOT NULL,
    status requeststatus NOT NULL DEFAULT 'pending',
    request_notes TEXT,
    reviewed_by_staff_id UUID,
    reviewed_at TIMESTAMP WITH TIME ZONE,
    reviewer_notes TEXT,
    created_at TIMESTAMP WITH TIME ZONE NOT NULL DEFAULT now(),
    updated_at TIMESTAMP WITH TIME ZONE NOT NULL DEFAULT now(),
    is_test_data BOOLEAN NOT NULL DEFAULT false,

    CONSTRAINT fk_role_change_requests_requester FOREIGN KEY (requester_staff_id) REFERENCES staffs(id) ON DELETE CASCADE,
    CONSTRAINT fk_role_change_requests_office FOREIGN KEY (office_id) REFERENCES offices(id) ON DELETE CASCADE,
    CONSTRAINT fk_role_change_requests_reviewer FOREIGN KEY (reviewed_by_staff_id) REFERENCES staffs(id) ON DELETE SET NULL
);

CREATE INDEX IF NOT EXISTS idx_role_change_requests_requester ON role_change_requests (requester_staff_id);
CREATE INDEX IF NOT EXISTS idx_role_change_requests_office ON role_change_requests (office_id);
CREATE INDEX IF NOT EXISTS idx_role_change_requests_status ON role_change_requests (status);
CREATE INDEX IF NOT EXISTS idx_role_change_requests_is_test_data ON role_change_requests (is_test_data);

-- employee_action_requests テーブル再作成
CREATE TABLE IF NOT EXISTS employee_action_requests (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    requester_staff_id UUID NOT NULL,
    office_id UUID NOT NULL,
    resource_type resourcetype NOT NULL,
    action_type actiontype NOT NULL,
    resource_id UUID,
    request_data JSONB,
    status requeststatus NOT NULL DEFAULT 'pending',
    approved_by_staff_id UUID,
    approved_at TIMESTAMP WITH TIME ZONE,
    approver_notes TEXT,
    execution_result JSONB,
    created_at TIMESTAMP WITH TIME ZONE NOT NULL DEFAULT now(),
    updated_at TIMESTAMP WITH TIME ZONE NOT NULL DEFAULT now(),
    is_test_data BOOLEAN NOT NULL DEFAULT false,

    CONSTRAINT fk_employee_action_requests_requester FOREIGN KEY (requester_staff_id) REFERENCES staffs(id) ON DELETE CASCADE,
    CONSTRAINT fk_employee_action_requests_office FOREIGN KEY (office_id) REFERENCES offices(id) ON DELETE CASCADE,
    CONSTRAINT fk_employee_action_requests_approver FOREIGN KEY (approved_by_staff_id) REFERENCES staffs(id) ON DELETE SET NULL
);

CREATE INDEX IF NOT EXISTS idx_employee_action_requests_requester ON employee_action_requests (requester_staff_id);
CREATE INDEX IF NOT EXISTS idx_employee_action_requests_office ON employee_action_requests (office_id);
CREATE INDEX IF NOT EXISTS idx_employee_action_requests_status ON employee_action_requests (status);
CREATE INDEX IF NOT EXISTS idx_employee_action_requests_is_test_data ON employee_action_requests (is_test_data);

-- approval_requests → role_change_requests データ移行
INSERT INTO role_change_requests (
    id,
    requester_staff_id,
    office_id,
    from_role,
    requested_role,
    status,
    request_notes,
    reviewed_by_staff_id,
    reviewed_at,
    reviewer_notes,
    created_at,
    updated_at,
    is_test_data
)
SELECT
    ar.id,
    ar.requester_staff_id,
    ar.office_id,
    (ar.request_data->>'from_role')::staffrole,
    (ar.request_data->>'requested_role')::staffrole,
    ar.status,
    ar.request_data->>'request_notes',
    ar.reviewed_by_staff_id,
    ar.reviewed_at,
    ar.reviewer_notes,
    ar.created_at,
    ar.updated_at,
    ar.is_test_data
FROM approval_requests ar
WHERE ar.resource_type = 'role_change';

-- approval_requests → employee_action_requests データ移行
INSERT INTO employee_action_requests (
    id,
    requester_staff_id,
    office_id,
    resource_type,
    action_type,
    resource_id,
    request_data,
    status,
    approved_by_staff_id,
    approved_at,
    approver_notes,
    execution_result,
    created_at,
    updated_at,
    is_test_data
)
SELECT
    ar.id,
    ar.requester_staff_id,
    ar.office_id,
    (ar.request_data->>'resource_type')::resourcetype,
    (ar.request_data->>'action_type')::actiontype,
    (ar.request_data->>'resource_id')::uuid,
    ar.request_data->'original_request_data',
    ar.status,
    ar.reviewed_by_staff_id,
    ar.reviewed_at,
    ar.reviewer_notes,
    ar.execution_result,
    ar.created_at,
    ar.updated_at,
    ar.is_test_data
FROM approval_requests ar
WHERE ar.resource_type = 'employee_action';

-- 注意: resource_type = 'withdrawal' のデータは移行先がないため削除されます

-- approval_requestsテーブル削除
DROP INDEX IF EXISTS idx_approval_requests_office_status;
DROP INDEX IF EXISTS idx_approval_requests_status_type;
DROP INDEX IF EXISTS idx_approval_requests_is_test_data;
DROP INDEX IF EXISTS idx_approval_requests_created_at;
DROP INDEX IF EXISTS idx_approval_requests_status;
DROP INDEX IF EXISTS idx_approval_requests_resource_type;
DROP INDEX IF EXISTS idx_approval_requests_office;
DROP INDEX IF EXISTS idx_approval_requests_requester;
DROP TABLE IF EXISTS approval_requests;

COMMIT;





-- ===========================================
-- Part 2: 旧監査ログテーブル復元
-- ===========================================
BEGIN;

-- staff_audit_logs テーブル再作成
CREATE TABLE IF NOT EXISTS staff_audit_logs (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    staff_id UUID NOT NULL,
    action VARCHAR(50) NOT NULL,
    performed_by UUID NOT NULL,
    ip_address VARCHAR(45),
    user_agent TEXT,
    details JSONB,
    created_at TIMESTAMP WITH TIME ZONE NOT NULL DEFAULT now(),

    CONSTRAINT fk_staff_audit_logs_staff FOREIGN KEY (staff_id) REFERENCES staffs(id) ON DELETE CASCADE,
    CONSTRAINT fk_staff_audit_logs_performer FOREIGN KEY (performed_by) REFERENCES staffs(id) ON DELETE SET NULL
);

CREATE INDEX IF NOT EXISTS idx_staff_audit_logs_staff_id ON staff_audit_logs (staff_id);
CREATE INDEX IF NOT EXISTS idx_staff_audit_logs_action ON staff_audit_logs (action);
CREATE INDEX IF NOT EXISTS idx_staff_audit_logs_performed_by ON staff_audit_logs (performed_by);
CREATE INDEX IF NOT EXISTS idx_staff_audit_logs_created_at ON staff_audit_logs (created_at);

COMMENT ON COLUMN staff_audit_logs.staff_id IS '対象スタッフID';
COMMENT ON COLUMN staff_audit_logs.action IS '操作種別（deleted, created, updated等）';
COMMENT ON COLUMN staff_audit_logs.performed_by IS '操作実行者のスタッフID';
COMMENT ON COLUMN staff_audit_logs.ip_address IS '操作元のIPアドレス';
COMMENT ON COLUMN staff_audit_logs.user_agent IS '操作元のUser-Agent';
COMMENT ON COLUMN staff_audit_logs.details IS '操作の詳細情報（JSON形式）';
COMMENT ON COLUMN staff_audit_logs.created_at IS '記録日時（UTC）';

-- office_audit_logs テーブル再作成
CREATE TABLE IF NOT EXISTS office_audit_logs (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    office_id UUID NOT NULL,
    staff_id UUID,
    action_type VARCHAR(100) NOT NULL,
    details TEXT,
    created_at TIMESTAMP WITH TIME ZONE NOT NULL DEFAULT now(),
    is_test_data BOOLEAN NOT NULL DEFAULT false,

    CONSTRAINT fk_office_audit_logs_office FOREIGN KEY (office_id) REFERENCES offices(id) ON DELETE CASCADE,
    CONSTRAINT fk_office_audit_logs_staff FOREIGN KEY (staff_id) REFERENCES staffs(id) ON DELETE SET NULL
);

CREATE INDEX IF NOT EXISTS idx_office_audit_logs_office_id ON office_audit_logs (office_id);
CREATE INDEX IF NOT EXISTS idx_office_audit_logs_staff_id ON office_audit_logs (staff_id);
CREATE INDEX IF NOT EXISTS idx_office_audit_logs_created_at ON office_audit_logs (created_at);
CREATE INDEX IF NOT EXISTS idx_office_audit_logs_is_test_data ON office_audit_logs (is_test_data);

COMMENT ON COLUMN office_audit_logs.action_type IS 'アクション種別: office_info_updated など';
COMMENT ON COLUMN office_audit_logs.details IS '変更内容の詳細（JSON形式）';
COMMENT ON COLUMN office_audit_logs.is_test_data IS 'テストデータフラグ';

-- audit_logs → staff_audit_logs データ移行
INSERT INTO staff_audit_logs (
    id,
    staff_id,
    action,
    performed_by,
    ip_address,
    user_agent,
    details,
    created_at
)
SELECT
    al.id,
    al.target_id,                               -- staff_id = 対象スタッフ
    REPLACE(al.action, 'staff.', ''),           -- action (staff.deleted → deleted)
    al.actor_id,                                -- performed_by = 操作実行者
    al.ip_address,
    al.user_agent,
    al.details,
    al.created_at
FROM audit_logs al
WHERE al.target_type = 'staff'
  AND al.action LIKE 'staff.%'
  AND al.target_id IS NOT NULL
  AND al.actor_id IS NOT NULL;

-- audit_logs → office_audit_logs データ移行
INSERT INTO office_audit_logs (
    id,
    office_id,
    staff_id,
    action_type,
    details,
    created_at,
    is_test_data
)
SELECT
    al.id,
    al.office_id,
    al.actor_id,
    al.action,
    al.details::text,                           -- JSONB → TEXT
    al.created_at,
    al.is_test_data
FROM audit_logs al
WHERE al.target_type = 'office'
  AND al.office_id IS NOT NULL;

-- 注意: target_type が 'staff', 'office' 以外のデータは移行先がないため削除されます

-- audit_logsテーブル削除
DROP INDEX IF EXISTS idx_audit_logs_action_created;
DROP INDEX IF EXISTS idx_audit_logs_office_created;
DROP INDEX IF EXISTS idx_audit_logs_is_test_data;
DROP INDEX IF EXISTS idx_audit_logs_created_at;
DROP INDEX IF EXISTS idx_audit_logs_office_id;
DROP INDEX IF EXISTS idx_audit_logs_target_type;
DROP INDEX IF EXISTS idx_audit_logs_action;
DROP INDEX IF EXISTS idx_audit_logs_actor_id;
DROP TABLE IF EXISTS audit_logs;

COMMIT;





-- ===========================================
-- Part 3: officesテーブル・enum復元
-- ===========================================
BEGIN;

-- officesテーブルから論理削除カラム削除
DROP INDEX IF EXISTS idx_offices_is_deleted;
ALTER TABLE offices DROP CONSTRAINT IF EXISTS fk_offices_deleted_by_staffs;
ALTER TABLE offices DROP COLUMN IF EXISTS deleted_by;
ALTER TABLE offices DROP COLUMN IF EXISTS deleted_at;
ALTER TABLE offices DROP COLUMN IF EXISTS is_deleted;

-- ApprovalResourceType enum削除
DROP TYPE IF EXISTS approvalresourcetype;

-- ===========================================
-- StaffRole enumから app_admin を削除
--
-- 注意: PostgreSQLではenumの値を直接削除できません。
-- app_adminを使用しているstaffsレコードが存在しないことを確認してから
-- 以下のコメントアウトを解除して実行してください。
-- ===========================================

/*
-- app_adminを使用しているレコードがないことを確認
-- SELECT COUNT(*) FROM staffs WHERE role = 'app_admin';

-- 1. 既存のenumを使用しているカラムを一時的にtext型に変更
ALTER TABLE staffs ALTER COLUMN role TYPE text;

-- 2. 既存のenumを削除
DROP TYPE staffrole;

-- 3. 新しいenumを作成（app_adminなし）
CREATE TYPE staffrole AS ENUM ('employee', 'manager', 'owner');

-- 4. カラムを新しいenum型に戻す
ALTER TABLE staffs ALTER COLUMN role TYPE staffrole USING role::staffrole;
*/

-- ===========================================
-- Alembicバージョン更新
-- ===========================================
UPDATE alembic_version SET version_num = 'c1d2e3f4g5h6' WHERE version_num = 'd2e3f4g5h6i7';

COMMIT;
