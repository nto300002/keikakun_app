# ログ安全基準 実装フロー / 受け入れ要件

作成日: 2026-07-04

## 目的

`data_access_masking_policy_todo.md` で定義したマスキング範囲を実装しても、ログ保存先・CI成果物・debug設定・静的チェックが弱いままだと、機微情報が二次流出する余地が残る。

この文書では、以下5項目について実装フローと受け入れ要件を定義する。

- ログ保存先のアクセス制御
- ログ保存期間
- CI artifacts の閲覧権限
- debug flag 管理
- 静的チェック

## 安全基準

基準は以下を採用する。

- ログには token / secret / password / MFA secret / backup code / QR code URI を保存しない。
- request body / response body / raw webhook payload / raw audit details を汎用ログに保存しない。
- email / name / phone / address / IP / User-Agent / Stripe ID / Push endpoint は用途別に mask / hash / present flag へ変換する。
- ログ保存先とCIログは、業務上必要な最小人数だけが閲覧できる。
- debug 出力は本番で有効化できない。
- sanitizer を通さない危険な `logger.*`, `console.*`, `print()` をCIで検出する。

## 1. ログ保存先のアクセス制御

### 実装フロー

1. ログ保存先を棚卸しする。
   - Google Cloud Logging
   - GitHub Actions logs
   - Vercel logs
   - Cloud Build logs
   - local docker logs
   - S3 / R2 / DB など、ログ・監査ログ・delivery log を保持する保存先
2. 保存先ごとに閲覧者・管理者・書き込み主体を一覧化する。
3. 本番ログ閲覧用の role/group を分離する。
   - production log viewer
   - staging log viewer
   - CI log viewer
   - incident responder
4. 個人アカウント直付け権限を廃止し、group / team 経由に寄せる。
5. 本番ログ閲覧権限に棚卸し期限を設定する。
6. 退職・担当解除時の権限削除手順を運用手順に追加する。
7. ログ閲覧イベント自体を監査できる保存先では、閲覧監査を有効化する。

### 受け入れ要件

- [ ] 本番ログ保存先が一覧化されている。
- [ ] 各保存先に対して owner / viewer / writer が明記されている。
- [ ] 本番ログを閲覧できるユーザーが group / team 経由で管理されている。
- [ ] 個人アカウントへの恒久的な本番ログ閲覧権限がない。
- [ ] staging と production のログ閲覧権限が分離されている。
- [ ] GitHub Actions / Cloud Build / Vercel / Cloud Logging の閲覧権限が最小権限になっている。
- [ ] 権限棚卸し手順と周期が文書化されている。
- [ ] 本番ログ閲覧が必要な障害対応時の一時権限付与・剥奪手順がある。

## 2. ログ保存期間

### 実装フロー

1. ログ種別を分類する。
   - application log
   - security event log
   - audit log
   - webhook processing log
   - CI log
   - E2E artifact
   - email delivery log
2. 種別ごとに保存目的を定義する。
3. 種別ごとに保存期間を設定する。
   - application log: 短期運用調査向け
   - security event log: セキュリティ調査向け
   - audit log: 業務監査・説明責任向け
   - CI/E2E artifact: 最短期間
4. 保存期間を超えたログの自動削除設定を確認・実装する。
5. 保存期間延長が必要な incident hold 手順を定義する。
6. raw data を含む可能性がある既存ログの削除・保持判断を行う。

### 推奨初期値

- application log: 30日
- security event log: 90日
- audit log: 1年。ただし法務・規約上必要なものは別定義
- webhook processing log: 90日
- CI log / artifact: 7日から14日
- E2E screenshot / trace / video: 7日
- local debug log: git 管理対象外、共有禁止

### 受け入れ要件

- [ ] ログ種別ごとの保存期間が明文化されている。
- [ ] Cloud Logging / Cloud Build / GitHub Actions / Vercel の保存期間設定が確認されている。
- [ ] CI artifacts の保存期間が必要最小限になっている。
- [ ] E2E trace / screenshot / video の保存期間が必要最小限になっている。
- [ ] 保存期間超過ログの削除が自動化されている、または運用手順がある。
- [ ] incident hold の条件、承認者、解除手順が定義されている。
- [ ] raw body / raw payload が含まれた既存ログの保持・削除判断が記録されている。

