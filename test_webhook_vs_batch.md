# Webhook vs Batch Processing テスト結果

## 対象Billing

- **Billing ID**: `daae3740-ee95-4967-a34d-9eca0d487dc9`
- **Office ID**: (対応するoffice_id)
- **Current Status**: `early_payment`

## 状況

### App Database
- `trial_end_date`: 2025-12-24 01:32:38 (過去)
- `billing_status`: early_payment

### Stripe Subscription
- Subscription ID: `sub_1ShfqeBxyBErCNcATO1ys9DU`
- `trial_end`: 2026-06-19 00:00:00 (未来)
- `status`: trialing

## 原因

`batch_trigger_setup.py expire` を使用した結果:
- ✅ App DBの `trial_end_date` は過去に変更された
- ❌ Stripeの `trial_end` は変更されていない

## 期待される動作

### Webhook: 発火しない ✅
理由: Stripe側ではまだtrial期間中（2026-06-19まで）

### Batch Processing: 発動する ✅
理由: App側ではtrial期限切れ（2025-12-24 < now）

## テスト手順

### 1. バッチ処理発動条件を確認

```bash
docker exec keikakun_app-backend-1 python3 scripts/batch_trigger_setup.py check
```

期待される出力:
```
2️⃣  Trial期限切れ（early_payment → active）:
   ✅ 発動条件を満たすBilling: 1件
      - Billing ID: daae3740-ee95-4967-a34d-9eca0d487dc9
        Trial End: 2025-12-24 01:32:38
```

### 2. バッチ処理を手動実行

```bash
docker exec keikakun_app-backend-1 python3 -c "
import asyncio
from app.db.session import AsyncSessionLocal
from app.tasks.billing_check import check_trial_expiration

async def main():
    async with AsyncSessionLocal() as db:
        count = await check_trial_expiration(db=db)
        print(f'Updated {count} billing(s)')

asyncio.run(main())
"
```

期待される出力:
```
Updated 1 billing(s)
```

### 3. 結果確認

```bash
docker exec keikakun_app-backend-1 python3 scripts/batch_trigger_setup.py list
```

期待される結果:
- `billing_status`: `early_payment` → `active` ✅

## 結論

これは**Webhook失敗時のフォールバックシナリオ**のテストです:

```
シナリオ: Webhookが発火しない状況でもバッチ処理で正しく遷移する

初期状態: early_payment
   ↓ (Webhookは発火しない: Stripe側でまだtrial期間中)
   ↓ (バッチ処理が検知: App側でtrial期限切れ)
check_trial_expiration()
   ↓
active ✅
```

## Webhook連携をテストしたい場合

Stripe Test Clocksを使用する必要があります:

```bash
# 詳細は以下を参照
cat k_back/scripts/README_STRIPE_TEST_CLOCKS.md
```

Stripe Test Clocksを使えば:
- ✅ Stripe側の時間が進む
- ✅ Webhookが実際に発火する
- ✅ `early_payment → active` がWebhook経由で遷移する

## 参考資料

- `k_back/scripts/README_TESTING_STRATEGY.md`: 包括的なテスト戦略
- `k_back/scripts/README_BATCH_TRIGGER.md`: batch_trigger_setup.pyの使い方
- `k_back/scripts/README_STRIPE_TEST_CLOCKS.md`: Stripe Test Clocksの使い方
