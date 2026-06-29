# Stripe Test Clock CLI 手動テスト手順

作成日: 2026-06-25

## 目的

Stripe Dashboard の読み込みが遅い場合でも、Stripe CLI で Test Clock / Customer / PaymentMethod / Subscription を作成し、継続課金失敗の Webhook を手動確認できるようにする。

主な確認対象:

- `invoice.payment_failed` が local webhook に到達すること。
- 継続課金中の請求失敗が `billing_status = payment_failed` に遷移すること。
- Checkout 画面での即時カード拒否と、Subscription の継続課金失敗を混同しないこと。

## 前提

- Stripe CLI がログイン済みである。
- local backend が起動している。
- `stripe listen` の転送先は local backend の webhook endpoint に向ける。
- backend の `STRIPE_SECRET_KEY` と Stripe CLI の `--api-key` は同じ Stripe アカウント・同じテスト環境のキーを使う。
- backend の `STRIPE_WEBHOOK_SECRET` は、現在起動している `stripe listen` が表示した `whsec_...` と一致している。
- `.env` を更新した場合、Docker container は restart ではなく recreate する。

```bash
docker compose up -d --force-recreate backend
```

## 注意点

- `stripe listen --api-key ...` は webhook 転送用であり、backend が Checkout / Stripe API を呼ぶキーは backend 側の `STRIPE_SECRET_KEY` である。
- Test Clock の時刻は Stripe 内の時刻であり、backend server の `now()` には影響しない。
- backend の `trial_end_date < now` 判定を使う場合、DB の `trial_end_date` は backend 実時刻基準で過去にしておく必要がある。
- `webhook_events` は原則として受信記録・idempotency 用であり、手動で紐づけるテーブルではない。
- webhook handler は主に `stripe_customer_id` で対象 Billing を検索するため、DB に `stripe_subscription_id` だけを入れても期待どおりに処理されない。

## 1. 環境変数

full secret を履歴やドキュメントに残さないため、shell で環境変数として設定する。

OK - 有効期限に注意
```bash
export STRIPE_API_KEY="sk_test_..."
export STRIPE_PRICE_ID="price_..."
```

## 2. Webhook listener を起動

```bash
stripe listen \
  --api-key "$STRIPE_API_KEY" \
  --forward-to localhost:8000/api/v1/billing/webhook
```

起動時に表示される `whsec_...` を backend の `STRIPE_WEBHOOK_SECRET` に反映する。

`.env` を変更した場合:

```bash
docker compose up -d --force-recreate backend
```

## 3. Test Clock を作成

```bash
stripe test_helpers test_clocks create \
  --api-key "$STRIPE_API_KEY" \
  --name "payment_failed_manual_test" \
  --frozen-time 1782105600
```

戻り値の `id` を控える。

```bash
export TEST_CLOCK_ID="clock_..."
```

## 4. Test Clock に紐づく Customer を作成

```bash
stripe customers create \
  --api-key "$STRIPE_API_KEY" \
  --test-clock "$TEST_CLOCK_ID" \
  --email "<対象office/userのメールアドレス>" \
  --name "payment_failed_manual_test"
```

戻り値の `id` を控える。

```bash
export STRIPE_CUSTOMER_ID="cus_..."
```

## 5. 失敗用 PaymentMethod を作成

継続課金失敗を作るため、Stripe の失敗用カードを Customer の default payment method にする。

```bash
stripe payment_methods attach pm_card_chargeCustomerFail \
  --api-key "$STRIPE_API_KEY" \
  --customer "$STRIPE_CUSTOMER_ID"
```

戻り値の `id` を控える。この `id` は `pm_card_chargeCustomerFail` ではなく、Customer に attach された実体の `pm_...` になる。

```bash
export STRIPE_PAYMENT_METHOD_ID="pm_..."
```

Customer の invoice default payment method に設定する。

```bash
stripe customers update "$STRIPE_CUSTOMER_ID" \
  --api-key "$STRIPE_API_KEY" \
  -d "invoice_settings[default_payment_method]=$STRIPE_PAYMENT_METHOD_ID"
```

## 6. trial 付き Subscription を作成

初回作成時に即時失敗させず、trial 終了後の請求で `invoice.payment_failed` を発生させる。

```bash
stripe subscriptions create \
  --api-key "$STRIPE_API_KEY" \
  --customer "$STRIPE_CUSTOMER_ID" \
  --default-payment-method "$STRIPE_PAYMENT_METHOD_ID" \
  -d "items[0][price]=$STRIPE_PRICE_ID" \
  --trial-period-days 1
```

戻り値の `id` を控える。


```bash
export STRIPE_SUBSCRIPTION_ID="sub_..."
```

## 7. DB の対象 Billing を active 相当に整える

手動検証対象の Billing に、作成した Customer / Subscription を紐づける。

重要:

- `stripe_customer_id` を必ず設定する。
- 継続課金失敗の確認では `billing_status = active` を前提にする。
- backend 実時刻基準で trial が終了している状態として扱う場合、`trial_end_date` は過去にする。

```sql
UPDATE billings
SET
  billing_status = 'active',
  stripe_customer_id = '<STRIPE_CUSTOMER_ID>',
  stripe_subscription_id = '<STRIPE_SUBSCRIPTION_ID>',
  trial_end_date = '2026-06-24 00:00:00+00',
  subscription_start_date = now(),
  last_payment_date = now(),
  scheduled_cancel_at = NULL,
  updated_at = now()
WHERE id = '<BILLING_ID>'::uuid;
```

