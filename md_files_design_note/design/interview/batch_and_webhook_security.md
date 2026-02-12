# バッチ処理とWebhookセキュリティ - 面接質問回答

## 質問1: APSchedulerでバッチ処理を実装した際、冪等性はどう担保しましたか？

### 回答サマリー

APSchedulerで実装した定期バッチ処理（トライアル期間終了チェック、スケジュールキャンセルチェック）では、**SQLクエリレベルでの条件付き抽出**と**ステータスベースの状態管理**により冪等性を担保しています。同じタイミングで複数回実行されても、結果が同じになることを保証しています。

---

## 1. バッチ処理の概要

### 実装したバッチ処理

けいかくんアプリでは、課金管理のために2つのバッチ処理を実装しています。

**ファイル**: `k_back/app/scheduler/billing_scheduler.py`

| バッチ処理 | 実行時刻 | 処理内容 |
|----------|---------|---------|
| **トライアル期間終了チェック** | 毎日 0:00 UTC | trial_end_dateが過去のレコードのステータスを更新 |
| **スケジュールキャンセルチェック** | 毎日 0:05 UTC | scheduled_cancel_atが過去のレコードをcanceledに更新 |

### APSchedulerの設定

```python
# k_back/app/scheduler/billing_scheduler.py:65-90
from apscheduler.schedulers.asyncio import AsyncIOScheduler
from apscheduler.triggers.cron import CronTrigger

billing_scheduler = AsyncIOScheduler()

def start():
    """スケジューラーを開始"""

    # トライアル期間終了チェック - 毎日 0:00 UTC に実行
    billing_scheduler.add_job(
        scheduled_trial_check,
        trigger=CronTrigger(hour=0, minute=0, timezone='UTC'),
        id='check_trial_expiration',
        replace_existing=True,  # ← 既存のジョブを置き換え（重複防止）
        name='トライアル期間終了チェック'
    )

    # スケジュールキャンセル期限チェック - 毎日 0:05 UTC に実行
    billing_scheduler.add_job(
        scheduled_cancellation_check,
        trigger=CronTrigger(hour=0, minute=5, timezone='UTC'),
        id='check_scheduled_cancellation',
        replace_existing=True,  # ← 既存のジョブを置き換え（重複防止）
        name='スケジュールキャンセル期限チェック'
    )

    billing_scheduler.start()
```

**重要な設定**:
- `replace_existing=True`: 同じIDのジョブが既に存在する場合は置き換え
- `id`: 一意のジョブID（重複実行防止）

---

## 2. 冪等性担保の実装戦略

### 2.1 トライアル期間終了チェックの冪等性

**ファイル**: `k_back/app/tasks/billing_check.py:18-102`

#### 処理フロー

```
1. 現在時刻を取得（UTC）
   ↓
2. 条件付きSELECT実行
   WHERE:
     - billing_status IN ('free', 'early_payment')
     - trial_end_date < now  ← 期限切れのみ抽出
   ↓
3. 各レコードに対してステータス更新
   - free → past_due
   - early_payment → active
   ↓
4. コミット（1回のみ）
```

#### 実装コード

