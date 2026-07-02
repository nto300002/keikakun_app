# CSRF対応 既存機能への影響レビュー

作成日: 2026-07-02

## 目的

CSRF関連の修正が既存機能の振る舞いを壊していないかを確認する。

特に以下を確認した。

- 状態変更APIで `X-CSRF-Token` が付与されるか。
- 既存のログイン/MFA/登録/パスワードリセットなど認証系導線がCSRFで詰まらないか。
- FormData送信、メッセージ、通知、課金、利用者CRUDなど既存機能の403リスクが下がっているか。
- backend middleware と endpoint 個別 `validate_csrf` の二重検証が挙動へ影響しないか。

## 現在の実装整理

### frontend

対象:

- `k_front/lib/http.ts`

現状:

- `POST` / `PUT` / `PATCH` / `DELETE` では、送信前に `ensureCsrfToken()` でCSRF tokenを確保する。
- メモリ上の token がない場合は `/api/v1/csrf-token` を取得する。
- `403` かつ `detail === "CSRF token validation failed"` の場合、tokenを再取得して1回だけ再送する。
- JSON API と FormData API の両方が対象。

影響:

- ページリロード直後、Fast Refresh後、CSRF初期化前操作でも状態変更APIが403になりにくくなる。
- 初回状態変更APIの前に `/api/v1/csrf-token` が1回増える。
- CSRF token取得APIが落ちている場合、認証前の登録/パスワードリセット等も失敗し得る。

### backend

対象:

- `k_back/app/main.py`
- `csrf_cookie_auth_middleware`

現状:

- `POST` / `PUT` / `PATCH` / `DELETE`
- `access_token` Cookieあり
- `Authorization: Bearer ...` なし
- `CSRF_EXEMPT_PATHS` ではない

上記条件に一致した場合だけ `CsrfProtect().validate_csrf(request)` が実行される。

exempt済み:

- `/api/v1/csrf-token`
- `/api/v1/auth/token`
- `/api/v1/auth/token/verify-mfa`
- `/api/v1/auth/mfa/first-time-verify`
- `/api/v1/auth/refresh-token`
- `/api/v1/billing/webhook`

## 既存機能への影響評価

### 1. 通常の `http` wrapper 経由API

対象例:

- 利用者登録/編集/削除
- アセスメント関連CRUD
- 個別支援計画PDFアップロード/更新/削除
- 通知既読/全既読/削除
- メッセージ作成/既読/アーカイブ
- 課金 Checkout / Customer Portal
- Google Calendar設定
- プロフィール変更
- MFA管理

評価:

- 既存機能への影響は基本的に改善方向。
- これまではページリロード直後など `csrfToken === null` の状態で403になる可能性があった。
- 現在は状態変更前に遅延取得し、CSRF失敗時も1回だけ再取得リトライするため、既存操作の成功率は上がる。

注意:

- 初回状態変更時にCSRF取得分の通信が1回増える。
- `/api/v1/csrf-token` がCORS/認証/環境設定ミスで失敗すると、状態変更API全般が失敗する。

### 2. FormData送信

対象:

- `k_front/lib/support-plan.ts`
- `http.postFormData`
- `http.putFormData`

評価:

- 個別支援計画PDFアップロードの403対策として妥当。
- `Content-Type` を手動設定せず、`X-CSRF-Token` のみ追加しているため multipart boundary は壊していない。
- CSRF失敗時に1回再送するため、古い token/cookie 不一致にもある程度耐えられる。

注意:

- ファイルアップロードの再送が1回発生し得るため、巨大ファイルでは再送分の負荷が増える。
- backend側で冪等性がないアップロード処理の場合、CSRF検証後に処理が進んでから失敗したケースの再送とは区別が必要。ただし現在の再送条件はCSRF 403のみなので、処理本体実行前に止まる前提。

### 3. ログイン

対象:

- `k_front/lib/auth.ts`
- `authApi.login()`
- `POST /api/v1/auth/token`

評価:

- login は直接 `fetch` だが、backend側で `/api/v1/auth/token` が `CSRF_EXEMPT_PATHS` に入っている。
- staleな `access_token` Cookie が残っていてもCSRFでログインが止まるリスクは低い。

