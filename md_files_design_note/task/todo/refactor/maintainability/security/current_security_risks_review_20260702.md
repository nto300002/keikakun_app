# current_security_risks_20260702.md レビュー

作成日: 2026-07-02

対象:

- `md_files_design_note/task/todo/refactor/maintainability/security/current_security_risks_20260702.md`
- 現作業ツリーの `k_back`
- 現作業ツリーの `k_front`

## 総評

`current_security_risks_20260702.md` のリスク分類は概ね妥当。ただし、現作業ツリーでは一部の対策がすでに入っており、ドキュメント上の「未対応」と実装状態に差分がある。

現時点で優先度を高く維持すべきものは、`refresh_token` のレスポンスボディ返却、MFA secret/QR URIの保存・キャッシュ制御、例外文字列のAPIレスポンス混入、Google Calendar系の秘密鍵/外部連携リスク。

## High として妥当な項目

### 14. refresh_token がレスポンスボディでJSへ返っている

判定: Highのまま。

確認結果:

- `k_back/app/api/v1/endpoints/auths.py` でログイン/MFA完了時に `refresh_token` をレスポンスボディで返している。
- access tokenはhttpOnly Cookieへ寄せられているが、refresh tokenはJSから参照可能な状態。

懸念:

- XSS、ブラウザ拡張、画面共有、frontend error reporting経由で露出した場合、セッション継続に悪用される。

推奨:

- refresh tokenもhttpOnly Cookieへ移す。
- Cookie化する場合、`HttpOnly; Secure; SameSite` と削除処理をテストする。

### 2. エラーレスポンスに内部例外文字列が残る

判定: High寄りのMedium。Google Calendar系は優先して修正する。

確認結果:

- `k_back/app/services/calendar_service.py`
- `k_back/app/services/google_calendar_client.py`
- `k_back/app/api/v1/endpoints/calendar.py`
- `k_back/app/api/v1/endpoints/staffs.py`

上記に `str(e)` や `detail=str(e)` が残る。

懸念:

- Google APIエラー、DB制約、内部実装名、外部ID、入力値がレスポンスに混ざる可能性がある。

推奨:

- 利用者向けdetailは固定文言にする。
- 内部調査用はログ側で `error_type` のみに寄せる。

## 作業ツリーでは修正済み、PR/マージ状態の確認が必要な項目

### 13. 本番で SECRET_KEY 未設定時に既知のデフォルト値へフォールバックする

判定: 実装上は対策済み寄り。ただし、PR/マージ状態確認が必要。

確認結果:

- `k_back/app/core/security.py` に `get_jwt_secret()` があり、productionで `SECRET_KEY` 未設定またはテスト用値の場合に `RuntimeError` になる。
- `get_mfa_encryption_key_source()` もproductionでは `ENCRYPTION_KEY` を必須としている。

残確認:

- production起動時にこのチェックが確実に通ること。
- `app/core/csrf.py` は `SECRET_KEY` fallbackとして `"your-secret-key"` を持つため、CSRF設定側も同じ方針に揃える必要がある。

### 1. Cookie認証の状態変更endpointにCSRF検証が一貫適用されていない

判定: 作業ツリーではmiddlewareで対策済み寄り。ただし、テストとPR/マージ状態確認が必要。

確認結果:

- `k_back/app/main.py` に `csrf_cookie_auth_middleware()` があり、Cookie認証かつ `POST` / `PUT` / `PATCH` / `DELETE` でCSRF検証する。
- `/api/v1/csrf-token` と `/api/v1/billing/webhook` は除外されている。
- Bearer認証はスキップされる。

残確認:

- Cookie付き状態変更でCSRFなしは403。
- 正常frontend操作は通る。
- billing webhookはCSRFなしで通る。
- Bearer認証の既存API互換性。

### 3. CORS production設定でVercel preview regexと検証用ヘッダーを許可している

判定: 作業ツリーでは対策済み寄り。

確認結果:

- productionでは `allow_origin_regex = None`。
- productionの `allowed_headers` から `x-vercel-protection-bypass` は外れている。
- development側にはpreview regexとbypass headerが残る。

残確認:

- productionデプロイ後にpreflightで確認する。
- preview検証が必要な場合はproduction APIではなくpreview/staging APIへ分離する。

### 12. セキュリティヘッダーが明示設定されていない

判定: 作業ツリーでは対策済み寄り。ただしCSPは初期導入として緩め。

確認結果:

- `k_front/next.config.ts` にCSP、nosniff、Referrer-Policy、Permissions-Policy、X-Frame-Options、HSTSが追加されている。
- `k_back/app/main.py` にAPIレスポンス用のsecurity headers middlewareが追加されている。

