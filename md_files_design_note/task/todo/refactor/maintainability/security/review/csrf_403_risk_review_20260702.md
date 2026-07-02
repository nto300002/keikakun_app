# CSRF起因403リスク調査

作成日: 2026-07-02

## 背景

localで個別支援計画PDFアップロード時に `POST /api/v1/support-plans/plan-deliverables` が `403 Forbidden` になった。

原因は、Cookie認証の状態変更リクエストに対してbackendのCSRF middlewareが `X-CSRF-Token` を要求する一方、frontendのFormData送信時にメモリ上のCSRF tokenが未初期化だとヘッダーが付かないこと。

## backend側のCSRF条件

対象:

- `k_back/app/main.py`

条件:

- method が `POST` / `PUT` / `PATCH` / `DELETE`
- `request.cookies["access_token"]` が存在する
- `Authorization: Bearer ...` がない
- `CSRF_EXEMPT_PATHS` に含まれない

この条件に一致すると `CsrfProtect().validate_csrf(request)` が実行される。

## 今回の直接原因

対象:

- `k_front/lib/support-plan.ts`
- `k_front/lib/http.ts`
- `k_back/app/api/v1/endpoints/support_plans.py`

発生条件:

- PDFアップロードは `http.postFormData()` を通る。
- `http.postFormData()` は `csrfToken` がメモリにある場合だけ `X-CSRF-Token` を付けていた。
- ページリロード、Fast Refresh、CSRF初期化前操作、古いtoken/cookie不一致の状態ではヘッダーなしまたは不一致で送信される。
- backendはCookie認証済み状態変更POSTとして扱うため403になる。

修正方針:

- `http.ts` 側で状態変更前にCSRF tokenがなければ `/api/v1/csrf-token` を取得する。
- CSRF不一致で403になった場合は、CSRF tokenを再取得して1回だけ再送する。
- JSONリクエストとFormDataリクエストの両方で同じ方針にする。

## 類似403が起きる可能性がある箇所

### 1. `http` を経由する状態変更API

対象例:

- `k_front/lib/assessment.ts`
- `k_front/lib/welfare-recipients.ts`
- `k_front/lib/api/notices.ts`
- `k_front/lib/api/messages.ts`
- `k_front/lib/api/employeeActionRequests.ts`
- `k_front/lib/api/roleChangeRequests.ts`
- `k_front/lib/api/withdrawalRequests.ts`
- `k_front/lib/calendar.ts`
- `k_front/lib/profile.ts`
- `k_front/lib/api/billing.ts`
- `k_front/lib/support-plan.ts`

リスク:

- 修正前は、アプリ起動直後やFast Refresh後に `csrfToken` が `null` のまま状態変更すると403になり得た。
- 特にFormData系は今回のPDFアップロードと同じ症状になりやすい。

現在の扱い:

- `http.ts` で状態変更前にCSRF tokenを遅延取得する方針にすれば、基本的に解消可能。
- 403 CSRF時の1回リトライも入れることで、token/cookie不一致にも耐えやすくなる。

### 2. `fetch` を直接使うログイン

対象:

- `k_front/lib/auth.ts`
- `authApi.login()`
- `POST /api/v1/auth/token`

リスク:

- 通常ログイン時は `access_token` CookieがないためCSRF middleware対象外。
- ただし、期限切れ/不整合な `access_token` Cookieがブラウザに残っている状態でログインPOSTすると、backendはCookie認証の状態変更として扱い、CSRF tokenなしで403になる可能性がある。

対応候補:

- `POST /api/v1/auth/token` を `CSRF_EXEMPT_PATHS` に追加する。
- または `authApi.login()` でも事前にCSRF tokenを取得して `X-CSRF-Token` を付ける。
- ログインは認証前エンドポイントなので、実装単純性を重視するならbackend exempt化が妥当。

### 3. `fetch` を直接使うログアウト

対象:

- `k_front/lib/http.ts`
- `handleLogout()`
- `POST /api/v1/auth/logout`

リスク:

- `handleLogout()` は認証エラー時に直接 `fetch()` でlogoutを呼ぶ。
- `access_token` Cookieがある状態のPOSTなので、CSRF tokenなしだと403になる。
- 現状はcatchして無視するためUI上は目立ちにくいが、backend側でCookie削除が実行されない可能性がある。

