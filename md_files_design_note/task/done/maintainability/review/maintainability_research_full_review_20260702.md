# maintainability_research.md 全体レビュー

作成日: 2026-07-02

対象:

- `md_files_design_note/task/todo/refactor/maintainability/maintainability_research.md`
- 既存レビュー:
  - `review/p1_p3_review_and_coverage_20260701.md`
  - `review/p4_p6_frontend_refactor_review_20260701.md`

## 総評

`maintainability_research.md` は、当初の調査メモから実装ログ、TDD記録、レビュー結果、今後の計画までを同一ファイルに追記しているため、情報量は十分だが、現在は「何が完了していて、何が残っているか」を一読で判断しにくくなっている。

実装方針自体は保守的で妥当。特に、外部API連携、課金状態遷移、DB変更管理について、段階的に責務を分離する方向に修正されている点は良い。ただし、古いチェックリストや未更新の受け入れ要件が残っており、文書をそのまま次タスクの根拠にすると重複実装や優先度の誤認が起きやすい。

## 主要な指摘

### High: 文書が単一の正になりにくくなっている

`推奨する実行順`、`最初のTDD候補`、末尾のフェーズチェックリストに、すでに実装・検証済みの項目が未完了のように残っている。

例:

- 認証Cookie設定
- 本番向け不要ログの削除
- Application 通知の一部
- 課金状態遷移の共通化
- `get_current_user` の分割
- DB変更を Alembic 正とする方針

対応方針:

- ファイル冒頭に「現在のステータス一覧」を追加する。
- 古い実装ログは各タスクmdまたは review 配下へ移す。
- `maintainability_research.md` は、今後の判断に使う要約と未完了タスクの索引に寄せる。

### Medium: Dashboard P4 の記述に矛盾がある

P4では、以下が未完了として残っている。

- `useDashboardData` が未抽出
- 課金制限ロジックが未抽出
- table 部分が未抽出

一方で後続の「7. フロントエンドのAPI呼び出しと状態管理がコンポーネント内に密集している」では、`useDashboardData.ts`、`dashboardDataState.ts`、`lib/permissions/dashboard.ts` が追加済みとして記録されている。

対応方針:

- P4側に「追加対応済み」または「現在の残タスク」を追記する。
- table 抽出だけが残っているのか、P4全体が完了扱いなのかを明確にする。

### Medium: ログ削除の受け入れ要件が二重管理になっている

「本番環境に影響しそうなログ出力が残っていない」は上部で未チェックだが、後続では print/log 削除が完了として扱われている。

また、`console.error/warn/info/debug` はフロントエンドに一定数残っているため、単純な全削除ではなく、利用者影響・本番出力・開発時のみの区別が必要。

対応方針:

- `log_policy.md` を作成する。
- `print` / `console.*` / `logger.*` を分類する。
- 本番で許可するログ、禁止するログ、開発時のみ許可するログを明文化する。

### Medium: 課金状態遷移は backend 側の共通化が進んだが、全体完了ではない

backend では `BillingStatusTransitionService` による共通化が進み、Webhook/API/バッチの一部が同じ判定関数を使うようになっている。

一方で、文書上の残タスクとして以下が残る。

- frontend/backend の status 表示・制限マッピングの一元化
- `trial_expired` / `payment_failed` / `past_due` / `canceled` などの制限仕様の一覧化
- 共有DB起因と思われるテスト不安定性の扱い

対応方針:

- 課金状態ごとの「表示」「書き込み権限」「Checkout可否」「Portal可否」を表にする。
- backend の判定関数と frontend の表示・制限定義を照合するテストを追加する。
- 共有DBを使うテストは isolated fixture 化または該当テストの安定化方針を別タスク化する。

### Medium: Google Calendar はリファクタリングではなく仕様判断が先

Google Calendar 連携は、廃止・縮退・代替機能の前提が追記されている。現在の方向性では、単なる既存コード整理よりも、以下の仕様判断が先に必要。

- Google Calendar 自動連携を継続するか
- アプリ内期限カレンダーを主にするか
- `.ics` ダウンロードを標準導線にするか
- Google Calendar 反映はチュートリアル扱いにするか

対応方針:

- Google Calendar は maintainability の一般リファクタリングから切り出す。
- `google_calendar.md` 側で、代替機能の受け入れ要件を確定してから実装に入る。
> これに関しては別のissueで実装します

### Medium: Alembic 方針は改善されたが、運用チェックリストは未完了

DB変更は Alembic を正とする方針に修正済み。baseline revision の判断も進んでいる。

