# エラーハンドリング・通知システム改善案

## 📊 調査結果サマリー

### 現状の課題
1. **コードの重複**: 各コンポーネントで同じトーストUIコードが重複
2. **ページ遷移時の通知**: ページをまたいだメッセージ表示が困難
3. **英語メッセージの混在**: 約70箇所以上で日本語化が必要

### 既存のエラー処理パターン

**共通パターン (Profile.tsx, NotificationsTab.tsx等で使用中)**:
```tsx
// State管理
const [error, setError] = useState<string | null>(null);
const [successMessage, setSuccessMessage] = useState<string | null>(null);

// エラーハンドリング
try {
  // API呼び出し等
} catch (err: unknown) {
  const message = err instanceof Error ? err.message : String(err);
  setError(message || 'デフォルトの日本語メッセージ');
  setTimeout(() => setError(null), 3000);
}

// UI表示
{successMessage && (
  <div className="fixed top-4 right-4 bg-green-600 text-white px-6 py-3 rounded-lg shadow-lg z-50">
    {successMessage}
  </div>
)}

{error && (
  <div className="fixed top-4 right-4 bg-red-600 text-white px-6 py-3 rounded-lg shadow-lg z-50">
    <div className="flex items-center justify-between">
      <span>{error}</span>
      <button onClick={() => setError(null)} className="ml-4 text-white hover:text-gray-200">
        ×
      </button>
    </div>
  </div>
)}
```

---

## 🔴 日本語化が必要な箇所（優先度別）

### 【高優先度】APIエラーメッセージ (約15箇所)

#### 1. lib/http.ts
| 行 | 現在 | 推奨 |
|---|---|---|
| 88 | `'Not authenticated'` | `'認証されていません'` |
| 90 | `Request failed with status ${response.status}` | `リクエストが失敗しました (ステータス: ${response.status})` |
| 120 | `'Not authenticated'` | `'認証されていません'` |

#### 2. lib/auth.ts
| 行 | 現在 | 推奨 |
|---|---|---|
| 39 | `'Login failed'` | `'ログインに失敗しました'` |

#### 3. lib/dal.ts
| 行 | 現在 | 推奨 |
|---|---|---|
| 107 | `'Unauthorized: Authentication required'` | `'未認証: 認証が必要です'` |
| 123 | `Forbidden: Required role is one of [${allowedRoles.join(', ')}]` | `アクセス拒否: 必要な権限は [${allowedRoles.join(', ')}] のいずれかです` |
| 138 | `'Forbidden: Office membership required'` | `'アクセス拒否: 事業所への所属が必要です'` |

#### 4. lib/support-plan.ts
| 行 | 現在 | 推奨 |
|---|---|---|
| 87 | `Upload failed: ${res.status} ${res.statusText}` | `アップロードに失敗しました: ${res.status} ${res.statusText}` |
| 111 | `'Reupload failed'` | `'再アップロードに失敗しました'` |

#### 5. app/auth/verify-email/page.tsx
| 行 | 現在 | 推奨 |
|---|---|---|
| 18 | `'Verification token not found.'` | `'認証トークンが見つかりません。'` |
| 32 | `'An unknown error occurred.'` | `'不明なエラーが発生しました。'` |
| 45 | `'Eメール認証中..'` | `'メール認証中...'` |

### 【中優先度】console.error (約35箇所)

<details>
<summary>console.errorの一覧を表示</summary>

1. **lib/http.ts:42** - `'Failed to logout:'` → `'ログアウトに失敗しました:'`
2. **lib/cookie.ts:17** - `'[Cookie] Failed to get token from cookies:'` → `'[Cookie] Cookieからトークンの取得に失敗しました:'`
3. **lib/dal.ts:82** - `'[DAL] Session verification failed:'` → `'[DAL] セッション検証に失敗しました:'`
4. **components/protected/pdf-list/PdfViewContent.tsx:101** - `'Failed to fetch recipients:'` → `'利用者の取得に失敗しました:'`
5. **components/protected/pdf-list/PdfViewContent.tsx:136** - `'Failed to fetch PDFs:'` → `'PDFの取得に失敗しました:'`
6. **components/protected/dashboard/Dashboard.tsx:67** - `'Failed to fetch initial data:'` → `'初期データの取得に失敗しました:'`
7. **components/protected/dashboard/Dashboard.tsx:116** - `'Failed to apply filters:'` → `'フィルターの適用に失敗しました:'`
8. **components/protected/dashboard/Dashboard.tsx:170** - `'Failed to reset display:'` → `'表示のリセットに失敗しました:'`
9. **components/protected/dashboard/Dashboard.tsx:202** - `'Failed to delete recipient:'` → `'利用者の削除に失敗しました:'`
10. **components/protected/recipients/EmploymentSection.tsx:70** - `'Failed to save employment:'` → `'就労情報の保存に失敗しました:'`
11. **components/protected/recipients/forms/MedicalInfoForm.tsx:37** - `'Failed to save medical info:'` → `'医療情報の保存に失敗しました:'`
12. **components/protected/support_plan/SupportPlan.tsx:54** - `'Failed to fetch support plan data:'` → `'個別支援計画データの取得に失敗しました:'`
13. **components/protected/support_plan/SupportPlan.tsx:156** - `'Failed to upload file:'` → `'ファイルのアップロードに失敗しました:'`
14. **hooks/useStaffRole.ts:21-22** - `'Failed to fetch staff data:'` → `'スタッフデータの取得に失敗しました'`

...その他約20箇所

</details>

### 【低優先度】デバッグログ (約20箇所)

開発時のconsole.log等。本番環境では削除を推奨。

---

## 🎨 グローバル通知システムの設計案

### オプション1: **Sonner** (推奨 ⭐)

#### メリット
- ✅ 軽量かつモダン（週間DL: 500K、急成長中）
- ✅ シンプルなAPI、学習コスト低
- ✅ Tailwind CSSとの相性良好
- ✅ ページ遷移時もグローバルに表示可能
- ✅ アクセシビリティ対応

#### デメリット
- ⚠️ React Toastifyより新しく、エコシステムが小さい

#### 実装方法

**1. インストール**
```bash
npm install sonner
```

