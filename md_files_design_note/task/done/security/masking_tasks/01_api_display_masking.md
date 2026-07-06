# 01 APIレスポンス / 管理画面表示マスキング

作成日: 2026-07-04

## 対象

元 TODO のうち、APIレスポンスと管理画面表示に関するマスキングタスクを扱う。

対象領域:

- app-admin 監査ログ画面
- app-admin 問い合わせ一覧/詳細
- app-admin 事務所一覧/詳細
- staff / welfare recipient / office 一覧・詳細 API
- 利用者一覧/詳細
- approval request / employee action request 表示
- Push subscription 表示
- email delivery log 表示

## 現状

- app-admin 監査ログ API は `details` をそのまま返している。
- app-admin 監査ログ画面は `JSON.stringify(log.details)` をそのまま表示している。
- app-admin 問い合わせ API は一覧・詳細とも本文、送信者名、メール、IP、User-Agent、delivery_log を生値で返す。
- app-admin 事務所詳細 API は事務所住所・電話・メール、所属スタッフ氏名・メールを生値で返す。
- 利用者一覧 API は `WelfareRecipientResponse` を使っており、一覧でも氏名・ふりがな・生年月日・住所・電話・緊急連絡先・障害情報を返し得る。
- 利用者詳細 API は同一事業所の全職員が全項目を参照可能。
- approval request / employee action request は `request_data` / `original_request_data` をそのまま返し得る。
- Push購読 API は `endpoint` をレスポンスに含めている。
- メール送信失敗の監査ログ・delivery_log は宛先、件名、外部エラー本文を含み得る。

## 実装タスク

- [ ] API表示用 serializer を DB schema と分離する。
- [ ] app-admin 監査ログ一覧では `details` を summary 化する。
- [ ] app-admin 監査ログ詳細では `details` を allowlist key のみ表示する。
- [ ] app-admin 問い合わせ一覧では本文全文、email、IP/User-Agent、delivery_log を返さない。
- [ ] app-admin 問い合わせ詳細では、通常権限と sensitive 権限で返却項目を分ける。
- [ ] app-admin 事務所一覧では連絡先情報を返す必要性を再確認する。
- [ ] app-admin 事務所詳細では staff email を通常はマスクする。
- [ ] welfare recipient list 用 schema を作り、住所・電話・緊急連絡先・障害詳細を除外する。
- [ ] welfare recipient detail 用 schema を権限別に分ける。
- [ ] approval request / employee action request の `request_data` 表示用 serializer を作る。
- [ ] Push subscription `endpoint` は `<registered>`、hash、または末尾6-8文字のみにする。
- [ ] email delivery log / email failure details は recipient / subject / error をマスクする。

## マスク例

- email: `na***@example.com`
- 氏名: `山田 太郎` -> `山田 *`
- phone: `090-1234-5678` -> `090-****-5678`
- address: 権限なしでは `<redacted>`
- IP: hash または `<redacted_ip>`
- User-Agent: family / major version 程度、または `<redacted_user_agent>`
- Push endpoint: `<registered>` または `***末尾8`

## 受け入れ要件

- [ ] app-admin 監査ログ API が raw `details` を返さない。
- [ ] app-admin 問い合わせ一覧が本文全文・email・IP/User-Agent・delivery_log を返さない。
- [ ] app-admin 事務所詳細で staff email が権限に応じてマスクされる。
- [ ] 利用者一覧で住所・電話・緊急連絡先・障害詳細が返らない。
- [ ] approval request の `request_data.original_request_data` が権限なしで生返却されない。
- [ ] Push subscription `endpoint` が通常レスポンスで生返却されない。
- [ ] email failure details が recipient / subject / 外部エラー本文を生返却しない。