注意:

- `script-src 'unsafe-inline' 'unsafe-eval'` はNext.js互換性上の初期値としては理解できるが、CSPとしては弱い。
- 本番配信層で上書き・削除されないか、`curl -I` で確認が必要。

## Mediumとして残る項目

### 15. MFA一時トークンを sessionStorage に保存している

判定: Medium。

確認結果:

- `k_front/lib/token.ts` は `temporary_token` を `sessionStorage` に保存している。
- localStorageではなくsessionStorageなので、当初記載よりリスクは下がっている。

残リスク:

- XSSがあれば取得可能。
- MFA画面離脱、失敗、再ログイン時の削除漏れは確認が必要。

推奨:

- 可能ならhttpOnly Cookie化。
- 暫定継続なら、MFA完了/失敗/離脱/ログアウト時削除のテストを追加する。

### 8. MFA初回設定レスポンスでsecret_key / qr_code_uriを返す

判定: Mediumのまま。

確認結果:

- `mfa/enroll`、admin MFA enable、enable-all、ログイン時の初回MFAセットアップで `secret_key` / `qr_code_uri` を返す。
- frontendでは `sessionStorage` に `mfa_qr_code_uri` / `mfa_secret_key` を保存する箇所がある。
- `Cache-Control: no-store` は確認できなかった。

推奨:

- MFA secret/QRを返すレスポンスに `Cache-Control: no-store` を付ける。
- 初回MFAセットアップ用の `sessionStorage` 保存を可能な限り短くし、画面離脱時削除を入れる。

### 16. PDFアップロードのサーバー側サイズ制限・実体検証が弱い

判定: 作業ツリーでは対策済み寄り。

確認結果:

- `k_back/app/api/v1/endpoints/support_plans.py` に10MB上限、chunk read、`%PDF-` マジックバイト、拡張子確認、ファイル名サニタイズが入っている。

残確認:

- 10MB超、MIME偽装、PDFでない実体の拒否テスト。
- 正常PDFのアップロード/再アップロード/ダウンロードの回帰確認。

### 17. GoogleサービスアカウントJSONのアップロード制限が弱い

判定: 部分対策済み。Mediumのまま。

確認結果:

- `k_back/app/schemas/calendar_account.py` に32KB上限、`type == service_account`、private_key PEM形式、client_email形式の検証がある。

残リスク:

- Google Calendar連携自体が縮退/廃止候補であるため、追加投資に対して運用リスクが高い。
- private keyを含むJSONの保存・更新・削除・ローテーション・閲覧権限を運用として固める必要がある。

## Lowとして妥当な項目

### 9. バリデーションエラーのレスポンスにinput値が残る

判定: LowからMedium寄り。

確認結果:

- `k_back/app/main.py` の `RequestValidationError` handlerは `input` をsanitizeして返している。

懸念:

- sanitize済みでも、password/token/private key/個人情報が422レスポンスに反射される可能性は残る。

推奨:

- productionでは `input` と `ctx.error` をレスポンスから除外する。

### 11. ASGI/access log側でURL queryやdetailが出る可能性がある

判定: LowからMedium寄り。

理由:

- password resetやemail verification等のtokenがURL queryにある場合、アプリログ以外のアクセスログに残る。
- アプリ側ログを削っても、Cloud Run/Vercel/proxyログは別経路。

推奨:

- token query利用を棚卸しする。
- 可能ならPOST body化する。
- query継続なら短命・単回使用・ログ確認を必須化する。

## ドキュメントの修正提案

- `SECRET_KEY` / `ENCRYPTION_KEY` は「未対応」ではなく「作業ツリーで対策済み、PR/マージ確認待ち」に更新する。
- CSRF/CORS/security headers/PDF upload/Google JSON validationは、作業ツリーでの対策状況を追記する。
- `MFA一時トークンを localStorage に保存` は、現状 `sessionStorage` へ変更済みのため文言を更新する。
- 次の推奨PR順は、実装状態を踏まえて以下へ更新する。

## 次の推奨順

1. refresh tokenのhttpOnly Cookie化、またはrefresh token方式の廃止/用途明文化。
2. MFA secret/QR URIの `Cache-Control: no-store` とsessionStorage削除タイミング強化。
3. Calendar系とstaff系の `str(e)` / `detail=str(e)` 固定文言化。
4. production validation errorから `input` / `ctx.error` を除外。
5. CSRF/CORS/security headers/PDF/Google JSONの作業ツリー修正をPR化し、テストを追加。
6. 外部連携先へ出る個人情報の仕様判断。
7. webhook payload、監査ログ、URL query token、scripts出力の運用ルール化。