ただし、末尾のフェーズチェックリストには以下が残っている。

- 手動SQLと Alembic 差分確認手順
- migration 適用前後確認SQL
- rollback/recovery のPR記載
- CDで migration が失敗した場合の対応手順

対応方針:

- 方針完了と運用手順完了を分けて管理する。
- `alembic/` 配下に、適用前確認、適用後確認、失敗時復旧、CD実行時の確認項目を追加する。

### Low: TODO/仮実装のmd化は完了したが、対応タスク化が残る

`todo_placeholder_cleanup.md` が作成され、利用者向け機能に残る TODO/仮実装は可視化された。

特に優先度が高いのは以下。

- 問い合わせ返信モーダルの仮実装
- 新規問い合わせタブの固定文言・固定メール

対応方針:

- P0項目を別ブランチでTDD対象にする。
- 利用者に見える仮文言と開発者向けTODOを分けて解消する。

## ステータス整理

| No | 項目 | 現状 | レビュー |
| --- | --- | --- | --- |
| 1 | 認証Cookie設定 | 完了寄り | ドキュメント上の古い未完了記述を整理する |
| 2 | 巨大Service/Component | 部分完了 | P1/P2/P3/P5は進捗あり。P4/P6の記述差分を整理する |
| 3 | Application通知 | 部分完了 | 利用者側は進捗あり。ロール変更通知・共通監視ログは残る |
| 4 | ログ削除 | 部分完了 | 不要ログ削除は進んだが、ログ方針mdが必要 |
| 5 | Google Calendar | 仕様判断待ち | 縮退・代替機能の設計を先に固める |
| 6 | 課金状態遷移 | backendは進捗大 | frontend/backendの状態マッピング統一が残る |
| 7 | Frontend API/state | 進捗あり | Dashboard P4との記述矛盾を解消する |
| 8 | get_current_user | 完了寄り | 古い未完了チェックを整理する |
| 9 | TODO/仮実装 | md化完了 | P0項目の実装タスク化が必要 |
| 10 | DB/Alembic | 方針は改善 | 運用手順・CD失敗時対応・確認SQLが残る |

## 次に行うべきこと

1. `maintainability_research.md` の冒頭に、上記のような現在ステータス表を追加する。
2. P4 Dashboard、ログ削除、課金状態遷移、Alembic の古いチェックリストを更新する。
3. `log_policy.md` を作成し、本番で許容するログと禁止するログを定義する。
4. 課金状態ごとの frontend/backend マッピング表とテスト要件を作る。
5. Google Calendar は代替機能仕様として分離し、アプリ内カレンダー・`.ics`・Google Calendar チュートリアルの要件を確定する。
6. TODO/仮実装のP0項目を次のTDD実装候補にする。

## 受け入れ要件

- [x] `maintainability_research.md` 全体を対象にレビューした。
- [x] 既存レビューとの差分を踏まえた。
- [x] 完了済み・未完了・矛盾している記述を分類した。
- [x] 次に修正すべき優先度を整理した。
- [x] review ディレクトリ配下にレビュー結果を記録した。

## 再レビュー: デプロイ可否確認

確認日: 2026-07-02

対象:

- `md_files_design_note/task/todo/refactor/maintainability/maintainability_research.md`
- 本レビューで指摘した未完了項目の反映状況
- 現在の `k_back` / `k_front` の代表テスト結果

### 判定

条件付きでデプロイ可能。

理由:

- `maintainability_research.md` は、前回レビュー時点で問題だった P4 Dashboard の記述矛盾、ログ方針md未作成、課金状態マッピング未整理について、概ね反映済み。
- 未完了として残っている項目は、主に追加リファクタ、別issueで扱う仕様判断、運用確認であり、今回の変更そのものを必ず止める種類ではない。
- frontend lint と backend の代表テストが通過している。

ただし、以下はデプロイ前またはPR本文で明記すること。

- `main DB` の `alembic_version` が `baseline_20260701` 以降に揃っていることは、DB接続先で別途確認が必要。
- CD実行ログに `DATABASE_URL` や secret 値が出ていないことは、初回CD実行後に確認が必要。
- 破壊的migrationを通常CDに混ぜない運用ルールは、PR本文または運用メモに明記する。
- Google Calendar のアプリ内カレンダー / `.ics` / 自動同期縮退は別issue扱いであり、今回のデプロイ完了条件には含めない。
- TODO/仮実装のP0修正は別issue扱いであり、今回のデプロイ完了条件には含めない。

### 実行した確認

frontend:

```bash
npm --prefix k_front run lint
```

