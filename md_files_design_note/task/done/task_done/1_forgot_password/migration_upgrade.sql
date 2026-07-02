--
-- 作業ブランチ: <ここに現在作業中のブランチ名を記入してください>
-- 注意: このファイルを編集する場合、必ず作業中のブランチ名を上部に記載し、変更はそのブランチへ push してください。
--

-- ========================================
-- パスワードリセット機能 - マイグレーション（アップグレード）
-- Revision ID: r3s4t5u6v7w8
-- Revises: a1b2c3d4e5f6
-- Create Date: 2025-01-20 10:00:00
-- ========================================


-- 1. password_reset_tokens テーブル作成
CREATE TABLE password_reset_tokens (
    id UUID NOT NULL DEFAULT gen_random_uuid(),
    staff_id UUID NOT NULL,
    token_hash VARCHAR(64) NOT NULL,  -- SHA-256ハッシュ（64文字の16進数）
    expires_at TIMESTAMP WITH TIME ZONE NOT NULL,
    used BOOLEAN NOT NULL DEFAULT false,
    used_at TIMESTAMP WITH TIME ZONE,
    created_at TIMESTAMP WITH TIME ZONE NOT NULL DEFAULT now(),
    updated_at TIMESTAMP WITH TIME ZONE NOT NULL DEFAULT now(),
    PRIMARY KEY (id),
    FOREIGN KEY(staff_id) REFERENCES staffs (id) ON DELETE CASCADE
);


-- 2. password_reset_audit_logs テーブル作成
CREATE TABLE password_reset_audit_logs (
    id UUID NOT NULL DEFAULT gen_random_uuid(),
    staff_id UUID,
    action VARCHAR(50) NOT NULL,  -- 'requested', 'token_verified', 'completed', 'failed'
    email VARCHAR(255),
    ip_address VARCHAR(45),  -- IPv6対応
    user_agent TEXT,
    success BOOLEAN NOT NULL DEFAULT true,
    error_message TEXT,
    created_at TIMESTAMP WITH TIME ZONE NOT NULL DEFAULT now(),
    PRIMARY KEY (id),
    FOREIGN KEY(staff_id) REFERENCES staffs (id) ON DELETE SET NULL
);


-- 3. インデックス作成（password_reset_tokens）
-- トークンハッシュのユニークインデックス（高速検索用）
CREATE UNIQUE INDEX idx_password_reset_token_hash
ON password_reset_tokens (token_hash);

-- 複合インデックス（有効なトークン検索用）
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

-- マイグレーション完了

-- 確認クエリ（オプション）
-- SELECT table_name FROM information_schema.tables WHERE table_name IN ('password_reset_tokens', 'password_reset_audit_logs');
-- SELECT indexname FROM pg_indexes WHERE tablename IN ('password_reset_tokens', 'password_reset_audit_logs');


-- ========================================
-- Downgrade (rollback) Revision ID: r3s4t5u6v7w8 -> a1b2c3d4e5f6  
-- Revert migration: r3s4t5u6v7w8
-- 実行すると本マイグレーションで作成したインデックスとテーブルを削除します。
-- 注意: 本操作はデータを完全に削除します。テスト環境以外での実行は避けてください。
-- ========================================

BEGIN;

-- 1) インデックス削除（テーブル削除前に削除）
DROP INDEX IF EXISTS idx_password_reset_token_hash;
DROP INDEX IF EXISTS idx_password_reset_composite;
DROP INDEX IF EXISTS idx_audit_staff_id;
DROP INDEX IF EXISTS idx_audit_created_at;
DROP INDEX IF EXISTS idx_audit_action;

-- 2) テーブル削除（依存関係を考慮して audit_logs を先に削除）
DROP TABLE IF EXISTS password_reset_audit_logs;
DROP TABLE IF EXISTS password_reset_tokens;

COMMIT;

-- 確認クエリ（オプション）：削除が成功したかを確認する
-- SELECT table_name FROM information_schema.tables WHERE table_name IN ('password_reset_tokens', 'password_reset_audit_logs');
-- SELECT indexname FROM pg_indexes WHERE tablename IN ('password_reset_tokens', 'password_reset_audit_logs');
