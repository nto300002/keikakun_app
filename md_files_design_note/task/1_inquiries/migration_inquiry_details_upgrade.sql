-- 問い合わせ機能 - inquiry_details テーブル作成マイグレーション
-- Revision ID: inquiry_001
-- Create Date: 2025-12-03
-- Description: 問い合わせ詳細情報を管理するテーブルを作成
--              Messageテーブルと1:1の関係で問い合わせ固有のメタ情報を保持
-- ============================================================================

-- ============================================================================
-- UPGRADE: テーブル作成とインデックス作成
-- ============================================================================

-- 1. InquiryStatus enum型を作成
CREATE TYPE inquiry_status AS ENUM (
    'new',          -- 新規受付（未確認）
    'open',         -- 確認済み（対応中）
    'in_progress',  -- 担当者割当済み
    'answered',     -- 回答済み
    'closed',       -- クローズ済み
    'spam'          -- スパム判定
);

COMMENT ON TYPE inquiry_status IS '問い合わせステータス';

-- 2. InquiryPriority enum型を作成
CREATE TYPE inquiry_priority AS ENUM (
    'low',      -- 低
    'normal',   -- 通常
    'high'      -- 高
);

COMMENT ON TYPE inquiry_priority IS '問い合わせ優先度';

-- 3. inquiry_details テーブル作成
CREATE TABLE inquiry_details (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),

    -- Messageテーブルとの1:1関連
    message_id UUID NOT NULL UNIQUE REFERENCES messages(id) ON DELETE CASCADE,

    -- 送信者情報（未ログインユーザー用）
    sender_name VARCHAR(100),
    sender_email VARCHAR(255),

    -- リクエスト情報
    ip_address VARCHAR(45),  -- IPv6対応
    user_agent TEXT,

    -- ステータス管理
    status inquiry_status NOT NULL DEFAULT 'new',

    -- 担当者
    assigned_staff_id UUID REFERENCES staffs(id) ON DELETE SET NULL,

    -- 優先度
    priority inquiry_priority NOT NULL DEFAULT 'normal',

    -- 管理者メモ
    admin_notes TEXT,

    -- メール送信履歴（JSON形式）
    delivery_log JSONB,

    -- タイムスタンプ
    created_at TIMESTAMP WITH TIME ZONE NOT NULL DEFAULT NOW(),
    updated_at TIMESTAMP WITH TIME ZONE NOT NULL DEFAULT NOW(),

    -- テストデータフラグ
    is_test_data BOOLEAN NOT NULL DEFAULT FALSE
);

-- コメント追加
COMMENT ON TABLE inquiry_details IS '問い合わせ詳細情報（Messageと1:1の関係）';
COMMENT ON COLUMN inquiry_details.id IS '問い合わせ詳細ID';
COMMENT ON COLUMN inquiry_details.message_id IS 'メッセージID（UNIQUE, messages.idへの外部キー）';
COMMENT ON COLUMN inquiry_details.sender_name IS '送信者名（未ログインユーザー用）';
COMMENT ON COLUMN inquiry_details.sender_email IS '送信者メールアドレス（未ログインユーザー用）';
COMMENT ON COLUMN inquiry_details.ip_address IS '送信元IPアドレス（IPv6対応）';
COMMENT ON COLUMN inquiry_details.user_agent IS 'ユーザーエージェント文字列';
COMMENT ON COLUMN inquiry_details.status IS 'ステータス（new, open, in_progress, answered, closed, spam）';
COMMENT ON COLUMN inquiry_details.assigned_staff_id IS '担当者スタッフID';
COMMENT ON COLUMN inquiry_details.priority IS '優先度（low, normal, high）';
COMMENT ON COLUMN inquiry_details.admin_notes IS '管理者メモ';
COMMENT ON COLUMN inquiry_details.delivery_log IS 'メール送信履歴（JSONB形式）';
COMMENT ON COLUMN inquiry_details.created_at IS '作成日時';
COMMENT ON COLUMN inquiry_details.updated_at IS '更新日時';
COMMENT ON COLUMN inquiry_details.is_test_data IS 'テストデータフラグ';

-- 4. インデックス作成

-- 単一カラムインデックス
CREATE INDEX ix_inquiry_details_message_id ON inquiry_details(message_id);
CREATE INDEX ix_inquiry_details_sender_email ON inquiry_details(sender_email);
CREATE INDEX ix_inquiry_details_status ON inquiry_details(status);
CREATE INDEX ix_inquiry_details_assigned_staff_id ON inquiry_details(assigned_staff_id);
CREATE INDEX ix_inquiry_details_created_at ON inquiry_details(created_at);
CREATE INDEX ix_inquiry_details_is_test_data ON inquiry_details(is_test_data);

-- 複合インデックス（一覧表示の最適化）
CREATE INDEX ix_inquiry_details_status_created ON inquiry_details(status, created_at DESC);
CREATE INDEX ix_inquiry_details_assigned_status ON inquiry_details(assigned_staff_id, status);
CREATE INDEX ix_inquiry_details_priority_status ON inquiry_details(priority, status);

-- 5. updated_at自動更新トリガー作成
CREATE OR REPLACE FUNCTION update_inquiry_details_updated_at()
RETURNS TRIGGER AS $$
BEGIN
    NEW.updated_at = NOW();
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER trigger_update_inquiry_details_timestamp
    BEFORE UPDATE ON inquiry_details
    FOR EACH ROW
    EXECUTE FUNCTION update_inquiry_details_updated_at();

COMMENT ON FUNCTION update_inquiry_details_updated_at() IS 'inquiry_detailsのupdated_atを自動更新する関数';
COMMENT ON TRIGGER trigger_update_inquiry_details_timestamp ON inquiry_details IS 'updated_at自動更新トリガー';

-- ============================================================================
-- DOWNGRADE: テーブル、トリガー、関数、enum型の削除
-- ============================================================================

-- -- 1. トリガーを削除
-- DROP TRIGGER IF EXISTS trigger_update_inquiry_details_timestamp ON inquiry_details;

-- -- 2. トリガー関数を削除
-- DROP FUNCTION IF EXISTS update_inquiry_details_updated_at();

-- -- 3. inquiry_details テーブルを削除（CASCADE で関連するインデックスも削除）
-- DROP TABLE IF EXISTS inquiry_details CASCADE;

-- -- 4. enum型を削除
-- DROP TYPE IF EXISTS inquiry_status;
-- DROP TYPE IF EXISTS inquiry_priority;

-- ============================================================================
-- ダウングレード完了
-- ============================================================================
