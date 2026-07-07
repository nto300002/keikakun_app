# サブスクリプション削除確認ガイド

## 📋 目的

`customer.subscription.deleted` webhook処理後、Stripe上でサブスクリプションが実際に削除されているかを確認する方法

---

## 🔍 確認方法

### 方法1: Stripe Dashboard

1. [Stripe Dashboard](https://dashboard.stripe.com/test/subscriptions) にアクセス
2. Subscriptions → All subscriptions
3. フィルター: Status = Canceled
4. 対象のサブスクリプションを検索
5. ステータスが「Canceled」になっていることを確認

**期待される状態:**
- Status: `Canceled`
- Canceled at: `<キャンセル日時>`
- Cancel at period end: `false`

---

### 方法2: Stripe CLI

#### サブスクリプション詳細を取得

```bash
stripe subscriptions retrieve sub_xxxxxxxxxxxxx --test-mode
```

**期待される出力:**

```json
{
  "id": "sub_xxxxxxxxxxxxx",
  "object": "subscription",
  "status": "canceled",
  "canceled_at": 1640000000,
  "cancel_at": null,
  "cancel_at_period_end": false,
  "customer": "cus_xxxxxxxxxxxxx",
  ...
}
```

**重要なフィールド:**
- `status`: `"canceled"` であること
- `canceled_at`: タイムスタンプが設定されていること
- `cancel_at_period_end`: `false`（即座にキャンセル）

#### すべてのサブスクリプションを一覧表示

```bash
# アクティブなサブスクリプション
stripe subscriptions list --status=active --test-mode

# キャンセルされたサブスクリプション
stripe subscriptions list --status=canceled --test-mode --limit=10
```

---

### 方法3: Pythonスクリプト

以下のスクリプトを使って、サブスクリプションの状態を確認できます。

**ファイル:** `k_back/scripts/verify_stripe_subscription.py`

```python
"""
Stripe サブスクリプション状態確認スクリプト
"""
import stripe
from app.core.config import settings

stripe.api_key = settings.STRIPE_SECRET_KEY


def verify_subscription(subscription_id: str) -> dict:
    """
    サブスクリプションの状態を確認

    Args:
        subscription_id: Stripe Subscription ID

    Returns:
        サブスクリプション情報の辞書
    """
    try:
        subscription = stripe.Subscription.retrieve(subscription_id)

        return {
            "id": subscription.id,
            "status": subscription.status,
            "customer": subscription.customer,
            "canceled_at": subscription.canceled_at,
            "cancel_at_period_end": subscription.cancel_at_period_end,
            "current_period_end": subscription.current_period_end,
            "items": [
                {
                    "price_id": item.price.id,
                    "quantity": item.quantity
                }
                for item in subscription["items"]["data"]
            ]
        }

    except stripe.error.InvalidRequestError as e:
        if "No such subscription" in str(e):
            return {
                "error": "Subscription not found",
                "subscription_id": subscription_id,
                "note": "This may indicate the subscription was deleted."
            }
        raise


def verify_customer_subscriptions(customer_id: str) -> list:
    """
    カスタマーの全サブスクリプションを確認

    Args:
        customer_id: Stripe Customer ID

    Returns:
        サブスクリプションリスト
    """
    try:
        subscriptions = stripe.Subscription.list(
            customer=customer_id,
            limit=100
        )

        return [
            {
                "id": sub.id,
                "status": sub.status,
                "canceled_at": sub.canceled_at,
                "current_period_end": sub.current_period_end
            }
            for sub in subscriptions.data
        ]

    except stripe.error.InvalidRequestError as e:
        if "No such customer" in str(e):
            return {
                "error": "Customer not found",
                "customer_id": customer_id
            }
        raise


if __name__ == "__main__":
    import sys

    if len(sys.argv) < 3:
        print("Usage:")
        print("  python verify_stripe_subscription.py subscription <sub_id>")
        print("  python verify_stripe_subscription.py customer <cus_id>")
        sys.exit(1)

    command = sys.argv[1]
    id_value = sys.argv[2]

    if command == "subscription":
        result = verify_subscription(id_value)
        print("Subscription Info:")
        for key, value in result.items():
            print(f"  {key}: {value}")

    elif command == "customer":
        result = verify_customer_subscriptions(id_value)
        print(f"Customer Subscriptions ({len(result)}):")
        for i, sub in enumerate(result, 1):
            print(f"\n{i}. Subscription {sub['id']}:")
            for key, value in sub.items():
                print(f"     {key}: {value}")

    else:
        print(f"Unknown command: {command}")
        sys.exit(1)
```

**使用方法:**

```bash
# Dockerコンテナ内で実行
docker exec keikakun_app-backend-1 python scripts/verify_stripe_subscription.py subscription sub_xxxxxxxxxxxxx

# ローカルで実行
cd k_back
python scripts/verify_stripe_subscription.py subscription sub_xxxxxxxxxxxxx
```

**期待される出力（削除済みサブスクリプション）:**

```
Subscription Info:
  id: sub_xxxxxxxxxxxxx
  status: canceled
  customer: cus_xxxxxxxxxxxxx
  canceled_at: 1640000000
  cancel_at_period_end: False
  current_period_end: 1642592000
  items: []
```

**期待される出力（サブスクリプション未存在）:**

```
Subscription Info:
  error: Subscription not found
  subscription_id: sub_xxxxxxxxxxxxx
  note: This may indicate the subscription was deleted.
```

---

## 🧪 E2Eテストでの確認フロー

### 統合テストケース

1. **データベースで状態を確認**
   ```sql
   SELECT billing_status, stripe_subscription_id
   FROM billings
   WHERE id = '<billing_id>';
   ```
   期待値: `billing_status = 'canceled'`

2. **Stripe APIで削除を確認**
   ```bash
   stripe subscriptions retrieve <subscription_id> --test-mode
   ```
   期待値: `status = "canceled"`

3. **Webhook eventを確認**
   ```sql
   SELECT event_type, status
   FROM webhook_events
   WHERE event_type = 'customer.subscription.deleted'
   ORDER BY processed_at DESC
   LIMIT 1;
   ```
   期待値: `status = 'success'`

4. **監査ログを確認**
   ```sql
   SELECT action, details
   FROM audit_logs
   WHERE action = 'billing.subscription_canceled'
   ORDER BY timestamp DESC
   LIMIT 1;
   ```
   期待値: レコードが存在すること

---

## 📊 サブスクリプション状態の一覧

| Stripe Status | 意味 | billing_statusとの対応 |
|--------------|------|----------------------|
| `incomplete` | 支払い未完了 | - |
| `incomplete_expired` | 支払い期限切れ | - |
| `trialing` | トライアル中 | `free` or `early_payment` |
| `active` | 有効 | `active` or `early_payment` |
| `past_due` | 支払い遅延 | `past_due` |
| `canceled` | キャンセル済み | `canceled` |
| `unpaid` | 未払い | `past_due` |

---

## 🎯 チェックリスト

### サブスクリプション削除確認

- [ ] Stripe Dashboard でステータスが `Canceled` になっている
- [ ] `canceled_at` タイムスタンプが設定されている
- [ ] `cancel_at_period_end` が `false` である
- [ ] データベースの `billing_status` が `canceled` である
- [ ] `webhook_events` テーブルに成功レコードがある
- [ ] `audit_logs` テーブルに記録がある

### トラブル発生時

- [ ] Stripe CLI で subscription を retrieve できるか確認
- [ ] Customer が存在するか確認（`stripe customers retrieve`）
- [ ] Webhook secret が正しく設定されているか確認
- [ ] アプリケーションログにエラーがないか確認

---

## 🚨 注意事項

1. **Test Mode と Live Mode を混同しない**
   - 開発・テスト時は必ず Test Mode を使用
   - Live Mode のデータは本番環境のため、注意が必要

2. **Webhook の冪等性**
   - 同じ event_id が複数回送信される可能性がある
   - データベースの UNIQUE 制約で重複処理を防止

3. **削除されたサブスクリプションの扱い**
   - Stripe では削除されたサブスクリプションも取得可能（`status=canceled`）
   - データベースでは `billing_status=canceled` として保持

---

**作成日**: 2025-12-23
**最終更新**: 2025-12-23