対応候補:

- `POST /api/v1/auth/logout` を `CSRF_EXEMPT_PATHS` に追加する。
- または `handleLogout()` でもCSRF tokenを取得して送る。
- 認証エラー処理中にCSRF取得まで要求すると失敗経路が複雑になるため、logoutはexempt化を検討する。

### 4. 今後追加される `fetch` 直叩きの状態変更

検索観点:

```bash
rg -n "fetch\\(|method:\\s*['\\\"](POST|PUT|PATCH|DELETE)['\\\"]|FormData\\(" k_front/app k_front/components k_front/lib k_front/hooks
```

リスク:

- `http` wrapperを通らない状態変更リクエストは、CSRF header付与・401処理・CSRF再取得リトライを受けられない。
- `credentials: "include"` が付いている場合、Cookie認証としてbackend CSRF middleware対象になる。

対応方針:

- 状態変更APIは原則 `http.post` / `http.put` / `http.patch` / `http.delete` / `http.postFormData` / `http.putFormData` を使う。
- 例外的に直接 `fetch` する場合は、CSRF token取得、`X-CSRF-Token` 付与、403時リトライ方針を明記する。

### 5. backendテストでCookie認証だけを設定して状態変更するケース

対象例:

- `tests/api/v1/test_notices.py`
- Cookieに `access_token` だけを入れて `PATCH` / `DELETE` を呼ぶテスト

リスク:

- 実装は正しいのに、テストがCSRF tokenを付けず403になる。
- 今後、CSRF middleware対象が広がるほど同種のテスト失敗が増える。

対応方針:

- Cookie認証で状態変更するAPIテストは `/api/v1/csrf-token` でtoken/cookieを取得し、`X-CSRF-Token` を付ける。
- Bearer認証のテストはCSRF不要。

## 現時点でCSRF対象外として妥当なもの

- `GET` リクエスト
- S3署名付きURLなど、アプリbackendではない外部URLへの `fetch`
- `Authorization: Bearer ...` を使うAPIテスト
- `CSRF_EXEMPT_PATHS` の webhook / csrf-token / refresh-token

## 追加で検討すべきexempt候補

### `/api/v1/auth/token`

理由:

- ログイン前エンドポイント。
- staleな `access_token` Cookieがある場合にログイン自体が403になる可能性がある。

注意:

- exempt化しても、認証情報を検証するだけであり、既存Cookieだけで状態変更が成立する経路ではない。

### `/api/v1/auth/logout`

理由:

- 認証エラー時の後始末として呼ばれる。
- CSRF失敗でCookie削除ができないと、ユーザーがログイン画面へ戻っても不整合Cookieが残る可能性がある。

注意:

- logoutは状態変更だが、攻撃者が成立させても主な影響はログアウトであり、機密操作よりリスクは低い。

## 推奨対応順

1. `http.ts` で状態変更前のCSRF遅延取得と403時1回リトライを実装する。
2. `POST /api/v1/auth/token` と `POST /api/v1/auth/logout` のCSRF扱いを決める。
3. `fetch` 直叩きの状態変更を禁止またはレビュー対象にする。
4. Cookie認証の状態変更テストにCSRF token付与を徹底する。
5. 本番/preview/localでPDFアップロード、通知既読、メッセージ送信、利用者登録/編集の手動確認を行う。

## 手動確認項目

- ページリロード直後にPDFアップロードして403にならない。
- Fast Refresh後にPDFアップロードして403にならない。
- 通知既読/全既読/削除が403にならない。
- メッセージ送信が403にならない。
- 利用者登録/編集/削除が403にならない。
- stale Cookieが残っている状態でログインPOSTが403にならないか確認する。

---

FAILED tests/api/v1/test_employee_action_requests.py::test_create_employee_action_request - assert 403 == 201
 +  where 403 = <Response [403 Forbidden]>.status_code
FAILED tests/api/v1/test_employee_action_requests.py::test_create_employee_action_request_update - assert 403 == 201
 +  where 403 = <Response [403 Forbidden]>.status_code
FAILED tests/api/v1/test_employee_action_requests.py::test_create_employee_action_request_delete - assert 403 == 201
 +  where 403 = <Response [403 Forbidden]>.status_code
