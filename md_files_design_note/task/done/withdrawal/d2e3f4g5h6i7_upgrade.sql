-- ===========================================
-- Migration: d2e3f4g5h6i7_add_withdrawal_feature_tables
-- Direction: UPGRADE
-- Revises: c1d2e3f4g5h6
-- Create Date: 2025-11-26
--
-- 退会機能のためのスキーマ追加:
-- - StaffRole enumに app_admin を追加
-- - officesテーブルに論理削除カラム追加
-- - audit_logsテーブル作成 + 既存データ移行 + 旧テーブル削除
-- - approval_requestsテーブル作成 + 既存データ移行 + 旧テーブル削除
-- ===========================================

BEGIN;

-- ===========================================
-- 1. StaffRole enumに app_admin を追加
-- ===========================================
ALTER TYPE staffrole ADD VALUE IF NOT EXISTS 'app_admin';

-- ===========================================
-- 2. ApprovalResourceType enum作成
-- ===========================================
CREATE TYPE approvalresourcetype AS ENUM (
    'role_change',
    'employee_action',
    'withdrawal'
);

-- ===========================================
-- 3. officesテーブルに論理削除カラム追加
-- ===========================================
ALTER TABLE offices ADD COLUMN is_deleted BOOLEAN NOT NULL DEFAULT false;
ALTER TABLE offices ADD COLUMN deleted_at TIMESTAMP WITH TIME ZONE;
ALTER TABLE offices ADD COLUMN deleted_by UUID;

-- 外部キー制約
ALTER TABLE offices
ADD CONSTRAINT fk_offices_deleted_by_staffs
FOREIGN KEY (deleted_by) REFERENCES staffs(id) ON DELETE SET NULL;

-- インデックス
CREATE INDEX idx_offices_is_deleted ON offices (is_deleted);
COMMIT;





BEGIN;
-- ===========================================
-- 4. audit_logsテーブル作成（統合型監査ログ）
-- ===========================================
CREATE TABLE audit_logs (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    actor_id UUID,
    actor_role VARCHAR(50),
    action VARCHAR(100) NOT NULL,
    target_type VARCHAR(50) NOT NULL,
    target_id UUID,
    office_id UUID,
    ip_address VARCHAR(45),
    user_agent TEXT,
    details JSONB,
    created_at TIMESTAMP WITH TIME ZONE NOT NULL DEFAULT now(),
    is_test_data BOOLEAN NOT NULL DEFAULT false,

    CONSTRAINT fk_audit_logs_actor FOREIGN KEY (actor_id) REFERENCES staffs(id) ON DELETE SET NULL,
    CONSTRAINT fk_audit_logs_office FOREIGN KEY (office_id) REFERENCES offices(id) ON DELETE SET NULL
);

-- コメント追加
COMMENT ON COLUMN audit_logs.actor_id IS '操作実行者のスタッフID';
COMMENT ON COLUMN audit_logs.actor_role IS '実行時のロール';
COMMENT ON COLUMN audit_logs.action IS 'アクション種別: staff.deleted, office.updated, withdrawal.approved など';
COMMENT ON COLUMN audit_logs.target_type IS '対象リソースタイプ: staff, office, withdrawal_request など';
COMMENT ON COLUMN audit_logs.target_id IS '対象リソースのID';
COMMENT ON COLUMN audit_logs.office_id IS '事務所ID（横断検索用、app_adminはNULL可）';
COMMENT ON COLUMN audit_logs.ip_address IS '操作元IPアドレス（IPv6対応）';
COMMENT ON COLUMN audit_logs.user_agent IS '操作元User-Agent';
COMMENT ON COLUMN audit_logs.details IS '変更内容（old_values, new_valuesなど）';
COMMENT ON COLUMN audit_logs.is_test_data IS 'テストデータフラグ';