確認済みテスト観点:

- `k_back/tests/api/v1/test_csrf_protection.py` に `test_login_is_not_blocked_by_csrf_when_stale_access_cookie_exists` がある。

注意:

- login成功後に `initializeCsrfToken()` を呼ぶため、CSRF token取得に失敗すると login 処理全体が reject される。
- 実際には access_token Cookie は発行済みになっている可能性があるため、CSRF取得失敗時のUI表示とログイン状態が不整合になる余地がある。

推奨:

- login後のCSRF初期化失敗を致命扱いにするか、警告扱いにして次回状態変更時の遅延取得へ任せるかを明確化する。

### 4. MFA検証

対象:

- `POST /api/v1/auth/token/verify-mfa`
- `POST /api/v1/auth/mfa/first-time-verify`

評価:

- backend側でCSRF exempt済み。
- MFA検証前は通常のaccess token Cookieが未確定、または一時token中心のため、CSRFで止めない方針は既存導線への影響が少ない。
- MFA検証成功後に `initializeCsrfToken()` を実行する設計も、Cookie認証に移行する流れとして妥当。

注意:

- loginと同じく、MFA成功後のCSRF取得失敗をどう扱うかはUI上の不整合確認が必要。

### 5. ログアウト

対象:

- `k_front/lib/auth.ts`
- `authApi.logout()`
- `k_front/lib/http.ts`
- `handleLogout()`
- `POST /api/v1/auth/logout`

評価:

- `authApi.logout()` は `http.post` 経由のためCSRF tokenが付く。
- 通常のログアウトボタンは既存機能を壊しにくい。

残リスク:

- `handleLogout()` は401時の後始末として直接 `fetch()` で `/api/v1/auth/logout` を呼ぶ。
- `/api/v1/auth/logout` は現時点の `CSRF_EXEMPT_PATHS` に入っていない。
- `access_token` Cookieが残っている状態で `handleLogout()` が走ると、logout自体がCSRF 403になり、backend側のCookie削除が実行されない可能性がある。
- `handleLogout()` は失敗を握りつぶして画面遷移するため、ユーザーからは見えにくい。

推奨:

- `/api/v1/auth/logout` を `CSRF_EXEMPT_PATHS` に追加するか、`handleLogout()` でもCSRF tokenを付ける。
- エラー回復中にCSRF取得へ依存すると失敗経路が複雑になるため、logout exempt化が実装上は単純。

### 6. 認証前の登録/パスワードリセット

対象:

- `authApi.registerAdmin`
- `authApi.registerStaff`
- `ForgotPasswordForm`
- `ResetPasswordForm`

評価:

- frontendは `http.post` 経由のため、認証前でもCSRF tokenを取得して送る。
- backend middlewareは `access_token` Cookieがない場合はCSRF検証しないため、ヘッダーが余分に付くこと自体は問題ない。

影響:

- 認証前APIでも `/api/v1/csrf-token` への依存が増える。
- Cookie/CORS設定が壊れている環境では、登録やパスワードリセットが本体APIに到達する前に失敗し得る。

推奨:

- 認証前APIにCSRF tokenを必須にする方針でなければ、`http.post` 側で endpoint 単位のCSRF不要指定を持たせるか、現状のまま「CSRF取得APIの可用性を必須」として運用するかを決める。

### 7. 直接 `fetch` の状態変更

検索結果:

- 直接 `fetch` の状態変更は主に `authApi.login()` と `handleLogout()`。
- `dal.ts` と profile page の直接 `fetch` は `GET /staffs/me` で状態変更ではない。
- `PlanDeliverableModal.tsx` の `fetch(existingPdfUrl)` は署名付きURL取得であり、アプリbackendのCSRF対象ではない。

評価:

- 新規に直接 `fetch` で `POST` / `PUT` / `PATCH` / `DELETE` を追加すると、CSRF header付与・再取得リトライ・401処理を通らないため再発リスクがある。

ルール:

- 状態変更APIは原則 `http.post` / `http.put` / `http.patch` / `http.delete` / `http.postFormData` / `http.putFormData` を使う。
- 直接 `fetch` を使う場合は、CSRF exempt対象か、CSRF token付与を明記する。