```python
async def check_trial_expiration(
    db: AsyncSession,
    dry_run: bool = False
) -> int:
    """
    トライアル期間終了チェック（定期実行タスク）

    冪等性の担保:
    - 条件付きクエリで対象レコードを厳密に絞り込み
    - ステータス遷移が明確（free → past_due, early_payment → active）
    - 既にステータスが更新済みのレコードは対象外
    """
    now = datetime.now(timezone.utc)

    # ✅ 冪等性ポイント1: 条件付きSELECT
    # billing_status が 'free' または 'early_payment' のレコードのみ抽出
    # → 既に past_due や active に更新済みのレコードは対象外
    query = select(Billing).where(
        Billing.billing_status.in_([BillingStatus.free, BillingStatus.early_payment]),
        Billing.trial_end_date < now  # ← 期限切れのみ
    )

    result = await db.execute(query)
    expired_billings = result.scalars().all()

    if dry_run:
        # dry_runモード: 実際には更新せず件数のみ返す
        return len(expired_billings)

    # ✅ 冪等性ポイント2: ステータスチェック後に更新
    updated_count = 0
    for billing in expired_billings:
        # 遷移先を判定
        if billing.billing_status == BillingStatus.free:
            new_status = BillingStatus.past_due
        elif billing.billing_status == BillingStatus.early_payment:
            new_status = BillingStatus.active
        else:
            continue  # ← ステータスが想定外の場合はスキップ

        await crud.billing.update_status(
            db=db,
            billing_id=billing.id,
            status=new_status,
            auto_commit=False  # ← まだコミットしない
        )

        logger.info(
            f"Trial expired: office_id={billing.office_id}, "
            f"{billing.billing_status.value} → {new_status.value}"
        )

        updated_count += 1

    # ✅ 冪等性ポイント3: 全更新後に1回だけコミット
    if updated_count > 0:
        await db.commit()

    return updated_count
```

---

### 2.2 スケジュールキャンセルチェックの冪等性

**ファイル**: `k_back/app/tasks/billing_check.py:105-177`

#### 処理フロー

```
1. 現在時刻を取得（UTC）
   ↓
2. 条件付きSELECT実行
   WHERE:
     - billing_status = 'canceling'
     - scheduled_cancel_at IS NOT NULL
     - scheduled_cancel_at < now  ← 期限切れのみ
   ↓
3. 各レコードを 'canceled' に更新
   ↓
4. コミット（1回のみ）
```

#### 実装コード

```python
async def check_scheduled_cancellation(
    db: AsyncSession,
    dry_run: bool = False
) -> int:
    """
    スケジュールされたキャンセルの期限チェック

    冪等性の担保:
    - billing_status = 'canceling' のレコードのみ抽出
    - 既に 'canceled' に更新済みのレコードは対象外
    """
    now = datetime.now(timezone.utc)

    # ✅ 冪等性ポイント1: 条件付きSELECT
    # billing_status = 'canceling' のレコードのみ抽出
    # → 既に canceled に更新済みのレコードは対象外
    query = select(Billing).where(
        Billing.billing_status == BillingStatus.canceling,
        Billing.scheduled_cancel_at.isnot(None),
        Billing.scheduled_cancel_at < now  # ← 期限切れのみ
    )

    result = await db.execute(query)
    expired_cancellations = result.scalars().all()

    if dry_run:
        return len(expired_cancellations)

    # ✅ 冪等性ポイント2: ステータス更新
    updated_count = 0
    for billing in expired_cancellations:
        await crud.billing.update_status(
            db=db,
            billing_id=billing.id,
            status=BillingStatus.canceled,
            auto_commit=False
        )

        logger.warning(
            f"Scheduled cancellation expired (Webhook may have been missed): "
            f"office_id={billing.office_id}, "
            f"scheduled_cancel_at={billing.scheduled_cancel_at}"
        )

        updated_count += 1

    # ✅ 冪等性ポイント3: 全更新後に1回だけコミット
    if updated_count > 0:
        await db.commit()

    return updated_count
```

---

## 3. 冪等性担保の3つの仕組み

### 3.1 条件付きクエリによる対象レコード絞り込み

**実装例**:

```python
# トライアル期間終了チェック
query = select(Billing).where(
    Billing.billing_status.in_([BillingStatus.free, BillingStatus.early_payment]),
    # ↑ 既に past_due や active のレコードは除外される
    Billing.trial_end_date < now
)
```

**効果**:
- 既に処理済み（ステータス更新済み）のレコードは自動的に除外
- 同じタイミングで複数回実行されても、2回目以降は対象レコードが0件になる

**冪等性の証明**:

```
初回実行:
  - billing_status = 'free', trial_end_date = 2025-01-01 00:00:00
  - 条件に一致 → past_due に更新

2回目実行（同日中）:
  - billing_status = 'past_due', trial_end_date = 2025-01-01 00:00:00
  - 条件に不一致（billing_status が free でない） → 更新されない

→ 結果が同じ（冪等）
```