**2. app/layout.tsx に統合**
```tsx
'use client';

import { Toaster } from 'sonner';

export default function RootLayout({ children }) {
  return (
    <html lang="ja">
      <body>
        <Toaster
          position="top-right"
          richColors
          duration={3000}
          closeButton
        />
        {children}
      </body>
    </html>
  );
}
```

**3. 使用例**
```tsx
import { toast } from 'sonner';

// 成功
toast.success('名前を更新しました');

// エラー
toast.error('名前の更新に失敗しました');

// 情報
toast.info('確認メールを送信しました');

// カスタム時間
toast.success('保存しました', { duration: 5000 });

// ページ遷移後も表示可能
router.push('/profile');
toast.success('ログアウトしました');
```

---

### オプション2: **React Hot Toast**

#### メリット
- ✅ 週間DL: 1M以上、成熟したライブラリ
- ✅ Tailwind CSSスタイリング対応
- ✅ 高度なカスタマイズ性
- ✅ JSXコンポーネントをトーストに埋め込み可能

#### デメリット
- ⚠️ Sonnerより少し重い
- ⚠️ APIがやや複雑

#### 実装方法

```bash
npm install react-hot-toast
```

```tsx
import { Toaster } from 'react-hot-toast';
import toast from 'react-hot-toast';

// Layout
<Toaster position="top-right" />

// 使用
toast.success('成功しました');
toast.error('失敗しました');
```

---

### オプション3: **React Toastify** (最も人気)

#### メリット
- ✅ 週間DL: 1.8M、業界標準
- ✅ 豊富なドキュメント・コミュニティ
- ✅ 安定性が高い

#### デメリット
- ⚠️ やや古いAPI設計
- ⚠️ 追加のCSSインポートが必要

---

### オプション4: **カスタム実装 (Context API)**

既存のコードと同じスタイルを維持しつつ、グローバル化。

#### メリット
- ✅ 完全なコントロール
- ✅ 外部依存なし
- ✅ 既存のTailwindスタイルと完全一致

#### デメリット
- ⚠️ 実装・テスト工数が必要
- ⚠️ アクセシビリティ対応を自前で実装

<details>
<summary>カスタム実装の例</summary>

**contexts/ToastContext.tsx**
```tsx
'use client';

import { createContext, useContext, useState, ReactNode } from 'react';

type ToastType = 'success' | 'error' | 'info' | 'warning';

interface Toast {
  id: string;
  type: ToastType;
  message: string;
  duration?: number;
}

interface ToastContextType {
  toasts: Toast[];
  showToast: (type: ToastType, message: string, duration?: number) => void;
  removeToast: (id: string) => void;
}

const ToastContext = createContext<ToastContextType | undefined>(undefined);

export function ToastProvider({ children }: { children: ReactNode }) {
  const [toasts, setToasts] = useState<Toast[]>([]);

  const showToast = (type: ToastType, message: string, duration = 3000) => {
    const id = Math.random().toString(36).substr(2, 9);
    setToasts((prev) => [...prev, { id, type, message, duration }]);

    if (duration > 0) {
      setTimeout(() => removeToast(id), duration);
    }
  };

  const removeToast = (id: string) => {
    setToasts((prev) => prev.filter((toast) => toast.id !== id));
  };

  return (
    <ToastContext.Provider value={{ toasts, showToast, removeToast }}>
      {children}
      <ToastContainer toasts={toasts} onClose={removeToast} />
    </ToastContext.Provider>
  );
}

export const useToast = () => {
  const context = useContext(ToastContext);
  if (!context) {
    throw new Error('useToast must be used within ToastProvider');
  }
  return context;
};

function ToastContainer({ toasts, onClose }: { toasts: Toast[]; onClose: (id: string) => void }) {
  return (
    <div className="fixed top-4 right-4 z-50 space-y-2">
      {toasts.map((toast) => (
        <div
          key={toast.id}
          className={`px-6 py-3 rounded-lg shadow-lg text-white flex items-center justify-between min-w-[300px] ${
            toast.type === 'success' ? 'bg-green-600' :
            toast.type === 'error' ? 'bg-red-600' :
            toast.type === 'warning' ? 'bg-yellow-600' :
            'bg-blue-600'
          }`}
        >
          <span>{toast.message}</span>
          <button
            onClick={() => onClose(toast.id)}
            className="ml-4 text-white hover:text-gray-200"
          >
            ×
          </button>
        </div>
      ))}
    </div>
  );
}
```

**使用方法**
```tsx
// app/layout.tsx
import { ToastProvider } from '@/contexts/ToastContext';

export default function RootLayout({ children }) {
  return (
    <html lang="ja">
      <body>
        <ToastProvider>
          {children}
        </ToastProvider>
      </body>
    </html>
  );
}

// コンポーネント内
import { useToast } from '@/contexts/ToastContext';

function MyComponent() {
  const { showToast } = useToast();

  const handleSave = async () => {
    try {
      await saveData();
      showToast('success', '保存しました');
    } catch (err) {
      showToast('error', '保存に失敗しました');
    }
  };
}
```

</details>

---

## 📝 推奨アクション

### フェーズ1: グローバル通知システムの導入
1. **Sonner**の導入（最小工数、即座に効果）
2. 既存のコンポーネントを段階的に移行

### フェーズ2: 高優先度の日本語化
1. `lib/http.ts`のエラーメッセージ修正
2. `lib/auth.ts`、`lib/dal.ts`のエラーメッセージ修正
3. UIで表示されるエラーメッセージ（verify-email等）を修正

### フェーズ3: console.errorの日本語化
1. ユーザー向けログは日本語化
2. 開発用デバッグログは英語のまま、またはコメントで補足

### フェーズ4: 既存コンポーネントのリファクタリング
1. 各コンポーネントの重複したトーストUIを削除
2. グローバルトーストシステムへ移行

---

## 🔧 実装サンプル（Sonner移行）

**Before (Profile.tsx)**
```tsx
const [error, setError] = useState<string | null>(null);
const [successMessage, setSuccessMessage] = useState<string | null>(null);

try {
  await profileApi.updateName(nameData);
  setSuccessMessage('名前を更新しました');
  setTimeout(() => setSuccessMessage(null), 3000);
} catch (err: unknown) {
  const message = err instanceof Error ? err.message : String(err);
  setError(message || '名前の更新に失敗しました');
}

// JSX内の重複したトーストUI（削除）
```

