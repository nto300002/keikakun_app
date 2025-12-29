# Webhook問題の修正手順

## 🎯 問題の特定結果

### Stripe側の状態
- ✅ Customer作成済み: `cus_TbcyUezfWZm0KY`
- ✅ Subscription作成済み: `sub_1SeTwqBzu2Qn9OhyvVYRyZGL`
- ✅ Price ID: `price_1SdMHLBzu2Qn9OhyuRrZZQmb`

### DB側の状態
- ❌ `stripe_subscription_id`: 空
- ❌ `billing_status`: `free` (本来は `early_payment` であるべき)

### 根本原因
**Webhookエンドポイント未登録**により、`customer.subscription.created` イベントがバックエンドに届かなかった。

---

## ⚠️ 重要な発見: Price ID の不一致

### 現在の.env設定
```bash
STRIPE_PRICE_ID=price_1SdO6OBxyBErCNcALazuDrcu
```

### 実際に作成されたSubscriptionのPrice ID
```bash
price_1SdMHLBzu2Qn9OhyuRrZZQmb
```

**これらは異なるStripeアカウントのPrice IDです！**

- `.env`のPrice: `BxyBErCNcA` アカウント
- 実際のSubscription: `Bzu2Qn9Ohy` アカウント

### 対応が必要
1. `.env`の`STRIPE_PRICE_ID`を正しい値に更新
2. `STRIPE_SECRET_KEY`も同じアカウントのものか確認

---

## 🔧 修正手順

### ステップ1: .env ファイルの更新

```bash
# 正しいPrice IDに更新
# 変更前: STRIPE_PRICE_ID=price_1SdO6OBxyBErCNcALazuDrcu
# 変更後: STRIPE_PRICE_ID=price_1SdMHLBzu2Qn9OhyuRrZZQmb

# .envファイルを編集
nano .env

# または sedで一括置換
sed -i '' 's/STRIPE_PRICE_ID=price_1SdO6OBxyBErCNcALazuDrcu/STRIPE_PRICE_ID=price_1SdMHLBzu2Qn9OhyuRrZZQmb/' .env
```

### ステップ2: STRIPE_SECRET_KEYの確認

```bash
# SECRET_KEYが Bzu2Qn9Ohy アカウントのものか確認
cat .env | grep STRIPE_SECRET_KEY

# 期待値:
# sk_test_51SczUABzu2Qn9Ohy... のような形式
# "Bzu2Qn9Ohy" がキーに含まれていることを確認
```

**確認方法**:
Stripe APIで確認:
```bash
# 現在の設定でPrice IDを取得できるか確認
stripe prices retrieve price_1SdMHLBzu2Qn9OhyuRrZZQmb
```

もしエラーが出る場合は、SECRET_KEYが間違ったアカウントのものです。

---

### ステップ3: Stripe CLIでWebhook転送を開始

```bash
# ローカルバックエンドにWebhookを転送
stripe listen --forward-to localhost:8000/api/v1/billing/webhook

# 出力例:
# > Ready! Your webhook signing secret is whsec_xxxxx
# > 2025-12-15 XX:XX:XX   --> customer.subscription.created [evt_xxxxx]
```

**別ターミナルで**バックエンドを起動:
```bash
# FastAPIサーバー起動
uvicorn app.main:app --reload --port 8000

# またはDocker Composeの場合
docker compose up backend
```

---

### ステップ4: DBのbillingレコードを手動更新

Subscriptionは既にStripe側で作成されているため、DBを手動で更新する必要があります。

#### オプションA: SQLで直接更新（推奨）

```sql
-- billing レコードを更新
UPDATE billings
SET
    stripe_subscription_id = 'sub_1SeTwqBzu2Qn9OhyvVYRyZGL',
    billing_status = 'early_payment',
    subscription_start_date = NOW(),
    updated_at = NOW()
WHERE id = 'daae3740-ee95-4967-a34d-9eca0d487dc9';

-- 結果確認
SELECT
    id,
    stripe_customer_id,
    stripe_subscription_id,
    billing_status,
    subscription_start_date
FROM billings
WHERE id = 'daae3740-ee95-4967-a34d-9eca0d487dc9';
```

#### オプションB: Pythonスクリプトで更新

`fix_billing_record.py` を作成:

```python
"""
Billing レコード手動修正スクリプト
"""
import asyncio
from datetime import datetime, timezone
from uuid import UUID

from app.db.session import AsyncSessionLocal
from app import crud
from app.models.enums import BillingStatus


async def fix_billing_record():
    """
    Webhook未処理のbillingレコードを手動で修正
    """
    billing_id = UUID("daae3740-ee95-4967-a34d-9eca0d487dc9")
    stripe_subscription_id = "sub_1SeTwqBzu2Qn9OhyvVYRyZGL"

    async with AsyncSessionLocal() as db:
        try:
            # billing レコードを取得
            billing = await crud.billing.get(db=db, id=billing_id)

            if not billing:
                print(f"❌ Billing record not found: {billing_id}")
                return

            print(f"📋 Current state:")
            print(f"   - stripe_subscription_id: {billing.stripe_subscription_id}")
            print(f"   - billing_status: {billing.billing_status.value}")
            print(f"   - subscription_start_date: {billing.subscription_start_date}")

            # stripe_subscription_idを更新
            await crud.billing.update_stripe_subscription(
                db=db,
                billing_id=billing_id,
                stripe_subscription_id=stripe_subscription_id,
                subscription_start_date=datetime.now(timezone.utc)
            )

            # billing_statusを early_payment に更新
            # (無料期間中にサブスクリプション登録したため)
            await crud.billing.update_status(
                db=db,
                billing_id=billing_id,
                status=BillingStatus.early_payment
            )

            await db.commit()

            # 更新後の状態を確認
            await db.refresh(billing)

            print(f"\n✅ Update completed:")
            print(f"   - stripe_subscription_id: {billing.stripe_subscription_id}")
            print(f"   - billing_status: {billing.billing_status.value}")
            print(f"   - subscription_start_date: {billing.subscription_start_date}")

        except Exception as e:
            await db.rollback()
            print(f"❌ Error: {e}")
            raise


if __name__ == "__main__":
    asyncio.run(fix_billing_record())
```

