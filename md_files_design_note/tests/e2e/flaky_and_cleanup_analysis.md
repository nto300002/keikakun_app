# E2E テスト — 不安定性・クリーンアップ未実行の原因分析

**対象**: `k_front/e2e/`  
**作成日**: 2026-04-15  
**更新日**: 2026-04-15  
**背景**: 全テストパス後にも「結果が不安定」「テストデータが残る」の2問題が継続

---

## 問題の整理（最終状態）

| # | 問題 | 原因 | 影響 | 状態 |
|---|------|------|------|------|
| A | 04 が利用者0件で失敗 | 03 の afterAll が先に削除 | 04 全テスト FAIL | ✅ 解決済み |
| B | セレクタ位置依存 | nth()・last() セレクタ | 断続的 FAIL | ⚠️ 残存（低優先度） |
| C | セクション遷移後の描画待ちなし | 待機ロジック欠如 | 断続的 FAIL | ⚠️ 残存（低優先度） |
| D | waitForTimeout 残存（01・02） | 固定スリープ | CI で FAIL | ✅ 解決済み |
| E | 02 のスタッフデータ未削除 | afterAll なし + 認証制約 | データ蓄積 | ✅ 解決済み |
| F | 03 の削除が失敗しても気づかない | エラーハンドリングなし | データ蓄積 | ✅ 解決済み |
| G | afterAll タイミングと共有データの矛盾 | 設計の根本問題 | A を引き起こす | ✅ 解決済み |

---

## 解決済み問題の詳細

### A・G: 04 が利用者0件で失敗（afterAll → globalTeardown 移行）

**根本原因**: `afterAll` はファイルの全テスト完了後・次ファイル開始前に実行される。  
`03` の afterAll が走ると `04` に必要な利用者が消えてしまう。

```
旧実装:
  03 完了 → afterAll（E2E利用者を全削除） → 04 実行 → 利用者0件でFAIL

新実装:
  03 完了 → 04 完了 → globalTeardown（全テスト終了後に1回）→ 利用者削除
```

**実装**:
- `03_welfare_recipient.spec.ts`: afterAll を削除
- `e2e/global-teardown.ts`: `last_name === 'E2E'` の全利用者を削除
- `04_support_plan_cycle.spec.ts`: `beforeAll` でテスト用利用者を API 直接作成（自己完結型）

---

### E: E2E スタッフが削除されない

#### 旧実装の問題点（3層構造）

**問題 1: `afterAll` が存在しなかった**

`02_staff_signup.spec.ts` にクリーンアップフックが一切なかった。

**問題 2: スタッフが識別できない名前で登録されていた**

```typescript
// ❌ 旧実装: generateStaffData() の 'E2E' を使わず固定の '山田' で登録
await page.fill('input[name="last_name"]', '山田');
// → email の e2e_staff_* 以外に識別マーカーがなく、
//   一覧 API に出ないため削除対象を特定できない
```

`GET /api/v1/offices/me/staffs` は `JOIN OfficeStaff` で事業所に紐づくスタッフのみ返す。  
登録直後のスタッフは `office_associations = []`（未承認）のため**一覧に出てこない**。

**問題 3: `DELETE /api/v1/staffs/{id}` の同一事務所チェックで 403**

```python
# 旧実装: office_associations が空 → 空集合 → チェック通過不可
target_staff_office_ids = {assoc.office_id for assoc in target_staff.office_associations}
if current_user_office.id not in target_staff_office_ids:  # 空集合 → 常に True
    raise HTTPException(status_code=403, ...)
```

**問題 4: `DELETE /api/v1/e2e/staffs`（旧 globalTeardown）が CI で 403**

```python
# k_back/app/api/v1/endpoints/e2e_cleanup.py
if settings.ENVIRONMENT == "production":
    raise HTTPException(status_code=403, ...)
```

CI は本番環境（`api.keikakun.com`）に対して実行する。  
`ENVIRONMENT=production` → `e2e/staffs` エンドポイントが必ず 403 を返す。  
`global-teardown.ts` は警告して続行するため、**CI でスタッフが永遠に削除されない**状態だった。

