# Alembic migration 検証手順

## 目的

DB enum 追加や nullable 化を含む Alembic migration を、安全に DEV / DEV_TEST / PROD / PROD_TEST へ反映するための検証手順を定める。

## 前提

- Alembic 本体は単一 `DATABASE_URL` を参照する。
- 複数DBへの通常 migration は `scripts/run_alembic_for_pair.py` で制御する。
- `alembic stamp` は schema を変更しない管理操作であり、通常 migration とは分けて扱う。
- URL や認証情報はログに出さない。

## ローカル検証

対象:

- `DEV_DATABASE_URL`
- `DEV_TEST_DATABASE_URL`

### 2026-07-07 実施結果

#### 統合済み旧テーブルの扱い

以下の旧テーブルは、現行アプリでは統合先へ移行済みとして baseline 判定の必須テーブルから除外する。

- `employee_action_requests`: `approval_requests` に統合済み。
- `role_change_requests`: `approval_requests` に統合済み。
- `office_audit_logs`: `audit_logs` に統合済み。

確認したコード上の根拠:

- `app/models/approval_request.py` が統合型 `ApprovalRequest` / `approval_requests` を定義している。
- `app/schemas/approval_request.py` が `EmployeeActionRequestData` / `RoleChangeRequestData` を `request_data` 用補助スキーマとして定義している。
- `employee_action_service.py` と `role_change_service.py` は `crud_approval_request` を使って `approval_requests` に作成・承認・却下を行う。
- `offices.py` の事務所監査ログ取得・更新時ログ作成は `crud.audit_log` / `audit_logs` を使う。
- 旧 model / CRUD ファイルは互換性コメント付きで残っているため、`Base.metadata` をそのまま使う schema 比較では旧テーブルが missing と判定される。

#### read-only schema 確認

旧 3 テーブルを除外した `Base.metadata` 比較結果:

- DEV: `metadata_missing_excluding_deprecated=[]`
- DEV_TEST: `metadata_missing_excluding_deprecated=[]`
- DEV: `required_unified_missing=[]`
- DEV_TEST: `required_unified_missing=[]`
- DEV: `deprecated_present=[]`
- DEV_TEST: `deprecated_present=[]`

結論:

- DEV / DEV_TEST は `mrg20260703p9q0` 相当の schema と判断できる。
- 旧 3 テーブル欠落は stamp を止める理由にしない。

#### baseline/stamp 実施

実行:

```bash
docker compose exec backend python scripts/run_alembic_for_pair.py --env local stamp mrg20260703p9q0
```

結果:

- DEV: `m2n3o4p5q6r7, n3o4p5q6r7s8 -> mrg20260703p9q0`
- DEV_TEST: 空の Alembic version 状態から `mrg20260703p9q0`

#### #171 migration 実施

実行:

```bash
docker compose exec backend python scripts/run_alembic_for_pair.py --env local upgrade head
```

結果:

- DEV: `mrg20260703p9q0 -> c171deadlinecal`
- DEV_TEST: `mrg20260703p9q0 -> c171deadlinecal`

#### 事後確認

DEV:

- `alembic_versions=['c171deadlinecal']`
- `calendar_sync_status.local_only=True`
- `calendar_event_type.assessment_incomplete=True`
- `calendar_events.google_calendar_id nullable=YES`
- `idx_calendar_events_cycle_type_unique` に `local_only` 条件あり
- `idx_calendar_events_status_type_unique` に `local_only` 条件あり

DEV_TEST:

- `alembic_versions=['c171deadlinecal']`
- `calendar_sync_status.local_only=True`
- `calendar_event_type.assessment_incomplete=True`
- `calendar_events.google_calendar_id nullable=YES`
- `idx_calendar_events_cycle_type_unique` に `local_only` 条件あり
- `idx_calendar_events_status_type_unique` に `local_only` 条件あり

#### テスト結果

実行:

```bash
docker compose exec backend pytest tests/services/test_calendar_refactor_services.py tests/api/v1/test_calendar.py tests/scripts/test_run_alembic_for_pair.py -q
```

結果:

- `31 passed`

### 1. read-only 事前確認

以下を確認する。

- `alembic_version` テーブルの有無
- 現在の `version_num`
- `calendar_sync_status.local_only` の有無
- `calendar_event_type.assessment_incomplete` の有無
- `calendar_events.google_calendar_id` が nullable か

この確認では DB schema を変更しない。

