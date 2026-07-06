# 現時点のセキュリティリスク一覧

作成日: 2026-07-02

参照:

- `md_files_design_note/task/todo/refactor/maintainability/log_policy.md`
- `md_files_design_note/task/todo/refactor/maintainability/review/maintainability_research_full_review_20260702.md`
- Backend security PR: https://github.com/nto300002/keikakun_back/pull/74

## 前提

本ファイルは、現時点で把握しているセキュリティリスクを実装タスクへ落とし込むための一覧。PR #74 で一部の機密ログは削減済みだが、未対応リスクは残っている。

依存パッケージCVE、DAST/SAST、実本番ログ確認はこの一覧の対象外。

## Critical

現時点でCritical扱いの新規リスクはなし。

直近でCriticalだったTOTPコード値・現在有効なTOTPコードのログ出力は、PR #74 の対象として修正済み。

## High

### 13. 本番で SECRET_KEY 未設定時に既知のデフォルト値へフォールバックする

対象:

- `k_back/app/core/security.py`

リスク:

- `os.getenv("SECRET_KEY", "test_secret_key_for_pytest")` が複数箇所にあり、本番で `SECRET_KEY` が未設定でも既知のデフォルト値でJWT署名・検証が成立する可能性がある。
- `ENCRYPTION_KEY` も同様に、MFA secret等の暗号化キーとして扱う場合は本番未設定を許容すべきではない。
- 本番環境変数の設定漏れが認証基盤全体の破綻につながるため、High扱いとする。

対応方針:

- productionでは `SECRET_KEY` / `ENCRYPTION_KEY` 未設定時にアプリ起動を失敗させる。
- test/developmentのみ明示的にテスト用デフォルト値を許可する。
- 本番デプロイ前チェックで、Cloud Run等の実行環境に必要secretが設定されていることを確認する。

本番環境での確認方法:

- production環境の環境変数/Secret Manager参照に `SECRET_KEY` と `ENCRYPTION_KEY` が設定されていることを確認する。
- 一時的な検証環境で `ENVIRONMENT=production` かつ `SECRET_KEY` 未設定にした場合、起動失敗することを確認する。
- 本番ログにsecret値そのものは出さず、起動成功/失敗のみで確認する。

### 14. refresh_token がレスポンスボディでJSへ返っている

対象:

- `k_back/app/api/v1/endpoints/auths.py`

リスク:

- access token は httpOnly Cookie に設定されているが、refresh token はレスポンスボディで返っており、ブラウザJSから参照可能になる。
- XSS、ブラウザ拡張、サポート時の画面共有、frontend error reporting等を経由してrefresh tokenが露出すると、長めのセッション継続に悪用される可能性がある。

対応方針:

- refresh tokenも httpOnly / Secure / SameSite Cookie に寄せる。
- もしくはrefresh token方式を廃止し、短命access token + 再ログイン/MFA導線へ寄せる。
- 現行方式を継続する場合は、frontendで保存しないこと、ログ・console・エラー収集へ渡さないことをテスト化する。

本番環境での確認方法:

- ログインAPIの本番レスポンスボディに `refresh_token` が含まれないことを確認する。
- `Set-Cookie` にrefresh tokenを載せる場合は `HttpOnly; Secure; SameSite` が付いていることを `curl -i` またはブラウザDevToolsで確認する。
- frontendのlocalStorage/sessionStorageにrefresh tokenが保存されていないことを確認する。

### 1. Cookie認証の状態変更endpointにCSRF検証が一貫適用されていない

対象例:

- `k_back/app/api/v1/endpoints/employee_action_requests.py`
- `k_back/app/api/v1/endpoints/welfare_recipients.py`
- `k_back/app/api/v1/endpoints/staffs.py`
- `k_back/app/api/v1/endpoints/assessment.py`
- `k_back/app/api/v1/endpoints/notices.py`

リスク:

- Cookie認証ではブラウザがCookieを自動送信するため、CSRF攻撃で状態変更だけ成立する可能性がある。
- frontendは `X-CSRF-Token` を送る実装があるが、backendの検証依存が全endpointに付いていない。