---

### 3.2 ステータスベースの状態管理

**ステータス遷移図**:

```
[トライアル期間終了時]

free (無料トライアル中)
  ↓ トライアル期限切れ
past_due (未課金・期限切れ)

early_payment (トライアル中に課金済み)
  ↓ トライアル期限切れ
active (課金済み・アクティブ)


[キャンセル処理]

active (課金済み・アクティブ)
  ↓ キャンセル予約
canceling (キャンセル予定)
  ↓ キャンセル期限到来
canceled (キャンセル済み)
```

**特徴**:
- 各ステータスは一方向にのみ遷移
- 逆方向への遷移はない（例: past_due → free には戻らない）
- 既に最終ステータスに到達したレコードは再処理されない

---

### 3.3 dry_runモードによるテスト実行

**実装例**:

```python
async def check_trial_expiration(
    db: AsyncSession,
    dry_run: bool = False  # ← dry_runフラグ
) -> int:
    # ... クエリ実行 ...

    if dry_run:
        # 実際には更新せず、対象件数のみ返す
        logger.info(f"[DRY RUN] Would update {len(expired_billings)} expired trials")
        return len(expired_billings)

    # 実際の更新処理
    # ...
```

**効果**:
- 本番実行前に影響範囲を確認可能
- デバッグやテスト時に安全に実行できる
- CI/CDパイプラインでのテスト実行に活用

**使用例**:

```bash
# ドライラン実行（テスト）
docker exec keikakun_app-backend-1 python scripts/test_batch_processing.py --dry-run

# 本番実行
docker exec keikakun_app-backend-1 python scripts/test_batch_processing.py
```

---

## 4. 重複実行防止の仕組み

### 4.1 APSchedulerのジョブID管理

```python
billing_scheduler.add_job(
    scheduled_trial_check,
    trigger=CronTrigger(hour=0, minute=0, timezone='UTC'),
    id='check_trial_expiration',  # ← 一意のジョブID
    replace_existing=True,  # ← 既存ジョブを置き換え
    name='トライアル期間終了チェック'
)
```

**効果**:
- 同じIDのジョブが複数登録されることを防止
- アプリケーション再起動時に二重登録されない

---

### 4.2 データベーストランザクション管理

```python
# ✅ 全更新を1つのトランザクションで実行
updated_count = 0
for billing in expired_billings:
    await crud.billing.update_status(
        db=db,
        billing_id=billing.id,
        status=new_status,
        auto_commit=False  # ← まだコミットしない
    )
    updated_count += 1

# ✅ 全更新後に1回だけコミット
if updated_count > 0:
    await db.commit()
```

**効果**:
- 処理途中でエラーが発生した場合、全ての変更がロールバックされる
- 部分的な更新が残ることを防止

---

## 5. エラーハンドリングと監査ログ

### 5.1 エラー発生時の処理

**ファイル**: `k_back/app/scheduler/billing_scheduler.py:21-42`

```python
async def scheduled_trial_check():
    """トライアル期間終了チェックのスケジュール実行"""
    async with AsyncSessionLocal() as db:
        try:
            count = await check_trial_expiration(db=db)
            logger.info(
                f"[BILLING_SCHEDULER] Trial expiration check completed: "
                f"{count} billing(s) updated"
            )
        except Exception as e:
            # ✅ エラー発生時はロールバック（AsyncSessionLocalのコンテキストマネージャが自動実行）
            logger.error(
                f"[BILLING_SCHEDULER] Trial expiration check failed: {e}",
                exc_info=True  # ← スタックトレースを含めてログ出力
            )
```

**効果**:
- エラー発生時は全ての変更がロールバックされる
- 次回実行時に再試行される
- エラー内容はログに記録される

---

### 5.2 監査ログの記録

```python
logger.info(
    f"Trial expired: office_id={billing.office_id}, "
    f"billing_id={billing.id}, "
    f"trial_end_date={billing.trial_end_date}, "
    f"{billing.billing_status.value} → {new_status.value}"
)
```

