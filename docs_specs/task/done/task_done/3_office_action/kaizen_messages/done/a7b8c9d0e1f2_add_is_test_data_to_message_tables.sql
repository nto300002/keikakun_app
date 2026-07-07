-- ============================================================================
-- is_test_data カラム追加マイグレーション
-- Revision ID: a7b8c9d0e1f2
-- Revises: x1y2z3a4b5c6
-- Create Date: 2025-11-23
-- ============================================================================

-- ============================================================================
-- UPGRADE: is_test_data カラムとインデックスを追加
-- ============================================================================

-- 1. messages テーブルに is_test_data カラムを追加
ALTER TABLE messages
ADD COLUMN is_test_data BOOLEAN NOT NULL DEFAULT false;

-- messages テーブルにインデックス作成
CREATE INDEX idx_messages_is_test_data ON messages(is_test_data);

COMMENT ON COLUMN messages.is_test_data IS 'テストデータフラグ（テスト環境でのデータクリーンアップ用）';


-- 2. message_recipients テーブルに is_test_data カラムを追加
ALTER TABLE message_recipients
ADD COLUMN is_test_data BOOLEAN NOT NULL DEFAULT false;

-- message_recipients テーブルにインデックス作成
CREATE INDEX idx_message_recipients_is_test_data ON message_recipients(is_test_data);

COMMENT ON COLUMN message_recipients.is_test_data IS 'テストデータフラグ（テスト環境でのデータクリーンアップ用）';


-- 3. message_audit_logs テーブルに is_test_data カラムを追加
ALTER TABLE message_audit_logs
ADD COLUMN is_test_data BOOLEAN NOT NULL DEFAULT false;

-- message_audit_logs テーブルにインデックス作成
CREATE INDEX idx_message_audit_logs_is_test_data ON message_audit_logs(is_test_data);

COMMENT ON COLUMN message_audit_logs.is_test_data IS 'テストデータフラグ（テスト環境でのデータクリーンアップ用）';


-- ============================================================================
-- DOWNGRADE: is_test_data カラムとインデックスを削除（ロールバック用）
-- ============================================================================

-- -- インデックス削除
-- DROP INDEX IF EXISTS idx_message_audit_logs_is_test_data;
-- DROP INDEX IF EXISTS idx_message_recipients_is_test_data;
-- DROP INDEX IF EXISTS idx_messages_is_test_data;

-- -- カラム削除
-- ALTER TABLE message_audit_logs DROP COLUMN IF EXISTS is_test_data;
-- ALTER TABLE message_recipients DROP COLUMN IF EXISTS is_test_data;
-- ALTER TABLE messages DROP COLUMN IF EXISTS is_test_data;


-- ============================================================================
-- 実行確認用クエリ
-- ============================================================================

-- カラムが追加されたことを確認
-- SELECT column_name, data_type, is_nullable, column_default
-- FROM information_schema.columns
-- WHERE table_name IN ('messages', 'message_recipients', 'message_audit_logs')
--   AND column_name = 'is_test_data'
-- ORDER BY table_name;

-- インデックスが作成されたことを確認
-- SELECT tablename, indexname
-- FROM pg_indexes
-- WHERE tablename IN ('messages', 'message_recipients', 'message_audit_logs')
--   AND indexname LIKE '%is_test_data%'
-- ORDER BY tablename;
