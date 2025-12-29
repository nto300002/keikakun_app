# Webhook発火テスト: Stripe Test Clocksを使った方法

**目的**: trial_end到達時に`invoice.payment_succeeded` Webhookが発火し、billing_statusが瞬時に更新されることを確認

---

## 🎯 テストシナリオ

### テストしたいフロー

```
Trial期間中 (early_payment)
   ↓
Trial終了 (trial_end到達)
   ↓
Stripe: invoice.payment_succeeded Webhook発火
   ↓
アプリ: Webhookハンドラ実行
   ↓
billing_status: early_payment → active ✅
```

---

## ❌ SQLでの変更では不可能

### 現在の方法（うまくいかない）

```bash
# 1. SQLでtrial_end_dateを変更
UPDATE billings
SET trial_end_date = NOW() - INTERVAL '1 day'
WHERE id = 'daae3740-ee95-4967-a34d-9eca0d487dc9';
```

**問題点**:
- ❌ Stripe側は何も知らない
- ❌ Webhookは発火しない
- ❌ Stripe Subscriptionのtrial_endは変わらない
- ⚠️ バッチ処理でのみ更新される（Webhookテストにならない）

---

## ✅ Stripe Test Clocksを使う（正しい方法）

### ステップ1: Test Clock作成

```bash
docker exec keikakun_app-backend-1 python3 scripts/stripe_test_clock_manager.py create --name "Webhook Test $(date +%Y%m%d)"
```

**出力例**:
```
✅ Test Clock作成完了

📊 作成されたTest Clock:
   Test Clock ID: clock_xxxxx
   Name: Webhook Test 20251225
   Frozen Time: 2025-12-25 02:00:00 UTC
   Status: ready
```

**Test Clock IDをコピー**: `clock_xxxxx`

---

### ステップ2: 新しいSubscriptionを作成（Test Clock紐付け）

**重要**: 既存のSubscriptionにTest Clockは紐付けられません。新しいSubscriptionを作成する必要があります。

#### オプションA: Stripe Dashboard経由

1. **Stripe Dashboard → Customers → Create customer**
   - Name: `Test Customer - Webhook Test`
   - Email: `webhook-test@example.com`
   - **Test clock**: `clock_xxxxx` を選択 ← 重要！

2. **Subscriptions → Create subscription**
   - Customer: 上で作成したCustomer
   - Product: あなたのプラン
   - **Trial period**: 7日（短めに設定してテストしやすく）

#### オプションB: アプリ経由（推奨）

```bash
# 1. 新しいOfficeとBillingを作成（テスト用）
# フロントエンドで新規登録
# → office_id とbilling_idを取得

# 2. Test ClockをStripe Customerに紐付ける必要がある
# → 現在のアプリはTest Clock対応していないため、Stripe Dashboard経由が必要
```

**注意**: 現在のアプリコードはTest Clocksに対応していません。Stripe Dashboard経由で作成する必要があります。

---

### ステップ3: アプリでBillingステータスを確認

```bash
docker exec keikakun_app-backend-1 python3 scripts/batch_trigger_setup.py list
```

**期待される状態**:
```
Billing ID: <新しいbilling_id>
Status: early_payment
Trial End: 2026-01-01 00:00:00 (✅ 残り7日)
Stripe Sub: sub_xxxxx
```

---

### ステップ4: Test Clockで7日進める

```bash
docker exec keikakun_app-backend-1 python3 scripts/stripe_test_clock_manager.py advance --clock-id clock_xxxxx --days 7
```

**出力例**:
```
================================================================================
Test Clock時間を進める
================================================================================

📋 Test Clock情報:
   Test Clock ID: clock_xxxxx
   Name: Webhook Test 20251225
   Current Time: 2025-12-25 02:00:00 UTC
   New Time: 2026-01-01 02:00:00 UTC
   Time Delta: 7日 0時間 0分

⏰ 時間を進めています...

================================================================================
✅ 時間を進めました
================================================================================

📊 更新後の状態:
   Frozen Time: 2026-01-01 02:00:00 UTC
   Status: advancing
```

---

### ステップ5: Webhookが発火したか確認

#### 5-1. Stripe Webhook Logs確認

**Stripe Dashboard → Developers → Webhooks → Logs**

期待されるWebhook:
- `invoice.created`
- `invoice.finalized`
- **`invoice.payment_succeeded`** ← これ！
- `customer.subscription.updated`

#### 5-2. アプリログ確認

```bash
docker logs keikakun_app-backend-1 --tail 100 | grep -i webhook
```

