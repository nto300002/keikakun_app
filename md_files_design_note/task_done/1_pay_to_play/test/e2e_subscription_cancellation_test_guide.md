# E2Eテスト手順書: Subscription Cancellation (canceling → canceled)

## 📋 目的

`canceling → canceled`の状態遷移をStripe CLIを使ってE2Eテストする手順書

## 🎯 テスト対象

- `billing_status`が`canceling`から`canceled`に遷移すること
- `customer.subscription.deleted` webhookが正しく受信・処理されること
- `scheduled_cancel_at`がクリアされること
- 監査ログが正しく記録されること

---

## 📦 前提条件

### 1. Stripe CLIのインストール

```bash
# macOS
brew install stripe/stripe-cli/stripe

# その他のOS
# https://stripe.com/docs/stripe-cli#install
```

### 2. Stripe CLIのログイン

```bash
stripe login
```

ブラウザが開くので、Stripeアカウントでログインします。

---

## 🧪 テストシナリオ

### シナリオ1: トライアル中のキャンセル → 削除

**想定フロー:**
1. ユーザーがトライアル中にサブスクリプション設定
2. トライアル中にキャンセル予定を設定（`canceling`状態）
3. `scheduled_cancel_at`到達でStripeが自動削除
4. `customer.subscription.deleted` webhook送信
5. `billing_status`が`canceled`に遷移

**テスト手順:**

#### Step 1: データベースの準備

```sql
-- テスト用事務所とBillingレコードを確認
SELECT
    b.id,
    b.office_id,
    b.billing_status,
    b.stripe_customer_id,
    b.stripe_subscription_id,
    b.scheduled_cancel_at,
    b.trial_end_date
FROM billings b
WHERE b.office_id = '<your_office_id>';
```

#### Step 2: Billing状態をcancelingに設定

```sql
-- テスト用にcanceling状態を作成
UPDATE billings
SET
    billing_status = 'canceling',
    stripe_customer_id = 'cus_test_e2e_cancel',
    stripe_subscription_id = 'sub_test_e2e_cancel',
    scheduled_cancel_at = NOW() + INTERVAL '7 days'
WHERE id = '<billing_id>';
```

#### Step 3: Stripe CLI Webhook Forwardingを開始

```bash
# ターミナル1: Webhook forwarding
stripe listen --forward-to http://localhost:8000/api/v1/webhooks/stripe
```

出力例:
```
> Ready! Your webhook signing secret is whsec_xxxxxxxxxxxxx
```

**重要:** `whsec_xxxxxxxxxxxxx`をコピーして、`.env`に設定します。

```bash
# .env
STRIPE_WEBHOOK_SECRET=whsec_xxxxxxxxxxxxx
```

#### Step 4: アプリケーションを再起動

```bash
# Dockerの場合
docker compose restart backend

# ローカルの場合
# FastAPIサーバーを再起動
```

#### Step 5: Webhookイベントを送信

```bash
# ターミナル2: customer.subscription.deleted イベントを送信
stripe trigger customer.subscription.deleted \
  --override customer:id=cus_test_e2e_cancel \
  --override id=sub_test_e2e_cancel
```

または、カスタムイベントを送信:

```bash
stripe events resend evt_xxxxxxxxxxxxx
```

#### Step 6: 結果確認

**ターミナル1の出力を確認:**

```
POST /api/v1/webhooks/stripe [202 Accepted]
```

**データベースで状態を確認:**

```sql
-- Billing状態を確認
SELECT
    billing_status,
    stripe_customer_id,
    stripe_subscription_id,
    scheduled_cancel_at,
    updated_at
FROM billings
WHERE id = '<billing_id>';

-- 期待される結果:
-- billing_status: canceled
-- scheduled_cancel_at: NULL
```

**Webhookイベントを確認:**

```sql
SELECT
    event_id,
    event_type,
    status,
    billing_id,
    office_id,
    processed_at
FROM webhook_events
ORDER BY processed_at DESC
LIMIT 5;

-- 期待される結果:
-- event_type: customer.subscription.deleted
-- status: success
```

**監査ログを確認:**

```sql
SELECT
    action,
    target_type,
    target_id,
    office_id,
    details,
    timestamp
FROM audit_logs
WHERE office_id = '<office_id>'
ORDER BY timestamp DESC
LIMIT 5;

-- 期待される結果:
-- action: billing.subscription_canceled
-- target_type: billing
```

---

### シナリオ2: Active状態からの即座のキャンセル

**想定フロー:**
1. ユーザーがトライアル終了後、課金中（`active`）
2. ユーザーがサブスクリプションを即座にキャンセル
3. Stripeがサブスクリプションを削除
4. `customer.subscription.deleted` webhook送信
5. `billing_status`が`canceled`に遷移

**テスト手順:**

