-- ====================================================================
-- Billing Table Migration - UPGRADE
-- Revision ID: g5h6i7j8k9l0
-- Revises: f4g5h6i7j8k9
-- Create Date: 2025-12-11 00:00:00.000000
--
-- Phase 0: Billingテーブル移行（課金機能の前提作業）
-- - OfficeテーブルからBillingテーブルへの1:1分離
-- - Stripe連携情報と課金ステータスの管理
-- - 無料期間（180日）の自動計算
-- ====================================================================

-- 1. billingsテーブルを作成
CREATE TABLE billings (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    office_id UUID NOT NULL,
    stripe_customer_id VARCHAR(255),
    stripe_subscription_id VARCHAR(255),
    billing_status VARCHAR(20) NOT NULL DEFAULT 'free',
    trial_start_date TIMESTAMPTZ NOT NULL,
    trial_end_date TIMESTAMPTZ NOT NULL,
    subscription_start_date TIMESTAMPTZ,
    next_billing_date TIMESTAMPTZ,
    current_plan_amount INTEGER NOT NULL DEFAULT 6000,
    last_payment_date TIMESTAMPTZ,
    created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

-- 2. ユニーク制約を作成
ALTER TABLE billings ADD CONSTRAINT uq_billings_office_id UNIQUE (office_id);
ALTER TABLE billings ADD CONSTRAINT uq_billings_stripe_customer_id UNIQUE (stripe_customer_id);
ALTER TABLE billings ADD CONSTRAINT uq_billings_stripe_subscription_id UNIQUE (stripe_subscription_id);

-- 3. インデックスを作成
CREATE INDEX idx_billings_billing_status ON billings (billing_status);

-- 4. 外部キー制約を作成（CASCADE DELETE）
ALTER TABLE billings
    ADD CONSTRAINT fk_billings_office_id
    FOREIGN KEY (office_id)
    REFERENCES offices (id)
    ON DELETE CASCADE;

-- 5. Officeテーブルからデータを移行
INSERT INTO billings (
    office_id,
    stripe_customer_id,
    stripe_subscription_id,
    billing_status,
    trial_start_date,
    trial_end_date,
    current_plan_amount,
    created_at,
    updated_at
)
SELECT
    id AS office_id,
    stripe_customer_id,
    stripe_subscription_id,
    billing_status,
    created_at AS trial_start_date,
    created_at + INTERVAL '180 days' AS trial_end_date,
    6000 AS current_plan_amount,
    now() AS created_at,
    now() AS updated_at
FROM offices;

-- 6. Officeテーブルから課金関連カラムを削除
ALTER TABLE offices DROP COLUMN IF EXISTS stripe_subscription_id;
ALTER TABLE offices DROP COLUMN IF EXISTS stripe_customer_id;
ALTER TABLE offices DROP COLUMN IF EXISTS billing_status;

-- 7. テーブルコメント
COMMENT ON TABLE billings IS '事業所の課金情報（Officeと1:1リレーション）';

-- マイグレーション完了
-- 確認用クエリ:
-- SELECT COUNT(*) FROM billings;
-- SELECT b.*, o.name FROM billings b JOIN offices o ON b.office_id = o.id LIMIT 5;

-- -- downgrade Script
-- -- 1. Officeテーブルに課金関連カラムを追加
-- ALTER TABLE offices ADD COLUMN billing_status VARCHAR(20) NOT NULL DEFAULT 'free';
-- ALTER TABLE offices ADD COLUMN stripe_customer_id VARCHAR(255);
-- ALTER TABLE offices ADD COLUMN stripe_subscription_id VARCHAR(255);

-- -- 2. Billingテーブルからデータを戻す
-- UPDATE offices
-- SET
--     billing_status = billings.billing_status,
--     stripe_customer_id = billings.stripe_customer_id,
--     stripe_subscription_id = billings.stripe_subscription_id
-- FROM billings
-- WHERE offices.id = billings.office_id;

-- -- 3. 外部キー制約を削除
-- ALTER TABLE billings DROP CONSTRAINT IF EXISTS fk_billings_office_id;

-- -- 4. インデックスを削除
-- DROP INDEX IF EXISTS idx_billings_billing_status;

-- -- 5. ユニーク制約を削除
-- ALTER TABLE billings DROP CONSTRAINT IF EXISTS uq_billings_stripe_subscription_id;
-- ALTER TABLE billings DROP CONSTRAINT IF EXISTS uq_billings_stripe_customer_id;
-- ALTER TABLE billings DROP CONSTRAINT IF EXISTS uq_billings_office_id;

-- -- 6. Billingテーブルを削除
-- DROP TABLE IF EXISTS billings;

-- -- ロールバック完了
-- -- 確認用クエリ:
-- -- SELECT id, name, billing_status, stripe_customer_id FROM offices LIMIT 5;