### 8. middleware と endpoint個別 `validate_csrf` の二重検証

対象:

- `k_back/app/main.py::csrf_cookie_auth_middleware`
- `k_back/app/api/deps.py::validate_csrf`

個別 `validate_csrf` 使用箇所:

- `admin_announcements.py`
- `offices.py::PUT /me`
- `messages.py` の作成/既読/全既読系

評価:

- middlewareでCSRF検証済みのリクエストに対して、endpoint dependencyでもう一度検証する。
- tokenが単回使用でなければ、機能的には通る可能性が高い。
- ただし、検証コストと実装の見通しは悪くなる。

残リスク:

- CSRFライブラリ側の挙動変更で token が消費型に変わる、またはcookie更新を伴う場合、二重検証が将来の不具合要因になる。
- 失敗ログがmiddleware由来かdependency由来か分かりづらくなる。

推奨:

- グローバルmiddlewareを正とするなら、endpoint個別 `Depends(validate_csrf)` は段階的に削除する。
- 逆に個別dependencyを正とするなら、middleware対象を限定する。
- 現状維持の場合は「二重検証を許容する」テストを明示する。

## テストカバー状況

確認できたもの:

- `k_back/tests/api/v1/test_csrf_protection.py`
  - CSRF token取得
  - Cookie認証の状態変更でCSRF必須
  - 有効/無効CSRF token
  - Bearer認証ではCSRF不要
  - stale access CookieありのログインがCSRFで止まらないこと
  - GETはCSRF不要
- `k_back/tests/api/v1/test_messages_api.py`
  - メッセージ系でCSRF token付きテスト多数
- `k_back/tests/api/v1/test_inquiries_integration.py`
  - 問い合わせ系でCSRF token付きテストあり

不足している可能性があるもの:

- [ ] `authApi.logout()` 相当の Cookie認証 + CSRF token付き logout。
- [ ] `handleLogout()` 相当の CSRF tokenなし logout がどうなるか。
- [ ] `http.ts` のCSRF遅延取得と1回リトライの frontend unit test。
- [ ] FormData送信で `X-CSRF-Token` が付与され、`Content-Type` を壊していないこと。
- [ ] CSRF token取得失敗時の login / MFA後 / 登録 / パスワードリセットのUI挙動。
- [ ] middleware + endpoint個別 `validate_csrf` の二重検証が通ること。

## 既存機能別の手動確認項目

- [ ] ページリロード直後に個別支援計画PDFをアップロードできる。
- [ ] Fast Refresh後に個別支援計画PDFをアップロードできる。
- [ ] 通知の既読、全既読、削除ができる。
- [ ] 個人メッセージ、全体通知、既読、アーカイブができる。
- [ ] 利用者の登録、編集、削除ができる。
- [ ] アセスメントの追加、編集、削除ができる。
- [ ] 有料会員登録、支払い方法変更/解約導線が動く。
- [ ] ログイン後にCSRF初期化失敗が起きてもUIが不整合にならない。
- [ ] MFA検証後にCSRF初期化失敗が起きてもUIが不整合にならない。
- [ ] ログアウト後に `access_token` Cookie が残らない。
- [ ] stale access Cookie が残った状態でもログインできる。

## 結論

今回のCSRF対応は、通常の `http` wrapper 経由APIとFormData送信については既存機能の403発生を減らす方向であり、挙動影響は概ね許容範囲。

ただし、以下は修正または方針決定が必要。

1. `handleLogout()` の直接 `fetch` は `/auth/logout` がCSRF exemptでないため、Cookie削除が失敗する可能性がある。
2. login/MFA成功後の `initializeCsrfToken()` 失敗を致命扱いにするか、遅延取得に任せるかを決める必要がある。
3. middlewareとendpoint個別 `validate_csrf` の二重検証は、短期的には動く可能性が高いが、保守性と将来互換性の観点で整理対象。
4. 認証前APIもCSRF token取得に依存するため、CSRF endpoint/CORS/cookie設定の不具合が登録やパスワードリセットに波及する。