FAILED tests/api/v1/test_employee_action_requests.py::test_approve_employee_action_request_as_manager - assert 403 == 200
 +  where 403 = <Response [403 Forbidden]>.status_code
FAILED tests/api/v1/test_employee_action_requests.py::test_approve_employee_action_request_as_owner - assert 403 == 200
 +  where 403 = <Response [403 Forbidden]>.status_code
FAILED tests/api/v1/test_employee_action_requests.py::test_approve_employee_action_request_already_approved - assert 403 == 400
 +  where 403 = <Response [403 Forbidden]>.status_code
FAILED tests/api/v1/test_employee_action_requests.py::test_reject_employee_action_request - assert 403 == 200
 +  where 403 = <Response [403 Forbidden]>.status_code
FAILED tests/api/v1/test_employee_action_requests.py::test_delete_pending_employee_action_request - assert 403 == 204
 +  where 403 = <Response [403 Forbidden]>.status_code
FAILED tests/api/v1/test_employee_action_requests.py::test_delete_approved_employee_action_request_fails - assert 403 == 400
 +  where 403 = <Response [403 Forbidden]>.status_code
FAILED tests/api/v1/test_inquiry_endpoints.py::TestInquiryPublicEndpoint::test_create_inquiry_from_logged_in_user - assert 403 == 200
 +  where 403 = <Response [403 Forbidden]>.status_code
FAILED tests/api/v1/test_inquiry_endpoints.py::TestAdminInquiryUpdateEndpoint::test_update_inquiry_as_app_admin - assert 403 == 200
 +  where 403 = <Response [403 Forbidden]>.status_code
FAILED tests/api/v1/test_inquiry_endpoints.py::TestAdminInquiryReplyEndpoint::test_reply_to_inquiry_from_logged_in_sender - assert 403 == 200
 +  where 403 = <Response [403 Forbidden]>.status_code
FAILED tests/api/v1/test_inquiry_endpoints.py::TestAdminInquiryReplyEndpoint::test_reply_to_inquiry_with_email - assert 403 == 200
 +  where 403 = <Response [403 Forbidden]>.status_code
FAILED tests/api/v1/test_inquiry_endpoints.py::TestAdminInquiryReplyEndpoint::test_reply_to_inquiry_not_found - assert 403 == 404
 +  where 403 = <Response [403 Forbidden]>.status_code
FAILED tests/api/v1/test_inquiry_endpoints.py::TestAdminInquiryReplyEndpoint::test_reply_to_inquiry_empty_body_fails - assert 403 == 422
 +  where 403 = <Response [403 Forbidden]>.status_code
FAILED tests/api/v1/test_inquiry_endpoints.py::TestAdminInquiryReplyEndpoint::test_reply_as_non_admin_fails - AssertionError: assert '権限がありません' in 'CSRF token validation failed'
FAILED tests/api/v1/test_inquiry_endpoints.py::TestAdminInquiryDeleteEndpoint::test_delete_inquiry_as_app_admin - assert 403 == 200
 +  where 403 = <Response [403 Forbidden]>.status_code
FAILED tests/api/v1/test_inquiry_endpoints.py::TestAdminInquiryDeleteEndpoint::test_delete_inquiry_not_found - assert 403 == 404
 +  where 403 = <Response [403 Forbidden]>.status_code
FAILED tests/api/v1/test_notices.py::test_mark_notice_as_read - assert 403 == 200
 +  where 403 = <Response [403 Forbidden]>.status_code
FAILED tests/api/v1/test_notices.py::test_mark_all_notices_as_read - assert 403 == 200
 +  where 403 = <Response [403 Forbidden]>.status_code
FAILED tests/api/v1/test_notices.py::test_delete_notice - assert 403 == 204
 +  where 403 = <Response [403 Forbidden]>.status_code
FAILED tests/api/v1/test_auth.py::TestCookieAuthentication::test_logout_clears_cookie - assert 403 == 200

---

## 2026-07-02 本番/CI 追加エラー調査: 退会リクエスト中心

### 受領した失敗全文

