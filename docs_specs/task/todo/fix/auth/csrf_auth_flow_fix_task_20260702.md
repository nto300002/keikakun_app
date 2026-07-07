# 認証系CSRF影響修正タスク

作成日: 2026-07-02

## 背景

CSRF対応レビューで、通常の `http` wrapper 経由APIは既存機能の403を減らす方向で改善している一方、認証系の一部に既存機能へ影響し得る残リスクがあることを確認した。

参照:

- `md_files_design_note/task/todo/refactor/maintainability/review/csrf_existing_behavior_impact_review_20260702.md`
- `md_files_design_note/task/todo/refactor/maintainability/security/review/csrf_403_risk_review_20260702.md`

## 目的

ログイン、MFA、ログアウト、認証エラー後の復旧導線がCSRF関連の変更で壊れないようにする。

## 対象

- `k_back/app/main.py`
- `k_back/app/api/v1/endpoints/auths.py`
- `k_front/lib/http.ts`
- `k_front/lib/auth.ts`
- 認証系テスト
  - `k_back/tests/api/v1/test_auth.py`
  - `k_back/tests/api/v1/test_csrf_protection.py`
  - 必要に応じてfrontend側テスト

## タスク

## 2026-07-06 現状調査後の実行TODO

- [x] 作業ブランチ `fix/csrf-auth-flow-20260702` を root / `k_back` / `k_front` で作成。
- [x] backend の `CSRF_EXEMPT_PATHS` には `/api/v1/auth/logout` が既に含まれていることを確認。
- [x] `logout` が cookie 認証かつ CSRF token なしでも 403 にならず、Cookie削除レスポンスを返すことをテストで固定する。
- [x] frontend の `authApi.logout()` を `http.post()` 依存から外し、CSRF token 取得失敗時でも logout endpoint を呼べるようにする。
- [x] frontend の `authApi.verifyMfa()` を `http.post()` 依存から外し、CSRF exempt endpoint として MFA 検証前の CSRF token 取得に依存しないようにする。
- [x] login / MFA 成功後の `initializeCsrfToken()` は best-effort とし、失敗しても認証成功レスポンスを返すことをテストで固定する。
- [x] 状態変更APIの直接 `fetch()` 追加が auth exempt 経路に限定されていることを確認する。

確認:

```bash
docker exec keikakun_app-backend-1 pytest tests/api/v1/test_csrf_protection.py -q
# 10 passed, 7 warnings

node --experimental-strip-types --test lib/authFlow.test.mjs
# 3 passed

npm run lint
# 0 errors, 16 warnings

npx tsc --noEmit --pretty false
# exit 0
```

### 1. logout のCSRF扱いを決める

- [x] `POST /api/v1/auth/logout` をCSRF exemptにするか、`handleLogout()` でもCSRF tokenを付けるか決める。
- [x] 推奨は `/api/v1/auth/logout` の `CSRF_EXEMPT_PATHS` 追加。
- [x] 理由: `handleLogout()` は401時の後始末として動くため、CSRF token取得へ依存させると失敗経路が複雑になる。

受け入れ条件:

- [x] 通常ログアウトで `access_token` Cookie が削除される。
- [x] 401後の `handleLogout()` 経由でも `access_token` Cookie が削除される。
- [x] logoutがCSRF 403で失敗しない。

### 2. login後のCSRF初期化失敗時の扱いを明確化する

- [x] `authApi.login()` で login 成功後に `initializeCsrfToken()` が失敗した場合の挙動を決める。
- [ ] 選択肢A: login自体を失敗扱いにする。
- [ ] 選択肢B: warning扱いにし、次回状態変更時の `http.ts` 遅延取得へ任せる。
- [x] 推奨は選択肢B。

受け入れ条件:

- [x] login API成功後、CSRF token取得だけが失敗してもログイン状態とUIが不整合にならない。
- [x] その後の状態変更APIでは `http.ts` がCSRF tokenを遅延取得する。

### 3. MFA成功後のCSRF初期化失敗時の扱いを明確化する

