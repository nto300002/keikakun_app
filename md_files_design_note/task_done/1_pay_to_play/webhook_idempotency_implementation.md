# Webhook冪等性実装 - webhook_eventsテーブル

## 作成日
2025-12-12

## 概要
Stripe Webhookイベントの重複処理を防止するための`webhook_events`テーブルとCRUD操作を実装しました。

---

## 作成したファイル

### 1. マイグレーション

#### Alembicマイグレーションファイル
**ファイル**: `k_back/migrations/versions/h6i7j8k9l0m1_create_webhook_events_table.py`
- **Revision ID**: h6i7j8k9l0m1
- **Revises**: g5h6i7j8k9l0 (billings テーブル作成)

#### SQL マイグレーションファイル
- **アップグレード**: `md_files_design_note/task/1_pay_to_play/migration_webhook_events_upgrade.sql`
- **ダウングレード**: `md_files_design_note/task/1_pay_to_play/migration_webhook_events_downgrade.sql`

### 2. モデル

**ファイル**: `k_back/app/models/webhook_event.py`

```python
class WebhookEvent(Base):
    __tablename__ = "webhook_events"

    id: Mapped[UUID]                    # 主キー
    event_id: Mapped[str]               # Stripe Event ID (UNIQUE)
    event_type: Mapped[str]             # イベントタイプ
    source: Mapped[str]                 # Webhook送信元（デフォルト: stripe）
    billing_id: Mapped[Optional[UUID]]  # 関連するBilling ID
    office_id: Mapped[Optional[UUID]]   # 関連するOffice ID
    payload: Mapped[Optional[dict]]     # Webhookペイロード（JSONB）
    processed_at: Mapped[datetime]      # 処理日時
    status: Mapped[str]                 # 処理ステータス（success, failed, skipped）
    error_message: Mapped[Optional[str]] # エラーメッセージ
    created_at: Mapped[datetime]        # 作成日時
```

**リレーションシップ**:
- `billing`: Billing モデルとの関連（SET NULL on delete）
- `office`: Office モデルとの関連（SET NULL on delete）

### 3. スキーマ

**ファイル**: `k_back/app/schemas/webhook_event.py`

- `WebhookEventBase` - 基底スキーマ
- `WebhookEventCreate` - 作成用
- `WebhookEventUpdate` - 更新用
- `WebhookEvent` - レスポンス用
- `WebhookEventListResponse` - 一覧レスポンス用

### 4. CRUD

**ファイル**: `k_back/app/crud/crud_webhook_event.py`

主要メソッド:
```python
# 冪等性チェック
async def is_event_processed(db, event_id) -> bool

# イベント取得
async def get_by_event_id(db, event_id) -> Optional[WebhookEvent]

# イベント記録作成
async def create_event_record(
    db,
    event_id,
    event_type,
    source="stripe",
    billing_id=None,
    office_id=None,
    payload=None,
    status="success",
    error_message=None
) -> WebhookEvent

# 最近のイベント取得
async def get_recent_events(
    db,
    event_type=None,
    billing_id=None,
    office_id=None,
    limit=100
) -> List[WebhookEvent]

# 失敗イベント取得
async def get_failed_events(
    db,
    since=None,
    limit=100
) -> List[WebhookEvent]

# 古いイベント削除
async def cleanup_old_events(
    db,
    retention_days=90,
    batch_size=1000
) -> int
```

### 5. モデル・CRUD登録

**ファイル**: `k_back/app/models/__init__.py`
```python
from .webhook_event import WebhookEvent
```

**ファイル**: `k_back/app/crud/__init__.py`
```python
from .crud_webhook_event import webhook_event
```

---

## テーブル構造

### webhook_events テーブル

```sql
CREATE TABLE webhook_events (
    -- 主キー
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),

    -- Stripe Event情報
    event_id VARCHAR(255) NOT NULL UNIQUE,  -- Stripe Event ID
    event_type VARCHAR(100) NOT NULL,       -- イベントタイプ
    source VARCHAR(50) NOT NULL DEFAULT 'stripe',

    -- 関連リソース
    billing_id UUID REFERENCES billings(id) ON DELETE SET NULL,
    office_id UUID REFERENCES offices(id) ON DELETE SET NULL,

    -- ペイロード（デバッグ用）
    payload JSONB,

    -- 処理情報
    processed_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    status VARCHAR(20) NOT NULL DEFAULT 'success',
    error_message TEXT,

    -- タイムスタンプ
    created_at TIMESTAMPTZ NOT NULL DEFAULT now()
);
```

### インデックス

```sql
-- 冪等性チェック用（最重要）
CREATE UNIQUE INDEX uq_webhook_events_event_id ON webhook_events(event_id);
CREATE INDEX idx_webhook_events_event_id ON webhook_events(event_id);

-- イベントタイプ検索用
CREATE INDEX idx_webhook_events_event_type ON webhook_events(event_type);

-- 処理日時検索用（古いログ削除に使用）
CREATE INDEX idx_webhook_events_processed_at ON webhook_events(processed_at);

-- 関連リソース検索用
CREATE INDEX idx_webhook_events_billing_id ON webhook_events(billing_id);
CREATE INDEX idx_webhook_events_office_id ON webhook_events(office_id);

-- ステータス検索用
CREATE INDEX idx_webhook_events_status ON webhook_events(status);
```

---

## 使用方法

### 1. Webhookハンドラーでの冪等性チェック

**ファイル**: `k_back/app/api/v1/endpoints/billing.py:222-335`

