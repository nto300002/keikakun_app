# Web Push通知 実装タスクリスト

## 概要

期限アラート（毎日9:00 JST）およびイベント駆動通知（スタッフアクション承認/却下、ロール変更）をPC/スマホのネイティブシステム通知として配信する機能を実装します。

**対象**: PC (Chrome/Firefox/Edge/Safari) + スマホ (Android Chrome/iOS Safari 16.4+)
**通知タイプ**:
1. 期限アラート（バッチ配信）
2. イベント駆動通知（リアルタイム配信）

**総見積工数**: 44-60時間（5.5-7.5日）

---

## Phase 1: Web Push基盤構築（8-10時間）

### 1.1 VAPID鍵生成・環境設定（1時間）
- [ ] VAPID鍵ペア生成（`vapid --gen`）
- [ ] 環境変数設定（`VAPID_PRIVATE_KEY`, `VAPID_PUBLIC_KEY`, `VAPID_SUBJECT`）
- [ ] k_back/.env.example更新
- [ ] k_front/.env.local更新（`NEXT_PUBLIC_VAPID_PUBLIC_KEY`）

**成果物**: `.env`に鍵設定完了

---

### 1.2 DBマイグレーション（2時間）

#### push_subscriptionsテーブル作成
```sql
CREATE TABLE push_subscriptions (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    staff_id UUID NOT NULL REFERENCES staffs(id) ON DELETE CASCADE,
    endpoint TEXT NOT NULL UNIQUE,
    p256dh_key TEXT NOT NULL,
    auth_key TEXT NOT NULL,
    user_agent TEXT,
    created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
    updated_at TIMESTAMP WITH TIME ZONE DEFAULT NOW()
);

CREATE INDEX idx_push_subscriptions_staff_id ON push_subscriptions(staff_id);
CREATE INDEX idx_push_subscriptions_endpoint_hash ON push_subscriptions USING HASH (endpoint);
```

**タスク**:
- [ ] Alembicマイグレーションファイル作成（`k_back/alembic/versions/`）
- [ ] マイグレーション実行（`docker exec keikakun_app-backend-1 alembic upgrade head`）
- [ ] テーブル作成確認（PostgreSQL）

**成果物**: `push_subscriptions`テーブル

---

### 1.3 モデル・スキーマ定義（2時間）

#### k_back/app/models/push_subscription.py
```python
from sqlalchemy import Column, String, Text, ForeignKey, DateTime
from sqlalchemy.dialects.postgresql import UUID
from sqlalchemy.orm import relationship
from app.db.base_class import Base
from datetime import datetime, timezone
import uuid

class PushSubscription(Base):
    __tablename__ = "push_subscriptions"

    id = Column(UUID(as_uuid=True), primary_key=True, default=uuid.uuid4)
    staff_id = Column(UUID(as_uuid=True), ForeignKey("staffs.id", ondelete="CASCADE"), nullable=False)
    endpoint = Column(Text, unique=True, nullable=False)
    p256dh_key = Column(Text, nullable=False)
    auth_key = Column(Text, nullable=False)
    user_agent = Column(Text, nullable=True)
    created_at = Column(DateTime(timezone=True), default=lambda: datetime.now(timezone.utc))
    updated_at = Column(DateTime(timezone=True), default=lambda: datetime.now(timezone.utc), onupdate=lambda: datetime.now(timezone.utc))

    staff = relationship("Staff", back_populates="push_subscriptions")
```

#### k_back/app/schemas/push_subscription.py
```python
from pydantic import BaseModel, Field
from datetime import datetime
from uuid import UUID
from typing import Optional

class PushSubscriptionCreate(BaseModel):
    endpoint: str
    keys: dict = Field(..., description="Contains p256dh and auth keys")

class PushSubscriptionResponse(BaseModel):
    id: UUID
    staff_id: UUID
    endpoint: str
    created_at: datetime

    class Config:
        from_attributes = True
```

**タスク**:
- [ ] モデルファイル作成（`k_back/app/models/push_subscription.py`）
- [ ] スキーマファイル作成（`k_back/app/schemas/push_subscription.py`）
- [ ] Staffモデルにリレーション追加（`staff.py: push_subscriptions = relationship(...)`）
- [ ] `k_back/app/db/base.py`にモデルインポート追加

**成果物**: モデル・スキーマ定義完了

---

### 1.4 CRUD操作実装（1-2時間）

#### k_back/app/crud/crud_push_subscription.py
```python
from typing import Optional, List
from uuid import UUID
from sqlalchemy import select
from sqlalchemy.ext.asyncio import AsyncSession
from app.crud.base import CRUDBase
from app.models.push_subscription import PushSubscription
from app.schemas.push_subscription import PushSubscriptionCreate

class CRUDPushSubscription(CRUDBase[PushSubscription, PushSubscriptionCreate, PushSubscriptionCreate]):
    async def get_by_staff_id(self, db: AsyncSession, staff_id: UUID) -> List[PushSubscription]:
        stmt = select(PushSubscription).where(PushSubscription.staff_id == staff_id)
        result = await db.execute(stmt)
        return result.scalars().all()

    async def get_by_endpoint(self, db: AsyncSession, endpoint: str) -> Optional[PushSubscription]:
        stmt = select(PushSubscription).where(PushSubscription.endpoint == endpoint)
        result = await db.execute(stmt)
        return result.scalar_one_or_none()

    async def delete_by_endpoint(self, db: AsyncSession, endpoint: str) -> bool:
        subscription = await self.get_by_endpoint(db=db, endpoint=endpoint)
        if subscription:
            await db.delete(subscription)
            await db.commit()
            return True
        return False

crud_push_subscription = CRUDPushSubscription(PushSubscription)
```

**タスク**:
- [ ] CRUDファイル作成（`k_back/app/crud/crud_push_subscription.py`）
- [ ] `k_back/app/crud/__init__.py`に追加（`from .crud_push_subscription import crud_push_subscription`）

**成果物**: CRUD操作実装完了

---

### 1.5 Push通知サービス実装（2-3時間）

