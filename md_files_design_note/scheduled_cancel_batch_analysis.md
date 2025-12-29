# scheduled_cancel_at 過去日付チェックの未実装分析

## 📋 現状の実装

### 既存のバッチ処理

**ファイル**: `k_back/app/scheduler/billing_scheduler.py`

現在、以下のバッチ処理が実装されている:

```python
# 毎日 0:00 UTC に実行
async def scheduled_trial_check():
    """トライアル期間終了チェック"""
    count = await check_trial_expiration(db=db)
```

**処理内容** (`k_back/app/tasks/billing_check.py:18-90`):
```python
# billing_status = 'free' かつ trial_end_date < now
# → billing_status = 'past_due' に更新
```

### 問題点: scheduled_cancel_at のチェックが未実装

**現状**:
- `billing_status = canceling` かつ `scheduled_cancel_at < now` のレコード
- → **何も処理されない**（`canceling` のまま残る）

**期待される動作**:
- `billing_status = canceling` かつ `scheduled_cancel_at < now` のレコード
- → `billing_status = canceled` に自動更新されるべき

## 🔍 なぜ未実装なのか (推測)

### 理由1: Stripeのwebhookに依存する設計

**前提**:
- Stripeで `cancel_at` が設定されると、その日時に `customer.subscription.deleted` イベントが送信される
- このイベントを受信することで、`billing_status = canceled` に更新される想定

**実装**: `k_back/app/services/billing_service.py:577-680`
```python
async def process_subscription_deleted(...):
    """customer.subscription.deleted Webhookを処理"""
    # billing_status = canceled に更新
```

**問題**:
- Webhookは**100%保証されていない**
  - ネットワーク障害で遅延する可能性
  - Stripe側の問題で送信されない可能性
  - アプリケーション側の受信失敗の可能性
- Webhookが失敗した場合、永遠に `canceling` のまま残る

### 理由2: 最近追加された機能

**経緯**:
1. `scheduled_cancel_at` カラムは今回の実装で追加された（`p7q8r9s0t1u2_add_scheduled_cancel_at_to_billings.py`）
2. トライアル期間終了チェックは既存の機能
3. スケジュールキャンセルチェックは、まだバッチ処理に組み込まれていない

**タイミング**:
- 新機能追加時に、バッチ処理の追加が漏れた可能性
- または、後続のタスクとして計画されている可能性

### 理由3: 優先度の判断

**トライアル期間終了チェック**:
- **必須**: Webhookなしで、アプリケーション側で必ずチェックする必要がある
- Stripeからは「トライアル終了」のイベントは来ない
- 理由: トライアルはStripe側のサブスクリプションではなく、アプリ側の概念

**スケジュールキャンセルチェック**:
- **準必須**: Webhookで通常は処理されるが、フォールバック機能として必要
- Stripeから `customer.subscription.deleted` が来る想定
- 優先度が下がった可能性

### 理由4: 楽観的な設計

**想定**:
- Stripeのwebhookは信頼性が高い
- ほとんどのケースでwebhookが正常に処理される
- レアケースに対応する必要性を低く見積もった

**現実**:
- Webhookの遅延は実際に発生する（数秒〜数分）
- 極稀に送信されないケースもある
- 冗長性を持たせるべき

## 📊 影響範囲の分析

### シナリオ1: Webhook正常受信 (99%のケース)

```
1. ユーザーがキャンセル操作
   → billing_status = canceling, scheduled_cancel_at = 2025-12-31

2. 2025-12-31 になると、Stripeが customer.subscription.deleted を送信

3. Webhookを受信
   → billing_status = canceled

✅ 問題なし
```

### シナリオ2: Webhook受信失敗 (1%のケース)

```
1. ユーザーがキャンセル操作
   → billing_status = canceling, scheduled_cancel_at = 2025-12-31

2. 2025-12-31 になると、Stripeが customer.subscription.deleted を送信

3. ❌ Webhookが届かない（ネットワーク障害、サーバーダウン等）

4. 現在日: 2026-01-05
   → billing_status = canceling のまま ⚠️
   → ユーザーには「キャンセル予定」と表示される
   → 実際にはStripe側では既に削除されている

⚠️ 問題: データの不整合
```

### ユーザーへの影響

| 項目 | 期待される状態 | 実際の状態 |
|------|---------------|-----------|
| Stripe | Subscription deleted | Subscription deleted ✅ |
| DB | billing_status = canceled | billing_status = canceling ❌ |
| UI | 「キャンセル済み」 | 「キャンセル予定」 ❌ |
| 機能 | 読み取り専用モード | 通常利用可能 ❌ |

