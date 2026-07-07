# 06 テスト / 静的チェック / 完了条件

作成日: 2026-07-04

## 対象

マスキングとログ削除系タスクの受け入れテスト、静的チェック、完了条件を定義する。

## Backend Test

- [ ] audit log API が email/name/Stripe ID を生値で返さない。
- [ ] webhook payload API が allowlist 以外を返さない。
- [ ] app-admin でも通常権限では sensitive field がマスクされる。
- [ ] 追加権限を持つ場合だけ詳細を見られる。
- [x] app-admin inquiry list が本文全文・email を返さない。
- [x] app-admin inquiry detail が email/IP/User-Agent/delivery_log を生返却しない。
- [x] welfare recipient list が住所・電話・緊急連絡先・障害詳細を返さない。
- [ ] assessment list/API が医療・家族・就労詳細を不要に返さない。
- [x] app-admin office detail が staff email を通常表示でマスクする。
- [ ] MFA 一括有効化結果の secret / backup codes が保存済みレスポンスやログに再露出しない。
- [ ] approval request API が `request_data.original_request_data` の住所・電話・障害情報を権限なしで生返却しない。
- [x] audit log create/display が `old_values` / `new_values` の email/phone/address をマスクする。
- [x] push subscription API が `endpoint` を通常レスポンスで生返却しない。
- [ ] email failure audit details が `recipient` / `subject` / 外部エラー本文を生返却しない。
- [ ] MFA secret / QR code / recovery codes が初回発行レスポンス以外で再取得できない。
- [x] billing portal/session失敗ログが `stripe_customer_id` を生出力しない。
- [ ] Google Calendar系 API エラー detail が `str(e)` 由来の内部文字列を返さない。

## Frontend / E2E Test

- [ ] E2E helper の失敗ログが response body の token/email/name/phone/address をマスクする。
- [ ] `/auth/token` response body がCIログに出ない。
- [ ] 利用者登録 response body がCIログに生値で出ない。
- [ ] Push購読解除失敗時に endpoint/query を console に出さない。
- [ ] frontend 表示で masked value が崩れない。
- [ ] 監査ログ画面で raw `details` を `JSON.stringify` 表示しない。
- [ ] 問い合わせ一覧・詳細で権限別に表示が切り替わる。

## Script Test

- [ ] 運用スクリプトが email/name/Stripe ID をマスクして標準出力する。
- [ ] billing修復スクリプトが固定IDを直書きしない。
- [ ] MFA修復スクリプトが対象 staff_id を通常出力しない。
- [ ] notification preferences 確認スクリプトが個人設定 JSON を出さない。

## 静的チェック

初期チェック候補:

```bash
rg -n "logger\\.(debug|info|warning|error|exception)\\(.*(token|secret|password|payload|request_data|response|stripe_customer_id|stripe_subscription_id)" k_back/app k_back/scripts
rg -n "console\\.(log|debug|warn|error)\\(.*(body|token|cookie|response|apiErr|error)" k_front
rg -n "print\\(.*(token|secret|password|payload|response|email|stripe)" k_back k_front
```

実装タスク:

- [x] CI に frontend/e2e blocking の `security-log-static-check` step を追加する。
- [x] backend の危険 logger pattern を検出する。
- [x] frontend の危険 console pattern を検出する。
- [x] scripts / tests / e2e の危険 print / console pattern を検出する。
- [ ] `type(e).__name__`, `*_present`, `*_count`, sanitizer helper 経由のログは許可する。
- [ ] allowlist は理由・期限・担当者付きで管理する。
- [x] frontend/e2e で危険ログを追加すると CI が失敗する。
- [ ] backend/scripts は既存検出が残るため warning mode 継続。

## 2026-07-05 TDD再実装メモ

完了:

- Python AST ベースの `logger.*` / `print()` 検出を維持。
- `console.log/debug/warn/error` を `.js/.jsx/.ts/.tsx/.mjs/.cjs` で検出。
- `--mode block` の戻り値テストを追加。
- GitHub Actions に frontend/e2e 対象の blocking 静的チェックを追加。

現状:

- `python scripts/security_log_static_check.py --mode block ../k_front` は通過。
- `python scripts/security_log_static_check.py --mode block app scripts ../k_front` は既存 backend/scripts の検出が残るため失敗。
- backend/scripts は既存違反の棚卸しが必要なため、CIでは warning mode のまま。

確認:

```bash
docker exec keikakun_app-backend-1 pytest tests/security/test_security_log_static_check.py -q
# 5 passed

docker exec keikakun_app-backend-1 python scripts/security_log_static_check.py --mode block ../k_front
# exit 0
```

## 2026-07-06 TDD追加実装メモ

完了:

- `CRUDAuditLog.create_log()` 経由の監査ログdetailsを保存前に sanitizer に通す。
- `billing.status_changed` の details allowlist を追加し、未定義 key は `<redacted>`、Stripe ID は `<present>` に変換。
- `raw_payload` / `raw_details` / `request_body` / `response_body` は共通detailsマスクでキー単位 `<redacted>` にする。
- staff profile の名前変更・メール変更監査ログは、直接 `AuditLog(...)` 生成時点で `old_value/new_value` をマスクして保存する。
- `WelfareRecipientListResponse` の item serializer を分離し、通常一覧から住所・電話・緊急連絡先・障害詳細を除外。
- backend/scripts の security log static check を block mode で通過確認。

確認:

```bash
docker exec keikakun_app-backend-1 pytest \
  tests/utils/test_privacy_utils.py::test_mask_sensitive_details_for_display_recursively_masks_known_sensitive_keys \
  tests/crud/test_crud_audit_log.py \
  tests/crud/test_audit_log_billing.py \
  tests/api/v1/test_recipients.py::test_list_recipients_does_not_expose_contact_or_disability_details \
  tests/api/v1/test_recipients.py::test_get_recipient_by_id -q

docker exec keikakun_app-backend-1 python scripts/security_log_static_check.py \
  --mode block --allowlist-file security_log_allowlist.json app scripts

docker exec keikakun_app-backend-1 pytest \
  tests/services/test_staff_profile_service.py \
  tests/services/test_staff_profile_service_email.py -q
```

## 実装順序

1. 静的チェックを warning mode で導入し、既存違反を一覧化する。
2. E2E/CIログの response body 出力を止める。
3. Stripe / token / secret 系のアプリログを sanitizer 経由へ変更する。
4. API表示用 serializer を作る。
5. audit details / webhook payload / request_data の raw 表示を止める。
6. 権限別表示とマスク解除フローを実装する。
7. backend/frontend/E2E/script test を追加する。
8. 静的チェックを blocking mode に変更する。

## 完了条件

- [ ] DBには業務上必要な値を保持しつつ、API/画面では権限に応じてマスクされる。
- [ ] raw payload / raw details / raw request_data をそのまま返す API がない。
- [ ] app-admin でも最小権限の原則に沿って閲覧範囲が制限される。
- [ ] token / secret / password / MFA secret / backup code / QR code URI はログ・CIログ・監査ログ表示に出ない。
- [ ] request body / response body / raw webhook payload / raw audit details の汎用出力がない。
- [ ] email/name/phone/address/IP/User-Agent/Stripe ID は用途別に mask/hash/present flag へ変換される。
- [ ] production で debug body 出力を有効化できない。
- [ ] 危険ログ追加が CI で検出される。
- [ ] 一時的な例外は理由・期限・担当者付きで追跡されている。
