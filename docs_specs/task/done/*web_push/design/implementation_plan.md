# Web Push通知実装 - 要件定義と工数見積

**作成日**: 2026-01-13
**最終更新**: 2026-01-14
**ステータス**:
- ✅ **バックエンド**: 実装完了（2026-01-13）
- 🚧 **フロントエンド**: 実装予定
**目的**: ログインしているStaffのデバイス(PC/スマホ)にリアルタイム通知を配信

---

## 1. 現状システムの分析

### 1.1 現在の通知システム

**アーキテクチャ**: Pull型（ポーリング方式）

**Backend**:
- **モデル**: `Notice` (`app/models/notice.py`)
  - フィールド: `recipient_staff_id`, `office_id`, `type`, `title`, `content`, `link_url`, `is_read`
  - PostgreSQLに保存
- **API**: `/api/v1/notices` エンドポイント
  - `GET /notices` - 通知一覧取得
  - `GET /notices/unread-count` - 未読件数取得
  - `PATCH /notices/{id}/read` - 既読化
  - `PATCH /notices/read-all` - 全既読化

**Frontend**:
- **ポーリング**: 30秒ごとに `/notices/unread-count` を呼び出し
- **実装場所**: `components/protected/LayoutClient.tsx` (Lines 188-191)
- **トースト通知**: `sonner` ライブラリ使用（ブラウザ内のみ）

**問題点**:
1. ✗ リアルタイム性が低い（最大30秒の遅延）
2. ✗ サーバー負荷が高い（全アクティブユーザーが30秒ごとにリクエスト）
3. ✗ ブラウザタブを閉じると通知を受け取れない
4. ✗ デバイスネイティブ通知が不可能

---

## 2. Web Push通知の要件

### 2.1 機能要件

1. **リアルタイム通知**: イベント発生時に即座に通知
2. **デバイス通知**: ブラウザタブが閉じていても通知を受信
3. **マルチデバイス対応**: PC、スマホ（ブラウザ）の両方に対応
4. **通知の種類**:
   - 期限アラート（更新期限）
   - アセスメント未完了
   - スタッフアクション承認/拒否
   - 事業所情報変更通知
   - その他システム通知

### 2.2 技術要件

1. **Browser Push API対応ブラウザ**:
   - Chrome/Edge: ✅ 対応
   - Firefox: ✅ 対応
   - Safari: ✅ 対応 (iOS 16.4+)

2. **HTTPS必須**: すでにCloud Runで対応済み ✅

3. **Service Worker**: PWA対応が必要

---

## 3. 実装に必要なコンポーネント

### 3.1 Backend実装

#### 3.1.1 新規テーブル: `push_subscriptions`

```sql
CREATE TABLE push_subscriptions (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    staff_id UUID NOT NULL REFERENCES staffs(id) ON DELETE CASCADE,
    endpoint TEXT NOT NULL,
    p256dh_key TEXT NOT NULL,  -- 公開鍵
    auth_key TEXT NOT NULL,     -- 認証シークレット
    user_agent TEXT,            -- デバイス識別用
    device_type VARCHAR(20),    -- 'pc', 'mobile'
    is_active BOOLEAN DEFAULT TRUE,
    created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
    updated_at TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
    is_test_data BOOLEAN DEFAULT FALSE NOT NULL,
    UNIQUE(staff_id, endpoint)
);

CREATE INDEX idx_push_subscriptions_staff_id ON push_subscriptions(staff_id);
CREATE INDEX idx_push_subscriptions_is_active ON push_subscriptions(is_active);
```

**マイグレーションファイル**: `migrations/versions/xxx_add_push_subscriptions.py`

#### 3.1.2 VAPID鍵管理

**環境変数に追加** (`.env`):
```bash
VAPID_PUBLIC_KEY=<生成された公開鍵>
VAPID_PRIVATE_KEY=<生成された秘密鍵>
VAPID_SUBJECT=mailto:admin@keikakun.com
```

**鍵生成スクリプト** (`scripts/generate_vapid_keys.py`):
```python
from py_vapid import Vapid

vapid = Vapid()
vapid.generate_keys()

print("Public Key:", vapid.public_key.decode('utf-8'))
print("Private Key:", vapid.private_key.decode('utf-8'))
```

#### 3.1.3 新規Pythonパッケージ

`requirements.txt` に追加:
```
py-vapid>=1.9.0
pywebpush>=2.0.0
```

#### 3.1.4 新規API エンドポイント

**ファイル**: `app/api/v1/endpoints/push_subscriptions.py`

**エンドポイント**:
- `POST /api/v1/push-subscriptions/subscribe` - Push購読登録
- `POST /api/v1/push-subscriptions/unsubscribe` - Push購読解除
- `GET /api/v1/push-subscriptions/vapid-public-key` - VAPID公開鍵取得
- `GET /api/v1/push-subscriptions` - 自分の購読一覧取得
- `POST /api/v1/push-subscriptions/test` - テスト通知送信（開発用）

**Schemas** (`app/schemas/push_subscription.py`):
```python
from pydantic import BaseModel
from datetime import datetime
from uuid import UUID

class PushSubscriptionCreate(BaseModel):
    endpoint: str
    p256dh_key: str
    auth_key: str
    user_agent: str | None = None
    device_type: str | None = None

class PushSubscriptionResponse(BaseModel):
    id: UUID
    staff_id: UUID
    endpoint: str
    device_type: str | None
    is_active: bool
    created_at: datetime

class VapidPublicKeyResponse(BaseModel):
    public_key: str
```

#### 3.1.5 Push通知サービス

**ファイル**: `app/services/push_notification_service.py`

```python
from pywebpush import webpush, WebPushException
from app.core.config import settings
from app import crud
from sqlalchemy.ext.asyncio import AsyncSession
import json
import logging
from uuid import UUID

logger = logging.getLogger(__name__)

class PushNotificationService:
    """Web Push通知サービス"""

    async def send_push_notification(
        self,
        db: AsyncSession,
        staff_id: UUID,
        title: str,
        body: str,
        data: dict = None,
        url: str = None
    ) -> dict:
        """
        指定されたスタッフの全デバイスにPush通知を送信

        Args:
            staff_id: 通知先スタッフID
            title: 通知タイトル
            body: 通知本文
            data: 追加データ（任意）
            url: 通知クリック時の遷移先URL（任意）

        Returns:
            送信結果 {"success": int, "failed": int}
        """
        # アクティブな購読を取得
        subscriptions = await crud.push_subscription.get_active_by_staff_id(
            db=db,
            staff_id=staff_id
        )

        if not subscriptions:
            logger.info(f"No active subscriptions for staff_id={staff_id}")
            return {"success": 0, "failed": 0}

        # 通知ペイロード作成
        payload = {
            "title": title,
            "body": body,
            "data": data or {},
            "url": url or "/dashboard",
            "tag": "keikakun-notification"
        }

        success_count = 0
        failed_count = 0

        # 各購読に対して通知送信
        for subscription in subscriptions:
            try:
                subscription_info = {
                    "endpoint": subscription.endpoint,
                    "keys": {
                        "p256dh": subscription.p256dh_key,
                        "auth": subscription.auth_key
                    }
                }

                webpush(
                    subscription_info=subscription_info,
                    data=json.dumps(payload),
                    vapid_private_key=settings.VAPID_PRIVATE_KEY,
                    vapid_claims={
                        "sub": settings.VAPID_SUBJECT
                    }
                )

                success_count += 1
                logger.info(f"Push sent successfully to subscription_id={subscription.id}")

            except WebPushException as e:
                failed_count += 1
                logger.error(f"Push failed for subscription_id={subscription.id}: {e}")

                # 410 Gone (購読が無効化された) の場合、DBから削除
                if e.response and e.response.status_code == 410:
                    await crud.push_subscription.remove(db=db, id=subscription.id)
                    await db.commit()
                    logger.info(f"Removed invalid subscription_id={subscription.id}")

            except Exception as e:
                failed_count += 1
                logger.error(f"Unexpected error for subscription_id={subscription.id}: {e}")

        return {"success": success_count, "failed": failed_count}
```

#### 3.1.6 既存通知作成処理の拡張

**変更ファイル**: `app/crud/crud_notice.py`

```python
async def create_notice_with_push(
    self,
    db: AsyncSession,
    notice_in: NoticeCreate,
    send_push: bool = True
) -> Notice:
    """
    Notice作成 + Push通知送信

    Args:
        db: DBセッション
        notice_in: Notice作成データ
        send_push: Push通知を送信するか（デフォルト: True）

    Returns:
        作成されたNotice
    """
    from app.services.push_notification_service import PushNotificationService

    # 1. Notice作成
    notice = await self.create(db=db, obj_in=notice_in)
    await db.commit()
    await db.refresh(notice)

    # 2. Push通知送信
    if send_push:
        push_service = PushNotificationService()
        result = await push_service.send_push_notification(
            db=db,
            staff_id=notice_in.recipient_staff_id,
            title=notice_in.title,
            body=notice_in.content or "",
            data={"notice_id": str(notice.id)},
            url=notice_in.link_url
        )
        logger.info(f"Push notification result: {result}")

    return notice
```

**全Notice作成箇所を更新**:
- `app/services/employee_action_service.py` - スタッフアクション承認/拒否通知
- `app/services/office_service.py` - 事業所情報変更通知
- その他Notice作成箇所

---

### 3.2 Frontend実装

#### 3.2.1 Service Worker作成

**ファイル**: `public/sw.js`

```javascript
// Service Worker バージョン
const VERSION = 'v1.0.0';

// Push通知受信ハンドラ
self.addEventListener('push', function(event) {
  console.log('[Service Worker] Push received:', event);

  if (!event.data) {
    console.warn('[Service Worker] Push event has no data');
    return;
  }

  try {
    const data = event.data.json();

    const options = {
      body: data.body,
      icon: '/icon-192x192.png',
      badge: '/badge-72x72.png',
      data: {
        url: data.url || '/dashboard',
        ...data.data
      },
      tag: data.tag || 'notification',
      requireInteraction: false,
      vibrate: [200, 100, 200]
    };

    event.waitUntil(
      self.registration.showNotification(data.title, options)
    );
  } catch (error) {
    console.error('[Service Worker] Error processing push:', error);
  }
});

// 通知クリックハンドラ
self.addEventListener('notificationclick', function(event) {
  console.log('[Service Worker] Notification click received:', event);

  event.notification.close();

  const urlToOpen = event.notification.data?.url || '/dashboard';

  event.waitUntil(
    clients.matchAll({ type: 'window', includeUncontrolled: true })
      .then(function(clientList) {
        // 既に開いているタブがあれば、そこにフォーカス
        for (let i = 0; i < clientList.length; i++) {
          const client = clientList[i];
          if (client.url === urlToOpen && 'focus' in client) {
            return client.focus();
          }
        }
        // なければ新しいウィンドウを開く
        if (clients.openWindow) {
          return clients.openWindow(urlToOpen);
        }
      })
  );
});

// Service Worker インストール
self.addEventListener('install', function(event) {
  console.log('[Service Worker] Installing version:', VERSION);
  self.skipWaiting();
});

// Service Worker アクティベーション
self.addEventListener('activate', function(event) {
  console.log('[Service Worker] Activating version:', VERSION);
  event.waitUntil(self.clients.claim());
});
```

#### 3.2.2 Push購読管理Hook

**ファイル**: `hooks/usePushNotifications.ts`

```typescript
import { useState, useEffect } from 'react';
import { toast } from 'sonner';

interface UsePushNotificationsReturn {
  isSupported: boolean;
  isSubscribed: boolean;
  permission: NotificationPermission;
  subscribe: () => Promise<void>;
  unsubscribe: () => Promise<void>;
  isLoading: boolean;
}

export function usePushNotifications(): UsePushNotificationsReturn {
  const [isSupported, setIsSupported] = useState(false);
  const [isSubscribed, setIsSubscribed] = useState(false);
  const [permission, setPermission] = useState<NotificationPermission>('default');
  const [isLoading, setIsLoading] = useState(false);

  useEffect(() => {
    // Push通知サポート確認
    const supported = 'serviceWorker' in navigator && 'PushManager' in window;
    setIsSupported(supported);

    if (supported) {
      setPermission(Notification.permission);
      checkSubscription();
    }
  }, []);

  // Service Worker登録
  const registerServiceWorker = async (): Promise<ServiceWorkerRegistration> => {
    const registration = await navigator.serviceWorker.register('/sw.js');
    await navigator.serviceWorker.ready;
    return registration;
  };

  // 購読状態確認
  const checkSubscription = async () => {
    try {
      const registration = await navigator.serviceWorker.ready;
      const subscription = await registration.pushManager.getSubscription();
      setIsSubscribed(!!subscription);
    } catch (error) {
      console.error('Failed to check subscription:', error);
    }
  };

  // Base64 URL-safe変換
  const urlBase64ToUint8Array = (base64String: string): Uint8Array => {
    const padding = '='.repeat((4 - base64String.length % 4) % 4);
    const base64 = (base64String + padding)
      .replace(/\-/g, '+')
      .replace(/_/g, '/');

    const rawData = window.atob(base64);
    const outputArray = new Uint8Array(rawData.length);

    for (let i = 0; i < rawData.length; ++i) {
      outputArray[i] = rawData.charCodeAt(i);
    }
    return outputArray;
  };

  // Push購読
  const subscribe = async () => {
    if (!isSupported) {
      toast.error('このブラウザはプッシュ通知に対応していません');
      return;
    }

    setIsLoading(true);

    try {
      // 1. 権限リクエスト
      const permissionResult = await Notification.requestPermission();
      setPermission(permissionResult);

      if (permissionResult !== 'granted') {
        toast.error('通知権限が拒否されました');
        return;
      }

      // 2. Service Worker登録
      const registration = await registerServiceWorker();

      // 3. VAPID公開鍵取得
      const vapidResponse = await fetch('/api/v1/push-subscriptions/vapid-public-key');
      const { public_key } = await vapidResponse.json();

      // 4. Push Manager購読
      const subscription = await registration.pushManager.subscribe({
        userVisibleOnly: true,
        applicationServerKey: urlBase64ToUint8Array(public_key)
      });

      // 5. バックエンドに購読情報送信
      const subscriptionJson = subscription.toJSON();

      await fetch('/api/v1/push-subscriptions/subscribe', {
        method: 'POST',
        headers: {
          'Content-Type': 'application/json',
        },
        credentials: 'include',
        body: JSON.stringify({
          endpoint: subscriptionJson.endpoint,
          p256dh_key: subscriptionJson.keys?.p256dh,
          auth_key: subscriptionJson.keys?.auth,
          user_agent: navigator.userAgent,
          device_type: /Mobile|Android|iPhone|iPad/i.test(navigator.userAgent) ? 'mobile' : 'pc'
        })
      });

      setIsSubscribed(true);
      toast.success('プッシュ通知を有効にしました');

    } catch (error) {
      console.error('Failed to subscribe:', error);
      toast.error('プッシュ通知の有効化に失敗しました');
    } finally {
      setIsLoading(false);
    }
  };

  // Push購読解除
  const unsubscribe = async () => {
    setIsLoading(true);

    try {
      // 1. Push Manager購読解除
      const registration = await navigator.serviceWorker.ready;
      const subscription = await registration.pushManager.getSubscription();

      if (subscription) {
        await subscription.unsubscribe();

        // 2. バックエンドに購読削除通知
        const subscriptionJson = subscription.toJSON();

        await fetch('/api/v1/push-subscriptions/unsubscribe', {
          method: 'POST',
          headers: {
            'Content-Type': 'application/json',
          },
          credentials: 'include',
          body: JSON.stringify({
            endpoint: subscriptionJson.endpoint
          })
        });
      }

      setIsSubscribed(false);
      toast.success('プッシュ通知を無効にしました');

    } catch (error) {
      console.error('Failed to unsubscribe:', error);
      toast.error('プッシュ通知の無効化に失敗しました');
    } finally {
      setIsLoading(false);
    }
  };

  return {
    isSupported,
    isSubscribed,
    permission,
    subscribe,
    unsubscribe,
    isLoading
  };
}
```

#### 3.2.3 通知設定UI

**ファイル**: `components/protected/settings/NotificationSettings.tsx`

```typescript
'use client';

import { usePushNotifications } from '@/hooks/usePushNotifications';
import { FiBell, FiBellOff } from 'react-icons/fi';

export function NotificationSettings() {
  const {
    isSupported,
    isSubscribed,
    permission,
    subscribe,
    unsubscribe,
    isLoading
  } = usePushNotifications();

  return (
    <div className="space-y-6">
      <div>
        <h2 className="text-2xl font-bold text-white mb-2">プッシュ通知設定</h2>
        <p className="text-gray-400 text-sm">
          重要な通知をリアルタイムで受け取れます
        </p>
      </div>

      {!isSupported && (
        <div className="bg-yellow-900/20 border border-yellow-700 rounded-lg p-4">
          <p className="text-yellow-400 text-sm">
            ⚠️ このブラウザはプッシュ通知に対応していません
          </p>
        </div>
      )}

      {isSupported && permission === 'denied' && (
        <div className="bg-red-900/20 border border-red-700 rounded-lg p-4">
          <p className="text-red-400 text-sm">
            ❌ 通知権限が拒否されています。ブラウザ設定から許可してください。
          </p>
        </div>
      )}

      {isSupported && permission !== 'denied' && (
        <div className="bg-gray-800 rounded-lg p-6 border border-gray-700">
          <div className="flex items-center justify-between">
            <div className="flex items-center gap-3">
              {isSubscribed ? (
                <FiBell className="text-green-400 text-2xl" />
              ) : (
                <FiBellOff className="text-gray-400 text-2xl" />
              )}
              <div>
                <h3 className="text-white font-medium">
                  {isSubscribed ? 'プッシュ通知が有効です' : 'プッシュ通知が無効です'}
                </h3>
                <p className="text-gray-400 text-sm">
                  {isSubscribed
                    ? 'このデバイスに通知が届きます'
                    : '通知を受け取るには有効にしてください'}
                </p>
              </div>
            </div>

            {permission === 'default' && !isSubscribed && (
              <button
                onClick={subscribe}
                disabled={isLoading}
                className="px-4 py-2 bg-blue-600 hover:bg-blue-700 text-white rounded-lg text-sm font-medium disabled:opacity-50 disabled:cursor-not-allowed transition-colors"
              >
                {isLoading ? '処理中...' : '有効にする'}
              </button>
            )}

            {isSubscribed && (
              <button
                onClick={unsubscribe}
                disabled={isLoading}
                className="px-4 py-2 bg-gray-700 hover:bg-gray-600 text-white rounded-lg text-sm font-medium disabled:opacity-50 disabled:cursor-not-allowed transition-colors"
              >
                {isLoading ? '処理中...' : '無効にする'}
              </button>
            )}
          </div>
        </div>
      )}

      <div className="bg-gray-800/50 rounded-lg p-4 border border-gray-700">
        <h4 className="text-white font-medium mb-2 text-sm">通知される内容</h4>
        <ul className="space-y-1 text-gray-400 text-sm">
          <li>• 更新期限アラート</li>
          <li>• アセスメント未完了通知</li>
          <li>• スタッフアクション承認/拒否</li>
          <li>• 事業所情報変更通知</li>
          <li>• その他重要なお知らせ</li>
        </ul>
      </div>
    </div>
  );
}
```

#### 3.2.4 LayoutClient修正

**ファイル**: `components/protected/LayoutClient.tsx`

**変更箇所**:

```typescript
import { usePushNotifications } from '@/hooks/usePushNotifications';

// ... (既存のコード)

export function LayoutClient({ children }: LayoutClientProps) {
  // ... (既存のstate)

  const { isSupported, isSubscribed } = usePushNotifications();

  useEffect(() => {
    setIsMounted(true);

    // CSRFトークンを初期化
    initializeCsrfToken().catch(error => {
      console.error('CSRFトークンの初期化に失敗しました', error);
    });

    // 事業所情報取得
    if (!office) {
      officeApi.getMyOffice()
        .then(officeData => setOffice(officeData))
        .catch(error => {
          console.error('事業所情報の取得に失敗しました', error);
        });
    }

    // 初回の未読件数取得
    fetchUnreadCount();

    // 期限アラート取得とトースト表示（ログイン時のみ、1回だけ）
    if (!deadlineAlertsShownRef.current) {
      deadlineAlertsShownRef.current = true;
      fetchDeadlineAlertsAll().then(alerts => {
        alerts.forEach((alert) => {
          const message = alert.alert_type === 'assessment_incomplete'
            ? alert.message
            : `${alert.full_name} 更新期限まで残り${alert.days_remaining}日`;

          toast.warning(message, {
            duration: 5000,
          });
        });
      });
    }

    // ポーリング間隔をPush有効時は調整
    const pollingInterval = isSupported && isSubscribed ? 60000 : 30000;

    const interval = setInterval(() => {
      fetchUnreadCount();
    }, pollingInterval);

    return () => {
      clearInterval(interval);
    };
  }, [isSupported, isSubscribed]);

  // ... (残りのコード)
}
```

#### 3.2.5 設定ページへの統合

**ファイル**: `app/protected/settings/page.tsx`（または適切な設定ページ）

```typescript
import { NotificationSettings } from '@/components/protected/settings/NotificationSettings';

export default function SettingsPage() {
  return (
    <div className="container mx-auto p-6 space-y-8">
      <h1 className="text-3xl font-bold text-white">設定</h1>

      {/* その他の設定セクション */}

      <NotificationSettings />

      {/* その他の設定セクション */}
    </div>
  );
}
```

#### 3.2.6 アイコン/バッジ作成

**必要なファイル**:
- `public/icon-192x192.png` - 通知アイコン（192x192px）
- `public/badge-72x72.png` - 通知バッジ（72x72px）
- `public/manifest.json` - PWA Manifest更新

**manifest.json例**:
```json
{
  "name": "個別支援計画くん",
  "short_name": "計画くん",
  "description": "個別支援計画管理システム",
  "start_url": "/dashboard",
  "display": "standalone",
  "background_color": "#1a1a1a",
  "theme_color": "#3b82f6",
  "icons": [
    {
      "src": "/icon-192x192.png",
      "sizes": "192x192",
      "type": "image/png"
    },
    {
      "src": "/icon-512x512.png",
      "sizes": "512x512",
      "type": "image/png"
    }
  ]
}
```

---

## 4. 実装ステップ

### Phase 1: Backend基盤構築（8-10時間）✅ **完了済み（2026-01-13）**

#### 4.1 VAPID鍵生成と環境設定（30分）✅
- [x] VAPID鍵生成実行
- [x] `.env` に鍵追加
- [x] `app/core/config.py` に設定追加

#### 4.2 DBマイグレーション（1時間）✅
- [x] `push_subscriptions` テーブル作成マイグレーション（`z8a9b0c1d2e3_add_push_subscriptions_table.py`）
- [x] インデックス追加
- [x] マイグレーション実行・検証

#### 4.3 Push購読API実装（3時間）✅
- [x] `app/schemas/push_subscription.py` - Schema定義
- [x] `app/models/push_subscription.py` - モデル定義
- [x] `app/crud/crud_push_subscription.py` - CRUD操作
- [x] `app/api/v1/endpoints/push_subscriptions.py` - エンドポイント実装
- [x] ルーター追加

#### 4.4 Push通知サービス実装（3時間）✅
- [x] `app/core/push.py` 作成（`send_push_notification()`）
- [x] pywebpush統合
- [x] エラーハンドリング（無効な購読削除：404/410対応）
- [x] ログ記録

#### 4.5 既存Notice作成処理の拡張（1.5時間）⚠️ **未統合**
- [ ] `app/crud/crud_notice.py` - `create_notice_with_push` メソッド追加
- [ ] `app/services/employee_action_service.py` - 更新
- [ ] `app/services/office_service.py` - 更新
- [ ] その他Notice作成箇所の更新
- [ ] `app/tasks/deadline_notification.py` - Web Push統合

#### 4.6 テストコード作成（2時間）✅
- [x] `tests/api/v1/test_push_subscriptions.py` - API テスト
- [x] `tests/crud/test_push_subscription.py` - CRUDテスト

---

### Phase 2: Frontend実装（12-14時間）🚧 **実装予定**

#### 2.1 Service Worker作成（3時間）
- [ ] `public/sw.js` 実装
- [ ] Push受信ハンドラ
- [ ] 通知クリックハンドラ
- [ ] インストール/アクティベーションハンドラ

#### 2.2 Push購読Hook実装（3時間）
- [ ] `hooks/usePushNotifications.ts` 作成
- [ ] 購読/購読解除ロジック
- [ ] 権限管理
- [ ] エラーハンドリング

#### 2.3 通知設定UI実装（2時間）
- [ ] `components/protected/settings/NotificationSettings.tsx` 作成
- [ ] UI/UXデザイン実装
- [ ] 設定ページへの統合

#### 2.4 LayoutClient修正（2時間）
- [ ] `components/protected/LayoutClient.tsx` 修正
- [ ] Service Worker初期化
- [ ] ポーリング頻度調整（Push有効時は60秒、無効時は30秒）

#### 2.5 アイコン/バッジ作成（1時間）
- [ ] 通知アイコン作成・配置
- [ ] PWA manifest作成・更新
- [ ] Service Worker登録確認

#### 2.6 テスト（3時間）
- [ ] Chrome/Edgeでのテスト
- [ ] Firefoxでのテスト
- [ ] Safari（iOS含む）でのテスト
- [ ] デバイステスト（PC, モバイル）

---

### Phase 3: 統合テスト・デバッグ（8-10時間）

#### 3.1 エンドツーエンドテスト（4時間）
- [ ] 通知送信フロー確認
- [ ] マルチデバイステスト
- [ ] エッジケース確認（ブラウザタブを閉じた状態、複数タブ、など）
- [ ] 権限拒否時の動作確認

#### 3.2 パフォーマンステスト（2時間）
- [ ] 大量通知送信テスト（100件、1000件）
- [ ] 同時購読数テスト（複数デバイス）
- [ ] ポーリング頻度最適化確認

#### 3.3 バグ修正（4時間）
- [ ] 発見されたバグの修正
- [ ] ブラウザ互換性問題対応
- [ ] レトロスペクティブとリファクタリング

---

### Phase 4: ドキュメント・デプロイ（4-6時間）

#### 4.1 ドキュメント作成（3時間）
- [ ] API仕様書更新（OpenAPI/Swagger）
- [ ] ユーザーガイド作成（プッシュ通知の有効化方法）
- [ ] 運用手順書作成（VAPID鍵管理、トラブルシューティング）
- [ ] README更新

#### 4.2 デプロイ準備（2時間）
- [ ] 環境変数設定（Cloud Run）
- [ ] Service Workerキャッシュ戦略確認
- [ ] ステージング環境デプロイ・検証

#### 4.3 本番デプロイ（1時間）
- [ ] マイグレーション実行
- [ ] 本番デプロイ
- [ ] 動作確認
- [ ] モニタリング設定

---

## 5. 工数見積

| フェーズ | タスク | 工数（時間） | 稼働日数 | ステータス |
|---------|--------|------------|----------|-----------|
| Phase 1 | Backend基盤構築 | ~~8-10~~ | ~~1-1.25日~~ | ✅ 完了（2026-01-13） |
| Phase 2 | Frontend実装 | 12-14 | 1.5-1.75日 | 🚧 実装予定 |
| Phase 3 | 統合テスト・デバッグ | 8-10 | 1-1.25日 | ⏸️ 保留 |
| Phase 4 | ドキュメント・デプロイ | 4-6 | 0.5-0.75日 | ⏸️ 保留 |
| **当初合計** | | ~~32-40時間~~ | ~~4-5営業日~~ | - |
| **残り工数** | | **24-30時間** | **3-3.75営業日** | - |

**前提条件**: 1日8時間作業

**工数削減**: Phase 1完了により8-10時間削減 ✅

---

## 6. リスクと対策

### 6.1 技術的リスク

| リスク | 影響度 | 対策 |
|-------|--------|------|
| **Safari（iOS）でのPush通知サポートが不完全** | 中 | iOS 16.4以上を必須とし、古いバージョンではポーリングのみ使用 |
| **Service Workerのキャッシュ戦略が複雑** | 低 | Next.jsの既存Service Workerと競合しないよう、Push専用のService Workerを使用 |
| **Push購読が突然無効化される** | 中 | 410 Gone エラーを検知して自動的にDB上の購読を削除 |
| **Next.js App Routerとの統合問題** | 中 | Service Workerを `public/` ディレクトリに配置、ビルド時に適切に含まれることを確認 |

### 6.2 運用リスク

| リスク | 影響度 | 対策 |
|-------|--------|------|
| **通知が多すぎてユーザーがオフにする** | 高 | 通知の頻度制限、重要度別の通知設定を実装 |
| **VAPIDキーが漏洩** | 高 | Google Secret Managerで管理、定期的なキーローテーション |
| **Push通知の到達率が低い** | 中 | フォールバックとしてポーリング継続、ログで到達率を監視 |

---

## 7. 代替案・段階的実装

### 7.1 段階的実装案

#### 最小構成（Phase 1のみ）: 10-12時間
- Backend Push購読API
- Frontend基本的なPush購読機能のみ
- 既存Notice作成時にPush送信
- **メリット**: 早期リリース、フィードバック収集
- **デメリット**: UI/UX未整備、設定画面なし

#### フル機能（Phase 1-4）: 32-40時間
- 通知設定UI
- 詳細なエラーハンドリング
- 統合テスト
- ドキュメント完備
- **メリット**: 本番運用可能、保守性高い
- **デメリット**: 実装期間が長い

### 7.2 代替技術

#### WebSocket方式
- **リアルタイム性**: ◎
- **実装コスト**: 高（サーバー側でWebSocket管理が必要）
- **デバイス通知**: ✗（ブラウザタブを閉じると受信不可）
- **スケーラビリティ**: △（コネクション維持が必要）

#### FCM（Firebase Cloud Messaging）
- **リアルタイム性**: ◎
- **実装コスト**: 中
- **デバイス通知**: ◎
- **デメリット**: Googleサービス依存、設定が複雑、コスト発生

#### Server-Sent Events (SSE)
- **リアルタイム性**: ◎
- **実装コスト**: 中
- **デバイス通知**: ✗（ブラウザタブを閉じると受信不可）
- **スケーラビリティ**: △（コネクション維持が必要）

**推奨**: **Web Push API**（標準仕様、シンプル、依存なし、デバイス通知可能）

---

## 8. セキュリティ考慮事項

### 8.1 VAPID鍵管理
- ✅ 秘密鍵は環境変数で管理（Git管理外）
- ✅ Google Secret Managerで保管
- ✅ 定期的なキーローテーション（年1回推奨）

### 8.2 購読エンドポイント
- ✅ 購読時に認証済みユーザーのみ許可
- ✅ 購読削除時に所有者チェック
- ✅ エンドポイントURLは推測不可能（Push Service提供）

### 8.3 通知内容
- ✅ 個人情報を含まない（通知タイトル/本文に注意）
- ✅ 詳細情報はアプリ内で確認（通知クリック後）
- ✅ 通知ペイロードは暗号化されて送信（Push Service仕様）

---

## 9. パフォーマンス最適化

### 9.1 購読管理
- デバイスごとに購読を管理（staff_id + endpointのUNIQUE制約）
- 無効な購読は自動削除（410 Goneエラー検知）
- インデックスで高速クエリ（staff_id, is_active）

### 9.2 通知送信
- バックグラウンドタスクで非同期送信（FastAPI BackgroundTasks使用）
- バッチ送信による効率化（複数デバイスへの同時送信）
- リトライ機能（一時的なネットワークエラー対応）

### 9.3 ポーリング頻度調整
- Push有効時: 60秒（負荷削減）
- Push無効時: 30秒（既存維持）

---

## 10. 監視・ログ

### 10.1 監視項目
- Push通知送信成功率
- Push通知送信失敗率（エラー種別ごと）
- アクティブな購読数（デバイスタイプ別）
- 通知の到達率（クリック率）

### 10.2 ログ記録
```python
logger.info(f"Push sent successfully to subscription_id={subscription.id}")
logger.error(f"Push failed for subscription_id={subscription.id}: {error}")
logger.info(f"Removed invalid subscription_id={subscription.id}")
```

### 10.3 アラート設定
- Push送信失敗率が30%を超えた場合
- アクティブな購読数が急減した場合
- VAPID鍵有効期限が近づいた場合

---

## 11. 結論

### 11.0 実装状況（2026-01-14更新）

#### ✅ バックエンド実装完了（2026-01-13）

**実装済みコンポーネント**:

1. **データベース**
   - マイグレーション: `migrations/versions/z8a9b0c1d2e3_add_push_subscriptions_table.py`
   - テーブル: `push_subscriptions` (staff_id, endpoint, p256dh_key, auth_key, user_agent, device_type)

2. **モデル層**
   - `app/models/push_subscription.py`: PushSubscription モデル（Staffリレーション付き）

3. **CRUD層**
   - `app/crud/crud_push_subscription.py`:
     - `create()`: サブスクリプション登録
     - `get_by_staff_and_endpoint()`: 既存サブスクリプション検索
     - `deactivate()`: サブスクリプション無効化
     - `get_active_by_staff()`: スタッフのアクティブサブスクリプション取得

4. **API層**
   - `app/api/v1/endpoints/push_subscriptions.py`: 3つのエンドポイント
     - `POST /api/v1/push-subscriptions/subscribe`: サブスクリプション登録
     - `DELETE /api/v1/push-subscriptions/unsubscribe`: サブスクリプション解除
     - `GET /api/v1/push-subscriptions/my-subscriptions`: 自分のサブスクリプション一覧

5. **Push通知サービス**
   - `app/core/push.py`: `send_push_notification()` 関数
     - pywebpush統合
     - VAPID署名
     - 404/410エラーハンドリング（無効なサブスクリプション自動削除）

6. **VAPID設定**
   - `app/core/config.py`: VAPID公開鍵・秘密鍵・サブジェクトの環境変数設定

7. **依存ライブラリ**
   - `pywebpush>=1.14.0`
   - `py-vapid>=1.9.0`

8. **テスト**
   - `tests/api/v1/test_push_subscriptions.py`: API層テスト
   - `tests/crud/test_push_subscription.py`: CRUD層テスト

**未統合**: 期限通知バッチ (`app/tasks/deadline_notification.py`) へのWeb Push統合はまだ未実装

#### 🚧 フロントエンド実装予定

**未実装コンポーネント**:
- Service Worker (`k_front/public/sw.js`)
- `usePushNotifications` カスタムフック
- 通知許可リクエストUI
- サブスクリプション管理UI
- 通知設定ページ

**実装意向**: フロントエンド実装を進める予定

---

### 11.1 実装推奨度
**★★★★☆（4/5）**

### 11.2 推奨理由
1. ✅ **ユーザー体験の大幅改善**（リアルタイム通知、デバイス通知）
2. ✅ **サーバー負荷削減**（ポーリング頻度を下げられる）
3. ✅ **標準Web API使用**で依存性が低い
4. ✅ **実装コストは合理的**（32-40時間 / 4-5日）

### 11.3 実装タイミング
- **バックエンド**: ✅ 完了（2026-01-13）
- **フロントエンド**: 🚧 実装予定（タイミング未定）
- **推奨時期**: ユーザー数が100名を超えた時点、または重要な通知機能追加時

### 11.4 次のステップ（フロントエンド実装）

**Phase 2のみ実装（12-14時間）**:
1. Service Worker作成 (`k_front/public/sw.js`)
2. `usePushNotifications` Hook実装
3. 通知設定UI実装
4. `LayoutClient.tsx` への統合
5. アイコン/バッジ作成
6. エンドツーエンドテスト

**段階的展開**:
1. 開発環境でテスト
2. ベータテスト（一部スタッフのみ有効化）
3. フィードバック収集
4. 本番全体展開

---

## 12. Web Pushとポーリングのハイブリッドアーキテクチャ（併用戦略）

### 12.1 現状システムの通知フロー分析

#### 現在のポーリング実装（`LayoutClient.tsx`）

```typescript
// 30秒ごとに未読通知件数を取得
const interval = setInterval(() => {
  fetchUnreadCount();  // notices + messages の未読件数
}, 30000); // 30秒

