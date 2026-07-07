# E2E テスト — セキュリティ・リファクタリング分析

**対象**: `k_front/e2e/`  
**ツール**: Playwright  
**作成日**: 2026-04-13  
**最終更新**: 2026-04-14（全テストパス後の再分析）

---

## 修正済み（前セッションで対応）

| 項目 | 内容 |
|------|------|
| ログイン率制限 (5/min) | `auth.setup.ts` + `storageState` でテスト全体で1回のみログイン |
| `browser.newContext()` の baseURL 継承不備 | `loggedInPage` フィクスチャを標準 `page` 委譲に変更 |
| `dashboard-filtering.spec.ts` の 404 | ログイン URL `/login` → `/auth/login` 修正済み |
| 支援計画リンクが `/recipients` に存在しない | `gotoFirstSupportPlan` でバックエンド API から ID 取得する方式に変更 |
| 利用規約チェックボックス直接操作エラー | `agreeViaModal()` ヘルパーでモーダル経由の同意フローを実装 |
| `02_staff_signup.spec.ts` での owner セッション干渉 | `test.use({ storageState: undefined })` を追加 |

---

## セキュリティリスク

### S-1: 平文パスワードがソースコードにハードコード【高・対応済み予定】

**ファイル**: `e2e/helpers/test-data.ts:10-11`

```typescript
// TEST_OWNER: フォールバック値として平文パスワード
password: process.env.E2E_OWNER_PASSWORD || 'E2ePass123!',

// generateStaffData: 環境変数なしで常に平文
password: 'E2ePassword123!',
```

**リスク**:
- 環境変数未設定のままリポジトリが公開されると認証情報が漏洩
- CI で `E2E_OWNER_PASSWORD` の設定漏れに気づけない（フォールバックでテストが通り続ける）
- `generateStaffData()` のパスワードはフォールバック機構すらなく常に平文でコミット済み

**修正方針**:
```typescript
function requireEnv(key: string): string {
  const val = process.env[key];
  if (!val) throw new Error(`環境変数 ${key} が未設定です (E2Eテスト実行前に .env.local に設定してください)`);
  return val;
}

export const TEST_OWNER = {
  email: requireEnv('E2E_OWNER_EMAIL'),
  password: requireEnv('E2E_OWNER_PASSWORD'),
};

// generateStaffData はパスワードを外部から受け取るか、同様に env 参照にする
```

---

### S-2: テストデータが蓄積し続ける（クリーンアップなし）【中・対応済み予定】

**ファイル**: `02_staff_signup.spec.ts`、`03_welfare_recipient.spec.ts`

**リスク**:
- `e2e_staff_<timestamp>@example.com` アカウントと姓 `E2E` の利用者が毎テスト実行ごとに蓄積
- CI が1日10回実行されると月に数百件のダミーデータが残る
- DB 容量圧迫、staging 環境で本番データと混在

**修正方針**:
```typescript
// afterAll でバックエンド API を叩いてクリーンアップ
test.afterAll(async ({ request }) => {
  // 作成したスタッフを削除（or 無効化）
  await request.delete(`${API_BASE_URL}/api/v1/staffs/${createdStaffId}`);
});
```

---

### S-3: `gotoFirstSupportPlan` が E2E 外の利用者を掴む可能性【中・対応済み予定】

**ファイル**: `04_support_plan_cycle.spec.ts:51`

```typescript
const recipientId = recipients[0].id;  // 一覧の先頭 = E2E作成分とは限らない
```

**リスク**:
- staging 環境に実データが存在する場合、実利用者の ID がテストログに記録される
- テストの意図（E2E が作成したデータを使う）が保証されない

**修正方針**:
```typescript
// E2E が作成した利用者に限定
const e2eRecipient = recipients.find(
  (r: { last_name: string }) => r.last_name === 'E2E'
);
if (!e2eRecipient) throw new Error('E2E利用者が見つかりません。03_welfare_recipient.spec.ts を先に実行してください。');
const recipientId = e2eRecipient.id;
```

---

### S-4: CI の GitHub Actions 例に secrets 設定が記載されていない【低】

**ファイル**: `e2e/README.md:175-206`

README の GitHub Actions サンプルに `E2E_OWNER_EMAIL` / `E2E_OWNER_PASSWORD` の
`env:` ブロックが存在しない。そのまま利用すると S-1 のフォールバック値で CI が動作する。

---

## リファクタリング

### R-1: `waitForTimeout` アンチパターン（5箇所）【中・対応済み予定】

**ファイル**: `dashboard-filtering.spec.ts:79, 105, 120, 135`

```typescript
await page.waitForTimeout(500); // デバウンス待ち
```

固定時間待機はCI環境の速度差でフレーキーになる。デバウンス後のネットワークレスポンスを
待つか、フィルター適用結果の DOM 変化を待機すべき。

**修正方針**:
```typescript
// フィルター適用後の Active Filters チップ出現を待機（確実に状態変化を検知）
await page.click('[title="計画期限切れでフィルター"]');
await expect(page.locator('text=絞り込み中:').first()).toBeVisible();
// waitForTimeout(500) を削除
```

---

### R-2: 利用者登録フォーム（5セクション）のコードが2テストに完全重複【高・対応済み予定】