**記録内容**:
- 更新対象のoffice_id、billing_id
- 更新前後のステータス
- トライアル期限日時

**用途**:
- デバッグ時の追跡
- 課金トラブルの調査
- 監査要件の充足

---

## 6. 冪等性のテスト戦略

### 6.1 テストケース

**ファイル**: `k_back/tests/tasks/test_billing_check.py`

```python
import pytest
from datetime import datetime, timedelta, timezone

@pytest.mark.asyncio
async def test_check_trial_expiration_idempotency(db_session):
    """
    トライアル期間終了チェックの冪等性テスト

    同じ条件で複数回実行しても結果が同じことを確認
    """
    # 準備: 期限切れのBillingを作成
    billing = await create_billing(
        db=db_session,
        billing_status=BillingStatus.free,
        trial_end_date=datetime.now(timezone.utc) - timedelta(days=1)  # 1日前
    )

    # 1回目実行
    count1 = await check_trial_expiration(db=db_session)
    assert count1 == 1  # ✅ 1件更新

    # 状態確認
    await db_session.refresh(billing)
    assert billing.billing_status == BillingStatus.past_due

    # 2回目実行（冪等性確認）
    count2 = await check_trial_expiration(db=db_session)
    assert count2 == 0  # ✅ 更新件数0（既に処理済み）

    # 状態が変わっていないことを確認
    await db_session.refresh(billing)
    assert billing.billing_status == BillingStatus.past_due  # ✅ 変わらない


@pytest.mark.asyncio
async def test_check_trial_expiration_concurrent_execution(db_session):
    """
    並行実行時の冪等性テスト

    複数のプロセスが同時に実行しても結果が同じことを確認
    """
    import asyncio

    # 準備: 期限切れのBillingを複数作成
    billings = [
        await create_billing(
            db=db_session,
            billing_status=BillingStatus.free,
            trial_end_date=datetime.now(timezone.utc) - timedelta(days=1)
        )
        for _ in range(10)
    ]

    # 並行実行
    results = await asyncio.gather(
        check_trial_expiration(db=db_session),
        check_trial_expiration(db=db_session),
        check_trial_expiration(db=db_session)
    )

    # 合計更新件数が10件以下であることを確認（重複更新なし）
    total_updated = sum(results)
    assert total_updated <= 10

    # 全てのBillingがpast_dueに更新されていることを確認
    for billing in billings:
        await db_session.refresh(billing)
        assert billing.billing_status == BillingStatus.past_due
```

---

## 7. まとめ: バッチ処理の冪等性担保

### 実装した冪等性担保の仕組み

| 手法 | 実装内容 | 効果 |
|------|---------|------|
| **条件付きクエリ** | ステータスと期限で厳密に絞り込み | 既処理レコードを自動除外 |
| **ステータス管理** | 一方向の状態遷移（free → past_due） | 逆戻りなし |
| **ジョブID管理** | APSchedulerのreplace_existing=True | 重複登録防止 |
| **トランザクション** | 全更新を1つのトランザクションで実行 | 部分更新防止 |
| **dry_runモード** | テスト実行機能 | 安全な動作確認 |
| **監査ログ** | 全更新を記録 | 追跡可能性 |

### セキュリティと信頼性

**冪等性の効果**:
- 同じタイミングで複数回実行されても結果が同じ
- バッチ処理の再実行が安全
- エラー後の再試行が可能

**信頼性の向上**:
- トランザクション管理により部分更新を防止
- エラーハンドリングで異常終了時もロールバック
- 監査ログで全変更を追跡可能

---

## 質問2: Stripe Webhookの署名検証はなぜ必要？

### 回答サマリー

Stripe Webhookの署名検証は、**偽装されたWebhookリクエストからアプリケーションを保護**するために必須です。署名検証により、リクエストが本当にStripeから送信されたものであることを暗号学的に証明し、攻撃者による不正な課金ステータス操作を防ぎます。けいかくんアプリでは、署名検証と冪等性チェックを組み合わせて実装しています。

