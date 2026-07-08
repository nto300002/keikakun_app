## CD エラー切り分けメモ

### 2026-07-08 read-only 確認結果

`backend` コンテナは通常起動時に `/app` bind mount 参照で `Too many open files: '/app'` が発生して停止していたため、検証時は `PYTHONPATH` を外し `/tmp` から Python を起動した。DB URL や認証情報は出力していない。

| 対象 | 接続ユーザー | alembic_version | `calendar_sync_status.local_only` | `calendar_event_type.assessment_incomplete` | `calendar_events.google_calendar_id` |
| --- | --- | --- | --- | --- | --- |
| `DEV_DATABASE_URL` | `neondb_owner` | `c171deadlinecal` | あり | あり | nullable |
| `DEV_TEST_DATABASE_URL` | `neondb_owner` | `c171deadlinecal` | あり | あり | nullable |
| `PROD_DATABASE_URL` | `neondb_owner` | `mrg20260703p9q0` | なし | なし | not nullable |
| `PROD_TEST_DATABASE_URL` | `neondb_owner` | `mrg20260703p9q0` | なし | なし | not nullable |

### managed stamp 判定

`PROD_DATABASE_URL` / `PROD_TEST_DATABASE_URL` は `alembic_version` が存在し、現在値は `mrg20260703p9q0`。これは baseline/stamp 不足ではなく、`c171deadlinecal` が未適用の状態と判定する。

そのため、現時点の対応は `alembic stamp` ではなく通常の Alembic migration 適用。`PROD_TEST` も `neondb_owner` で接続できているため、NeonDB の owner 権限不足ではなく、単純に migration がまだ反映されていないことが主要因。

CD pytest の失敗に出ている `invalid input value for enum calendar_sync_status: "local_only"` は、pytest が参照するテスト DB 側にも `c171deadlinecal` が反映されていない場合に再現する。Cloud Build の本番 migration より前に pytest が走るため、CD の pytest 用 DB を事前に migration する、または `TEST_DATABASE_URL` が migration 済みの DB を指すようにする必要がある。

### 対応内容

CD pytest の前に GitHub Actions 上で `TEST_DATABASE_URL` を対象に Alembic migration を実行する方針とした。`migrations/env.py` は `DATABASE_URL` を Alembic 接続先として参照するため、pytest 前の migration step では `DATABASE_URL=${{ secrets.TEST_DATABASE_URL }}` として `alembic upgrade head` を実行する。

Cloud Build 側では、現在の `k_back/cloudbuild.yml` で本番反映前に `PROD_DATABASE_URL` と `PROD_TEST_DATABASE_URL` の両方へ migration を実行する構成になっている。両DBとも `alembic_baseline_guard.py` による baseline 管理確認を通してから migration する。

実装対象:

- `.github/workflows/cd-backend.yml`
  - pytest 前に `Verify test DB Alembic baseline` を追加
  - pytest 前に `Run Alembic migrations for test DB` を追加

関連確認:

- `k_back/cloudbuild.yml`
  - `_PROD_TEST_DATABASE_URL` に対する baseline guard は既に存在
  - `scripts/run_alembic_for_pair.py --env prod upgrade head` により `PROD_DATABASE_URL` / `PROD_TEST_DATABASE_URL` の同時 migration を実行

残る確認:

- GitHub Actions の `TEST_DATABASE_URL` secret が、意図した test DB を `neondb_owner` で指していること
- GitHub Actions 上で pytest 前 migration が成功すること
- Cloud Build 上で `PROD_DATABASE_URL` / `PROD_TEST_DATABASE_URL` の両方が `c171deadlinecal` まで進むこと
- CD 成功後、read-only で `PROD` / `PROD_TEST` の `alembic_version` と enum 追加状態を再確認すること

### 代表エラー

CD pytest では、少なくとも以下のエラーが確認された。

```text
sqlalchemy.exc.DataError:
(psycopg.errors.InvalidTextRepresentation)
invalid input value for enum calendar_sync_status: "local_only"
```

この enum 不足で transaction abort が起き、その後に複数の `500` や `InFailedSqlTransaction` が連鎖していた。したがって本件の直接対策は、pytest 実行前に `TEST_DATABASE_URL` へ Alembic migration を適用すること。
