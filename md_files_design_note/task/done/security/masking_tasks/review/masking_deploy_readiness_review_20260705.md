# マスキング対応 デプロイ可否レビュー

作成日: 2026-07-05

## 結論

現時点では **この作業ツリーをそのままデプロイ不可** と判断する。

ただし、今回のマスキング / ログ安全改善そのものは一部デプロイ候補になり得る。  
その場合は、無関係な差分を除外し、対象ファイルだけを切り出した PR として扱う必要がある。

## 判断対象

- `md_files_design_note/task/todo/security/masking_tasks/README.md`
- `md_files_design_note/task/todo/security/data_access_masking_policy_todo.md`
- 現在の親ディレクトリ / `k_back` / `k_front` の作業ツリー
- 直近のテスト・静的チェック結果

## デプロイ不可と判断した理由

### 1. 作業ツリーに無関係な大量削除が含まれている

親ディレクトリで `md_files_design_note/task/todo/refactor/...` 配下に大量の `D` が出ている。

確認時点の差分概要:

```text
43 files changed, 386 insertions(+), 78117 deletions(-)
```

この削除差分は、今回のマスキング / ログ安全対応と直接関係しない可能性が高い。  
この状態でまとめて PR 化またはデプロイすると、意図しないドキュメント削除を混入させるリスクがある。

判断:

- この作業ツリー全体をそのままデプロイ対象にしてはいけない。
- staging 対象はマスキング / ログ安全対応の関連ファイルに限定する。
- 無関係な `D` は別作業として扱うか、ユーザー確認後に整理する。

### 2. マスキング要件はまだ部分達成

`data_access_masking_policy_todo.md` と `masking_tasks/README.md` の基準では、以下がまだ未完了である。

未完了:

- welfare recipient list/detail の権限別 serializer 分離。
- assessment / support plan / monitoring / PDF download 周辺の表示制限。
- audit log 保存前 sanitizer。
- audit log action 別 allowlist schema。
- backend/scripts の危険ログ検出解消。
- DB audit log / email delivery log の retention と削除方針。
- Cloud Logging / Cloud Build / Vercel / GitHub の実権限・保存期間確認。
- production / staging のログ閲覧 group/team 管理確認。
- backend/app と scripts の static check blocking 化。

別 issue 扱い:

- MFA/Auth の再取得不可・管理者一括有効化レスポンス縮小・ログ再露出防止は issue #152 に切り出し済み。

判断:

- 「マスキング安全基準を完全達成した」としてのデプロイは不可。
- 「代表的な漏えい経路を塞ぐ部分的なセキュリティ改善」としてなら、残課題を明記したうえでデプロイ候補にできる。

### 3. backend/scripts の静的チェックが warning finding を残している

frontend/e2e の blocking static check は通過しているが、backend/scripts は warning mode で既存検出が残っている。

主な検出領域:

- `app/api/deps.py`
- `app/api/v1/endpoints/auths.py`
- MFA/Auth 周辺
- password reset / token / secret 関連ログ
- 運用スクリプトの `print()`
- webpush 検証スクリプトの response object 出力候補

判断:

- backend/scripts の warning finding が残っているため、ログ安全基準の完全達成とは言えない。
- ただし、既存findingをすべて潰す前に frontend/e2e blocking と代表的なログマスクをデプロイする判断は可能。
- その場合も「backend/scripts は warning継続」と PR に明記する。

## デプロイ候補にできる範囲

以下は、無関係な差分を除外すればデプロイ候補にできる。

### Backend

- audit log details 表示マスク。
- webhook payload 表示用マスク。
- employee action request の `request_data` 表示マスク。
- inquiry list/detail の sender metadata / delivery_log マスク。
- app-admin office detail の office contact / staff email マスク。
- push subscription endpoint の通常レスポンス `<registered>` 化。
- Stripe webhook / portal session 周辺ログの代表的マスク。
- production debug / body dump flag の fail-fast。
- static check allowlist file 対応。

### Frontend