#### 新実装

```
02_staff_signup.spec.ts:「正常登録」テスト
    ↓ POST /api/v1/auth/register のレスポンスをインターセプト → id を取得
    ↓ afterAll: owner 認証で DELETE /api/v1/staffs/{id}（production でも動作）

k_back/app/api/v1/endpoints/staffs.py:
    ↓ 事業所未所属スタッフ（office_associations=[]）は同一事務所チェックをスキップ
    ↓ どの事業所の owner も削除可能（未所属スタッフはデータにアクセスできないため安全）
```

---

### D: waitForTimeout 除去

```typescript
// ❌ 旧実装（02_staff_signup.spec.ts）
await page.waitForTimeout(1500);  // 固定スリープ

// ✅ 新実装
await expect(
  page.locator('.text-red-400').filter({ hasText: /パスワード/ }).first()
).toBeVisible({ timeout: 5000 });  // エラー要素の出現を待機
```

---

## クリーンアップの完全フロー（現行実装）

```
テスト実行順（fullyParallel: false, workers: 1）:

01_login.spec.ts          → 全テスト完了（テストデータ作成なし）
02_staff_signup.spec.ts   → 全テスト完了
  ↓ afterAll: DELETE /api/v1/staffs/{captured_id}  ← スタッフ削除
03_welfare_recipient.spec.ts → 全テスト完了（E2E利用者を作成）
04_support_plan_cycle.spec.ts
  ↓ beforeAll: POST /api/v1/welfare-recipients/ → recipient_id を取得
  → 全テスト完了
dashboard-filtering.spec.ts → 全テスト完了（テストデータ作成なし）
  ↓
globalTeardown（全ファイル完了後）
  → GET /api/v1/welfare-recipients/ → last_name='E2E' でフィルタ
  → Promise.allSettled で全件 DELETE  ← 利用者削除（03・04 分）
```

---

## クリーンアップ失敗時の対処

詳細は `k_front/e2e/README.md` の「クリーンアップ失敗時のフォールバック」を参照。

### 一時対応 SQL

```sql
-- E2E スタッフを論理削除
UPDATE staffs
SET is_deleted = true, deleted_at = now()
WHERE email LIKE 'e2e_staff_%@example.com'
  AND is_deleted = false;

-- E2E 利用者を物理削除
DELETE FROM welfare_recipients WHERE last_name = 'E2E';
```

### 失敗の検知

`globalTeardown` / `afterAll` は失敗しても CI 全体を失敗させない（警告のみ）。  
削除残しを検知するには：

1. `[teardown] 利用者削除失敗:` の文字列を CI ログで grep する
2. `[cleanup] E2E スタッフの削除に失敗しました` の文字列を CI ログで grep する
3. 定期実行クエリで蓄積量を監視する（月次 GitHub Actions ジョブを推奨）

---

## 残存している不安定要因（低優先度）

### B: セレクタ位置依存（recipient-form.ts）

```typescript
// 位置インデックスに依存 → DOM 構造変更で即座に壊れる
await page.locator('select').nth(0).selectOption(livingArrangement);
await page.locator('select').nth(1).selectOption(transportation);
await page.locator('select').filter({ hasNot: page.locator('[disabled]') }).last()
  .selectOption(gender);
```

**対策方針**: フォームコンポーネントに `data-testid` を追加することで根本解決できる。  
ただし UI コンポーネントの変更を伴うため、フロント開発者との協議が必要。

### C: セクション遷移後の描画待ちなし（recipient-form.ts）

```typescript
// ❌ 遷移直後に fill → セクションがまだ描画されていない場合に失敗
await page.click('button:text("次へ")');
await page.getByPlaceholder(/東京都/).fill(data.address);

// ✅ 理想形
await page.click('button:text("次へ")');
await expect(page.locator('h3').filter({ hasText: '連絡先・住所情報' })).toBeVisible();
await page.getByPlaceholder(/東京都/).fill(data.address);
```

現状は CI の遅い環境でも通過しているが、将来的なフレーキーテストの原因になりうる。

---

*作成日: 2026-04-15*  
*更新日: 2026-04-15*