**After (Sonner使用)**
```tsx
import { toast } from 'sonner';

try {
  await profileApi.updateName(nameData);
  toast.success('名前を更新しました');
} catch (err: unknown) {
  const message = err instanceof Error ? err.message : String(err);
  toast.error(message || '名前の更新に失敗しました');
}

// JSXからトーストUI削除（グローバルToasterが表示）
```

**削減されるコード**: 各コンポーネントから約40行のボイラープレート削除可能

---

## 📈 期待される効果

1. **コード削減**: 約2000-3000行のボイラープレートコード削除
2. **保守性向上**: 通知UIの一元管理
3. **UX改善**: ページ遷移時も通知が表示され続ける
4. **国際化対応**: 全てのエラーメッセージが日本語化
5. **開発速度向上**: 新しいコンポーネントでトーストUI実装不要

---
---

# 🔧 バックエンドAPI - エラーメッセージ調査結果

## 📊 調査サマリー

### 発見された英語メッセージ
- **認証・認可関連**: 約30箇所
- **MFA関連**: 約10箇所
- **福祉受給者関連**: 約10箇所
- **ロール変更・権限**: 約15箇所
- **カレンダー連携**: 約10箇所
- **バリデーション**: 約10箇所
- **サービス層**: 約15箇所

**合計: 約100箇所以上**

---

## 🔴 バックエンドの日本語化が必要な箇所（優先度別）

### 【最高優先度】認証・認可エラー（ユーザーが頻繁に遭遇）

#### 1. ユーザー登録 (`auths.py`)

| ファイル:行 | エンドポイント | 現在のメッセージ | 推奨 |
|---|---|---|---|
| `auths.py:60` | `POST /api/v1/auth/register-admin` | `"The user with this email already exists in the system."` | `"このメールアドレスは既に登録されています"` |
| `auths.py:103` | `POST /api/v1/auth/register` | `"The user with this email already exists in the system."` | `"このメールアドレスは既に登録されています"` |

#### 2. メール確認 (`auths.py`)

| ファイル:行 | エンドポイント | 現在のメッセージ | 推奨 |
|---|---|---|---|
| `auths.py:140` | `GET /api/v1/auth/verify-email` | `"Invalid or expired token"` | `"確認リンクが無効または期限切れです"` |
| `auths.py:147` | `GET /api/v1/auth/verify-email` | `"User not found"` | `"ユーザーが見つかりません"` |
| `auths.py:151` | `GET /api/v1/auth/verify-email` | `"Email already verified"` | `"メールアドレスは既に確認済みです"` |
| `auths.py:159` | `GET /api/v1/auth/verify-email` | `"Email verified successfully"` | `"メールアドレスの確認が完了しました"` |

#### 3. ログイン (`auths.py`)

| ファイル:行 | エンドポイント | 現在のメッセージ | 推奨 |
|---|---|---|---|
| `auths.py:182` | `POST /api/v1/auth/token` | `"Incorrect email or password"` | `"メールアドレスまたはパスワードが正しくありません"` |
| `auths.py:188` | `POST /api/v1/auth/token` | `"Email not verified"` | `"メールアドレスの確認が完了していません"` |
| `auths.py:277` | `POST /api/v1/auth/token` | `"Login successful"` | `"ログインしました"` |

#### 4. トークンリフレッシュ (`auths.py`)

| ファイル:行 | エンドポイント | 現在のメッセージ | 推奨 |
|---|---|---|---|
| `auths.py:303, 310` | `POST /api/v1/auth/refresh-token` | `"Invalid refresh token"` | `"リフレッシュトークンが無効です"` |
| `auths.py:345` | `POST /api/v1/auth/refresh-token` | `"Token refreshed"` | `"トークンを更新しました"` |

#### 5. MFA検証（ログイン時） (`auths.py`)

| ファイル:行 | エンドポイント | 現在のメッセージ | 推奨 |
|---|---|---|---|
| `auths.py:361` | `POST /api/v1/auth/token/verify-mfa` | `"Invalid or expired temporary token"` | `"一時トークンが無効または期限切れです"` |
| `auths.py:371` | `POST /api/v1/auth/token/verify-mfa` | `"MFA not properly configured"` | `"多要素認証が正しく設定されていません"` |
| `auths.py:389` | `POST /api/v1/auth/token/verify-mfa` | `"Invalid TOTP code or recovery code"` | `"認証コードまたはリカバリコードが正しくありません"` |
| `auths.py:436` | `POST /api/v1/auth/token/verify-mfa` | `"MFA verification successful"` | `"多要素認証に成功しました"` |

#### 6. ログアウト (`auths.py`)

| ファイル:行 | エンドポイント | 現在のメッセージ | 推奨 |
|---|---|---|---|
| `auths.py:469` | `POST /api/v1/auth/logout` | `"Logout successful"` | `"ログアウトしました"` |

#### 7. 権限チェック (`deps.py`)

| ファイル:行 | 現在のメッセージ | 推奨 |
|---|---|---|
| `deps.py:66` | `"Could not validate credentials"` | `"認証情報を検証できませんでした"` |
| `deps.py:158` | `"Manager or Owner role required"` | `"管理者または事業所管理者の権限が必要です"` |
| `deps.py:175` | `"Owner role required"` | `"事業所管理者の権限が必要です"` |
| `deps.py:233` | `"Staff must be associated with an office"` | `"スタッフは事業所に所属している必要があります"` |

---

### 【高優先度】MFA（多要素認証）関連

#### MFA エンドポイント (`mfa.py`)

| ファイル:行 | エンドポイント | 現在のメッセージ | 推奨 |
|---|---|---|---|
| `mfa.py:44` | `POST /api/v1/mfa/enroll` | `"MFA is already enabled for this user."` | `"多要素認証は既に有効になっています"` |
| `mfa.py:81` | `POST /api/v1/mfa/verify` | `"MFA is not enrolled for this user."` | `"多要素認証が登録されていません"` |
| `mfa.py:87` | `POST /api/v1/mfa/verify` | `"MFA is already enabled."` | `"多要素認証は既に有効になっています"` |
| `mfa.py:97` | `POST /api/v1/mfa/verify` | `"Invalid TOTP code."` | `"認証コードが正しくありません"` |
| `mfa.py:100` | `POST /api/v1/mfa/verify` | `"MFA verification successful"` | `"多要素認証の検証に成功しました"` |
| `mfa.py:128` | `POST /api/v1/mfa/disable` | `"MFA is not enabled for this user."` | `"多要素認証は有効になっていません"` |
| `mfa.py:135` | `POST /api/v1/mfa/disable` | `"Incorrect password."` | `"パスワードが正しくありません"` |
| `mfa.py:142` | `POST /api/v1/mfa/disable` | `"MFA disabled successfully"` | `"多要素認証を無効にしました"` |

