-- ========================================
-- パスワードリセット機能 - 完全マイグレーションSQL
-- Revision ID: r3s4t5u6v7w8
-- Revises: a1b2c3d4e5f6
-- Create Date: 2025-01-20 10:00:00
-- ========================================
--
-- このファイルにはアップグレード（テーブル作成）とダウングレード（テーブル削除）の両方のSQLが含まれています。
-- 実行する際は、必要なセクションのみを実行してください。
--
-- ========================================

-- ========================================
-- UPGRADE: テーブルとインデックスの作成
-- ========================================

BEGIN;

-- 1. password_reset_tokens テーブル作成
-- パスワードリセットトークンを管理するテーブル
-- トークンはSHA-256でハッシュ化して保存される
CREATE TABLE password_reset_tokens (
    id UUID NOT NULL DEFAULT gen_random_uuid(),
    staff_id UUID NOT NULL,
    token_hash VARCHAR(64) NOT NULL,  -- SHA-256ハッシュ（64文字の16進数）
    expires_at TIMESTAMP WITH TIME ZONE NOT NULL,  -- トークン有効期限
    used BOOLEAN NOT NULL DEFAULT false,  -- 使用済みフラグ
    used_at TIMESTAMP WITH TIME ZONE,  -- 使用日時
    created_at TIMESTAMP WITH TIME ZONE NOT NULL DEFAULT now(),
    updated_at TIMESTAMP WITH TIME ZONE NOT NULL DEFAULT now(),
    PRIMARY KEY (id),
    FOREIGN KEY(staff_id) REFERENCES staffs (id) ON DELETE CASCADE
);

COMMENT ON TABLE password_reset_tokens IS 'パスワードリセットトークン管理テーブル';
COMMENT ON COLUMN password_reset_tokens.token_hash IS 'SHA-256ハッシュ化されたトークン（平文保存禁止）';
COMMENT ON COLUMN password_reset_tokens.expires_at IS 'トークン有効期限（推奨: 1時間）';
COMMENT ON COLUMN password_reset_tokens.used IS '使用済みフラグ（楽観的ロックで制御）';

-- 2. password_reset_audit_logs テーブル作成
-- パスワードリセットの全アクションを記録する監査ログテーブル
CREATE TABLE password_reset_audit_logs (
    id UUID NOT NULL DEFAULT gen_random_uuid(),
    staff_id UUID,  -- スタッフが削除されてもログは保持（SET NULL）
    action VARCHAR(50) NOT NULL,  -- 'requested', 'token_verified', 'completed', 'failed'
    email VARCHAR(255),  -- リクエストされたメールアドレス
    ip_address VARCHAR(45),  -- IPv6対応（最大45文字）
    user_agent TEXT,  -- ブラウザ・デバイス情報
    success BOOLEAN NOT NULL DEFAULT true,  -- アクションの成功/失敗
    error_message TEXT,  -- エラーメッセージ（失敗時のみ）
    created_at TIMESTAMP WITH TIME ZONE NOT NULL DEFAULT now(),
    PRIMARY KEY (id),
    FOREIGN KEY(staff_id) REFERENCES staffs (id) ON DELETE SET NULL
);

COMMENT ON TABLE password_reset_audit_logs IS 'パスワードリセット監査ログテーブル';
COMMENT ON COLUMN password_reset_audit_logs.action IS 'アクション種別: requested, token_verified, completed, failed';
COMMENT ON COLUMN password_reset_audit_logs.success IS '成功フラグ（異常検知に使用）';

-- 3. インデックス作成（password_reset_tokens）
-- トークンハッシュのユニークインデックス（高速検索用）
CREATE UNIQUE INDEX idx_password_reset_token_hash
ON password_reset_tokens (token_hash);

-- 複合インデックス（有効なトークン検索用）
-- WHERE staff_id = ? AND used = false AND expires_at > NOW() のクエリを高速化
CREATE INDEX idx_password_reset_composite
ON password_reset_tokens (staff_id, used, expires_at);

-- 4. インデックス作成（password_reset_audit_logs）
-- スタッフIDでの監査ログ検索用
CREATE INDEX idx_audit_staff_id
ON password_reset_audit_logs (staff_id);

-- 時系列でのログ検索用
CREATE INDEX idx_audit_created_at
ON password_reset_audit_logs (created_at);

