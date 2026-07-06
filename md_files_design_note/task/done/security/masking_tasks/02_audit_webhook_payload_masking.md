# 02 Audit Log / Webhook Payload / Request Data マスキング

作成日: 2026-07-04

## 対象

raw payload や raw details をそのまま保存・表示・ログ出力しないためのタスク。

対象:

- `audit_logs.details`
- `webhook_events.payload`
- billing関連監査ログ
- staff削除 / email変更 / withdrawal / terms agreement の監査ログ
- approval request / employee action request の `request_data`
- office update の `old_values` / `new_values`

## 現状

- `admin_audit_logs.py` は `details: log.details` をそのまま返している。
- `AuditLogResponse.details` は任意 dict。
- `WebhookEvent` response schema は `payload` をそのまま含める形。
- webhook表示APIは現時点で見当たらないが、schema を使った API 追加時に raw payload 露出リスクがある。
- `crud.audit_log.create_log(details=...)` は保存前共通 sanitizer を通していない。
- office update 監査ログは `old_values` / `new_values` をそのまま保存する可能性がある。
- approval request の `request_data` は利用者作成・更新時に氏名、住所、障害情報、緊急連絡先を含み得る。

## 実装タスク

- [ ] 監査ログ表示用 serializer を作る。
- [ ] 監査ログ保存前 sanitizer の要否を決める。
- [ ] `details` の allowlist schema を action ごとに定義する。
- [ ] 未定義 key は `<redacted>` にする。
- [ ] `old_values` / `new_values` は key 単位でマスクする。
- [ ] webhook payload 表示用 serializer を作る。
- [ ] webhook payload ログ用 serializer を表示用 serializer と分ける。
- [ ] Stripe ID は `<present>` または `prefix_***last4` に統一する。
- [ ] approval request / employee action request の `request_data` 表示用 serializer を作る。
- [ ] request_data 内の `basic_info`, `contact_address`, `emergency_contacts`, `disability_info`, `disability_details` を権限別にマスクする。
- [ ] audit details / webhook payload / request_data の raw JSON 表示を frontend で禁止する。

## 危険キー候補

- `email`
- `sender_email`
- `recipient`
- `recipient_email`
- `first_name`
- `last_name`
- `full_name`
- `address`
- `tel`
- `phone`
- `ip_address`
- `user_agent`
- `stripe_customer_id`
- `stripe_subscription_id`
- `customer_id`
- `subscription_id`
- `payment_intent`
- `invoice`
- `token`
- `secret`
- `password`
- `verification_token`
- `reset_token`
- `qr_code_uri`
- `recovery_codes`
- `backup_codes`

## 受け入れ要件

- [ ] audit log API が email/name/phone/address/Stripe ID/token を生値で返さない。
- [ ] webhook payload API が allowlist 以外を返さない。
- [ ] raw `details` / raw `payload` / raw `request_data` をそのまま JSON 表示する画面がない。
- [ ] office update の `old_values` / `new_values` が API表示時にマスクされる。
- [ ] approval request API が利用者住所・電話・障害情報を権限なしで返さない。
- [ ] action ごとの sanitizer test がある。