#### k_back/app/core/push.py
```python
from pywebpush import webpush, WebPushException
from app.core.config import settings
import logging
import json

logger = logging.getLogger(__name__)

async def send_push_notification(
    subscription_info: dict,
    title: str,
    body: str,
    icon: str = "/logo.png",
    badge: str = "/badge.png",
    data: dict = None
) -> bool:
    """
    Web Push通知を送信

    Args:
        subscription_info: {endpoint, keys: {p256dh, auth}}
        title: 通知タイトル
        body: 通知本文
        icon: アイコンURL
        badge: バッジURL
        data: カスタムデータ

    Returns:
        bool: 送信成功/失敗
    """
    try:
        payload = {
            "title": title,
            "body": body,
            "icon": icon,
            "badge": badge,
            "data": data or {}
        }

        webpush(
            subscription_info=subscription_info,
            data=json.dumps(payload),
            vapid_private_key=settings.VAPID_PRIVATE_KEY,
            vapid_claims={"sub": settings.VAPID_SUBJECT}
        )

        logger.info(f"[PUSH] Notification sent successfully to {subscription_info['endpoint'][:50]}...")
        return True

    except WebPushException as e:
        if e.response and e.response.status_code in [404, 410]:
            logger.warning(f"[PUSH] Subscription expired: {subscription_info['endpoint'][:50]}...")
        else:
            logger.error(f"[PUSH] Failed to send notification: {e}", exc_info=True)
        return False
```

**タスク**:
- [ ] `pywebpush`パッケージ追加（`k_back/requirements.txt`）
- [ ] Pushサービスファイル作成（`k_back/app/core/push.py`）
- [ ] 環境変数読み込み実装（`k_back/app/core/config.py`に`VAPID_*`追加）

**成果物**: Push送信サービス実装完了

---

### 1.6 Push購読API実装（2時間）

#### k_back/app/api/v1/endpoints/push_subscriptions.py
```python
from fastapi import APIRouter, Depends, HTTPException
from sqlalchemy.ext.asyncio import AsyncSession
from app.api.deps import get_db, get_current_user
from app.models.staff import Staff
from app.schemas.push_subscription import PushSubscriptionCreate, PushSubscriptionResponse
from app import crud

router = APIRouter()

@router.post("/subscribe", response_model=PushSubscriptionResponse)
async def subscribe_push(
    subscription: PushSubscriptionCreate,
    current_user: Staff = Depends(get_current_user),
    db: AsyncSession = Depends(get_db)
):
    """Push通知購読登録"""
    existing = await crud.crud_push_subscription.get_by_endpoint(db=db, endpoint=subscription.endpoint)
    if existing:
        return existing

    subscription_data = {
        "staff_id": current_user.id,
        "endpoint": subscription.endpoint,
        "p256dh_key": subscription.keys["p256dh"],
        "auth_key": subscription.keys["auth"]
    }

    new_subscription = await crud.crud_push_subscription.create(db=db, obj_in=subscription_data)
    return new_subscription

@router.delete("/unsubscribe")
async def unsubscribe_push(
    endpoint: str,
    current_user: Staff = Depends(get_current_user),
    db: AsyncSession = Depends(get_db)
):
    """Push通知購読解除"""
    deleted = await crud.crud_push_subscription.delete_by_endpoint(db=db, endpoint=endpoint)
    if not deleted:
        raise HTTPException(status_code=404, detail="Subscription not found")
    return {"message": "Unsubscribed successfully"}
```

**タスク**:
- [ ] エンドポイントファイル作成（`k_back/app/api/v1/endpoints/push_subscriptions.py`）
- [ ] ルーター登録（`k_back/app/api/v1/api.py`に追加）

**成果物**: Push購読API実装完了

---

### 1.7 テストコード作成（Phase 1）（2時間）

#### tests/api/v1/test_push_subscriptions.py
```python
import pytest
from httpx import AsyncClient

@pytest.mark.asyncio
async def test_subscribe_push_success(client: AsyncClient, normal_user_token_headers):
    """Push購読登録成功"""
    response = await client.post(
        "/api/v1/push-subscriptions/subscribe",
        headers=normal_user_token_headers,
        json={
            "endpoint": "https://fcm.googleapis.com/fcm/send/...",
            "keys": {
                "p256dh": "BNcRd...",
                "auth": "tBHI..."
            }
        }
    )
    assert response.status_code == 200
    assert "id" in response.json()

@pytest.mark.asyncio
async def test_unsubscribe_push_success(client: AsyncClient, normal_user_token_headers):
    """Push購読解除成功"""
    # ...実装
```

**タスク**:
- [ ] APIテスト作成（`tests/api/v1/test_push_subscriptions.py`）
- [ ] CRUDテスト作成（`tests/crud/test_push_subscription.py`）
- [ ] テスト実行（`docker exec keikakun_app-backend-1 pytest tests/ -v`）

**成果物**: Phase 1テスト完了

---

## Phase 2: イベント駆動通知のWeb Push化（6-8時間）

### 2.1 スタッフアクション承認/却下通知（3-4時間）

#### 通知タイミング
- 管理者が承認/却下ボタンを押した瞬間にリアルタイム配信
- 対象: 申請したスタッフ全員

#### 実装箇所
`k_back/app/api/v1/endpoints/staff_actions.py`の以下エンドポイント:
- `POST /api/v1/staff-actions/{staff_action_id}/approve`
- `POST /api/v1/staff-actions/{staff_action_id}/reject`

**タスク**:
- [ ] 承認通知実装（approve endpoint内）
  ```python
  # スタッフの全デバイスにPush送信
  subscriptions = await crud.crud_push_subscription.get_by_staff_id(db=db, staff_id=staff_action.staff_id)
  for sub in subscriptions:
      await send_push_notification(
          subscription_info={
              "endpoint": sub.endpoint,
              "keys": {"p256dh": sub.p256dh_key, "auth": sub.auth_key}
          },
          title="スタッフアクション承認",
          body=f"{staff_action.action_name}が承認されました",
          data={"type": "staff_action_approved", "action_id": str(staff_action.id)}
      )
  ```
- [ ] 却下通知実装（reject endpoint内、同様の実装）
- [ ] エラーハンドリング（購読期限切れ時の自動削除）

**成果物**: スタッフアクション通知実装完了

---

### 2.2 ロール変更承認/却下通知（3-4時間）

#### 通知タイミング
- 管理者がロール変更を承認/却下した瞬間にリアルタイム配信
- 対象: ロール変更対象のスタッフ全員

#### 実装箇所
`k_back/app/api/v1/endpoints/staffs.py`の以下エンドポイント:
- `POST /api/v1/staffs/role-change/{role_change_id}/approve`
- `POST /api/v1/staffs/role-change/{role_change_id}/reject`

**タスク**:
- [ ] 承認通知実装
- [ ] 却下通知実装
- [ ] エラーハンドリング

**成果物**: ロール変更通知実装完了

---

## Phase 3: 期限アラートのWeb Push化（14-22時間）

### 3.1 バッチ処理修正（メール + Web Push併用）（6-10時間）

#### k_back/app/tasks/deadline_notification.py修正

**現状**: メール送信のみ
**修正後**: メール + Web Push両方送信