---

## 1. Stripe Webhookとは

### 1.1 Webhookの仕組み

```
┌──────────────┐
│   Stripe     │
│   サーバー   │
└──────┬───────┘
       │ イベント発生
       │ (例: 支払い成功)
       ↓
┌──────────────┐
│   Webhook    │ POST /api/v1/billing/webhook
│   送信       │ Header: Stripe-Signature: xxx
└──────┬───────┘ Body: {"type": "invoice.payment_succeeded", ...}
       ↓
┌──────────────┐
│ けいかくん   │
│ アプリ       │ 署名検証 → イベント処理 → ステータス更新
└──────────────┘
```

### 1.2 処理対象のWebhookイベント

**ファイル**: `k_back/app/api/v1/endpoints/billing.py:265-391`

| イベントタイプ | 処理内容 | ステータス遷移 |
|-------------|---------|-------------|
| `customer.subscription.created` | サブスク作成 | free/early_payment → early_payment/active |
| `invoice.payment_succeeded` | 支払い成功 | early_payment → active |
| `invoice.payment_failed` | 支払い失敗 | active → past_due |
| `customer.subscription.updated` | サブスク更新（キャンセル予約） | active → canceling |
| `customer.subscription.deleted` | サブスクキャンセル | canceling → canceled |

---

## 2. 署名検証が必要な理由

### 2.1 攻撃シナリオ1: 偽装Webhookによる不正課金ステータス操作

**署名検証がない場合の攻撃**:

```python
# 攻撃者が送信する偽装リクエスト
POST https://api.keikakun.com/api/v1/billing/webhook
Content-Type: application/json

{
  "type": "invoice.payment_succeeded",
  "data": {
    "object": {
      "customer": "cus_target_customer_id",  # ← 標的となるCustomer ID
      "subscription": "sub_target_subscription_id",
      "amount_paid": 300000,  # 3000円
      "status": "paid"
    }
  }
}
```

**署名検証なしの場合の被害**:

```
1. 攻撃者が偽装Webhookを送信
   ↓
2. アプリケーションが受信（署名検証なし）
   ↓
3. billing_status を 'active' に更新
   ↓
4. 被害者の事務所が無料で有料プランを使用可能になる
   （実際には課金されていない）
   ↓
5. Stripeから実際の支払いが行われないまま、サービス利用が継続
```

**経済的損失**:
- 月額3000円 × 12ヶ月 × 被害事務所数 = 数十万円〜数百万円の損失

---

### 2.2 攻撃シナリオ2: リプレイ攻撃によるステータス巻き戻し

**署名検証があるが冪等性チェックがない場合の攻撃**:

```
1. 攻撃者が過去の正規Webhookリクエストを盗聴
   （例: invoice.payment_failedイベント）
   ↓
2. 同じリクエストを再送信（リプレイ攻撃）
   ↓
3. 署名は正規なので検証を通過
   ↓
4. billing_status が 'past_due' に巻き戻される
   ↓
5. 被害者の事務所が強制的に機能制限モードになる
```

**被害**:
- サービス妨害（DoS）
- 顧客満足度の低下
- サポート対応コスト増加

---

### 2.3 攻撃シナリオ3: タイミング攻撃によるレースコンディション

**冪等性チェックがない場合の攻撃**:

```
1. 攻撃者が正規Webhookを盗聴
   ↓
2. 同じWebhookを短時間に大量送信
   ↓
3. 複数のリクエストが同時に処理される
   ↓
4. データベースの不整合が発生
   （例: 同じイベントで複数回ステータス更新）
   ↓
5. 課金情報が破損
```

---

## 3. 署名検証の実装

### 3.1 Stripe署名検証の仕組み

**署名生成アルゴリズム（Stripe側）**:

```
1. Webhookペイロード（JSON文字列）を準備
   payload = '{"type": "invoice.payment_succeeded", ...}'

2. タイムスタンプを生成
   timestamp = 1674123456

3. 署名文字列を作成
   signed_payload = timestamp + '.' + payload

4. HMAC-SHA256でハッシュ化
   signature = HMAC_SHA256(webhook_secret, signed_payload)

5. ヘッダーに追加
   Stripe-Signature: t=1674123456,v1=abc123...,v0=def456...
```

**署名検証アルゴリズム（けいかくんアプリ側）**:

```
1. Stripe-Signatureヘッダーを解析
   t=1674123456 → タイムスタンプ
   v1=abc123... → 署名（バージョン1）

2. 同じ署名文字列を再作成
   signed_payload = timestamp + '.' + payload

3. 同じシークレットキーでハッシュ化
   expected_signature = HMAC_SHA256(webhook_secret, signed_payload)

4. 署名を比較
   if expected_signature == received_signature:
       ✅ 検証成功（正規のWebhook）
   else:
       ❌ 検証失敗（偽装Webhook）
```

---

### 3.2 実装コード

**ファイル**: `k_back/app/api/v1/endpoints/billing.py:265-310`

```python
@router.post("/webhook")
async def stripe_webhook(
    request: Request,
    db: Annotated[AsyncSession, Depends(deps.get_db)],
    stripe_signature: Annotated[str, Header(alias="Stripe-Signature")]
):
    """
    Stripe Webhook受信API

    セキュリティ対策:
    1. Stripe署名検証（偽装Webhook防止）
    2. 冪等性チェック（リプレイ攻撃防止）
    3. トランザクション管理（データ整合性保証）
    """
    # ① Webhook Secretの存在確認
    if not settings.STRIPE_WEBHOOK_SECRET:
        raise HTTPException(
            status_code=status.HTTP_503_SERVICE_UNAVAILABLE,
            detail="Webhook Secretが設定されていません"
        )

    # ② リクエストボディを取得
    payload = await request.body()

    # ③ Stripe署名を検証
    try:
        # stripe.Webhook.construct_event() 内部で以下を実行:
        # - Stripe-Signatureヘッダーからタイムスタンプと署名を抽出
        # - タイムスタンプの有効期限チェック（デフォルト: 5分以内）
        # - HMAC-SHA256で署名を再計算
        # - 署名の一致を確認
        event = stripe.Webhook.construct_event(
            payload,
            stripe_signature,
            settings.STRIPE_WEBHOOK_SECRET.get_secret_value()
        )
    except ValueError:
        # ペイロードが不正なJSON形式
        logger.error("Invalid payload")
        raise HTTPException(
            status_code=status.HTTP_400_BAD_REQUEST,
            detail="無効なペイロードです"
        )
    except stripe.error.SignatureVerificationError:
        # 署名検証失敗 → 偽装Webhookの可能性
        logger.error("Invalid signature")
        raise HTTPException(
            status_code=status.HTTP_400_BAD_REQUEST,
            detail="署名検証に失敗しました"
        )

    # ④ 冪等性チェック: 既に処理済みのイベントはスキップ
    event_id = event.get('id', 'unknown')
    is_processed = await crud.webhook_event.is_event_processed(
        db=db,
        event_id=event_id
    )
    if is_processed:
        logger.info(f"[Webhook:{event_id}] Event already processed - skipping")
        return {"status": "success", "message": "Event already processed"}

    # ⑤ イベント処理
    # ... (後述)
```

---

## 4. 冪等性チェックの実装

### 4.1 webhook_eventsテーブルによる重複防止

**テーブル定義**:

```sql
CREATE TABLE webhook_events (
    id UUID PRIMARY KEY,
    event_id VARCHAR(255) UNIQUE NOT NULL,  -- ← Stripe Event ID（一意制約）
    event_type VARCHAR(100) NOT NULL,
    source VARCHAR(50) NOT NULL,
    billing_id UUID REFERENCES billings(id),
    office_id UUID REFERENCES offices(id),
    payload JSONB,
    status VARCHAR(20) NOT NULL,  -- success, failed, skipped
    error_message TEXT,
    processed_at TIMESTAMP WITH TIME ZONE NOT NULL DEFAULT NOW(),
    created_at TIMESTAMP WITH TIME ZONE NOT NULL DEFAULT NOW()
);

-- インデックス
CREATE UNIQUE INDEX idx_webhook_events_event_id ON webhook_events(event_id);
```