**期待されるログ**:
```
[Webhook:evt_xxxxx] Payment succeeded for customer cus_xxxxx, billing_status=active
```

#### 5-3. アプリのBillingステータス確認

```bash
docker exec keikakun_app-backend-1 python3 scripts/batch_trigger_setup.py list
```

**期待される結果**:
```
Billing ID: <billing_id>
Status: active ✅ (early_payment から遷移)
Trial End: 2026-01-01 00:00:00 (⏰ 期限切れ)
Stripe Sub: sub_xxxxx
```

---

## 📊 Test Clocks vs SQL変更 比較

| 観点 | SQL変更 | Stripe Test Clocks |
|------|---------|-------------------|
| **Stripe側の時間** | ❌ 変わらない | ✅ 進む |
| **Webhook発火** | ❌ 発火しない | ✅ 発火する |
| **invoice.payment_succeeded** | ❌ テスト不可 | ✅ テスト可能 |
| **billing_status更新** | ⚠️ バッチ処理のみ | ✅ Webhook経由で瞬時 |
| **Stripe Subscription状態** | ❌ 変わらない | ✅ 変わる |
| **本番環境に近い** | ❌ 遠い | ✅ 非常に近い |

---

## 🔧 アプリをTest Clocks対応にする（オプション）

現在のアプリはTest Clocksに自動対応していません。対応するには:

### billing_service.pyを修正

```python
async def create_checkout_session_with_customer(
    self,
    db: AsyncSession,
    *,
    billing_id: UUID,
    office_id: UUID,
    office_name: str,
    user_email: str,
    user_id: UUID,
    trial_end_date: datetime,
    stripe_secret_key: str,
    stripe_price_id: str,
    frontend_url: str,
    test_clock_id: Optional[str] = None  # ← 追加
) -> Dict[str, str]:
    try:
        stripe.api_key = stripe_secret_key

        # Customerを作成
        customer_params = {
            "email": user_email,
            "name": office_name,
            "metadata": {
                "office_id": str(office_id),
                "staff_id": str(user_id)
            }
        }

        # Test Clock対応
        if test_clock_id:
            customer_params["test_clock"] = test_clock_id

        customer = stripe.Customer.create(**customer_params)
        # ...
```

**しかし、テストのためには Stripe Dashboard経由が簡単です。**

---

## 🎯 推奨されるテスト戦略

### Webhook連携をテストしたい場合

**Stripe Test Clocks を使う** (今回のケース)

1. Stripe DashboardでTest Clock作成
2. Test ClockをCustomerに紐付けてSubscription作成
3. アプリでbilling_status確認（early_payment）
4. Test Clockで時間を進める
5. Webhookログ確認
6. アプリでbilling_status確認（active）

### バッチ処理をテストしたい場合

**batch_trigger_setup.py を使う**

1. SQLでtrial_end_dateを過去に変更
2. バッチ処理を手動実行
3. billing_statusが更新されることを確認

---

## ✅ まとめ

### 質問への回答

**Q: trial_end_dateを過ぎた時に瞬時にbilling_statusとStripe側の支払い状況を変更したい。SQLで日時を変更してテストしているが反映されない。Stripe Test Clocksが必要か？**

**A: はい、Stripe Test Clocksが必須です。**

理由:
1. SQLでtrial_end_dateを変更しても、**Stripe側は何も知らない**
2. Webhookを発火させるには、**Stripe側の時間を進める**必要がある
3. Stripe Test Clocksで時間を進めることで:
   - Stripe Subscriptionのtrial_endに到達
   - invoice.payment_succeeded Webhook発火
   - アプリのWebhookハンドラ実行
   - billing_status瞬時に更新 ✅

### テスト手順

```bash
# 1. Test Clock作成
docker exec keikakun_app-backend-1 python3 scripts/stripe_test_clock_manager.py create --name "Webhook Test"

# 2. Stripe DashboardでCustomer+Subscription作成（Test Clock紐付け、trial: 7日）

# 3. アプリでステータス確認
docker exec keikakun_app-backend-1 python3 scripts/batch_trigger_setup.py list
# → billing_status: early_payment

# 4. 7日進める
docker exec keikakun_app-backend-1 python3 scripts/stripe_test_clock_manager.py advance --clock-id <clock_id> --days 7

# 5. Webhookログ確認
docker logs keikakun_app-backend-1 --tail 100 | grep -i webhook
# → invoice.payment_succeeded

# 6. アプリでステータス確認
docker exec keikakun_app-backend-1 python3 scripts/batch_trigger_setup.py list
# → billing_status: active ✅
```

---

**最終更新**: 2025-12-25