結果:

- 成功

backend:

```bash
docker exec keikakun_app-backend-1 pytest \
  tests/core/test_auth_cookie.py \
  tests/api/test_deps_permissions.py \
  tests/services/test_billing_status_transition.py \
  tests/tasks/test_billing_check.py \
  tests/services/test_employee_action_notice_service.py \
  tests/services/test_employee_action_executor.py \
  tests/services/test_welfare_recipient_refactor_services.py \
  tests/services/test_calendar_refactor_services.py \
  tests/services/test_google_calendar_gateway.py \
  tests/api/v1/test_admin_audit_logs.py \
  tests/scripts/test_alembic_baseline_guard.py \
  -q
```

結果:

- `87 passed in 249.48s`

### 残タスクの扱い

デプロイを止めるべき項目:

- なし。ただしDB/Alembicの接続先確認とCDログ確認は、デプロイ手順上の必須確認として扱う。

別issueで扱う項目:

- Dashboard 一覧描画の `DashboardRecipientTable` 分離。
- P6 AdminMenu の Google Calendar 状態管理、スタッフMFA操作、事業所編集form状態のhook化。
- role change 側の通知共通化と監査ログ共通化。
- Google Calendar 縮退・代替機能化。
- TODO/仮実装のP0実装対応。

### デプロイ前チェックリスト

- [x] `maintainability_research.md` の前回レビュー指摘が概ね反映されている。
- [x] frontend lint が通っている。
- [x] backend の代表テストが通っている。
- [ ] `main DB` の `alembic_version` が `baseline_20260701` 以降であることを確認する。
- [ ] 初回CD実行後、ログに secret / DB URL が出ていないことを確認する。
- [ ] PR本文に、破壊的migrationを通常CDに混ぜない方針と手動確認方法を記載する。

## 再レビュー: 機密情報ログ観点

確認日: 2026-07-02

結論:

- ログ観点では、現時点のまま本番デプロイするのは推奨しない。
- 理由は、今回の差分で追加されたCD/Alembic部分だけでなく、同時に本番へ載る backend コード内に、MFA/TOTP値、メールアドレス、個人名、内部ID、例外全文を出すログが残っているため。
- 前回の「条件付きでデプロイ可能」は、機能テスト観点の判定としては維持できるが、機密ログ観点では「修正後にデプロイ可能」へ引き下げる。

### Critical: TOTPコードと現在有効なMFAコードがINFOログに出る

対象:

- `k_back/app/api/v1/endpoints/auths.py`
- `k_back/app/core/security.py`

確認した内容:

- MFA検証時に入力された `totp_code` をINFOログに出している。
- `verify_totp()` 内で、入力token、sanitized token、さらに `totp.now()` で生成した現在有効なコードをINFOログに出している。

リスク:

- Cloud Run / Cloud Logging に、MFA突破に使える短時間有効な認証コードが残る。
- ログ閲覧権限を持つユーザー、ログ転送先、障害調査用の共有ログから認証コードが漏れる。
- これはデバッグログではなくINFOログのため、本番で通常出力される可能性が高い。

対応:

- デプロイ前に削除する。
- 残す場合でも「MFA検証開始」「検証成功/失敗」程度に限定し、コード値、現在有効コード、secret復号成功詳細は出さない。

### High: 認証・MFA関連ログにメールアドレスや内部IDが残る

対象例:

- `k_back/app/api/v1/endpoints/auths.py`
- `k_back/app/models/staff.py`
- `k_back/app/api/deps.py`

確認した内容:

- MFA secret復号失敗時に `user.email` をログ出力している。
- StaffモデルのMFA secret復号失敗でもメールアドレスをログ出力している。
- 認証依存で `user.email`、`user.id`、削除済み事務所アクセス時のメールアドレスをログ出力している。

リスク:

- メールアドレスは個人情報として扱うべき。
- 認証失敗ログと紐づくことで、アカウント存在確認や攻撃対象の特定に使われる。

対応:

- 本番ログでは staff_id のみ、またはハッシュ化/マスクした識別子に寄せる。
- メールアドレスは監査ログやDB上の調査で追えるようにし、通常アプリログには出さない。

### High: Cloud Build / Cloud Run の環境変数渡しはsecret露出リスクが残る

対象:

- `k_back/cloudbuild.yml`

確認した内容:

- Alembic baseline guard / migration step に `DATABASE_URL=${_PROD_DATABASE_URL}` を渡している。
- Cloud Run deploy step では `--update-env-vars` にDB URL、SECRET_KEY、AWS、S3、Mail、Stripe、VAPIDなど多数のsecret系値を渡している。
- ファイル上はプレースホルダだが、Cloud Build substitutions / 実行ログ / build detail / 失敗時出力の扱いに注意が必要。

評価:

- 今回追加された `alembic_baseline_guard.py` 自体は、正常系ではDB URLを出力しない。
- ただし、`create_engine()` / 接続失敗時の例外文字列がDB接続情報をどこまで含むかは実環境で確認が必要。
- `--update-env-vars` にsecretを直接並べる方式は、長期的にはSecret Manager参照へ寄せる方が安全。

対応:

- 初回CD実行後、Cloud BuildログとCloud Run revision設定表示にsecret値が露出していないか確認する。
- 中期的には `--set-secrets` またはSecret Manager連携へ移行する。
- 少なくともPR本文に「CDログでsecret値が出ていないことを確認する」を必須手順として書く。

### Medium: 利用者名・内部ID・例外全文を出す業務ログが残る

対象例:

- `k_back/app/services/dashboard_service.py`
- `k_back/app/services/support_plan_service.py`
- `k_back/app/services/employee_action_service.py`
- `k_back/app/services/approval/employee_action_executor.py`
- `k_back/app/crud/crud_welfare_recipient.py`

確認した内容:

- Dashboard系debugログで利用者氏名、期限計算情報、cycle情報をINFO出力している。
- 支援計画・利用者作成周辺で plan_cycle_id、recipient_id、status_id、traceback全文を出している。
- employee actionで `execution_result` や `error={str(e)}` をそのままログに出す箇所がある。
- `Request data: %s` のように、リクエストデータ全体をログ出力する箇所がある。

リスク:

- 直接secretではないが、個人情報、内部ID、業務データ、例外内のSQL値が出る可能性がある。
- 特に `traceback.format_exc()` と `str(e)` は、DB制約エラーや外部APIエラーの内容次第で予期しない値を含む。

対応:

- デプロイ前の最低ラインとして、個人名、メール、MFA/TOTP、token、secret、raw request data、traceback全文の本番出力を削除する。
- 内部IDのみ必要な場合も、INFOではなくDEBUGへ落とし、本番ログレベルで出ないことを確認する。
- 例外ログは `error_type` と安全な文脈だけに絞る。

### Frontend console

確認した内容:

- 今回差分では `LayoutClient.tsx` などで一部 `console.error` が削除されている。
- ただし、frontend全体には `console.error` がまだ複数残る。

評価:

- frontend consoleは利用者のブラウザ上に出るため、Cloud Loggingとは性質が違う。
- ただし、error object にAPIレスポンスや個人情報が含まれる実装は避けるべき。

対応:

- 今回の本番ブロッカーはbackendのMFA/TOTPログ。
- frontendは別途、error object丸ごと出力している箇所を棚卸しする。

### 修正後に再確認するコマンド

```bash
rg -n "totp_code|Current valid code|Original token|Sanitized token|Secret decrypted|user\\.email|Request data:|traceback\\.format_exc|console\\.(log|debug|info)" \
  k_back/app k_front \
  --glob '!**/node_modules/**' \
  --glob '!**/.next/**'
```

```bash
rg -n "print\\(|logger\\.(debug|info|warning|error|exception)|console\\.(log|debug|info|warn|error)" \
  k_back/app k_front \
  --glob '!**/node_modules/**' \
  --glob '!**/.next/**'
```

### 更新後のデプロイ判定

- 機能テスト観点: 条件付きでデプロイ可能。
- 機密ログ観点: 現時点ではデプロイ非推奨。
- 最低限、MFA/TOTPコード値、現在有効なTOTPコード、メールアドレス、raw request data、traceback全文の本番出力を削除してから再判定する。

## 修正記録: 機密ログ/CSRF/CORS

対応日: 2026-07-02

対象要件:

- Cookie認証の状態変更endpointにCSRF検証が一貫適用されていない。
- backend本番ログに個人情報、業務データ、raw request data、traceback全文が残る。
- production CORSでVercel preview regexと検証用ヘッダーが許可されている。
- Google Calendar連携識別子やイベント情報がログに出る。
- frontend `console.error` がAPIエラーオブジェクトを出す箇所が残る。

### 対応内容

- [x] `k_back/app/main.py` に `csrf_cookie_auth_middleware` を追加し、Cookie認証かつ `POST` / `PUT` / `PATCH` / `DELETE` のリクエストへ共通CSRF検証を適用した。
  - `Authorization: Bearer ...` のAPI利用は従来どおりCSRF対象外。
  - Stripe webhook とCSRFトークン取得endpointは除外。
