# DB保存値・管理画面表示の閲覧権限/マスク設計 TODO

作成日: 2026-07-02

## 結論

ログ出力のマスキング対応とは別 issue で進める。

理由:

- ログ修正は「意図せず出力される情報」を止めるリファクタリング寄りの作業。
- 本件は「DBに保存された機密・個人情報を、誰が、どの画面/APIで、どの粒度まで閲覧できるか」を決める仕様・権限設計。
- 監査ログ、webhook payload、問い合わせ、スタッフ情報、退会処理、app-admin 管理画面など複数領域にまたがる。
- 表示マスクだけでなく、APIレスポンス、CSV/export、管理者権限、監査用途、運用時の例外対応まで含むため、影響範囲が広い。

## issue 化チェックリスト

別 issue で進める前提で、現在のログマスキング対応には含めない。

- [x] ログ出力の秘匿化とは別スコープとして切り出す。
- [x] DB保存値そのものの削除・変換は今回の対応対象外にする。
- [x] app-admin / owner / manager / employee の閲覧権限設計を別途行う。
- [x] APIレスポンス・管理画面表示・export のマスク仕様を同一 issue で扱う。
- [x] audit log details / webhook payload の raw 表示禁止方針を別途設計する。
- [x] 詳細閲覧、マスク解除、一時権限、監査記録は運用設計として扱う。
- [x] TDD実装は、権限表と表示仕様が確定してから開始する。
- [ ] issue 本文へこの TODO を転記する。
- [ ] 対象API/画面の棚卸し結果を issue に追記する。
- [ ] 権限別の期待レスポンス例を issue に追記する。
- [ ] backend/frontend のテスト観点を issue に追記する。

## 2026-07-04 現状調査メモ

結論: この TODO の本体である「DB保存値を API/管理画面で権限に応じてマスクする」実装は、まだほぼ未着手。

進んでいる範囲:

- [x] ログ出力・標準出力の秘匿化とは別スコープとして切り出し済み。
- [x] `app.utils.privacy_utils.mask_email` / `mask_name` と単体テストは存在する。
- [x] 一部ログ出力では例外本文や token payload を直接出さない修正が入っている。
- [x] 退会済みスタッフ向けには `archived_staffs.anonymized_full_name` / `anonymized_email` がある。

未実装または未適用の範囲:

- [ ] 監査ログ API は `details` をそのまま返している。
  - Backend: `k_back/app/api/v1/endpoints/admin_audit_logs.py`
  - Schema: `k_back/app/schemas/audit_log.py`
  - Frontend: `k_front/components/protected/app-admin/tabs/AuditLogTab.tsx` が `JSON.stringify(log.details)` をそのまま表示。
- [ ] `WebhookEvent` schema は `payload` をそのままレスポンスに含める形。
  - Schema: `k_back/app/schemas/webhook_event.py`
  - 現時点で app-admin 向け webhook 一覧/詳細 API は見当たらないが、schema を使った API 追加時に raw payload が露出するリスクが残る。
- [ ] app-admin 問い合わせ API は一覧・詳細とも本文、送信者名、メール、IP、User-Agent、delivery_log を生値で返す。
  - Backend: `k_back/app/api/v1/endpoints/admin_inquiries.py`
  - Schema: `k_back/app/schemas/inquiry.py`
  - Frontend: `k_front/components/admin/inquiry/InquiryDetail.tsx`
- [ ] app-admin 事務所詳細 API は事務所住所・電話・メール、所属スタッフ氏名・メールを生値で返す。
  - Backend: `k_back/app/api/v1/endpoints/admin_offices.py`
  - Schema: `k_back/app/schemas/office.py`
- [ ] 利用者一覧 API は `WelfareRecipientResponse` を使っており、一覧でも氏名・ふりがな・生年月日・性別・住所・電話・緊急連絡先・障害情報を返し得る。
  - Backend: `k_back/app/api/v1/endpoints/welfare_recipients.py`
  - Schema: `k_back/app/schemas/welfare_recipient.py`
- [ ] 利用者詳細 API は同一事業所の全職員が詳細情報を参照可能。owner/manager/employee 間で項目別マスクは未実装。
- [ ] 承認リクエスト API は `request_data` / `original_request_data` をそのまま返し得る。
  - Backend schema: `k_back/app/schemas/approval_request.py`
  - Backend schema: `k_back/app/schemas/employee_action_request.py`
  - 利用者作成・更新申請では、氏名、住所、障害情報、緊急連絡先などが `request_data` に含まれる可能性がある。
- [ ] `crud.audit_log.create_log(details=...)` は呼び出し元の `details` を保存前に共通マスクしていない。
  - Backend: `k_back/app/crud/crud_audit_log.py`
  - 表示時マスクだけでなく、保存前に危険キーを `<redacted>` 化する共通 sanitizer の要否を決める必要がある。
