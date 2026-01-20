# Webhook処理 vs バッチ処理の分類

## 📋 目的

Stripe Webhookで完結するものと、アプリ側のバッチ処理（スケジューラー）が必要なものを明確に分類する。

---

## 🎯 分類の原則

### Stripe Webhookで処理すべきもの

**特徴:**
- ユーザーの操作に対する即座の反応が必要
- Stripeでのイベント発生がトリガー
- リアルタイム性が重要

**例:**
- 課金処理（invoice.payment_succeeded）
- 支払い失敗（invoice.payment_failed）
- サブスク削除（customer.subscription.deleted）

### バッチ処理で処理すべきもの

**特徴:**
- 時間経過による自動遷移
- Stripeからのイベントが発生しない
- 定期的なチェックが必要

**例:**
- トライアル期間終了チェック
- スケジュールキャンセル期限チェック
- Webhook失敗時のフォールバック

---

## 📊 完全な分類表

### 1. Stripe Webhookで完結するもの

| イベント | トリガー | 処理内容 | billing_status遷移 | 実装場所 |
|---------|---------|---------|-------------------|---------|
| `customer.subscription.created` | サブスク作成 | - stripe_customer_id保存<br>- stripe_subscription_id保存<br>- subscription_start_date保存 | - | billing_service.py:332-446 |
| `invoice.payment_succeeded` | 初回支払い成功 | - billing_status更新<br>- trial_end_date基準で判定 | free → early_payment<br>free → active | billing_service.py:332-446 |
| `invoice.payment_failed` | 支払い失敗 | - billing_status更新 | any → past_due | billing_service.py:233-327 |
| `customer.subscription.updated` | サブスク更新 | - cancel_at保存<br>- scheduled_cancel_at保存<br>- billing_status更新 | any → canceling<br>canceling → early_payment/free/active | billing_service.py:448-596 |
| `customer.subscription.deleted` | サブスク削除 | - billing_status更新<br>- scheduled_cancel_at削除 | any → canceled | billing_service.py:598-686 |

**バッチ処理は不要:**
- Stripeが確実にイベントを送信する
- リアルタイム性が求められる
- Webhook再送機能がある（失敗時）

---

### 2. バッチ処理が必須なもの

| バッチ処理名 | 実行頻度 | 処理内容 | billing_status遷移 | 理由 | 実装状況 |
|------------|---------|---------|-------------------|------|---------|
| **trial_expiration_check** | 毎日 0:00 UTC | trial_end_date < now<br>かつ billing_status=free<br>を past_due に更新 | free → past_due | Stripeはトライアル終了イベントを送信しない | ✅ 実装済み<br>billing_check.py:18-90 |
| **trial_to_active_check** | 毎日 0:00 UTC | trial_end_date < now<br>かつ billing_status=early_payment<br>を active に更新 | early_payment → active | Stripeはトライアル終了イベントを送信しない | ❌ 未実装<br>（要実装） |

**バッチ処理が必要な理由:**
- Stripeからイベントが送信されない
- 時間経過による自動遷移が必要
- アプリ側で定期的にチェックする必要がある

**なぜStripeがイベントを送信しないのか:**
- `trial_end_date`はアプリ側の概念（Stripe側では`trial_end`として存在するが、イベントは送信されない）
- トライアル終了は課金開始のタイミングであり、Stripeは`invoice.created`イベントを送信する
- しかし、`billing_status`の更新はアプリ側のロジックなので、アプリ側で処理する必要がある

---

### 3. バッチ処理が推奨されるもの（Webhook失敗時のフォールバック）

| バッチ処理名 | 実行頻度 | 処理内容 | billing_status遷移 | 理由 | 実装状況 |
|------------|---------|---------|-------------------|------|---------|
| **scheduled_cancel_check** | 毎日 0:05 UTC | scheduled_cancel_at < now<br>かつ billing_status=canceling<br>を canceled に更新 | canceling → canceled | Webhook失敗時のフォールバック<br>データ整合性の保証 | ❌ 未実装<br>（推奨） |

**バッチ処理が推奨される理由:**
- 通常はWebhookで処理される（99%のケース）
- しかし、Webhook失敗時（1%のケース）にデータ不整合が発生
- バッチ処理でフォールバックすることで、データ整合性を保証

**Webhook失敗のシナリオ:**
1. scheduled_cancel_at = 2026-06-19 に設定
2. 2026-06-19 になると、Stripeが `customer.subscription.deleted` を送信
3. **しかし、ネットワーク障害でWebhookが届かない**
4. billing_status = canceling のまま残る
5. バッチ処理が scheduled_cancel_at < now を検知
6. billing_status = canceled に更新

---

## 🔍 詳細分析: 各イベントの処理フロー