```text
FAILED tests/api/v1/test_withdrawal_requests.py::test_approve_withdrawal_request_already_processed - assert 403 == 400
 +  where 403 = <Response [403 Forbidden]>.status_code
FAILED tests/api/v1/test_withdrawal_requests.py::test_reject_withdrawal_request_as_app_admin - assert 403 == 200
 +  where 403 = <Response [403 Forbidden]>.status_code
FAILED tests/api/v1/test_withdrawal_requests.py::test_reject_withdrawal_request_not_found - assert 403 == 404
 +  where 403 = <Response [403 Forbidden]>.status_code
FAILED tests/services/test_calendar_service.py::TestCalendarService::test_sync_pending_events_with_api_error - AssertionError: assert 'API Error' in 'GoogleCalendarAPIError'
 +  where 'GoogleCalendarAPIError' = <app.models.calendar_events.CalendarEvent object at 0x7ffaf4657bf0>.last_error_message
FAILED tests/utils/test_email_utils.py::TestSendEmailWithRetry::test_all_retries_fail - AssertionError: assert 'Exception' == 'Permanent failure'
```

関連する既存の同種失敗:

```text
FAILED tests/api/v1/test_employee_action_requests.py::test_create_employee_action_request - assert 403 == 201
FAILED tests/api/v1/test_employee_action_requests.py::test_create_employee_action_request_update - assert 403 == 201
FAILED tests/api/v1/test_employee_action_requests.py::test_create_employee_action_request_delete - assert 403 == 201
FAILED tests/api/v1/test_employee_action_requests.py::test_approve_employee_action_request_as_manager - assert 403 == 200
FAILED tests/api/v1/test_employee_action_requests.py::test_approve_employee_action_request_as_owner - assert 403 == 200
FAILED tests/api/v1/test_employee_action_requests.py::test_approve_employee_action_request_already_approved - assert 403 == 400
FAILED tests/api/v1/test_employee_action_requests.py::test_reject_employee_action_request - assert 403 == 200
FAILED tests/api/v1/test_employee_action_requests.py::test_delete_pending_employee_action_request - assert 403 == 204
FAILED tests/api/v1/test_employee_action_requests.py::test_delete_approved_employee_action_request_fails - assert 403 == 400
FAILED tests/api/v1/test_inquiry_endpoints.py::TestInquiryPublicEndpoint::test_create_inquiry_from_logged_in_user - assert 403 == 200
FAILED tests/api/v1/test_inquiry_endpoints.py::TestAdminInquiryUpdateEndpoint::test_update_inquiry_as_app_admin - assert 403 == 200
FAILED tests/api/v1/test_inquiry_endpoints.py::TestAdminInquiryReplyEndpoint::test_reply_to_inquiry_from_logged_in_sender - assert 403 == 200
FAILED tests/api/v1/test_inquiry_endpoints.py::TestAdminInquiryReplyEndpoint::test_reply_to_inquiry_with_email - assert 403 == 200
FAILED tests/api/v1/test_inquiry_endpoints.py::TestAdminInquiryReplyEndpoint::test_reply_to_inquiry_not_found - assert 403 == 404
FAILED tests/api/v1/test_inquiry_endpoints.py::TestAdminInquiryReplyEndpoint::test_reply_to_inquiry_empty_body_fails - assert 403 == 422
FAILED tests/api/v1/test_inquiry_endpoints.py::TestAdminInquiryReplyEndpoint::test_reply_as_non_admin_fails - AssertionError: assert '権限がありません' in 'CSRF token validation failed'
FAILED tests/api/v1/test_inquiry_endpoints.py::TestAdminInquiryDeleteEndpoint::test_delete_inquiry_as_app_admin - assert 403 == 200
FAILED tests/api/v1/test_inquiry_endpoints.py::TestAdminInquiryDeleteEndpoint::test_delete_inquiry_not_found - assert 403 == 404
FAILED tests/api/v1/test_notices.py::test_mark_notice_as_read - assert 403 == 200
FAILED tests/api/v1/test_notices.py::test_mark_all_notices_as_read - assert 403 == 200
FAILED tests/api/v1/test_notices.py::test_delete_notice - assert 403 == 204
FAILED tests/api/v1/test_auth.py::TestCookieAuthentication::test_logout_clears_cookie - assert 403 == 200
```