```python
from app import crud

@router.post("/webhook")
async def stripe_webhook(
    request: Request,
    db: Annotated[AsyncSession, Depends(deps.get_db)],
    stripe_signature: Annotated[str, Header(alias="Stripe-Signature")]
):
    # Stripe署名検証
    event = stripe.Webhook.construct_event(...)
    event_id = event.get('id', 'unknown')
    event_type = event['type']

    # 冪等性チェック
    is_processed = await crud.webhook_event.is_event_processed(db=db, event_id=event_id)
    if is_processed:
        logger.info(f"[Webhook:{event_id}] Already processed, skipping")
        return {"status": "success", "message": "Event already processed"}

    try:
        # イベント処理
        if event_type == 'invoice.payment_succeeded':
            # ... 処理ロジック

        # 処理成功を記録
        await crud.webhook_event.create_event_record(
            db=db,
            event_id=event_id,
            event_type=event_type,
            billing_id=billing.id if billing else None,
            office_id=billing.office_id if billing else None,
            payload=event,
            status="success"
        )

        await db.commit()
        return {"status": "success"}

    except Exception as e:
        # 処理失敗を記録
        await crud.webhook_event.create_event_record(
            db=db,
            event_id=event_id,
            event_type=event_type,
            status="failed",
            error_message=str(e)
        )
        await db.commit()
        raise
```

### 2. 処理済みイベントの確認

```python
# 特定のイベントIDが処理済みか確認
is_processed = await crud.webhook_event.is_event_processed(
    db=db,
    event_id="evt_1234567890"
)

# イベント詳細を取得
event = await crud.webhook_event.get_by_event_id(
    db=db,
    event_id="evt_1234567890"
)
```

### 3. 最近のイベント取得

```python
# 特定の事業所の最近のイベント
recent_events = await crud.webhook_event.get_recent_events(
    db=db,
    office_id=office_id,
    limit=50
)

# 特定タイプのイベント
payment_events = await crud.webhook_event.get_recent_events(
    db=db,
    event_type="invoice.payment_succeeded",
    limit=100
)
```

### 4. 失敗イベントの取得

```python
from datetime import datetime, timedelta

# 過去24時間の失敗イベント
since = datetime.utcnow() - timedelta(hours=24)
failed_events = await crud.webhook_event.get_failed_events(
    db=db,
    since=since,
    limit=100
)
```

### 5. 古いイベントのクリーンアップ

```python
# 90日以上前のイベントを削除
deleted_count = await crud.webhook_event.cleanup_old_events(
    db=db,
    retention_days=90,
    batch_size=1000
)
await db.commit()

logger.info(f"Cleaned up {deleted_count} old webhook events")
```

---

## マイグレーション実行手順

### 本番環境

#### 1. SQLファイルを使用する場合

```bash
# アップグレード
psql -U postgres -d keikakun_db -f migration_webhook_events_upgrade.sql

# ダウングレード（必要な場合）
psql -U postgres -d keikakun_db -f migration_webhook_events_downgrade.sql
```

#### 2. Alembicを使用する場合

```bash
# アップグレード
docker exec keikakun_app-backend-1 alembic upgrade head

# ダウングレード（必要な場合）
docker exec keikakun_app-backend-1 alembic downgrade -1
```

### 確認

```sql
-- テーブル確認
\d webhook_events

-- インデックス確認
\di webhook_events*

-- 件数確認
SELECT COUNT(*) FROM webhook_events;

-- 最近のイベント確認
SELECT event_id, event_type, status, processed_at
FROM webhook_events
ORDER BY processed_at DESC
LIMIT 10;
```

---

## 保持期間

### 推奨設定

- **成功イベント**: 90日
- **失敗イベント**: 180日（再処理の可能性を考慮）

### クリーンアップジョブ

定期的に古いイベントを削除することを推奨（cronジョブなど）:

```python
# app/tasks/cleanup_webhook_events.py (例)
async def cleanup_webhook_events_task():
    async with async_session() as db:
        # 成功イベントは90日で削除
        deleted_count = await crud.webhook_event.cleanup_old_events(
            db=db,
            retention_days=90
        )
        await db.commit()
        logger.info(f"Cleaned up {deleted_count} webhook events")
```

---

## ステータス値

- **`success`**: 正常に処理完了
- **`failed`**: 処理中にエラー発生
- **`skipped`**: 重複により処理スキップ

---

## 次のステップ

### 1. Webhookハンドラーへの統合

`k_back/app/api/v1/endpoints/billing.py` の `stripe_webhook()` 関数に冪等性チェックを追加:

- [ ] 冪等性チェックの追加
- [ ] 処理成功時の記録
- [ ] 処理失敗時の記録
- [ ] 重複イベントのスキップ処理

### 2. テスト追加

- [ ] 冪等性チェックのテスト
- [ ] 重複イベント送信のテスト
- [ ] 失敗イベント記録のテスト
- [ ] クリーンアップ処理のテスト

### 3. モニタリング

- [ ] 失敗イベントの監視
- [ ] 重複イベントの頻度確認
- [ ] クリーンアップジョブのスケジュール設定

---

## セキュリティチェックリスト更新

### ✅ 新規実装

- [x] webhook_eventsテーブル作成
- [x] WebhookEvent モデル作成
- [x] CRUD操作実装
- [x] スキーマ定義

### ⏳ 次のステップ

- [ ] Webhookハンドラーへの冪等性チェック統合
- [ ] テスト実装
- [ ] クリーンアップジョブ実装

---

## 関連ドキュメント

- `security_transaction_review.md` - セキュリティレビュー（P0問題として特定）
- `security_transaction_fixes.md` - 修正レポート
- `audit_log_requirements.md` - 監査ログ実装要件
- `implementation_summary.md` - 実装完了レポート

---

## 参考

- [Stripe Webhookベストプラクティス](https://stripe.com/docs/webhooks/best-practices)
- [Stripe Event ID仕様](https://stripe.com/docs/api/events)