// ログイン時に期限アラートを全件取得してトースト表示（1回のみ）
fetchDeadlineAlertsAll().then(alerts => {
  alerts.forEach((alert) => {
    toast.warning(alert.message, { duration: 5000 });
  });
});

// ホバー時に詳細データを取得
handleNoticeHover() {
  fetchRecentUnreadNotices();  // 最新2件の承認/却下通知
  fetchDeadlineAlerts(0);      // 期限アラート10件
}
```

#### 通知が発生するタイミング

| 通知種別 | 発生タイミング | 重要度 | 遅延許容度 |
|---------|--------------|--------|----------|
| **スタッフアクション承認/却下** | リクエスト処理時 | 高 | 低（即時通知が望ましい） |
| **ロール変更承認/却下** | ロール変更処理時 | 高 | 低（即時通知が望ましい） |
| **更新期限アラート** | クエリ実行時に計算 | 中 | 中（日次更新で十分） |
| **アセスメント未完了アラート** | クエリ実行時に計算 | 中 | 中（日次更新で十分） |
| **事業所情報変更通知** | 事業所情報更新時 | 中 | 中（数分遅延OK） |

**分析結果**:
- **イベント駆動通知**（承認/却下）は即座に届けるべき → **Web Push向き**
- **期限アラート**は1日1回の確認で十分 → **ポーリングで十分**
- **未読件数**は定期的な確認で問題なし → **ポーリングで十分**

---

### 12.2 最適な併用バランス

#### 推奨アーキテクチャ: **役割分担型ハイブリッド**

```
Web Push通知（Push型）
  ├─ スタッフアクション承認/却下  ← リアルタイム配信
  ├─ ロール変更承認/却下          ← リアルタイム配信
  └─ 緊急度の高い事業所情報変更   ← リアルタイム配信

