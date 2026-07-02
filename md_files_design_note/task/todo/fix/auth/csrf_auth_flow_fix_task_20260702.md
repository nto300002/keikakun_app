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

### 1. logout のCSRF扱いを決める

- [ ] `POST /api/v1/auth/logout` をCSRF exemptにするか、`handleLogout()` でもCSRF tokenを付けるか決める。
- [ ] 推奨は `/api/v1/auth/logout` の `CSRF_EXEMPT_PATHS` 追加。
- [ ] 理由: `handleLogout()` は401時の後始末として動くため、CSRF token取得へ依存させると失敗経路が複雑になる。

受け入れ条件:

- [ ] 通常ログアウトで `access_token` Cookie が削除される。
- [ ] 401後の `handleLogout()` 経由でも `access_token` Cookie が削除される。
- [ ] logoutがCSRF 403で失敗しない。

### 2. login後のCSRF初期化失敗時の扱いを明確化する

- [ ] `authApi.login()` で login 成功後に `initializeCsrfToken()` が失敗した場合の挙動を決める。
- [ ] 選択肢A: login自体を失敗扱いにする。
- [ ] 選択肢B: warning扱いにし、次回状態変更時の `http.ts` 遅延取得へ任せる。
- [ ] 推奨は選択肢B。

受け入れ条件:

- [ ] login API成功後、CSRF token取得だけが失敗してもログイン状態とUIが不整合にならない。
- [ ] その後の状態変更APIでは `http.ts` がCSRF tokenを遅延取得する。

### 3. MFA成功後のCSRF初期化失敗時の扱いを明確化する

- [ ] `authApi.verifyMfa()` でMFA成功後に `initializeCsrfToken()` が失敗した場合の挙動を決める。
- [ ] login後と同じ方針に揃える。

受け入れ条件:

- [ ] MFA成功後、CSRF token取得だけが失敗しても認証完了状態とUIが不整合にならない。
- [ ] その後の状態変更APIでは `http.ts` がCSRF tokenを遅延取得する。

### 4. middleware と endpoint個別 `validate_csrf` の整理方針を決める

- [ ] グローバル middleware を正とするか、endpoint個別 dependency を正とするか決める。
- [ ] 推奨はグローバル middleware を正とし、個別 `Depends(validate_csrf)` は段階的に削除。
- [ ] まずは二重検証で既存機能が壊れていないことをテストで確認する。

現時点で個別 `validate_csrf` が残る主な箇所:

- `k_back/app/api/v1/endpoints/admin_announcements.py`
- `k_back/app/api/v1/endpoints/offices.py`
- `k_back/app/api/v1/endpoints/messages.py`

受け入れ条件:

- [ ] メッセージ作成/既読/全既読がCSRF付きで成功する。
- [ ] 事務所情報更新がCSRF付きで成功する。
- [ ] 管理者通知作成がCSRF付きで成功する。
- [ ] 二重検証を残す場合、その意図がコメントまたはドキュメントに残っている。

### 5. 直接 fetch の状態変更を増やさない

- [ ] frontendで `fetch()` を直接使う `POST` / `PUT` / `PATCH` / `DELETE` が増えていないか確認する。
- [ ] 状態変更APIは原則 `http` wrapper を使う。
- [ ] 例外は `authApi.login()` のようにCSRF exemptが明確なものだけにする。

確認コマンド:

```bash
rg -n "fetch\\(|method:\\s*['\\\"](POST|PUT|PATCH|DELETE)['\\\"]|credentials:\\s*['\\\"]include['\\\"]" k_front/app k_front/components k_front/contexts k_front/hooks k_front/lib
```

受け入れ条件:

- [ ] 直接 `fetch` の状態変更が追加されていない。
- [ ] 追加されている場合はCSRF exemptまたは `X-CSRF-Token` 付与理由が明確。

## TDD方針

### Red

- [ ] Cookie認証状態で `POST /api/v1/auth/logout` をCSRFなしで呼んだ場合の期待挙動をテスト化する。
- [ ] login成功後のCSRF token取得失敗でUI/戻り値が不整合にならないことをテスト化する。
- [ ] MFA成功後のCSRF token取得失敗でUI/戻り値が不整合にならないことをテスト化する。

### Green

- [ ] logoutのexempt追加、または `handleLogout()` のCSRF対応を実装する。
- [ ] login/MFA成功後のCSRF初期化失敗処理を方針に合わせて修正する。

### Refactor

- [ ] `initializeCsrfToken()` の失敗処理を認証導線で共通化する。
- [ ] CSRF二重検証の整理方針に合わせてbackend側を整理する。

## 手動確認

- [ ] 通常ログアウト後、Cookieが削除されログイン画面へ遷移する。
- [ ] 期限切れCookieや401発生後もログアウト後処理が詰まらない。
- [ ] stale access Cookieが残っていてもログインできる。
- [ ] MFA必須アカウントでMFA完了後に通常画面へ遷移できる。
- [ ] ログイン直後に通知既読、メッセージ送信、PDFアップロードなど状態変更APIが成功する。

## 完了条件

- [ ] 認証系CSRFの残リスクがテストで固定されている。
- [ ] logout、login、MFAの既存導線がCSRF変更で壊れていない。
- [ ] 直接 `fetch` の状態変更ルールが守られている。
- [ ] review md の指摘事項に対する対応方針が明確になっている。
