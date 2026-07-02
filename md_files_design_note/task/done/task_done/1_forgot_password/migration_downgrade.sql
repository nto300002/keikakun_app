--
-- 作業ブランチ: <ここに現在作業中のブランチ名を記入してください>
-- 注意: このファイルを編集する場合、必ず作業中のブランチ名を上部に記載し、変更はそのブランチへ push してください。
--

-- ========================================
-- パスワードリセット機能 - マイグレーション（ダウングレード/ロールバック）
-- Revision ID: r3s4t5u6v7w8 -> a1b2c3d4e5f6
-- ========================================

-- ========================================
-- 1. インデックス削除（password_reset_audit_logs）
-- ========================================

DROP INDEX IF EXISTS idx_audit_action;
DROP INDEX IF EXISTS idx_audit_created_at;
DROP INDEX IF EXISTS idx_audit_staff_id;

-- ========================================
-- 2. インデックス削除（password_reset_tokens）
-- ========================================

DROP INDEX IF EXISTS idx_password_reset_composite;
DROP INDEX IF EXISTS idx_password_reset_token_hash;

-- ========================================
-- 3. テーブル削除
-- ========================================

-- 監査ログテーブルを削除
DROP TABLE IF EXISTS password_reset_audit_logs;

-- パスワードリセットトークンテーブルを削除
DROP TABLE IF EXISTS password_reset_tokens;

-- ========================================
-- ロールバック完了
-- ========================================

-- 確認クエリ（オプション）
-- SELECT table_name FROM information_schema.tables WHERE table_name IN ('password_reset_tokens', 'password_reset_audit_logs');
