# アプリ実装で対応できるマスキング残要件レビュー

作成日: 2026-07-06

## 目的

`masking_tasks/README.md` の残要件を、アプリケーション実装で対応できるものと、外部サービス・運用設定の確認が必要なものに分ける。

このレビューでは、アプリ実装で対応可能なものを実装チェックリストとして整理し、今後の PR 分割単位を明確にする。

## 結論

現時点でアプリ実装として進められる残タスクはまだある。

特に優先度が高いのは以下。

1. welfare recipient detail の権限別 serializer 分離。
2. assessment / support plan / monitoring / PDF download の表示制限。
3. audit log action 別 allowlist の拡張。
4. MFA/Auth の再取得不可・管理者一括有効化レスポンス縮小。
5. 一時マスク解除 API / UI / 永続化。
6. DB audit log / email delivery log の retention。

一方で、Cloud Logging / Cloud Build / Vercel / GitHub の実権限・保存期間・artifact 閲覧権限は、アプリコードだけでは完了できない。これらは運用確認タスクとして別管理する。

## アプリ実装で対応できるもの

### 1. Welfare Recipient 表示制限

現状:

- 通常一覧は住所、電話、緊急連絡先、障害詳細を返さないよう対応済み。
- 詳細 API は owner / manager / employee / app_admin の項目別制御が未完了。

チェックリスト:

- [x] 通常一覧で住所を返さない。
- [x] 通常一覧で電話番号を返さない。
- [x] 通常一覧で緊急連絡先を返さない。
- [x] 通常一覧で障害詳細を返さない。
- [ ] 詳細 API 用 schema を role 別に分ける。
- [ ] employee 通常詳細では contact / emergency / disability detail をマスクまたは非返却にする。
- [ ] owner / manager は同一事業所内で必要項目を閲覧可にする。
- [ ] app_admin は通常表示では最小情報に限定する。
- [ ] role 別期待レスポンスの API テストを追加する。

推奨 PR 粒度:

- PR 1: detail schema 分離と employee 通常詳細の制限。
- PR 2: owner / manager / app_admin の期待レスポンス固定。

### 2. Assessment / Support Plan / Monitoring / PDF Download

現状:

- Assessment は同一事業所スタッフ向け詳細業務 API として全量返却に近い。
- employee / owner / manager の表示範囲差分は未実装。
- PDF filename / download URL / presigned URL のログ・一覧表示制限は未確認。

判断:

- employee は summary 表示を原則にする。
- family / medical / employment / issue analysis の詳細は、担当者または明示権限がある場合に限定する。
- owner / manager は同一事業所内で業務上必要な詳細閲覧を許可する。

チェックリスト:

- [ ] `AssessmentSummaryResponse` を追加する。
- [ ] employee 通常取得では summary schema を返す。
- [ ] family details を employee 通常表示から除外する。
- [ ] medical details / hospital visits を employee 通常表示から除外する。
- [ ] employment details を employee 通常表示から除外する。
- [ ] issue analysis 本文を employee 通常表示から除外する。
- [ ] owner / manager 用の詳細 schema を明示する。
- [ ] support plan / monitoring の本文・メモ・評価内容の表示範囲を整理する。
- [ ] PDF filename に個人名・医療情報・支援内容が入る前提で一覧表示を制限する。
- [ ] presigned URL を logger / audit details / frontend console に出さないテストを追加する。

推奨 PR 粒度:

- PR 1: Assessment summary/detail schema 分離。
- PR 2: Support plan / monitoring 表示範囲整理。
- PR 3: PDF deliverable filename / URL のログ・一覧制限。

### 3. Audit Log 保存前 sanitizer / action 別 allowlist

現状:

- `CRUDAuditLog.create_log()` 経由では保存前 sanitizer 対応済み。
- `billing.status_changed` は action 別 allowlist 対応済み。
- billing 以外の action は棚卸し未完了。
- 別モデルや直接生成経路は継続確認が必要。

チェックリスト:

- [x] `CRUDAuditLog.create_log()` で details を保存前 sanitizer に通す。
- [x] `raw_payload` / `raw_details` / `request_body` / `response_body` を `<redacted>` に倒す。
- [x] `billing.status_changed` の action 別 allowlist を追加する。
- [ ] staff profile / office / message / withdrawal / terms / role change の action 一覧を棚卸しする。
- [ ] action 別に保存可能 key を定義する。
- [ ] 未定義 key を `<redacted>` に倒す。
- [ ] 業務監査上 raw 保存が必要な場合は、暗号化・閲覧権限・理由付き解除に分ける。
- [ ] audit log 保存前 sanitizer の regression test を action ごとに追加する。

推奨 PR 粒度:

- PR 1: action 一覧と allowlist map の拡張。
- PR 2: 直接 `AuditLog(...)` 生成経路の共通化。

### 4. MFA/Auth 再取得不可・再露出防止

現状:

- issue #152 に別 issue として切り出し済み。
- 自己登録の初回表示は許容する方針。
- 管理者個別 MFA 状態変更機能は維持する方針。
- 管理者一括で secret / QR / recovery codes を返す現仕様は縮小する方針。