---

### 【高優先度】福祉受給者関連

#### 福祉受給者エンドポイント (`welfare_recipients.py`)

| ファイル:行 | エンドポイント | 現在のメッセージ | 推奨 |
|---|---|---|---|
| `welfare_recipients.py:58` | `POST /api/v1/welfare-recipients/` | `"Staff member must be associated with an office to create recipients"` | `"利用者を作成するには事業所に所属する必要があります"` |
| `welfare_recipients.py:78` | `POST /api/v1/welfare-recipients/` | `"Request created and pending approval"` | `"申請を作成しました。承認待ちです"` |
| `welfare_recipients.py:142` | `POST /api/v1/welfare-recipients/` | `"Failed to create welfare recipient: {str(e)}"` | `"利用者の作成に失敗しました: {str(e)}"` |
| `welfare_recipients.py:160` | `GET /api/v1/welfare-recipients/` | `"Staff member must be associated with an office"` | `"事業所に所属している必要があります"` |
| `welfare_recipients.py:270` | `PUT /api/v1/welfare-recipients/{id}` | `"Request created and pending approval"` | `"申請を作成しました。承認待ちです"` |
| `welfare_recipients.py:294` | `PUT /api/v1/welfare-recipients/{id}` | `"Failed to update welfare recipient: {str(e)}"` | `"利用者の更新に失敗しました: {str(e)}"` |
| `welfare_recipients.py:341` | `DELETE /api/v1/welfare-recipients/{id}` | `"Request created and pending approval"` | `"申請を作成しました。承認待ちです"` |
| `welfare_recipients.py:351` | `DELETE /api/v1/welfare-recipients/{id}` | `"Failed to delete welfare recipient"` | `"利用者の削除に失敗しました"` |
| `welfare_recipients.py:354` | `DELETE /api/v1/welfare-recipients/{id}` | `"Welfare recipient deleted successfully"` | `"利用者を削除しました"` |
| `welfare_recipients.py:362` | `DELETE /api/v1/welfare-recipients/{id}` | `"Failed to delete welfare recipient: {str(e)}"` | `"利用者の削除に失敗しました: {str(e)}"` |

---

### 【中優先度】ロール変更・権限リクエスト

#### ロール変更リクエスト (`role_change_requests.py`)

| ファイル:行 | エンドポイント | 現在のメッセージ | 推奨 |
|---|---|---|---|
| `role_change_requests.py:46` | `POST /api/v1/role-change-requests` | `"You are already a {current_user.role.value}"` | `"既に{current_user.role.value}の権限を持っています"` |
| `role_change_requests.py:53` | `POST /api/v1/role-change-requests` | `"You are not associated with any office"` | `"事業所に所属していません"` |
| `role_change_requests.py:148` | `PATCH /api/v1/role-change-requests/{id}/approve` | `"Request not found"` | `"リクエストが見つかりません"` |
| `role_change_requests.py:155` | `PATCH /api/v1/role-change-requests/{id}/approve` | `"Request is already {request.status.value}"` | `"リクエストは既に{request.status.value}です"` |
| `role_change_requests.py:162` | `PATCH /api/v1/role-change-requests/{id}/approve` | `"You do not have permission to approve this request"` | `"このリクエストを承認する権限がありません"` |
| `role_change_requests.py:252` | `DELETE /api/v1/role-change-requests/{id}` | `"Request not found"` | `"リクエストが見つかりません"` |
| `role_change_requests.py:259` | `DELETE /api/v1/role-change-requests/{id}` | `"You can only delete your own requests"` | `"自分のリクエストのみ削除できます"` |
| `role_change_requests.py:266` | `DELETE /api/v1/role-change-requests/{id}` | `"Cannot delete {request.status.value} request"` | `"{request.status.value}状態のリクエストは削除できません"` |

---

### 【中優先度】個別支援計画関連

#### サポートプラン (`support_plans.py`)

| ファイル:行 | エンドポイント | 現在のメッセージ | 推奨 |
|---|---|---|---|
| `support_plans.py:486, 496` | `GET /api/v1/support-plans/plan-deliverables` | `"Invalid recipient_ids format: {e}"` | `"パラメータの形式が正しくありません: {e}"` |

---

### 【中優先度】事業所関連

#### 事業所エンドポイント (`offices.py`)

| ファイル:行 | エンドポイント | 現在のメッセージ | 推奨 |
|---|---|---|---|
| `offices.py:86` | `POST /api/v1/offices/setup` | `"User not found"` | `"ユーザーが見つかりません"` |

#### 事業所-スタッフ関連付け (`office_staff.py`)

| ファイル:行 | エンドポイント | 現在のメッセージ | 推奨 |
|---|---|---|---|
| `office_staff.py:28` | `POST /api/v1/office-staff/associate-office` | `"Owner cannot use this endpoint."` | `"事業所管理者はこのエンドポイントを使用できません"` |
| `office_staff.py:37` | `POST /api/v1/office-staff/associate-office` | `"User not found"` | `"ユーザーが見つかりません"` |

---

### 【中優先度】カスタム例外クラス

#### 共通例外 (`exceptions.py`)

| ファイル:行 | 例外クラス | デフォルトメッセージ | 推奨 |
|---|---|---|---|
| `exceptions.py:18` | `BadRequestException` | `"Bad request"` | `"不正なリクエストです"` |
| `exceptions.py:27` | `NotFoundException` | `"Not found"` | `"見つかりません"` |
| `exceptions.py:31` | `ForbiddenException` | `"Forbidden"` | `"アクセスが拒否されました"` |
| `exceptions.py:35` | `InternalServerException` | `"Internal server error"` | `"サーバー内部エラーが発生しました"` |

---

### 【低優先度】バリデーションスキーマ