### 1. customer.subscription.created（Webhook処理）

**トリガー:**
- ユーザーが課金設定を完了
- Stripeでサブスクリプションが作成される

**処理フロー:**
```
1. Stripe → Webhook送信
2. バックエンド → Webhook受信
3. billing_service.py:process_subscription_created()
   - stripe_customer_id保存
   - stripe_subscription_id保存
   - subscription_start_date保存
4. 監査ログ記録
5. commit
```

**billing_status遷移:**
- なし（次のinvoice.payment_succeededで遷移）

**バッチ処理:**
- 不要

---

### 2. invoice.payment_succeeded（Webhook処理）

**トリガー:**
- 初回支払いが成功
- または、定期支払いが成功

**処理フロー:**
```
1. Stripe → Webhook送信
2. バックエンド → Webhook受信
3. billing_service.py:process_payment_succeeded()
   - trial_end_date > now かチェック
   - early_payment または active を判定
   - billing_status更新
4. 監査ログ記録
5. commit
```

**billing_status遷移:**
- trial期間中: free → early_payment
- trial期間外: free → active

**バッチ処理:**
- 不要（Webhookで完結）

---

### 3. trial_end_date到達（バッチ処理必須）

**トリガー:**
- 時間経過（trial_end_date < now）

**処理フロー:**
```
1. スケジューラー → 毎日 0:00 UTC に実行
2. billing_check.py:check_trial_expiration()
   - trial_end_date < now かつ billing_status=free を検索
   - billing_status = past_due に更新
3. 監査ログ記録
4. commit
```

**billing_status遷移:**
- free → past_due

**Webhookでは処理できない理由:**
- Stripeはトライアル終了イベントを送信しない
- トライアル終了は時間経過によるものであり、ユーザー操作ではない

**未実装の遷移:**
- early_payment → active（要実装）

---

### 4. customer.subscription.updated（Webhook処理）

**トリガー:**
- ユーザーがキャンセル予定を設定
- または、キャンセル予定を解除

**処理フロー:**
```
1. Stripe → Webhook送信
2. バックエンド → Webhook受信
3. billing_service.py:process_subscription_updated()
   - cancel_at をチェック
   - scheduled_cancel_at保存
   - billing_status = canceling に更新
4. 監査ログ記録
5. commit
```

**billing_status遷移:**
- cancel設定時: any → canceling
- cancel解除時: canceling → early_payment/free/active

**バッチ処理:**
- 不要（Webhookで完結）

---

### 5. scheduled_cancel_at到達（バッチ処理推奨）

**トリガー:**
- 時間経過（scheduled_cancel_at < now）

**通常の処理フロー（99%）:**
```
1. scheduled_cancel_at到達
2. Stripe → customer.subscription.deleted 送信
3. バックエンド → Webhook受信
4. billing_service.py:process_subscription_deleted()
   - billing_status = canceled に更新
5. commit
```

**Webhook失敗時のフォールバック（1%）:**
```
1. scheduled_cancel_at到達
2. Stripe → customer.subscription.deleted 送信
3. ❌ Webhook受信失敗（ネットワーク障害等）
4. billing_status = canceling のまま残る

--- バッチ処理でカバー ---

5. スケジューラー → 毎日 0:05 UTC に実行
6. billing_check.py:check_scheduled_cancellation()
   - scheduled_cancel_at < now かつ billing_status=canceling を検索
   - billing_status = canceled に更新
7. commit
```

**billing_status遷移:**
- canceling → canceled

**バッチ処理が推奨される理由:**
- Webhook失敗時のフォールバック
- データ整合性の保証

---

## 📝 実装チェックリスト

### ✅ 実装済み

- [x] customer.subscription.created（Webhook）
- [x] invoice.payment_succeeded（Webhook）
- [x] invoice.payment_failed（Webhook）
- [x] customer.subscription.updated（Webhook）
- [x] customer.subscription.deleted（Webhook）
- [x] trial_expiration_check（バッチ: free → past_due）

### ❌ 未実装（要実装）

- [ ] trial_to_active_check（バッチ: early_payment → active）
  - **優先度: 高**
  - **理由**: early_paymentが永遠に残る問題を解決

- [ ] scheduled_cancel_check（バッチ: canceling → canceled）
  - **優先度: 中**
  - **理由**: Webhook失敗時のフォールバック

---

## 🎯 推奨実装順序

### 1. trial_expiration_checkの拡張（最優先）

**修正箇所:**
`k_back/app/tasks/billing_check.py:check_trial_expiration()`

