## 1. 【UI】サインアップ時の利用規約チェック

### 現在の問題
サインアップページに利用規約を見ないと先に進めない仕掛けがあるが、リンクを踏まないとチェックボックスにチェックが入らないためわかりにくい。一見するとクリックで先に進めるように思えてしまう。

### 原因箇所
- `k_front/components/auth/TermsAgreement.tsx:30-40`

**問題のコード:**
```typescript
const handleTermsCheckboxChange = (e: React.ChangeEvent<HTMLInputElement>) => {
  if (!e.target.checked) {
    onTermsAgree(false);
  }
};
```

チェックボックスの `onChange` ハンドラーがチェックを外す時だけ `onTermsAgree(false)` を呼び出し、チェックを入れる時は何もしない。そのため、ユーザーがチェックボックスを直接クリックしても同意状態にならない。

### 改善方法

**実装済み**: チェックボックスをクリックした時に警告テキストを表示

実装内容:
- チェックボックスをクリックした時に、その下に赤文字で警告メッセージを表示
- 警告メッセージ内のリンクをクリックするとモーダルが開く
- モーダル内の「同意する」ボタンを押すと警告が消えてチェックが入る

```typescript
{showTermsWarning && !termsAgreed && (
  <div className="ml-7 mt-2 text-xs text-red-400">
    ※ <button
      type="button"
      onClick={() => setIsTermsModalOpen(true)}
      className="underline hover:text-red-300"
    >
      利用規約リンク
    </button>
    をクリックして内容を確認し、モーダル内の「同意する」ボタンを押してください
  </div>
)}
```

**修正ファイル**: `k_front/components/auth/TermsAgreement.tsx`

---

## 2. 【Backend】プロフィール自動入力問題

### 現在の問題
現在の設計ではプロフィール画面で初めて名字のふりがななどを入力する。そのデフォルトが「やまだ」「たろう」になっている。ここで初めて入力するのなら、サインアップ画面でふりがなを入力する方が手っ取り早い。

### 原因箇所
- `k_front/components/protected/profile/Profile.tsx:340, 350`
  - プロフィール編集画面で placeholder が「やまだ」「たろう」
- `k_front/components/auth/SignupForm.tsx:100-138`
  - サインアップ時にふりがなフィールドが存在しない（姓・名のみ）

### 改善方法

**サインアップフォームにふりがなフィールドを追加:**

`k_front/components/auth/SignupForm.tsx` の名前入力セクション（100-138行目）に以下を追加:

```typescript
<div className="grid grid-cols-2 gap-4">
  <div>
    <label htmlFor="last_name_furigana" className="block text-sm font-medium text-gray-300 mb-2">
      姓（ふりがな） <span className="text-red-400">*</span>
    </label>
    <input
      id="last_name_furigana"
      name="last_name_furigana"
      type="text"
      required
      value={formData.last_name_furigana}
      onChange={handleChange}
      pattern="^[ぁ-んー　]+$"
      maxLength={50}
      className="..."
      placeholder="やまだ"
      title="ふりがなはひらがなのみ使用可能です"
    />
  </div>
  <div>
    <label htmlFor="first_name_furigana" className="block text-sm font-medium text-gray-300 mb-2">
      名（ふりがな） <span className="text-red-400">*</span>
    </label>
    <input
      id="first_name_furigana"
      name="first_name_furigana"
      type="text"
      required
      value={formData.first_name_furigana}
      onChange={handleChange}
      pattern="^[ぁ-んー　]+$"
      maxLength={50}
      className="..."
      placeholder="たろう"
      title="ふりがなはひらがなのみ使用可能です"
    />
  </div>
</div>
```

**StaffCreateData 型にもフィールド追加が必要** (`k_front/types/staff.ts`)

---

## 3. 【UI】MFA ON/OFF ホバーで切り替え　MFAの説明

### 現在の問題
管理者メニューで、現在MFA設定を切り替える際に、現在のステータスの右隣に有効または無効化するボタンが常に表示されている。これをホバーした際に無効なら有効化、有効なら無効化ボタンが出るようにする。

### 原因箇所
- `k_front/components/protected/admin/AdminMenu.tsx:832-891`

**現在の実装:**
```typescript
<td className="py-3 px-4">
  <div className="flex items-center gap-2">
    <span className={...}>
      {s.is_mfa_enabled ? '有効' : '無効'}
    </span>
    {s.is_mfa_enabled ? (
      <button onClick={...}>無効化</button>
    ) : (
      <button onClick={...}>有効化</button>
    )}
  </div>
</td>
```

### 改善方法

**ホバー時のみボタンを表示:**