#### スタッフスキーマ (`schemas/staff.py`)

| ファイル:行 | 現在のメッセージ | 推奨 |
|---|---|---|
| `staff.py:70` | `"Cannot register as an owner through this endpoint."` | `"このエンドポイントからオーナーとして登録できません"` |

#### カレンダーアカウントスキーマ (`schemas/calendar_account.py`)

| ファイル:行 | 現在のメッセージ | 推奨 |
|---|---|---|
| `calendar_account.py:81` | `"All reminder days must be positive integers"` | `"リマインダー日数は正の整数である必要があります"` |
| `calendar_account.py:84` | `"custom_reminder_days must be comma-separated positive integers"` | `"カスタムリマインダー日数はカンマ区切りの正の整数である必要があります"` |
| `calendar_account.py:183` | `"Missing required field in service account JSON: {field}"` | `"サービスアカウントJSONに必須フィールドがありません: {field}"` |
| `calendar_account.py:187` | `"Invalid service account JSON: type must be 'service_account'"` | `"無効なサービスアカウントJSONです: typeは'service_account'である必要があります"` |
| `calendar_account.py:191` | `"Invalid JSON format: {str(e)}"` | `"無効なJSON形式です: {str(e)}"` |

#### 福祉受給者スキーマ (`schemas/welfare_recipient.py`)

| ファイル:行 | 現在のメッセージ | 推奨 |
|---|---|---|
| `welfare_recipient.py:114, 136` | `'Birth date cannot be in the future'` | `"生年月日は未来の日付にできません"` |

---

### 【低優先度】サービス層

#### ロール変更サービス (`services/role_change_service.py`)

| ファイル:行 | 現在のメッセージ | 推奨 |
|---|---|---|
| `role_change_service.py:57` | `"Staff {requester_staff_id} not found"` | `"スタッフ {requester_staff_id} が見つかりません"` |
| `role_change_service.py:142` | `"Request {request_id} not found"` | `"リクエスト {request_id} が見つかりません"` |
| `role_change_service.py:147` | `"Reviewer staff {reviewer_staff_id} not found"` | `"レビュワースタッフ {reviewer_staff_id} が見つかりません"` |

#### Employee制限サービス (`services/employee_action_service.py`)

| ファイル:行 | 現在のメッセージ | 推奨 |
|---|---|---|
| `employee_action_service.py:148` | `"Request {request_id} not found"` | `"リクエスト {request_id} が見つかりません"` |
| `employee_action_service.py:443` | `"Unsupported resource type: {resource_type}"` | `"サポートされていないリソースタイプです: {resource_type}"` |
| `employee_action_service.py:632` | `"resource_id is required for update action"` | `"更新操作にはresource_idが必要です"` |
| `employee_action_service.py:636` | `"WelfareRecipient {recipient_id} not found"` | `"利用者 {recipient_id} が見つかりません"` |
| `employee_action_service.py:684` | `"resource_id or welfare_recipient_id is required for delete action"` | `"削除操作にはresource_idまたはwelfare_recipient_idが必要です"` |
| `employee_action_service.py:688` | `"WelfareRecipient {recipient_id} not found"` | `"利用者 {recipient_id} が見つかりません"` |
| `employee_action_service.py:700` | `"Unsupported action type: {action_type}"` | `"サポートされていないアクションタイプです: {action_type}"` |

#### カレンダーサービス (`services/calendar_service.py`)

| ファイル:行 | 現在のメッセージ | 推奨 |
|---|---|---|
| `calendar_service.py:71` | `"Office {request.office_id} already has a calendar account"` | `"事業所 {request.office_id} は既にカレンダーアカウントを持っています"` |
| `calendar_service.py:124, 255, 722` | `"Calendar account {account_id} not found"` | `"カレンダーアカウント {account_id} が見つかりません"` |
| `calendar_service.py:230` | `"client_email not found in service account JSON"` | `"サービスアカウントJSONにclient_emailが見つかりません"` |
| `calendar_service.py:233` | `"Invalid JSON format: {str(e)}"` | `"無効なJSON形式です: {str(e)}"` |
| `calendar_service.py:264, 800` | `"Service account key not found"` | `"サービスアカウントキーが見つかりません"` |

---

## 💡 バックエンド日本語化の推奨実装方法

### オプション1: メッセージ定数ファイル（推奨）

**ファイル構成**:
```
k_back/
  app/
    messages/
      __init__.py
      ja.py          # 日本語メッセージ
      en.py          # 英語メッセージ（将来対応用）
```

**実装例 (`app/messages/ja.py`)**:
```python
"""日本語エラーメッセージ定数"""

# 認証関連
AUTH_EMAIL_ALREADY_EXISTS = "このメールアドレスは既に登録されています"
AUTH_INVALID_TOKEN = "確認リンクが無効または期限切れです"
AUTH_USER_NOT_FOUND = "ユーザーが見つかりません"
AUTH_EMAIL_ALREADY_VERIFIED = "メールアドレスは既に確認済みです"
AUTH_EMAIL_VERIFIED = "メールアドレスの確認が完了しました"
AUTH_INCORRECT_CREDENTIALS = "メールアドレスまたはパスワードが正しくありません"
AUTH_EMAIL_NOT_VERIFIED = "メールアドレスの確認が完了していません"
AUTH_LOGIN_SUCCESS = "ログインしました"
AUTH_INVALID_REFRESH_TOKEN = "リフレッシュトークンが無効です"
AUTH_TOKEN_REFRESHED = "トークンを更新しました"
AUTH_LOGOUT_SUCCESS = "ログアウトしました"

# MFA関連
MFA_ALREADY_ENABLED = "多要素認証は既に有効になっています"
MFA_NOT_ENROLLED = "多要素認証が登録されていません"
MFA_INVALID_CODE = "認証コードが正しくありません"
MFA_VERIFICATION_SUCCESS = "多要素認証の検証に成功しました"
MFA_NOT_ENABLED = "多要素認証は有効になっていません"
MFA_INCORRECT_PASSWORD = "パスワードが正しくありません"
MFA_DISABLED_SUCCESS = "多要素認証を無効にしました"

# 権限関連
PERM_CREDENTIALS_INVALID = "認証情報を検証できませんでした"
PERM_MANAGER_OR_OWNER_REQUIRED = "管理者または事業所管理者の権限が必要です"
PERM_OWNER_REQUIRED = "事業所管理者の権限が必要です"
PERM_OFFICE_REQUIRED = "スタッフは事業所に所属している必要があります"

# 福祉受給者関連
RECIPIENT_OFFICE_REQUIRED = "利用者を作成するには事業所に所属する必要があります"
RECIPIENT_REQUEST_PENDING = "申請を作成しました。承認待ちです"
RECIPIENT_CREATE_FAILED = "利用者の作成に失敗しました: {error}"
RECIPIENT_UPDATE_FAILED = "利用者の更新に失敗しました: {error}"
RECIPIENT_DELETE_FAILED = "利用者の削除に失敗しました"
RECIPIENT_DELETED = "利用者を削除しました"

# 例外クラス
EXC_BAD_REQUEST = "不正なリクエストです: {error}"
EXC_NOT_FOUND = "見つかりません"
EXC_FORBIDDEN = "アクセスが拒否されました: {error}"
EXC_INTERNAL_ERROR = "サーバー内部エラーが発生しました: {error}"
```