**ファイル**: `03_welfare_recipient.spec.ts`

テスト1「5セクション完走」とテスト3「登録後一覧で確認」が同一のフォーム入力コード
約45行を丸ごと重複している。

**修正方針**:
```typescript
// e2e/helpers/recipient-form.ts に抽出
export async function fillAndSubmitRecipientForm(
  page: Page,
  data: ReturnType<typeof generateRecipientData>
): Promise<void> {
  // Section 0〜4 の入力 + 登録完了クリック + URL待機
}
```

---

### R-3: `loggedInPage` フィクスチャが標準 `page` の別名になっている【低】

**ファイル**: `fixtures/auth.ts:27-33`

```typescript
loggedInPage: async ({ page }, use) => {
  await use(page); // storageState は playwright.config.ts が自動適用するため何もしていない
},
```

storageState 実装後、このフィクスチャの存在意義がなくなった。
`03_welfare_recipient.spec.ts` と `04_support_plan_cycle.spec.ts` が
`@playwright/test` を直接 import するよう変更すれば、`fixtures/auth.ts` ごと削除できる。

**移行後**:
```typescript
// Before
import { test, expect } from './fixtures/auth';
async ({ loggedInPage: page }) => { ... }

// After
import { test, expect } from '@playwright/test';
async ({ page }) => { ... }
```

---

### R-4: プレースホルダー文字列セレクタが脆弱【中・対応済み予定】

**ファイル**: `03_welfare_recipient.spec.ts:31-34` など多数

```typescript
await page.fill('input[placeholder="山田"]', recipient.last_name);
await page.fill('input[placeholder="太郎"]', recipient.first_name);
```

UI のコピーライト変更（`"山田"` → `"例: 山田"` 等）で即壊れる。
フォームの `name` 属性はすでに存在するため、セレクタを切り替えるだけで解決。

**修正方針**:
```typescript
await page.fill('input[name="last_name"]', recipient.last_name);
await page.fill('input[name="first_name"]', recipient.first_name);
await page.fill('input[name="last_name_furigana"]', recipient.last_name_furigana);
await page.fill('input[name="first_name_furigana"]', recipient.first_name_furigana);
```

---

### R-5: `API_BASE_URL` がテストファイルに直接定義されている【低】

**ファイル**: `04_support_plan_cycle.spec.ts:25`

```typescript
const API_BASE_URL = (process.env.NEXT_PUBLIC_API_URL || 'http://localhost:8000').replace(/\/$/, '');
```

`lib/http.ts`、`lib/auth.ts` でも同一パターンが存在し、3箇所に分散。
E2E テスト内では `helpers/test-data.ts` に共通定数として抽出すべき。

---

### R-6: `test.skip()` のテスト本体内呼び出し【低】

**ファイル**: `04_support_plan_cycle.spec.ts:81, 88`

```typescript
test('PDFアップロード...', async ({ loggedInPage: page }) => {
  test.skip(!fs.existsSync(SAMPLE_PDF), '...');  // 本体内でスキップ判定
  // ↑ テストが開始してからスキップするため、レポートが不明瞭になる
```

`test.skip()` 引数形式（テスト本体外）で書くと、レポート上で明確に「スキップ済み」と表示される。

---

### R-7: README が現状の実装と乖離【低】

**ファイル**: `e2e/README.md`

- `playwright.config.ts` のサンプルが旧版（`setup` プロジェクト・`storageState` 未記載）
- `auth.setup.ts`、`.auth/owner.json`、`storageState` の説明がない
- CI サンプルに `E2E_OWNER_EMAIL` / `E2E_OWNER_PASSWORD` の `secrets:` 設定がない
- 実在しない `scripts/seed_test_data.py` への参照

---

## 優先度・対応状況まとめ

| ID | 分類 | 優先度 | 対応状況 | 概要 |
|----|------|--------|----------|------|
| S-1 | セキュリティ | 🔴 高 | 要対応 | 平文パスワードのハードコード削除 |
| S-2 | セキュリティ | 🟡 中 | 要対応 | テストデータの afterAll クリーンアップ |
| S-3 | セキュリティ | 🟡 中 | 要対応 | E2E 利用者への絞り込み |
| R-2 | リファクタリング | 🔴 高 | 要対応 | 利用者フォーム入力ヘルパーへの抽出 |
| R-1 | リファクタリング | 🟡 中 | 要対応 | `waitForTimeout` → DOM/ネットワーク待機 |
| R-4 | リファクタリング | 🟡 中 | 要対応 | `placeholder` セレクタ → `name` 属性 |
| S-4 | セキュリティ | 🟢 低 | README 更新で対応 | CI secrets 設定漏れ |
| R-3 | リファクタリング | 🟢 低 | 任意 | `loggedInPage` フィクスチャの削除 |
| R-5 | リファクタリング | 🟢 低 | 任意 | `API_BASE_URL` の定数化 |
| R-6 | リファクタリング | 🟢 低 | 任意 | `test.skip()` 引数形式への変更 |
| R-7 | リファクタリング | 🟢 低 | 要更新 | README を現状に合わせて更新 |

---

*最終更新: 2026-04-14*
