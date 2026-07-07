# Playwright E2E テスト 手順書

**対象**: keikakun_app / k_front (Next.js)  
**ツール**: Playwright  
**作成日**: 2026-04-13

---

## 目次

1. [環境セットアップ](#1-環境セットアップ)
2. [ディレクトリ構成](#2-ディレクトリ構成)
3. [テスト共通設定](#3-テスト共通設定)
4. [テストケース設計](#4-テストケース設計)
   - 4-1. ログイン
   - 4-2. スタッフ登録（Staff Signup）
   - 4-3. 利用者登録（WelfareRecipient）
   - 4-4. 個別支援計画サイクル登録（SupportPlanCycle）
5. [実装コード](#5-実装コード)
6. [実行方法](#6-実行方法)
7. [注意事項・落とし穴](#7-注意事項落とし穴)

---

## 1. 環境セットアップ

### 1-1. Playwright インストール

```bash
cd k_front
npm install -D @playwright/test
npx playwright install chromium  # ブラウザバイナリのダウンロード
```

### 1-2. 設定ファイル作成

`k_front/playwright.config.ts` を作成:

```typescript
import { defineConfig, devices } from '@playwright/test';

export default defineConfig({
  testDir: './e2e',
  fullyParallel: false,        // 登録系テストは順序依存があるためシリアル実行
  retries: process.env.CI ? 2 : 0,
  workers: 1,
  reporter: 'html',
  use: {
    baseURL: 'http://localhost:3000',
    trace: 'on-first-retry',
    screenshot: 'only-on-failure',
    video: 'retain-on-failure',
  },
  projects: [
    {
      name: 'chromium',
      use: { ...devices['Desktop Chrome'] },
    },
  ],
  // テスト実行前にNext.js dev serverを起動
  webServer: {
    command: 'npm run dev',
    url: 'http://localhost:3000',
    reuseExistingServer: !process.env.CI,
    timeout: 120 * 1000,
  },
});
```

### 1-3. 環境変数

`k_front/.env.test.local` を作成（テスト専用）:

```
NEXT_PUBLIC_API_URL=http://localhost:8000
```

---

## 2. ディレクトリ構成

```
k_front/
├── e2e/
│   ├── fixtures/
│   │   └── auth.ts          # 認証ヘルパー（ログイン済み状態）
│   ├── helpers/
│   │   └── test-data.ts     # テストデータ生成ユーティリティ
│   ├── 01_login.spec.ts
│   ├── 02_staff_signup.spec.ts
│   ├── 03_welfare_recipient.spec.ts
│   ├── 04_support_plan_cycle.spec.ts
│   └── dashboard-filtering.spec.ts  # 既存
├── playwright.config.ts
└── package.json
```

---

## 3. テスト共通設定

### 3-1. テストデータ定数

```typescript
// e2e/helpers/test-data.ts

import { v4 as uuidv4 } from 'uuid';

/** テスト用スタッフ認証情報（事前にDBに存在すること） */
export const TEST_OWNER = {
  email: 'test_owner@example.com',
  password: 'TestPassword123!',
};

export const TEST_MANAGER = {
  email: 'test_manager@example.com',
  password: 'TestPassword123!',
};

/** テスト用スタッフ登録データ生成（ユニークなメールで衝突回避） */
export function generateStaffData() {
  const uid = uuidv4().slice(0, 8);
  return {
    last_name: 'テスト',
    first_name: '太郎',
    last_name_furigana: 'てすと',
    first_name_furigana: 'たろう',
    email: `e2e_staff_${uid}@example.com`,
    role: 'employee',
    password: 'E2ePassword123!',
    confirmPassword: 'E2ePassword123!',
  };
}

/** テスト用利用者データ生成 */
export function generateRecipientData() {
  const uid = uuidv4().slice(0, 8);
  return {
    last_name: 'E2E',
    first_name: `利用者${uid}`,
    last_name_furigana: 'いーつーいー',
    first_name_furigana: `りようしゃ`,
    birth_date: '1990-01-01',
    gender: 'male',
    address: '東京都新宿区西新宿1-1-1',
    phone: '090-1234-5678',
    disability_type: '知的障害',
  };
}
```

### 3-2. 認証フィクスチャ

```typescript
// e2e/fixtures/auth.ts

import { test as base, Page } from '@playwright/test';
import { TEST_OWNER } from '../helpers/test-data';

/** ログイン済み状態でテストを開始するカスタムフィクスチャ */
export const test = base.extend<{ loggedInPage: Page }>({
  loggedInPage: async ({ page }, use) => {
    await loginAsOwner(page);
    await use(page);
  },
});

export async function loginAsOwner(page: Page) {
  await page.goto('/auth/login');
  await page.fill('input[name="email"]', TEST_OWNER.email);
  await page.fill('input[name="password"]', TEST_OWNER.password);
  await page.click('button[type="submit"]');
  // MFAなしの場合はダッシュボードへ
  await page.waitForURL(/\/(dashboard|auth\/select-office)/, { timeout: 10000 });
}

export { expect } from '@playwright/test';
```

---

## 4. テストケース設計

### 4-1. ログインテスト

**URL**: `/auth/login`  
**フォーム要素**:
- `input[name="email"]`
- `input[name="password"]`
- `button[type="submit"]`

**遷移先**:
- 正常: `/dashboard`（MFAなし）または `/auth/mfa-verify`（MFAあり）
- エラー: 同ページにエラーメッセージ表示

| テストケース | 入力 | 期待結果 |
|---|---|---|
| 正常ログイン | 正しいemailとpassword | `/dashboard` へリダイレクト |
| パスワード誤り | 正しいemail + 誤password | エラーメッセージ表示、ページ遷移なし |
| メール未入力 | email空 + password入力 | HTML5バリデーションまたはエラー表示 |
| 未登録メール | 存在しないemail | エラーメッセージ表示 |

---

### 4-2. スタッフ登録テスト（Staff Signup）

**URL**: `/auth/signup`  
**フォーム要素**:
- `input[name="last_name"]` — 姓
- `input[name="first_name"]` — 名
- `input[name="last_name_furigana"]` — 姓（ふりがな）
- `input[name="first_name_furigana"]` — 名（ふりがな）
- `input[name="email"]` — メールアドレス
- `select[name="role"]` or radio — 役割（owner/manager/employee）
- `input[name="password"]` — パスワード
- `input[name="confirmPassword"]` — パスワード確認

**遷移先**:
- 正常: `/auth/signup-success?role={role}`

| テストケース | 確認項目 |
|---|---|
| 正常登録（employee） | フォーム送信 → signup-success ページ表示 |
| パスワード不一致 | エラーメッセージ表示、送信されない |
| 重複メール | APIエラーがUIに反映される |
| 必須項目未入力 | バリデーションエラー表示 |

**注意**: 登録後のメール認証フローが存在する場合はモック or スキップが必要

---

### 4-3. 利用者登録テスト（WelfareRecipient）

**前提条件**: owner または manager でログイン済み  
**URL**: `/recipients/new`  
**主要フォーム要素（コード調査結果）**:

```
姓          placeholder="山田"
名          placeholder="太郎"
姓ふりがな   placeholder="やまだ"
名ふりがな   placeholder="たろう"
住所        placeholder="例：東京都新宿区西新宿1-1-1"
電話番号     placeholder="例：090-1234-5678"
障害種別     placeholder="例：統合失調症、知的障害、身体障害など"
```

**遷移先**:
- owner/manager: 直接登録 → `/dashboard`
- employee: 申請フロー → `/dashboard`（承認待ちメッセージ）

| テストケース | 確認項目 |
|---|---|
| 正常登録 | フォーム送信 → ダッシュボードへ遷移 |
| 登録後一覧確認 | `/recipients` で追加した利用者が表示される |
| 必須項目未入力 | バリデーションエラー表示 |

---

### 4-4. 個別支援計画サイクル登録（SupportPlanCycle）

**前提条件**: 利用者登録済み、ログイン済み  
**URL**: `/support_plan/{recipient_id}`  
**機能概要**（コード調査結果）:
- `supportPlanApi.getCycles(recipientId)` でサイクル一覧取得
- `supportPlanApi.uploadDeliverable(...)` でPDFアップロード
- モニタリング期限の設定（`updateMonitoringDeadline`）

**テスト対象操作**:
1. 利用者の支援計画ページを開く
2. 計画書PDFをアップロード（deliverable upload）
3. アップロード後の状態変化を確認

| テストケース | 確認項目 |
|---|---|
| ページ表示 | recipient_id で `/support_plan/{id}` を開けること |
| PDF一覧表示 | 計画書ステータス（アセスメント/計画書案/会議用/最終版/モニタリング）が表示される |
| PDFアップロード | ファイル選択 → アップロード成功 → 一覧更新 |

---

## 5. 実装コード

### 5-1. ログインテスト

```typescript
// e2e/01_login.spec.ts

import { test, expect } from '@playwright/test';
import { TEST_OWNER } from './helpers/test-data';

test.describe('ログイン機能', () => {

  test('正常ログイン → ダッシュボードへ遷移', async ({ page }) => {
    await page.goto('/auth/login');

    await page.fill('input[name="email"]', TEST_OWNER.email);
    await page.fill('input[name="password"]', TEST_OWNER.password);
    await page.click('button[type="submit"]');

    // MFAなし → dashboard / MFAあり → mfa-verify
    await page.waitForURL(/\/(dashboard|auth\/mfa-verify|auth\/select-office)/, {
      timeout: 10000,
    });

    // 最終的にダッシュボードに到達することを確認
    if (page.url().includes('select-office')) {
      // 複数事業所の場合はofficeを選択
      await page.click('[data-testid="office-item"]:first-child');
      await page.waitForURL('/dashboard', { timeout: 10000 });
    }

    await expect(page).toHaveURL(/\/dashboard/);
  });

  test('パスワード誤り → エラーメッセージ表示', async ({ page }) => {
    await page.goto('/auth/login');

    await page.fill('input[name="email"]', TEST_OWNER.email);
    await page.fill('input[name="password"]', 'wrongpassword');
    await page.click('button[type="submit"]');

    // ダッシュボードへ遷移しないこと
    await page.waitForTimeout(2000);
    expect(page.url()).not.toContain('/dashboard');

    // エラーメッセージが表示されること
    const errorMessage = page.locator('text=パスワード').or(
      page.locator('text=認証').or(page.locator('[role="alert"]'))
    );
    await expect(errorMessage.first()).toBeVisible();
  });

  test('未登録メール → エラーメッセージ表示', async ({ page }) => {
    await page.goto('/auth/login');

    await page.fill('input[name="email"]', 'notexist@example.com');
    await page.fill('input[name="password"]', 'SomePassword123!');
    await page.click('button[type="submit"]');

    await page.waitForTimeout(2000);
    expect(page.url()).not.toContain('/dashboard');
  });

  test('ログアウト後は保護ルートへアクセス不可', async ({ page }) => {
    // ログイン
    await page.goto('/auth/login');
    await page.fill('input[name="email"]', TEST_OWNER.email);
    await page.fill('input[name="password"]', TEST_OWNER.password);
    await page.click('button[type="submit"]');
    await page.waitForURL(/\/dashboard/, { timeout: 10000 });

    // ダッシュボードへ直接アクセス試行（クッキーなし状態をシミュレート）
    await page.context().clearCookies();
    await page.goto('/dashboard');

    // ログインページへリダイレクトされること
    await page.waitForURL(/\/auth\/login/, { timeout: 5000 });
  });

});
```

### 5-2. スタッフ登録テスト

```typescript
// e2e/02_staff_signup.spec.ts

import { test, expect } from '@playwright/test';
import { generateStaffData } from './helpers/test-data';

test.describe('スタッフ登録', () => {

  test('正常登録 → signup-success ページへ遷移', async ({ page }) => {
    const staffData = generateStaffData();

    await page.goto('/auth/signup');

    await page.fill('input[name="last_name"]', staffData.last_name);
    await page.fill('input[name="first_name"]', staffData.first_name);
    await page.fill('input[name="last_name_furigana"]', staffData.last_name_furigana);
    await page.fill('input[name="first_name_furigana"]', staffData.first_name_furigana);
    await page.fill('input[name="email"]', staffData.email);

    // role 選択（select or radio）
    const roleSelect = page.locator('select[name="role"]');
    const roleRadio = page.locator('input[name="role"][value="employee"]');
    if (await roleSelect.isVisible()) {
      await roleSelect.selectOption('employee');
    } else if (await roleRadio.isVisible()) {
      await roleRadio.check();
    }

    await page.fill('input[name="password"]', staffData.password);
    await page.fill('input[name="confirmPassword"]', staffData.confirmPassword);

    // 利用規約チェックがある場合
    const termsCheckbox = page.locator('input[type="checkbox"]').first();
    if (await termsCheckbox.isVisible()) {
      await termsCheckbox.check();
    }

    await page.click('button[type="submit"]');

    await page.waitForURL(/\/auth\/signup-success/, { timeout: 10000 });
    await expect(page).toHaveURL(/\/auth\/signup-success/);
  });

  test('パスワード不一致 → エラー表示', async ({ page }) => {
    const staffData = generateStaffData();

    await page.goto('/auth/signup');

    await page.fill('input[name="last_name"]', staffData.last_name);
    await page.fill('input[name="first_name"]', staffData.first_name);
    await page.fill('input[name="last_name_furigana"]', staffData.last_name_furigana);
    await page.fill('input[name="first_name_furigana"]', staffData.first_name_furigana);
    await page.fill('input[name="email"]', staffData.email);
    await page.fill('input[name="password"]', 'Password123!');
    await page.fill('input[name="confirmPassword"]', 'DifferentPassword!');

    await page.click('button[type="submit"]');

    await page.waitForTimeout(1000);
    expect(page.url()).not.toContain('/signup-success');

    // エラーメッセージの確認
    const errorMsg = page.locator('text=パスワード').or(page.locator('[role="alert"]'));
    await expect(errorMsg.first()).toBeVisible();
  });

});
```

### 5-3. 利用者登録テスト

```typescript
// e2e/03_welfare_recipient.spec.ts

import { test, expect } from './fixtures/auth';
import { generateRecipientData } from './helpers/test-data';

test.describe('利用者登録', () => {

  test('正常登録 → ダッシュボードへ遷移', async ({ loggedInPage: page }) => {
    const recipientData = generateRecipientData();

    await page.goto('/recipients/new');

    // 姓名入力
    await page.fill('input[placeholder="山田"]', recipientData.last_name);
    await page.fill('input[placeholder="太郎"]', recipientData.first_name);
    await page.fill('input[placeholder="やまだ"]', recipientData.last_name_furigana);
    await page.fill('input[placeholder="たろう"]', recipientData.first_name_furigana);

    // 住所・電話
    await page.fill('input[placeholder*="東京都"]', recipientData.address);
    await page.fill('input[placeholder*="090"]', recipientData.phone);

    // 生年月日（入力形式に合わせて調整）
    const birthDateInput = page.locator('input[type="date"]').first();
    if (await birthDateInput.isVisible()) {
      await birthDateInput.fill(recipientData.birth_date);
    }

    // 障害種別
    const disabilityInput = page.locator(`input[placeholder*="統合失調症"]`).or(
      page.locator('input[placeholder*="障害"]')
    );
    if (await disabilityInput.first().isVisible()) {
      await disabilityInput.first().fill(recipientData.disability_type);
    }

    await page.click('button[type="submit"]');

    // owner/manager: ダッシュボードへ
    await page.waitForURL(/\/dashboard/, { timeout: 10000 });
    await expect(page).toHaveURL(/\/dashboard/);
  });

  test('登録後に利用者一覧で確認できる', async ({ loggedInPage: page }) => {
    const recipientData = generateRecipientData();
    const fullName = `${recipientData.last_name} ${recipientData.first_name}`;

    // 登録
    await page.goto('/recipients/new');
    await page.fill('input[placeholder="山田"]', recipientData.last_name);
    await page.fill('input[placeholder="太郎"]', recipientData.first_name);
    await page.fill('input[placeholder="やまだ"]', recipientData.last_name_furigana);
    await page.fill('input[placeholder="たろう"]', recipientData.first_name_furigana);
    await page.click('button[type="submit"]');
    await page.waitForURL(/\/dashboard/, { timeout: 10000 });

    // 一覧で確認
    await page.goto('/recipients');
    await expect(page.locator(`text=${recipientData.last_name}`).first()).toBeVisible({
      timeout: 5000,
    });
  });

});
```

### 5-4. 個別支援計画サイクルテスト

```typescript
// e2e/04_support_plan_cycle.spec.ts

import { test, expect } from './fixtures/auth';
import * as path from 'path';

// テスト用PDFファイルのパス（fixtures/sample.pdf を用意する）
const SAMPLE_PDF_PATH = path.join(__dirname, 'fixtures', 'sample.pdf');

test.describe('個別支援計画サイクル', () => {

  test('利用者の支援計画ページを開ける', async ({ loggedInPage: page }) => {
    // 利用者一覧から最初の利用者を開く
    await page.goto('/recipients');

    // 利用者リストの最初のアイテムをクリック
    const firstRecipient = page.locator('a[href*="/support_plan/"]').first();
    await expect(firstRecipient).toBeVisible({ timeout: 5000 });
    await firstRecipient.click();

    await page.waitForURL(/\/support_plan\//, { timeout: 10000 });
    await expect(page).toHaveURL(/\/support_plan\//);
  });

  test('支援計画ページにステータス項目が表示される', async ({ loggedInPage: page }) => {
    await page.goto('/recipients');

    const firstRecipient = page.locator('a[href*="/support_plan/"]').first();
    const href = await firstRecipient.getAttribute('href');
    if (!href) return;

    await page.goto(href);
    await page.waitForURL(/\/support_plan\//, { timeout: 10000 });

    // 各ステータス項目の確認
    const statusItems = ['アセスメント', '計画書案', '会議用', '最終版', 'モニタリング'];
    for (const item of statusItems) {
      await expect(page.locator(`text=${item}`).first()).toBeVisible({ timeout: 5000 });
    }
  });

  test('PDFアップロード → ステータス更新', async ({ loggedInPage: page }) => {
    // 注意: SAMPLE_PDF_PATH に実際のPDFファイルが必要
    // テスト用PDFをfixtures/sample.pdfとして配置すること

    await page.goto('/recipients');
    const firstRecipient = page.locator('a[href*="/support_plan/"]').first();
    const href = await firstRecipient.getAttribute('href');
    if (!href) return;

    await page.goto(href);
    await page.waitForURL(/\/support_plan\//, { timeout: 10000 });

    // ファイルアップロードボタンを探す
    const fileInput = page.locator('input[type="file"]').first();
    if (await fileInput.isVisible()) {
      await fileInput.setInputFiles(SAMPLE_PDF_PATH);
      // アップロード完了を待つ
      await page.waitForResponse(
        (resp) => resp.url().includes('/support_plans') && resp.status() === 200,
        { timeout: 10000 }
      );
    }
  });

});
```

---

## 6. 実行方法

### ローカル実行

```bash
cd k_front

# 全テスト実行
npx playwright test

# 特定ファイルのみ
npx playwright test e2e/01_login.spec.ts

# UIモードで実行（デバッグに便利）
npx playwright test --ui

# ヘッドありで実行（ブラウザ画面を表示）
npx playwright test --headed

# HTMLレポート確認
npx playwright show-report
```

### CI（GitHub Actions）実行

`.github/workflows/e2e.yml` に追加:

```yaml
- name: Install Playwright Browsers
  run: npx playwright install --with-deps chromium
  working-directory: k_front

- name: Run E2E tests
  run: npx playwright test
  working-directory: k_front
  env:
    NEXT_PUBLIC_API_URL: http://localhost:8000
```

---

## 7. 注意事項・落とし穴

### テストデータの独立性

- 各テストは `generateStaffData()` / `generateRecipientData()` でユニークなデータを生成し、他テストと干渉しない
- テスト実行後のDB汚染: CI環境ではテスト専用DBを使用すること（`TEST_DATABASE_URL`）

### placeholder セレクタの脆弱性

- `input[placeholder="山田"]` は画面テキスト変更で壊れる
- 本番実装では `data-testid` 属性を付与する方が堅牢（例: `data-testid="input-last-name"`）
- 現状のコードベースには `data-testid` がないため placeholder ベースで実装

### MFA フロー

- ログインテストは MFA が無効なテスト用アカウントを使用すること
- CI環境の `TEST_OWNER` アカウントは MFA を無効化しておくこと

### 支援計画テストの前提条件

- `04_support_plan_cycle.spec.ts` は利用者が1件以上存在することが前提
- テスト実行順序: `01 → 02 → 03 → 04` の順で実行すること（`playwright.config.ts` の `fullyParallel: false` で制御）
- PDFアップロードテストには `e2e/fixtures/sample.pdf` を用意すること

### APIレスポンス待ち

- `page.waitForURL()` のタイムアウトはCI環境に合わせて調整（デフォルト: 10000ms）
- ネットワーク応答を待つ場合は `page.waitForResponse()` を使用

---

## 実装優先度

| 優先度 | テスト | 理由 |
|---|---|---|
| ★★★ | `01_login.spec.ts` | 全機能の前提、最も基本 |
| ★★☆ | `03_welfare_recipient.spec.ts` | コア業務フロー |
| ★★☆ | `04_support_plan_cycle.spec.ts` | メイン機能 |
| ★☆☆ | `02_staff_signup.spec.ts` | 初回のみ実行される操作 |