```python
async def send_deadline_alert_emails(
    db: AsyncSession,
    dry_run: bool = False
) -> int:
    # 既存のメール送信ロジック
    for staff in staffs:
        # メール送信（既存）
        await send_deadline_alert_email(...)

        # 🆕 Web Push送信追加
        subscriptions = await crud.crud_push_subscription.get_by_staff_id(db=db, staff_id=staff.id)
        for sub in subscriptions:
            try:
                await send_push_notification(
                    subscription_info={
                        "endpoint": sub.endpoint,
                        "keys": {"p256dh": sub.p256dh_key, "auth": sub.auth_key}
                    },
                    title=f"期限アラート（{office.name}）",
                    body=f"更新期限: {len(renewal_alerts)}件、アセスメント未完了: {len(assessment_alerts)}件",
                    data={
                        "type": "deadline_alert",
                        "office_id": str(office.id),
                        "renewal_count": len(renewal_alerts),
                        "assessment_count": len(assessment_alerts)
                    }
                )
            except Exception as e:
                logger.error(f"[PUSH] Failed to send deadline alert: {e}")
                # Push失敗してもメールは送信済みなので続行

    return email_count
```

**タスク**:
- [ ] `send_deadline_alert_emails`関数修正
- [ ] Push送信ロジック追加
- [ ] エラーハンドリング（Push失敗時でもメールは成功として扱う）
- [ ] ログ出力追加（`logger.info(f"Sent {push_count} push notifications")`）

**成果物**: バッチ処理修正完了

---

### 3.2 スケジューラー更新（1時間）

#### k_back/app/scheduler/deadline_notification_scheduler.py

**現状確認**: 既に実装済み（毎日0:00 UTC = 9:00 JST）
**確認事項**: バッチ処理が修正されれば自動的にPushも送信される

**タスク**:
- [ ] スケジューラーログ確認（起動時に正常動作しているか）
- [ ] テスト実行（dry_run=Trueで確認）

**成果物**: スケジューラー動作確認完了

---

### 3.3 手動トリガーAPI実装（デバッグ用）（2-3時間）

#### k_back/app/api/v1/endpoints/admin.py（新規）

管理者がテスト用に手動で期限アラートを配信できるAPI

```python
@router.post("/trigger-deadline-alerts")
async def trigger_deadline_alerts(
    current_user: Staff = Depends(get_current_admin),
    db: AsyncSession = Depends(get_db)
):
    """期限アラート手動トリガー（管理者専用）"""
    count = await send_deadline_alert_emails(db=db, dry_run=False)
    return {"message": f"Sent {count} deadline alerts"}
```

**タスク**:
- [ ] エンドポイント作成（`k_back/app/api/v1/endpoints/admin.py`）
- [ ] 管理者権限チェック実装（`get_current_admin` dependency）
- [ ] ルーター登録（`api.py`に追加）

**成果物**: 手動トリガーAPI実装完了

---

### 3.4 テストコード作成（Phase 3）（5-8時間）

#### tests/tasks/test_deadline_notification.py
```python
@pytest.mark.asyncio
async def test_send_deadline_alert_with_push(db_session, mock_push_service):
    """期限アラート送信（メール + Push）"""
    # テストデータ作成
    office = await create_test_office(db_session)
    staff = await create_test_staff(db_session, office_id=office.id)
    subscription = await create_test_subscription(db_session, staff_id=staff.id)

    # バッチ実行
    count = await send_deadline_alert_emails(db=db_session, dry_run=True)

    # アサーション
    assert count > 0
    assert mock_push_service.called
```

**タスク**:
- [ ] バッチ処理テスト作成（`tests/tasks/test_deadline_notification.py`）
- [ ] Pushサービスモック作成（`tests/mocks/push_service.py`）
- [ ] 手動トリガーAPIテスト作成（`tests/api/v1/test_admin.py`）
- [ ] テスト実行（`pytest tests/ -v`）

**成果物**: Phase 3テスト完了

---

## Phase 4: Frontend実装（12-14時間）

### 4.1 Service Worker作成（3-4時間）

#### k_front/public/sw.js
```javascript
self.addEventListener('push', (event) => {
  const data = event.data.json();

  const options = {
    body: data.body,
    icon: data.icon || '/logo.png',
    badge: data.badge || '/badge.png',
    data: data.data,
    requireInteraction: true,
    actions: [
      { action: 'view', title: 'ダッシュボードを開く' },
      { action: 'close', title: '閉じる' }
    ]
  };

  event.waitUntil(
    self.registration.showNotification(data.title, options)
  );
});

self.addEventListener('notificationclick', (event) => {
  event.notification.close();

  if (event.action === 'view') {
    event.waitUntil(
      clients.openWindow('/dashboard')
    );
  }
});
```

**タスク**:
- [ ] Service Workerファイル作成（`k_front/public/sw.js`）
- [ ] Pushイベントハンドラー実装
- [ ] 通知クリックハンドラー実装
- [ ] アイコン/バッジ配置（`k_front/public/logo.png`, `badge.png`）

**成果物**: Service Worker実装完了

---

### 4.2 Push購読Hook実装（3-4時間）

#### k_front/hooks/usePushNotification.ts
```typescript
import { useState, useEffect } from 'react';

export const usePushNotification = () => {
  const [isSupported, setIsSupported] = useState(false);
  const [isSubscribed, setIsSubscribed] = useState(false);

  useEffect(() => {
    setIsSupported('serviceWorker' in navigator && 'PushManager' in window);
  }, []);

  const subscribe = async () => {
    const registration = await navigator.serviceWorker.register('/sw.js');
    const subscription = await registration.pushManager.subscribe({
      userVisibleOnly: true,
      applicationServerKey: urlBase64ToUint8Array(process.env.NEXT_PUBLIC_VAPID_PUBLIC_KEY!)
    });

    await fetch('/api/v1/push-subscriptions/subscribe', {
      method: 'POST',
      headers: { 'Content-Type': 'application/json', 'Authorization': `Bearer ${token}` },
      body: JSON.stringify(subscription.toJSON())
    });

    setIsSubscribed(true);
  };

  const unsubscribe = async () => {
    const registration = await navigator.serviceWorker.getRegistration();
    const subscription = await registration?.pushManager.getSubscription();

    if (subscription) {
      await subscription.unsubscribe();
      await fetch(`/api/v1/push-subscriptions/unsubscribe?endpoint=${encodeURIComponent(subscription.endpoint)}`, {
        method: 'DELETE',
        headers: { 'Authorization': `Bearer ${token}` }
      });
    }

    setIsSubscribed(false);
  };

  return { isSupported, isSubscribed, subscribe, unsubscribe };
};
```

**タスク**:
- [ ] Hookファイル作成（`k_front/hooks/usePushNotification.ts`）
- [ ] 購読関数実装
- [ ] 購読解除関数実装
- [ ] Base64変換ユーティリティ実装

