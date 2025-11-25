-- Migration: add office info and audit
-- Revision ID: c1d2e3f4g5h6
-- Revises: b2c3d4e5f6g7
-- Create Date: 2025-11-24 15:00:00.000000
--
-- 事務所情報変更機能のためのスキーマ追加:
-- - officesテーブルに連絡先情報カラム追加（address, phone_number, email）
-- - office_audit_logsテーブル作成（監査ログ）
-- - インデックス追加

-- ==========================================
-- UPGRADE
-- ==========================================

-- officesテーブルに連絡先情報カラムを追加
ALTER TABLE offices ADD COLUMN address VARCHAR(500);
ALTER TABLE offices ADD COLUMN phone_number VARCHAR(20);
ALTER TABLE offices ADD COLUMN email VARCHAR(255);

-- office_audit_logsテーブル作成
CREATE TABLE office_audit_logs (
    id UUID NOT NULL DEFAULT gen_random_uuid(),
    office_id UUID NOT NULL,
    staff_id UUID,
    action_type VARCHAR(100) NOT NULL,
    details TEXT,
    created_at TIMESTAMP WITH TIME ZONE NOT NULL DEFAULT now(),
    is_test_data BOOLEAN NOT NULL DEFAULT false,
    PRIMARY KEY (id),
    FOREIGN KEY (office_id) REFERENCES offices (id) ON DELETE CASCADE,
    FOREIGN KEY (staff_id) REFERENCES staffs (id) ON DELETE SET NULL
);

-- office_audit_logsテーブルのコメント追加
COMMENT ON COLUMN office_audit_logs.action_type IS 'アクション種別: office_info_updated など';
COMMENT ON COLUMN office_audit_logs.details IS '変更内容の詳細（JSON形式）';
COMMENT ON COLUMN office_audit_logs.is_test_data IS 'テストデータフラグ';

-- office_audit_logsテーブルのインデックス追加
CREATE INDEX idx_office_audit_logs_office_id ON office_audit_logs (office_id);
CREATE INDEX idx_office_audit_logs_staff_id ON office_audit_logs (staff_id);
CREATE INDEX idx_office_audit_logs_created_at ON office_audit_logs (created_at);
CREATE INDEX idx_office_audit_logs_is_test_data ON office_audit_logs (is_test_data);

-- ==========================================
-- DOWNGRADE
-- ==========================================

-- -- office_audit_logsテーブルのインデックス削除
-- DROP INDEX IF EXISTS idx_office_audit_logs_is_test_data;
-- DROP INDEX IF EXISTS idx_office_audit_logs_created_at;
-- DROP INDEX IF EXISTS idx_office_audit_logs_staff_id;
-- DROP INDEX IF EXISTS idx_office_audit_logs_office_id;

-- -- office_audit_logsテーブル削除
-- DROP TABLE IF EXISTS office_audit_logs;

-- -- officesテーブルから連絡先情報カラムを削除
-- ALTER TABLE offices DROP COLUMN IF EXISTS email;
-- ALTER TABLE offices DROP COLUMN IF EXISTS phone_number;
-- ALTER TABLE offices DROP COLUMN IF EXISTS address;