-- audit_logsテーブルのインデックス
CREATE INDEX idx_audit_logs_actor_id ON audit_logs (actor_id);
CREATE INDEX idx_audit_logs_action ON audit_logs (action);
CREATE INDEX idx_audit_logs_target_type ON audit_logs (target_type);
CREATE INDEX idx_audit_logs_office_id ON audit_logs (office_id);
CREATE INDEX idx_audit_logs_created_at ON audit_logs (created_at);
CREATE INDEX idx_audit_logs_is_test_data ON audit_logs (is_test_data);
CREATE INDEX idx_audit_logs_office_created ON audit_logs (office_id, created_at);
CREATE INDEX idx_audit_logs_action_created ON audit_logs (action, created_at);

-- ===========================================
-- 5. staff_audit_logs → audit_logs データ移行
-- ===========================================
INSERT INTO audit_logs (
    id,
    actor_id,
    actor_role,
    action,
    target_type,
    target_id,
    office_id,
    ip_address,
    user_agent,
    details,
    created_at,
    is_test_data
)
SELECT
    sal.id,
    sal.performed_by,                           -- actor_id
    NULL,                                       -- actor_role (取得不可)
    'staff.' || sal.action,                     -- action (例: staff.deleted)
    'staff',                                    -- target_type
    sal.staff_id,                               -- target_id
    (                                           -- office_id (スタッフの所属事務所から取得)
        SELECT os.office_id
        FROM office_staffs os
        WHERE os.staff_id = sal.staff_id
        LIMIT 1
    ),
    sal.ip_address,
    sal.user_agent,
    sal.details,
    sal.created_at,
    false                                       -- is_test_data (元テーブルにカラムなし)
FROM staff_audit_logs sal;

-- ===========================================
-- 6. office_audit_logs → audit_logs データ移行
-- ===========================================
INSERT INTO audit_logs (
    id,
    actor_id,
    actor_role,
    action,
    target_type,
    target_id,
    office_id,
    ip_address,
    user_agent,
    details,
    created_at,
    is_test_data
)
SELECT
    oal.id,
    oal.staff_id,                               -- actor_id
    NULL,                                       -- actor_role
    oal.action_type,                            -- action (例: office_info_updated)
    'office',                                   -- target_type
    oal.office_id,                              -- target_id
    oal.office_id,                              -- office_id
    NULL,                                       -- ip_address (元テーブルにカラムなし)
    NULL,                                       -- user_agent (元テーブルにカラムなし)
    CASE
        WHEN oal.details IS NOT NULL THEN oal.details::jsonb
        ELSE NULL
    END,                                        -- details (TEXT → JSONB)
    oal.created_at,
    oal.is_test_data
FROM office_audit_logs oal;

-- ===========================================
-- 7. 旧監査ログテーブル削除
-- ===========================================
DROP TABLE IF EXISTS staff_audit_logs CASCADE;
DROP TABLE IF EXISTS office_audit_logs CASCADE;
COMMIT;





BEGIN;
-- ===========================================
-- 8. approval_requestsテーブル作成（統合型承認リクエスト）
-- ===========================================
CREATE TABLE approval_requests (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    requester_staff_id UUID NOT NULL,
    office_id UUID NOT NULL,
    resource_type approvalresourcetype NOT NULL,
    status requeststatus NOT NULL DEFAULT 'pending',
    request_data JSONB,
    reviewed_by_staff_id UUID,
    reviewed_at TIMESTAMP WITH TIME ZONE,
    reviewer_notes TEXT,
    execution_result JSONB,
    created_at TIMESTAMP WITH TIME ZONE NOT NULL DEFAULT now(),
    updated_at TIMESTAMP WITH TIME ZONE NOT NULL DEFAULT now(),
    is_test_data BOOLEAN NOT NULL DEFAULT false,

    CONSTRAINT fk_approval_requests_requester FOREIGN KEY (requester_staff_id) REFERENCES staffs(id) ON DELETE CASCADE,
    CONSTRAINT fk_approval_requests_office FOREIGN KEY (office_id) REFERENCES offices(id) ON DELETE CASCADE,
    CONSTRAINT fk_approval_requests_reviewer FOREIGN KEY (reviewed_by_staff_id) REFERENCES staffs(id) ON DELETE SET NULL
);

