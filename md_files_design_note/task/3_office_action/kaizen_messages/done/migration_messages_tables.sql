-- ============================================================================
-- メッセージ・お知らせ機能 マイグレーションSQL
-- Revision ID: x1y2z3a4b5c6
-- Revises: w9x0y1z2a3b4
-- Create Date: 2025-11-21
-- ============================================================================

-- ============================================================================
-- UPGRADE: テーブル作成とインデックス作成

-- 1. messages テーブル作成（メッセージ本体）

CREATE TABLE messages (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    sender_staff_id UUID REFERENCES staffs(id) ON DELETE SET NULL,
    office_id UUID NOT NULL REFERENCES offices(id) ON DELETE CASCADE,
    message_type VARCHAR(20) NOT NULL DEFAULT 'personal',
    priority VARCHAR(20) NOT NULL DEFAULT 'normal',
    title VARCHAR(200) NOT NULL,
    content TEXT NOT NULL,
    created_at TIMESTAMP WITH TIME ZONE NOT NULL DEFAULT NOW(),
    updated_at TIMESTAMP WITH TIME ZONE NOT NULL DEFAULT NOW()
);

COMMENT ON TABLE messages IS 'メッセージ本体';
COMMENT ON COLUMN messages.id IS 'メッセージID';
COMMENT ON COLUMN messages.sender_staff_id IS '送信者スタッフID（削除時NULL）';
COMMENT ON COLUMN messages.office_id IS '所属事務所ID';
COMMENT ON COLUMN messages.message_type IS 'メッセージタイプ: personal, announcement, system, inquiry';
COMMENT ON COLUMN messages.priority IS '優先度: low, normal, high, urgent';
COMMENT ON COLUMN messages.title IS 'タイトル（最大200文字）';
COMMENT ON COLUMN messages.content IS '本文（最大10,000文字）';

-- 2. message_recipients テーブル作成（受信者管理・中間テーブル）
CREATE TABLE message_recipients (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    message_id UUID NOT NULL REFERENCES messages(id) ON DELETE CASCADE,
    recipient_staff_id UUID NOT NULL REFERENCES staffs(id) ON DELETE CASCADE,
    is_read BOOLEAN NOT NULL DEFAULT FALSE,
    read_at TIMESTAMP WITH TIME ZONE,
    is_archived BOOLEAN NOT NULL DEFAULT FALSE,
    created_at TIMESTAMP WITH TIME ZONE NOT NULL DEFAULT NOW(),
    updated_at TIMESTAMP WITH TIME ZONE NOT NULL DEFAULT NOW(),

    -- 同じメッセージを同じ受信者に複数回送信しない
    CONSTRAINT uq_message_recipient UNIQUE (message_id, recipient_staff_id)
);

COMMENT ON TABLE message_recipients IS 'メッセージ受信者管理（中間テーブル）';
COMMENT ON COLUMN message_recipients.id IS '受信者レコードID';
COMMENT ON COLUMN message_recipients.message_id IS 'メッセージID';
COMMENT ON COLUMN message_recipients.recipient_staff_id IS '受信者スタッフID';
COMMENT ON COLUMN message_recipients.is_read IS '既読フラグ';
COMMENT ON COLUMN message_recipients.read_at IS '既読日時';
COMMENT ON COLUMN message_recipients.is_archived IS 'アーカイブフラグ';
COMMENT ON CONSTRAINT uq_message_recipient ON message_recipients IS '重複送信防止';

-- 3. message_audit_logs テーブル作成（監査ログ）
CREATE TABLE message_audit_logs (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    staff_id UUID REFERENCES staffs(id) ON DELETE SET NULL,
    message_id UUID REFERENCES messages(id) ON DELETE SET NULL,
    action VARCHAR(50) NOT NULL,
    ip_address VARCHAR(45),
    user_agent TEXT,
    success BOOLEAN NOT NULL DEFAULT TRUE,
    error_message TEXT,
    created_at TIMESTAMP WITH TIME ZONE NOT NULL DEFAULT NOW()
);

