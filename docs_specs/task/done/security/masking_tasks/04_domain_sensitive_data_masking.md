# 04 ドメイン別 機微情報マスキング

作成日: 2026-07-04

## 対象

ドメインごとに機微情報の種類とマスキング方針を定義する。

## 1. Staff / Office

対象:

- staff email/name
- staff role
- MFA状態
- office address / phone / email
- billing status

タスク:

- [x] app-admin 事務所詳細の staff email をマスクする。
- [x] app-admin 事務所詳細の office contact を用途別に表示制限する。
- [ ] staff list/detail の返却項目を owner/manager/employee/app_admin で分ける。
- [ ] deleted staff / archived staff は匿名化情報を優先して表示する。

## 2. Welfare Recipient

対象:

- 氏名
- フリガナ
- 生年月日
- 性別
- 住所
- 電話
- 緊急連絡先
- 障害名 / 疾病名
- 手帳・年金詳細
- 生活保護情報

タスク:

- [x] 一覧 API から住所・電話・緊急連絡先・障害詳細を除外する。
- [ ] 詳細 API を owner/manager/employee で項目別に分ける。
- [ ] employee が閲覧できる項目を最小化するか決める。
- [ ] search / dashboard / deadline alerts で詳細情報を返しすぎていないか確認する。

## 3. Assessment / Support Plan / PDF

対象:

- 家族構成
- 医療情報
- 通院歴
- 就労歴
- 課題分析
- 支援計画本文
- モニタリング内容
- PDF file name
- presigned download URL

タスク:

- [ ] assessment list/detail 表示用 serializer を分ける。
- [ ] assessment 一括取得 API が医療・家族・就労詳細を不要に返さないよう確認する。
- [ ] support plan / monitoring / deliverable download の権限を確認する。
- [ ] presigned download URL をログに出さない。
- [ ] PDF download URL の有効期限と閲覧権限を確認する。

## 4. Inquiry / Message / Notice

対象:

- 問い合わせ本文
- 返信本文
- sender email/name
- IP / User-Agent
- admin_notes
- delivery_log
- notice/message title/content
- sender/recipient staff name

タスク:

- [x] 問い合わせ一覧は summary のみ返す。
- [x] 問い合わせ詳細の email/IP/User-Agent/delivery_log は通常 app_admin 表示ではマスクする。
- [ ] message / notice の本文に利用者名や申請内容が含まれる前提で表示範囲を確認する。
- [ ] Push通知・メール通知へ埋め込む本文を最小化する。

## 5. Billing / Stripe / Webhook

対象:

- `stripe_customer_id`
- `stripe_subscription_id`
- Stripe event id
- invoice id
- payment_intent id
- checkout / portal session URL
- webhook payload
- billing関連監査ログ

タスク:

- [ ] Stripe ID を `<present>` または末尾4桁にする。
- [ ] checkout / portal session URL をログに出さない。
- [ ] webhook payload 表示用 serializer を作る。
- [x] billing関連監査ログ details を allowlist 化する。

## 6. MFA / Auth

対象:

- MFA secret
- QR code URI
- recovery codes / backup codes
- temporary token
- refresh token
- access token
- reset token
- verification token
- passphrase

タスク:

- [ ] token / secret / code 類はログ・監査ログ・CIログに出さない。
- [ ] MFA 初期化レスポンスは発行直後の一時表示に限定する。
- [ ] recovery codes は再取得不可を保証する。
- [ ] MFA状態や user_id をログで生値紐付けしない。

## 7. Push Subscription

対象:

- Push endpoint
- p256dh key
- auth key
- user_agent

タスク:

- [x] endpoint を通常レスポンスで生返却しない。
- [ ] p256dh/auth は常に `<redacted>`。
- [ ] user_agent は必要最小限の分類にする。
- [ ] Push失敗ログは staff_id / endpoint を出さず、件数・エラー種別にする。

## 2026-07-05 TDD再実装メモ

完了:

- `OfficeDetailResponse` / `StaffInOffice` で app_admin 事務所詳細の office contact と staff email を表示時マスク。
- `InquiryListItem` で問い合わせ一覧本文を summary 表示にし、sender name/email をマスク。
- `InquiryDetailResponse` で sender name/email、IP、User-Agent、delivery_log を表示時マスク。
- `delivery_log.recipient` のメールアドレスを `mask_sensitive_details_for_display()` でマスク対象に追加。
- Push購読 endpoint は既存実装で通常レスポンス `<registered>` 化済みであることをテスト確認。
- `WelfareRecipientListResponse` の item serializer を詳細用 `WelfareRecipientResponse` から分離し、通常一覧から住所・電話・緊急連絡先・障害詳細を除外。
- `billing.status_changed` の監査ログ details は保存前に allowlist を通し、未定義 key は `<redacted>`、Stripe ID は `<present>` に変換。
- 監査ログdetails共通マスクで `raw_payload` / `raw_details` / `request_body` / `response_body` をキー単位で `<redacted>` に変換。

判断が必要:

- Assessment / Support Plan は現状、同一事業所スタッフ向けの詳細業務APIとして全量取得される。employee に医療・家族・就労詳細をどこまで見せるかの職務要件が未確定のため、serializer 分割は未実装。
- staff list/detail の role 別表示差分、deleted/archived staff の匿名化優先表示は未着手。

確認:

```bash
docker exec keikakun_app-backend-1 pytest \
  tests/utils/test_privacy_utils.py \
  tests/api/v1/test_inquiry_endpoints.py::TestAdminInquiryListEndpoint::test_get_inquiries_masks_sensitive_fields_in_list \
  tests/api/v1/test_inquiry_endpoints.py::TestAdminInquiryDetailEndpoint::test_get_inquiry_detail_masks_sender_metadata_and_delivery_log \
  tests/api/v1/test_admin_offices.py::test_app_admin_get_office_detail \
  tests/api/v1/test_push_subscriptions.py::TestSubscribePush::test_subscribe_success -q
# 17 passed, 2 warnings

docker exec keikakun_app-backend-1 pytest \
  tests/utils/test_privacy_utils.py::test_mask_sensitive_details_for_display_recursively_masks_known_sensitive_keys \
  tests/crud/test_audit_log_billing.py \
  tests/api/v1/test_recipients.py::test_list_recipients_does_not_expose_contact_or_disability_details \
  tests/api/v1/test_recipients.py::test_get_recipient_by_id -q
```

## 受け入れ要件

- [x] 各ドメインの機微情報が一覧化されている。
- [ ] ドメインごとの list/detail serializer が分離されている。
  - [x] Welfare Recipient 一覧は詳細serializerから分離済み。
  - [ ] Welfare Recipient 詳細、Assessment / Support Plan / Staff は未完了。
- [ ] owner/manager/employee/app_admin で表示項目が明文化されている。
- [ ] token / secret / MFA code / Push auth key は再表示・ログ出力されない。
- [x] backend test で代表的な機微項目が生返却されないことを確認している。