対応方針:

- `POST` / `PUT` / `PATCH` / `DELETE` endpointへ原則 `Depends(validate_csrf)` を追加する。
- Bearer認証のみを想定するAPIだけ例外として明文化する。
- endpoint一覧をテスト化し、CSRF依存漏れを検出する。

### 2. エラーレスポンスに内部例外文字列が残る

対象例:

- `HTTPException(detail=f"...{str(e)}")`
- `detail=...format(error=str(e))`

リスク:

- DB制約エラー、外部APIエラー、接続情報、内部実装名、入力値がレスポンス本文に混ざる可能性がある。
- ログ削減済みでも、APIレスポンス経由で内部情報が利用者・攻撃者に見える。

対応方針:

- 利用者向けdetailは固定文言にする。
- 内部調査用には安全な `error_type` のみログ出力する。
- `rg "str\\(e\\)|format\\(error=" k_back/app` で棚卸しする。

## Medium

### 15. MFA一時トークンを localStorage に保存している

対象:

- `k_front/lib/token.ts`

リスク:

- MFA一時トークンは短命だが、`localStorage` に保存されるためXSS発生時に取得される。
- ブラウザを閉じても残る可能性があり、MFA完了/失敗/離脱時の削除漏れがあると不要に露出時間が延びる。

対応方針:

- 可能ならMFA一時トークンも httpOnly Cookie 化する。
- Cookie化が大きい変更になる場合は、暫定的に `sessionStorage` へ縮小する。
- MFA完了、MFA失敗、ログアウト、MFA画面離脱、ログイン画面再表示時に削除されることをテストする。

本番環境での確認方法:

- MFAが必要なアカウントでログインし、DevTools Application タブで `localStorage` に `temporary_token` が残らないことを確認する。
- 暫定対応で `sessionStorage` を使う場合も、MFA完了後・失敗後・ログアウト後に削除されることを確認する。
- consoleやエラー収集にtemporary tokenが出ないことを確認する。

### 3. CORS production設定でVercel preview regexと検証用ヘッダーを許可している

対象:

- `k_back/app/main.py`

リスク:

- production APIが広いpreview originを許可している。
- `x-vercel-protection-bypass` をproduction CORS許可ヘッダーに残す必要性が未確認。
- `allow_credentials=True` とCookie認証を併用しているため、許可originは最小化すべき。

対応方針:

- productionではpreview regexを削除、または明示allowlistへ変更する。
- preview環境が必要な場合はpreview用backendを分ける。
- `x-vercel-protection-bypass` のproduction許可要否を確認する。

### 4. Google Calendar / deadline通知 / メール本文に利用者名が含まれる設計

対象:

- Google Calendarイベントtitle / description
- 更新期限メール本文
- push通知本文
- アプリ内通知本文

リスク:

- Google Calendarやメール配送先など、アプリ外部に利用者名・期限種別が渡る。
- ログではなく仕様上のデータ送信リスクであり、同意・設定・表示文言の整理が必要。

対応方針:

- 外部連携先へ利用者名を出すかを仕様として決める。
- 事業所単位で「外部カレンダーに個人名を含める/含めない」設定を検討する。
- `.ics` / アプリ内カレンダー / Google縮退方針の別issueで扱う。

### 5. webhook_event.payload にStripe raw payloadを保存している

対象:

- Stripe webhook event保存処理
- `webhook_events.payload`

リスク:

- customer id、subscription id、請求関連の識別子がDBに保存される。
- DB閲覧権限や管理画面表示経由で外部サービスIDが漏れる可能性がある。

対応方針:

- 保存するpayloadを必要最小限に絞る。
- raw payloadを保存する場合は保持期間と閲覧権限を定義する。
- 管理画面へ表示する場合はマスキングする。

### 6. 監査ログにメール変更の旧/新メールが保存される

対象:

- staff email change audit log

リスク:

- 監査用途として妥当だが、監査ログ閲覧者がメール変更履歴を広く閲覧できる。
- メールアドレスは個人情報として扱う必要がある。

