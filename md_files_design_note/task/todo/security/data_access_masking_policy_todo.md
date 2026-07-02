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

## 今回対応しないこと

- audit log details / webhook payload のDB保存形式変更。
- app-admin 画面の表示項目変更。
- staff / welfare recipient / office の一覧・詳細レスポンス再設計。
- CSV/export の権限設計とマスク実装。
- マスク解除フロー、理由入力、一時権限、監査証跡の実装。

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

### 2. Stripe / billing webhook payload

対象候補:

- `webhook_events.payload`
- `billing.stripe_customer_id`
- `billing.stripe_subscription_id`
- billing関連監査ログ

確認したいリスク:

- Stripe customer/subscription id は秘密鍵ではないが、外部サービス上の追跡識別子。
- 管理画面・API・運用ログで無制限に表示すると、外部アカウントとの紐付け情報が漏れる。

### 3. 問い合わせ/メッセージ

対象候補:

- 問い合わせ本文、返信本文、送信者 email/name
- app-admin 問い合わせ詳細
- ユーザー側メッセージ一覧/詳細

確認したいリスク:

- app-admin 全員が問い合わせ本文・メールアドレスを常時閲覧できる設計でよいか。
- 返信に必要な情報と一覧表示に必要な情報の粒度が同じになっていないか。

### 4. staff / welfare recipient / office

対象候補:

- staff email/name
- welfare recipient 氏名、フリガナ、生年月日、障害情報、家族/医療情報
- office 情報、請求状態

確認したいリスク:

- 一覧APIで詳細情報を返しすぎている。
- app-admin、owner、manager、employee の権限境界が画面/APIごとに統一されていない。
- CSV/export や一括取得APIが存在する場合、表示マスクを迂回する可能性がある。

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

## TODO

### P0: 現状調査

- [ ] app-admin 画面/APIで表示している監査ログ項目を洗い出す。
- [ ] `webhook_events.payload` を返す API / 画面があるか確認する。
- [ ] audit log details をそのまま返している API があるか確認する。
- [ ] staff/welfare recipient/office の一覧APIと詳細APIで返却項目差分を確認する。
- [ ] export/CSV/一括取得機能の有無を確認する。

### P0: 表示用 schema の分離

- [ ] DB保存用 payload と API表示用 payload を分ける。
- [ ] 監査ログ表示用 serializer を作る。
- [ ] webhook payload 表示用 serializer を作る。
- [ ] allowlist 方式で表示可能 key を定義する。
- [ ] 未定義 key は `<redacted>` にする。

### P1: 権限チェック

- [ ] app-admin の監査ログ閲覧権限を定義する。
- [ ] app-admin の問い合わせ詳細閲覧権限を定義する。
- [ ] billing/webhook 詳細閲覧権限を定義する。
- [ ] owner/manager/employee の一覧/詳細/API権限を表にする。
- [ ] 権限不足時は 403、存在秘匿が必要な場合は 404 を使い分ける。

### P1: テスト

- [ ] audit log API が email/name/Stripe ID を生値で返さない backend test。
- [ ] webhook payload API が allowlist 以外を返さない backend test。
- [ ] app-admin でも通常権限では sensitive field がマスクされる backend test。
- [ ] 追加権限を持つ場合だけ詳細を見られる backend test。
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