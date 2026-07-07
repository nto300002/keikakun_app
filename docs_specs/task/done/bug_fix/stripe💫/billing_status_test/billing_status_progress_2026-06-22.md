# Billing Status 進捗記録 2026-06-22

## 目的

Stripe課金状態のうち、`trial_expired` / `payment_failed` / `canceled` の意味を分離し、Webhook順序やStripe自動削除による誤った状態遷移を抑える。

## 現時点の設計判断

- `trial_expired`
  - 無料期間が終了し、まだ有効な課金契約がない状態。
  - Checkout画面で即時決済に失敗しただけでは `payment_failed` にしない。

- `payment_failed`
  - 継続課金中、またはtrial終了後にStripeが請求書を作成し、`invoice.payment_failed` が発生した状態。
  - 単なるCheckout入力中の `payment_intent.payment_failed` / `charge.failed` は含めない。

- `canceled`
  - 通常のSubscription削除・解約完了を表す。
  - ただし、直近の `invoice.payment_failed` 直後にStripeが `customer.subscription.deleted` を送る場合は、ユーザー解約ではなく支払い失敗起因の自動削除として扱い、`payment_failed` を優先する。

## 確認済みのStripe挙動

### Checkout画面でのカード拒否

- 失敗カードをCheckout画面で入力すると、主に以下が発生する。
  - `payment_intent.payment_failed`
  - `payment_intent.canceled`
  - `charge.failed`
- このケースはSubscriptionの継続請求失敗ではないため、`payment_failed` には含めない。

### Test Clock + trial付きSubscription + 失敗カード

- Customerのdefault payment methodに失敗カードを設定し、trial付きSubscriptionを作成してTest Clockを進めると、trial終了後に `invoice.payment_failed` が発生する。
- 確認例:
  - `invoice.payment_failed`
  - `customer.subscription.deleted`
  - `invoice.payment_failed`
- この場合、現行実装では `invoice.payment_failed` で `payment_failed` になった後、`customer.subscription.deleted` が無条件で `canceled` に上書きしていた。

## 実装済み

### Webhookデバッグログ追加

- Webhook入口で以下をログ出力する。
  - `event_type`
  - `object_id`
  - `customer`
  - `subscription`
  - `payment_intent`
  - `invoice`
  - `status`

- `customer.subscription.created` で以下をログ出力する。
  - Stripe Subscription payloadの主要値
  - DB上の遷移前status
  - trial判定
  - 遷移先status
  - 例外時のスタックトレース

- `customer.subscription.updated` で以下をログ出力する。
  - `stripe_status`
  - `cancel_at_period_end`
  - `cancel_at`
  - `canceled_at`
  - `cancellation_details.reason`
  - `latest_invoice`
  - 即時canceled判定フラグ

- `customer.subscription.deleted` で以下をログ出力する。
  - 遷移前status
  - 直近 `invoice.payment_failed` の有無
  - 遷移先status

### 支払い失敗起因のSubscription削除を保守的に判定

- `CRUDWebhookEvent.has_recent_successful_event()` を追加。
- `process_subscription_deleted()` で、同一Billingに直近10分以内の成功済み `invoice.payment_failed` がある場合は `payment_failed` を維持する。
- 直近の `invoice.payment_failed` がない通常削除は従来通り `canceled` にする。

## TDD結果

### Red

- 追加テスト:
  - `test_process_subscription_deleted_after_recent_payment_failed_keeps_payment_failed`
- 現行実装では `customer.subscription.deleted` が無条件で `canceled` にするため失敗。

### Green

- `customer.subscription.deleted` の遷移先を以下に分岐。
  - 直近10分以内に同一Billingの `invoice.payment_failed` success がある: `payment_failed`
  - それ以外: `canceled`

### 実行済みテスト

```bash
docker exec keikakun_app-backend-1 pytest \
  tests/services/test_billing_service.py::TestBillingServiceTransactionIntegrity::test_process_subscription_deleted_after_recent_payment_failed_keeps_payment_failed \
  tests/services/test_billing_service.py::TestBillingServiceTransactionIntegrity::test_process_subscription_deleted_sets_canceled \
  -q
```

結果:

- `2 passed`
- `15 warnings`

## 更新済みチェックリスト

- `billing_status_test.md`
  - `payment_failed` は継続課金中の請求失敗として定義。
  - Checkout即時決済失敗は `payment_failed` に含めない。
  - 直近10分以内に同一Billingの `invoice.payment_failed` がある `customer.subscription.deleted` は `payment_failed` を維持する要件を追加。

## 残タスク

- localでTest Clockシナリオを再実行し、`invoice.payment_failed -> customer.subscription.deleted` 後にDBが `payment_failed` のままになることを手動確認する。
- `customer.subscription.created` が500になる原因を、追加ログで確認する。
- `payment_intent.payment_failed` / `charge.failed` をWebhook購読対象にする場合、status更新せずログ記録のみでよいか実装方針を決める。
- Frontendで `payment_failed` 表示と導線が期待通りか確認する。
- prod環境で同じWebhook順序が発生した場合の確認手順を整理する。