対応方針:

- 監査ログ閲覧権限をapp_admin等に限定する。
- UI表示時は必要に応じてマスキングする。
- 保持期間とエクスポート可否を決める。

### 7. frontend console.error がAPIエラーオブジェクトを出力している

対象例:

- `k_front/lib/http.ts`
- `k_front/lib/dal.ts`
- `k_front/components/protected/profile/NotificationSettings.tsx`
- `k_front/app/(protected)/recipients/[id]/page.tsx`
- `k_front/components/protected/admin/PlanTab.tsx`

リスク:

- 共有端末、画面共有、サポート時にAPIエラー詳細や内部状態が見える。
- error objectにレスポンス本文や個人情報が含まれる場合、不要な露出になる。

対応方針:

- consoleへerror objectをそのまま渡さない。
- UIにはtoast/error stateで固定文言を出す。
- 本番ビルドでconsole削除を検討するが、開発中も個人情報を出さない方針を優先する。

### 8. MFA初回設定レスポンスでsecret_key / qr_code_uriを返す

対象:

- MFA enrollment API

リスク:

- 仕様上必要なレスポンスだが、TLS、キャッシュ禁止、frontendログ禁止が前提。
- ブラウザキャッシュ、proxy、console、エラー収集ツール経由で漏れるとMFA設定を乗っ取られる。

対応方針:

- MFA enrollmentレスポンスに `Cache-Control: no-store` を付ける。
- frontend側でsecret/QR URIをconsoleや永続ストレージに保存しないことをテスト/レビューで固定する。
- 一定時間後に再表示不可とする導線を明確にする。

### 12. セキュリティヘッダーが明示設定されていない

対象:

- `k_front/next.config.ts`
- `k_back/app/main.py`
- 本番ドメイン配信側の設定

本番ドメイン配信側とは:

- ブラウザへ最終的なHTTPレスポンスを返す、アプリコード外側の配信レイヤーを指す。
- frontendでは Vercel の本番デプロイ設定、Vercel headers/redirects、独自ドメイン設定が該当する。
- backendでは Cloud Run、API Gateway、ロードバランサ、CDN、リバースプロキシなど、`api.keikakun.com` 相当のドメインでレスポンスを中継・終端する層が該当する。
- アプリでヘッダーを設定していても、この配信レイヤーで上書き・削除・未付与になる場合があるため、本番URLへ直接 `curl -I` などで確認する必要がある。

リスク:

- `Content-Security-Policy` がない場合、XSS発生時の被害範囲を抑えにくい。
- `X-Frame-Options` または `Content-Security-Policy: frame-ancestors` がない場合、クリックジャッキング対策が弱い。
- `X-Content-Type-Options: nosniff` がない場合、MIME sniffing による想定外実行の余地が残る。
- `Referrer-Policy` がない場合、外部遷移時にURL query tokenや内部パスが参照元として送られる可能性がある。
- `Strict-Transport-Security` がない場合、HTTPS強制のブラウザ側保護が弱い。
- `Permissions-Policy` がない場合、カメラ・マイク・位置情報など未使用ブラウザ機能の利用制御が明示されない。

対応方針:

- frontendは `next.config.ts` の `headers()` で共通セキュリティヘッダーを設定する。
- backendは FastAPI middleware でAPIレスポンスに必要なセキュリティヘッダーを付与する。
- CSPはまず緩めに導入し、外部画像、Stripe、Google、Vercel、API接続先を洗い出して段階的に厳格化する。
- 本番ドメイン配信側でヘッダーが上書きされないか、production URLに対して `curl -I` で確認する。
- frontend/backendの両方で、期待ヘッダーが返ることをテストまたは運用チェックリスト化する。

本番環境での確認方法:

- frontend本番URLに対して `curl -I https://www.keikakun.com` を実行し、以下が返ることを確認する。
  - `Content-Security-Policy`
  - `X-Frame-Options` または `Content-Security-Policy: frame-ancestors`
  - `X-Content-Type-Options: nosniff`
  - `Referrer-Policy`
  - `Strict-Transport-Security`
  - `Permissions-Policy`