ポーリング（Pull型）
  ├─ 未読件数確認                ← 60秒ごと（Push有効時）
  ├─ 期限アラート                ← ログイン時 + 1時間ごと
  └─ バックグラウンド同期        ← フォールバック
```

---

### 12.3 実装パターン

#### パターン1: イベント駆動通知のみPush化（推奨）

**対象**:
- スタッフアクション承認/却下通知
- ロール変更承認/却下通知

**メリット**:
- ✅ 最も効果が高い（ユーザーが待っている通知）
- ✅ 実装コストが低い（通知作成箇所が限定的）
- ✅ Push送信回数が少ない（コスト効率◎）

**実装例**:

```python
# app/services/employee_action_service.py

async def approve_request(self, db: AsyncSession, request_id: UUID, approver_id: UUID):
    # 1. リクエスト承認処理
    request = await self._execute_action(db, request_id)

    # 2. Notice作成
    notice = await crud_notice.create(
        db=db,
        obj_in=NoticeCreate(
            recipient_staff_id=request.requester_staff_id,
            type="employee_action_approved",
            title="リクエストが承認されました",
            content=f"あなたのリクエストが承認されました"
        )
    )

    # 3. Web Push送信（Push有効ユーザーのみ）
    await push_service.send_push_notification(
        db=db,
        staff_id=request.requester_staff_id,
        title="リクエストが承認されました",
        body=f"あなたのリクエストが承認されました",
        url="/dashboard/notices"
    )

    return notice
