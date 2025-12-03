-- ===========================================
-- Migration: audit_logs テーブル統合
-- Direction: DOWNGRADE
-- Create Date: 2025-11-26
--
-- audit_logsテーブルを元の状態に戻し、
-- staff_audit_logs, office_audit_logs を復元
-- ===========================================

BEGIN;

-- ===========================================
-- 1. staff_audit_logs テーブル再作成
-- ===========================================
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

-- ===========================================
-- 2. office_audit_logs テーブル再作成
-- ===========================================
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

-- ===========================================
-- 3. audit_logs → staff_audit_logs データ移行
-- ===========================================
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
    al.staff_id,                                -- performed_by = 操作実行者
    al.ip_address,
    al.user_agent,
    al.details,
    al.timestamp
FROM audit_logs al
WHERE al.target_type = 'staff'
  AND al.action LIKE 'staff.%'
  AND al.target_id IS NOT NULL
  AND al.staff_id IS NOT NULL;

-- ===========================================
-- 4. audit_logs → office_audit_logs データ移行
-- ===========================================
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
    al.staff_id,
    al.action,
    al.details::text,                           -- JSONB → TEXT
    al.timestamp,
    al.is_test_data
FROM audit_logs al
WHERE al.target_type = 'office'
  AND al.office_id IS NOT NULL;

-- ===========================================
-- 5. audit_logsから移行済みデータを削除
-- ===========================================
DELETE FROM audit_logs
WHERE target_type IN ('staff', 'office')
  AND action LIKE 'staff.%'
  OR target_type = 'office';

-- ===========================================
-- 6. audit_logsテーブルから追加カラム削除
-- ===========================================

-- インデックス削除
DROP INDEX IF EXISTS idx_audit_logs_action_timestamp;
DROP INDEX IF EXISTS idx_audit_logs_office_timestamp;
DROP INDEX IF EXISTS idx_audit_logs_timestamp;
DROP INDEX IF EXISTS idx_audit_logs_is_test_data;
DROP INDEX IF EXISTS idx_audit_logs_office_id;
DROP INDEX IF EXISTS idx_audit_logs_target_type;

-- 外部キー制約削除
ALTER TABLE audit_logs DROP CONSTRAINT IF EXISTS fk_audit_logs_office;

-- カラム削除
ALTER TABLE audit_logs DROP COLUMN IF EXISTS is_test_data;
ALTER TABLE audit_logs DROP COLUMN IF EXISTS details;
ALTER TABLE audit_logs DROP COLUMN IF EXISTS office_id;
ALTER TABLE audit_logs DROP COLUMN IF EXISTS target_id;
ALTER TABLE audit_logs DROP COLUMN IF EXISTS target_type;
ALTER TABLE audit_logs DROP COLUMN IF EXISTS actor_role;

-- ===========================================
-- 7. 既存データのdetails → old_value/new_value 復元
--    （注意: 完全な復元は不可能な場合あり）
-- ===========================================
-- 既存のold_value/new_valueカラムは維持されているため、
-- 特別な処理は不要

COMMIT;
