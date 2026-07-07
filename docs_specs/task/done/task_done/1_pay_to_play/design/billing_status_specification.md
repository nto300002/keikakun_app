# Billing Status仕様書 - 状態管理の整理

## 📋 目的

`billing_status`の状態遷移を`trial_end_date`を基準に一貫性を持たせる。
また、Stripe Webhookで処理できるものと、アプリ側のバッチ処理（スケジューラー）が必要なものを明確に分類する。

---

## 🎯 想定仕様（ユーザー要求）

### 状態定義

| billing_status | 条件 | 説明 |
|---------------|------|------|
| **free** | 初期状態 | トライアル中、課金設定なし |
| **early_payment** | `trial_end_date > 現在` AND 課金済み | トライアル中に課金設定を完了（先払い） |
| **active** | `trial_end_date < 現在` AND 課金済み | トライアル終了後、通常課金中 |
| **past_due** | `trial_end_date < 現在` AND 課金未処理 | トライアル終了後、支払い失敗 |
| **canceling** | `trial_end_date > 現在` AND サブスク削除予定 | トライアル中にキャンセル予定 |
| **canceled** | `trial_end_date < 現在` AND サブスク削除済み | トライアル終了後にキャンセル完了 |

### 重要な原則

1. **trial_end_dateを状態判定の基準とする**
   - `trial_end_date > 現在` = トライアル期間中
   - `trial_end_date < 現在` = トライアル期間終了後

2. **early_paymentを活用する**
   - トライアル中に課金設定した場合、明確に`early_payment`状態とする
   - トライアル終了時に自動的に`active`に遷移する

3. **状態遷移は2つの方法で実現**
   - **Stripe Webhook**: リアルタイムイベント駆動
   - **バッチ処理**: 定期実行による時間ベースの遷移

---

## 🔄 状態遷移図

```
初期状態
   ↓
[free]
   ↓ invoice.payment_succeeded (trial期間中)
[early_payment]
   ↓ バッチ処理: trial_end_date 到達
[active]
   ↓ invoice.payment_failed
[past_due]
   ↓ customer.subscription.deleted
[canceled]

別ルート:
[free] → invoice.payment_failed → [past_due]
[free] → バッチ処理: trial_end_date 到達 → [past_due]
[early_payment] → customer.subscription.updated (cancel設定) → [canceling]
[canceling] → バッチ処理: scheduled_cancel_at 到達 → [canceled]
```

---

## 📊 現在の実装分析

### ✅ 実装されている状態遷移

| イベント/処理 | 条件 | 遷移元 | 遷移先 | 実装場所 |
|-------------|------|--------|--------|----------|
| `invoice.payment_succeeded` | trial期間中 | free | early_payment | billing_service.py:382 |
| `invoice.payment_succeeded` | trial期間外 | free | active | billing_service.py:382 |
| `invoice.payment_failed` | - | any | past_due | billing_service.py:287 |
| `customer.subscription.updated` | cancel設定 | any | canceling | billing_service.py:517 |
| `customer.subscription.updated` | cancel解除 | canceling | early_payment/free/active | billing_service.py:533-539 |
| `customer.subscription.deleted` | - | any | canceled | billing_service.py:641 |
| バッチ: `check_trial_expiration` | trial_end_date < now | free | past_due | billing_check.py:74 |

### ❌ 未実装の状態遷移（問題点）

| 処理 | 条件 | 遷移元 | 遷移先 | 影響 |
|------|------|--------|--------|------|
| **バッチ: trial終了チェック** | trial_end_date < now | **early_payment** | **active** | ⚠️ トライアル終了後もearly_paymentのまま残る |
| **バッチ: scheduled_cancel到達** | scheduled_cancel_at < now | canceling | canceled | ⚠️ キャンセル予定日を過ぎてもcancelingのまま |
| **Webhook: subscription.updated** | trial_end_date基準の判定 | - | - | ⚠️ trial_end_dateを考慮していない |

---

## 🔴 問題1: early_paymentが活用されていない

### 現状の問題

```
1. ユーザーがトライアル中に課金設定
   → billing_status = early_payment ✅

2. trial_end_date が到達（トライアル終了）
   → バッチ処理が実行される
   → しかし、billing_status = early_payment のまま ❌

3. 結果: 永遠に early_payment のままになる可能性
```

### 原因

`billing_check.py:check_trial_expiration()` は以下の条件でのみ動作:

```python
query = select(Billing).where(
    Billing.billing_status == BillingStatus.free,  # ← freeのみ
    Billing.trial_end_date < now
)
```

**early_payment → active の遷移が実装されていない**

### 解決策

バッチ処理で`early_payment`もチェックする:

```python
query = select(Billing).where(
    Billing.billing_status.in_([BillingStatus.free, BillingStatus.early_payment]),
    Billing.trial_end_date < now
)

# 遷移ロジック
if billing.billing_status == BillingStatus.free:
    new_status = BillingStatus.past_due
elif billing.billing_status == BillingStatus.early_payment:
    new_status = BillingStatus.active
```

---

## 🔴 問題2: scheduled_cancel_atのバッチ処理未実装

### 現状の問題

```
1. ユーザーがキャンセル予定を設定
   → billing_status = canceling ✅
   → scheduled_cancel_at = 2026-06-19 ✅

2. scheduled_cancel_at が到達
   → Webhook: customer.subscription.deleted が送信される（99%のケース）
   → billing_status = canceled ✅

3. しかし、Webhookが失敗した場合（1%のケース）
   → billing_status = canceling のまま ❌
   → scheduled_cancel_at < now でも処理されない
```