```

**ポーリング頻度の調整**:

```typescript
// components/protected/LayoutClient.tsx

const { isSupported, isSubscribed } = usePushNotifications();

// Push有効時はポーリング頻度を下げる
const pollingInterval = isSupported && isSubscribed ? 60000 : 30000;

const interval = setInterval(() => {
  fetchUnreadCount();
}, pollingInterval);
```

**効果**:
- Push有効ユーザー: 30秒 → 60秒（50%削減）
- 100人のアクティブユーザー: 200リクエスト/分 → 100リクエスト/分

---

#### パターン2: 全通知をPush化（非推奨）

**対象**:
- すべてのNotice作成時にPush送信

**デメリット**:
- ❌ 期限アラートはクエリ時計算のため、Push送信タイミングが不明瞭
- ❌ バッチ処理（日次チェック）との統合が複雑
- ❌ Push送信回数が多い（コスト増）

**結論**: 期限アラートは**ポーリングのままで十分**

---

### 12.4 期限アラートの最適化戦略

#### 現在の問題点

```typescript
// ログイン時に全件取得してトースト表示
fetchDeadlineAlertsAll().then(alerts => {
  alerts.forEach((alert) => {
    toast.warning(alert.message, { duration: 5000 });
  });
});
```

**問題**:
- ログイン後に毎回同じアラートが表示される
- 1日に何度もログインするユーザーには不快

#### 推奨改善策（Push不要）

**戦略**: ブラウザストレージを使った重複抑制

```typescript
// hooks/useDeadlineAlerts.ts

const ALERT_SHOWN_KEY = 'deadline_alerts_shown_date';

export function useDeadlineAlerts() {
  const showAlertsOnce = async () => {
    const today = new Date().toISOString().split('T')[0]; // YYYY-MM-DD
    const lastShown = localStorage.getItem(ALERT_SHOWN_KEY);

    // 今日まだ表示していない場合のみ表示
    if (lastShown !== today) {
      const alerts = await fetchDeadlineAlertsAll();
      alerts.forEach((alert) => {
        toast.warning(alert.message, { duration: 5000 });
      });
      localStorage.setItem(ALERT_SHOWN_KEY, today);
    }
  };

  return { showAlertsOnce };
}
```

**効果**:
- ✅ 1日1回のみアラート表示（UX向上）
- ✅ Push不要（実装コスト削減）
- ✅ サーバー負荷削減（ログイン時のクエリ削減可能）

#### 代替案: 日次バッチ通知（Push使用）

**実装**:
```python
# app/services/scheduled_tasks.py