- app-admin audit log の raw `JSON.stringify(log.details)` 表示廃止。
- E2E `/auth/token` body 出力の sanitizer 経由化。
- E2E recipient form response body 出力の sanitizer 経由化。
- Push購読解除失敗時の raw `apiErr` console 出力廃止。
- Playwright artifact 設定の短期・失敗時保存確認。

### Workflow / Docs

- `ci-frontend.yml` の artifacts retention を7日に統一。
- Playwright HTML report を失敗時のみ保存。
- `security-check.yml` で static check allowlist を参照。
- safety standards / masking tasks のレビュー記録。

## デプロイ前に必須の整理

1. 親ディレクトリの無関係な `D` を staging しない。
2. `k_back` / `k_front` / workflows の対象差分を手動で確認する。
3. `md_files_design_note/task/todo/refactor/...` の削除差分は、今回PRから除外する。
4. `.DS_Store`、`.coverage` は staging しない。
5. PR本文に「マスキング安全基準は部分達成、残タスクあり」と明記する。

## 推奨する staging 方針

staging 対象:

- `.github/workflows/ci-frontend.yml`
- `.github/workflows/security-check.yml`
- `k_back` のマスキング / ログ安全関連変更
- `k_front` のマスキング / E2E sanitizer 関連変更
- `md_files_design_note/task/todo/security/masking_tasks/`
- `md_files_design_note/task/todo/security/safety_standards/`
- `md_files_design_note/task/todo/security/data_access_masking_policy_todo.md`

staging しない:

- `md_files_design_note/task/todo/refactor/...` の大量削除
- `.DS_Store`
- `.coverage`
- 今回のセキュリティ対応と関係しないドキュメント移動・削除

## 確認済みテスト

直近確認:

```bash
docker exec keikakun_app-backend-1 pytest \
  tests/security/test_security_log_static_check.py \
  tests/security/test_log_safety_runtime_config.py \
  tests/security/test_ci_artifact_safety.py \
  tests/security/test_deploy_safety_guards.py -q

# 19 passed, 2 skipped
```

```bash
docker exec keikakun_app-backend-1 python scripts/security_log_static_check.py \
  --mode block --allowlist-file security_log_allowlist.json ../k_front

# exit 0
```

設定確認:

```bash
rg -n "if: always\\(\\)|retention-days: 14|retention-days: [0-9]+|Upload Playwright HTML report|trace:|screenshot:|video:" \
  .github/workflows/ci-frontend.yml k_front/playwright.config.ts
```

結果:

- `retention-days: 7` のみ。
- Playwright report / server logs / test-results は失敗時保存。
- trace / screenshot / video は失敗時または retry 時に限定。

## 追加で推奨する確認

デプロイ候補PRにする前に、最低限以下を再実行する。

```bash
docker exec keikakun_app-backend-1 pytest \
  tests/utils/test_privacy_utils.py \
  tests/services/test_sensitive_access_service.py \
  tests/security/test_security_log_static_check.py \
  tests/security/test_log_safety_runtime_config.py \
  tests/security/test_ci_artifact_safety.py \
  tests/security/test_deploy_safety_guards.py \
  tests/api/v1/test_admin_audit_logs.py \
  tests/api/v1/test_admin_offices.py \
  tests/api/v1/test_employee_action_requests.py \
  tests/api/v1/test_inquiry_endpoints.py \
  tests/api/v1/test_push_subscriptions.py \
  tests/api/test_billing.py -q
```

```bash
cd k_front
npm run lint
```

## 最終判定

この作業ツリー全体: **デプロイ不可**

理由:

- 無関係な大量削除差分が混在している。
- マスキング安全基準は部分達成であり、完全達成ではない。
- backend/scripts の warning finding が残っている。

切り出しPR: **条件付きでデプロイ候補**

条件:

- 無関係差分を除外する。
- 対象テストを再実行して通す。
- 残タスクをPR本文に明記する。
- MFA/Auth は issue #152 の別対応として扱う。

## 2026-07-05 削除差分整理