### 調査結果

認証系の失敗原因:

- `app/main.py` の CSRF middleware は Cookie 認証の `POST` / `PUT` / `PATCH` / `DELETE` に `X-CSRF-Token` を要求する。
- 退会リクエスト承認/却下、employee action、問い合わせ管理、通知既読/削除のテストは `access_token` Cookie だけを設定し、CSRF token/cookie を付けていなかった。
- そのため、エンドポイント本体の権限・404・400 検証へ到達する前に middleware が `403 CSRF token validation failed` を返していた。
- フロントの `withdrawalRequestsApi` は `http` wrapper 経由で、状態変更前の CSRF 遅延取得と 403 時の token 再取得リトライを通る。退会リクエスト画面側の実装はこの観点では正しい。
- `POST /api/v1/auth/logout` は認証エラー時の後始末として呼ばれるため、CSRF 失敗で Cookie 削除ができない方が問題になる。ログイン系と同じく middleware exempt が妥当。

非認証系の失敗原因:

- `test_calendar_service.py::test_sync_pending_events_with_api_error` は、同期失敗時に `str(exc)` ではなく `type(exc).__name__` を保存していたため、`API Error` が `GoogleCalendarAPIError` に置き換わっていた。
- `test_email_utils.py::test_all_retries_fail` は、メール送信失敗時に `str(e)` ではなく `type(e).__name__` を戻していたため、`Permanent failure` が `Exception` に置き換わっていた。

### 対応

- `tests/conftest.py` に `csrf_headers` fixture を追加。
- Cookie 認証で状態変更する以下のテストへ `X-CSRF-Token` を付与。
  - `tests/api/v1/test_withdrawal_requests.py`
  - `tests/api/v1/test_employee_action_requests.py`
  - `tests/api/v1/test_inquiry_endpoints.py`
  - `tests/api/v1/test_notices.py`
- `POST /api/v1/auth/logout` と trailing slash variant を `CSRF_EXEMPT_PATHS` に追加。
- カレンダー同期失敗時の `last_error_message` は `str(exc) or type(exc).__name__` を保存するよう修正。
- メール送信リトライ失敗時の `result["error"]` は `str(e) or type(e).__name__` を保存するよう修正。

### 検証

```bash
docker exec keikakun_app-backend-1 pytest tests/api/v1/test_withdrawal_requests.py tests/api/v1/test_auth.py::TestCookieAuthentication::test_logout_clears_cookie
```

結果:

```text
18 passed in 106.55s
```

```bash
docker exec keikakun_app-backend-1 pytest tests/api/v1/test_withdrawal_requests.py tests/api/v1/test_employee_action_requests.py tests/api/v1/test_inquiry_endpoints.py tests/api/v1/test_notices.py tests/api/v1/test_auth.py::TestCookieAuthentication::test_logout_clears_cookie
```

結果:

```text
59 passed, 14 warnings in 425.03s
```

```bash
docker exec keikakun_app-backend-1 pytest tests/services/test_calendar_service.py::TestCalendarService::test_sync_pending_events_with_api_error tests/utils/test_email_utils.py::TestSendEmailWithRetry::test_all_retries_fail
```

結果:

```text
2 passed in 20.41s
```

### 結論

退会処理/MFA設定後に見えていた 403 の主因は、退会ロジックや app_admin 権限判定ではなく、Cookie 認証の状態変更リクエストが CSRF middleware で先に拒否されること。

本番フロントは `http` wrapper を通る限り CSRF token を取得して送るため、退会リクエスト API 呼び出し自体は修正済み方針に合っている。今後の追加 API でも、Cookie 認証の状態変更を直接 `fetch` しないこと、テストでは Cookie 認証時に CSRF token を明示することを徹底する。
 +  where 403 = <Response [403 Forbidden]>.status_code
FAILED tests/api/v1/test_auth.py::TestCookieAuthentication::test_cookie_attributes_in_*** - RuntimeError: SECRET_KEY must be configured for ***
FAILED tests/api/v1/test_auth.py::TestCookieAuthentication::test_cookie_domain_in_*** - RuntimeError: SECRET_KEY must be configured for ***
FAILED tests/api/v1/test_role_change_requests.py::test_create_role_change_request_employee_to_manager - assert 403 == 201
 +  where 403 = <Response [403 Forbidden]>.status_code