- backend本番URLに対して `curl -I https://api.keikakun.com/api/v1/...` を実行し、APIレスポンスにも必要なヘッダーが返ることを確認する。
- 現時点ではコストと運用複雑性を考慮し、API Gateway / ロードバランサは未導入とする。
- アプリ規模、外部公開範囲、攻撃面、監査要件が大きくなった段階で、Cloud Armor、API Gateway、ロードバランサ、WAF/CDN等のネットワーク側防御を追加検討する。

### 16. PDFアップロードのサーバー側サイズ制限・実体検証が弱い

対象:

- `k_back/app/api/v1/endpoints/support_plans.py`

リスク:

- frontendでは10MB制限があるが、backendでは `content_type == "application/pdf"` 確認後に全量 `read()` している。
- frontend制限は迂回可能なため、巨大ファイルによるメモリ負荷、MIME偽装、PDF以外の混入リスクが残る。
- 成果物PDFは業務データを含むため、アップロード時の検証と保存時のアクセス制御を明確にする必要がある。

対応方針:

- backendで10MB等のサイズ上限を強制する。
- `Content-Type` だけでなく、拡張子とPDFマジックバイト `%PDF-` を確認する。
- S3保存前にファイル名をサニタイズし、保存名はUUID主体にする。
- 必要に応じてウイルススキャン/無害化を別タスク化する。

本番環境での確認方法:

- 10MB超のPDFアップロードがbackendで拒否されることを確認する。
- `Content-Type: application/pdf` だが実体がPDFでないファイルが拒否されることを確認する。
- 正常なPDFは従来通りアップロード・再アップロード・ダウンロードできることを確認する。

### 17. GoogleサービスアカウントJSONのアップロード制限が弱い

対象:

- `k_back/app/schemas/calendar_account.py`
- `k_front/components/protected/admin/AdminMenu.tsx`
- `k_front/components/protected/admin/GoogleIntegrationTab.tsx`

リスク:

- 必須フィールド確認はあるが、サイズ上限、`private_key` 形式、`client_email` 形式、想定外フィールドの扱いが限定的。
- サービスアカウントJSONは秘密鍵を含むため、ブラウザ、APIリクエスト、バリデーションエラー、DB、ログ、サポート手順の全経路で機密情報として扱う必要がある。
- Google Calendar連携は将来的な廃止・縮退候補でもあるため、追加投資とリスク低減のバランスを検討する。

対応方針:

- backendでJSONサイズ上限を設定する。
- `type == service_account`、`private_key` のPEM形式、`client_email` の形式、必須フィールドのみを検証する。
- バリデーションエラーにJSON本文やprivate key断片を含めない。
- UIではファイル名表示に留め、JSON本文やprivate keyを表示・console出力しない。
- Google Calendar連携を継続する場合のみ、保存・更新・削除・ローテーション手順を運用ドキュメント化する。

本番環境での確認方法:

- 不正JSON、巨大JSON、`type` が `service_account` でないJSON、private key形式が不正なJSONが拒否されることを確認する。
- 正常なサービスアカウントJSONでは接続テストが成功し、画面・ログ・エラーレスポンスにprivate keyが出ないことを確認する。
- Google Calendar連携を使わない事業所では未設定のまま主要機能が利用できることを確認する。

## Low

### 9. バリデーションエラーのレスポンスにinput値が残る

対象:

- `k_back/app/main.py` の `RequestValidationError` handler

リスク:

- HTML escape済みでも、422レスポンスに入力値そのものが返る。
- パスワード、token、個人情報を含むフィールドでは不要な反射になる。

対応方針:

- productionでは `input` をレスポンスから除外する。
- developmentだけ詳細を返す場合は環境分岐する。

### 10. 運用・検証scriptsがPIIや外部IDを出す可能性がある

対象例:

- `fix_double_encoded_mfa_secrets.py`
- Stripe確認・test clock系scripts
- E2E/cleanup系scripts

リスク:

- 手元実行、CI、Cloud Run job等で標準出力にstaff email、Stripe customer/subscription id、復号エラー詳細が残る。

