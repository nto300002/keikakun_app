-- スタッフ削除機能のためのスキーマ削除（downgrade）
-- Revision ID: b2c3d4e5f6g7
-- Revises: a7b8c9d0e1f2
-- Create Date: 2025-11-24 14:30:00.000000

-- 1. staff_audit_logsテーブルのインデックス削除
DROP INDEX IF EXISTS ix_staff_audit_logs_created_at;
DROP INDEX IF EXISTS ix_staff_audit_logs_performed_by;
DROP INDEX IF EXISTS ix_staff_audit_logs_action;
DROP INDEX IF EXISTS ix_staff_audit_logs_staff_id;

-- 2. staff_audit_logsテーブル削除
DROP TABLE IF EXISTS staff_audit_logs;

-- 3. staffsテーブルのインデックス削除
DROP INDEX IF EXISTS idx_staff_office_id_is_deleted;
DROP INDEX IF EXISTS idx_staff_is_deleted;

-- 4. staffsテーブルの外部キー制約削除
ALTER TABLE staffs DROP CONSTRAINT IF EXISTS fk_staffs_deleted_by_staffs;

-- 5. staffsテーブルのカラム削除
ALTER TABLE staffs DROP COLUMN IF EXISTS deleted_by;
ALTER TABLE staffs DROP COLUMN IF EXISTS deleted_at;
ALTER TABLE staffs DROP COLUMN IF EXISTS is_deleted;

-- 完了