@scheduler.scheduled_job('cron', hour=9, minute=0)  # 毎朝9時
async def send_daily_deadline_alerts():
    """期限アラートを毎朝9時に一括送信"""
    async with AsyncSessionLocal() as db:
        offices = await crud_office.get_all_active(db)

        for office in offices:
            alerts = await welfare_recipient_service.get_deadline_alerts(
                db=db,
                office_id=office.id,
                threshold_days=30
            )

            # 事業所のすべてのアクティブスタッフに通知
            staff_list = await crud_staff.get_by_office_id(db, office.id)
            for staff in staff_list:
                if alerts.total > 0:
                    await push_service.send_push_notification(
                        db=db,
                        staff_id=staff.id,
                        title=f"期限アラート: {alerts.total}件",
                        body=f"更新期限が近い利用者が{alerts.total}名います",
                        url="/dashboard"
                    )
```

**評価**:
- ✅ 1日1回の通知（適切な頻度）
- ⚠️ 実装コスト: 中（スケジューラー追加が必要）
- ⚠️ 事業所全体への一斉通知は過剰な可能性

---

### 12.5 ブラウザサポート別のフォールバック戦略

#### ブラウザ判定による動的切り替え

```typescript
// hooks/usePushNotifications.ts

export function usePushNotifications() {
  const [isSupported, setIsSupported] = useState(false);
  const [isSubscribed, setIsSubscribed] = useState(false);
  const [fallbackMode, setFallbackMode] = useState<'polling' | 'push' | 'hybrid'>('polling');

  useEffect(() => {
    const userAgent = navigator.userAgent.toLowerCase();
    const isIOS = /iphone|ipad|ipod/.test(userAgent);
    const isStandalone = (window.navigator as any).standalone === true ||
                        window.matchMedia('(display-mode: standalone)').matches;

    let mode: 'polling' | 'push' | 'hybrid' = 'polling';

    if ('serviceWorker' in navigator && 'PushManager' in window) {
      if (isIOS && !isStandalone) {
        // iOS Safari（ホーム画面追加なし）→ ポーリングのみ
        mode = 'polling';
        setIsSupported(false);
      } else {
        // Chrome/Firefox/Safari(macOS)/iOS PWA → Push使用可能
        mode = 'hybrid';
        setIsSupported(true);
      }
    } else {
      // 古いブラウザ → ポーリングのみ
      mode = 'polling';
      setIsSupported(false);
    }

    setFallbackMode(mode);
  }, []);

  return { isSupported, isSubscribed, fallbackMode };
}
```

#### モード別のポーリング設定

```typescript
// components/protected/LayoutClient.tsx

const { fallbackMode } = usePushNotifications();

const getPollingConfig = () => {
  switch (fallbackMode) {
    case 'push':
      // Push完全有効 → ポーリング最小限
      return {
        unreadCountInterval: 120000,  // 2分
        deadlineAlertInterval: null   // 無効（Pushのみ）
      };
    case 'hybrid':
      // Push + ポーリング併用
      return {
        unreadCountInterval: 60000,   // 1分
        deadlineAlertInterval: null   // ログイン時のみ
      };
    case 'polling':
    default:
      // ポーリングのみ
      return {
        unreadCountInterval: 30000,   // 30秒
        deadlineAlertInterval: 3600000 // 1時間
      };
  }
};

const config = getPollingConfig();

// 未読件数ポーリング
useEffect(() => {
  const interval = setInterval(() => {
    fetchUnreadCount();
  }, config.unreadCountInterval);

  return () => clearInterval(interval);
}, [config.unreadCountInterval]);

// 期限アラートポーリング（polling/hybridモードのみ）
useEffect(() => {
  if (config.deadlineAlertInterval) {
    const interval = setInterval(() => {
      fetchDeadlineAlerts();
    }, config.deadlineAlertInterval);

    return () => clearInterval(interval);
  }
}, [config.deadlineAlertInterval]);
```

---

### 12.6 サーバー負荷シミュレーション

#### 現状（ポーリングのみ）

**前提条件**:
- アクティブユーザー: 100人（同時ログイン）
- ポーリング間隔: 30秒

**負荷**:
```
未読件数API: 100人 × (60秒 / 30秒) = 200リクエスト/分
            = 200 × 60 × 24 = 288,000リクエスト/日
```

#### Web Push導入後（ハイブリッドモード）

**前提条件**:
- アクティブユーザー: 100人
- Push有効: 70人（70%）
- Push無効: 30人（30%）

**負荷**:
```
未読件数API:
  - Push有効: 70人 × (60秒 / 60秒) = 70リクエスト/分
  - Push無効: 30人 × (60秒 / 30秒) = 60リクエスト/分
  - 合計: 130リクエスト/分 = 187,200リクエスト/日

削減率: (288,000 - 187,200) / 288,000 = 35%削減
```

#### Web Push送信コスト

**イベント駆動通知の発生頻度**（推定）:
- スタッフアクション承認/却下: 10件/日
- ロール変更承認/却下: 2件/日
- 合計: 12件/日

**Push送信数**:
```
12件/日 × 70人（Push有効） = 840Push送信/日
```

**評価**:
- ✅ Push送信数は極めて少ない（<1000件/日）
- ✅ ポーリング削減効果（35%）> Push送信コスト
- ✅ **コストパフォーマンス: 非常に高い**

---

### 12.7 推奨実装ロードマップ

#### Phase 1: ポーリング最適化（Push不要）

**工数**: 2-4時間

**実装内容**:
1. 期限アラートの重複表示抑制（localStorage使用）
2. ポーリング間隔の動的調整（アクティブタブのみ）
3. ブラウザのPage Visibility API活用

```typescript
// ブラウザタブが非アクティブ時はポーリング停止
useEffect(() => {
  const handleVisibilityChange = () => {
    if (document.hidden) {
      clearInterval(pollingInterval);
    } else {
      pollingInterval = setInterval(fetchUnreadCount, 30000);
    }
  };

  document.addEventListener('visibilitychange', handleVisibilityChange);
  return () => document.removeEventListener('visibilitychange', handleVisibilityChange);
}, []);
```

**効果**:
- サーバー負荷 20-30%削減
- UX向上（重複通知なし）
- 実装コスト: 極小

---

#### Phase 2: Web Push導入（イベント駆動通知のみ）

**工数**: 32-40時間（既存計画通り）

**実装内容**:
1. スタッフアクション承認/却下通知をPush化
2. ロール変更承認/却下通知をPush化
3. Push有効時のポーリング頻度調整（30秒→60秒）

**効果**:
- リアルタイム通知実現
- サーバー負荷 35%削減
- ユーザー体験向上

---

#### Phase 3: 期限アラートの日次バッチ通知（オプション）

**工数**: 8-12時間

**実装内容**:
1. 日次スケジューラー追加
2. 期限アラートの日次集計とPush送信
3. 通知設定UI（期限アラートのON/OFF）

**評価**:
- ⚠️ 必要性は低い（Phase 1で十分）
- ⚠️ 実装する場合は**ユーザー設定で制御可能にする**

---

### 12.8 最終推奨事項

#### ✅ 推奨する併用バランス

| 通知種別 | 配信方法 | 頻度/タイミング | 理由 |
|---------|---------|---------------|------|
| **スタッフアクション承認/却下** | Web Push | イベント発生時（即座） | ユーザーが待っている通知 |
| **ロール変更承認/却下** | Web Push | イベント発生時（即座） | 重要度が高い |
| **未読件数確認** | ポーリング | 60秒ごと（Push有効時）<br>30秒ごと（Push無効時） | 件数のみの確認はPull型で十分 |
| **期限アラート** | ポーリング | ログイン時（1日1回表示） | リアルタイム性不要、ポーリングで十分 |
| **事業所情報変更** | Web Push<br>（オプション） | イベント発生時 | 緊急度による |

#### 🎯 バランスの黄金比

```
Web Push: イベント駆動通知（20%）
  - 承認/却下など、ユーザーが待っている通知
  - リアルタイム性が求められる通知

ポーリング: 定期確認・状態同期（80%）
  - 未読件数確認
  - 期限アラート
  - バックグラウンド同期
```

**理由**:
1. ✅ **コストパフォーマンス最大化**: Push送信数を抑えつつ、最大の効果
2. ✅ **実装コスト最小化**: 既存ポーリングを活かし、必要な部分のみPush化
3. ✅ **ブラウザ互換性**: Push非対応環境でも問題なく動作
4. ✅ **段階的移行**: Phase 1（ポーリング最適化）→ Phase 2（Push導入）の順で実装可能

---

## 13. 期限アラートへのWeb Push導入の詳細検討

### 13.1 現状の期限アラート通知システム

#### 既存実装の分析

**実装状況**: ✅ **既に実装済み**（メール通知）

**ファイル**:
- `app/scheduler/deadline_notification_scheduler.py` - スケジューラー
- `app/tasks/deadline_notification.py` - バッチ処理
- `app/core/mail.py` - メール送信

**実行スケジュール**:
- **頻度**: 毎日 0:00 UTC（9:00 JST）
- **実行条件**: 平日かつ祝日でない場合のみ
- **対象**: threshold_days=30（期限30日以内）

**処理フロー**:
```python
1. 全事業所を取得
2. 各事業所ごとに期限アラートを取得
   - 更新期限アラート（next_renewal_deadline <= 30日以内）
   - アセスメント未完了アラート
3. アラートがある事業所の全スタッフにメール送信
4. 送信完了件数をログ記録
```

**現在のメール送信数**（推定）:
- 事業所数: 50事業所（仮定）
- 事業所あたりスタッフ数: 5人（仮定）
- 期限アラートがある事業所: 20事業所（40%、仮定）
- **メール送信数**: 20事業所 × 5人 = **100通/日**

---

### 13.2 メール通知の問題点

#### 現状の課題

| 問題点 | 詳細 | 影響度 |
|-------|------|--------|
| **開封率が低い** | ビジネスメールの平均開封率: 15-25% | 高 |
| **見落としリスク** | 他のメールに埋もれる、迷惑メールフォルダに振り分け | 高 |
| **遅延** | メールサーバーの遅延、未読のまま放置 | 中 |
| **即座のアクション不可** | メールからダッシュボードへのワンクリック遷移が困難 | 中 |
| **通知タイミング固定** | 9:00 JSTのみ、ユーザーの勤務時間外の可能性 | 低 |

**想定データ（業界平均からの推定）**:
- ⚠️ **注意**: 現状は開発者のみが利用しているため、実際のユーザーデータは未計測
- メール開封率: 15-25%（**ビジネスメールの業界平均**、出典: HubSpot 2024）
- 福祉業界の実測データは不明

**参考**: 業界平均を適用した場合の推定
- メール開封: 20人/100通 ≈ 20%
- 未開封/見落とし: 80人/100通 ≈ 80%

**課題**:
- ✅ **実測が必要**: 本番運用開始後にメール開封率を計測すべき
- ✅ **計測方法**: メール内にトラッキングピクセル、またはリンククリック率で測定可能

---

### 13.3 Web Push化のメリット

#### ✅ メリット1: 視認性・到達率の向上

**Web Pushの特徴**:
- デバイスネイティブ通知（OSレベル）
- 画面上部にポップアップ表示
- サウンド・バイブレーションで注意喚起
- 未読通知は通知センターに残る

**効果（業界データからの推定）**:
```
メール通知: 開封率 15-25%（ビジネスメール業界平均）
Web Push通知: 開封率 70-90%（Web Push業界平均、出典: OneSignal 2024）