-- アクションタイプでのフィルタリング用
CREATE INDEX idx_audit_action
ON password_reset_audit_logs (action);

COMMIT;

-- ========================================
-- 確認クエリ（アップグレード後）
-- ========================================

-- テーブルが作成されたことを確認
SELECT
    table_name,
    table_type
FROM information_schema.tables
WHERE table_name IN ('password_reset_tokens', 'password_reset_audit_logs')
ORDER BY table_name;

-- インデックスが作成されたことを確認
SELECT
    tablename,
    indexname,
    indexdef
FROM pg_indexes
WHERE tablename IN ('password_reset_tokens', 'password_reset_audit_logs')
ORDER BY tablename, indexname;

-- カラム情報を確認
SELECT
    table_name,
    column_name,
    data_type,
    is_nullable,
    column_default
FROM information_schema.columns
WHERE table_name IN ('password_reset_tokens', 'password_reset_audit_logs')
ORDER BY table_name, ordinal_position;


-- ========================================
-- DOWNGRADE: テーブルとインデックスの削除
-- ========================================
--
-- 注意: 以下のSQLを実行すると、全データが削除されます。
-- 本番環境では絶対に実行しないでください。
-- テスト環境でのみ使用してください。
--
-- ========================================

/*
BEGIN;

-- 1. インデックス削除（password_reset_audit_logs）
DROP INDEX IF EXISTS idx_audit_action;
DROP INDEX IF EXISTS idx_audit_created_at;
DROP INDEX IF EXISTS idx_audit_staff_id;

-- 2. インデックス削除（password_reset_tokens）
DROP INDEX IF EXISTS idx_password_reset_composite;
DROP INDEX IF EXISTS idx_password_reset_token_hash;

-- 3. テーブル削除
-- 外部キー制約があるため、audit_logsを先に削除
DROP TABLE IF EXISTS password_reset_audit_logs;
DROP TABLE IF EXISTS password_reset_tokens;

COMMIT;
*/

-- ========================================
-- 確認クエリ（ダウングレード後）
-- ========================================

/*
-- テーブルが削除されたことを確認（結果が0件であること）
SELECT
    table_name
FROM information_schema.tables
WHERE table_name IN ('password_reset_tokens', 'password_reset_audit_logs');

-- インデックスが削除されたことを確認（結果が0件であること）
SELECT
    indexname
FROM pg_indexes
WHERE tablename IN ('password_reset_tokens', 'password_reset_audit_logs');
*/

-- ========================================
-- 使用例: データ挿入とクエリ
-- ========================================

/*
-- トークンの作成例（実際のアプリケーションではSHA-256ハッシュを使用）
INSERT INTO password_reset_tokens (staff_id, token_hash, expires_at)
VALUES (
    'xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx'::uuid,  -- 実際のstaff_id
    'abcdef1234567890abcdef1234567890abcdef1234567890abcdef1234567890',  -- SHA-256ハッシュ
    NOW() + INTERVAL '1 hour'
);

-- 監査ログの作成例
INSERT INTO password_reset_audit_logs (staff_id, action, email, ip_address, user_agent, success)
VALUES (
    'xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx'::uuid,
    'requested',
    'user@example.com',
    '192.168.1.1',
    'Mozilla/5.0',
    true
);

-- 有効なトークンの検索例
SELECT *
FROM password_reset_tokens
WHERE token_hash = 'abcdef1234567890abcdef1234567890abcdef1234567890abcdef1234567890'
  AND used = false
  AND expires_at > NOW();

-- 監査ログの検索例（過去24時間のリクエスト）
SELECT *
FROM password_reset_audit_logs
WHERE action = 'requested'
  AND created_at > NOW() - INTERVAL '24 hours'
ORDER BY created_at DESC;

-- 異常なアクセスパターンの検出例（同一IPから10回以上のリクエスト）
SELECT
    ip_address,
    COUNT(*) as request_count,
    MIN(created_at) as first_request,
    MAX(created_at) as last_request
FROM password_reset_audit_logs
WHERE action = 'requested'
  AND created_at > NOW() - INTERVAL '1 hour'
GROUP BY ip_address
HAVING COUNT(*) > 10
ORDER BY request_count DESC;
*/