```typescript
<td className="py-3 px-4">
  <div className="flex items-center gap-2 group">
    <span className={...}>
      {s.is_mfa_enabled ? '有効' : '無効'}
    </span>
    {s.is_mfa_enabled ? (
      <button
        onClick={...}
        className="opacity-0 group-hover:opacity-100 transition-opacity bg-red-600 hover:bg-red-700 text-white px-3 py-1 rounded text-sm"
      >
        無効化
      </button>
    ) : (
      <button
        onClick={...}
        className="opacity-0 group-hover:opacity-100 transition-opacity bg-blue-600 hover:bg-blue-700 text-white px-3 py-1 rounded text-sm"
      >
        有効化
      </button>
    )}
  </div>
</td>
```

**ポイント**: `group` クラスを親要素に追加し、ボタンに `opacity-0 group-hover:opacity-100` を適用。

---

**改善2: MFA説明ヘルプボタンを追加**

テーブルヘッダーの「MFA状態/変更」列にヘルプボタンを追加:

```typescript
<th className="text-left py-3 px-4 text-gray-400 font-medium">
  <div className="flex items-center gap-2">
    MFA状態/変更
    <div className="relative group/help">
      <button
        type="button"
        className="w-4 h-4 rounded-full bg-gray-700/50 hover:bg-gray-600/70 text-gray-300 flex items-center justify-center text-xs font-bold transition-colors"
        title="MFAについて"
      >
        ?
      </button>
      {/* ツールチップ */}
      <div className="absolute left-0 top-full mt-2 w-80 bg-gray-900 border border-gray-700 rounded-lg p-4 shadow-xl opacity-0 invisible group-hover/help:opacity-100 group-hover/help:visible transition-all duration-200 z-50">
        <div className="flex items-start gap-2">
          <svg className="w-5 h-5 text-blue-400 flex-shrink-0 mt-0.5" fill="none" viewBox="0 0 24 24" stroke="currentColor">
            <path strokeLinecap="round" strokeLinejoin="round" strokeWidth={2} d="M13 16h-1v-4h-1m1-4h.01M21 12a9 9 0 11-18 0 9 9 0 0118 0z" />
          </svg>
          <div>
            <p className="text-sm font-semibold text-white mb-2">MFA（多要素認証）とは</p>
            <p className="text-sm text-gray-300 leading-relaxed mb-3">
              MFA（Multi-Factor Authentication）は、パスワードに加えて、スマートフォンアプリで生成される6桁の認証コードを使用する2段階認証です。
            </p>
            <ul className="text-sm text-gray-300 space-y-1 list-disc list-inside">
              <li>セキュリティが大幅に向上します</li>
              <li>Google Authenticatorなどのアプリが必要です</li>
              <li>ログイン時に追加の認証コード入力が必要になります</li>
            </ul>
          </div>
        </div>
      </div>
    </div>
  </div>
</th>
```

**参考箇所**: 同じファイル内の `k_front/components/protected/admin/AdminMenu.tsx:684-709` に既存のヘルプツールチップの実装例があります（QRコード紛失時のヘルプ）。

**実装のポイント**:
- `group/help` モディファイアを使用して、他のホバー効果と競合しないようにする
- ツールチップの z-index を高めに設定（z-50）してテーブルの上に表示
- `opacity-0 invisible` から `group-hover/help:opacity-100 group-hover/help:visible` で滑らかに表示

---

## 4. 【Backend】エラーハンドリング 変数マッピング

### 現在の問題
利用者作成(編集)の際、`firstNameFurigana` や `relationship` など変数名が日本語になっておらずエラーがわかりにくくなっている。

### 原因箇所
- **バックエンド:** `k_back/app/schemas/welfare_recipient.py:21-25`
  - `alias="firstNameFurigana"` などは正しく設定されている
  - しかし、バリデーションエラーが発生した際、フィールド名がそのまま返される可能性がある

- **フロントエンド:** `k_front/lib/welfare-recipients.ts:22-27`
  - エラーメッセージをそのまま表示している

### 改善方法

**フロントエンドでエラーメッセージを日本語にマッピング:**

`k_front/lib/welfare-recipients.ts` または `k_front/components/protected/recipients/RecipientRegistrationForm.tsx` に以下の辞書を追加:

```typescript
const ERROR_FIELD_MAPPING: Record<string, string> = {
  'firstNameFurigana': '名（ふりがな）',
  'lastNameFurigana': '姓（ふりがな）',
  'firstName': '名',
  'lastName': '姓',
  'relationship': '続柄',
  'birthDay': '生年月日',
  'gender': '性別',
  'address': '住所',
  'tel': '電話番号',
  'disabilityOrDiseaseName': '障害または疾患名',
  'livelihoodProtection': '生活保護受給状況',
  'formOfResidence': '居住形態',
  'meansOfTransportation': '交通手段',
  // ... 他のフィールドも追加
};

function translateErrorMessage(error: string): string {
  for (const [key, value] of Object.entries(ERROR_FIELD_MAPPING)) {
    error = error.replace(new RegExp(key, 'g'), value);
  }
  return error;
}
```

エラーハンドリング箇所で使用:
```typescript
catch (error) {
  const message = translateErrorMessage(error.message);
  setErrors({ submit: message });
}
```

---

## 5. 【UI】利用者入力, 編集　必須マークが噛み合っていない

### 現在の問題
本来、利用者作成(編集)では手帳・年金詳細情報が必須だが、UI上に必須マークが付いていないためわかりにくい。

### 原因箇所
- `k_front/components/protected/recipients/RecipientRegistrationForm.tsx:900-1002`
- セクション4「手帳・年金詳細情報」のフィールドに必須マーク `<span className="text-red-400">*</span>` がない

**現在の実装:**
```typescript
<label className="block text-sm font-medium text-gray-300 mb-2">カテゴリ</label>
<label className="block text-sm font-medium text-gray-300 mb-2">等級・レベル</label>
<label className="block text-sm font-medium text-gray-300 mb-2">申請状況</label>
```

### 改善方法

**必須フィールドに必須マークを追加:**

```typescript
<label className="block text-sm font-medium text-gray-300 mb-2">
  カテゴリ <span className="text-red-400">*</span>
</label>

<label className="block text-sm font-medium text-gray-300 mb-2">
  申請状況 <span className="text-red-400">*</span>
</label>
```

**注意:** 等級・レベルはカテゴリによってオプショナルの場合があるため、必須マークの追加は慎重に判断する。

---

## 6. 利用者ダッシュボード　ソート順

### 現在の問題
デフォルトのソート順を期限の短い順にする（残りの更新期限）

### 原因箇所
- `k_front/components/protected/dashboard/Dashboard.tsx:28-29`

**現在の実装:**
```typescript
const [sortOrder, setSortOrder] = useState<'asc' | 'desc'>('asc');
const [sortBy, setSortBy] = useState('name_phonetic');
```

デフォルトのソートが名前（ふりがな順）になっている。

### 改善方法

**デフォルトソートを更新期限の短い順に変更:**

```typescript
const [sortOrder, setSortOrder] = useState<'asc' | 'desc'>('asc');
const [sortBy, setSortBy] = useState('next_renewal_deadline');
```

これにより、ダッシュボード初期表示時に更新期限が近い利用者から順に表示される。

### バックエンド対応

**変更箇所1:** `k_back/app/api/v1/endpoints/dashboard.py:18`
- デフォルトの `sort_by` パラメータを `'name_phonetic'` から `'next_renewal_deadline'` に変更

**変更箇所2:** `k_back/app/crud/crud_dashboard.py:156`
- 更新期限でソートする際の NULL 値の扱いを `nullsfirst()` から `nullslast()` に変更
- これにより、昇順ソート時に期限がある利用者が優先表示され、期限がない利用者は最後に表示される

```python
elif sort_by == "next_renewal_deadline":
    sort_column = SupportPlanCycle.next_renewal_deadline
    # 昇順の場合も nullslast() を使用して、期限がある利用者を優先表示
    order_func = sort_column.desc().nullslast() if sort_order == "desc" else sort_column.asc().nullslast()
```

### テスト検証

**実行日時:** 2025-12-09

**結果:** 全テスト成功（テスト修正不要）

1. **CRUD層テスト** - `tests/crud/test_crud_dashboard_summary.py`
   - 全15テスト成功
   - 特に `test_sort_by_next_renewal_deadline_asc` が正常に動作
   - 期限切れ → 更新間近 → 通常 の順で正しくソートされることを確認

2. **API層テスト** - `tests/api/v1/test_dashboard.py`
   - 全4テスト成功
   - ダッシュボードエンドポイントが正常に動作

**理由:** `sort_by="next_renewal_deadline"` の場合、INNER JOIN が使用されるため（`crud_dashboard.py:102-103`）、サイクルがない利用者は自動的に除外される。そのため `nullslast()` の変更は既存のテストに影響しない。

---

**調査日時:** 2025-12-09


## 8. GoogleCalendar連携 -> Youtube動画
管理者メニュー > G連携 > 使い方のリンクを以下に置き換える
https://www.youtube.com/watch?v=xAXWnT_kP2g