- [ ] 事務所更新監査ログは `old_values` / `new_values` をそのまま保存している。
  - Backend: `k_back/app/api/v1/endpoints/offices.py`
  - 住所、電話、メールなどの事務所連絡先が監査ログ details に残る可能性がある。
- [ ] Push購読 API は `endpoint` をレスポンスに含めている。
  - Backend: `k_back/app/schemas/push_subscription.py`
  - `endpoint` は個人端末・ブラウザと紐づく識別子のため、通常表示では末尾数文字または `<registered>` へのマスク候補。
- [ ] メール送信失敗の監査ログは宛先、件名、エラー本文を保存している。
  - Backend: `k_back/app/utils/email_utils.py`
  - `recipient`, `subject`, `error` はメールアドレス、問い合わせ件名、外部メールサービスの詳細エラーを含み得る。
- [ ] MFA初期化レスポンスは `secret_key`, `qr_code_uri`, `recovery_codes` を返す。
  - Backend: `k_back/app/api/v1/endpoints/mfa.py`
  - 発行直後の一時表示としては必要だが、ログ、監査ログ、再取得API、画面保持に残さない方針を明文化する必要がある。
- [ ] CSV/export は明示的な汎用 export API は見当たらないが、PDF deliverable download と一括取得 API があるため別途棚卸しが必要。

現時点の進捗感:

- ログマスキング: 部分対応済み。
- 共通マスク関数: 最小限あり。
- APIレスポンスのマスキング: ほぼ未実装。
- app-admin / owner / manager / employee の権限別表示設計: 未実装。
- raw details / raw payload の表示用 serializer 分離: 未実装。
- backend/frontend のマスキングテスト: utility 単体以外は未実装。

## 2026-07-04 ログ加工・マスキング追加調査

基準:

- OWASP Logging Cheat Sheet は、ログに直接記録しない、または記録前に削除・マスク・ハッシュ化すべきデータとして、session id、access token、機微な個人情報、認証パスワード、DB接続文字列、暗号鍵、支払いカード/銀行情報、高分類情報を挙げている。
  - 参照: https://cheatsheetseries.owasp.org/cheatsheets/Logging_Cheat_Sheet.html#data-to-exclude
- OWASP API Security 2023 API3 は、APIレスポンスは必要なプロパティだけを選別し、business requirement 上の最小データに抑えることを推奨している。ログの request/response body 出力にも同じ考え方を適用する。
  - 参照: https://owasp.org/API-Security/editions/2023/en/0xa3-broken-object-property-level-authorization/
- NIST SP 800-92 は、組織全体でログ管理基盤・ログ管理プロセスを整備し、ログを保護しながら運用する必要性を示している。
  - 参照: https://csrc.nist.gov/pubs/sp/800/92/final

追加で見つかったログ加工・マスキング候補:

- [ ] Stripe Customer Portal Session 作成失敗ログで `stripe_customer_id` を生値出力している。
  - Backend: `k_back/app/api/v1/endpoints/billing.py`
  - 該当: `Stripe Customer Portal Session creation failed ... stripe_customer_id=%s`
  - 対応案: `customer_present=True/False` または `cus_***末尾4` にする。原則は生値禁止。
- [ ] Stripe webhook 受信ログで `event_id`, `object_id`, `customer`, `subscription`, `payment_intent`, `invoice` を生値出力している。
  - Backend: `k_back/app/api/v1/endpoints/billing.py`
  - 該当: `[Webhook:%s] Received event ... customer=%s subscription=%s payment_intent=%s invoice=%s`
  - 対応案: event id は相関IDとして許容する場合も hash/末尾4に統一。customer/subscription/payment/invoice は `<present>` または末尾4。
- [ ] Stripe webhook 未対応イベントログでも同じ Stripe ID 群を生値出力している。
  - Backend: `k_back/app/api/v1/endpoints/billing.py`
  - 対応案: 受信ログと同じ sanitizer を使う。
- [ ] billing service の webhook 詳細ログに `latest_invoice` など Stripe object id が生値で出る。
  - Backend: `k_back/app/services/billing_service.py`
  - 該当: `Subscription created payload`, `Subscription updated payload`, error log の `latest_invoice`
  - 対応案: Stripe ID sanitizer を共通化し、`latest_invoice_present=True/False` または末尾4のみ。
- [ ] webhook event DB payload はログではないが、運用調査時に raw payload をログ出力しやすい構造のため、serializer と logger helper を分ける必要がある。
  - Backend: `k_back/app/schemas/webhook_event.py`, `k_back/app/services/billing_service.py`
  - 対応案: `sanitize_webhook_payload_for_log()` と `sanitize_webhook_payload_for_display()` を分ける。