チェックリスト:

- [ ] `/mfa/enroll` の初回レスポンス以外で `secret_key` / `qr_code_uri` を返さない。
- [ ] `/mfa/verify` 後に secret / QR / recovery codes を再取得できない。
- [ ] recovery codes は DB に hash のみ保存する。
- [ ] recovery codes の再表示 API を作らない。
- [ ] 再発行が必要な場合は旧コードを失効して新規生成する。
- [ ] 管理者個別 MFA 状態変更機能は維持する。
- [ ] 管理者一括有効化レスポンスに secret / QR / recovery codes を含めない。
- [ ] temporary token / TOTP code / recovery code / MFA secret / QR URI をログに出さない。
- [ ] raw user_id を MFA/Auth ログに出さない。

推奨 PR 粒度:

- PR 1: 管理者一括有効化レスポンス縮小。
- PR 2: secret / QR / recovery codes 再取得不可テスト。
- PR 3: MFA/Auth ログ再露出防止。

### 5. 一時マスク解除 API / UI / 永続化

現状:

- `SensitiveFieldGroup` / `TemporaryUnmaskGrant` / `can_view_unmasked()` の判定ロジックは実装済み。
- API、UI、永続化テーブルは未実装。

チェックリスト:

- [x] 機微情報グループを定義する。
- [x] 一時 grant の判定ロジックを実装する。
- [x] 理由必須の判定を実装する。
- [x] マスク解除監査ログ作成 helper を実装する。
- [ ] 一時 grant 永続化テーブルを追加する。
- [ ] マスク解除申請 API を追加する。
- [ ] マスク解除承認 API を追加する。
- [ ] マスク解除付き閲覧 API を追加する。
- [ ] UI で理由入力を必須化する。
- [ ] 期限切れ後に再マスクされる統合テストを追加する。
- [ ] 403 / 404 の出し分けを API に統合する。

推奨 PR 粒度:

- PR 1: DB / model / CRUD。
- PR 2: API。
- PR 3: UI。
- PR 4: integration test。

### 6. DB Audit Log / Email Delivery Log Retention

現状:

- ログ保存期間の基準は文書化済み。
- DB audit log / email delivery log の実削除処理は未実装。

チェックリスト:

- [ ] audit log の保存期間を設定値化する。
- [ ] email delivery log の保存期間を設定値化する。
- [ ] retention 対象外にする security event / incident hold の条件を定義する。
- [ ] retention job / task を追加する。
- [ ] 削除件数・error_type のみログに残す。
- [ ] raw details を再ログ出力しない。
- [ ] retention の unit test / integration test を追加する。

推奨 PR 粒度:

- PR 1: retention 設定と削除service。
- PR 2: scheduler / task 統合。
- PR 3: incident hold 条件。

### 7. Static Check / Allowlist 運用

現状:

- `security_log_static_check.py` は allowlist file に対応済み。
- expired allowlist は finding を抑止しない。
- frontend/e2e は blocking。
- backend/scripts の既存 finding は継続対応が必要。

チェックリスト:

- [x] allowlist file を追加する。
- [x] reason / owner / expires_on を必須にする。
- [x] expired allowlist を無効にする。
- [x] frontend/e2e を blocking にする。
- [ ] backend/app の existing finding を解消する。
- [ ] backend/app を blocking にする。
- [ ] scripts の existing finding を解消する。
- [ ] scripts を blocking にする。
- [ ] allowlist 期限前レビューを CI または定期タスクで通知する。

推奨 PR 粒度:

- PR 1: backend/app finding 解消。
- PR 2: backend/app blocking 化。
- PR 3: scripts finding 解消。
- PR 4: scripts blocking 化。

## アプリ実装だけでは完了できないもの

以下は外部サービス・運用設定の確認が必要。

- [ ] Cloud Logging の IAM / retention 確認。
- [ ] Cloud Build logs の IAM / retention 確認。
- [ ] Vercel logs の閲覧権限 / retention 確認。
- [ ] GitHub Actions logs / artifacts の閲覧権限確認。
- [ ] production / staging のログ閲覧 group/team 管理確認。
- [ ] 個人アカウント直付け権限がないことの確認。
- [ ] fork PR で secrets / artifact が露出しない設定確認。
- [ ] 既存本番ログに raw body / raw payload / token 類が含まれていた場合の削除・保持判断。

## デプロイ観点

アプリ実装済みの代表経路は、部分的なセキュリティ改善としてデプロイ候補にできる。

ただし、以下の理由により「マスキング安全基準の完全達成」とは扱わない。

- welfare recipient detail が未完了。
- assessment / support plan / monitoring / PDF download が未完了。
- MFA/Auth は issue #152 の別対応。
- backend/app / scripts の static check blocking 化が未完了。
- 外部ログ保存先の実権限・保存期間確認が未完了。

## 次の推奨順序

1. welfare recipient detail の role 別 serializer。
2. assessment summary/detail serializer。
3. MFA/Auth issue #152。
4. audit log action 別 allowlist 拡張。
5. backend/app static check finding 解消。
6. 一時マスク解除 API / UI / 永続化。
7. DB audit log / email delivery log retention。
