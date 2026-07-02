## 現在
toastについて
- 表示される
利用者の作成,編集
- 表示されない
利用者の削除
PDFアップロード

## 原因
- クエリパラメータ?が渡されているか否か

---

# Toast表示調査結果（2025-11-16）

## 調査概要
フロントエンドでtoastが表示される処理とそうでない処理がある原因を調査。
CRUD操作における実装パターンの違いを特定。

## Toast実装の基本構造

### 使用ライブラリ
- **Sonner** v2.0.7
- 位置: 右上 (top-right)
- 表示時間: 5秒
- 最大表示数: 9個

### 実装ファイル
1. `k_front/app/toaster-provider.tsx` - Sonner初期化
2. `k_front/lib/toast-debug.ts` - toastラッパー（重複防止機能付き）
3. `k_front/app/layout.tsx` - ToasterProviderマウント

### 重複防止メカニズム
- 同じメッセージを1秒間ブロック
- デバッグ情報を自動ログ出力
- DOM状態確認機能あり

## CRUD操作ごとのToast表示パターン

### ✅ Create（利用者登録）- Toast表示あり
**ファイル**: `RecipientRegistrationForm.tsx:215`
```typescript
// 成功時：URLパラメータ経由でダッシュボードにメッセージを渡す
router.push('/dashboard?message=' + encodeURIComponent('利用者の登録が完了しました'))
```
**表示場所**: `Dashboard.tsx:105, 114-117`
- クエリパラメータからメッセージを検出
- `toast.success()` で表示

**パターン**: URLパラメータ経由

---

### ✅ Read（利用者情報取得）- Toast表示なし（意図的）
**ファイル**: `Dashboard.tsx:157-170`
```typescript
// データ取得後、UIに直接反映
const response = await welfareRecipientsApi.list(params);
setDashboardData(response);
```
**エラー時**: `console.error` のみ（行172）

**理由**: 検索・フィルタ操作は頻繁に発生するため、toastは不要

---

### ✅ Update（利用者情報更新）- Toast表示あり
**ファイル**: `RecipientEditForm.tsx:356`
```typescript
// 成功時：URLパラメータ経由
router.push('/dashboard?message=' + encodeURIComponent('利用者情報を更新しました'))
```

**ファイル**: `Profile.tsx:102, 142, 205`
```typescript
// プロフィール更新時は直接toast呼び出し
toast.success('名前を更新しました');
toast.success(response.message);
```

**パターン**: URLパラメータ or 直接呼び出し

---

### ❌ Delete（利用者削除）- Toast表示なし
**ファイル**: `Dashboard.tsx:241-264`
```typescript
// 確認ダイアログ
if (window.confirm(`${recipientName}さんを本当に削除しますか？...`)) {
  // API呼び出し
  await welfareRecipientsApi.delete(recipientId);

  // UI状態を直接更新
  setDashboardData(prevData => {
    const updatedRecipients = prevData.recipients.filter(...)
    return { ...prevData, recipients: updatedRecipients };
  });
}

// エラー時：alert（行260）
alert('利用者の削除に失敗しました。...');
```

**問題点**:
- 成功時のtoast表示なし
- エラー時は`alert()`を使用（toastではない）
- UI更新のみで完了

---

## Toast表示される処理 vs 表示されない処理

### Toast表示される処理

| 処理 | ファイル | 行番号 | パターン |
|------|---------|--------|---------|
| ログイン成功 | LoginForm.tsx | 37 | クエリパラメータ |
| ダッシュボード入場 | Dashboard.tsx | 105, 114-117 | クエリパラメータ |
| 名前更新成功 | Profile.tsx | 102 | 直接呼び出し |
| パスワード変更成功 | Profile.tsx | 142 | 直接呼び出し |
| メール変更リクエスト | Profile.tsx | 205 | 直接呼び出し |
| フィードバック送信 | Profile.tsx | 275 | 直接呼び出し |
| 権限変更リクエスト | Profile.tsx | 691 | 直接呼び出し |

### Toast表示されない処理

| 処理 | ファイル | 行番号 | 現在の表示方法 |
|------|---------|--------|---------------|
| 利用者情報取得 | Dashboard.tsx | 157-170 | UIに直接反映 |
| フィルター適用 | Dashboard.tsx | 145-176 | UIに直接反映 |
| 検索実行 | Dashboard.tsx | 354-357 | UIに直接反映 |
| **利用者削除** | Dashboard.tsx | 246 | confirm + UIアップデート |
| リセット処理 | Dashboard.tsx | 218-229 | UIリセット |
| 通知既読 | NotificationsTab.tsx | 70-78 | useState管理 |
| 通知承認/却下 | NotificationsTab.tsx | 96-137 | useState管理 |

---

## 原因分析

### 1. 実装パターンの不統一

#### パターンA: URLパラメータ経由（Create/Update）
```typescript
router.push('/dashboard?message=' + encodeURIComponent('成功メッセージ'))
```
- 別ページへリダイレクトする場合に使用
- Dashboard側でクエリパラメータを検出してtoast表示

#### パターンB: 直接toast呼び出し（Update - Profile）
```typescript
toast.success('成功メッセージ');
```
- 同じページに留まる場合に使用
- その場で即座に表示

#### パターンC: useState管理（通知ページ）
```typescript
const [successMessage, setSuccessMessage] = useState<string | null>(null);
setSuccessMessage('通知を既読にしました');
```
- toastを使わず独立した実装
- 3秒後に自動消去

#### パターンD: toast表示なし（Delete）
```typescript
// 成功時：何も表示しない
// エラー時：alert()のみ
```

### 2. 利用者削除でtoastが表示されない理由