- [ ] Playwright/E2E helper が利用者登録 API の response body 先頭500文字を CI ログに出している。
  - Frontend: `k_front/e2e/helpers/recipient-form.ts`
  - 該当: `console.log("[recipient-form] response body: ...")`
  - リスク: validation error やレスポンス内容に利用者氏名、住所、電話、障害情報が含まれると CI ログへ流れる。
  - 対応案: status、request id、error code のみ。body は `sanitizeForCiLog()` 経由で known sensitive keys を `<redacted>`。
- [ ] Playwright/E2E auth fixture が `/auth/token` の response body 先頭300文字を CI ログに出している。
  - Frontend: `k_front/e2e/fixtures/auth.ts`
  - 該当: `console.log("[auth] /auth/token body...")`
  - リスク: access token / refresh token / MFA temporary token がレスポンス body に含まれる場合、CI ログに漏れる。
  - 対応案: body 出力禁止。status と error code のみ。どうしても必要な場合は token-like values を正規表現で `<redacted_token>`。
- [ ] Playwright/E2E auth fixture が cookie 名と domain 一覧を出している。
  - Frontend: `k_front/e2e/fixtures/auth.ts`
  - 該当: `全 Cookie 一覧: ${allCookies.map(c => `${c.name}@${c.domain}`)...}`
  - 値は出していないため低リスクだが、認証 cookie の存在・domain 構成が CI ログに残る。必要時のみ debug flag 配下にする。
- [ ] Frontend の `console.error(apiErr)` 系で Error object に request/response body が含まれる場合の再確認が必要。
  - 例: `k_front/hooks/usePushNotification.ts`
  - 対応案: production build では generic message のみ。debug 時も endpoint/auth key/token/body は sanitizer 経由。
- [ ] Push subscription endpoint / p256dh / auth key は現状 logger で raw 出力していないが、API docstring と E2E/console error 経由で出やすい。
  - Backend: `k_back/app/api/v1/endpoints/push_subscriptions.py`, `k_back/app/crud/crud_push_subscription.py`
  - 対応案: endpoint は hash または末尾8、`auth` は常に `<redacted>`。logger helper にルール化する。
- [ ] email 送信 helper は recipient email を delivery_log / audit details に残す設計がある。logger は主に error type だが、今後ログに delivery_log を出さないルールが必要。
  - Backend: `k_back/app/utils/email_utils.py`, `k_back/app/models/inquiry.py`
  - 対応案: email はログでは `mask_email()`、delivery_log 表示も app-admin serializer 経由。

ログ用 sanitizer の最低要件:

- token-like: JWT, refresh token, temporary token, reset token, verification token は常に `<redacted_token>`。
- secret-like: password, passphrase, TOTP secret, backup code, QR code URI, VAPID auth key, p256dh/auth, S3 secret, DB URL は常に `<redacted_secret>`。
- Stripe-like: `cus_`, `sub_`, `evt_`, `in_`, `pi_`, `cs_` は原則 `<present>`。相関が必要な場合のみ `prefix_***last4`。
- PII: email は `mask_email()`、氏名は `mask_name()`、電話/住所/IP/User-Agent は用途別に `<redacted>` または hash。
- response/request body: 原則ログ禁止。CI/debug で必要な場合も allowlist key のみ。

## 今回対応しないこと

- audit log details / webhook payload のDB保存形式変更。
- app-admin 画面の表示項目変更。
- staff / welfare recipient / office の一覧・詳細レスポンス再設計。
- CSV/export の権限設計とマスク実装。
- マスク解除フロー、理由入力、一時権限、監査証跡の実装。

## 2026-07-04 追加調査メモ: ログ/標準出力のマスキング候補

結論: API/画面の表示マスクとは別に、ログ・標準出力・E2Eデバッグ出力にも追加で加工/マスキング候補が残っている。

優先度高:

- [ ] Stripe Customer Portal 作成失敗ログで `stripe_customer_id` を生値出力している。
  - Backend: `k_back/app/api/v1/endpoints/billing.py`
  - `StripeError` 分岐で `stripe_customer_id=%s` に `billing.stripe_customer_id` を渡している。
  - `has_stripe_customer_id=%s`、`stripe_customer_id_present=%s`、または末尾4桁のみへ変更する。
- [ ] E2E/Playwright のデバッグログが API response body をそのまま標準出力する。
  - Frontend: `k_front/e2e/helpers/recipient-form.ts`
  - Frontend: `k_front/e2e/fixtures/auth.ts`
  - 利用者登録レスポンス、ログインレスポンス本文に氏名、住所、電話、障害情報、token類、エラーdetailが混ざる可能性がある。
  - CIログに残るため、status / error_type / redacted body keys のみへ変更する。