#### Step 1: Billing状態をactiveに設定

```sql
UPDATE billings
SET
    billing_status = 'active',
    stripe_customer_id = 'cus_test_e2e_active',
    stripe_subscription_id = 'sub_test_e2e_active',
    trial_end_date = NOW() - INTERVAL '30 days'
WHERE id = '<billing_id>';
```

#### Step 2: Webhookイベントを送信

```bash
stripe trigger customer.subscription.deleted \
  --override customer:id=cus_test_e2e_active \
  --override id=sub_test_e2e_active
```

#### Step 3: 結果確認（シナリオ1と同様）

---

## 🔍 トラブルシューティング

### Webhook が受信されない

**症状:** `stripe listen`は動いているが、アプリケーションが200/202を返さない

**原因と対処:**

1. **Webhook secretが設定されていない**
   ```bash
   # .envを確認
   cat .env | grep STRIPE_WEBHOOK_SECRET
   ```

2. **アプリケーションが起動していない**
   ```bash
   docker ps | grep backend
   ```

3. **ファイアウォールがブロックしている**
   ```bash
   # ローカルホストでテスト
   curl -X POST http://localhost:8000/api/v1/webhooks/stripe
   ```

### Billing が見つからない

**症状:** ログに「Billing not found for customer」

**原因:** `stripe_customer_id`がデータベースと一致していない

**対処:**

```sql
-- stripe_customer_idを確認
SELECT stripe_customer_id FROM billings WHERE id = '<billing_id>';

-- webhook送信時に正しいcustomer_idを指定
stripe trigger customer.subscription.deleted \
  --override customer:id=<正しいcustomer_id>
```

### Webhook が重複処理される

**症状:** 同じevent_idで複数回処理される

**原因:** 冪等性チェックが機能していない

**確認:**

```sql
-- webhook_eventsテーブルを確認
SELECT event_id, COUNT(*)
FROM webhook_events
GROUP BY event_id
HAVING COUNT(*) > 1;
```

**対処:** UNIQUE制約が設定されているか確認

```sql
SELECT constraint_name, constraint_type
FROM information_schema.table_constraints
WHERE table_name = 'webhook_events'
  AND constraint_type = 'UNIQUE';
```

---

## 📊 実際のStripe環境でのテスト

### 前提条件

1. Stripe Testモードを使用
2. テスト用のCustomerとSubscriptionを作成済み

### 手順

#### Step 1: テストサブスクリプションを作成

Stripe Dashboard → Customers → Create customer → Add subscription

または CLI:

```bash
# Customer作成
stripe customers create \
  --email test@example.com \
  --name "E2E Test Customer" \
  --test-mode

# Subscription作成
stripe subscriptions create \
  --customer cus_xxxxxxxxxxxxx \
  --items[0][price]=price_xxxxxxxxxxxxx \
  --test-mode
```

#### Step 2: データベースに登録

```sql
UPDATE billings
SET
    stripe_customer_id = 'cus_xxxxxxxxxxxxx',
    stripe_subscription_id = 'sub_xxxxxxxxxxxxx',
    billing_status = 'active'
WHERE id = '<billing_id>';
```

#### Step 3: Subscriptionをキャンセル

Stripe Dashboard → Subscriptions → Cancel subscription

または CLI:

```bash
stripe subscriptions cancel sub_xxxxxxxxxxxxx \
  --test-mode
```

#### Step 4: Webhook受信を確認

```bash
# Webhook forwarding実行中
stripe listen --forward-to http://localhost:8000/api/v1/webhooks/stripe
```

Stripe Dashboardで「Cancel subscription」をクリックすると、自動的にwebhookが送信されます。

---

## 🎯 試験結果の記録

### テストケース1: canceling → canceled

| 項目 | 期待値 | 実際の値 | 結果 |
|------|--------|----------|------|
| billing_status | canceled | | ☐ |
| scheduled_cancel_at | NULL | | ☐ |
| webhook_event記録 | success | | ☐ |
| 監査ログ記録 | あり | | ☐ |

### テストケース2: active → canceled

| 項目 | 期待値 | 実際の値 | 結果 |
|------|--------|----------|------|
| billing_status | canceled | | ☐ |
| webhook_event記録 | success | | ☐ |
| 監査ログ記録 | あり | | ☐ |

---

## 📚 参考リンク

- [Stripe CLI Documentation](https://stripe.com/docs/stripe-cli)
- [Stripe Webhooks Testing](https://stripe.com/docs/webhooks/test)
- [Stripe Events API](https://stripe.com/docs/api/events)
- [Stripe Subscriptions Lifecycle](https://stripe.com/docs/billing/subscriptions/overview)

---

**作成日**: 2025-12-23
**最終更新**: 2025-12-23
**テスト実施者**: _______
**テスト実施日**: _______