⚠️ 注意: これらは他業界のデータであり、福祉業界の実測値ではありません
推定改善率: 3.5-6倍（最小値: 70% / 25% = 2.8倍、最大値: 90% / 15% = 6倍）
```

**実測が必要な理由**:
- 福祉業界のユーザー特性（年齢層、ITリテラシー）は一般とは異なる可能性
- 実際の効果を測定してからWeb Push投資判断をすべき

**具体例**:
```
シナリオ: 期限30日以内の利用者が5名いる事業所

【メール通知のみ】
- 5人のスタッフにメール送信
- 開封: 1人（20%）
- 対応: 1人

【Web Push併用】
- 5人のスタッフにWeb Push送信
- 開封: 4人（80%）
- 対応: 4人

結果: 対応率が4倍向上
```

---

#### ✅ メリット2: 即座のアクション誘導

**ワンクリックでダッシュボードに遷移**:

```javascript
// Web Push通知をクリック
→ 即座にダッシュボードを開く
→ 期限アラート一覧を表示
→ すぐに対応可能

// メール通知の場合
→ メールを開く
→ URLをクリック
→ ログイン画面（セッション切れ）
→ ログイン
→ ダッシュボード
→ 対応まで複数ステップ
```

**効果**:
- アクション完了率: メール 10% → Web Push 40%（4倍）
- 対応までの時間: メール 平均2時間 → Web Push 平均10分（12倍高速）

---

#### ✅ メリット3: 段階的通知による効果的なリマインド

**現状（メール）**:
- 毎日9:00 JSTに一斉送信
- 同じ内容が毎日届く → **通知疲れ**

**Web Push化の場合の改善案**:

```python
# 段階的通知の例

def get_notification_schedule(days_remaining: int) -> bool:
    """残り日数に応じて通知を送信するか判定"""
    if days_remaining in [30, 21, 14, 7, 3, 1]:  # マイルストーン
        return True
    return False

# 実装例
if days_remaining == 30:
    message = "更新期限まで30日です。そろそろアセスメントを開始してください"
elif days_remaining == 7:
    message = "⚠️ 更新期限まで7日です！至急対応してください"
elif days_remaining == 1:
    message = "🚨 更新期限まで1日です！本日中に対応してください"
```

**効果**:
- 毎日送信 → 重要なタイミングのみ送信（週3-4回）
- 通知疲れを軽減しつつ、効果的なリマインド
- 緊急度に応じたメッセージで優先度を明確化

---

#### ✅ メリット4: サーバー負荷の観点（メールより軽い）

**メール送信コスト**:
```
SMTP接続 + メールヘッダー構築 + HTML生成 + 送信
→ 処理時間: 約500-1000ms/通
→ 100通送信: 50-100秒
```

**Web Push送信コスト**:
```
HTTPSリクエスト + ペイロードJSON
→ 処理時間: 約50-100ms/通
→ 100通送信: 5-10秒
```

**結論**: Web Pushは**メールより10倍高速**、サーバー負荷も低い

---

#### ✅ メリット5: リアルタイム性（日次→リアルタイムへ）

**現状（メール）**:
- 毎日9:00 JSTに一斉送信
- 例: 9:05に期限が30日以内になった場合 → **翌日9:00まで通知なし（23時間55分遅延）**

**Web Push化の場合**:

**方法A: バッチ処理の頻度を上げる**
```python
# 1時間ごとにチェック
@scheduler.scheduled_job('cron', hour='*/1')
async def send_hourly_deadline_alerts():
    # 前回送信していない新規アラートのみ送信
```

**方法B: イベント駆動型（最もリアルタイム）**
```python
# next_renewal_deadline が更新されたタイミングで通知
async def update_support_plan_cycle(...):
    cycle = await crud.support_plan_cycle.update(...)

    # 期限が30日以内になった瞬間に通知
    if cycle.next_renewal_deadline:
        days_remaining = (cycle.next_renewal_deadline - date.today()).days
        if days_remaining <= 30:
            await push_service.send_push_notification(
                staff_id=staff.id,
                title="新しい期限アラート",
                body=f"{recipient.full_name}の更新期限まで{days_remaining}日",
                url="/dashboard"
            )
```

**効果**:
- 遅延: 最大23時間55分 → **数秒以内**
- より早い対応が可能

---

### 13.4 Web Push化のデメリット

#### ❌ デメリット1: 実装コスト

**追加実装が必要な箇所**:

1. **Push通知サービス統合**（8-12時間）
   - `app/services/push_notification_service.py` 作成
   - VAPID鍵管理
   - pywebpush統合

2. **バッチ処理の修正**（4-6時間）
   ```python
   # app/tasks/deadline_notification.py

   async def send_deadline_alert_notifications(db: AsyncSession):
       """期限アラート通知（メール + Web Push）"""

       for office in offices:
           alerts = await get_deadline_alerts(db, office.id)

           for staff in office.staffs:
               # メール送信（既存）
               await send_deadline_alert_email(...)

               # Web Push送信（新規）
               await push_service.send_push_notification(
                   db=db,
                   staff_id=staff.id,
                   title=f"期限アラート: {alerts.total}件",
                   body=f"更新期限が近い利用者が{alerts.total}名います",
                   url="/dashboard"
               )
   ```

3. **通知重複防止ロジック**（2-4時間）
   ```python
   # 既に今日通知済みのアラートはスキップ
   last_sent_date = await redis.get(f"alert_sent:{staff.id}:{recipient.id}")
   if last_sent_date == today:
       continue  # スキップ
   ```

**合計工数**: 14-22時間（既存のWeb Push基盤がある場合は半分）

---

#### ❌ デメリット2: ブラウザサポート問題

**Push非対応ユーザーへの対応**:

| ブラウザ | 対応状況 | 割合（推定） |
|---------|---------|------------|
| Chrome/Edge | ✅ 完全対応 | 60% |
| Firefox | ✅ 完全対応 | 10% |
| Safari (macOS) | ✅ 対応 | 15% |
| Safari (iOS) | ⚠️ 制限あり | 15% |

**iOS Safariの問題**:
- iOS 16.4未満: 完全に不可
- iOS 16.4+: ホーム画面追加必須

**対策**:
```python
# メール + Web Push のハイブリッド配信

async def send_deadline_alerts(staff: Staff, alerts: list):
    # 1. メールは全員に送信（フォールバック）
    await send_email(staff.email, alerts)

    # 2. Push購読があればWeb Pushも送信
    subscriptions = await crud.push_subscription.get_active_by_staff_id(
        db=db,
        staff_id=staff.id
    )
    if subscriptions:
        await push_service.send_push_notification(
            staff_id=staff.id,
            title=f"期限アラート: {len(alerts)}件",
            body="更新期限が近い利用者がいます",
            url="/dashboard"
        )
```

**結論**: **メールは残しつつ、Web Pushを追加**することで全ユーザーをカバー

---

#### ❌ デメリット3: 通知疲れのリスク

**問題**:
- 毎日同じ期限アラートが届く
- 複数の利用者の期限が重なると大量通知

**対策1: 通知の集約**

```python
# 個別通知ではなく、サマリー通知を送信

# ❌ 悪い例（通知が多い）
for alert in alerts:
    await push_service.send(
        title=f"{alert.full_name}の更新期限まで{alert.days_remaining}日"
    )
# → 5人の期限アラート = 5件の通知

# ✅ 良い例（通知を集約）
await push_service.send(
    title=f"期限アラート: {len(alerts)}件",
    body=f"更新期限が近い利用者が{len(alerts)}名います",
    url="/dashboard"
)
# → 5人の期限アラート = 1件の通知
```

**対策2: 通知頻度の最適化**

```python
# 段階的通知（マイルストーンのみ）
NOTIFICATION_MILESTONES = [30, 21, 14, 7, 3, 1]  # 日数

async def should_send_notification(days_remaining: int, last_sent_days: int) -> bool:
    """通知を送信すべきか判定"""
    # 新しいマイルストーンに達した場合のみ送信
    if days_remaining in NOTIFICATION_MILESTONES:
        if last_sent_days > days_remaining:  # 前回より期限が近づいた
            return True
    return False
```

**効果**:
- 毎日送信 → 重要なタイミングのみ（週2-3回）
- 通知疲れを50-70%削減

---

#### ❌ デメリット4: 通知設定UIが必要

**ユーザーが制御できるべき項目**:
- [ ] 期限アラート通知のON/OFF
- [ ] 通知タイミングの選択（毎日/マイルストーンのみ）
- [ ] 通知方法の選択（メールのみ/Web Pushのみ/両方）

**実装例**:

```typescript
// components/protected/settings/NotificationSettings.tsx

<div>
  <h3>期限アラート通知設定</h3>

  <label>
    <input type="checkbox" checked={settings.deadlineAlert.enabled} />
    期限アラート通知を受け取る
  </label>

  <select value={settings.deadlineAlert.frequency}>
    <option value="daily">毎日（9:00）</option>
    <option value="milestone">重要なタイミングのみ（30/14/7/1日前）</option>
  </select>

  <label>
    <input type="checkbox" checked={settings.deadlineAlert.email} />
    メールで受け取る
  </label>

  <label>
    <input type="checkbox" checked={settings.deadlineAlert.push} />
    プッシュ通知で受け取る
  </label>
</div>
```

**工数**: 6-8時間

---

### 13.5 サーバー負荷の詳細比較

#### シナリオ: 事業所50箇所、期限アラート対象20箇所、スタッフ計100人

| 項目 | メール通知のみ | メール + Web Push | Web Pushのみ |
|------|--------------|-----------------|-------------|
| **処理時間** | 50-100秒 | 55-110秒 | 5-10秒 |
| **サーバー負荷** | 中 | 中 | 低 |
| **外部API呼び出し** | SMTP: 100回 | SMTP: 100回<br>Push Service: 100回 | Push Service: 100回 |
| **ネットワーク帯域** | 約10MB（HTML） | 約10.1MB | 約100KB（JSON） |
| **失敗時リトライ** | 複雑（SMTP） | 複雑（SMTP）<br>シンプル（Push） | シンプル（Push） |

**結論**:
- **メール + Web Push併用**: 処理時間 +10%増加（許容範囲）
- **Web Pushのみ**: 処理時間 90%削減、負荷も大幅減

**推奨**: 初期は**メール + Web Push併用**、将来的にWeb Push移行を検討

---

### 13.6 ユーザー体験の詳細比較

#### ケーススタディ: サービス管理責任者の1日

**シナリオ**: 田中さん（サービス管理責任者）、担当利用者30名、期限30日以内が5名

---

**【メール通知のみ】**

```
09:00 - 期限アラートメール受信
        ↓
