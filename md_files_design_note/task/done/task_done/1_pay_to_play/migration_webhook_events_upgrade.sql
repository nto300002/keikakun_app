-- Webhook Events テーブル作成マイグレーション（アップグレード）
-- Revision: h6i7j8k9l0m1
-- 作成日: 2025-12-12
--
-- 目的: Stripe Webhookイベントの重複処理を防止（冪等性担保）

-- ==========================================
-- 1. webhook_eventsテーブル作成
-- ==========================================

CREATE TABLE webhook_events (
    -- 主キー
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),

    -- Stripe Event情報
    event_id VARCHAR(255) NOT NULL UNIQUE,  -- Stripe Event ID (例: evt_1234567890)
    event_type VARCHAR(100) NOT NULL,       -- イベントタイプ (例: invoice.payment_succeeded)
    source VARCHAR(50) NOT NULL DEFAULT 'stripe',  -- Webhook送信元

    -- 関連リソース
    billing_id UUID REFERENCES billings(id) ON DELETE SET NULL,
    office_id UUID REFERENCES offices(id) ON DELETE SET NULL,

    -- ペイロード（デバッグ用）
    payload JSONB,

    -- 処理情報
    processed_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    status VARCHAR(20) NOT NULL DEFAULT 'success',  -- success, failed, skipped
    error_message TEXT,

    -- タイムスタンプ
    created_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

-- ==========================================
-- 2. インデックス作成
-- ==========================================

-- 冪等性チェック用（最重要）
CREATE UNIQUE INDEX uq_webhook_events_event_id ON webhook_events(event_id);
CREATE INDEX idx_webhook_events_event_id ON webhook_events(event_id);

-- イベントタイプ検索用
CREATE INDEX idx_webhook_events_event_type ON webhook_events(event_type);

-- 処理日時検索用（古いログ削除に使用）
CREATE INDEX idx_webhook_events_processed_at ON webhook_events(processed_at);

-- 関連リソース検索用
CREATE INDEX idx_webhook_events_billing_id ON webhook_events(billing_id);
CREATE INDEX idx_webhook_events_office_id ON webhook_events(office_id);

-- ステータス検索用
CREATE INDEX idx_webhook_events_status ON webhook_events(status);

-- ==========================================
-- 3. コメント追加
-- ==========================================

COMMENT ON TABLE webhook_events IS 'Webhook冪等性管理テーブル - Stripeから送信されるWebhookイベントの重複処理を防止';
COMMENT ON COLUMN webhook_events.event_id IS 'Stripe Event ID (例: evt_1234567890)';
COMMENT ON COLUMN webhook_events.event_type IS 'イベントタイプ (例: invoice.payment_succeeded)';
COMMENT ON COLUMN webhook_events.source IS 'Webhook送信元 (stripe, etc.)';
COMMENT ON COLUMN webhook_events.billing_id IS '関連するBilling ID';
COMMENT ON COLUMN webhook_events.office_id IS '関連するOffice ID';
COMMENT ON COLUMN webhook_events.payload IS 'Webhookペイロード（デバッグ用）';
COMMENT ON COLUMN webhook_events.processed_at IS '処理日時';
COMMENT ON COLUMN webhook_events.status IS '処理ステータス (success, failed, skipped)';
COMMENT ON COLUMN webhook_events.error_message IS 'エラーメッセージ（処理失敗時）';

-- ==========================================
-- 4. 確認クエリ
-- ==========================================

-- テーブル構造確認
\d webhook_events

-- インデックス確認
\di webhook_events*

-- 件数確認（初期は0件）
SELECT COUNT(*) FROM webhook_events;


-- ==========================================
-- ダウングレードスクリプト（コメント）
-- ==========================================

-- ロールバック時は以下を実行:
-- DROP INDEX IF EXISTS idx_webhook_events_status;
-- DROP INDEX IF EXISTS idx_webhook_events_office_id;
-- DROP INDEX IF EXISTS idx_webhook_events_billing_id;
-- DROP INDEX IF EXISTS idx_webhook_events_processed_at;
-- DROP INDEX IF EXISTS idx_webhook_events_event_type;
-- DROP INDEX IF EXISTS idx_webhook_events_event_id;
-- DROP INDEX IF EXISTS uq_webhook_events_event_id;
-- DROP TABLE IF EXISTS webhook_events CASCADE;