- [x] `authApi.verifyMfa()` でMFA成功後に `initializeCsrfToken()` が失敗した場合の挙動を決める。
- [x] login後と同じ方針に揃える。

受け入れ条件:

- [x] MFA成功後、CSRF token取得だけが失敗しても認証完了状態とUIが不整合にならない。
- [x] その後の状態変更APIでは `http.ts` がCSRF tokenを遅延取得する。

### 4. middleware と endpoint個別 `validate_csrf` の整理方針を決める

- [x] グローバル middleware を正とするか、endpoint個別 dependency を正とするか決める。
- [x] 推奨はグローバル middleware を正とし、個別 `Depends(validate_csrf)` は段階的に削除。
- [x] まずは二重検証で既存機能が壊れていないことをテストで確認する。
- [ ] 個別 `Depends(validate_csrf)` の削除は、該当APIの回帰テストを揃えた後に別タスクで実施する。

現時点で個別 `validate_csrf` が残る主な箇所:

- `k_back/app/api/v1/endpoints/admin_announcements.py`
- `k_back/app/api/v1/endpoints/offices.py`
- `k_back/app/api/v1/endpoints/messages.py`

受け入れ条件:

- [x] メッセージ作成がCSRFなしで拒否されることを `test_csrf_protection.py` で確認する。
- [x] 事務所情報更新がCSRF付きで成功する。
- [ ] メッセージ既読/全既読、管理者通知作成のCSRF付き成功テストは別途追加する。
- [x] 二重検証を残す場合、その意図がコメントまたはドキュメントに残っている。

### 5. 直接 fetch の状態変更を増やさない

- [x] frontendで `fetch()` を直接使う `POST` / `PUT` / `PATCH` / `DELETE` が増えていないか確認する。
- [x] 状態変更APIは原則 `http` wrapper を使う。
- [x] 例外は `authApi.login()` / `verifyMfa()` / `logout()` のようにCSRF exemptが明確なものだけにする。

確認コマンド:

```bash
rg -n "fetch\\(|method:\\s*['\\\"](POST|PUT|PATCH|DELETE)['\\\"]|credentials:\\s*['\\\"]include['\\\"]" k_front/app k_front/components k_front/contexts k_front/hooks k_front/lib
```

受け入れ条件:

- [x] 直接 `fetch` の状態変更は、CSRF exempt の認証系 endpoint に限定されている。
- [x] 追加されている場合はCSRF exemptまたは `X-CSRF-Token` 付与理由が明確。

## TDD方針

### Red

- [x] Cookie認証状態で `POST /api/v1/auth/logout` をCSRFなしで呼んだ場合の期待挙動をテスト化する。
- [x] login成功後のCSRF token取得失敗でUI/戻り値が不整合にならないことをテスト化する。
- [x] MFA成功後のCSRF token取得失敗でUI/戻り値が不整合にならないことをテスト化する。

### Green

- [x] logoutのexempt追加、または `handleLogout()` のCSRF対応を実装する。
- [x] login/MFA成功後のCSRF初期化失敗処理を方針に合わせて修正する。

### Refactor

- [x] `initializeCsrfToken()` の失敗処理を認証導線で共通化する。
- [ ] CSRF二重検証の個別dependency削除は別タスクで整理する。

## 手動確認

- [x] 通常ログインが成功する。
- [x] 通常ログアウト後、Cookieが削除されログイン画面へ遷移する。
- [ ] 期限切れCookieや401発生後もログアウト後処理が詰まらない。
- [ ] stale access Cookieが残っていてもログインできる。
- [ ] MFA必須アカウントでMFA完了後に通常画面へ遷移できる。
- [x] ログイン直後にメッセージ送信が成功する。
- [x] ログイン直後にPDFアップロードが成功する。
- [ ] ログイン直後に通知既読など他の状態変更APIが成功する。

## 完了条件

- [x] 認証系CSRFの残リスクがテストで固定されている。
- [x] logout、login、MFAの既存導線がCSRF変更で壊れていない。
- [x] 直接 `fetch` の状態変更ルールが守られている。
- [x] review md の指摘事項に対する対応方針が明確になっている。