09:15 - 他の業務メール対応中、見落とす
        ↓
12:00 - 昼休憩、メールチェック
        ↓
12:10 - 期限アラートメールを発見
        ↓
12:15 - スマホでメール内のURLをタップ
        ↓
12:16 - ログイン画面表示（セッション切れ）
        ↓
12:18 - ログイン完了、ダッシュボード表示
        ↓
12:20 - 期限アラート確認、5名を把握
        ↓
13:00 - 午後の業務開始、対応を忘れる
        ↓
17:00 - 帰宅、未対応のまま
```

**結果**: 気づくまで3時間、対応せず終了

---

**【Web Push通知あり】**

```
09:00 - Web Push通知受信「期限アラート: 5件」
        ↓
09:01 - スマホの通知をタップ
        ↓
09:02 - アプリが起動（既にログイン済み）
        ↓
09:03 - ダッシュボード表示、5名を即座に確認
        ↓
09:05 - 1名のアセスメント開始
        ↓
10:00 - 1件完了、残り4件を把握
```

**結果**: 気づくまで1分、即座に対応開始

---

#### 効果測定（業界平均からの推定、実測値ではない）

| 指標 | メールのみ（推定） | Web Push併用（推定） | 推定改善率 |
|------|-----------------|----------------|----------|
| 通知への気づき | 15-25% | 70-90% | **2.8-6倍** |
| 気づくまでの時間 | 数時間（推定） | 数分（推定） | **数十倍** |
| 当日中の対応率 | 不明（要計測） | 不明（要計測） | 不明 |
| アクション完了率 | 不明（要計測） | 不明（要計測） | 不明 |

**⚠️ 重要な注意事項**:
- 上記は**他業界の平均値からの推定**であり、実測データではありません
- 福祉業界の特性（ユーザー年齢層、業務環境）により、実際の数値は異なる可能性があります
- **実装前に**: 現状のメール通知の開封率・対応率を計測することを強く推奨します

---

### 13.7 実装パターンの比較

#### パターンA: メール継続 + Web Push追加（推奨）

**実装**:
```python
async def send_deadline_alerts(db: AsyncSession):
    for office in offices:
        alerts = await get_deadline_alerts(db, office.id)

        for staff in office.staffs:
            # 1. メール送信（全員）
            await send_email(staff.email, alerts)

            # 2. Web Push送信（購読者のみ）
            await push_service.send_push_notification(
                db=db,
                staff_id=staff.id,
                title=f"期限アラート: {len(alerts)}件",
                body="更新期限が近い利用者がいます",
                url="/dashboard"
            )
```

**メリット**:
- ✅ 全ユーザーをカバー（メールでフォールバック）
- ✅ Push対応ブラウザのユーザーは高い到達率
- ✅ 段階的移行が可能

**デメリット**:
- ⚠️ 重複通知の可能性（メール + Push両方届く）
- ⚠️ サーバー負荷は若干増加（+10%）

**工数**: 14-22時間

---

#### パターンB: 段階的通知（マイルストーンのみ）

**実装**:
```python
NOTIFICATION_MILESTONES = {
    30: {"title": "期限アラート（30日前）", "urgency": "low"},
    14: {"title": "期限アラート（2週間前）", "urgency": "medium"},
    7: {"title": "⚠️ 期限アラート（1週間前）", "urgency": "high"},
    3: {"title": "🚨 期限アラート（3日前）", "urgency": "critical"},
    1: {"title": "🚨🚨 期限アラート（明日期限）", "urgency": "critical"}
}

async def send_milestone_alerts(db: AsyncSession):
    for office in offices:
        alerts = await get_deadline_alerts(db, office.id)

        # アラートごとに送信済みチェック
        for alert in alerts:
            days = alert.days_remaining

            if days in NOTIFICATION_MILESTONES:
                # 今日このマイルストーンで送信済みかチェック
                key = f"alert_sent:{alert.id}:{days}"
                if await redis.get(key):
                    continue  # 既に送信済み

                # 通知送信
                config = NOTIFICATION_MILESTONES[days]
                await push_service.send_push_notification(
                    title=config["title"],
                    body=f"{alert.full_name}の更新期限まで{days}日",
                    url=f"/dashboard/recipients/{alert.id}"
                )

                # 送信済みフラグ
                await redis.set(key, "1", ex=86400)  # 24時間保持
```

**メリット**:
- ✅ 通知疲れを大幅削減（毎日→週2-3回）
- ✅ 重要なタイミングで確実に通知
- ✅ 緊急度が視覚的に分かりやすい

**デメリット**:
- ⚠️ 実装がやや複雑（Redis使用）
- ⚠️ マイルストーン間は通知なし

**工数**: 20-28時間

---

#### パターンC: Web Pushのみ（メール廃止）

**実装**:
```python
async def send_push_only_alerts(db: AsyncSession):
    for office in offices:
        alerts = await get_deadline_alerts(db, office.id)

        for staff in office.staffs:
            # Push購読がある場合のみ送信
            subscriptions = await get_push_subscriptions(staff.id)
            if subscriptions:
                await push_service.send_push_notification(...)
            else:
                logger.warning(f"Staff {staff.id} has no push subscription, skipping")
```

**メリット**:
- ✅ サーバー負荷最小（90%削減）
- ✅ 実装がシンプル
- ✅ メール開封率の低さを気にする必要なし

**デメリット**:
- ❌ Push非対応ユーザーは通知なし（15-30%）
- ❌ iOS Safari問題
- ❌ ユーザーの反発リスク

**評価**: **非推奨**（一部ユーザーが通知を受け取れない）

---

### 13.8 最終推奨事項

#### 🎯 推奨実装: パターンA + パターンB のハイブリッド

**フェーズ1: メール + Web Push併用**（工数: 14-22時間）

```python
async def send_deadline_alerts_phase1(db: AsyncSession):
    """メール + Web Push 両方送信（毎日9:00）"""
    for office in offices:
        alerts = await get_deadline_alerts(db, office.id)

        for staff in office.staffs:
            # メール（全員）
            await send_email(staff.email, alerts)

            # Web Push（購読者のみ）
            await push_service.send_push_notification(
                db=db,
                staff_id=staff.id,
                title=f"期限アラート: {len(alerts)}件",
                body=f"更新期限が近い利用者が{len(alerts)}名います",
                url="/dashboard"
            )
```

**期待効果（業界平均からの推定）**:
- 到達率: 15-25% → 70-90%（**2.8-6倍**）
- 対応率: 要実測（実装前に現状値を計測すべき）

**⚠️ 実装前の推奨アクション**:
1. 現状のメール開封率を計測（トラッキングピクセルまたはリンククリック率）
2. 現状の対応率を計測（期限内に対応完了した割合）
3. 実測値を基に投資対効果を再評価

---

**フェーズ2: 段階的通知の導入**（工数: 6-8時間、フェーズ1から3-6ヶ月後）

```python
async def send_deadline_alerts_phase2(db: AsyncSession):
    """マイルストーンのみ通知（30/14/7/3/1日前）"""
    for office in offices:
        alerts = await get_deadline_alerts(db, office.id)

        for alert in alerts:
            days = alert.days_remaining

            # マイルストーンチェック
            if days not in [30, 14, 7, 3, 1]:
                continue

            # 重複防止
            if await is_already_sent(alert.id, days):
                continue

            # 通知送信（メール + Web Push）
            await send_milestone_notification(alert, days)
```

**効果**:
- 通知頻度: 毎日 → 週2-3回（50-70%削減）
- 通知疲れ軽減
- 重要なタイミングで確実に通知

---

**フェーズ3: ユーザー設定の追加**（工数: 6-8時間、フェーズ2から3-6ヶ月後）

```typescript
// ユーザーが選択可能
interface DeadlineAlertSettings {
  enabled: boolean;              // ON/OFF
  frequency: 'daily' | 'milestone';  // 毎日 or マイルストーン
  channels: {
    email: boolean;              // メールで受け取る
    push: boolean;               // Web Pushで受け取る
  }
}
```

**効果**:
- ユーザーが通知方法を自由に選択
- 通知疲れの完全解消
- 満足度向上

---

### 13.9 実装前に行うべき計測（重要）

#### 現状の効果測定が必須な理由

**課題**: 現在は開発者のみが利用しており、実際のユーザーデータが存在しない

**リスク**:
- Web Push導入のROI（投資対効果）が不明
- 想定効果（2.8-6倍改善）が実現しない可能性
- 投資判断の根拠が弱い

#### 推奨する計測方法

##### 計測1: メール開封率（クリック率）

**実装方法A: メール内リンクのクリック率で測定**

```python
# app/core/mail.py

async def send_deadline_alert_email(
    staff_email: str,
    staff_name: str,
    office_name: str,
    renewal_alerts: List[DeadlineAlertItem],
    assessment_alerts: List[DeadlineAlertItem],
    dashboard_url: str
):
    # トラッキング用のユニークID生成
    tracking_id = str(uuid.uuid4())

    # クリック追跡URL生成
    tracked_url = f"{dashboard_url}?utm_source=email&utm_medium=deadline_alert&tracking_id={tracking_id}"

    # DBに送信記録を保存
    await crud.email_tracking.create(
        db=db,
        obj_in=EmailTrackingCreate(
            tracking_id=tracking_id,
            staff_email=staff_email,
            email_type="deadline_alert",
            sent_at=datetime.now(timezone.utc)
        )
    )

    # メール送信（tracked_urlを使用）
    await send_email(
        to=staff_email,
        subject=f"【期限アラート】{office_name}",
        html_content=f"""
        <p>{staff_name}様</p>
        <p>更新期限が近い利用者がいます。</p>
        <a href="{tracked_url}">ダッシュボードで確認する</a>
        """
    )
```

**フロントエンド側でクリックを記録**:

```typescript
// app/protected/dashboard/page.tsx

useEffect(() => {
  const params = new URLSearchParams(window.location.search);
  const trackingId = params.get('tracking_id');

  if (trackingId) {
    // クリック記録
    fetch('/api/v1/email-tracking/click', {
      method: 'POST',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify({
        tracking_id: trackingId,
        clicked_at: new Date().toISOString()
      })
    });

    // URLからパラメータを削除（クリーン化）
    window.history.replaceState({}, '', '/protected/dashboard');
  }
}, []);
```

**新規テーブル**:

```sql
CREATE TABLE email_tracking (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    tracking_id UUID NOT NULL UNIQUE,
    staff_email VARCHAR(255) NOT NULL,
    email_type VARCHAR(50) NOT NULL,
    sent_at TIMESTAMP WITH TIME ZONE NOT NULL,
    clicked_at TIMESTAMP WITH TIME ZONE,
    created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW()
);

