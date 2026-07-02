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