対応方針:

- scriptsの標準出力も `log_policy.md` の対象に含める。
- secret/password/private keyは出力禁止。
- 外部IDは必要な場合だけ末尾数文字にマスクする。

### 11. ASGI/access log側でURL queryやdetailが出る可能性がある

対象:

- Uvicorn / Cloud Run access log
- proxy / CDN / Vercel / Cloud Build log

リスク:

- アプリログを抑えても、URL queryにtokenが含まれる設計ではaccess logに残る。
- 特に password reset / email verification token の扱いに注意が必要。

対応方針:

- tokenをquery stringで受けるAPIを棚卸しする。
- 可能ならPOST bodyへ移す。
- query継続の場合は短命化、単回使用、ログ確認を必須にする。

## 本番環境での確認方法の分類

### CLIでも実行可能な確認

- `SECRET_KEY` / `ENCRYPTION_KEY` の本番設定確認
  - Cloud Run等の環境変数/Secret Manager参照をCLIで確認する。
  - secret値そのものは出力せず、設定有無と参照先だけを確認する。

- production起動失敗確認
  - 一時的な検証環境で `ENVIRONMENT=production` かつ必須secret未設定にし、アプリが起動失敗することを確認する。
  - 本番実環境でsecretを外す確認は行わない。

- refresh tokenのレスポンス確認
  - `curl -i` でログインAPIを叩き、レスポンスボディに `refresh_token` が含まれないことを確認する。
  - Cookie化する場合は `Set-Cookie` に `HttpOnly; Secure; SameSite` が付くことを確認する。

- セキュリティヘッダー確認
  - `curl -I https://www.keikakun.com` でfrontendのレスポンスヘッダーを確認する。
  - `curl -I https://api.keikakun.com/api/v1/...` でbackend APIのレスポンスヘッダーを確認する。
  - `Content-Security-Policy`, `X-Content-Type-Options`, `Referrer-Policy`, `Strict-Transport-Security`, `Permissions-Policy`, `X-Frame-Options` または `frame-ancestors` を確認する。

- CORS確認
  - `curl` で `Origin` と `Access-Control-Request-Headers` を指定し、productionでpreview originや `x-vercel-protection-bypass` が許可されないことを確認する。

- APIレスポンスの内部例外文字列確認
  - 不正入力や不正ファイルをAPIへ送り、レスポンスに `str(e)` 由来のDBエラー、外部APIエラー、内部パス、secret断片が出ないことを確認する。

- PDFアップロード検証
  - CLIから10MB超ファイル、MIME偽装ファイル、PDFマジックバイトを持たないファイルをアップロードし、backendで拒否されることを確認する。
  - 正常なPDFはアップロード成功することを確認する。

- GoogleサービスアカウントJSON検証
  - CLIから不正JSON、巨大JSON、`type` が `service_account` でないJSON、private key形式が不正なJSONを送り、拒否されることを確認する。
  - エラーレスポンスにJSON本文やprivate key断片が出ないことを確認する。

- URL query token / access log確認
  - password reset / email verification等のURL query tokenがaccess logに残るかをCloud Run/Vercel等のログ検索で確認する。
  - ログ確認はsecret/token値そのものを共有しない。

### GUI確認が必須、またはGUIでの確認が現実的なもの

- MFA一時トークンのブラウザ保存確認
  - DevTools Application タブで `localStorage` / `sessionStorage` / Cookieを確認する。
  - MFA完了、MFA失敗、ログアウト、MFA画面離脱後に `temporary_token` が残らないことを確認する。

- refresh tokenのブラウザ保存確認
  - DevTools Application タブで `localStorage` / `sessionStorage` にrefresh tokenが保存されていないことを確認する。
  - Cookie化した場合はDevToolsで `HttpOnly`, `Secure`, `SameSite` を確認する。

- MFA enrollmentのsecret/QR表示確認
  - 画面上でsecret/QR URIが必要なタイミングだけ表示され、再表示・キャッシュ・console出力されないことを確認する。
  - QRコード表示やコピー導線はGUIで確認する。