- [ ] E2E/Playwright の thrown error に API response body を含めている。
  - Frontend: `k_front/e2e/helpers/recipient-form.ts`
  - Frontend: `k_front/e2e/fixtures/auth.ts`
  - test failure時のCIログへ生レスポンスが残るため、本文は `sanitizeE2EApiBody()` のような共通関数で redaction してから埋め込む。
- [ ] frontend Push購読解除失敗時に `apiErr` オブジェクトを `console.warn` に渡している。
  - Frontend: `k_front/hooks/usePushNotification.ts`
  - エラーオブジェクトが unsubscribe URL の `endpoint=` query やレスポンス本文を保持する可能性がある。
  - `error_type` / 固定文言のみへ変更する。

優先度中:

- [ ] 管理者・E2E作成系スクリプトが staff email / full_name / staff_id / office_id を標準出力する。
  - Backend: `k_back/scripts/create_e2e_owner.py`
  - Backend: `k_back/scripts/create_app_admin.py`
  - Backend: `k_back/scripts/set_admin_passphrase.py`
  - 手元実行だけでなくCIログや共有ターミナル履歴に残る可能性があるため、email/name はマスク、IDは必要時のみ `--verbose` に寄せる。
- [ ] billing検証/テスト補助スクリプトが billing_id / office_id / customer_id / subscription_id を標準出力する。
  - Backend: `k_back/scripts/test_batch_processing.py`
  - Backend: `k_back/scripts/batch_trigger_setup.py`
  - Backend: `k_back/scripts/test_clock_quick_cycle.sh`
  - Backend: `k_back/scripts/test_clock_one_liner.sh`
  - Backend: `k_back/scripts/test_billing_status_transition.sh`
  - 一部は `<hidden>` 対応済みだが、未対応箇所が混在している。外部IDは `<present>` または末尾4桁、内部IDは必要性を確認する。
- [ ] Google Calendar 系の例外文字列が API detail に混入する。
  - Backend: `k_back/app/api/v1/endpoints/calendar.py`
  - Backend: `k_back/app/services/calendar_service.py`
  - Backend: `k_back/app/services/google_calendar_client.py`
  - service account JSON、Google API error、event id、calendar id が `str(e)` 経由でレスポンスや上位ログに混ざる可能性がある。
  - Google Calendar廃止/縮退判断とは別に、残す場合は固定文言 + `error_type` のみにする。
- [ ] `create_app_admin.py` / `set_admin_passphrase.py` の存在有無エラーが email をそのまま出す。
  - Backend: `k_back/scripts/create_app_admin.py`
  - Backend: `k_back/scripts/set_admin_passphrase.py`
  - アカウント存在確認ログとして使われると user enumeration 情報になるため、emailはマスクする。

既存TODOと重複するが、ログ観点でも再確認が必要:

- [ ] `k_back/app/utils/email_utils.py` はメール送信失敗の `last_error = str(e)` を監査ログ details に保存し得るため、API表示マスクだけでなく保存前加工も検討する。
- [ ] `k_back/app/api/v1/endpoints/staffs.py` の `detail=str(e)` は RateLimitExceededError の安全な業務文言として残しているが、例外型が変わった場合に内部文字列が出ないようテストで固定する。
- [ ] `k_back/app/api/v1/endpoints/billing.py` の duplicate key 判定で `str(e)` を条件判定に使っている。ログ出力は型名のみだが、将来ログ追加時にDB詳細を出さないよう注意する。

## 2026-07-04 追加確認メモ: 追加で見つかったログ/標準出力マスキング候補

確認コマンド:

- `rg -n "logger\\.(debug|info|warning|warn|error|exception)\\(|logging\\.(debug|info|warning|warn|error|exception)\\(" k_back/app k_back/scripts`
- `rg -n "console\\.(log|warn|error|debug|info)\\(" k_front`
- `rg -n "print\\(|echo |RAISE NOTICE" k_back/scripts k_back/*.py k_back/tests k_front/e2e`

追加で対応候補に入れるもの:

- [ ] 手動 billing 修正スクリプトが Stripe 外部IDと固定対象IDを生値出力している。
  - Backend: `k_back/fix_billing_record.py`
  - `billing_id`, `office_id`, `stripe_customer_id`, `stripe_subscription_id` を `print` している。
  - ファイル内 docstring と SQL 確認文にも具体IDが直書きされている。
  - 一時復旧用スクリプトであっても共有ログ・ターミナル履歴・リポジトリ履歴に残るため、固定IDの除去、外部IDは `<present>` または末尾4桁表示へ変更する。
