# セキュリティ

## 認証・認可

### DAL (Data Access Layer) パターン
- **ファイル**: `lib/dal.ts`
- CVE-2025-29927 対策として DAL パターンを導入
- `verifySession()`: サーバー側で認証検証（React の `cache()` でリクエスト内重複排除）
- `requireAuth()`, `requireRole()`, `requireOffice()` でサーバー側の権限チェック

### Middleware での軽量チェック
- **ファイル**: `middleware.ts`
- Cookie 存在の軽量チェック: `request.cookies.get('access_token')`
- 保護ルート（ダッシュボード・受給者・サポートプラン等）を判定してリダイレクト
- 静的ファイル（画像・フォント等）は除外
- 本格的な認証検証は DAL に委譲

### Protected Layout でのサーバー検証
- **ファイル**: `app/(protected)/layout.tsx`
- サーバーコンポーネントで `verifySession()` を呼び出し
- 未認証時: `redirect('/auth/login')` で即時リダイレクト
- app_admin ロールは専用レイアウトへ分岐

## Cookie・トークン管理

| トークン | 保存先 | 用途 |
|---------|--------|------|
| `access_token` | HTTPOnly Cookie | 通常の認証（自動送信） |
| `temporary_token` | localStorage | MFA認証中の短期トークン |

- **ファイル**: `lib/token.ts`
- MFA フロー: ログイン成功 → `temporary_token` を localStorage 保存 → MFA確認後に正式な Cookie 発行

## CSRF 対策
- **ファイル**: `lib/csrf.ts`, `lib/http.ts`
- ログイン後に `csrfApi.getCsrfToken()` でトークン取得
- メモリ上にトークンを保存 (`setCsrfToken`)
- 状態変更リクエスト（POST / PUT / PATCH / DELETE）に `X-CSRF-Token` ヘッダーを自動付与

## XSS 対策
- React の JSX 自動エスケープ機構
- Zod スキーマによる入力バリデーション
- パスワード複雑性チェック: 小大文字・数字・記号すべて必須（`lib/password-validation.ts`）

## HTTP 層でのセキュリティ
- **ファイル**: `lib/http.ts`
- 全リクエストに `credentials: 'include'` を指定（Cookie 自動送信）
- 401 レスポンス時: `handleLogout()` → ログインページへリダイレクト
- FastAPI バリデーションエラーを日本語化して表示

---

# パフォーマンス

## キャッシング戦略

### React `cache()` による重複排除
- **ファイル**: `lib/dal.ts` (line 41)
- 同一リクエスト内で `verifySession()` が複数回呼ばれても API 呼び出しは 1 回のみ

```typescript
export const verifySession = cache(async (): Promise<Session | null> => {
  // 同一リクエスト内でキャッシュされる
```

## ポーリング

| 対象 | 間隔 | ファイル |
|------|------|---------|
| 未読通知件数 | 30秒 | `components/protected/LayoutClient.tsx` |
| 課金ステータス | 10分 | `contexts/BillingContext.tsx` |

- `useEffect` の cleanup で `clearInterval()` を確実に実行してメモリリーク防止

## コード分割・遅延ロード
- **ファイル**: `components/auth/MfaFirstSetupForm.tsx`, `app/page.tsx`
- `<Suspense>` による遅延ロード
- Next.js の自動コード分割機構を活用
- Turbopack 有効化（`package.json`: `"dev": "next dev --turbopack"`）でビルド高速化

## 画像最適化
- **ファイル**: `app/page.tsx`
- Next.js の `<Image>` コンポーネント使用
- `priority` 属性で LCP 対象画像を優先ロード
- `width` / `height` 指定による CLS 防止

## メモ化 (useCallback)
- **ファイル**: `components/ui/DateDrumPicker.tsx`, `components/admin/inquiry/InquiryList.tsx`
- `getDaysInMonth`, `notifyChange`, `fetchInquiries` 等で `useCallback` を使用
- 再レンダリング時の不要な関数再生成を防止

## Push 通知の最適化
- **ファイル**: `hooks/usePushNotification.ts`
- iOS 検出（`detectIOS()`）: PWA 非対応の iOS Safari では購読処理をスキップ
- Service Worker のアクティブ化を待機してから購読登録