- Google Calendar連携の実操作確認
  - 管理画面でサービスアカウントJSONをアップロードし、接続テスト、保存、更新、未設定事業所での通常利用を確認する。
  - 画面・toast・モーダル・consoleにprivate keyやJSON本文が出ないことを確認する。

- PDFアップロードの利用者導線確認
  - 管理/支援計画画面でPDFアップロード、再アップロード、ダウンロード、エラー表示の文言を確認する。
  - 業務上の正常フローが壊れていないことはGUIで確認する。

- 外部連携先へ出る個人情報の確認
  - Google Calendarイベント、メール本文、push通知、アプリ内通知に利用者名や期限種別がどう表示されるかを実画面・実通知で確認する。
  - 仕様として「外部に個人名を出す/出さない」を判断するため、GUI/受信画面での確認が必要。

- 監査ログの閲覧権限とマスキング確認
  - app_admin等でログ画面を開き、メール変更の旧/新メールが誰に見えるか、マスキング要否を確認する。

### GUI必須ではないが、GUIでも補助確認した方がよいもの

- セキュリティヘッダー
  - CLIの `curl -I` が主確認。
  - ブラウザDevTools Networkでも最終レスポンスにヘッダーが付いているか補助確認する。

- CORS
  - CLIでpreflight確認可能。
  - 実ブラウザで本番frontendから正常操作でき、preview/不許可originからは通らないことを補助確認する。

- CSRF
  - CLI/APIテストでCSRF tokenなしの状態変更が拒否されることを確認可能。
  - 実ブラウザで通常操作が壊れていないことはGUIで補助確認する。

### 現時点のネットワーク側セキュリティ方針

- 現時点ではコストと運用複雑性を考慮し、API Gateway / ロードバランサは未導入とする。
- まずはアプリ側で、Cookie/CSRF/CORS/セキュリティヘッダー/入力検証/ログ削減を優先する。
- アプリ規模、外部公開範囲、攻撃面、監査要件が大きくなった段階で、Cloud Armor、API Gateway、ロードバランサ、WAF/CDN等のネットワーク側防御を追加検討する。

## 修正済みとして扱う項目

- TOTPコード値、sanitized token、現在有効なTOTPコードのログ出力削除。
- MFA secret長、復号成功詳細、ユーザーメール付きMFAログの削減。
- backendの一部debug `print()` 削除。
- VAPID private key / E2E password をscripts標準出力で隠す対応。
- push endpoint断片、raw request data、traceback全文の一部削減。

## 次の推奨PR

1. productionで `SECRET_KEY` / `ENCRYPTION_KEY` 未設定時に起動失敗させるPR。
2. refresh tokenのhttpOnly Cookie化、またはrefresh token方式の廃止/用途明文化PR。
3. CSRF適用漏れ修正PR。
4. `HTTPException(detail=str(e))` 系の固定文言化PR。
5. production CORS allowlist見直しPR。
6. frontend console error object削減PR。
7. MFA enrollment no-store / frontend保存禁止確認PR。
8. MFA temporary tokenのlocalStorage利用縮小PR。
9. frontend/backend/security delivery layer のセキュリティヘッダー付与・本番URL確認PR。
10. PDFアップロードのbackendサイズ制限・実体検証PR。
11. GoogleサービスアカウントJSONのサイズ/形式検証PR。

## CLI確認結果

確認日: 2026-07-02

確認方法:

```bash
rg -n "@(router|app)\.(post|put|patch|delete)" k_back/app/api/v1/endpoints -g '*.py'
rg -n "validate_csrf|Depends\(deps\.validate_csrf\)|Depends\(validate_csrf\)" k_back/app/api/v1/endpoints k_back/app/api/deps.py -g '*.py'
rg -n "str\(e\)|str\([a-zA-Z_]+_error\)|format\(error=|detail=f|traceback\.format_exc|exc_info=True|logger\.exception" k_back/app -g '*.py'
rg -n "allow_origin_regex|x-vercel-protection-bypass|allow_credentials|allowed_origins|allow_headers" k_back/app/main.py
rg -n "console\.(log|debug|info|warn|error)" k_front/app k_front/components k_front/lib -g '*.ts' -g '*.tsx'
rg -n "secret_key|qr_code_uri|Cache-Control|no-store|MFA|mfa" k_back/app/api/v1/endpoints/mfa.py k_back/app/schemas k_front/app k_front/components -g '*.py' -g '*.ts' -g '*.tsx'
rg -n "token[: ]|verification_token|reset_token|verify-reset|request\.query_params" k_back/app k_front/app k_front/components -g '*.py' -g '*.ts' -g '*.tsx'
rg -n "webhook_event|payload=|event\.data|customer|subscription" k_back/app/api/v1/endpoints/billing.py k_back/app/services/billing_service.py k_back/app/crud/crud_webhook_event.py k_back/app/models -g '*.py'
```

### 確認1: CSRF適用状況

結果:

- 状態変更endpointは多数存在する。
- 個別endpointで `Depends(validate_csrf)` が付いているのは、確認時点では主に `admin_announcements.py`、`offices.py`、`messages.py`。
- ただし、現作業ツリーの `k_back/app/main.py` には `csrf_cookie_auth_middleware()` が追加されている。
  - Cookie認証かつ `POST` / `PUT` / `PATCH` / `DELETE` の場合にCSRF検証する。
  - `Authorization: Bearer` がある場合はスキップする。
  - exemptは `/api/v1/csrf-token` と `/api/v1/billing/webhook`。

判定:

- CLI上は、個別依存ではなくmiddlewareで一括適用する修正が入っていることを確認。
- ただし `git status` では `k_back/app/main.py` は未コミット。現時点では「作業ツリーでは修正済み、PR未作成/未マージ」扱い。
- リスク項目「CSRF適用漏れ」は「修正PR待ち」に更新するのが妥当。

残確認:

- CSRFなしCookie付き状態変更が403になるテスト。
- Bearer認証は従来通り通るテスト。
- billing webhookがCSRF対象外で通るテスト。

### 確認2: 例外文字列のレスポンス混入

結果:

- `str(e)` / `format(error=str(e))` はまだ残る。
- 主な残存箇所:
  - `k_back/app/services/google_calendar_client.py`
  - `k_back/app/services/calendar_service.py`
  - `k_back/app/api/v1/endpoints/calendar.py`
  - `k_back/app/schemas/calendar_account.py`

判定:

- リスク項目「エラーレスポンスに内部例外文字列が残る」はCLIで残存確認済み。
- Google Calendar系に集中しているため、Calendar error response固定文言化PRとして分けやすい。

### 確認3: CORS production設定

結果:

- 現作業ツリーの `k_back/app/main.py` では、production時に `allow_origin_regex = None` になる修正を確認。
- productionの `allowed_headers` から `x-vercel-protection-bypass` は削除されている差分を確認。
- productionの `allowed_origins` から `https://api.keikakun.com` も削除されている差分を確認。

判定:

- CORS production allowlistリスクは作業ツリーでは修正済み。
- ただし `k_back/app/main.py` は未コミット。現時点では「修正PR待ち」。

### 確認4: frontend console

結果:

- `console.error` は複数残る。
- 多くは `console.error('Operation failed')` の固定文言へ置換済み。
- 一部、固定文言だが日本語の詳細文言が残る。
  - `リクエストの取得に失敗しました`
  - `PDF一覧の取得に失敗しました`
  - `メールアドレス変更トークンが見つかりません`
  - `カレンダー設定の再取得に失敗`
- CLI出力上、`console.error(..., err)` のようなerror object直接出力は大きく減っている。

判定:

- frontend console error objectリスクは「部分修正済み」。
- 次は `console.error` 自体を本番で許容するか、固定文言でも削除するかを方針決定する。

### 確認5: MFA secret / QR URIの扱い

結果:

- backend:
  - `mfa/enroll` は `secret_key` と `qr_code_uri` を返す。
  - admin MFA enable / enable-all も `secret_key` と `qr_code_uri` を返す。
  - `Cache-Control: no-store` は該当endpointで確認できなかった。
