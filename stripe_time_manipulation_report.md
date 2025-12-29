# Stripeの時間操作に関する調査レポート

**調査日時**: 2025-12-24
**調査内容**: アプリからStripeの時間を操作してテストする方法

---

## 🎯 調査結果サマリー

### ✅ 可能です

**Stripe Test Clocks API**を使用して、**アプリからStripeの時間を操作**できます。

---

## 📊 実装内容

### 作成したツール: `stripe_test_clock_manager.py`

以下の操作をアプリから実行できます:

| 機能 | コマンド | 説明 |
|------|---------|------|
| **一覧表示** | `list` | Test Clocksを一覧表示 |
| **作成** | `create --name <name>` | 新しいTest Clockを作成 |
| **時間を進める** | `advance --clock-id <id> --days <N>` | Test Clockの時間を進める |
| **顧客確認** | `customers --clock-id <id>` | Test Clockに紐づいた顧客を表示 |
| **削除** | `delete --clock-id <id>` | Test Clockを削除 |

---

## 🧪 動作確認済み

すべての機能が正常に動作することを確認:

### 1. Test Clock一覧表示 ✅

```bash
docker exec keikakun_app-backend-1 python3 scripts/stripe_test_clock_manager.py list
```

**結果**: 既存の2つのTest Clocksを正常に取得

### 2. Test Clock作成 ✅

```bash
docker exec keikakun_app-backend-1 python3 scripts/stripe_test_clock_manager.py create --name "API Test Clock 2025-12-24"
```

**結果**: Test Clock作成成功（ID: `clock_1ShhZ5BxyBErCNcAc3vT1Ir1`）

### 3. 時間を進める ✅

```bash
docker exec keikakun_app-backend-1 python3 scripts/stripe_test_clock_manager.py advance --clock-id clock_1ShhZ5BxyBErCNcAc3vT1Ir1 --days 1
```

**結果**: 1日進めることに成功（Status: `advancing`）

### 4. Test Clock削除 ✅

```bash
docker exec keikakun_app-backend-1 python3 scripts/stripe_test_clock_manager.py delete --clock-id clock_1ShhZ5BxyBErCNcAc3vT1Ir1
```

**結果**: Test Clock削除成功

---

## 🔧 技術的な実装詳細

### Stripe Python SDK使用

```python
import stripe
from app.core.config import settings

# API Key設定（SecretStr対応）
stripe.api_key = settings.STRIPE_SECRET_KEY.get_secret_value()

# Test Clock作成
test_clock = stripe.test_helpers.TestClock.create(
    frozen_time=int(datetime.now().timestamp()),
    name="Test Clock Name"
)

# 時間を進める
stripe.test_helpers.TestClock.advance(
    test_clock_id,
    frozen_time=int((datetime.now() + timedelta(days=90)).timestamp())
)

# Test Clock一覧取得
test_clocks = stripe.test_helpers.TestClock.list(limit=20)

# 削除
stripe.test_helpers.TestClock.delete(test_clock_id)
```

### SecretStr対応

Pydantic `SecretStr`型に対応:

```python
# ❌ 間違い
stripe.api_key = settings.STRIPE_SECRET_KEY

# ✅ 正しい
stripe.api_key = settings.STRIPE_SECRET_KEY.get_secret_value()
```

---

## 📚 使用方法

### 基本的な使い方

```bash
# 1. Test Clock作成
docker exec keikakun_app-backend-1 python3 scripts/stripe_test_clock_manager.py create --name "Trial Test"

# 2. Test Clock IDをコピー（出力から取得）

# 3. Stripe DashboardまたはアプリでCustomer/Subscription作成
#    → Test Clock IDを紐付ける

# 4. 時間を進める（例: 90日）
docker exec keikakun_app-backend-1 python3 scripts/stripe_test_clock_manager.py advance --clock-id <test_clock_id> --days 90

# 5. Webhookが発火 → アプリの状態を確認
docker exec keikakun_app-backend-1 python3 scripts/batch_trigger_setup.py list

# 6. クリーンアップ
docker exec keikakun_app-backend-1 python3 scripts/stripe_test_clock_manager.py delete --clock-id <test_clock_id>
```

### E2Eテストシナリオ例

**Trial期間中に課金設定 → active遷移**:

```bash
# 1. Test Clock作成
docker exec keikakun_app-backend-1 python3 scripts/stripe_test_clock_manager.py create --name "Trial Test $(date +%Y%m%d)"

# 2. アプリでSubscription作成（Test Clock紐付け、trial: 90日）

# 3. Billingステータス確認
docker exec keikakun_app-backend-1 python3 scripts/batch_trigger_setup.py list
# → billing_status: early_payment

# 4. 90日進める
docker exec keikakun_app-backend-1 python3 scripts/stripe_test_clock_manager.py advance --clock-id <id> --days 90

# 5. Webhook発火を確認
docker logs keikakun_app-backend-1 --tail 50 | grep Webhook
# → invoice.payment_succeeded

# 6. Billingステータス確認
docker exec keikakun_app-backend-1 python3 scripts/batch_trigger_setup.py list
# → billing_status: active ✅
```

---

## 🔄 Test Clocks vs batch_trigger_setup.py

### 2つのツールの使い分け

| テスト対象 | 使用ツール | 理由 |
|----------|-----------|------|
| **Webhook連携** | **stripe_test_clock_manager.py** | Stripe側の時間を進める → Webhook発火 |
| **バッチ処理** | **batch_trigger_setup.py** | アプリ側のDBを変更 → バッチ処理発動 |
| **Webhook失敗時のフォールバック** | **batch_trigger_setup.py** | Webhookが発火しない状況を再現 |

### 詳細比較

| 観点 | Test Clocks Manager | batch_trigger_setup.py |
|------|---------------------|------------------------|
| **操作対象** | Stripe側の時間 | アプリDBの日付 |
| **Webhook発火** | ✅ 実際に発火 | ❌ 発火しない |
| **本番環境に近い** | ✅ 非常に近い | ⚠️ ロジックのみ |
| **free → past_due** | ❌ テスト不可 | ✅ テスト可能 |
| **early_payment → active** | ✅ Webhookで遷移 | ✅ バッチで遷移 |
| **canceling → canceled** | ✅ Webhookで遷移 | ✅ バッチで遷移 |
| **セットアップ** | やや複雑 | 簡単 |

---

## 📝 作成したドキュメント

1. **`stripe_test_clock_manager.py`**:
   - Stripe Test Clocksを操作するスクリプト
   - Test Clock作成、時間操作、削除などの機能

2. **`README_STRIPE_TEST_CLOCK_MANAGER.md`**:
   - スクリプトの使い方ガイド
   - E2Eテストシナリオ例
   - Test Clocks vs batch_trigger_setup.pyの比較

3. **既存ドキュメントとの連携**:
   - `README_TESTING_STRATEGY.md`: 包括的なテスト戦略
   - `README_STRIPE_TEST_CLOCKS.md`: Stripe Dashboard操作ガイド
   - `README_BATCH_TRIGGER.md`: batch_trigger_setup.py使い方

---

## ✅ 結論

### 質問への回答

**Q: Stripeの時間を変更してテストする場合、アプリ上から時間を操作することは可能か**

**A: はい、可能です。**

- Stripe Test Clocks APIを使用
- `stripe_test_clock_manager.py`スクリプトで操作
- Test Clock作成、時間を進める、削除などが可能

### 推奨されるテスト戦略

**Webhook連携のテスト**:
→ **stripe_test_clock_manager.py**を使用

**バッチ処理のテスト**:
→ **batch_trigger_setup.py**を使用

**包括的なテスト（正常系＋異常系）**:
→ **両方**を使用

---

## 🎯 次のステップ

### すぐに試せること

1. **Test Clock一覧を確認**:
   ```bash
   docker exec keikakun_app-backend-1 python3 scripts/stripe_test_clock_manager.py list
   ```

2. **新しいTest Clockを作成**:
   ```bash
   docker exec keikakun_app-backend-1 python3 scripts/stripe_test_clock_manager.py create --name "My Test Clock"
   ```

3. **時間を進めてWebhookをテスト**:
   ```bash
   docker exec keikakun_app-backend-1 python3 scripts/stripe_test_clock_manager.py advance --clock-id <id> --days 90
   ```

### 詳細なガイドは以下を参照

- `k_back/scripts/README_STRIPE_TEST_CLOCK_MANAGER.md`
- `k_back/scripts/README_TESTING_STRATEGY.md`

---

**最終更新**: 2025-12-24
