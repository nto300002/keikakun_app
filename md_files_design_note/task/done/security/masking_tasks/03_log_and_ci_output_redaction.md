# 03 ログ / CI / 標準出力の削除・マスキング

作成日: 2026-07-04

## 対象

アプリログ、CIログ、E2E/Playwrightデバッグ出力、運用スクリプト標準出力に機微情報を残さないためのタスク。

## 基準

- token / secret / password / MFA secret / backup code / QR code URI はログ出力禁止。
- request body / response body / raw webhook payload / raw audit details は汎用ログ出力禁止。
- Stripe ID / Push endpoint / email / phone / address / IP / User-Agent は mask/hash/present flag へ変換。

## 優先度高タスク

- [ ] Stripe Customer Portal Session 作成失敗ログの `stripe_customer_id` 生値出力を削除する。
  - Backend: `k_back/app/api/v1/endpoints/billing.py`
  - 対応: `has_stripe_customer_id` または `stripe_customer_id_present` にする。
- [ ] Stripe webhook 受信ログの `customer`, `subscription`, `payment_intent`, `invoice` 生値出力を削除する。
  - Backend: `k_back/app/api/v1/endpoints/billing.py`
  - 対応: `<present>` または末尾4桁。
- [ ] Stripe webhook 未対応イベントログも同じ sanitizer を使う。
- [ ] billing service の `latest_invoice` など Stripe object id 生値ログを削除する。
  - Backend: `k_back/app/services/billing_service.py`
- [ ] E2E/Playwright の利用者登録 API response body 出力を削除・マスクする。
  - Frontend: `k_front/e2e/helpers/recipient-form.ts`
- [ ] E2E/Playwright の `/auth/token` response body 出力を削除・マスクする。
  - Frontend: `k_front/e2e/fixtures/auth.ts`
- [ ] E2E/Playwright の thrown error に API response body を生値で含めない。
- [ ] frontend Push購読解除失敗時の `console.warn(apiErr)` を固定文言にする。
  - Frontend: `k_front/hooks/usePushNotification.ts`

## 優先度中タスク

- [ ] 管理者・E2E作成系スクリプトの staff email / full_name / staff_id / office_id 出力をマスクする。
  - `k_back/scripts/create_e2e_owner.py`
  - `k_back/scripts/create_app_admin.py`
  - `k_back/scripts/set_admin_passphrase.py`
- [ ] billing検証/テスト補助スクリプトの billing_id / office_id / customer_id / subscription_id 出力をマスクする。
  - `k_back/scripts/test_batch_processing.py`
  - `k_back/scripts/batch_trigger_setup.py`
  - `k_back/scripts/test_clock_quick_cycle.sh`
  - `k_back/scripts/test_clock_one_liner.sh`
  - `k_back/scripts/test_billing_status_transition.sh`
- [ ] Google Calendar 系の `str(e)` が API detail / 上位ログへ伝播しないよう固定文言 + `error_type` にする。
- [ ] `create_app_admin.py` / `set_admin_passphrase.py` の存在有無エラーで email を生値表示しない。
- [ ] `fix_billing_record.py` の固定ID直書きと Stripe ID 標準出力を削除する。
- [ ] `check_notification_preferences.py` の staff id / notification_preferences JSON 出力をマスクする。
- [ ] `fix_double_encoded_mfa_secrets.py` の staff_id 出力を summary または suffix にする。
- [ ] `app/api/deps.py` の user_id / office_id debug/warning log を present/suffix にする。
- [ ] MFA初回検証ログの user_id 生値出力を削除する。
- [ ] cleanup service の削除対象 office name 生値出力を削除する。
- [ ] deadline notification の office name / office id / staff id ログを件数・失敗種別に寄せる。
- [ ] Playwright global teardown の削除対象利用者ID出力を suffix または件数にする。
- [ ] backend test の debug `print` が request/response body を出さないよう共通 helper を作る。

## 実装タスク

- [ ] `mask_external_id()` を追加する。
- [ ] `redact_dict_by_keys()` を追加する。
- [ ] `sanitize_log_value()` を追加する。
- [ ] `sanitizeE2EApiBody()` を追加する。
- [ ] `sanitizeE2EErrorMessage()` を追加する。
- [ ] logger に渡す値は sanitizer 経由に統一する。
- [ ] console に Error object を直接渡さないルールを作る。
- [ ] `print()` / `echo` は script 用 mask helper 経由にする。

## 受け入れ要件

- [ ] Stripe ID がアプリログに生値で出ない。
- [ ] `/auth/token` response body が CIログに出ない。
- [ ] 利用者登録 response body が CIログに生値で出ない。
- [ ] token / secret / password / MFA secret / recovery code / QR code URI がログに出ない。
- [ ] E2E failure log に利用者住所・電話・障害情報が出ない。
- [ ] 運用スクリプトが email/name/Stripe ID をマスクして標準出力する。
- [ ] frontend production console に request/response body や API error object が出ない。