- [x] `k_back/app/main.py` のproduction CORSから Vercel preview regex を外した。
- [x] `k_back/app/main.py` のproduction CORSから `x-vercel-protection-bypass` と `X-Requested-With` を外した。
  - 開発環境側の検証用ヘッダーは残す。
- [x] MFA/TOTP検証ログから、入力TOTP、正規化後TOTP、現在有効なTOTP、secret復号詳細を削除した。
- [x] `employee_action` / `support_plan` / `calendar` 周辺のログから、raw request data、内部ID中心の詳細ログ、例外全文を削った。
- [x] Google Calendar同期失敗時に、外部API例外全文をDB/ログへ残さず `type(exc).__name__` 中心にした。
- [x] frontend実行コードの `console.error('...', errorObject)` 形式を固定文言中心へ変更した。

### 追加テスト

追加:

- `k_back/tests/security/test_deploy_safety_guards.py`

確認内容:

- TOTP値や現在有効コードをlogger行に含めない。
- raw request data と `traceback.format_exc()` を対象リファクタ経路に残さない。
- production CORSにpreview regex / bypass header / `X-Requested-With` を含めない。
- Cookie認証の状態変更リクエストにCSRF middleware がある。

実行結果:

```bash
docker exec keikakun_app-backend-1 pytest \
  tests/security/test_deploy_safety_guards.py \
  tests/core/test_mfa_security.py \
  tests/api/v1/test_csrf_protection.py \
  -q
```

- `34 passed`

```bash
npm --prefix k_front run lint
```

- 成功
- `console.error` からerror objectを外した影響で未使用catch変数のwarningが残るが、lint failureではない。

### 再判定

- 機密ログ観点: 最低限のデプロイブロッカーは解消。
- 残る注意点:
  - Cloud Build / Cloud Run の実行ログに secret / DB URL が出ていないことは、初回CD実行後に必ず確認する。
  - frontend の未使用catch変数warningは別途整理対象。
  - 本番CORSのpreview許可を外したため、preview環境から本番APIを叩くE2E運用は使えない。必要な場合は本番ではなく検証環境APIを使う。

## 再確認: デプロイ前準備とGitHub Actions側の確認範囲

確認日: 2026-07-02

### 結論

GitHub Actions側で確認するのは、secretが正しいDBや接続先を指していることだけでは不十分。

今回のAlembic移行では、以下を分けて確認する必要がある。

1. GitHub Actions secretが正しい値を参照していること。
2. 本番 `main` DBが `baseline_20260701` にstamp済みであること。
3. Cloud Build内の baseline guard が `alembic upgrade head` 前に実行されること。
4. 初回CD実行ログに `DATABASE_URL` やsecret値が露出していないこと。
5. migration成功後にCloud Run deployへ進むこと。

### 現在のCD構成確認

`.github/workflows/cd-backend.yml`:

- `main` pushでbackend CDが起動する。
- `gcloud builds submit --config cloudbuild.yml` を実行する。
- `_PROD_DATABASE_URL="${{ secrets.PROD_DATABASE_URL }}"` をCloud Build substitutionとして渡している。
- `GCP_SA_KEY`、`GCP_PROJECT_ID`、runtime用secretも同じstepで渡している。

`k_back/cloudbuild.yml`:

- production imageをbuildする。
- imageをArtifact Registryへpushする。
- push済みimageで `python scripts/alembic_baseline_guard.py` を実行する。
- guardが通った場合のみ `alembic upgrade head` を実行する。
- migration成功後にCloud Run deployを行う。

`k_back/scripts/alembic_baseline_guard.py`:

- `DATABASE_URL` に接続する。
- DBのcurrent headsを取得する。
- current revisionが `baseline_20260701` 以降でなければ終了コード1で停止する。
- DB URLやsecret値は出力しない。

### GitHub Actions側で確認する項目

GitHub Actions側では、最低限以下を確認する。

- [ ] `PROD_DATABASE_URL` がNeonDBの本番 `main` ブランチを指している。
- [ ] `PROD_DATABASE_URL` が `main_test` / `dev` / `dev_test` を指していない。
- [ ] `DATABASE_URL` と `PROD_DATABASE_URL` の役割が混同されていない。
  - test実行では既存どおり `DATABASE_URL=${{ secrets.DATABASE_URL }}` と `TEST_DATABASE_URL=${{ secrets.TEST_DATABASE_URL }}` を使う。
  - deployでは `_PROD_DATABASE_URL=${{ secrets.PROD_DATABASE_URL }}` をCloud Buildへ渡す。