## 8. Test Clock を trial 終了後まで進める

`--frozen-time` は進めたい UTC epoch 秒を指定する。

まず trial 終了時刻まで進める。この段階では、次回請求 invoice が `draft` として作成されるだけで、`invoice.payment_failed` はまだ発生しない場合がある。

```bash
stripe test_helpers test_clocks advance "$TEST_CLOCK_ID" \
  --api-key "$STRIPE_API_KEY" \
  --frozen-time 1782192000
```

Clock が `ready` に戻った後、invoice の `next_payment_attempt` を確認する。

```bash
stripe invoices list \
  --api-key "$STRIPE_API_KEY" \
  --customer "$STRIPE_CUSTOMER_ID" \
  --limit 1
```

次に `next_payment_attempt` より後まで進める。以下は `next_payment_attempt = 1782195600` の場合の例。

```bash
stripe test_helpers test_clocks advance "$TEST_CLOCK_ID" \
  --api-key "$STRIPE_API_KEY" \
  --frozen-time 1782199200
```

期待する Stripe 側イベント:

- `invoice.created`
- `invoice.finalized`
- `invoice.payment_failed`
- 場合により `customer.subscription.updated`
- 設定によっては `customer.subscription.deleted`

## 8.1 今回の観測結果

確認日: 2026-06-25

- `TEST_CLOCK_ID = clock_1Tm2yyBxyBErCNcAiWIAUcPs`
- `STRIPE_CUSTOMER_ID = cus_UlaK3MywP6FYR1`
- `STRIPE_SUBSCRIPTION_ID = sub_1Tm5NlBxyBErCNcALarLanKJ`
- Clock は複数回 `test_helpers.test_clock.advancing` / `ready` になったが、`frozen_time` は `1782192000` のままだった。
- 最新 invoice は `draft` のまま。
- `next_payment_attempt = 1782195600`
- そのため `invoice.payment_failed` は未発生で、DB の `billing_status` は `active` のまま。

この状態では実装の問題ではなく、Test Clock が支払い試行時刻まで進んでいないことが主因。

追加確認:

- Clock を `1782199200` まで進めた。
- Clock は `ready` に戻り、`frozen_time = 1782199200` になった。
- Stripe 側 Subscription は `past_due` になった。
- 最新 invoice は `open` / `attempted = true` / `attempt_count = 1` になった。
- Stripe 側で `invoice.payment_failed` が発生した。
- local webhook は `invoice.payment_failed` を受信し、`webhook_events.status = success` で記録した。
- 対象 Billing は `billing_status = payment_failed` へ遷移した。

## 9. local webhook 到達確認

Stripe CLI の listener で `invoice.payment_failed` が `200` になっていることを確認する。

```text
--> invoice.payment_failed [evt_...]
<-- [200] POST http://localhost:8000/api/v1/billing/webhook [evt_...]
```

DB では対象 Customer / Billing の webhook を確認する。

```sql
SELECT
  event_id,
  event_type,
  status,
  billing_id,
  office_id,
  payload,
  error_message,
  created_at
FROM webhook_events
WHERE payload::text LIKE '%<STRIPE_CUSTOMER_ID>%'
   OR billing_id = '<BILLING_ID>'::uuid
ORDER BY created_at DESC
LIMIT 30;
```

## 10. Billing 状態確認

```sql
SELECT
  id,
  billing_status::text,
  stripe_customer_id,
  stripe_subscription_id,
  trial_end_date,
  updated_at
FROM billings
WHERE id = '<BILLING_ID>'::uuid;
```

期待:

- `invoice.payment_failed` が成功処理されている。
- 対象 Billing が `payment_failed` になる。
- `payment_intent.payment_failed` / `charge.failed` だけでは `payment_failed` にしない。

## うまくいかない場合の確認

### Checkout 500 が出る

- backend container が古い `STRIPE_SECRET_KEY` を掴んでいないか確認する。
- `.env` 更新後に `docker compose up -d --force-recreate backend` を実行したか確認する。
- `stripe listen --api-key ...` のキーと backend の `STRIPE_SECRET_KEY` は別経路である点に注意する。

### Webhook が 400 になる

- backend の `STRIPE_WEBHOOK_SECRET` が、現在の `stripe listen` の `whsec_...` と一致しているか確認する。
- `stripe listen` を再起動すると `whsec_...` が変わる場合がある。

### Webhook は来ているが Billing が更新されない

- `billings.stripe_customer_id` が Stripe 側 Customer ID と一致しているか確認する。
- `stripe_subscription_id` だけを合わせても handler が対象 Billing を見つけられない可能性がある。
- `invoice.payment_failed` ではなく、Checkout 即時拒否の `payment_intent.payment_failed` / `charge.failed` だけを見ていないか確認する。

### Test Clock を進めても backend の trial 判定が変わらない

- Test Clock は Stripe 内の時刻だけを進める。
- backend の `trial_end_date < now` は backend 実時刻基準で評価される。
- 必要であれば DB の `trial_end_date` を backend 実時刻より過去に設定する。

## 参照

- Stripe API: Test Clocks  
  https://docs.stripe.com/api/test_clocks
- Stripe Billing testing  
  https://docs.stripe.com/billing/testing
- Stripe CLI  
  https://docs.stripe.com/stripe-cli