COMMENT ON TABLE message_audit_logs IS 'メッセージ操作の監査ログ';
COMMENT ON COLUMN message_audit_logs.id IS '監査ログID';
COMMENT ON COLUMN message_audit_logs.staff_id IS '操作者スタッフID（削除時NULL保持）';
COMMENT ON COLUMN message_audit_logs.message_id IS 'メッセージID（削除時NULL保持）';
COMMENT ON COLUMN message_audit_logs.action IS '操作種別: sent, read, archived, deleted';
COMMENT ON COLUMN message_audit_logs.ip_address IS 'IPアドレス（IPv6対応）';
COMMENT ON COLUMN message_audit_logs.user_agent IS 'User-Agent文字列';
COMMENT ON COLUMN message_audit_logs.success IS '操作成功フラグ';
COMMENT ON COLUMN message_audit_logs.error_message IS 'エラーメッセージ（失敗時）';

-- 4. インデックス作成（messages）
-- 事務所ごとのメッセージ一覧を時系列で取得（DESC で最新順）
CREATE INDEX idx_messages_office_created ON messages(office_id, created_at DESC);

-- 送信者のメッセージ一覧取得
CREATE INDEX idx_messages_sender ON messages(sender_staff_id);

-- メッセージタイプでのフィルタリング
CREATE INDEX idx_messages_type ON messages(message_type);

-- 5. インデックス作成（message_recipients）
-- 受信箱取得と未読フィルタの高速化
CREATE INDEX idx_message_recipients_recipient_read ON message_recipients(recipient_staff_id, is_read);

-- メッセージの受信者一覧・統計取得
CREATE INDEX idx_message_recipients_message ON message_recipients(message_id);

-- 時系列での受信箱表示
CREATE INDEX idx_message_recipients_created ON message_recipients(created_at DESC);

-- 6. インデックス作成（message_audit_logs）
-- スタッフの操作履歴検索
CREATE INDEX idx_message_audit_staff ON message_audit_logs(staff_id);

-- メッセージの操作履歴検索
CREATE INDEX idx_message_audit_message ON message_audit_logs(message_id);

-- 時系列での監査ログ検索
CREATE INDEX idx_message_audit_created ON message_audit_logs(created_at DESC);

-- アクションタイプでのフィルタリング
CREATE INDEX idx_message_audit_action ON message_audit_logs(action);


-- ============================================================================
-- DOWNGRADE: ロールバック処理（テーブルとインデックスの削除）
-- ===========================================================================

-- -- 1. インデックス削除（message_audit_logs）
-- DROP INDEX IF EXISTS idx_message_audit_action;
-- DROP INDEX IF EXISTS idx_message_audit_created;
-- DROP INDEX IF EXISTS idx_message_audit_message;
-- DROP INDEX IF EXISTS idx_message_audit_staff;

-- -- 2. インデックス削除（message_recipients）
-- DROP INDEX IF EXISTS idx_message_recipients_created;
-- DROP INDEX IF EXISTS idx_message_recipients_message;
-- DROP INDEX IF EXISTS idx_message_recipients_recipient_read;

-- -- 3. インデックス削除（messages）
-- DROP INDEX IF EXISTS idx_messages_type;
-- DROP INDEX IF EXISTS idx_messages_sender;
-- DROP INDEX IF EXISTS idx_messages_office_created;

-- -- 4. テーブル削除（依存関係の逆順）
-- -- 監査ログテーブル削除（最初に削除）
-- DROP TABLE IF EXISTS message_audit_logs CASCADE;

-- -- 受信者テーブル削除（次に削除）
-- DROP TABLE IF EXISTS message_recipients CASCADE;

-- -- メッセージ本体テーブル削除（最後に削除）
-- DROP TABLE IF EXISTS messages CASCADE;