## ✅ 正しい実装

### 実装すべき機能

**バッチ処理の追加**: `k_back/app/tasks/billing_check.py`

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

    実行頻度: 毎日0:00 UTC（推奨）

    Args:
        db: データベースセッション
        dry_run: Trueの場合は更新せず、対象件数のみ返す（テスト用）

    Returns:
        int: 更新したBillingの件数
    """
    now = datetime.now(timezone.utc)

    # スケジュールキャンセルが過去日付のBillingを取得
    query = select(Billing).where(
        Billing.billing_status == BillingStatus.canceling,
        Billing.scheduled_cancel_at.isnot(None),
        Billing.scheduled_cancel_at < now
    )

    result = await db.execute(query)
    expired_cancellations = result.scalars().all()

    if dry_run:
        logger.info(
            f"[DRY RUN] Would update {len(expired_cancellations)} expired scheduled cancellations"
        )
        return len(expired_cancellations)

    # ステータス更新
    updated_count = 0
    for billing in expired_cancellations:
        await crud.billing.update_status(
            db=db,
            billing_id=billing.id,
            status=BillingStatus.canceled
        )

        logger.warning(
            f"Scheduled cancellation expired (Webhook may have been missed): "
            f"office_id={billing.office_id}, "
            f"billing_id={billing.id}, "
            f"scheduled_cancel_at={billing.scheduled_cancel_at}"
        )

        updated_count += 1

    # コミット
    if updated_count > 0:
        await db.commit()
        logger.info(f"Updated {updated_count} expired scheduled cancellations to canceled")

    return updated_count
```

**スケジューラーへの追加**: `k_back/app/scheduler/billing_scheduler.py`

```python
async def scheduled_cancellation_check():
    """
    スケジュールされたキャンセルの期限チェック

    実行頻度: 毎日 0:00 UTC
    処理内容: scheduled_cancel_at が過去で billing_status = 'canceling' のレコードを canceled に更新
    """
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
    """スケジューラーを開始"""
    # トライアル期間終了チェック - 毎日 0:00 UTC に実行
    billing_scheduler.add_job(
        scheduled_trial_check,
        trigger=CronTrigger(hour=0, minute=0, timezone='UTC'),
        id='check_trial_expiration',
        replace_existing=True,
        name='トライアル期間終了チェック'
    )

    # 🆕 スケジュールキャンセル期限チェック - 毎日 0:05 UTC に実行
    billing_scheduler.add_job(
        scheduled_cancellation_check,
        trigger=CronTrigger(hour=0, minute=5, timezone='UTC'),
        id='check_scheduled_cancellation',
        replace_existing=True,
        name='スケジュールキャンセル期限チェック'
    )

    billing_scheduler.start()
    logger.info(
        "[BILLING_SCHEDULER] Started successfully\n"
        "  - check_trial_expiration: Daily at 0:00 UTC\n"
        "  - check_scheduled_cancellation: Daily at 0:05 UTC"  # 🆕
    )
```

### メリット

1. **冗長性**: Webhookが失敗しても、バッチ処理でカバーできる
2. **データ整合性**: Stripe側とDB側の状態が必ず一致する
3. **ユーザー体験**: 正確なステータスが表示される
4. **監視**: ログから「Webhook失敗」を検知できる

### 実装の優先度

**優先度: 🟡 推奨**

- 必須ではない（99%のケースでWebhookが正常動作）
- しかし、実装すべき（データ整合性の保証、ユーザー体験の向上）
- 実装コストは低い（既存のパターンを踏襲するだけ）

## 📝 まとめ

### 現状

- ❌ `scheduled_cancel_at` が過去になっても、`canceling` のまま残る
- ✅ Webhookが正常なら問題ない
- ❌ Webhookが失敗すると、データ不整合が発生する

### 未実装の理由（推測）

1. **Webhookに依存する設計**: 通常はWebhookで処理される想定
2. **最近追加された機能**: バッチ処理への組み込みが未完了
3. **優先度の判断**: 必須ではないと判断された可能性
4. **楽観的な設計**: Webhookの信頼性を高く見積もった

### 推奨される対応

**実装すべき**: バッチ処理で `scheduled_cancel_at < now` をチェックし、`canceled` に更新

**理由**:
- Webhookの失敗に対する冗長性を持たせる
- データ整合性を保証する
- ユーザー体験を向上させる
- 実装コストが低い

**実装後の動作**:
- 通常: Webhook受信 → 即座に `canceled`
- Webhook失敗時: 翌日0:05 UTC のバッチ処理 → `canceled` に更新（最大24時間の遅延）