-- コメント追加
COMMENT ON COLUMN approval_requests.requester_staff_id IS 'リクエスト作成者のスタッフID';
COMMENT ON COLUMN approval_requests.office_id IS '対象事務所ID';
COMMENT ON COLUMN approval_requests.resource_type IS 'リクエスト種別';
COMMENT ON COLUMN approval_requests.status IS 'ステータス';
COMMENT ON COLUMN approval_requests.request_data IS 'リクエスト固有のデータ';
COMMENT ON COLUMN approval_requests.reviewed_by_staff_id IS '承認/却下したスタッフID';
COMMENT ON COLUMN approval_requests.reviewed_at IS '承認/却下日時';
COMMENT ON COLUMN approval_requests.reviewer_notes IS '承認者のメモ';
COMMENT ON COLUMN approval_requests.execution_result IS '実行結果';
COMMENT ON COLUMN approval_requests.is_test_data IS 'テストデータフラグ';

-- approval_requestsテーブルのインデックス
CREATE INDEX idx_approval_requests_requester ON approval_requests (requester_staff_id);
CREATE INDEX idx_approval_requests_office ON approval_requests (office_id);
CREATE INDEX idx_approval_requests_resource_type ON approval_requests (resource_type);
CREATE INDEX idx_approval_requests_status ON approval_requests (status);
CREATE INDEX idx_approval_requests_created_at ON approval_requests (created_at);
CREATE INDEX idx_approval_requests_is_test_data ON approval_requests (is_test_data);
CREATE INDEX idx_approval_requests_status_type ON approval_requests (status, resource_type);
CREATE INDEX idx_approval_requests_office_status ON approval_requests (office_id, status);

-- ===========================================
-- 9. role_change_requests → approval_requests データ移行
-- ===========================================
INSERT INTO approval_requests (
    id,
    requester_staff_id,
    office_id,
    resource_type,
    status,
    request_data,
    reviewed_by_staff_id,
    reviewed_at,
    reviewer_notes,
    execution_result,
    created_at,
    updated_at,
    is_test_data
)
SELECT
    rcr.id,
    rcr.requester_staff_id,
    rcr.office_id,
    'role_change'::approvalresourcetype,
    rcr.status,
    jsonb_build_object(
        'from_role', rcr.from_role::text,
        'requested_role', rcr.requested_role::text,
        'request_notes', rcr.request_notes
    ),
    rcr.reviewed_by_staff_id,
    rcr.reviewed_at,
    rcr.reviewer_notes,
    NULL,                                       -- execution_result (元テーブルにカラムなし)
    rcr.created_at,
    rcr.updated_at,
    rcr.is_test_data
FROM role_change_requests rcr;

-- ===========================================
-- 10. employee_action_requests → approval_requests データ移行
-- ===========================================
INSERT INTO approval_requests (
    id,
    requester_staff_id,
    office_id,
    resource_type,
    status,
    request_data,
    reviewed_by_staff_id,
    reviewed_at,
    reviewer_notes,
    execution_result,
    created_at,
    updated_at,
    is_test_data
)
SELECT
    ear.id,
    ear.requester_staff_id,
    ear.office_id,
    'employee_action'::approvalresourcetype,
    ear.status,
    jsonb_build_object(
        'resource_type', ear.resource_type::text,
        'action_type', ear.action_type::text,
        'resource_id', ear.resource_id::text,
        'original_request_data', ear.request_data
    ),
    ear.approved_by_staff_id,
    ear.approved_at,
    ear.approver_notes,
    ear.execution_result,
    ear.created_at,
    ear.updated_at,
    ear.is_test_data
FROM employee_action_requests ear;

-- ===========================================
-- 11. 旧承認リクエストテーブル削除
-- ===========================================
DROP TABLE IF EXISTS role_change_requests CASCADE;
DROP TABLE IF EXISTS employee_action_requests CASCADE;

-- ===========================================
-- Alembicバージョン更新
-- ===========================================
UPDATE alembic_version SET version_num = 'd2e3f4g5h6i7' WHERE version_num = 'c1d2e3f4g5h6';

COMMIT;