**具体的な実装箇所**: `Dashboard.tsx:241-264`

1. **成功時の処理不足**
   - `await welfareRecipientsApi.delete(recipientId)` 成功後
   - `setDashboardData()` でUI更新のみ
   - **toast呼び出しが実装されていない**

2. **エラー時の古い実装**
   - `alert()` を使用（行260）
   - toastではなくブラウザ標準ダイアログ

3. **実装の意図**
   - confirmダイアログで確認済み
   - UIから即座に削除されるため、toastは不要と判断された可能性

### 3. PDFアップロードでtoastが表示されない理由

**調査結果**: PDFアップロード関連のコンポーネントが見つからず

可能性:
- 実装が未完了
- または別の機能名で実装されている
- RecipientEditForm内に統合されている可能性

---

## エラーハンドリングの違い

### Toast使用パターン（Profile.tsx）
```typescript
try {
  const response = await profileApi.updateName(nameData);
  toast.success('名前を更新しました');
} catch (err: unknown) {
  const message = err instanceof Error ? err.message : String(err);
  toast.error(message || '名前の更新に失敗しました');
}
```

### Toast未使用パターン（Dashboard.tsx）
```typescript
try {
  const [userData, data] = await Promise.all([...]);
  setDashboardData(data);
} catch (error) {
  console.error('Failed to fetch initial data:', error);
  // toast呼び出しなし
}
```

### Alert使用パターン（Dashboard.tsx - Delete）
```typescript
try {
  await welfareRecipientsApi.delete(recipientId);
  setDashboardData(prevData => ...); // UI更新のみ
} catch (error) {
  alert('利用者の削除に失敗しました。...');
}
```

---

## 通知ページの独立実装

**ファイル**: `NotificationsTab.tsx:15-16, 142-145`

toastを使わず、独自のメッセージ表示システム:
```typescript
const [successMessage, setSuccessMessage] = useState<string | null>(null);
const [error, setError] = useState<string | null>(null);

// 成功時
setSuccessMessage('通知を既読にしました');
setTimeout(() => setSuccessMessage(null), 3000);

// JSXで直接表示
{successMessage && (
  <div className="fixed top-4 right-4 bg-green-600 text-white ...">
    {successMessage}
  </div>
)}
```

**理由**: toastとは別にカスタムUIで表示

---

## Toast使用コンポーネント一覧

### 使用している（3ファイル）
1. `k_front/components/auth/LoginForm.tsx` - ログインメッセージ
2. `k_front/components/protected/dashboard/Dashboard.tsx` - ダッシュボード通知
3. `k_front/components/protected/profile/Profile.tsx` - プロフィール操作

### 使用していない
1. `k_front/components/protected/recipients/RecipientRegistrationForm.tsx` - URLパラメータ経由のみ
2. `k_front/components/protected/recipients/RecipientEditForm.tsx` - URLパラメータ経由のみ
3. `k_front/components/notice/NotificationsTab.tsx` - 独立したメッセージ管理

---

## 結論・改善提案

### 主な課題
1. **利用者削除でtoastが実装されていない**
   - 成功時: toast呼び出しなし
   - エラー時: `alert()` を使用

2. **実装パターンの不統一**
   - Create/Update: URLパラメータ vs 直接呼び出し
   - Delete: toast未実装
   - 通知: 独立実装

3. **エラーハンドリングの不均衡**
   - Profile: toast.error()
   - Dashboard: console.error() or alert()
   - 通知: useState管理

### 改善推奨方針

#### 1. 削除処理にtoast追加
```typescript
// Dashboard.tsx:246の後に追加
await welfareRecipientsApi.delete(recipientId);
toast.success(`${recipientName}さんを削除しました`); // 追加
setDashboardData(prevData => ...);
```

#### 2. エラーハンドリング統一
```typescript
catch (error) {
  console.error('Failed to delete recipient:', error);
  toast.error('利用者の削除に失敗しました'); // alert()から変更
}
```

#### 3. CRUD操作の統一パターン確立
```
Create: toast.success() + リダイレクト or UIアップデート
Read: toastなし（頻繁な操作のため）
Update: toast.success() + UIアップデート
Delete: confirm + toast.success() + UIアップデート
```

#### 4. 通知ページのtoast統一
- useState管理からtoastに移行
- 既存のカスタムUIを削除

---

## 技術詳細

### toast-debug.ts の機能
1. **重複防止**: 同じメッセージを1秒間ブロック
2. **デバッグログ**: メッセージ、オプション、タイムスタンプ、呼び出し元
3. **DOM確認**: `[data-sonner-toaster]`要素の存在確認
4. **メモリリーク防止**: 古いエントリ自動削除

### ToasterProvider 設定
```typescript
<Toaster
  position="top-right"
  richColors
  duration={5000}
  closeButton
  expand={true}
  visibleToasts={9}
/>
```

---

## ファイルパス参照

### 基本実装
- `k_front/app/toaster-provider.tsx`
- `k_front/lib/toast-debug.ts`
- `k_front/app/layout.tsx`

### CRUD実装
- `k_front/components/protected/dashboard/Dashboard.tsx` - Delete実装（toast未使用）
- `k_front/components/protected/recipients/RecipientRegistrationForm.tsx` - Create実装
- `k_front/components/protected/recipients/RecipientEditForm.tsx` - Update実装
- `k_front/components/protected/profile/Profile.tsx` - Update実装（toast使用）

### API層
- `k_front/lib/welfare-recipients.ts` - 利用者API
- `k_front/lib/http.ts` - HTTP基本設定

## 次のタスク
- PDFアップロード時にもtoast設定