### 解決策

バッチ処理を実装:

```python
async def check_scheduled_cancellation(db: AsyncSession) -> int:
    """scheduled_cancel_atが過去になったcancelingをcanceledに更新"""
    now = datetime.now(timezone.utc)

    query = select(Billing).where(
        Billing.billing_status == BillingStatus.canceling,
        Billing.scheduled_cancel_at.isnot(None),
        Billing.scheduled_cancel_at < now
    )

    expired_cancellations = await db.execute(query)

    for billing in expired_cancellations.scalars().all():
        await crud.billing.update_status(
            db=db,
            billing_id=billing.id,
            status=BillingStatus.canceled
        )
```

詳細: `md_files_design_note/scheduled_cancel_batch_analysis.md`

---

## 📂 Webhook処理 vs バッチ処理の分類

### Stripe Webhookで処理できるもの（リアルタイム）

| イベント | トリガー | 処理内容 | 状態遷移 |
|---------|---------|---------|---------|
| `customer.subscription.created` | サブスクリプション作成 | DBに保存 | - |
| `invoice.payment_succeeded` | 支払い成功 | billing_status更新 | free/early_payment → early_payment/active |
| `invoice.payment_failed` | 支払い失敗 | billing_status更新 | any → past_due |
| `customer.subscription.updated` | サブスク更新（キャンセル設定等） | cancel_at保存、status更新 | any → canceling |
| `customer.subscription.deleted` | サブスク削除 | billing_status更新 | any → canceled |

**特徴:**
- ✅ リアルタイムで即座に反映
- ✅ ユーザー操作に対する即座のフィードバック
- ❌ 時間経過による自動遷移は不可能
- ❌ Webhook失敗時のフォールバックなし

### アプリ側バッチ処理が必要なもの（定期実行）

| バッチ処理 | 実行頻度 | 処理内容 | 状態遷移 | 実装状況 |
|----------|---------|---------|---------|---------|
| **trial_expiration_check** | 毎日 0:00 UTC | trial_end_date到達チェック | free → past_due | ✅ 実装済み |
| **trial_to_active_check** | 毎日 0:00 UTC | trial_end_date到達チェック | early_payment → active | ❌ 未実装 |
| **scheduled_cancel_check** | 毎日 0:05 UTC | scheduled_cancel_at到達チェック | canceling → canceled | ❌ 未実装 |

**特徴:**
- ✅ 時間ベースの自動遷移が可能
- ✅ Webhook失敗時のフォールバック機能
- ❌ リアルタイム性なし（最大24時間の遅延）
- ✅ データ整合性の保証

---

## ✅ 推奨実装計画

### 優先度1: trial_expiration_checkの拡張（必須）

**現状:**
```python
# free → past_due のみ
Billing.billing_status == BillingStatus.free
```

**修正後:**
```python
# free → past_due
# early_payment → active
Billing.billing_status.in_([BillingStatus.free, BillingStatus.early_payment])
```

**理由:**
- early_paymentが永遠に残る問題を解決
- 既存のバッチ処理に1行追加するだけ
- 実装コスト: 低

### 優先度2: scheduled_cancel_checkの実装（推奨）

**新規実装:**
```python
async def check_scheduled_cancellation(db: AsyncSession) -> int:
    # canceling → canceled
    # 条件: scheduled_cancel_at < now
```

**理由:**
- Webhook失敗時のフォールバック
- データ整合性の保証
- 実装コスト: 中

### 優先度3: Webhook処理の改善（任意）

**customer.subscription.updated**での判定を追加:

```python
# trial_end_dateを基準にした状態判定を追加
if not cancel_at_period_end and not cancel_at:
    now = datetime.now(timezone.utc)
    is_in_trial = now < billing.trial_end_date
    has_paid = billing.stripe_subscription_id is not None

    if is_in_trial and has_paid:
        status = BillingStatus.early_payment
    elif is_in_trial and not has_paid:
        status = BillingStatus.free
    elif not is_in_trial and has_paid:
        status = BillingStatus.active
    else:
        status = BillingStatus.past_due
```

**理由:**
- より一貫性のある状態管理
- 実装コスト: 中

---

## 📝 まとめ

### 現在の問題点

1. **early_paymentが活用されていない**
   - トライアル終了後も`early_payment`のまま残る
   - `early_payment → active`の遷移がバッチ処理に未実装

2. **scheduled_cancel_atのバッチ処理未実装**
   - Webhook失敗時に`canceling`のまま残る
   - データ不整合のリスク

3. **trial_end_dateを基準にした判定が不一貫**
   - Webhookによっては`trial_end_date`をチェックしない
   - 状態管理の一貫性が欠如

### 推奨される対応

1. **即座に実装すべき**:
   - `check_trial_expiration()`を拡張（early_payment → active）

2. **早期に実装すべき**:
   - `check_scheduled_cancellation()`を新規実装

3. **長期的に改善すべき**:
   - Webhook処理でのtrial_end_date基準の判定追加
   - 状態遷移ロジックの一元化

---

## 🎯 次のステップ

1. ユーザーと仕様を確認・合意
2. 優先度1のバッチ処理拡張を実装
3. テストケースの作成と実行
4. 優先度2のバッチ処理新規実装
5. ドキュメントの更新

---

**作成日**: 2025-12-23
**最終更新**: 2025-12-23
