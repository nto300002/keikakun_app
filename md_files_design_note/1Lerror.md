[Service Worker] Install event

[Service Worker] Activate event

エラー（赤）

[usePushNotification] Subscribe error: Error: Not authenticated (usePushNotification.ts:158) at usePushNotification.useCallback[subscribe] (usePushNotification.ts:138:15) at async handleToggle (_13a87ccd...js:883:21)

Failed to subscribe: Error: Not authenticated (VM3929_13a87ccd...js:886)

[Fast Refresh] rebuilding (forward-logs-shared.ts:95)](https://microsoft.com)))



Console Error


Not authenticated
hooks/usePushNotification.ts (138:15) @ usePushNotification.useCallback[subscribe]


  136 |
  137 |       if (!token) {
> 138 |         throw new Error('Not authenticated');
      |               ^
  139 |       }
  140 |
  141 |       const response = await fetch(`${process.env.NEXT_PUBLIC_API_URL}/api/v1/push-subscriptions/subscribe`, {

---

## 2026-01-14 調査結果

### 原因
このプロジェクトは **Cookie認証** を採用しているが、実装したWeb Push機能は **localStorage認証** を前提としていた。

**問題のコード**: `localStorage.getItem('token')`
- トークンはlocalStorageではなくHTTPOnly Cookieに保存されている
- `localStorage.getItem('token')`は常にnullを返す

### 修正方法
既存の`k_front/lib/http.ts`を使用する：
- Cookie認証（`credentials: 'include'`）自動設定
- CSRFトークン自動付与
- エラーハンドリング

**詳細**: `@md_files_design_note/task/*web_push/fix/fix.md` を参照

### 影響範囲
1. `k_front/hooks/usePushNotification.ts` - subscribe/unsubscribe関数
2. `k_front/components/protected/profile/NotificationSettings.tsx` - fetchPreferences/savePreferences関数

---

## 2026-01-14 修正完了

### 修正内容
両ファイルでlocalStorage認証を削除し、`http.ts`の共通HTTPライブラリを使用する形に修正。

**修正前**:
```typescript
const token = localStorage.getItem('token');
if (!token) throw new Error('Not authenticated');
await fetch(url, { headers: { 'Authorization': `Bearer ${token}` }});
```

**修正後**:
```typescript
import { http } from '@/lib/http';
await http.post('/api/v1/push-subscriptions/subscribe', data);
```

### 修正による改善
1. ✅ Cookie認証に対応（`credentials: 'include'`自動設定）
2. ✅ CSRFトークン自動付与
3. ✅ 401時の自動ログアウト処理
4. ✅ コードの簡潔化

**詳細**: `@md_files_design_note/task/*web_push/fix/fix.md` 参照

**ステータス**: ✅ 修正完了