**成果物**: Push購読Hook実装完了

---

### 4.3 通知設定UI実装（4-5時間）

#### k_front/components/protected/settings/NotificationSettings.tsx
```typescript
'use client';

import { usePushNotification } from '@/hooks/usePushNotification';

export default function NotificationSettings() {
  const { isSupported, isSubscribed, subscribe, unsubscribe } = usePushNotification();

  if (!isSupported) {
    return <div>お使いのブラウザはプッシュ通知をサポートしていません</div>;
  }

  return (
    <div>
      <h2>通知設定</h2>
      <p>期限アラートやアクション承認をリアルタイムで受け取る</p>

      {isSubscribed ? (
        <button onClick={unsubscribe}>通知を無効化</button>
      ) : (
        <button onClick={subscribe}>通知を有効化</button>
      )}
    </div>
  );
}
```

**タスク**:
- [ ] 設定画面コンポーネント作成（`k_front/components/protected/settings/NotificationSettings.tsx`）
- [ ] 設定ページに組み込み（`k_front/app/(protected)/settings/page.tsx`）
- [ ] デザイン実装（Tailwind CSS）
- [ ] ブラウザサポート判定UI追加

**成果物**: 通知設定UI実装完了

---

### 4.4 LayoutClient修正（ポーリング頻度調整）（2時間）

#### k_front/components/protected/LayoutClient.tsx修正

**現状**: 30秒ごとにポーリング
**修正後**: Push購読中は60秒ごと、未購読は30秒ごと

```typescript
const { isSubscribed } = usePushNotification();
const pollingInterval = isSubscribed ? 60000 : 30000; // Push有効時は頻度を下げる

useEffect(() => {
  const interval = setInterval(() => {
    fetchUnreadCount();
  }, pollingInterval);

  return () => clearInterval(interval);
}, [pollingInterval]);
```

**タスク**:
- [ ] `LayoutClient.tsx`修正
- [ ] ポーリング頻度調整ロジック追加
- [ ] 動作確認

**成果物**: LayoutClient修正完了

---

## Phase 5: ドキュメント・デプロイ（4-6時間）

### 5.1 環境変数設定（本番環境）（1時間）

#### Cloud Run環境変数設定
```bash
VAPID_PRIVATE_KEY=<秘密鍵>
VAPID_PUBLIC_KEY=<公開鍵>
VAPID_SUBJECT=mailto:support@keikakun.com
```

#### Vercel環境変数設定
```bash
NEXT_PUBLIC_VAPID_PUBLIC_KEY=<公開鍵>
```

**タスク**:
- [ ] Cloud Run環境変数設定（GCPコンソール）
- [ ] Vercel環境変数設定（Vercelダッシュボード）
- [ ] 設定確認（デプロイ後にログ確認）

**成果物**: 本番環境設定完了

---

### 5.2 ドキュメント更新（2-3時間）

**タスク**:
- [ ] README.md更新（Web Push機能追加を記載）
- [ ] 環境構築ドキュメント更新（VAPID鍵生成手順追加）
- [ ] API仕様書更新（Push購読エンドポイント追加）
- [ ] 運用マニュアル作成（通知配信タイミング、トラブルシューティング）

**成果物**: ドキュメント更新完了

---

### 5.3 動作確認・リリース（1-2時間）

#### 動作確認項目
- [ ] 期限アラートPush受信確認（バッチ実行後）
- [ ] スタッフアクション承認通知確認
- [ ] ロール変更通知確認
- [ ] 購読/購読解除動作確認
- [ ] 複数デバイス登録確認
- [ ] ブラウザ別動作確認（Chrome, Firefox, Safari, Edge）
- [ ] iOS Safari動作確認（ホーム画面追加後）

**タスク**:
- [ ] ステージング環境で全機能テスト
- [ ] 本番環境デプロイ
- [ ] デプロイ後動作確認
- [ ] モニタリング設定（エラーログ監視）

**成果物**: リリース完了

---

## Phase 6: セキュリティ・パフォーマンス改善＋オプション機能

### 6.0 パフォーマンス・セキュリティレビュー（完了）✅
**実施日**: 2026-01-19
**成果物**: `performance_security_review.md`、`implementation_status_report.md`更新

**レビュー結果**:
- セキュリティスコア: 9.1/10
- パフォーマンススコア: 9.2/10
- 発見課題: 6件（Critical 1件、High 2件、Medium 3件）

---

### 6.1 Critical Issue #1修正: 複数デバイス対応（完了）✅
**実施日**: 2026-01-19
**工数**: 1時間

**問題**:
- `crud_push_subscription.py`の`create_or_update`メソッドで、新規デバイス登録時に既存購読を削除
- ユーザーがPC+スマホなど複数デバイスで通知を受信できない

**修正内容**:
- [x] 既存購読削除ロジックを除去（lines 96-99削除）
- [x] 重要な設計決定として警告コメントを追加
- [x] 全12テスト（通知設定）パス確認

**成果物**: `k_back/app/crud/crud_push_subscription.py`修正完了

---

### 6.2 High Priority: pywebpush非同期化（2-3時間）⏸️
**優先度**: High
**影響**: パフォーマンス改善

**問題**:
- `send_push_notification()`がpywebpush（同期ライブラリ）を使用
- AsyncIO環境でブロッキング処理が発生

**実装タスク**:
- [ ] httpx.AsyncClientによる非同期HTTP実装を検討
- [ ] または`asyncio.to_thread()`でpywebpushをラップ
- [ ] パフォーマンステスト実施（100件同時送信）

**成果物**: 非同期Push送信実装

---

### 6.3 High Priority: バッチ削除の最適化（1-2時間）⏸️
**優先度**: High
**影響**: パフォーマンス改善

**問題**:
- `delete_by_staff_id()`がループで個別削除
- 大量購読時に非効率

**実装タスク**:
- [ ] SQLAlchemyのbulk deleteに変更
  ```python
  stmt = delete(PushSubscription).where(PushSubscription.staff_id == staff_id)
  result = await db.execute(stmt)
  await db.commit()
  return result.rowcount
  ```
- [ ] パフォーマンステスト実施

**成果物**: バッチ削除最適化

---

### 6.4 Medium Priority: Service Worker改善（3-4時間）⏸️
**優先度**: Medium
**影響**: UX改善、メンテナンス性向上

**実装タスク**:
- [ ] sw.jsに自動更新ロジック追加（skipWaiting、clients.claim）
- [ ] オフライン対応（キャッシュ戦略）検討
- [ ] Push通知データのバリデーション追加
- [ ] エラーログ記録（通知表示失敗時）

**成果物**: Service Worker改善