- [ ] 通知設定確認スクリプトが staff id と `notification_preferences` JSON をそのまま標準出力する。
  - Backend: `k_back/check_notification_preferences.py`
  - `staffs LIMIT 1` の結果を `json.dumps` で出している。
  - 通知設定には連絡手段・閾値・有効/無効など個人設定が含まれるため、サンプル表示は件数/キー一覧/boolean有無のみにする。
- [ ] MFA二重エンコード修復スクリプトが MFA secret 保有スタッフの `staff_id` と処理結果を標準出力する。
  - Backend: `k_back/scripts/fix_double_encoded_mfa_secrets.py`
  - 平文 secret は出していないが、MFA secret 保有者・復号可否・再設定が必要な対象を識別できる。
  - 通常表示は件数サマリーのみ、個別 staff_id は `--verbose` 時のみ、または末尾数文字へマスクする。
- [ ] 認証依存処理の debug/warning ログが `sub` / `user_id` / `office_id` を生値出力している。
  - Backend: `k_back/app/api/deps.py`
  - `TokenData created with sub=%s`, `Parsed user_id=%s`, `User not found for id`, `Deleted user attempted access`, deleted office access の `user_id` / `office_id`。
  - token 自体は出していないが、認証失敗ログと内部IDが紐づくため、通常ログでは `user_id_present=true`、`user_id_suffix` 程度に抑える。
- [ ] MFA初回検証ログが temporary token 由来の `user_id` を生値出力している。
  - Backend: `k_back/app/api/v1/endpoints/auths.py`
  - `Token validated, user_id`, `User not found`, `MFA not enabled`, `User already verified` など。
  - MFA状態とスタッフIDが紐づくため、IDはマスクし、結果は `user_found`, `mfa_enabled`, `already_verified` の boolean/固定文言へ寄せる。
- [ ] 物理削除クリーンアップログが削除対象の事務所名を生値出力している。
  - Backend: `k_back/app/services/cleanup_service.py`
  - `Physically deleting office: id=..., name=..., deleted_at=...`
  - 退会/削除済み事務所名が運用ログに残るため、`office_id` はマスク、`name` は出さない。件数と削除日時だけにする。
- [ ] 期限通知バッチの debug/error ログが事務所名、office id、staff id を出力している。
  - Backend: `k_back/app/tasks/deadline_notification.py`
  - alert なしの debug で `Office {office.name} (ID: {office.id})`、Web Push 成否で `staff_id` を出している。
  - 通知対象・通知失敗対象の推測につながるため、通常ログは件数・threshold・失敗種別のみ、個別IDはマスクまたは debug verbose 限定にする。
- [ ] Playwright global teardown が削除対象利用者IDを失敗時の Error に含める。
  - Frontend: `k_front/e2e/global-teardown.ts`
  - `DELETE /welfare-recipients/${r.id} → ${resp.status()}` を rejected reason として CIログに出す。
  - E2Eデータでも利用者IDが残るため、`recipient_id_suffix` または件数/HTTP status のみにする。
- [ ] backend テストのデバッグ `print` が request/response body をそのまま出力する。
  - Backend: `k_back/tests/api/v1/test_auth_session_persistence.py`
  - Backend: `k_back/tests/api/v1/test_recipients.py`
  - Backend: `k_back/tests/api/v1/test_dashboard.py`
  - Cookie、利用者作成 payload、dashboard response に氏名・住所・障害情報・token/cookie情報が混ざる可能性がある。
  - 失敗時ログは status、エラーコード、redacted keys のみにする共通 helper を用意する。

## 対象

### 1. 監査ログ

対象候補:

- `audit_logs.details`
- staff削除、email変更、billing変更、withdrawal 実行結果
- app-admin の監査ログ一覧/詳細表示

確認したいリスク:

- email、氏名、Stripe ID、外部連携ID、リクエスト本文が監査ログに保存・表示される。
- app-admin で必要以上に詳細が見える。
- APIレスポンスではマスクされていても、DB payload をそのまま返す実装があると漏洩する。

現状:

- `admin_audit_logs.py` で `details: log.details` をそのまま返している。
- `AuditLogTab.tsx` で `JSON.stringify(log.details)` をそのまま表示している。
- `actor_name`, `ip_address`, `user_agent` も app-admin に常時表示される。

### 2. Stripe / billing webhook payload

対象候補:

- `webhook_events.payload`
- `billing.stripe_customer_id`
- `billing.stripe_subscription_id`
- billing関連監査ログ

確認したいリスク:

- Stripe customer/subscription id は秘密鍵ではないが、外部サービス上の追跡識別子。
- 管理画面・API・運用ログで無制限に表示すると、外部アカウントとの紐付け情報が漏れる。

現状:

- webhook 保存 schema は `payload` を保持し、レスポンス schema にも含めている。
- app-admin 向け webhook 表示 API は現時点では見当たらない。
- billing webhook のログには Stripe customer/subscription/payment/invoice/object id が出る箇所があるため、ログマスキング側の継続確認も必要。