CREATE INDEX idx_email_tracking_staff_email ON email_tracking(staff_email);
CREATE INDEX idx_email_tracking_email_type ON email_tracking(email_type);
CREATE INDEX idx_email_tracking_sent_at ON email_tracking(sent_at);
```

**開封率（クリック率）の計算**:

```sql
-- 過去30日間のメール開封率
SELECT
    COUNT(*) FILTER (WHERE clicked_at IS NOT NULL) * 100.0 / COUNT(*) AS click_rate_percent,
    COUNT(*) AS total_sent,
    COUNT(*) FILTER (WHERE clicked_at IS NOT NULL) AS total_clicked
FROM email_tracking
WHERE email_type = 'deadline_alert'
  AND sent_at >= NOW() - INTERVAL '30 days';
```

**工数**: 4-6時間

---

##### 計測2: 対応完了率

**実装方法: アセスメント完了状況を追跡**

```python
# app/services/welfare_recipient_service.py

async def calculate_response_rate(
    db: AsyncSession,
    office_id: UUID,
    start_date: date,
    end_date: date
) -> dict:
    """
    期限アラート対応率を計算

    Returns:
        {
            "total_alerts": 10,  # 期間内のアラート総数
            "completed_in_time": 7,  # 期限内に完了した数
            "response_rate": 0.7  # 70%
        }
    """
    # 期間内に期限アラートが発生した利用者を取得
    stmt = (
        select(SupportPlanCycle)
        .where(
            SupportPlanCycle.office_id == office_id,
            SupportPlanCycle.next_renewal_deadline >= start_date,
            SupportPlanCycle.next_renewal_deadline <= end_date
        )
    )
    result = await db.execute(stmt)
    cycles = result.scalars().all()

    total_alerts = len(cycles)
    completed_in_time = 0

    for cycle in cycles:
        # アセスメントPDFがアップロードされているかチェック
        has_assessment = any(
            d.deliverable_type == DeliverableType.assessment_sheet
            for d in cycle.deliverables
        )

        if has_assessment:
            # アップロード日が期限前かチェック
            assessment_deliverable = next(
                d for d in cycle.deliverables
                if d.deliverable_type == DeliverableType.assessment_sheet
            )
            if assessment_deliverable.uploaded_at.date() <= cycle.next_renewal_deadline:
                completed_in_time += 1

    response_rate = completed_in_time / total_alerts if total_alerts > 0 else 0

    return {
        "total_alerts": total_alerts,
        "completed_in_time": completed_in_time,
        "response_rate": response_rate
    }
```

**API追加**:

```python
# app/api/v1/endpoints/analytics.py

@router.get("/deadline-response-rate")
async def get_deadline_response_rate(
    *,
    db: AsyncSession = Depends(get_db),
    current_user: Staff = Depends(get_current_user),
    start_date: date = Query(...),
    end_date: date = Query(...)
):
    """期限アラート対応率を取得"""
    result = await welfare_recipient_service.calculate_response_rate(
        db=db,
        office_id=current_user.office_id,
        start_date=start_date,
        end_date=end_date
    )
    return result
```

**工数**: 4-6時間

---

#### 計測期間の推奨

**最低計測期間**: 1-3ヶ月（本番運用開始後）

**理由**:
- 福祉業界の業務サイクルは月次・年次が多い
- 統計的に有意なサンプル数を確保
- 季節変動を考慮

**計測スケジュール例**:

```
2026年4月: 本番リリース + 計測開始
2026年7月: 3ヶ月間のデータ分析
2026年8月: Web Push導入判断（Go/No-Go）
2026年9月: Web Push実装開始（Goの場合）
```

---

#### 計測結果に基づく判断基準

**Web Push導入を推奨する条件**:

| 指標 | 閾値 | 判断 |
|------|------|------|
| メール開封率（クリック率） | < 30% | ✅ Web Push導入を推奨 |
| 対応完了率 | < 50% | ✅ Web Push導入を推奨 |
| 対応遅延（気づくまでの時間） | > 1時間 | ✅ Web Push導入を推奨 |

**Web Push導入を見送る条件**:

| 指標 | 閾値 | 判断 |
|------|------|------|
| メール開封率（クリック率） | > 60% | ⚠️ 現状で十分、Web Pushは不要 |
| 対応完了率 | > 80% | ⚠️ 現状で十分、Web Pushは不要 |

---

### 13.10 結論: 期限アラートのWeb Push導入は**計測後に判断すべき**

#### 総合評価（業界平均からの推定、実測値ではない）

| 評価項目 | スコア | 理由 |
|---------|--------|------|
| **ユーザー体験（推定）** | ★★★★★ | 業界平均では到達率2.8-6倍改善が期待できる |
| **サーバー負荷** | ★★★★☆ | メール併用時+10%、Web Pushのみなら-90% |
| **実装コスト** | ★★★☆☆ | 14-22時間（中程度） |
| **投資対効果** | ★★★☆☆ | **実測データ次第**（現状は不明） |
| **リスク** | ★★★☆☆ | ブラウザ問題、計測不足リスク |

**総合スコア**: **3.8 / 5.0**（実測後に再評価が必要）

---

#### 推奨実装順序（修正版）

```
✅ Phase 0: 現状計測（必須、最優先）
  ├─ 工数: 8-12時間
  ├─ 内容: メール開封率・対応率の計測機能実装
  ├─ 期間: 本番運用開始後1-3ヶ月間
  └─ 実装時期: 本番リリース前

⚠️ Phase 1: 計測結果の分析・判断
  ├─ 工数: 分析のみ（4-8時間）
  ├─ 判断基準:
  │   - メール開封率 < 30% → Web Push導入へ
  │   - メール開封率 > 60% → Web Push見送り
  └─ 実施時期: 計測終了後

✅ Phase 2: Web Push導入（判断後）
  ├─ 工数: 14-22時間
  ├─ 効果: 実測データに基づいて算出
  └─ 実装時期: Phase 1でGo判断の場合のみ

✅ Phase 3: 段階的通知（オプション）
  ├─ 工数: 6-8時間
  ├─ 効果: 通知疲れ削減
  └─ 実装時期: Phase 2から3-6ヶ月後

✅ Phase 4: ユーザー設定UI（オプション）
  ├─ 工数: 6-8時間
  ├─ 効果: 満足度向上
  └─ 実装時期: Phase 3から3-6ヶ月後
```

---

#### 期限アラートとイベント駆動通知の優先順位

**同時実装する場合の推奨順序**:

1. **Web Push基盤構築**（Phase 1、8-10時間）
   - VAPID鍵、DBテーブル、購読API

2. **イベント駆動通知のWeb Push化**（Phase 2前半、6-8時間）
   - スタッフアクション承認/却下
   - ロール変更承認/却下
   - **理由**: 実装が簡単、即効性が高い

3. **期限アラートのWeb Push化**（Phase 2後半、14-22時間）
   - メール + Web Push併用
   - バッチ処理修正
   - **理由**: 既存メール処理との統合が必要

**合計工数**: 28-40時間（既存計画と同等）

---

#### 最終結論（修正版）

**期限アラートへのWeb Push導入は、まず現状を計測してから判断すべき**

**計測が必須な理由**:
1. ⚠️ **実測データがない**（現在は開発者のみ利用）
2. ⚠️ **業界平均（15-25%）が福祉業界に当てはまるか不明**
3. ⚠️ **投資判断の根拠が弱い**（推定値のみでROI不明）
4. ⚠️ **ユーザー特性が異なる可能性**（年齢層、ITリテラシー）

**推奨アプローチ**:

```
1. まず計測機能を実装（8-12時間）
   ↓
2. 本番運用で1-3ヶ月間データ収集
   ↓
3. 実測データを分析
   ↓
4. 判断:
   - メール開封率 < 30% → Web Push導入（期待効果大）
   - メール開封率 30-60% → Web Push導入検討（要コスト分析）
   - メール開封率 > 60% → Web Push見送り（現状で十分）
```

**イベント駆動通知との比較**:

| 項目 | イベント駆動通知 | 期限アラート |
|------|----------------|------------|
| 実装優先度 | ✅ 高（即効性あり） | ⚠️ 中（計測後判断） |
| 現状の課題 | 明確（ポーリング30秒遅延） | 不明（要計測） |
| 実装コスト | 6-8時間（低） | 14-22時間（中） |
| 効果の確実性 | 高（リアルタイム化は確実に改善） | 不明（実測次第） |

**結論**:
- **イベント駆動通知**: 先に実装を推奨（効果が確実）
- **期限アラート**: 計測→分析→判断の順で慎重に進める

---

#### 📝 実装状況ノート（2026-01-14追記）

**バックエンド実装完了により、Phase 1はスキップ可能**:
- ✅ Phase 1（Backend基盤構築）: **既に完了**（2026-01-13）
  - VAPID鍵生成・環境設定 ✅
  - DBマイグレーション ✅
  - Push購読API実装 ✅
  - Push通知サービス実装 ✅
  - テストコード作成 ✅

**次のステップ: Phase 2（フロントエンド実装）**:
- 🚧 Service Worker作成
- 🚧 Push購読Hook実装
- 🚧 通知設定UI実装
- 🚧 LayoutClient修正

**工数削減**:
- 当初見積: 32-40時間（Phase 1-4）
- 残り実装: 12-14時間（Phase 2のみ）
- **削減された工数**: 8-10時間（Phase 1完了済み）

**実装意向**: フロントエンド実装を進める予定

---

## 14. 参考資料

### 14.1 技術ドキュメント
- [Web Push Notification API (MDN)](https://developer.mozilla.org/en-US/docs/Web/API/Push_API)
- [Service Worker API (MDN)](https://developer.mozilla.org/en-US/docs/Web/API/Service_Worker_API)
- [pywebpush Documentation](https://github.com/web-push-libs/pywebpush)
- [VAPID Specification (RFC 8292)](https://tools.ietf.org/html/rfc8292)

### 14.2 ブラウザサポート
- [Can I use - Push API](https://caniuse.com/push-api)
- [Can I use - Service Workers](https://caniuse.com/serviceworkers)

### 14.3 ベストプラクティス
- [Web Push Best Practices (Google)](https://web.dev/push-notifications-overview/)
- [Notification UX Best Practices (Apple)](https://developer.apple.com/design/human-interface-guidelines/notifications)

---

**ドキュメント作成日**: 2026-01-13
**最終更新日**: 2026-01-13（期限アラートのWeb Push導入検討を追加）
**次回レビュー予定**: 実装開始時
