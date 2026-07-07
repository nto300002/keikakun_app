# ログ安全基準 実装状況

作成日: 2026-07-05

対象:

- `log_safety_standards_implementation_flow.md`
- `.github/workflows/ci-frontend.yml`
- `.github/workflows/security-check.yml`
- `k_back/app/core/log_safety.py`
- `k_back/scripts/security_log_static_check.py`
- `k_back/security_log_allowlist.json`

## 結論

TDDで以下を実装した。

- production debug / body dump flag の fail-fast。
- CI artifacts の retention 短縮と失敗時保存化。
- Playwright trace / screenshot / video の失敗時スコープ確認。
- 静的チェック allowlist の理由・期限・担当者付き管理。
- CI で frontend/e2e の危険ログ追加を blocking する設定。
- backend/scripts の既存 static check finding を解消し、CI のログ安全静的チェックを blocking 化。
- Playwright trace を `off` に変更し、trace 内の cookie / localStorage / sessionStorage 露出リスクを低減。

ただし、ログ保存先の実IAM権限、Cloud Logging / Cloud Build / Vercel の実保存期間、GitHub artifact の実閲覧権限はローカルコードだけでは確認できないため、運用確認項目として残す。

## 1. ログ保存先のアクセス制御

現時点の棚卸し:

| 保存先 | 用途 | writer | viewer 推奨 | owner 推奨 | 状態 |
| --- | --- | --- | --- | --- | --- |
| Google Cloud Logging | backend production logs | Cloud Run / Cloud Build SA | production log viewer group | platform/admin group | 実IAM確認が必要 |
| Cloud Build logs | production deploy / migration logs | Cloud Build | production deploy maintainer group | platform/admin group | 実IAM確認が必要 |
| GitHub Actions logs | CI / security check logs | GitHub Actions | repository maintainer | repository admin | repo設定確認が必要 |
| GitHub Actions artifacts | Playwright report / server logs / traces | GitHub Actions | repository maintainer | repository admin | workflow retention は設定済み |
| Vercel logs | frontend production logs | Vercel runtime | frontend production maintainer group | platform/admin group | 実権限確認が必要 |
| local docker logs | local development only | developer machine | local developer only | local developer | 共有禁止 |
| DB audit logs | app audit trail | backend app | owner/app_admin with masking | DB/admin group | API表示マスクは別タスクで部分対応 |
| email delivery log | delivery troubleshooting | backend app | app_admin_sensitive/system | DB/admin group | 全経路確認が必要 |

受け入れ状況:

- 本番ログ保存先の一覧化: **部分達成**
- owner / viewer / writer 明記: **文書上は達成、実IAM確認は未達**
- group / team 経由管理: **未確認**
- 個人アカウント恒久権限なし: **未確認**
- staging / production 分離: **未確認**
- 権限棚卸し周期: **未実装**
- incident時の一時権限付与・剥奪手順: **未実装**

## 2. ログ保存期間

推奨初期値:

| ログ種別 | 保存期間 | 状態 |
| --- | ---: | --- |
| application log | 30日 | Cloud Logging設定確認が必要 |
| security event log | 90日 | Cloud Logging設定確認が必要 |
| audit log | 1年 | DB retention 実装が必要 |
| webhook processing log | 90日 | Cloud Logging設定確認が必要 |
| CI log | GitHub設定依存 | repository設定確認が必要 |
| CI artifact | 7日 | workflowで設定済み |
| E2E screenshot / trace / video | 7日 | workflowで設定済み |
| local debug log | 共有禁止 | 文書上の運用 |

実装済み:

- `ci-frontend.yml` の Playwright report / server logs / test results は `retention-days: 7`。
- Playwright HTML report は成功時保存をやめ、失敗時のみ保存。

未達:

- Cloud Logging / Cloud Build / Vercel の実保存期間確認。
- DB audit log / email delivery log の自動削除方針。
- raw body / raw payload が含まれた既存ログの削除・保持判断。
- incident hold の承認者・解除手順。

## 3. CI Artifacts の閲覧権限

実装済み:

- Playwright report: 失敗時のみ保存、7日。
- server logs: 失敗時のみ保存、7日。
- Playwright test-results: 失敗時のみ保存、7日。
- Playwright config:
  - `trace: 'off'`
  - `screenshot: 'only-on-failure'`
  - `video: 'retain-on-failure'`
- E2E helper は response body を sanitizer 経由でログ出力する。
- frontend/e2e 危険ログは CI の static check で blocking。

未達:

- GitHub repository の artifact download 権限確認。
- fork PR で secrets / production相当artifact が取得できないことの設定確認。
- Playwright trace は `off` に変更済み。screenshot / video に画面上の個人情報が含まれる可能性は failure artifact の短期保存と閲覧権限確認で管理する。

## 4. Debug Flag 管理

実装済み:

- `k_back/app/core/log_safety.py` を追加。
- `validate_production_log_safety()` で production 時に以下を拒否する。
  - `DEBUG=true`
  - `LOG_LEVEL=DEBUG|TRACE|NOTSET`
  - `LOG_REQUEST_BODY`
  - `LOG_RESPONSE_BODY`
  - `LOG_RAW_PAYLOAD`
  - `DEBUG_BODY`
  - `BODY_LOGGING_ENABLED`
- `Settings` の validator から起動時に検証する。

未達:

- frontend production build の `console.log` / `console.debug` 完全削除は lint/static check 側で継続確認が必要。
- E2E verbose body 出力の明示 opt-in 管理は helper 実装済みだが、flag一覧文書化は継続。
- debug flag 追加時の PR checklist 反映。

## 5. 静的チェック

実装済み:

- `k_back/scripts/security_log_static_check.py` が以下を検出する。
  - backend `logger.*`
  - Python `print()`
  - frontend/e2e `console.log/debug/warn/error`
- safe pattern:
  - `type(e).__name__`
  - `*_present`
  - `*_count`
  - `mask_*`
  - `sanitize_*`
  - `redact`
- `--mode block` で finding がある場合に失敗する。
- `--allowlist-file` を追加。
- allowlist entry は以下を必須にする。
  - `path`
  - `call_type`
  - `reason`
  - `owner`
  - `expires_on`
- expired allowlist entry は finding を抑止しない。
- CI は `k_back/security_log_allowlist.json` を参照する。
- frontend/e2e と backend/scripts は blocking。

未達:

- allowlist のレビュー運用。
- external SaaS / Cloud 側のログ権限・保存期間の実設定確認。

## TDD確認

実行:

```bash
docker exec keikakun_app-backend-1 pytest \
  tests/security/test_security_log_static_check.py \
  tests/security/test_log_safety_runtime_config.py \
  tests/security/test_ci_artifact_safety.py -q
```

結果:

```text
11 passed, 2 skipped
```

補足:

- `test_ci_artifact_safety.py` は Docker 内で親ディレクトリ `.github` と `k_front` がマウントされない場合は skip する。
- ローカルでは `rg` で `.github/workflows/ci-frontend.yml` と `k_front/playwright.config.ts` の設定を確認済み。

確認:

```bash
rg -n "if: always\\(\\)|retention-days: 14|retention-days: [0-9]+|Upload Playwright HTML report|trace:|screenshot:|video:" \
  .github/workflows/ci-frontend.yml k_front/playwright.config.ts
```

確認結果:

- `retention-days: 7` のみ。
- Playwright report / server logs / test-results は失敗時保存。
- trace は `off`。
- screenshot / video は失敗時のみに限定。

追加確認:

```bash
docker exec keikakun_app-backend-1 python scripts/security_log_static_check.py \
  --mode block --allowlist-file security_log_allowlist.json app scripts

# exit 0

docker exec keikakun_app-backend-1 python scripts/security_log_static_check.py \
  --mode block --allowlist-file security_log_allowlist.json ../k_front

# exit 0
```

## 次に必要な作業

1. Cloud Logging / Cloud Build / Vercel / GitHub の実権限と保存期間を確認する。
2. GitHub artifact download 権限と fork PR 時の secret / artifact 露出設定を確認する。
3. DB audit log / email delivery log の retention と削除方針を決める。
4. allowlist 追加時の承認者・レビュー周期・期限切れ時の運用を定義する。
5. screenshot / video に個人情報が含まれた場合の incident hold / 削除判断を定義する。