**実行**:
```bash
# スクリプトを保存
# k_back/fix_billing_record.py

# 実行
cd /Users/naotoyasuda/workspase/keikakun_app/k_back
python fix_billing_record.py
```

---

### ステップ5: webhook_eventsテーブルにイベント記録（オプション）

冪等性チェックのため、イベントを記録しておくことを推奨:

```sql
-- webhook_eventsテーブルに手動でイベントを記録
INSERT INTO webhook_events (
    event_id,
    event_type,
    source,
    billing_id,
    office_id,
    payload,
    status,
    created_at,
    updated_at
)
VALUES (
    'evt_manual_fix_' || gen_random_uuid()::text,  -- ユニークなイベントID
    'customer.subscription.created',
    'manual_fix',
    'daae3740-ee95-4967-a34d-9eca0d487dc9',
    '0949d359-5e1a-42f3-87da-07b40946efc0',
    '{"subscription_id": "sub_1SeTwqBzu2Qn9OhyvVYRyZGL", "note": "Manually fixed due to webhook not received"}'::jsonb,
    'success',
    NOW(),
    NOW()
);
```

---

### ステップ6: 動作確認

#### 6-1. DBの確認

```sql
SELECT
    id,
    stripe_customer_id,
    stripe_subscription_id,
    billing_status,
    subscription_start_date,
    trial_end_date
FROM billings
WHERE id = 'daae3740-ee95-4967-a34d-9eca0d487dc9';
```

**期待される結果**:
- `stripe_subscription_id`: `sub_1SeTwqBzu2Qn9OhyvVYRyZGL` ✅
- `billing_status`: `early_payment` ✅
- `subscription_start_date`: 2025-12-15 XX:XX:XX ✅

#### 6-2. API動作確認

```bash
# 課金ステータス取得API
curl -X GET http://localhost:8000/api/v1/billing/status \
  -H "Authorization: Bearer YOUR_ACCESS_TOKEN"

# 期待されるレスポンス:
# {
#   "billing_status": "early_payment",
#   "trial_end_date": "2026-06-01T00:36:47.636267+00:00",
#   "next_billing_date": null,
#   "current_plan_amount": 6000
# }
```

#### 6-3. フロントエンド確認

```
1. http://localhost:3000/admin/plan にアクセス
2. 課金ステータスが「課金完了 💳」と表示されることを確認
3. 「無料期間終了まで残りXX日」が表示されることを確認
```

---

### ステップ7: 今後のWebhook設定

#### ローカル開発環境

**毎回バックエンド起動時に実行**:
```bash
# ターミナル1: Webhook転送
stripe listen --forward-to localhost:8000/api/v1/billing/webhook

# ターミナル2: バックエンド起動
docker compose up backend
# または
uvicorn app.main:app --reload --port 8000
```

#### ステージング/本番環境

Stripe Dashboardでエンドポイントを登録:
```
1. Stripe Dashboard → Developers → Webhooks
2. Add endpoint をクリック
3. Endpoint URL: https://your-backend-url.run.app/api/v1/billing/webhook
4. イベント選択:
   - customer.subscription.created
   - customer.subscription.deleted
   - invoice.payment_succeeded
   - invoice.payment_failed
5. Signing Secretをコピーして環境変数に設定
```

---

## ✅ チェックリスト

修正完了後、以下を確認:

- [ ] `.env`の`STRIPE_PRICE_ID`を`price_1SdMHLBzu2Qn9OhyuRrZZQmb`に更新
- [ ] `STRIPE_SECRET_KEY`が同じアカウント（Bzu2Qn9Ohy）のものか確認
- [ ] `STRIPE_WEBHOOK_SECRET`が正しく設定されているか確認
- [ ] Stripe CLIで`stripe listen`を実行
- [ ] DBの`billings`テーブルを手動更新
  - `stripe_subscription_id`: `sub_1SeTwqBzu2Qn9OhyvVYRyZGL`
  - `billing_status`: `early_payment`
- [ ] API で課金ステータスが正しく取得できるか確認
- [ ] フロントエンドで「課金完了」バッジが表示されるか確認
- [ ] 今後の開発では必ず`stripe listen`を起動する

---

## 🚨 注意事項

### Price IDについて

今回、2つの異なるPrice IDが見つかりました:
- `.env`: `price_1SdO6OBxyBErCNcALazuDrcu` (BxyBErCNcAアカウント)
- 実際のSubscription: `price_1SdMHLBzu2Qn9OhyuRrZZQmb` (Bzu2Qn9Ohyアカウント)

**これは異なるStripeアカウントを示しています。**

今後、以下を確認してください:
1. どちらのStripeアカウントを使用するか決定
2. 全ての環境変数（SECRET_KEY, WEBHOOK_SECRET, PRICE_ID）を同じアカウントのもので統一
3. 不要なアカウントのデータは削除

---

## 📝 参考資料

- [Stripe CLI Documentation](https://stripe.com/docs/stripe-cli)
- [Webhooks Best Practices](https://stripe.com/docs/webhooks/best-practices)
- [webhook_investigation_steps.md](./webhook_investigation_steps.md)