- frontend:
  - `MfaSetupForm` は `qr_code_uri` / `secret_key` をstateに保持する。
  - `LoginForm` は管理者設定済みMFA初回セットアップ用に `sessionStorage` へ `mfa_qr_code_uri` / `mfa_secret_key` を保存する。
  - `MfaFirstSetupForm` は検証成功後に `sessionStorage.removeItem()` で削除する。

判定:

- MFA secret / QR URIリスクはCLIで残存確認済み。
- 特に `sessionStorage` へMFA secretを保存する設計は要再検討。
- 最低限、短時間TTL相当の扱い、画面離脱時削除、no-store、console禁止を追加確認する。

### 確認6: tokenのURL query利用

結果:

- password reset:
  - frontend `ResetPasswordForm.tsx` は `verify-reset-token` をPOST bodyで検証するコメントあり。
  - backendにはGET `/verify-reset-token` とPOST `/verify-reset-token` が併存している。
- email verification:
  - `k_front/app/auth/verify-email/page.tsx` は `?token=` を読む。
  - `k_front/app/auth/verify-email-change/page.tsx` は `?token=` を読む。
  - `k_back/app/core/mail.py` は `verify-email-change?token=...` を生成する。

判定:

- URL query tokenリスクはCLIで残存確認済み。
- password resetはPOST body化が進んでいるが、GET版が残っている。
- email verification / email changeはquery token設計が継続している。

### 確認7: Stripe webhook payload保存

結果:

- `webhook_events.payload` 保存は残る。
- `customer.subscription.created` では `payload=subscription_data` としてraw subscription dataを保存している。
- updated/deleted/payment failed系では `customer_id` などを含むpayloadを保存する箇所がある。
- webhook受信ログにも `customer` / `subscription` / `payment_intent` / `invoice` を出す箇所がある。

判定:

- Stripe payload保存リスクはCLIで残存確認済み。
- ログ出力とDB保存の両面で、Stripe外部IDのマスキング/最小化が必要。

### 確認8: 監査ログのメール保持

結果:

- `EmailChangeRequestModel` は `old_email` / `new_email` を保持する。
- `staff_profile_service.py` はメール変更完了時の `AuditLog` に `old_value=old_email` / `new_value=new_email` を保存する。
- メール通知では新メールをマスクする処理があるが、監査ログ保存値は平文。

判定:

- 監査ログメール保持リスクはCLIで残存確認済み。
- 監査用途として保存自体は妥当だが、表示時マスキング・閲覧権限・保持期間を決める必要がある。

### 確認9: validation error input反射

結果:

- `k_back/app/main.py` の `RequestValidationError` handler は `error["input"]` をsanitizeしてレスポンスへ含める。
- production分岐や `input` 除外は確認できなかった。

判定:

- validation input反射リスクはCLIで残存確認済み。

### CLI確認後の更新判定

| No | リスク | CLI判定 | 状態 |
| --- | --- | --- | --- |
| 1 | CSRF適用漏れ | middleware修正を確認 | 作業ツリー修正済み、PR待ち |
| 2 | 例外文字列レスポンス | 残存確認 | 未対応 |
| 3 | production CORS | production regex無効化・ヘッダー削除を確認 | 作業ツリー修正済み、PR待ち |
| 4 | 外部通知/Calendar本文の利用者名 | CLIだけでは仕様妥当性判断不可 | 要仕様判断 |
| 5 | Stripe payload保存 | 残存確認 | 未対応 |
| 6 | 監査ログメール保持 | 残存確認 | 要方針決定 |
| 7 | frontend console.error | 固定文言中心で残存 | 部分修正済み |
| 8 | MFA secret / QR URI | secret_key / qr_code_uri返却とsessionStorage保存を確認 | 未対応 |
| 9 | validation input反射 | 残存確認 | 未対応 |
| 10 | scripts出力 | 一部修正済み、全scripts未確認 | 継続確認 |
| 11 | URL query token | email系query tokenとreset GET版残存確認 | 未対応 |