**特徴**:
- `event_id`に一意制約（UNIQUE）を設定
- 同じイベントIDが2回INSERTされるとエラー
- データベースレベルで重複を防止

---

### 4.2 冪等性チェックの実装

**ファイル**: `k_back/app/crud/crud_webhook_event.py:40-56`

```python
class CRUDWebhookEvent(CRUDBase[WebhookEvent, WebhookEventCreate, WebhookEventUpdate]):

    async def is_event_processed(
        self,
        db: AsyncSession,
        event_id: str
    ) -> bool:
        """
        イベントが既に処理済みかどうかを確認

        Args:
            db: データベースセッション
            event_id: Stripe Event ID

        Returns:
            True: 処理済み, False: 未処理
        """
        webhook_event = await self.get_by_event_id(db=db, event_id=event_id)
        return webhook_event is not None
```

**使用例**:

```python
# Webhook受信時の冪等性チェック
event_id = event.get('id')  # 例: "evt_1A2B3C4D5E6F7G8H"

is_processed = await crud.webhook_event.is_event_processed(
    db=db,
    event_id=event_id
)

if is_processed:
    # 既に処理済み → スキップ
    logger.info(f"[Webhook:{event_id}] Event already processed - skipping")
    return {"status": "success", "message": "Event already processed"}

# 未処理の場合は処理を続行
# ...
```

---

### 4.3 Webhook処理フロー（冪等性保証）

```python
# k_back/app/api/v1/endpoints/billing.py:312-391
try:
    if event_type == 'invoice.payment_succeeded':
        # 支払い成功 → active
        customer_id = event_data.get('customer')

        # サービス層で処理（トランザクション内で webhook_events テーブルに記録）
        await billing_service.process_payment_succeeded(
            db=db,
            event_id=event_id,  # ← イベントIDを渡す
            customer_id=customer_id
        )

    # ... 他のイベントタイプの処理 ...

    return {"status": "success"}

except IntegrityError as e:
    # 冪等性: 既に処理済みのイベント（UniqueViolation）
    if "duplicate key" in str(e) and "webhook_events_event_id_key" in str(e):
        # 同じイベントIDが既に存在 → 重複リクエスト
        logger.info(
            f"[Webhook:{event_id}] Event already processed "
            f"(detected via IntegrityError) - returning success"
        )
        return {"status": "success", "message": "Event already processed"}

    # その他のIntegrityError
    logger.error(f"[Webhook:{event_id}] Integrity error: {e}")
    raise HTTPException(
        status_code=status.HTTP_500_INTERNAL_SERVER_ERROR,
        detail="Webhook処理に失敗しました"
    )
```

**冪等性の保証**:

1. **事前チェック**: `is_event_processed()`でイベントIDを確認
2. **データベース制約**: webhook_eventsテーブルのUNIQUE制約
3. **例外ハンドリング**: IntegrityErrorをキャッチして重複を検知

---

## 5. セキュリティ上の脅威と対策

### 5.1 脅威モデル

| 脅威 | 攻撃手法 | 影響 | 対策 |
|------|---------|------|------|
| **偽装Webhook** | 攻撃者が偽のWebhookを送信 | 不正な課金ステータス操作 | Stripe署名検証 |
| **リプレイ攻撃** | 過去の正規Webhookを再送信 | ステータス巻き戻し | 冪等性チェック（webhook_events） |
| **MITM攻撃** | 通信の盗聴・改ざん | Webhookペイロードの改ざん | HTTPS通信、署名検証 |
| **DoS攻撃** | 大量のWebhook送信 | サーバーリソース枯渇 | レート制限、署名検証 |

---

### 5.2 Stripe署名検証の効果

**署名検証なしの場合**:

```bash
# 攻撃者が偽装Webhookを送信（curlコマンド）
curl -X POST https://api.keikakun.com/api/v1/billing/webhook \
  -H "Content-Type: application/json" \
  -d '{
    "type": "invoice.payment_succeeded",
    "data": {
      "object": {
        "customer": "cus_victim_id",
        "amount_paid": 300000
      }
    }
  }'

# 結果: 署名検証がないため成功 → billing_status が 'active' に更新される
```

**署名検証ありの場合**:

```bash
# 攻撃者が偽装Webhookを送信（Stripe-Signatureヘッダーなし）
curl -X POST https://api.keikakun.com/api/v1/billing/webhook \
  -H "Content-Type: application/json" \
  -d '{...}'

# 結果: 400 Bad Request - 署名検証に失敗しました
```

**効果**:
- 偽装Webhookを100%ブロック
- Stripeから送信されたWebhookのみ受信
- 攻撃者はSTRIPE_WEBHOOK_SECRETを知らないため、有効な署名を生成できない

---

### 5.3 冪等性チェックの効果

**冪等性チェックなしの場合**:

```
1. 正規Webhook受信:
   event_id = "evt_123456"
   → billing_status を 'active' に更新

2. 攻撃者が同じWebhookを再送信:
   event_id = "evt_123456" (同じイベントID)
   → 再度 billing_status を 'active' に更新（重複処理）

3. ステータスが意図しない状態になる可能性
```

**冪等性チェックありの場合**:

```
1. 正規Webhook受信:
   event_id = "evt_123456"
   → webhook_events テーブルにレコード作成
   → billing_status を 'active' に更新

2. 攻撃者が同じWebhookを再送信:
   event_id = "evt_123456" (同じイベントID)
   → is_event_processed() が True を返す
   → 処理をスキップ（重複防止）

3. ステータスは常に正しい状態を維持
```

**効果**:
- リプレイ攻撃を100%ブロック
- 同じイベントが複数回処理されることを防止
- データ整合性を保証

---

## 6. まとめ: Stripe Webhook署名検証の重要性

### 実装したセキュリティ対策

| 対策 | 実装内容 | 防止する脅威 |
|------|---------|------------|
| **Stripe署名検証** | stripe.Webhook.construct_event() | 偽装Webhook、改ざん |
| **冪等性チェック** | webhook_eventsテーブルでイベントID管理 | リプレイ攻撃、重複処理 |
| **トランザクション管理** | 全操作を1つのトランザクションで実行 | データ不整合 |
| **エラーハンドリング** | IntegrityErrorで重複検知 | レースコンディション |
| **監査ログ** | webhook_eventsテーブルに全イベント記録 | 追跡可能性 |

### セキュリティ効果

**署名検証の効果**:
- 偽装Webhookを100%ブロック
- MITM攻撃による改ざんを検知
- Stripeからの正規リクエストのみ受信

**冪等性チェックの効果**:
- リプレイ攻撃を100%ブロック
- 同じイベントの重複処理を防止
- データ整合性を保証

**経済的損失の防止**:
- 不正な課金ステータス操作を防止
- 月額数十万円〜数百万円の損失を回避
- 顧客信頼の維持

### 実装の完成度

**チェックリスト**:

| 項目 | 状態 | 詳細 |
|------|------|------|
| Stripe署名検証 | ✅ 実装済み | construct_event()使用 |
| タイムスタンプ検証 | ✅ 実装済み | デフォルト5分以内 |
| 冪等性チェック | ✅ 実装済み | webhook_eventsテーブル |
| トランザクション管理 | ✅ 実装済み | サービス層で一元管理 |
| エラーハンドリング | ✅ 実装済み | IntegrityError検知 |
| 監査ログ | ✅ 実装済み | 全イベント記録 |
| テストカバレッジ | ✅ 実装済み | 署名検証、冪等性のテスト |

**セキュリティレベル**: ⭐⭐⭐⭐⭐（5/5）

---

**最終更新日**: 2026-01-27
**文書管理者**: 開発チーム