## 3. CI Artifacts の閲覧権限

### 実装フロー

1. CI artifacts を棚卸しする。
   - GitHub Actions logs
   - pytest output
   - Playwright trace
   - screenshot
   - video
   - coverage report
   - build artifact
2. artifact に機微情報が入り得る経路を洗い出す。
   - API response body
   - browser localStorage/sessionStorage/cookies
   - request headers
   - query string
   - screenshot 上の氏名・メール・住所・利用者情報
3. CI の artifact upload 条件を見直す。
   - success 時は保存しない
   - failure 時のみ保存
   - 保存期間を短くする
4. Playwright trace / screenshot / video の保存方針を定義する。
5. PR from fork / external contributor で secret や artifact が露出しない設定を確認する。
6. artifact ダウンロード権限を最小化する。
7. artifact 生成前に redaction helper を通す。

### 受け入れ要件

- [ ] CI artifacts の種類と保存場所が一覧化されている。
- [ ] artifacts の retention days が明示設定されている。
- [ ] Playwright trace / screenshot / video は失敗時のみ、短期保存になっている。
- [ ] `/auth/token` response body、利用者登録 response body、Cookie value がCIログに出ない。
- [ ] CIログに access token / refresh token / reset token / email verification token が出ないことをテストまたは静的チェックで確認している。
- [ ] CI artifact に localStorage / sessionStorage / cookie value が含まれる可能性を確認し、必要に応じて trace 設定を制限している。
- [ ] 外部PRで secret や本番相当のログ/artifact が取得できない。
- [ ] artifact 閲覧権限が repository admin / maintainer 等の必要最小限に制限されている。

## 4. Debug Flag 管理

### 実装フロー

1. debug 出力に関係する環境変数・設定値を棚卸しする。
   - `DEBUG`
   - `LOG_LEVEL`
   - `NEXT_PUBLIC_*`
   - Playwright debug flags
   - app-specific verbose flags
2. production で許可される log level を定義する。
3. production 起動時に危険な debug flag を検出したら fail-fast する。
4. request / response body 出力を有効化する flag は production で無効化する。
5. frontend の `console.*` 方針を定義する。
6. E2E / local debug の verbose 出力は明示 opt-in にする。
7. debug flag 変更時のレビュー観点を PR checklist に追加する。

### 受け入れ要件

- [ ] production で `DEBUG=true` 相当の設定が有効にならない。
- [ ] production で `LOG_LEVEL=DEBUG` が設定された場合、起動失敗または強制的に安全な log level へ丸める。
- [ ] request body / response body / raw payload 出力 flag は production で無効化される。
- [ ] frontend production build で不要な `console.log` / `console.debug` が残らない。
- [ ] E2E の verbose body 出力は明示 flag がない限り実行されない。
- [ ] debug flag の一覧と許可環境が文書化されている。
- [ ] debug flag 追加時のレビュー項目が PR template または review checklist にある。

## 5. 静的チェック

### 実装フロー

1. 危険なログ出力パターンを定義する。
   - `logger.*(... str(e) ...)`
   - `logger.*(... request_data ...)`
   - `logger.*(... payload ...)`
   - `logger.*(... token ...)`
   - `logger.*(... secret ...)`
   - `logger.*(... stripe_customer_id ...)`
   - `console.log(response body)`
   - `print(response.json())`
2. allowlist 可能な安全パターンを定義する。
   - `type(e).__name__`
   - `*_present`
   - `*_count`
   - masked value helper 経由
3. backend 用チェックを作る。
   - `rg` ベースの軽量チェック
   - 必要なら `ruff` custom rule / Semgrep へ移行
4. frontend 用チェックを作る。
   - `console.log` / `console.debug` の禁止
   - Error object 直接出力の禁止
   - response body 出力の禁止
5. scripts / tests / e2e も対象に含める。
6. CI に `security-log-static-check` job を追加する。
7. 例外が必要な場合は inline allow comment ではなく、allowlist ファイルに理由・期限付きで登録する。

### 初期チェック候補

```bash
rg -n "logger\\.(debug|info|warning|error|exception)\\(.*(token|secret|password|payload|request_data|response|stripe_customer_id|stripe_subscription_id)" k_back/app k_back/scripts
rg -n "console\\.(log|debug|warn|error)\\(.*(body|token|cookie|response|apiErr|error)" k_front
rg -n "print\\(.*(token|secret|password|payload|response|email|stripe)" k_back k_front
```

