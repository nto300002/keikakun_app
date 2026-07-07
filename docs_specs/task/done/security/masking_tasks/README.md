# マスキング / ログ削除タスク分割

作成日: 2026-07-04

元資料:

- `md_files_design_note/task/todo/security/data_access_masking_policy_todo.md`

## 目的

DB保存値、APIレスポンス、管理画面表示、ログ、CI出力、運用スクリプト出力に残る機微情報を、実装しやすい粒度のタスクへ分割する。

このディレクトリでは、元 TODO の内容を以下のセクションに分けて管理する。

## セクション

1. `01_api_display_masking.md`
   - APIレスポンスと管理画面表示のマスキング。
   - app-admin / owner / manager / employee の閲覧粒度。

2. `02_audit_webhook_payload_masking.md`
   - audit log details / webhook payload / approval request data の raw 表示禁止。
   - DB保存用 payload と表示用 serializer の分離。

3. `03_log_and_ci_output_redaction.md`
   - アプリログ、CIログ、E2E/Playwright 出力、運用スクリプト標準出力の削除・マスク。
   - Stripe ID、token、response body、Error object の出力抑制。

4. `04_domain_sensitive_data_masking.md`
   - 利用者、アセスメント、支援計画、問い合わせ、MFA、Push、メール、Office/Staff などドメイン別の機微情報。

5. `05_permissions_and_unmasking_flow.md`
   - 詳細閲覧、マスク解除、一時権限、理由入力、監査記録。

6. `06_tests_static_checks_and_acceptance.md`
   - backend/frontend/E2E/script テスト。
   - logger / console / print の静的チェック。
   - 完了条件。

## 現時点の進捗

- ログマスキング: 代表経路は対応済み。backend/scripts と frontend/e2e の static check は blocking mode 化済み。
- 共通マスク関数: email/name/外部ID/details/webhook/request_data 向けの表示用 sanitizer を追加済み。
- APIレスポンスのマスキング: audit log、webhook payload、employee action request、inquiry、office detail、push subscription の代表経路は対応済み。
- raw details / raw payload の serializer 分離: 代表経路は対応済み。`CRUDAuditLog.create_log()` 経由の保存前 sanitizer と `billing.status_changed` の action 別 allowlist schema は対応済み。
- 権限別表示設計: `SensitiveFieldGroup` / 一時マスク解除判定ロジックは実装済み。API/UI/永続化統合は未完了。
- utility 単体以外のマスキングテスト: 代表 API / service / security static check は追加済み。

## 基本方針

- DB保存値そのものの削除・変換は原則対象外。
- API/画面/ログ/CI出力では、用途に必要な最小項目だけを allowlist で出す。
- token / secret / password / MFA secret / recovery code / QR code URI は常に非表示。
- raw request body / raw response body / raw webhook payload / raw audit details はそのまま出さない。
- app-admin でも最小権限を原則にする。
- 詳細閲覧が必要な場合は、一時権限・理由入力・監査ログを必須にする。

## 2026-07-06 残要件の分類

mdファイル移動・削除差分を除外した場合の残要件を、アプリ実装で対応できるものと、外部運用・設定確認が必要なものに分ける。

### アプリ実装で対応できるもの

優先度高:

- [ ] `welfare recipient list/detail` の権限別 serializer 分離。
  - [x] 通常一覧では住所、電話、緊急連絡先、障害詳細を返さない。
  - [x] 詳細 API は employee の場合、住所・電話・緊急連絡先・障害詳細を返さない。
  - [ ] app_admin の利用者詳細閲覧要件を定義し、必要なら app_admin 用 serializer を追加する。

- [ ] `assessment / support plan / monitoring / PDF download` 周辺の表示制限。
  - family / medical / employment / issue analysis の一覧・一括取得の返却範囲を整理する。
  - [x] PDF一覧では presigned download URL を返さず、ダウンロード専用 endpoint でのみ発行する。
  - [ ] PDF filename を一覧に出す業務必要性を確認する。
  - employee が医療・家族・就労詳細をどこまで見られるか仕様判断後に serializer 分離する。