### 3. 問い合わせ/メッセージ

対象候補:

- 問い合わせ本文、返信本文、送信者 email/name
- app-admin 問い合わせ詳細
- ユーザー側メッセージ一覧/詳細

確認したいリスク:

- app-admin 全員が問い合わせ本文・メールアドレスを常時閲覧できる設計でよいか。
- 返信に必要な情報と一覧表示に必要な情報の粒度が同じになっていないか。

現状:

- app-admin の問い合わせ一覧で `content`, `sender_name`, `sender_email` を返している。
- app-admin の問い合わせ詳細で `ip_address`, `user_agent`, `admin_notes`, `delivery_log` も返している。
- 一覧と詳細の返却粒度が大きく分離されていない。

### 4. staff / welfare recipient / office

対象候補:

- staff email/name
- welfare recipient 氏名、フリガナ、生年月日、障害情報、家族/医療情報
- office 情報、請求状態

確認したいリスク:

- 一覧APIで詳細情報を返しすぎている。
- app-admin、owner、manager、employee の権限境界が画面/APIごとに統一されていない。
- CSV/export や一括取得APIが存在する場合、表示マスクを迂回する可能性がある。

現状:

- app-admin 事務所詳細で所属スタッフの `full_name`, `email` を返している。
- 利用者一覧が詳細レスポンス schema を流用しており、住所・電話・緊急連絡先・障害情報まで一覧レスポンスに含まれる可能性がある。
- 利用者詳細は同一事業所の全スタッフが全項目を参照可能。

### 5. アセスメント / 支援計画 / 添付PDF

対象候補:

- アセスメントの家族構成、医療情報、通院歴、就労歴、課題分析。
- 支援計画・モニタリング・PDF deliverable の本文、ファイル名、presigned download URL。
- `assessment` の全件取得 API / 一括取得 service。

確認したいリスク:

- 利用者基本情報よりもセンシティブな医療・家族・就労情報が、同一事業所内の全 staff に無制限表示される。
- PDF download URL が権限確認後に発行されても、URL 自体の有効期限・ログ出力・画面表示で漏れる可能性がある。
- 一覧やダッシュボード用途で詳細情報まで返していないか確認が必要。

### 6. MFA / 認証補助情報

対象候補:

- MFA 一括有効化結果に含まれる QR code URI / backup codes。
- MFA audit log の IP address / User-Agent。
- password reset / email change audit log。

確認したいリスク:

- MFA 初期化時の secret, QR code, backup codes は一度しか表示しない前提でも、app-admin/owner 画面やログ・監査ログに残ると重大。
- 認証系 audit log の IP/User-Agent は個人情報相当として扱う必要がある。

### 7. 通知 / メッセージ / Push購読

対象候補:

- notices / messages の title, content, sender/recipient staff name。
- push_subscriptions endpoint / auth keys / endpoint URL。
- deadline alerts の利用者名、期限情報。

確認したいリスク:

- 通知本文に利用者名や申請内容が埋め込まれており、一覧・Push・メールで広く表示される。
- Push購読 endpoint は個人端末と紐づく識別子のため raw 表示・ログ出力を避ける。

## 方針案

### 権限レベル

- `self`: 自分自身の情報。
- `same_office_admin`: 同一事業所の owner/manager。
- `app_admin_support`: サポート対応に必要な最小情報。
- `app_admin_sensitive`: 本人確認や障害対応で一時的に詳細閲覧が必要な情報。
- `system`: batch/webhook/internal のみ。

### 表示粒度

- 一覧: 原則マスク済み/最小項目。
- 詳細: 権限と用途に応じて段階的に開示。
- 監査ログ: デフォルトはマスク。詳細閲覧は追加権限または明示操作。
- export: 別権限。実行履歴を監査ログに残す。

### マスク例

- email: `na***@example.com`
- 氏名: `山田 太郎` -> `山田 *`
- Stripe ID: `cus_...` / `sub_...` -> `<present>` または末尾4桁だけ
- webhook payload: key単位で allowlist 表示
- request body / details: raw JSON 返却禁止。表示用 schema に変換する。
- phone: `090-1234-5678` -> `090-****-5678`
- address: 市区町村以降を `***` にする、または権限がない場合は `<redacted>`
- Push endpoint: 末尾6-8文字のみ表示、または `<registered>`
- MFA secret / recovery codes: 再表示禁止。表示後は `<issued_once>` / `<redacted>`
- email送信エラー: 外部サービスの生エラー本文は `error_type` / `status_code` / `<redacted>` に正規化する。

## TODO

### P0: 現状調査