---

### 6.5 DoS対策・監査ログ（2-3時間）⏸️
**優先度**: Medium
**影響**: セキュリティ強化

**実装タスク**:
- [ ] レート制限実装（FastAPI Limiterまたはカスタム実装）
  - subscribe: 10回/分/ユーザー
  - unsubscribe: 10回/分/ユーザー
- [ ] Push送信失敗時の監査ログ記録
- [ ] 購読数上限設定（1ユーザーあたり最大10デバイス）

**成果物**: DoS対策・監査ログ実装

---

### 6.6 リトライメカニズム（2-3時間）⏸️
**優先度**: Medium
**影響**: 信頼性向上

**実装タスク**:
- [ ] Push送信失敗時のリトライロジック追加（tenacity等）
- [ ] 最大3回リトライ、指数バックオフ
- [ ] リトライ失敗時のログ記録

**成果物**: リトライメカニズム実装

---

### 6.7 PII保護・タイムゾーン対応（1-2時間）⏸️
**優先度**: Low
**影響**: セキュリティ・国際化対応

**実装タスク**:
- [ ] Push通知ペイロードからPII（個人識別情報）を除外
- [ ] タイムスタンプをUTC統一（現在は混在の可能性）
- [ ] ログ出力時のPIIマスキング

**成果物**: PII保護・タイムゾーン対応

---

### 6.8 通知履歴機能（オプション）（4-5時間）⏸️
- [ ] `push_notification_logs`テーブル作成
- [ ] 送信履歴記録ロジック追加
- [ ] 履歴表示UI実装

### 6.9 通知設定カスタマイズ（オプション）（4-5時間）⏸️
- [ ] 通知タイプ別ON/OFF機能
- [ ] 通知時間帯設定（DND機能）
- [ ] 設定画面UI拡張

---

## 進捗管理

### 完了チェックリスト
- [x] Phase 1: Web Push基盤構築（8-10時間）✅ 100%完了
- [ ] Phase 2: イベント駆動通知のWeb Push化（6-8時間）⏸️ 未着手
- [x] Phase 3: 期限アラートのWeb Push化（14-22時間）🚧 70%完了（バッチ統合のみ未完了）
- [x] Phase 4: Frontend実装（12-14時間）✅ 95%完了（閾値セレクターUIのみ欠如）
- [ ] Phase 5: ドキュメント・デプロイ（4-6時間）⏸️ 未着手
- [x] Phase 6: セキュリティ・パフォーマンス改善 🚧 実装中
  - [x] 6.0 レビュー実施 ✅
  - [x] 6.1 Critical修正 ✅
  - [ ] 6.2-6.7 High/Medium優先度課題 ⏸️

### 総見積工数（更新）
**当初見積**: 44-60時間（5.5-7.5日）
**Phase 6追加**: +13-20時間（セキュリティ・パフォーマンス改善）
**新総見積**: 57-80時間（7-10日）

### 完了率
**全体進捗**: 約75%完了
- Phase 1: 100% ✅
- Phase 2: 0% ⏸️
- Phase 3: 70% 🚧
- Phase 4: 95% ✅
- Phase 5: 0% ⏸️
- Phase 6: 33%（2/6タスク完了）🚧

---

## 参考資料

