# Web Push通知 不具合修正記録

## 2026-01-14: システム通知ON時の認証エラー

### 症状
プロフィールページ → 通知設定タブ → システム通知（Web Push）をONにしようとすると、以下のエラーが発生：

```
エラー: Not authenticated
```

**エラー発生箇所**: `hooks/usePushNotification.ts:138`

```typescript
const token = localStorage.getItem('token');
if (!token) {
  throw new Error('Not authenticated');  // ← ここでエラー
}
```

**コンソールログ**:
```
[usePushNotification] Subscribe error: Error: Not authenticated
Failed to subscribe: Error: Not authenticated
```

---

### 原因調査

#### 1. 認証システムの仕様確認

このプロジェクトは **Cookie認証** を採用しており、HTTPOnly Cookieで認証トークンを管理している。

**証拠**: `k_front/lib/http.ts`
```typescript
const config: RequestInit = {
  ...options,
  credentials: 'include', // Cookie送信のため必須
  headers: {
    ...defaultHeaders,
    ...options.headers,
  },
};
```

**証拠**: `k_front/lib/token.ts`
```typescript
/**
 * Token management - Cookie-based authentication
 *
 * Note: access_tokenはCookieで管理されるため、
 * setToken/getToken/removeTokenは空の実装（互換性のため残す）
 *
 * temporary_tokenは短期間の一時トークンのため、localStorageを使用
 */
```

#### 2. 問題のある実装箇所

**ファイル1**: `k_front/hooks/usePushNotification.ts`

❌ **誤った実装**:
```typescript
// Line 135-139
const token = localStorage.getItem('token');

if (!token) {
  throw new Error('Not authenticated');
}

// Line 141-149
const response = await fetch(`${process.env.NEXT_PUBLIC_API_URL}/api/v1/push-subscriptions/subscribe`, {
  method: 'POST',
  headers: {
    'Content-Type': 'application/json',
    'Authorization': `Bearer ${token}`  // ← 不要（Cookieで自動送信される）
  },
  body: JSON.stringify(subscription.toJSON())
});
```

**問題点**:
1. `localStorage.getItem('token')` - トークンはlocalStorageではなくCookieに保存されている
2. `Authorization: Bearer ${token}` - Cookie認証なので不要
3. `credentials: 'include'` がない - Cookieを送信するために必須
4. CSRFトークンがない - POST/PUT/DELETEリクエストには必要

**ファイル2**: `k_front/components/protected/profile/NotificationSettings.tsx`

❌ **誤った実装** (Line 59-69):
```typescript
const token = localStorage.getItem('token');
if (!token) {
  toast.error('認証エラー: ログインしてください');
  return;
}

const response = await fetch(
  `${process.env.NEXT_PUBLIC_API_URL}/api/v1/staffs/me/notification-preferences`,
  {
    method: 'PUT',
    headers: {
      'Content-Type': 'application/json',
      'Authorization': `Bearer ${token}`  // ← 不要
    },
    body: JSON.stringify(newPreferences)
  }
);
```

同じ問題点：
1. `localStorage.getItem('token')` で取得できない
2. `Authorization`ヘッダー不要
3. `credentials: 'include'` がない
4. CSRFトークンがない

**ファイル3**: `k_front/hooks/usePushNotification.ts` (unsubscribe関数)

❌ **誤った実装** (Line 189-196):
```typescript
const token = localStorage.getItem('token');

if (token) {
  await fetch(
    `${process.env.NEXT_PUBLIC_API_URL}/api/v1/push-subscriptions/unsubscribe?endpoint=${encodeURIComponent(endpoint)}`,
    {
      method: 'DELETE',
      headers: {
        'Authorization': `Bearer ${token}`  // ← 不要
      }
    }
  );
}
```

---

### 修正方法

#### 修正案1: `http.ts` の共通関数を使用する（推奨）

既存のプロジェクトには`k_front/lib/http.ts`という共通HTTPライブラリがあり、以下の機能を持つ：
- Cookie認証（`credentials: 'include'`）自動設定
- CSRFトークン自動付与
- エラーハンドリング（401 Unauthorized時のログアウト処理）

✅ **正しい実装例**:

```typescript
import { http } from '@/lib/http';

// subscribe関数内
const response = await http.post<any>(
  '/api/v1/push-subscriptions/subscribe',
  subscription.toJSON()
);

// unsubscribe関数内
await http.delete(
  `/api/v1/push-subscriptions/unsubscribe?endpoint=${encodeURIComponent(endpoint)}`
);

// NotificationSettings.tsx内 - GET
const data = await http.get<NotificationPreferences>(
  '/api/v1/staffs/me/notification-preferences'
);

// NotificationSettings.tsx内 - PUT
const data = await http.put<NotificationPreferences>(
  '/api/v1/staffs/me/notification-preferences',
  newPreferences
);
```

#### 修正案2: fetch APIを直接使用する場合

✅ **正しい実装例**:

```typescript
import { getCsrfToken } from '@/lib/http';

const headers: HeadersInit = {
  'Content-Type': 'application/json'
};

// POSTリクエストの場合はCSRFトークンを追加
const csrfToken = getCsrfToken();
if (csrfToken) {
  headers['X-CSRF-Token'] = csrfToken;
}

const response = await fetch(
  `${process.env.NEXT_PUBLIC_API_URL}/api/v1/push-subscriptions/subscribe`,
  {
    method: 'POST',
    credentials: 'include',  // ← Cookie送信のため必須
    headers,
    body: JSON.stringify(subscription.toJSON())
  }
);
```

---

### 修正対象ファイル

1. ✅ `k_front/hooks/usePushNotification.ts`
   - `subscribe()` 関数: Line 135-149
   - `unsubscribe()` 関数: Line 189-196

2. ✅ `k_front/components/protected/profile/NotificationSettings.tsx`
   - `fetchPreferences()` 関数: Line 37-50
   - `savePreferences()` 関数: Line 52-88

---

### 修正優先度

**Critical（緊急）**: システム通知機能が全く動作しない

---

### 関連資料

- `k_front/lib/http.ts` - Cookie認証の共通HTTPライブラリ
- `k_front/lib/token.ts` - トークン管理（Cookie認証の説明あり）
- バックエンドAPI:
  - `k_back/app/api/v1/endpoints/push_subscriptions.py`
  - `k_back/app/core/config.py` (VAPID設定)

---

### 次のステップ

1. `usePushNotification.ts` を修正（http.post/http.deleteを使用）
2. `NotificationSettings.tsx` を修正（http.get/http.putを使用）
3. 動作確認（通知設定タブでシステム通知をON）
4. ブラウザDevToolsでCookieが送信されていることを確認

---

## 修正内容（2026-01-14実施）

### 修正ファイル1: `k_front/hooks/usePushNotification.ts`

**変更箇所1 - インポート追加**:
```typescript
import { http } from '@/lib/http';
```

**変更箇所2 - subscribe関数**:
```typescript
// 修正前（❌）
const token = localStorage.getItem('token');
if (!token) {
  throw new Error('Not authenticated');
}
const response = await fetch(`${process.env.NEXT_PUBLIC_API_URL}/api/v1/push-subscriptions/subscribe`, {
  method: 'POST',
  headers: {
    'Content-Type': 'application/json',
    'Authorization': `Bearer ${token}`
  },
  body: JSON.stringify(subscription.toJSON())
});

// 修正後（✅）
await http.post<any>(
  '/api/v1/push-subscriptions/subscribe',
  subscription.toJSON()
);
```

**変更箇所3 - unsubscribe関数**:
```typescript
// 修正前（❌）
const token = localStorage.getItem('token');
if (token) {
  await fetch(
    `${process.env.NEXT_PUBLIC_API_URL}/api/v1/push-subscriptions/unsubscribe?endpoint=${encodeURIComponent(endpoint)}`,
    {
      method: 'DELETE',
      headers: {
        'Authorization': `Bearer ${token}`
      }
    }
  );
}

// 修正後（✅）
await http.delete(
  `/api/v1/push-subscriptions/unsubscribe?endpoint=${encodeURIComponent(endpoint)}`
);
```

---

### 修正ファイル2: `k_front/components/protected/profile/NotificationSettings.tsx`

**変更箇所1 - インポート追加**:
```typescript
import { http } from '@/lib/http';
```

**変更箇所2 - fetchPreferences関数**:
```typescript
// 修正前（❌）
const token = localStorage.getItem('token');
if (!token) return;

const response = await fetch(
  `${process.env.NEXT_PUBLIC_API_URL}/api/v1/staffs/me/notification-preferences`,
  {
    headers: {
      'Authorization': `Bearer ${token}`
    }
  }
);

if (response.ok) {
  const data = await response.json();
  setPreferences(data);
}

// 修正後（✅）
const data = await http.get<NotificationPreferences>(
  '/api/v1/staffs/me/notification-preferences'
);
setPreferences(data);
```

**変更箇所3 - savePreferences関数**:
```typescript
// 修正前（❌）
const token = localStorage.getItem('token');
if (!token) {
  toast.error('認証エラー: ログインしてください');
  return;
}

const response = await fetch(
  `${process.env.NEXT_PUBLIC_API_URL}/api/v1/staffs/me/notification-preferences`,
  {
    method: 'PUT',
    headers: {
      'Content-Type': 'application/json',
      'Authorization': `Bearer ${token}`
    },
    body: JSON.stringify(newPreferences)
  }
);

// 修正後（✅）
const data = await http.put<NotificationPreferences>(
  '/api/v1/staffs/me/notification-preferences',
  newPreferences
);
setPreferences(data);
```

---

### 修正による改善点

1. ✅ **Cookie認証に対応** - `credentials: 'include'`が自動設定される
2. ✅ **CSRFトークン自動付与** - POST/PUT/DELETEリクエストに自動追加
3. ✅ **エラーハンドリング統一** - 401時の自動ログアウト処理
4. ✅ **コードの簡潔化** - localStorage認証チェックが不要

---

**作成日**: 2026-01-14
**修正日**: 2026-01-14
**ステータス**: ✅ 修正完了