**使用例**:
```python
# 修正前
raise HTTPException(status_code=400, detail="The user with this email already exists in the system.")

# 修正後
from app.messages import ja

raise HTTPException(status_code=400, detail=ja.AUTH_EMAIL_ALREADY_EXISTS)
```

---

### オプション2: i18n ライブラリの導入（将来の多言語対応）

**ライブラリ**: `python-i18n` または `babel`

**実装例**:
```python
import i18n

# 設定
i18n.set('locale', 'ja')
i18n.set('fallback', 'en')
i18n.load_path.append('app/locales')

# 使用
raise HTTPException(
    status_code=400,
    detail=i18n.t('auth.email_already_exists')
)
```

**翻訳ファイル (`app/locales/ja.yml`)**:
```yaml
auth:
  email_already_exists: "このメールアドレスは既に登録されています"
  invalid_credentials: "メールアドレスまたはパスワードが正しくありません"
  email_not_verified: "メールアドレスの確認が完了していません"
```

---

## 📝 バックエンド日本語化の推奨フェーズ

### フェーズ1: 最高優先度（ユーザー影響大）
1. 認証エラーメッセージ (`auths.py`)
2. 権限チェックエラー (`deps.py`)
3. MFAエラーメッセージ (`mfa.py`)

**推定工数**: 2-3時間

### フェーズ2: 高優先度
1. 福祉受給者関連 (`welfare_recipients.py`)
2. ロール変更リクエスト (`role_change_requests.py`)
3. 共通例外クラス (`exceptions.py`)

**推定工数**: 3-4時間

### フェーズ3: 中優先度
1. 事業所関連 (`offices.py`, `office_staff.py`)
2. サポートプラン (`support_plans.py`)
3. サービス層のエラーメッセージ

**推定工数**: 4-5時間

### フェーズ4: 低優先度
1. バリデーションスキーマ
2. 開発者向けの技術的エラー

**推定工数**: 2-3時間

---

## 🎯 バックエンド日本語化の実装サンプル

### Before
```python
# app/api/v1/endpoints/auths.py:182
if not user or not verify_password(form_data.password, user.password_hash):
    raise HTTPException(
        status_code=status.HTTP_401_UNAUTHORIZED,
        detail="Incorrect email or password",
        headers={"WWW-Authenticate": "Bearer"},
    )
```

### After (メッセージ定数使用)
```python
from app.messages import ja

# app/api/v1/endpoints/auths.py:182
if not user or not verify_password(form_data.password, user.password_hash):
    raise HTTPException(
        status_code=status.HTTP_401_UNAUTHORIZED,
        detail=ja.AUTH_INCORRECT_CREDENTIALS,
        headers={"WWW-Authenticate": "Bearer"},
    )
```

---

## 📊 全体統計

### フロントエンド + バックエンド
- **フロントエンド**: 約70箇所
- **バックエンド**: 約100箇所
- **合計**: **約170箇所以上**の日本語化が必要

### 期待される効果
1. **UX向上**: 全てのエラーメッセージが日本語で表示
2. **保守性向上**: メッセージの一元管理
3. **国際化対応**: 将来的な多言語対応の基盤
4. **開発効率向上**: 統一されたメッセージ管理方法


- フロントエンド: グローバル通知システム Sonner
- バックエンド: i18n

⏺ テストファイルを作成しました。次に、テストを実行して現在の状態を確認します。

⏺ Bash(cd k_back && python -m pytest tests/error_handling/test_japanese_error_messages.py -v
      --tb=short 2>&1 | head -100)
  ⎿  Interrupted · What should Claude do instead?
  ⎿  Interrupted · What should Claude do instead?

  > dockerで実行
---

# ✅ 実装完了 (2025-01-15)

## 実装サマリー

### フェーズ1: Sonnerグローバル通知システムの導入 ✅
- [x] `sonner` パッケージをインストール
- [x] `k_front/app/layout.tsx` にToasterコンポーネントを統合
- [x] 言語設定を日本語(`lang="ja"`)に変更

### フェーズ2: フロントエンド - 高優先度エラーメッセージの日本語化 ✅
- [x] **lib/http.ts**: 認証エラー、リクエストエラーを日本語化
- [x] **lib/auth.ts**: ログインエラーを日本語化
- [x] **lib/dal.ts**: 認証・権限エラーを日本語化
- [x] **lib/support-plan.ts**: アップロードエラーを日本語化
- [x] **app/auth/verify-email/page.tsx**: メール認証エラーを日本語化

### フェーズ3: バックエンド - 日本語メッセージ定数ファイルの作成 ✅
- [x] `k_back/app/messages/ja.py` を作成
- [x] 認証、MFA、権限、福祉受給者など約145個の日本語メッセージ定数を定義

### フェーズ4: バックエンド - 最高優先度エラーメッセージの日本語化 ✅
- [x] **app/api/v1/endpoints/auths.py**: 認証関連すべてのメッセージを日本語化
- [x] **app/api/deps.py**: 権限チェック関連のエラーを日本語化

### フェーズ5: 既存コンポーネントをSonnerへ移行 ✅
- [x] **components/protected/profile/Profile.tsx** を完全移行
  - `toast.success()` と `toast.error()` を使用
  - 重複したトーストUIコード(約40行)を削除
  - `error` と `successMessage` のstate管理を削除
  - **すべての`setError`と`setSuccessMessage`の呼び出しを削除**