FAILED tests/api/v1/test_role_change_requests.py::test_create_role_change_request_employee_to_owner - assert 403 == 201
 +  where 403 = <Response [403 Forbidden]>.status_code
FAILED tests/api/v1/test_role_change_requests.py::test_create_role_change_request_manager_to_owner - assert 403 == 201
 +  where 403 = <Response [403 Forbidden]>.status_code
FAILED tests/api/v1/test_role_change_requests.py::test_create_role_change_request_same_role - assert 403 == 400
 +  where 403 = <Response [403 Forbidden]>.status_code
FAILED tests/api/v1/test_role_change_requests.py::test_approve_role_change_request_as_manager - assert 403 == 200
 +  where 403 = <Response [403 Forbidden]>.status_code
FAILED tests/api/v1/test_role_change_requests.py::test_approve_role_change_request_as_owner - assert 403 == 200
 +  where 403 = <Response [403 Forbidden]>.status_code
FAILED tests/api/v1/test_role_change_requests.py::test_approve_role_change_request_already_approved - assert 403 == 400
 +  where 403 = <Response [403 Forbidden]>.status_code
FAILED tests/api/v1/test_role_change_requests.py::test_reject_role_change_request - assert 403 == 200
 +  where 403 = <Response [403 Forbidden]>.status_code
FAILED tests/api/v1/test_role_change_requests.py::test_delete_pending_role_change_request - assert 403 == 204
 +  where 403 = <Response [403 Forbidden]>.status_code
FAILED tests/api/v1/test_role_change_requests.py::test_delete_approved_role_change_request_fails - assert 403 == 400
 +  where 403 = <Response [403 Forbidden]>.status_code
FAILED tests/api/v1/test_withdrawal_requests.py::test_create_withdrawal_request_as_owner - assert 403 == 201
 +  where 403 = <Response [403 Forbidden]>.status_code
FAILED tests/api/v1/test_withdrawal_requests.py::test_create_withdrawal_request_empty_title - assert 403 == 422
 +  where 403 = <Response [403 Forbidden]>.status_code
FAILED tests/api/v1/test_withdrawal_requests.py::test_create_withdrawal_request_empty_reason - assert 403 == 422
 +  where 403 = <Response [403 Forbidden]>.status_code
FAILED tests/api/v1/test_withdrawal_requests.py::test_approve_withdrawal_request_as_app_admin - assert 403 == 200
 +  where 403 = <Response [403 Forbidden]>.status_code
FAILED tests/api/v1/test_withdrawal_requests.py::test_approve_withdrawal_request_not_found - assert 403 == 404
 +  where 403 = <Response [403 Forbidden]>.status_code
FAILED tests/api/v1/test_withdrawal_requests.py::test_approve_withdrawal_request_already_processed - assert 403 == 400
 +  where 403 = <Response [403 Forbidden]>.status_code
FAILED tests/api/v1/test_withdrawal_requests.py::test_reject_withdrawal_request_as_app_admin - assert 403 == 200
 +  where 403 = <Response [403 Forbidden]>.status_code
FAILED tests/api/v1/test_withdrawal_requests.py::test_reject_withdrawal_request_not_found - assert 403 == 404
 +  where 403 = <Response [403 Forbidden]>.status_code
FAILED tests/services/test_calendar_service.py::TestCalendarService::test_sync_pending_events_with_api_error - AssertionError: assert 'API Error' in 'GoogleCalendarAPIError'
 +  where 'GoogleCalendarAPIError' = <app.models.calendar_events.CalendarEvent object at 0x7ffaf4657bf0>.last_error_message
FAILED tests/utils/test_email_utils.py::TestSendEmailWithRetry::test_all_retries_fail - AssertionError: assert 'Exception' == 'Permanent failure'

  - Permanent failure
  + Exception
FAILED tests/utils/test_email_utils.py::TestSendAndLogEmail::test_send_and_log_failure - AssertionError: assert 'Exception' == 'Send failed'

  - Send failed
  + Exception
==== 45 failed, 1893 passed, 90 skipped, 191 warnings in 1217.48s (0:20:17) ====
