# E2E CI 修正ログ: Vercel Preview 対応

**日付**: 2026-04-19〜20  
**対象 PR**: nto300002/keikakun_front#55 (`feature/e2e-playwright-core-flows`)  
**結果**: CI success（全 26 テスト通過）

---

## 問題の連鎖と修正内容

### 1. 利用者登録 422 エラー

**原因**: `INITIAL_FORM_DATA.disabilityDetails` に空エントリ `[{category:'', ...}]` が初期値として入っており、バックエンドの enum バリデーションが失敗。

**修正**: `k_front/components/protected/recipients/RecipientRegistrationForm.tsx`
```typescript
// Before
disabilityDetails: [{ category: '', applicationStatus: '', ... }],
// After
disabilityDetails: [],  // 空配列（任意項目）
```

---

### 2. Vercel Preview URL の自動取得

**原因**: CI の `PLAYWRIGHT_BASE_URL` が常に本番 URL（main ブランチ）を指しており、PR のコードに対してテストされていなかった。

**修正**: `k_front/.github/workflows/ci-frontend.yml`
- GitHub Deployments API をポーリングして PR の Vercel Preview URL を自動取得（最大 5 分待機）
- PR 以外（main push）は `secrets.PLAYWRIGHT_BASE_URL` にフォールバック

---

### 3. Vercel Deployment Protection（401）

**原因**: Vercel Preview に Deployment Protection が有効で、Playwright のリクエストが 401 で弾かれていた。

**修正**:
- `playwright.config.ts`: `extraHTTPHeaders` に `x-vercel-protection-bypass` を追加
- GitHub Secrets に `VERCEL_AUTOMATION_BYPASS_SECRET` を登録
- CI の `env` に `VERCEL_AUTOMATION_BYPASS_SECRET` を追加

---

### 4. CORS ブロック（オリジン）

**原因**: `k_back/app/main.py` の `allowed_origins` に Vercel Preview の動的 URL（`keikakun-front-*.vercel.app`）が含まれていなかった。`allow_credentials=True` 時はワイルドカード `*` が使えない。

**修正**: `k_back/app/main.py`
```python
app.add_middleware(
    CORSMiddleware,
    allow_origins=allowed_origins,
    allow_origin_regex=r"https://keikakun-front[^.]*\.vercel\.app",  # 追加
    allow_credentials=True,
    ...
)
```

---

### 5. CORS ブロック（ヘッダー）

**原因**: Playwright が `extraHTTPHeaders` で全リクエストに `x-vercel-protection-bypass` を付加するため、CORS preflight の `Access-Control-Request-Headers` にこのヘッダーが含まれるが、バックエンドの `allowed_headers` に存在せず 400 を返していた。

**修正**: `k_back/app/main.py`
```python
allowed_headers = [
    "Content-Type",
    "Authorization",
    ...
    "x-vercel-protection-bypass",  # 追加
]
```

---

### 6. ログイン後 401（SameSite Cookie）

**原因**: `COOKIE_SAMESITE=lax` に設定されていたため、Vercel Preview（`*.vercel.app`）から `api.keikakun.com` へのクロスサイト fetch リクエストに `access_token` Cookie が含まれず 401 になっていた。

本番では `www.keikakun.com` → `api.keikakun.com` が同一サイト（`.keikakun.com`）なので問題なし。

**採用した解決策**: GitHub Secrets の `COOKIE_SAMESITE` を `none` に変更して再デプロイ。

**検討した選択肢**:

| 方法 | 採用 | 理由 |
|------|------|------|
| `COOKIE_SAMESITE=none` | ✅ | CSRF トークン + CORS で補完済み。変更コスト最小 |
| Next.js rewrites プロキシ | ❌ | Cookie Domain 問題が残る、lib/http.ts 基盤変更が必要 |
| E2E 専用認証 | ❌ | 本番コードに分岐が混入、テスト価値が下がる |

**セキュリティ補足**: `SameSite=None; Secure` は Auth0・Firebase など主要サービスが採用する標準構成。CSRF トークン（POST/PUT/PATCH/DELETE 必須）と CORS（特定オリジンのみ許可）で二重防御。

---

### 7. Next.js middleware が access_token を参照できない

**原因**: `access_token` Cookie は `Domain=.keikakun.com` で発行されるため、ブラウザは `vercel.app` ドメインへのページリクエストにこの Cookie を含めない。Next.js middleware（Vercel Edge）が Cookie を見つけられず `/auth/login?from=/dashboard` にリダイレクト。

**修正**: `k_front/e2e/fixtures/auth.ts`
- ログイン成功後、`page.context().cookies([apiOrigin])` で API ドメインの `access_token` を取得
- `page.context().addCookies()` で現在の Vercel ホスト名にも同 Cookie を追加
- プロダクションコードへの変更なし

```typescript
const apiCookies = await page.context().cookies([apiOrigin]);
const accessTokenCookie = apiCookies.find(c => c.name === 'access_token');
if (accessTokenCookie) {
  await page.context().addCookies([{
    ...accessTokenCookie,
    domain: currentHostname,  // vercel.app のホスト名
  }]);
}
```

---

## 変更ファイル一覧

| リポジトリ | ファイル | 内容 |
|-----------|---------|------|
| k_front | `e2e/fixtures/auth.ts` | 診断ログ追加・Cookie コピー処理 |
| k_front | `e2e/helpers/recipient-form.ts` | waitForResponse で API レスポンス捕捉 |
| k_front | `playwright.config.ts` | x-vercel-protection-bypass ヘッダー |
| k_front | `.github/workflows/ci-frontend.yml` | Vercel Preview URL 自動取得 |
| k_front | `components/protected/recipients/RecipientRegistrationForm.tsx` | disabilityDetails 初期値修正 |
| k_back | `app/main.py` | allow_origin_regex・allowed_headers 追加 |
| keikakun_app | GitHub Secrets | `COOKIE_SAMESITE=none` に変更 |

---

## 教訓

- `NEXT_PUBLIC_*` はビルド時に Vercel の環境変数から bake-in されるため、CI の env では上書きできない
- `allow_credentials=True` + `SameSite=None` はセットで必要（CORS と Cookie 設定は独立した問題）
- Playwright の `extraHTTPHeaders` は API リクエストにも付与されるため CORS の `allowed_headers` に追加が必要
- Vercel Preview と本番でドメインが異なる場合、Cookie の `Domain` 属性が middleware の認証チェックを壊す。`context.addCookies()` で E2E 側から解決できる