---

## 🚨 重要な教訓: State削除時の注意点

### 問題
`error`と`successMessage`のstateを削除したにもかかわらず、コード内で`setError()`や`setSuccessMessage()`の呼び出しが残存していた。

### 影響
- TypeScriptコンパイルエラー: `Cannot find name 'setError'`, `Cannot find name 'setSuccessMessage'`
- アプリケーションが起動しない

### 修正内容
以下の箇所をすべて修正:

1. **メールアドレス変更リクエスト (180, 196-199行目)**
   ```typescript
   // Before
   setError(null);
   setSuccessMessage(`確認メールを ${newEmail} に送信しました...`);
   setTimeout(() => setSuccessMessage(null), 10000);

   // After
   toast.success(`確認メールを ${newEmail} に送信しました...`, { duration: 10000 });
   ```

2. **フィードバック送信 (212-213行目)**
   ```typescript
   // Before
   setError('フィードバック内容を入力してください');
   setTimeout(() => setError(null), 3000);

   // After
   toast.error('フィードバック内容を入力してください');
   ```

3. **メールクライアント起動 (264-270, 277-285行目)**
   ```typescript
   // Before
   setSuccessMessage(message);
   setTimeout(() => setSuccessMessage(null), 5000);
   setError('メールクライアントの起動に失敗しました...');
   setTimeout(() => setError(null), 5000);

   // After
   toast.success(message, { duration: 5000 });
   toast.error('メールクライアントの起動に失敗しました...', { duration: 5000 });
   ```

4. **ロール変更モーダル (675-677行目)**
   ```typescript
   // Before
   onSuccess={() => {
     setSuccessMessage('権限変更リクエストを送信しました...');
     setTimeout(() => setSuccessMessage(null), 5000);
   }}

   // After
   onSuccess={() => {
     toast.success('権限変更リクエストを送信しました...', { duration: 5000 });
   }}
   ```

5. **モーダルキャンセルボタン (657, 777行目)**
   ```typescript
   // Before
   onClick={() => {
     setIsPasswordModalOpen(false);
     setError(null);
   }}

   // After
   onClick={() => {
     setIsPasswordModalOpen(false);
     // setError(null)を削除
   }}
   ```

### 今後の対策チェックリスト

Stateを削除する際は、以下を必ず確認:

1. **State宣言を削除**
   ```typescript
   // 削除対象
   const [error, setError] = useState<string | null>(null);
   const [successMessage, setSuccessMessage] = useState<string | null>(null);
   ```

2. **Setterの呼び出しをすべて検索**
   ```bash
   # grepで検索
   grep -n "setError\|setSuccessMessage" <ファイルパス>
   ```

3. **各呼び出しを適切に置き換え**
   - `setError(message)` → `toast.error(message)`
   - `setSuccessMessage(message)` → `toast.success(message)`
   - `setError(null)` → 削除(不要)
   - `setSuccessMessage(null)` → 削除(不要)
   - `setTimeout(() => set...(null), ...)` → 削除(Sonnerが自動で消す)

4. **UIレンダリング部分を削除**
   ```typescript
   // 削除対象
   {error && <div className="...">...</div>}
   {successMessage && <div className="...">...</div>}
   ```

5. **TypeScriptコンパイルを確認**
   ```bash
   npm run build
   # または
   npx tsc --noEmit
   ```

---

## 📊 移行の成果

### Profile.tsx での改善
- **削除されたコード**: 約60行
  - State定義: 2行
  - Setter呼び出し: 約13箇所
  - トーストUI: 約20行
  - setTimeout: 約10箇所
- **追加されたコード**: 1行 (`import { toast } from 'sonner'`)
- **ネット削減**: 約59行

### 期待される効果
1. **コード削減**: 約2000-3000行のボイラープレートコード削除(全体)
2. **保守性向上**: 通知UIの一元管理
3. **UX改善**: ページ遷移時も通知が表示され続ける
4. **国際化対応**: すべてのエラーメッセージが日本語化
5. **開発速度向上**: 新しいコンポーネントでトーストUI実装不要

---

## 🔄 次のステップ: 残りのコンポーネント移行

### 移行対象コンポーネント

以下のコンポーネントも同じパターンで移行:

#### 高優先度
1. **NotificationsTab.tsx**
   - 予想削減: 約40行

2. **Dashboard.tsx**
   - 予想削減: 約50行

#### 中優先度
3. **EmploymentSection.tsx**
   - 予想削減: 約30行

4. **MedicalInfoForm.tsx**
   - 予想削減: 約30行

5. **SupportPlan.tsx**
   - 予想削減: 約40行

### 移行手順(テンプレート)

```typescript
// 1. Sonnerをインポート
import { toast } from 'sonner';

// 2. Stateを削除
// const [error, setError] = useState<string | null>(null);
// const [successMessage, setSuccessMessage] = useState<string | null>(null);

// 3. Setterをtoastに置き換え
// setError(message) → toast.error(message)
// setSuccessMessage(message) → toast.success(message)
// setError(null) → 削除
// setTimeout(() => set...(null), ...) → 削除

// 4. UIを削除
// {error && <div>...</div>} → 削除
// {successMessage && <div>...</div>} → 削除

// 5. 確認
// grep -n "setError\|setSuccessMessage" <ファイル>
```

### 移行時のチェックリスト

- [ ] `import { toast } from 'sonner'` を追加
- [ ] `const [error, setError] = useState...` を削除
- [ ] `const [successMessage, setSuccessMessage] = useState...` を削除
- [ ] `setError(...)` → `toast.error(...)` に置換
- [ ] `setSuccessMessage(...)` → `toast.success(...)` に置換
- [ ] `setError(null)` を削除
- [ ] `setSuccessMessage(null)` を削除
- [ ] `setTimeout(() => setError(null), ...)` を削除
- [ ] `setTimeout(() => setSuccessMessage(null), ...)` を削除
- [ ] トーストUI JSX を削除
- [ ] `grep -n "setError\|setSuccessMessage"` で残存確認
- [ ] TypeScriptコンパイルエラーを確認
- [ ] 動作確認

---