### 2. baseline/stamp 要否判定

`DEV_DATABASE_URL`:

- `alembic_version` に複数 revision があり、`alembic upgrade head` が overlap する場合は stamp 管理作業が必要。
- schema 実態が `mrg20260703p9q0` 相当であることを確認できた場合、承認後に `stamp --purge mrg20260703p9q0` を検討する。

`DEV_TEST_DATABASE_URL`:

- `alembic_version` が無い場合、schema 実態が `mrg20260703p9q0` 相当であることを確認できた後、承認後に `stamp mrg20260703p9q0` を検討する。

2026-07-07 時点では、DEV / DEV_TEST とも stamp 済みであり、#171 migration も `c171deadlinecal` まで適用済み。

### 3. migration 試行

stamp 管理作業が完了してから実行する。

```bash
docker compose exec backend python scripts/run_alembic_for_pair.py --env local upgrade head
```

期待:

- DEV に migration が適用される。
- DEV_TEST に同じ migration が適用される。
- どちらかが失敗した場合は非0終了し、後続へ進まない。

### 4. read-only 事後確認

以下を確認する。

- `alembic current` が head を返す。
- `calendar_sync_status.local_only` が存在する。
- `calendar_event_type.assessment_incomplete` が存在する。
- `calendar_events.google_calendar_id` が nullable。
- `idx_calendar_events_cycle_type_unique` と `idx_calendar_events_status_type_unique` が存在する。

## 本番検証

対象:

- `PROD_DATABASE_URL`
- `PROD_TEST_DATABASE_URL`

### 2026-07-07 PROD_TEST 事前接続確認

ローカル Docker backend から `PROD_TEST_DATABASE_URL` に対して read-only schema 検証を試行した。

初回確認結果:

- `PROD_TEST_DATABASE_URL` は `.env` 上に存在する。
- URL は host / username / password / database を含む。
- `sslmode` は未指定。
- `sslmode=require` を実行時に付与しても接続不可。
- 接続エラーは password authentication failure。

比較確認:

- `PROD_DATABASE_URL` は同じ Docker backend から read-only `select 1` に成功。

結論:

- 現状の `PROD_TEST_DATABASE_URL` では read-only schema 検証を実行できない。
- `PROD_TEST` の baseline stamp 要否判定は未完了。
- `PROD_TEST` に対する `alembic stamp` は実施していない。
- 本番系 migration を Cloud Build に流す前に、`PROD_TEST_DATABASE_URL` の認証情報を更新または確認する必要がある。

再確認結果:

- backend コンテナを再作成して env を再読み込みした。
- `PROD_TEST_DATABASE_URL` は接続可能になった。
- read-only schema 検証を実行した。

read-only schema 検証:

- `alembic_version_table=False`
- `alembic_versions=[]`
- `metadata_missing_excluding_deprecated=[]`
- `required_unified_missing=[]`
- `deprecated_present=[]`
- `calendar_sync_status.local_only=False`
- `calendar_event_type.assessment_incomplete=False`
- `calendar_events.google_calendar_id nullable=NO`
- `idx_calendar_events_cycle_type_unique` に `local_only` 条件なし
- `idx_calendar_events_status_type_unique` に `local_only` 条件なし

再確認後の結論:

- `PROD_TEST` の schema は `mrg20260703p9q0` 相当と判断できる。
- `PROD_TEST` は `alembic_version` がないため、#171 migration 前に baseline stamp が必要。
- `PROD_TEST` の stamp 候補は `mrg20260703p9q0`。
- `PROD_TEST` に対する `alembic stamp` はまだ実施していない。

#### baseline stamp 試行結果

初回実行:

実行:

```bash
docker compose exec backend sh -lc 'DATABASE_URL="$PROD_TEST_DATABASE_URL" alembic stamp mrg20260703p9q0'
```

結果:

- 失敗。
- `alembic_version` テーブル作成時に `permission denied for schema public`。
- `alembic_version` テーブルは作成されていない。

権限確認:

- current user: `main_test`
- `public` schema `USAGE`: `True`
- `public` schema `CREATE`: `False`
- `calendar_events` owner: `neondb_owner`
- `approval_requests` owner: `neondb_owner`
- `audit_logs` owner: `neondb_owner`
- `calendar_event_type` owner: `neondb_owner`
- `calendar_sync_status` owner: `neondb_owner`

結論:

- 現在の `PROD_TEST_DATABASE_URL` の接続ユーザーでは baseline stamp も #171 migration も実行できない。
- `PROD_TEST_DATABASE_URL` は `neondb_owner` 相当の権限を持つ migration 用 URL に更新する必要がある。
- 代替として、NeonDB 側で `main_test` に必要な権限を付与する方法もあるが、本番系 migration 用 secret は owner 権限 URL に揃える方が運用上明確。

#### PROD_TEST URL 更新後の再実行結果

実施内容:

- backend コンテナを再作成して `.env` を再読み込みした。
- `PROD_TEST_DATABASE_URL` が `neondb_owner` で接続されることを確認した。
- `public` schema `CREATE=True` を確認した。
- pytest 側で URL / DB user に `main_test` や `test` が含まれる前提だった箇所を修正した。
  - `TEST_DATABASE_URL` と `DATABASE_URL` が分離されている場合も test target として扱う。
  - `?sslmode` などの URL query を削らない。
  - sync URL を async engine で使う場合は `postgresql+psycopg` に正規化する。

pytest 確認:

```bash
docker compose exec backend pytest tests/test_database_connection.py tests/test_db_cleanup.py::TestFinalDatabaseCleanupVerification::test_verify_all_factory_data_removed tests/scripts/test_run_alembic_for_pair.py -q
```

結果:

- `16 passed`

baseline stamp 再実行:

```bash
docker compose exec backend sh -lc 'DATABASE_URL="$PROD_TEST_DATABASE_URL" alembic stamp mrg20260703p9q0'
```

結果:

- 成功。
- `Running stamp_revision  -> mrg20260703p9q0`

stamp 後 read-only 確認:

- `alembic_versions=['mrg20260703p9q0']`
- `calendar_sync_status.local_only=False`
- `calendar_event_type.assessment_incomplete=False`
- `calendar_events.google_calendar_id nullable=NO`

結論:

- `PROD_TEST` の baseline stamp は完了。
- #171 migration はまだ本番系 DB には適用していない。
- 次に本番系へ進む場合は、Cloud Build と同じ経路で `scripts/run_alembic_for_pair.py --env prod upgrade head` を実行し、`PROD_DATABASE_URL` と `PROD_TEST_DATABASE_URL` の両方へ `c171deadlinecal` を適用する。

### 1. PROD_TEST の事前確認

PROD に直接 migration を試す前に、PROD_TEST を検証対象にする。

確認項目:

- `alembic_version` テーブルの有無
- schema が `mrg20260703p9q0` 相当か
- migration 対象の enum / column / index の現状

### 2. PROD_TEST の baseline/stamp

`PROD_TEST_DATABASE_URL` に `alembic_version` が無い場合、schema 実態の確認と承認後に以下を検討する。

```bash
DATABASE_URL=$PROD_TEST_DATABASE_URL alembic stamp mrg20260703p9q0
```

これは schema 変更ではなく、Alembic 管理位置を記録する操作。

### 3. PROD_TEST で migration 事前実行

CI/CD に組み込む前に、PROD_TEST 単体で migration が通ることを確認する。

```bash
DATABASE_URL=$PROD_TEST_DATABASE_URL alembic upgrade head
```

期待:

- enum 追加が成功する。
- nullable 化が成功する。
- index 再作成が成功する。
- `alembic current` が head を返す。

### 4. CI/CD での本番反映

Cloud Build では `scripts/run_alembic_for_pair.py --env prod upgrade head` を使う。

対象順:

1. `PROD_DATABASE_URL`
2. `PROD_TEST_DATABASE_URL`

Cloud Run runtime の `DATABASE_URL` は `PROD_DATABASE_URL` のまま維持する。

### 5. 本番事後確認

read-only で以下を確認する。

- `PROD_DATABASE_URL` / `PROD_TEST_DATABASE_URL` の両方で `alembic current` が head。
- `calendar_sync_status.local_only` が存在する。
- `calendar_event_type.assessment_incomplete` が存在する。
- `calendar_events.google_calendar_id` が nullable。
- 期限カレンダー API が Google Calendar 未接続でも応答する。
- 既存 Google Calendar 自動同期で `pending` / `synced` イベントの挙動が壊れていない。

## 注意点

- `stamp` は自動化された deploy pipeline に混ぜない。
- `stamp` は必ず schema 実態の確認後、明示承認を得て実行する。
- 複数DB間で atomic な同時反映はできない。
- 失敗時は、どのDBまで反映されたかを確認してから再実行する。