---

# ライフサイクルなどの設計

## アーキテクチャ層の構成

```
Page層 (app/(protected)/*/page.tsx)
  ↓
Layout層 (app/(protected)/layout.tsx)
  ├─ サーバー側: verifySession() で認証検証
  └─ ProtectedLayoutClient (クライアントコンポーネント)
      ├─ ヘッダー・サイドメニュー
      └─ 通知管理 (usePushNotification)

Component層 (components/*)
  ├─ UI Components (ui/*)
  ├─ Protected Components (protected/*)
  └─ Auth Components (auth/*)

Context層
  ├─ BillingContext（課金ステータス管理）
  └─ Toaster Provider（トースト通知）

Hook層
  ├─ useStaffRole（ユーザー権限取得）
  ├─ usePushNotification（Web Push 管理）
  └─ useCallback（パフォーマンス最適化）

API層 (lib/api/*)
  └─ http クライアント（CSRF・エラーハンドリング）

DAL層 (lib/dal.ts)
  └─ verifySession()（認証キャッシング）
```

## サーバー/クライアント コンポーネント分離
- **App Router** を使用
- `layout.tsx` はサーバーコンポーネント → 認証検証を担当
- `LayoutClient.tsx` はクライアントコンポーネント → 動的 UI を担当
- ページコンポーネントはデータ取得に応じてサーバー/クライアントを使い分け

## useEffect ライフサイクル

### マウント時の初期化（`LayoutClient.tsx`）
```typescript
useEffect(() => {
  setIsMounted(true);
  initializeCsrfToken();         // CSRF トークン初期化
  officeApi.getMyOffice().then(setOffice);  // 事業所情報取得
  fetchUnreadCount();            // 未読件数初回取得
  initializeNotifications();     // Push 通知初期化

  const interval = setInterval(() => fetchUnreadCount(), 30000);
  return () => clearInterval(interval);  // cleanup
}, []);
```

### ホバーイベント時のデータ取得
```typescript
const handleNoticeHover = () => {
  if (unreadCount > 0) fetchRecentUnreadNotices();
  if (!deadlineAlertsLoaded) fetchDeadlineAlerts(0);
};
```

## カスタムフック

### `useStaffRole` (`hooks/useStaffRole.ts`)
- 現在のスタッフ情報を取得し、ロールを判定
- 戻り値: `isEmployee`, `isManager`, `isOwner`, `canApproveRequests`

### `usePushNotification` (`hooks/usePushNotification.ts`)
- Web Push API の購読・解除を管理
- VAPID 鍵を使用した購読登録
- ブラウザ側とサーバー側を同期して解除

## Context API

### `BillingContext` (`contexts/BillingContext.tsx`)
```typescript
interface BillingContextType {
  billingStatus: BillingStatusResponse | null;
  canWrite: boolean;   // past_due / canceled 時は false
  isPastDue: boolean;
  refreshBillingStatus: () => Promise<void>;
}
```
- 書き込み操作の制限 (`canWrite`) を全コンポーネントで共有
- `past_due` 時に支払い遅延モーダルを表示

## フォームハンドリング
- `useState` でフォームデータを管理（Zod スキーマでバリデーション）
- `e.preventDefault()` で標準サブミット防止
- 非同期送信中は `isLoading` フラグでボタンを無効化
- エラーは `catch` でキャッチし、日本語メッセージを表示

## エラーハンドリング戦略

| エラー種別 | 対応 |
|-----------|------|
| 401 認証エラー | `handleLogout()` → `/auth/login` リダイレクト |
| バリデーションエラー | FastAPI の詳細を日本語化して表示 |
| ネットワークエラー | `try/catch` で捕捉、トーストで通知 |

## 状態管理方針
- グローバル状態: Context API（課金・認証情報）
- サーバー状態: API 呼び出し + `useState` でローカル管理（React Query 不使用）
- フォーム状態: `useState` でコンポーネントローカルに管理
- 永続化: Cookie（認証）/ localStorage（MFA 一時トークン）