- [x] app-admin 画面/APIで表示している監査ログ項目を洗い出す。
- [x] `webhook_events.payload` を返す API / 画面があるか確認する。
- [x] audit log details をそのまま返している API があるか確認する。
- [x] staff/welfare recipient/office の一覧APIと詳細APIで返却項目差分を確認する。
- [ ] assessment / support plan / PDF download の返却項目差分を確認する。
- [ ] notices / messages / push subscription の raw 識別子表示を確認する。
- [ ] MFA 一括有効化結果と backup codes の表示・ログ保存有無を確認する。
- [ ] export/CSV/一括取得機能の有無を確認する。
- [ ] approval_requests / employee_action_requests の `request_data` がAPIレスポンスや画面で生表示されていないか確認する。
- [ ] `crud.audit_log.create_log()` 呼び出し元の `details` に email/name/phone/address/token/external_id が含まれないか棚卸しする。
- [ ] 事務所更新監査ログの `old_values` / `new_values` に連絡先情報が含まれるか確認する。
- [ ] メール送信失敗監査ログの `recipient` / `subject` / `error` の保存・表示範囲を確認する。
- [ ] Push購読 `endpoint` のレスポンス、ログ、画面表示の有無を確認する。
- [ ] MFA secret / QR code / recovery codes が初回表示後に再取得・ログ出力・監査ログ保存されないか確認する。
- [ ] Stripe/Billing関連ログで `stripe_customer_id` / `stripe_subscription_id` / `invoice_id` / `payment_intent_id` が生出力されないか確認する。
- [ ] E2E/Playwrightログで API response body / URL query / token / 利用者情報がCIログへ出ないか確認する。
- [ ] 運用スクリプトの標準出力で email/name/office_id/billing_id/Stripe ID が生出力されないか確認する。
- [ ] frontend `console.warn/error` に Error オブジェクトや API error object をそのまま渡していないか確認する。
- [ ] Google Calendar系の `str(e)` が API detail / 上位ログへ伝播しないか確認する。

### P0: 表示用 schema の分離

- [ ] DB保存用 payload と API表示用 payload を分ける。
- [ ] 監査ログ表示用 serializer を作る。
- [ ] 監査ログ保存前 sanitizer を作るか、表示時 serializer のみで対応するかを決める。
- [ ] webhook payload 表示用 serializer を作る。
- [ ] approval request / employee action request の `request_data` 表示用 serializer を作る。
- [ ] inquiry list/detail 表示用 serializer を分ける。
- [ ] welfare recipient list/detail 表示用 serializer を分ける。
- [ ] assessment list/detail 表示用 serializer を分ける。
- [ ] app-admin office list/detail 表示用 serializer を分ける。
- [ ] push subscription 表示用 serializer で `endpoint` をマスクする。
- [ ] email delivery log / email failure audit details 表示用 serializer を作る。
- [ ] E2E/CIログ用の `sanitizeE2EApiBody()` / `sanitizeE2EErrorMessage()` を作る。
- [ ] 運用スクリプト用の `mask_cli_value()` または既存 `privacy_utils` のCLI利用方針を決める。
- [ ] 外部連携IDログ用の `mask_external_id()` を Stripe / Google Calendar / Push endpoint に適用する。
- [ ] allowlist 方式で表示可能 key を定義する。
- [ ] 未定義 key は `<redacted>` にする。
- [ ] `mask_phone`, `mask_address`, `mask_external_id`, `redact_dict_by_keys` を共通utilityに追加する。

### P1: 権限チェック

- [ ] app-admin の監査ログ閲覧権限を定義する。
- [ ] app-admin の問い合わせ詳細閲覧権限を定義する。
- [ ] billing/webhook 詳細閲覧権限を定義する。
- [ ] owner/manager/employee の一覧/詳細/API権限を表にする。
- [ ] employee が閲覧できる利用者詳細・アセスメント・支援計画項目を owner/manager と分けるか決める。
- [ ] app-admin が閲覧できる事務所スタッフ email / office contact / billing identifiers を用途別に分ける。
- [ ] MFA secret / QR code / backup codes は発行直後の対象者または owner/manager の一時表示に限定する。
- [ ] approval request の `request_data` 詳細閲覧権限を owner/manager/employee/app_admin で分ける。
- [ ] Push購読 `endpoint` の生値閲覧を本人または system のみに制限する。
- [ ] メール送信失敗 details の生値閲覧を system / app_admin_sensitive に限定する。
- [ ] 権限不足時は 403、存在秘匿が必要な場合は 404 を使い分ける。

### P1: テスト