確認コマンド:

```bash
git diff --name-status -- \
  md_files_design_note/task/todo/refactor \
  md_files_design_note/task/todo/security/data_access_masking_policy_todo.md

git diff --stat -- \
  md_files_design_note/task/todo/refactor \
  md_files_design_note/task/todo/security/data_access_masking_policy_todo.md
```

確認結果:

```text
39 files changed, 78293 deletions(-)
```

削除差分の分類:

| 分類 | 削除元 | 移動・整理先らしき場所 | 件数/内容 | 今回PRでの扱い |
| --- | --- | --- | --- | --- |
| maintainability 完了整理 | `md_files_design_note/task/todo/refactor/maintainability/...` | `md_files_design_note/task/done/maintainability/...` | Alembic、schema snapshots、review、security review、maintainability research など | マスキング対応とは別作業。今回PRに混ぜない |
| performance v0.1 完了整理 | `md_files_design_note/task/todo/refactor/performance/...` | `md_files_design_note/task/done/performance-v0.1/...` | `performance.md`、`app_fix_list.md`、`db_fix_list.md`、index SQL、review | マスキング対応とは別作業。今回PRに混ぜない |
| performance v0.2 再配置 | `md_files_design_note/task/todo/refactor/performance/...` | `md_files_design_note/task/todo/refactor/performance-v0.2/...` | performance 系タスクの新バージョン配置 | 別PRで移動として扱う |
| masking policy 再配置 | `md_files_design_note/task/todo/security/data_access_masking_policy_todo.md` | `md_files_design_note/task/todo/security/masking_tasks/data_access_masking_policy_todo.md` | マスキングタスク配下へ移動された可能性 | 今回のマスキング文書整理として含めてもよいが、削除元と新規先をセットで staging する |

見解:

- 削除差分の大半は、ファイル削除ではなく `todo` から `done` または versioned directory への移動整理に見える。
- ただし Git 上は rename としてではなく `D` + `??` に見えているため、そのまま staging すると「大量削除」としてレビューされる。
- マスキング / ログ安全のデプロイ可否レビューに含めるべき削除は、`data_access_masking_policy_todo.md` の移動整理のみ。
- maintainability / performance の削除・移動は、セキュリティ対応PRから除外するのが安全。

今回PRで staging しない削除:

```text
md_files_design_note/task/todo/refactor/maintainability/**
md_files_design_note/task/todo/refactor/performance/**
```

今回PRに含める場合はセットで staging するもの:

```text
md_files_design_note/task/todo/security/data_access_masking_policy_todo.md
md_files_design_note/task/todo/security/masking_tasks/data_access_masking_policy_todo.md
```

理由:

- `data_access_masking_policy_todo.md` は masking_tasks 配下に同名ファイルが存在するため、タスク構成整理として説明可能。
- 削除元だけ、または新規先だけを staging すると履歴上の移動意図が不明確になる。

推奨 staging 方針:

1. セキュリティ対応PRでは、`md_files_design_note/task/todo/security/masking_tasks/**` と `safety_standards/**` を中心に staging する。
2. `data_access_masking_policy_todo.md` は移動として扱うなら削除元・移動先をセットにする。
3. `maintainability` / `performance` の移動整理は別PRに分ける。
4. `.DS_Store`、`.coverage` は staging しない。

デプロイ可否への影響:

- 削除差分を含めた作業ツリー全体は引き続き **デプロイ不可**。
- マスキング / ログ安全の対象差分のみを切り出せば **条件付きでデプロイ候補**。
- `backend/scripts` の static check は追加修正により block mode で通過済みのため、以前の「warning finding 残あり」は解消済みとして扱う。

追加確認:

```bash
docker exec keikakun_app-backend-1 python scripts/security_log_static_check.py \
  --mode block --allowlist-file security_log_allowlist.json app scripts

# exit 0

docker exec keikakun_app-backend-1 python scripts/security_log_static_check.py \
  --mode block --allowlist-file security_log_allowlist.json ../k_front

# exit 0
```