- [ ] `GCP_SA_KEY` がCloud Build実行、Artifact Registry push、Cloud Run deployに必要な権限を持つ。
- [ ] `GCP_PROJECT_ID` が本番 `k-back` をdeployするGCP projectを指している。
- [ ] `FRONTEND_URL`、Cookie系設定、Stripe系secretなどruntime secretが本番向け値になっている。
- [ ] GitHub Actionsログ上で、secret値そのものが表示されていない。

### GitHub Actionsだけでは確認できない項目

以下はGitHub Actionsのsecret設定画面を見るだけでは確認できない。

- [ ] 本番 `main` DBの `alembic_version` が `baseline_20260701` になっていること。
- [ ] Cloud Build内で baseline guard が実際に通ること。
- [ ] `alembic upgrade head` が本番DBに対して成功すること。
- [ ] Cloud Buildログに `_PROD_DATABASE_URL` やsecret値が露出していないこと。
- [ ] Cloud Run deploy後、runtime環境変数が期待どおり反映されていること。

### デプロイ前に必須のDB確認

本番 `main` DBに対して、事前に以下を確認する。

```bash
DATABASE_URL="$PROD_DATABASE_URL" alembic current
```

期待値:

```text
baseline_20260701 (head) (mergepoint)
```

未反映の場合は、schema確認後に一度だけ以下を実行する。

```bash
DATABASE_URL="$PROD_DATABASE_URL" alembic stamp baseline_20260701
DATABASE_URL="$PROD_DATABASE_URL" alembic current
```

この確認が終わっていない状態でCDを走らせた場合、baseline guardが停止するのが正しい挙動。

### 初回CD実行時に確認する項目

- [ ] Cloud Build step 3 の baseline guard が成功する。
- [ ] Cloud Build step 4 の `alembic upgrade head` が成功する。
- [ ] Cloud Build step 5 の Cloud Run deploy が成功する。
- [ ] guard / Alembic / deploy のログにDB URLやsecret値が出ていない。
- [ ] deploy後のアプリが本番DBに接続できる。
- [ ] 課金・認証・通知など、今回の代表変更に関係する画面で明確な500が出ていない。

### 現時点の判定

デプロイ前準備は、コード構成としては概ね整っている。

ただし、以下が完了するまでは「準備完了」とはしない。

- 本番 `main` DBの `alembic current` が `baseline_20260701` を返すこと。
- GitHub Actions secretの接続先が本番 `main` DBと本番GCP projectを指していること。
- 初回CD実行ログでsecret露出がないことを確認すること。

## 再レビュー: backend/frontend 現行実装のセキュリティリスク評価

確認日: 2026-07-02

対象:

- `k_back/app`
- `k_front/app`
- `k_front/components`
- `k_front/lib`
- 現在の未コミット差分を含む作業ツリー

評価範囲:

- 認証Cookie / CSRF / CORS
- 権限チェック
- ログ出力と個人情報・機密情報露出
- 外部連携情報の扱い
- frontend console / API error handling

評価対象外:

- npm / pip 依存パッケージの最新CVE照合。
- DAST、SAST、ペネトレーションテスト。
- 本番Cloud Build / Cloud Run / GitHub Actionsの実ログ確認。

### 総合判定

現時点のまま本番デプロイする場合のセキュリティ評価は「要修正」。

直近レビュー時点でCriticalだったTOTPコード値そのもののINFOログは、`k_back/app/core/security.py` 上では削除済みになっている。一方で、backendにはまだ本番ログレベルで出る可能性がある `logger.error` / `logger.warning` に、個人情報、業務データ、raw request data、traceback全文、外部連携識別子が残っている。

また、cookie認証を使っているにもかかわらず、CSRF検証が状態変更endpoint全体に一貫適用されていない。frontendは状態変更時に `X-CSRF-Token` を送る実装だが、backend側で `validate_csrf` を依存注入しているendpointは一部に限られる。これはログ問題よりも優先して設計を揃えるべき。

### High: Cookie認証の状態変更endpointにCSRF検証が一貫適用されていない

該当例:

- `k_back/app/api/v1/endpoints/employee_action_requests.py`
  - `POST ""`
  - `PATCH "/{request_id}/approve"`
  - `PATCH "/{request_id}/reject"`
  - `DELETE "/{request_id}"`
- `k_back/app/api/v1/endpoints/welfare_recipients.py`
  - `POST "/"`, `PUT "/{recipient_id}"`, `DELETE "/{recipient_id}"`