### 受け入れ要件

- [ ] CI にログ安全静的チェック job がある。
- [ ] backend の危険 logger pattern が検出される。
- [ ] frontend の危険 console pattern が検出される。
- [ ] scripts / tests / e2e の危険 print / console pattern が検出される。
- [ ] `type(e).__name__`, `*_present`, `*_count`, sanitizer helper 経由のログは許可される。
- [ ] allowlist は理由・期限・担当者付きで管理される。
- [ ] 既存コードの検出結果が todo として棚卸しされ、未対応件数が追跡できる。
- [ ] PR で危険ログを追加すると CI が失敗する。

## 実装順序

1. 静的チェックを warning mode で導入し、既存違反を一覧化する。
2. E2E/CIログの response body 出力を止める。
3. Stripe / token / secret 系のアプリログを sanitizer 経由へ変更する。
4. ログ保存期間と CI artifact retention を短縮する。
5. production debug flag の fail-fast を入れる。
6. ログ保存先のアクセス権限を棚卸しし、group/team 管理へ寄せる。
7. 静的チェックを blocking mode に変更する。

## 完了条件

- 上記5項目の受け入れ要件がすべて満たされている。
- `data_access_masking_policy_todo.md` に列挙した機微情報が、アプリログ・CIログ・artifact・監査ログ表示に生値で出ない。
- production で debug body 出力を有効化できない。
- 危険ログ追加が CI で検出される。
- 一時的な例外は理由・期限・担当者付きで追跡されている。

## 2026-07-05 TDD実装メモ

実装記録:

- `log_safety_controls_status_20260705.md`

実装済み:

- production debug / body dump flag の fail-fast を追加。
  - `k_back/app/core/log_safety.py`
  - `k_back/app/core/config.py`
- CI artifacts の保存方針を短期・失敗時保存へ変更。
  - Playwright HTML report: failure only / 7日
  - server logs: failure only / 7日
  - Playwright test results: failure only / 7日
- Playwright artifact 設定をテストで確認。
  - trace: `off`
  - screenshot: `only-on-failure`
  - video: `retain-on-failure`
- 静的チェックに理由・期限・担当者付き allowlist を追加。
  - `--allowlist-file`
  - expired allowlist entry は finding を抑止しない。
  - `k_back/security_log_allowlist.json` を追加。
- GitHub Actions の security check から allowlist を参照するように変更。
- backend/scripts の既存 static check finding を解消し、backend/scripts と frontend/e2e の両方を `--mode block` に変更。
- MFA/Auth、TOTP、password reset、Push、Stripe webhook、運用スクリプトのログ・標準出力から危険語および識別子紐付けを削減。

確認:

```bash
docker exec keikakun_app-backend-1 pytest \
  tests/security/test_security_log_static_check.py \
  tests/security/test_log_safety_runtime_config.py \
  tests/security/test_ci_artifact_safety.py -q
# 11 passed, 2 skipped

docker exec keikakun_app-backend-1 python scripts/security_log_static_check.py \
  --mode block --allowlist-file security_log_allowlist.json app scripts
# exit 0

docker exec keikakun_app-backend-1 python scripts/security_log_static_check.py \
  --mode block --allowlist-file security_log_allowlist.json ../k_front
# exit 0
```

補足:

- Docker 内では親ディレクトリ `.github` と `k_front` が見えないため、CI artifact 設定テストは skip される。
- ローカルでは `rg` で `.github/workflows/ci-frontend.yml` と `k_front/playwright.config.ts` の artifact 設定を確認済み。

残課題:

- Cloud Logging / Cloud Build / Vercel / GitHub の実権限確認。
- production / staging のログ閲覧 group/team 管理確認。
- Cloud Logging / Cloud Build / Vercel の retention 設定確認。
- DB audit log / email delivery log の retention 実装。
- allowlist 追加時の承認者・レビュー周期・期限切れ時の運用定義。
- screenshot / video に個人情報が含まれた場合の incident hold / 削除判断。
- backend/app と scripts の blocking 化。
- debug flag 追加時の PR checklist 化。