**修正内容:**
```python
# 現在
query = select(Billing).where(
    Billing.billing_status == BillingStatus.free,
    Billing.trial_end_date < now
)

# 修正後
query = select(Billing).where(
    Billing.billing_status.in_([BillingStatus.free, BillingStatus.early_payment]),
    Billing.trial_end_date < now
)

# ステータス更新ロジック
for billing in expired_billings:
    if billing.billing_status == BillingStatus.free:
        new_status = BillingStatus.past_due
    elif billing.billing_status == BillingStatus.early_payment:
        new_status = BillingStatus.active

    await crud.billing.update_status(
        db=db,
        billing_id=billing.id,
        status=new_status
    )
```

**理由:**
- 既存のバッチ処理に1行追加するだけ
- 実装コスト: 低
- 影響: 大（early_paymentが永遠に残る問題を解決）

---

### 2. scheduled_cancel_checkの新規実装（次優先）

**実装箇所:**
`k_back/app/tasks/billing_check.py`

**新規関数:**
```python
async def check_scheduled_cancellation(
    db: AsyncSession,
    dry_run: bool = False
) -> int:
    """
    スケジュールされたキャンセルの期限チェック（定期実行タスク）

    処理内容:
    - scheduled_cancel_at < now かつ billing_status = 'canceling' のレコードを抽出
    - billing_status を 'canceled' に更新
    - 処理件数を返す

    実行頻度: 毎日0:05 UTC（推奨）
    """
    now = datetime.now(timezone.utc)

    query = select(Billing).where(
        Billing.billing_status == BillingStatus.canceling,
        Billing.scheduled_cancel_at.isnot(None),
        Billing.scheduled_cancel_at < now
    )

    result = await db.execute(query)
    expired_cancellations = result.scalars().all()

    if dry_run:
        logger.info(f"[DRY RUN] Would update {len(expired_cancellations)} expired scheduled cancellations")
        return len(expired_cancellations)

    updated_count = 0
    for billing in expired_cancellations:
        await crud.billing.update_status(
            db=db,
            billing_id=billing.id,
            status=BillingStatus.canceled
        )

        logger.warning(
            f"Scheduled cancellation expired (Webhook may have been missed): "
            f"office_id={billing.office_id}, billing_id={billing.id}, "
            f"scheduled_cancel_at={billing.scheduled_cancel_at}"
        )

        updated_count += 1

    if updated_count > 0:
        await db.commit()
        logger.info(f"Updated {updated_count} expired scheduled cancellations to canceled")

    return updated_count
```

**スケジューラー登録:**
`k_back/app/scheduler/billing_scheduler.py`

```python
async def scheduled_cancellation_check():
    async with AsyncSessionLocal() as db:
        try:
            count = await check_scheduled_cancellation(db=db)
            logger.info(
                f"[BILLING_SCHEDULER] Scheduled cancellation check completed: "
                f"{count} billing(s) updated to canceled"
            )
        except Exception as e:
            logger.error(
                f"[BILLING_SCHEDULER] Scheduled cancellation check failed: {e}",
                exc_info=True
            )

def start():
    # 既存のトライアルチェック
    billing_scheduler.add_job(
        scheduled_trial_check,
        trigger=CronTrigger(hour=0, minute=0, timezone='UTC'),
        id='check_trial_expiration',
        replace_existing=True,
        name='トライアル期間終了チェック'
    )

    # 🆕 スケジュールキャンセルチェック
    billing_scheduler.add_job(
        scheduled_cancellation_check,
        trigger=CronTrigger(hour=0, minute=5, timezone='UTC'),
        id='check_scheduled_cancellation',
        replace_existing=True,
        name='スケジュールキャンセル期限チェック'
    )

    billing_scheduler.start()
```

**理由:**
- Webhook失敗時のフォールバック
- データ整合性の保証
- 実装コスト: 中

---

## 📊 まとめ

### Webhook処理（リアルタイム）

| 項目 | 内容 |
|------|------|
| **トリガー** | Stripeでのイベント発生 |
| **処理タイミング** | 即座（数秒以内） |
| **メリット** | リアルタイム性、ユーザー体験の向上 |
| **デメリット** | Webhook失敗時のリスク、時間ベースの遷移不可 |
| **実装箇所** | billing_service.py |

### バッチ処理（定期実行）

| 項目 | 内容 |
|------|------|
| **トリガー** | 時間経過（定期実行） |
| **処理タイミング** | 毎日 0:00 UTC、0:05 UTC |
| **メリット** | 時間ベースの遷移、Webhook失敗時のフォールバック |
| **デメリット** | 最大24時間の遅延 |
| **実装箇所** | billing_check.py、billing_scheduler.py |

### ベストプラクティス

1. **ユーザー操作によるイベント**: Webhookで処理
2. **時間経過による遷移**: バッチ処理で処理
3. **冗長性**: Webhookで処理できるものもバッチでフォールバック

---

**作成日**: 2025-12-23
**最終更新**: 2025-12-23