- [ ] audit log API が email/name/Stripe ID を生値で返さない backend test。
- [ ] webhook payload API が allowlist 以外を返さない backend test。
- [ ] app-admin でも通常権限では sensitive field がマスクされる backend test。
- [ ] 追加権限を持つ場合だけ詳細を見られる backend test。
- [ ] app-admin inquiry list が本文全文・email・IP/User-Agent を返さない backend test。
- [ ] welfare recipient list が住所・電話・緊急連絡先・障害詳細を返さない backend test。
- [ ] assessment list/API が医療・家族・就労詳細を不要に返さない backend test。
- [ ] app-admin office detail が staff email を権限に応じてマスクする backend test。
- [ ] MFA 一括有効化結果の secret / backup codes が保存済みレスポンスやログに再露出しない backend test。
- [ ] approval request API が `request_data.original_request_data` の住所・電話・障害情報を権限なしで生返却しない backend test。
- [ ] audit log create/display が `old_values` / `new_values` の email/phone/address をマスクする backend test。
- [ ] push subscription API が `endpoint` を通常レスポンスで生返却しない backend test。
- [ ] email failure audit details が `recipient` / `subject` / 外部エラー本文を生返却しない backend test。
- [ ] MFA secret / QR code / recovery codes が初回発行レスポンス以外で再取得できない backend test。
- [ ] billing portal/session失敗ログが `stripe_customer_id` を生出力しない backend test。
- [ ] Google Calendar系 API エラーdetailが `str(e)` 由来の内部文字列を返さない backend test。
- [ ] E2E helper の失敗ログが response body の token/email/name/phone/address をマスクする frontend test。
- [ ] Push購読解除失敗時に endpoint/query を console に出さない frontend test。
- [ ] 運用スクリプトが email/name/Stripe ID をマスクして標準出力する script test。
- [ ] frontend 表示で masked value が崩れない test。

### P2: 運用設計

- [ ] 詳細閲覧が必要な障害対応フローを定義する。
- [ ] 詳細閲覧イベントを監査ログに残す。
- [ ] export 実行時の理由入力、実行者、対象範囲、件数を記録する。
- [ ] マスク解除の一時権限/期限を検討する。

## 完了条件

- DBには業務上必要な値を保持しつつ、API/画面では権限に応じてマスクされる。
- raw payload / raw details をそのまま返す API がない。
- app-admin でも最小権限の原則に沿って閲覧範囲が制限される。
- 監査ログ・webhook payload・問い合わせ・staff/welfare recipient でテストが追加されている。

## 安全基準と達成判定

この TODO の安全基準:

- OWASP Logging Cheat Sheet の `Data to exclude` に該当する値を、アプリログ・CIログ・監査ログ表示・運用ログに生値で出さない。
- OWASP API Security API3 の考え方に従い、API/画面/ログでは用途に必要なプロパティだけを allowlist で出す。
- NIST SP 800-92 の考え方に従い、ログは調査可能性を残しつつ、ログ自体を機微情報の二次保管場所にしない。
- 具体的には、次を満たすこと:
  - token / secret / password / MFA secret / backup code / QR code URI は 0 件露出。
  - request body / response body / raw webhook payload / raw audit details の汎用出力は 0 件。
  - email/name/phone/address/IP/User-Agent/Stripe ID は用途別に mask/hash/present flag へ変換。
  - app-admin でも raw 表示は追加権限・理由・監査記録なしでは不可。
  - backend/frontend/CI のテストで代表的な token, email, Stripe ID, recipient PII がログ・レスポンスに出ないことを検証。

指定済み範囲をマスキングすれば安全基準を超えるか:

- 現在この文書に列挙した範囲をすべて実装し、上記の sanitizer / serializer / test まで入れば、OWASP の最低ラインは満たせる。
- ただし「超える」とまでは言えない。理由は、ログ保護にはマスキングだけでなく、ログ保存先のアクセス制御、保存期間、削除、監査、CI artifacts の閲覧権限、debug flag 管理が必要なため。
- 安全基準を明確に超えるには、追加で以下を完了条件に含める:
  - production では debug log を無効化し、debug flag で body 出力を有効化できない設計にする。
  - Cloud Logging / GitHub Actions logs / Vercel logs の閲覧権限を最小化する。
  - ログ保存期間と削除ルールを定義する。
  - sanitizer を通さない `logger.*`, `console.*`, `print()` を CI で検出する静的チェックを入れる。
  - 障害調査で raw data が必要な場合は、一時権限・理由入力・監査ログを必須にする。

## 今回のログマスキング対応との境界

今回対応済みの範囲:

- ログ出力・標準出力・一部APIエラー本文から機密値や個人情報を出さない。
- reset token のフロント検証を query string から POST body に変更。

この issue で扱う範囲:

- DBに保存された値の閲覧権限。
- APIレスポンスや管理画面での表示マスク。
- raw payload / audit details の表示設計。
- export や運用時の詳細閲覧ルール。

- アセスメントページ(recipient個別)のタブ ライト/ダーク対応