- [Web Push API仕様](https://developer.mozilla.org/en-US/docs/Web/API/Push_API)
- [VAPID RFC 8292](https://datatracker.ietf.org/doc/html/rfc8292)
- [pywebpush Documentation](https://github.com/web-push-libs/pywebpush)
- [Service Worker Cookbook](https://serviceworke.rs/)
- [implementation_plan.md](./implementation_plan.md)（設計詳細）

---

**作成日**: 2026-01-13
**最終更新**: 2026-01-19


---

## Phase 3 + PWA対応: 期限アラートのWeb Push化（27-36時間）

**実装範囲**:
- 緊急のみ: renewal_deadline（残り10日以内）、assessment_incomplete（残り5日以内）
- 通知タイミング: 毎日9:00 JST（休日・祝日を除く）
- 既存との調整: プロフィール画面で通知ON/OFF設定（アプリ内通知、メール通知、システム通知）
- PWA対応: iOS Safari対応のためmanifest.json、アイコン、メタタグ追加

**関連ドキュメント**: [deadline_alerts_web_push_requirements.md](./design/deadline_alerts_web_push_requirements.md)

---

### 3.0 PWA化対応（iOS Safari対応）（2-3時間）

#### 3.0.1 manifest.json作成

**タスク**:
- [ ] `k_front/public/manifest.json` 作成
  - name: "個別支援計画くん"
  - short_name: "計画くん"
  - start_url: "/dashboard"
  - display: "standalone"
  - icons: 192x192, 512x512

**成果物**: PWA manifest作成完了

---

#### 3.0.2 PWAアイコン準備

**タスク**:
- [ ] `k_front/public/icon-192.png` 作成（192x192ピクセル）
- [ ] `k_front/public/icon-512.png` 作成（512x512ピクセル）
- [ ] デザイン要件: 白背景、ロゴ中央配置、余白20%

**成果物**: PWAアイコン準備完了

---

#### 3.0.3 HTMLヘッダー修正

**タスク**:
- [ ] `k_front/app/layout.tsx` 修正
  - manifest.json リンク追加
  - apple-touch-icon リンク追加
  - PWAメタタグ追加（apple-mobile-web-app-capable等）
  - theme-color メタタグ追加

**成果物**: PWAメタタグ設定完了

---

### 3.1 DBマイグレーション（notification_preferences追加 + 閾値フィールド）（1時間）

#### staffsテーブルにnotification_preferencesカラム追加（閾値カスタマイズ対応）

```sql
ALTER TABLE staffs ADD COLUMN notification_preferences JSONB DEFAULT '{
  "in_app_notification": true,
  "email_notification": true,
  "system_notification": false,
  "email_threshold_days": 30,
  "push_threshold_days": 10
}'::jsonb;
```

**タスク**:
- [ ] Alembicマイグレーションファイル作成
  - ID: 次のシーケンシャルID
  - カラム追加: notification_preferences (JSONB)
  - デフォルト値設定（閾値フィールド含む）
- [ ] SQLファイル作成（upgrade/downgrade機能付き）
- [ ] マイグレーション実行（手動）
- [ ] テーブル確認

**成果物**: notification_preferencesカラム追加完了（閾値フィールド含む）

---

### 3.2 Backend実装（14-17時間、閾値カスタマイズ含む）

#### 3.2.1 モデル修正（0.5時間）

**タスク**:
- [ ] `k_back/app/models/staff.py` 修正
  - notification_preferences: Mapped[dict] 追加
  - JSONB型、デフォルト値設定（閾値フィールド含む）

**成果物**: Staffモデル修正完了

---

#### 3.2.2 スキーマ定義（1時間、閾値バリデーション含む）

**タスク**:
- [ ] `k_back/app/schemas/staff.py` 修正
  - NotificationPreferences クラス作成
  - バリデーション追加:
    - 少なくとも1つON必須
    - **閾値バリデーション**: 5, 10, 20, 30のいずれか
    - email_threshold_daysはemail_notification=trueの場合のみ
    - push_threshold_daysはsystem_notification=trueの場合のみ

**成果物**: 通知設定スキーマ定義完了（閾値バリデーション含む）

---

#### 3.2.3 通知設定API実装（2.5時間、閾値対応）

**タスク**:
- [ ] `k_back/app/api/v1/endpoints/staffs.py` 修正
  - GET /staffs/me/notification-preferences 追加（閾値フィールド含む）
  - PUT /staffs/me/notification-preferences 追加（閾値更新対応）

**成果物**: 通知設定API実装完了（閾値対応）

---

#### 3.2.4 バッチ処理修正（5-7時間、閾値反映含む）

**重要**: メール/Web Push送信ロジックに閾値を動的反映

**タスク**:
- [ ] `k_back/app/tasks/deadline_notification.py` 修正
  - ⚠️ **メール送信ロジック**: `staff.notification_preferences['email_threshold_days']`を使用
  - ⚠️ **Web Push送信ロジック**: `staff.notification_preferences['push_threshold_days']`を使用
    - Web Push対象アラートフィルタリング（閾値動的）
    - notification_preferences チェック追加
    - Web Push送信ロジック追加
    - 購読期限切れ自動削除追加
    - エラーハンドリング追加
  - 平日・祝日判定は既に実装済み（`is_japanese_weekday_and_not_holiday()`）
  - 戻り値を`int`から`dict`に変更（`{"email_sent": int, "push_sent": int, "push_failed": int}`）

**成果物**: バッチ処理修正完了（閾値反映含む）

---

#### 3.2.5 Backend テスト作成（4-5時間、閾値テスト含む）

**タスク**:
- [ ] `tests/api/v1/test_staff_notification_preferences.py` 作成
  - 通知設定取得テスト（閾値フィールド含む）
  - 通知設定更新テスト（閾値更新含む）
  - 全てfalseバリデーションテスト
  - **閾値バリデーションテスト**:
    - 有効値（5, 10, 20, 30）テスト
    - 無効値（3, 15, 50など）でエラーテスト
- [ ] `tests/tasks/test_deadline_notification_with_push.py` 作成
  - Web Push送信テスト
  - 通知設定反映テスト
  - 購読期限切れ削除テスト
  - **閾値反映テスト**:
    - メール閾値10日設定時、11日前の利用者にメール送信されないことを確認
    - Push閾値30日設定時、29日前の利用者にPush送信されることを確認
- [ ] テスト実行（全テスト通過確認）

**成果物**: Backend テスト完了（閾値テスト含む）

---

### 3.3 Frontend実装（18-24時間、閾値UI含む）

#### 3.3.1 Service Worker作成（3-4時間）

**タスク**:
- [ ] `k_front/public/sw.js` 作成
  - push イベントハンドラー実装
  - notificationclick イベントハンドラー実装
  - 通知クリック時の遷移処理（/recipients?filter=deadline等）

**成果物**: Service Worker実装完了

---

#### 3.3.2 Push購読Hook作成（3-4時間）

**タスク**:
- [ ] `k_front/hooks/usePushNotification.ts` 作成
  - iOS判定ロジック追加
  - PWAモード判定追加
  - isSupported, isSubscribed, isPWA, isIOS 状態管理
  - subscribe() 関数実装
  - unsubscribe() 関数実装
  - urlBase64ToUint8Array() ユーティリティ実装

**成果物**: Push購読Hook実装完了

---

#### 3.3.3 通知設定UI作成（5-6時間、閾値セレクトボックス含む）

**タスク**:
- [ ] `k_front/components/protected/profile/NotificationSettings.tsx` 作成
  - 3種類の通知ON/OFFスイッチ実装
    - アプリ内通知
    - メール通知（+ 閾値セレクトボックス）
    - システム通知（Web Push）（+ 閾値セレクトボックス）
  - **閾値セレクトボックス実装**:
    - メール通知: 5日前, 10日前, 20日前, 30日前（デフォルト: 30日前）
    - システム通知: 5日前, 10日前, 20日前, 30日前（デフォルト: 10日前）
    - 通知OFF時はセレクトボックス無効化
  - iOS判定UI追加
    - PWA化していない場合: iOSガイダンス表示
    - PWA化成功時: 成功メッセージ表示
  - 全てfalse禁止ロジック追加
  - API連携（GET/PUT）

**成果物**: 通知設定UI実装完了（閾値セレクトボックス含む）

---

#### 3.3.4 プロフィール画面統合（1-2時間）

**タスク**:
- [ ] `k_front/app/(protected)/profile/page.tsx` 修正
  - NotificationSettings コンポーネント組み込み
  - デザイン調整

**成果物**: プロフィール画面統合完了

---

#### 3.3.5 Frontend テスト・動作確認（4-5時間、閾値変更テスト含む）

**タスク**:
- [ ] Chrome（Desktop）動作確認
- [ ] Firefox（Desktop）動作確認
- [ ] Safari（macOS）動作確認
- [ ] Chrome（Android）動作確認、ホーム画面追加テスト
- [ ] Safari（iOS）動作確認
  - PWA判定テスト
  - ホーム画面追加テスト
  - PWA起動テスト
  - Push通知受信テスト
  - 通知クリックテスト
- [ ] **閾値変更テスト**:
  - メール閾値10日に変更 → 設定反映確認
  - Push閾値30日に変更 → 設定反映確認
  - ページリロード後も設定保持確認

**成果物**: Frontend テスト完了（閾値変更テスト含む）

---

### 3.4 統合テスト（2-3時間）

**タスク**:
- [ ] E2Eテスト: 購読〜通知受信
  - プロフィール画面でシステム通知ON
  - バッチ実行
  - OS通知受信確認
- [ ] 通知設定反映テスト
  - メール通知OFF → メール送信されない
  - システム通知ON → Push送信される
  - **閾値反映テスト**:
    - メール閾値10日、利用者が11日前 → メール送信されない
    - Push閾値30日、利用者が29日前 → Push送信される
- [ ] 購読期限切れテスト
  - 無効なendpointでPush送信
  - 購読レコード削除確認

**成果物**: 統合テスト完了

---

## 進捗管理（Phase 3 + 閾値カスタマイズ）

### 完了チェックリスト
- [ ] 3.0: PWA化対応（2-3時間）
- [ ] 3.1: DBマイグレーション（1時間、閾値フィールド含む）
- [ ] 3.2: Backend実装（14-17時間、閾値カスタマイズ含む）
- [ ] 3.3: Frontend実装（18-24時間、閾値UI含む）
- [ ] 3.4: 統合テスト（2-3時間）

### Phase 3 総見積工数（閾値カスタマイズ機能含む）
**最小**: 32時間（4日）
**最大**: 41時間（5日）
**平均**: 36.5時間（約4.5日）

**追加工数**: +5-6時間（DBマイグレーション、スキーマバリデーション、UI実装、テスト）

---

**Phase 1**: ✅ 完了（基盤構築: push_subscriptions, API, テスト全22件パス）
**Phase 2**: ⏸️ 未実装（イベント駆動通知: スタッフアクション、ロール変更）
**Phase 3**: 🚧 実装中（期限アラート + PWA対応）約70%完了
  - ✅ 3.0 PWA化対応（manifest.json、アイコン、メタタグ）
  - ✅ 3.1 DBマイグレーション（notification_preferences追加、閾値フィールド含む）
  - ✅ 3.2 Backend実装（通知設定API: 全12テストパス）
  - ✅ 3.3 Frontend実装（18-25時間）
    - ✅ 3.3.1 Service Worker作成（sw.js）
    - ✅ 3.3.2 Push購読Hook作成（usePushNotification.ts）
    - ✅ 3.3.3 通知設定UI作成（NotificationSettings.tsx）
    - ✅ 3.3.4 プロフィール画面統合（通知設定タブ追加）
    - ⏸️ 3.3.5 Frontend テスト・動作確認
    - ✅ 3.3.6 ログイン時の自動購読機能実装
    - ✅ 3.3.8 期限切れアラート機能実装（renewal_overdue、赤色トースト）
    - ✅ 3.3.9 アプリ内通知ON/OFF制御修正（in_app_notification設定尊重）
  - ⏸️ 3.3.7 期限通知バッチへのWeb Push統合（次の優先タスク）
  - ⏸️ 3.4 統合テスト
**Phase 4**: ✅ ほぼ完了（95%、閾値セレクターUIのみ欠如）
**Phase 5**: ⏸️ 未着手（ドキュメント・本番環境設定）
**Phase 6**: 🚧 実装中（セキュリティ・パフォーマンス改善）
  - ✅ 6.0 パフォーマンス・セキュリティレビュー実施（2026-01-19）
  - ✅ 6.1 Critical Issue #1修正: 複数デバイス対応（2026-01-19）
  - ⏸️ 6.2 High Priority: pywebpush非同期化
  - ⏸️ 6.3 High Priority: バッチ削除の最適化
  - ⏸️ 6.4 Medium Priority: Service Worker改善
  - ⏸️ 6.5 DoS対策・監査ログ
  - ⏸️ 6.6-6.7 リトライ・PII保護・タイムゾーン

**VAPID鍵生成**: ✅ 完了
  - 秘密鍵PEM: `/app/private_key.pem`
  - 公開鍵B64: `BBmBnPkVV0X-PdBZRYBr1Yra2xzkRIKuhHyEwJZObLoNTQtYxTiw248CJB1M9CtEqnWpl4JFZUFzkLTtugbObMs`
  - フロントエンド環境変数: ✅ 設定済み（`.env.local`）
  - バックエンド環境変数: ⚠️ 要設定（Dockerコンテナ）

**次のステップ（優先順位順）**:
1. ✅ ログイン時の自動購読機能実装（Phase 3.3.6完了）
2. ✅ パフォーマンス・セキュリティレビュー実施（Phase 6.0完了、2026-01-19）
3. ✅ Critical Issue #1修正: 複数デバイス対応（Phase 6.1完了、2026-01-19）
4. ✅ 期限切れアラート機能実装（Phase 3.3.8完了、2026-01-19）
5. ✅ アプリ内通知ON/OFF制御修正（Phase 3.3.9完了、2026-01-19）
6. 🔴 **最優先**: 期限通知バッチへのWeb Push統合（Phase 3.3.7、5-7時間）
7. ⏸️ バックエンド環境変数設定（VAPID_PRIVATE_KEY、VAPID_PUBLIC_KEY、VAPID_SUBJECT）
8. ⏸️ ブラウザ別動作確認（Chrome/Firefox/Safari/iOS）
9. ⏸️ Phase 6高優先度課題対応（pywebpush非同期化、バッチ削除最適化）
10. ⏸️ Phase 2: イベント駆動通知実装（6-8時間）

---

## 実装ファイル一覧（Phase 3.3完了分）

### フロントエンド
- ✅ `k_front/public/manifest.json` - PWAマニフェスト
- ✅ `k_front/public/sw.js` - Service Worker（Push受信、通知クリック処理）
- ✅ `k_front/public/icon-192.png` - PWAアイコン（192x192）
- ✅ `k_front/public/icon-512.png` - PWAアイコン（512x512）
- ✅ `k_front/hooks/usePushNotification.ts` - Push購読管理Hook
- ✅ `k_front/components/protected/profile/NotificationSettings.tsx` - 通知設定UI（閾値フィールド対応）
- ✅ `k_front/components/protected/profile/Profile.tsx` - プロフィール画面（通知設定タブ統合）
- ✅ `k_front/components/protected/LayoutClient.tsx` - ログイン時の自動購読ロジック実装、アプリ内通知ON/OFF制御（2026-01-19更新）
- ✅ `k_front/types/deadline.ts` - DeadlineAlert型定義（renewal_overdue対応、2026-01-19更新）
- ✅ `k_front/app/layout.tsx` - PWAメタタグ追加
- ✅ `k_front/.env.local` - VAPID公開鍵設定

### バックエンド
- ✅ `k_back/app/models/push_subscription.py` - PushSubscriptionモデル
- ✅ `k_back/app/schemas/push_subscription.py` - Push購読スキーマ
- ✅ `k_back/app/crud/crud_push_subscription.py` - CRUD操作（複数デバイス対応修正、2026-01-19更新）
- ✅ `k_back/app/api/v1/endpoints/push_subscriptions.py` - Push購読API
- ✅ `k_back/app/core/push.py` - Push送信サービス
- ✅ `k_back/app/core/config.py` - VAPID設定
- ✅ `k_back/app/schemas/deadline_alert.py` - DeadlineAlertスキーマ（renewal_overdue対応、2026-01-19更新）
- ✅ `k_back/app/services/welfare_recipient_service.py` - 期限アラート生成ロジック（overdue検出、2026-01-19更新）
- ✅ `k_back/tests/api/v1/test_deadline_alerts_overdue.py` - 期限切れアラートテスト（新規作成、2026-01-19）
- ✅ `k_back/scripts/generate_vapid_keys.py` - VAPID鍵生成スクリプト
- ✅ `k_back/private_key.pem` - VAPID秘密鍵
- ✅ `k_back/public_key.pem` - VAPID公開鍵

### ドキュメント（2026-01-19追加）
- ✅ `md_files_design_note/task/*web_push/performance_security_review.md` - セキュリティ・パフォーマンスレビュー
- ✅ `md_files_design_note/task/*web_push/implementation_status_report.md` - 実装状況レポート（レビュー結果統合）
- ✅ `md_files_design_note/task/*web_push/log/1-19_log_implementation.md` - 実装ログ（2026-01-19）

**最終更新**: 2026-01-19

**変更履歴**:
- 2026-01-19: Phase 6.0-6.1完了（セキュリティ・パフォーマンスレビュー、複数デバイス対応修正）
- 2026-01-19: Phase 3.3.8-3.3.9完了（期限切れアラート機能、アプリ内通知ON/OFF制御）
- 2026-01-16: Phase 3.3.6（ログイン時の自動購読機能）実装完了


---

## Phase 3.3.6: ログイン時の自動購読機能実装（2-3時間）

### 概要
ユーザーが一度システム通知をONにした場合、次回ログイン時に自動的にPush通知を再購読する仕組みを実装します。

### 背景
**現状の問題点**:
- Push通知の購読機能は実装済みだが、ログイン時に自動購読する仕組みがない
- ユーザーが一度システム通知をONにしても、次回ログイン時には手動で再度ONにする必要がある
- `notification_preferences.system_notification`の設定が保存されているにも関わらず、購読状態が同期されない

**解決策**:
- LayoutClient.tsxのマウント時（ログイン直後）に通知設定を取得
- `system_notification: true`の場合、自動的にPush購読を実行
- すでに購読済みの場合はスキップ（冪等性を保証）

---

### 3.3.6.1 要件定義

#### 機能要件
1. **ログイン時の自動購読**
   - LayoutClient.tsxマウント時に`/api/v1/staffs/me/notification-preferences`を取得
   - `system_notification: true`の場合、usePushNotification.subscribe()を自動実行
   - すでに購読済み（isSubscribed: true）の場合はスキップ

2. **エラーハンドリング**
   - 購読失敗時はコンソールログに記録（ユーザーには通知しない）
   - 通知権限が拒否されている場合はスキップ
   - iOS Safari（PWAモードでない）の場合はスキップ

3. **パフォーマンス考慮**
   - 初回マウント時のみ実行（useEffect依存配列: `[]`）
   - 他の初期化処理（CSRF、事業所情報取得）と並列実行

#### 非機能要件
- 既存の初期化処理に影響を与えない
- ユーザー体験を損なわない（エラー時も画面表示は正常に動作）

---

### 3.3.6.2 実装タスク（TDD）

#### Step 1: テストケース作成（0.5-1時間）
- [ ] `k_front/__tests__/components/protected/LayoutClient.test.tsx` 作成
  - テストケース1: `system_notification: true`の場合、subscribe()が呼ばれる
  - テストケース2: `system_notification: false`の場合、subscribe()が呼ばれない
  - テストケース3: すでに購読済み（isSubscribed: true）の場合、subscribe()が呼ばれない
  - テストケース4: 通知設定API取得失敗時、subscribe()が呼ばれない
  - テストケース5: subscribe()失敗時、エラーログが出力される

#### Step 2: LayoutClient.tsx修正（1-1.5時間）
- [ ] usePushNotification Hookをインポート
- [ ] 通知設定取得API呼び出しを追加（useEffect内）
- [ ] 自動購読ロジック実装
  ```typescript
  // 疑似コード
  useEffect(() => {
    // 既存の初期化処理...

    // 🆕 自動購読ロジック追加
    const autoSubscribePush = async () => {
      try {
        // 通知設定を取得
        const preferences = await http.get('/api/v1/staffs/me/notification-preferences');

        // system_notification=trueかつ未購読の場合のみ購読
        if (preferences.system_notification && !isSubscribed && isSupported) {
          await subscribe();
          console.log('[Auto-subscribe] Push notification subscribed on login');
        }
      } catch (error) {
        console.error('[Auto-subscribe] Failed to auto-subscribe:', error);
        // エラー時も処理を継続（ユーザー体験に影響を与えない）
      }
    };

    autoSubscribePush();
  }, []);
  ```
- [ ] エラーハンドリング追加
- [ ] コンソールログ追加

#### Step 3: テスト実行と修正（0.5時間）
- [ ] テスト実行: `npm test -- LayoutClient.test.tsx`
- [ ] 失敗したテストケースを修正
- [ ] 全テストパスを確認

---

### 3.3.6.3 動作確認項目

#### 手動テスト
1. **初回ログイン → システム通知ON → ログアウト → 再ログイン**
   - [ ] 再ログイン時に自動的にPush購読が完了する
   - [ ] 通知許可ダイアログが表示されない（既に許可済み）

2. **システム通知OFF状態でログイン**
   - [ ] Push購読が実行されない

3. **ブラウザ別確認**
   - [ ] Chrome（Desktop）: 自動購読成功
   - [ ] Firefox（Desktop）: 自動購読成功
   - [ ] Safari（macOS）: 自動購読成功
   - [ ] iOS Safari（PWAモード）: 自動購読成功
   - [ ] iOS Safari（通常ブラウザ）: 自動購読スキップ

4. **エラーケース**
   - [ ] 通知権限が拒否されている場合: エラーログ出力、画面表示は正常
   - [ ] バックエンドAPI障害時: エラーログ出力、画面表示は正常

---

### 3.3.6.4 成果物
- [ ] テストファイル作成: `k_front/__tests__/components/protected/LayoutClient.test.tsx`（テスト環境未構築のため保留）
- [x] LayoutClient.tsx修正: 自動購読ロジック追加
  - usePushNotification Hookをインポート
  - 初期化useEffect内に自動購読ロジックを追加
  - 通知設定API呼び出しを実装
  - エラーハンドリング実装
- [x] 型定義更新: NotificationPreferences（閾値フィールド含む）
  - LayoutClient.tsx: 型定義更新
  - NotificationSettings.tsx: 型定義更新
- [ ] テスト全件パス（テスト環境未構築のため保留）
- [ ] 手動動作確認完了（Phase 3.1 DBマイグレーション完了後に実施）

---

### 3.3.6.5 見積工数
**最小**: 2時間
**最大**: 3時間
**平均**: 2.5時間

---

**作成日**: 2026-01-16
**最終更新**: 2026-01-16     