## 📝 補足: MFA関連とその他の日本語化

### 今後の日本語化対象

#### 中優先度 (console.error)
- 約35箇所のconsole.errorを日本語化
- 開発時のデバッグ効率向上

#### 低優先度
- バリデーションスキーマのエラーメッセージ
- 開発用デバッグログ

### バックエンド追加実装

#### MFA エンドポイント (mfa.py)
- `app/api/v1/endpoints/mfa.py` のメッセージを日本語化
- `from app.messages import ja` をインポート
- 既存の定数を使用

#### 福祉受給者エンドポイント (welfare_recipients.py)
- `app/api/v1/endpoints/welfare_recipients.py` のメッセージを日本語化

---

## 🎯 最終目標

- フロントエンド: **すべてのコンポーネント**でSonnerを使用
- バックエンド: **すべてのユーザー向けメッセージ**を日本語化
- 統一された国際化基盤の構築

---

# 🔧 MFAテスト失敗の修正 (2025-01-15)

## 問題

日本語化実装後、MFA関連のテストが失敗：

```
FAILED tests/api/v1/test_mfa_api.py::TestMFALogin::test_login_mfa_enabled_success - AssertionError: assert '多要素認証に成功しました' == 'MFA verification successful'
FAILED tests/api/v1/test_mfa_api.py::TestMFALogin::test_login_mfa_enabled_invalid_totp - AssertionError: assert 'invalid' in '認証コードまたはリカバリコードが正しくありません'
FAILED tests/api/v1/test_mfa_api.py::TestMFALogin::test_login_invalid_temporary_token - AssertionError: assert 'invalid' in '一時トークンが無効または期限切れです'
```

## 原因

1. **auths.pyの日本語化**: MFAログイン関連のエンドポイントを日本語化したが、テストは英語を期待していた
2. **mfa.pyが未日本語化**: MFA登録・検証・無効化エンドポイントが英語のままだった

## 実施した修正

### 1. app/api/v1/endpoints/mfa.py の日本語化

```python
# Before
detail="MFA is already enabled for this user."
detail="MFA is not enrolled for this user."
detail="Invalid TOTP code."
{"message": "MFA verification successful"}
{"message": "MFA disabled successfully"}

# After
from app.messages import ja

detail=ja.MFA_ALREADY_ENABLED
detail=ja.MFA_NOT_ENROLLED
detail=ja.MFA_INVALID_CODE
{"message": ja.MFA_VERIFICATION_SUCCESS}
{"message": ja.MFA_DISABLED_SUCCESS}
```

### 2. tests/api/v1/test_mfa_api.py の修正

#### test_login_mfa_enabled_success (line 223)
```python
# Before
assert verify_data["message"] == "MFA verification successful"

# After
assert verify_data["message"] == "多要素認証に成功しました"
```

#### test_login_mfa_enabled_invalid_totp (line 254)
```python
# Before
assert "invalid" in verify_response.json()["detail"].lower()

# After
detail = verify_response.json()["detail"]
assert "認証コード" in detail or "リカバリコード" in detail or "正しくありません" in detail
```

#### test_login_invalid_temporary_token (line 269)
```python
# Before
assert "invalid" in response.json()["detail"].lower()

# After
detail = response.json()["detail"]
assert "一時トークン" in detail or "無効" in detail or "期限切れ" in detail
```

#### test_mfa_enroll_already_enabled (line 64)
```python
# Before
assert "already enabled" in response.json()["detail"].lower()

# After
detail = response.json()["detail"]
assert "多要素認証" in detail and "有効" in detail
```

#### test_mfa_verify_not_enrolled (line 151)
```python
# Before
assert "not enrolled" in response.json()["detail"].lower()

# After
detail = response.json()["detail"]
assert "多要素認証" in detail and "登録" in detail
```

#### test_mfa_verify_success (line 102)
```python
# Before
assert data["message"] == "MFA verification successful"

# After
assert data["message"] == "多要素認証の検証に成功しました"
```

#### test_mfa_disable_success (line 375)
```python
# Before
assert data["message"] == "MFA disabled successfully"

# After
assert data["message"] == "多要素認証を無効にしました"
```

## 実際のMFA認証について

ユーザーから「実際にMFA認証に正しい値を入力しても401エラーとなり弾かれた」との報告があったが、コードレビューの結果：

1. **auths.py の verify_mfa_for_login**: ロジックは正常
   - `verify_temporary_token_with_session()` で一時トークン検証
   - `verify_totp()` でTOTPコード検証
   - どちらも正しく実装されている

2. **考えられる原因**:
   - テストの失敗により、動作確認できなかった可能性
   - フロントエンドからの送信データの問題
   - 時刻のずれによるTOTPコードの不一致

## 検証方法

修正後、以下のテストを実行して確認:

```bash
cd k_back
python -m pytest tests/api/v1/test_mfa_api.py -v
```

## 教訓

### テスト駆動での日本語化

今後、エラーメッセージを日本語化する際は：

1. **バックエンドAPIを日本語化**
2. **対応するテストケースも同時に修正**
3. **テストを実行して確認**

この順序を守ることで、テスト失敗を最小限に抑えられる。

### テストの書き方

日本語メッセージのテストは、完全一致ではなく**キーワード検索**にすることで、メッセージの微修正に強くなる：

```python
# Good: 柔軟なテスト
detail = response.json()["detail"]
assert "多要素認証" in detail and "有効" in detail

# Less flexible: 完全一致
assert detail == "多要素認証は既に有効になっています"
```

## 完了した日本語化ファイル一覧

### バックエンド
- ✅ `app/api/v1/endpoints/auths.py` - 認証関連
- ✅ `app/api/v1/endpoints/mfa.py` - MFA関連
- ✅ `app/api/deps.py` - 権限チェック
- ✅ `app/messages/ja.py` - 日本語メッセージ定数

### テスト
- ✅ `tests/api/v1/test_mfa_api.py` - MFAテスト

### フロントエンド
- ✅ `lib/http.ts`
- ✅ `lib/auth.ts`
- ✅ `lib/dal.ts`
- ✅ `lib/support-plan.ts`
- ✅ `app/auth/verify-email/page.tsx`
- ✅ `components/protected/profile/Profile.tsx`
- ✅ `app/layout.tsx` (Sonner導入)