- `k_back/app/api/v1/endpoints/staffs.py`
  - `PATCH "/me/name"`, `PATCH "/me/password"`, `POST "/me/email"`, `DELETE "/{staff_id}"`
- `k_back/app/api/v1/endpoints/assessment.py`
  - family / service-history / medical / hospital / employment / issue-analysis の作成・更新・削除
- `k_back/app/api/v1/endpoints/notices.py`
  - 既読化・削除

確認内容:

- CSRF保護の依存関数は `k_back/app/api/deps.py` の `validate_csrf()` として存在する。
- `messages.py`、`admin_announcements.py`、`offices.py` など一部endpointでは `Depends(validate_csrf)` が付いている。
- しかし、多数の状態変更endpointでは `get_current_user` / `require_active_billing` のみで、CSRF検証が付いていない。
- frontend側は `k_front/lib/http.ts` でPOST/PUT/PATCH/DELETE時に `X-CSRF-Token` を送るため、クライアント側の準備はあるが、backend側の検証適用範囲が不足している。

リスク:

- Cookieが自動送信される構成のため、攻撃者サイトから状態変更リクエストを誘導された場合に、CORSでレスポンスを読めなくても副作用だけ成立する可能性がある。
- `SameSite=None` が本番デフォルトになっているため、`COOKIE_SAMESITE` の本番設定が誤っている場合はCSRF耐性が弱くなる。

推奨対応:

- 状態変更endpointは原則 `Depends(validate_csrf)` を必須にする。
- Bearer認証を明示的に許可するAPIだけ例外化する。
- `POST/PUT/PATCH/DELETE` endpoint一覧に対して、CSRF依存が付いているかをテストで固定する。
- `COOKIE_SAMESITE=None` を使う必要がある場合、その理由と許可originをPRに明記する。可能なら本番も `lax` に寄せる。

### High: 本番ログに個人情報・業務データ・例外全文が残る

該当例:

- `k_back/app/services/welfare_recipient_service.py`
  - 利用者氏名をdebug出力。
  - `IntegrityError` / `SQLAlchemyError` / 予期しない例外で `str(e)` と `traceback.format_exc()` をerror出力。
- `k_back/app/scheduler/calendar_sync_scheduler.py`
  - 例外内容とtraceback全文をerror出力。
- `k_back/app/scheduler/cleanup_scheduler.py`
  - cleanup errors配列の内容とtraceback全文をerror出力。
- `k_back/app/services/approval/employee_action_executor.py`
  - `Request data: %s` で承認リクエスト内のraw payloadをINFO出力。
- `k_back/app/api/v1/endpoints/auths.py`
  - パスワードリセット関連でメールアドレスと例外文字列をwarning/error出力。
- `k_back/app/api/v1/endpoints/push_subscriptions.py`
  - メールアドレス、push endpoint断片、例外全文をログ出力。
- `k_back/app/services/assessment_service.py`
  - `current_user.email`、office id、recipient office id をINFO/ERROR出力。

リスク:

- 福祉利用者名、スタッフメールアドレス、内部ID、支援計画・アセスメント関連データ、SQLエラー内の値がCloud Logging等に残る可能性がある。
- `traceback.format_exc()` と `str(e)` は、DB接続情報、SQL、外部APIレスポンス、入力値を含むことがある。
- ログ閲覧権限を持つ人の範囲がアプリDB権限より広い場合、データアクセス制御を迂回した情報露出になる。

推奨対応:

- 本番ログ禁止: メール、氏名、TOTP/token/secret、raw request data、traceback全文、SQLAlchemy例外文字列。
- 許可する文脈: `error_type`、安全なoperation名、必要最小限の内部ID。ただしINFOではなくWARNING/ERRORの最小限にする。
- `logger.exception` / `exc_info=True` も本番では原則禁止し、必要な箇所はPIIを含まないことを確認してから使う。
- 既存の `log_policy.md` と照合し、CIで禁止パターンを検出する。

### Medium: Google Calendar連携の識別情報がログに出る

該当例:

- `k_back/app/services/google_calendar_client.py`
  - service account の `project_id`、`client_email`、`client_id` をINFO出力。
  - `calendar_id`、イベントtitle、日時をINFO出力。
- `k_back/app/services/calendar_service.py`
  - 接続テストでcalendar id、calendar name、event id、エラー文字列をログ出力。

リスク:

- 秘密鍵そのものではないが、サービスアカウント識別子・カレンダーID・イベントtitleは外部連携先の攻撃面や業務予定の推測材料になる。
- イベントtitleに利用者名や期限種別が入る場合、個人情報・業務情報の漏えいになる。

推奨対応:

- service account識別子とcalendar_idの通常ログ出力を削除する。
- 接続確認ログは成功/失敗、office_id、error_type程度に留める。
- Google Calendar縮退・代替機能の別issueでも、イベントtitleに個人名を含めるかを仕様として再確認する。

### Medium: CORSのpreview許可と検証用ヘッダーが本番に残っている

該当:

- `k_back/app/main.py`

確認内容:

- productionでも `allow_origin_regex=r"https://keikakun-front[^.]*\.vercel\.app"` が有効。
- productionでも `x-vercel-protection-bypass` が許可ヘッダーに含まれる。

リスク:

- Vercel preview全体を許可する設計は、preview環境の管理や保護設定に依存する。
- `x-vercel-protection-bypass` はVercel側のヘッダーだが、API側CORS許可に残す必要があるか再確認が必要。
- Cookie認証・credentials許可と組み合わさるため、許可originは最小化するべき。

推奨対応:

- productionではpreview regexを原則外す。必要ならpreview専用backendまたは明示的なpreview URL allowlistにする。
- `x-vercel-protection-bypass` をproduction CORS許可ヘッダーに含める必要性を確認し、不要なら削除する。

### Medium: frontend console.error がAPIエラーオブジェクトを出力している

該当例:

- `k_front/lib/http.ts`
- `k_front/lib/dal.ts`
- `k_front/components/protected/profile/NotificationSettings.tsx`
- `k_front/app/(protected)/recipients/[id]/page.tsx`
- `k_front/components/protected/admin/PlanTab.tsx`
- `k_front/components/protected/admin/AdminMenu.tsx`

リスク:

- frontend consoleはサーバーログとは違い利用者端末上の情報だが、共有端末・画面共有・サポート時にAPIエラー詳細や内部状態が見える。
- API error objectにレスポンス本文や個人情報が含まれる場合、不要な露出になる。

推奨対応:

- UIではtoast等でユーザー向け文言のみ表示し、consoleには安全な固定メッセージだけを出す。
- `console.error(error)` や `console.error(..., err)` は棚卸しし、必要な箇所は `error instanceof Error ? error.message : 'unknown'` 程度に制限する。
- 本番ビルドでconsoleを落とす方針にする場合でも、開発中に個人情報を出さない設計を優先する。

### Low: バリデーションエラーのレスポンスにinput値が残る

該当:

- `k_back/app/main.py` の `validation_exception_handler`

確認内容:

- `RequestValidationError` の `input` はHTML escapeされてレスポンスに返される。

評価:

- XSS対策としてescapeしている点は良い。
- ただし、422レスポンスに入力値そのものを返すため、パスワード・token・個人情報を含むフィールドで不要な反射が起こる可能性がある。

推奨対応:

- `input` は原則レスポンスから除外する。
- 開発環境だけ詳細を返す場合は `ENVIRONMENT != production` で分岐する。

### 改善済み・評価できる点

- TOTP検証のコード値・現在有効コードの直接ログは `k_back/app/core/security.py` では削除済み。
- 認証Cookie設定は `k_back/app/core/auth_cookie.py` に集約され、HttpOnly、secure、SameSite、domainの制御点が明確になった。
- frontend HTTP clientは状態変更methodでCSRFヘッダーを送る実装になっている。
- app_admin系endpointは `require_app_admin` が使われている箇所が多く、管理者向けAPIの入口権限は概ね明示されている。

### 優先対応順

1. 全状態変更endpointへ `validate_csrf` を適用し、テストで漏れを固定する。
2. backend本番ログから raw request data、traceback全文、メール、氏名、外部連携識別子を削除する。
3. CORS production設定からpreview regexと不要ヘッダーを外せるか判断する。
4. Google Calendarログを成功/失敗と安全なerror_typeに限定する。
5. frontend console.errorのerror object出力を整理する。
6. 422 validation responseから `input` を削る。

### デプロイ判定

- 機能面: 代表テストが通っていれば条件付きでデプロイ可能。
- セキュリティ面: 現時点ではデプロイ非推奨。

最低限、CSRF適用漏れとbackend本番ログのPII/traceback/raw data出力を修正してから、再評価する。

したがって、GitHub Actions側で確認する主対象はsecretの向きだが、それだけで完了判断はできない。DB側のbaseline状態と、Cloud Build実ログの確認まで含めてデプロイ前後の必須確認とする。