- [ ] `audit log` 保存前 sanitizer。
  - [x] `CRUDAuditLog.create_log()` 経由では、表示時マスクだけでなく保存前に危険な raw value を共通 sanitizer に通す。
  - [x] `raw_payload` / `raw_details` / `request_body` / `response_body` はキー単位で `<redacted>` に倒す。
  - [x] staff profile の直接 `AuditLog(...)` 生成経路では、名前・メールの `old_value/new_value` を保存前にマスクする。
  - [x] 旧 `OfficeAuditLog` CRUD の `old_values/new_values` は保存前に共通 sanitizer に通す。
  - [ ] password reset / message など、別モデルの監査ログも同じ基準で棚卸しする。
  - [ ] 既存の業務監査要件と衝突する場合は、保存用 raw と表示用 masked の保持方針を分ける。

- [ ] `audit log` action 別 allowlist schema。
  - [x] `billing.status_changed` は保存してよい details key を allowlist 化し、未定義 key は `<redacted>` に倒す。
  - [ ] billing以外の action も同じ形式で棚卸しする。

- [ ] MFA/Auth の再取得不可・管理者一括有効化レスポンス縮小・ログ再露出防止。
  - issue #152 の別対応。
  - MFA secret / QR code URI / recovery codes は初回表示以外で再取得不可にする。
  - [x] 管理者一括有効化結果に secret / QR code URI / recovery codes を返さない。
  - [x] フロントエンドの一括有効化結果モーダルも、対象スタッフの最小情報だけを表示する。
  - [ ] 単体MFA有効化と初回ログイン時セットアップで secret / QR code URI を返す既存仕様は、別途プロダクト判断が必要。

優先度中:

- [ ] 一時マスク解除 API / UI / 永続化。
  - `SensitiveFieldGroup` と `TemporaryUnmaskGrant` のサービス案を API に統合する。
  - 理由入力、期限、対象、承認者、監査ログを必須にする。

- [ ] DB audit log / email delivery log の retention と削除方針。
  - アプリDB内に保存される audit log / delivery log の保持期間を定義する。
  - 自動削除、手動削除、incident hold のどれで運用するか決める。

- [ ] allowlist 追加時の承認者・レビュー周期・期限切れ時の運用定義。
  - `security_log_allowlist.json` の entry 追加ルールを文書化する。
  - 期限切れ allowlist は CI で検出されるが、期限前レビュー運用は未定義。

- [ ] screenshot / video に個人情報が含まれた場合の incident hold / 削除判断。
  - Playwright trace は `off` 済み。
  - failure screenshot / video は短期保存だが、個人情報が含まれた場合の削除・保持判断が未定義。

### アプリ実装だけでは完了できないもの

外部サービス / 運用設定の確認が必要:

- [ ] Cloud Logging / Cloud Build / Vercel / GitHub の実権限・保存期間確認。
  - 実IAM、team/group、repository権限、retention 設定はローカルコードから検証できない。

- [ ] production / staging のログ閲覧 group/team 管理確認。
  - 個人アカウント直付け権限がないことを管理画面またはCLIで確認する必要がある。

- [ ] GitHub artifact download 権限、fork PR 時の secret / artifact 露出設定確認。
  - repository settings / organization settings の確認が必要。

- [ ] Cloud Logging / Cloud Build / Vercel の retention 設定確認。
  - 保存期間はサービス側設定で確認・変更する。

- [ ] 既存本番ログに raw body / raw payload / token 類が含まれていた場合の削除・保持判断。
  - 既存ログの実データ確認、incident判断、削除可否判断が必要。

### 現時点のデプロイ判断

- md移動・削除差分を除外し、対象差分だけを切り出すなら、代表的な漏えい経路を塞ぐ **部分的なセキュリティ改善としてデプロイ候補**。
- ただし、上記残要件があるため、**マスキング安全基準の完全達成としては未達**。
- PR本文には、残要件と外部運用確認待ちを明記する。
