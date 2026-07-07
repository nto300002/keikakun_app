-- スタッフ削除機能のためのスキーマ追加（upgrade）
-- Revision ID: b2c3d4e5f6g7_fixed
-- Revises: a7b8c9d0e1f2
-- Create Date: 2025-11-24 14:30:00.000000

-- 1. staffsテーブルに論理削除カラムを追加
ALTER TABLE staffs ADD COLUMN IF NOT EXISTS is_deleted BOOLEAN NOT NULL DEFAULT false;
ALTER TABLE staffs ADD COLUMN IF NOT EXISTS deleted_at TIMESTAMP WITH TIME ZONE;
ALTER TABLE staffs ADD COLUMN IF NOT EXISTS deleted_by UUID;

-- 2. deleted_byの外部キー制約を追加
DO $$
BEGIN
    IF NOT EXISTS (
        SELECT 1 FROM pg_constraint WHERE conname = 'fk_staffs_deleted_by_staffs'
    ) THEN
        ALTER TABLE staffs
        ADD CONSTRAINT fk_staffs_deleted_by_staffs
        FOREIGN KEY (deleted_by) REFERENCES staffs(id);
    END IF;
END $$;

-- 3. staffsテーブルのインデックス追加
CREATE INDEX IF NOT EXISTS idx_staff_is_deleted ON staffs(is_deleted);
-- 修正: 以下の行を削除（office_idカラムはstaffsテーブルに存在しない）
-- CREATE INDEX idx_staff_office_id_is_deleted ON staffs(office_id, is_deleted);

-- 4. staff_audit_logsテーブル作成
CREATE TABLE IF NOT EXISTS staff_audit_logs (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    staff_id UUID NOT NULL,
    action VARCHAR(50) NOT NULL,
    performed_by UUID NOT NULL,
    ip_address VARCHAR(45),
    user_agent TEXT,
    details JSONB,
    created_at TIMESTAMP WITH TIME ZONE NOT NULL DEFAULT now(),
    CONSTRAINT fk_staff_audit_logs_staff_id_staffs
        FOREIGN KEY (staff_id) REFERENCES staffs(id) ON DELETE CASCADE,
    CONSTRAINT fk_staff_audit_logs_performed_by_staffs
        FOREIGN KEY (performed_by) REFERENCES staffs(id) ON DELETE SET NULL
);

-- 5. staff_audit_logsテーブルのインデックス追加
CREATE INDEX IF NOT EXISTS ix_staff_audit_logs_staff_id ON staff_audit_logs(staff_id);
CREATE INDEX IF NOT EXISTS ix_staff_audit_logs_action ON staff_audit_logs(action);
CREATE INDEX IF NOT EXISTS ix_staff_audit_logs_performed_by ON staff_audit_logs(performed_by);
CREATE INDEX IF NOT EXISTS ix_staff_audit_logs_created_at ON staff_audit_logs(created_at);

-- 完了
COMMENT ON TABLE staff_audit_logs IS 'スタッフ操作の監査ログ（削除、作成、更新等）';
COMMENT ON COLUMN staff_audit_logs.staff_id IS '対象スタッフID';
COMMENT ON COLUMN staff_audit_logs.action IS '操作種別（deleted, created, updated等）';
COMMENT ON COLUMN staff_audit_logs.performed_by IS '操作実行者のスタッフID';
COMMENT ON COLUMN staff_audit_logs.ip_address IS '操作元のIPアドレス';
COMMENT ON COLUMN staff_audit_logs.user_agent IS '操作元のUser-Agent';
COMMENT ON COLUMN staff_audit_logs.details IS '操作の詳細情報（JSON形式）';
COMMENT ON COLUMN staff_audit_logs.created_at IS '記録日時（UTC）';

COMMENT ON COLUMN staffs.is_deleted IS '論理削除フラグ';
COMMENT ON COLUMN staffs.deleted_at IS '削除日時（UTC）';
COMMENT ON COLUMN staffs.deleted_by IS '削除を実行したスタッフのID';


-- =ダウングレード処理=
-- -- 1. staff_audit_logsテーブルのインデックス削除
-- DROP INDEX IF EXISTS ix_staff_audit_logs_created_at;
-- DROP INDEX IF EXISTS ix_staff_audit_logs_performed_by;
-- DROP INDEX IF EXISTS ix_staff_audit_logs_action;
-- DROP INDEX IF EXISTS ix_staff_audit_logs_staff_id;

-- -- 2. staff_audit_logsテーブル削除
-- DROP TABLE IF EXISTS staff_audit_logs;

-- -- 3. staffsテーブルのインデックス削除
-- DROP INDEX IF EXISTS idx_staff_is_deleted;
-- -- 修正: 以下の行は削除（このインデックスは作成されていない）
-- -- DROP INDEX IF EXISTS idx_staff_office_id_is_deleted;

-- -- 4. staffsテーブルの外部キー制約削除
-- ALTER TABLE staffs DROP CONSTRAINT IF EXISTS fk_staffs_deleted_by_staffs;

-- -- 5. staffsテーブルのカラム削除
-- ALTER TABLE staffs DROP COLUMN IF EXISTS deleted_by;
-- ALTER TABLE staffs DROP COLUMN IF EXISTS deleted_at;
-- ALTER TABLE staffs DROP COLUMN IF EXISTS is_deleted;
