# Schema comparison summary

作成日: 2026-07-01

## 目的

Alembicの新baseline revisionをDBへ記録する前に、NeonDB各ブランチのschema-only dumpを比較し、同じbaselineを記録してよい状態か確認する。

## 比較対象

- `main_schema_20260701.sql`
- `main_test_schema_20260701.sql`
- `dev_schema_20260701.sql`
- `dev_test_schema_20260701.sql`

## 比較結果

### `main` vs `main_test`

実質同一。

差分は `pg_dump` が出力する `restrict` / `unrestrict` のランダム文字列のみ。

判断:

- `main` と `main_test` は、同じbaseline revisionを記録する候補にできる。

### `dev` vs `dev_test`

差分あり。

`dev` のみに存在:

- tables
  - `alembic_version`
  - `welfare_recipients_part_0`
  - `welfare_recipients_partitioned`
- materialized views
  - `dashboard_summary`
- indexes
  - `idx_dashboard_summary_office_deadline`
  - `idx_dashboard_summary_office_furigana`
  - `idx_office_welfare_recipients_office_welfare`
  - `idx_support_plan_cycles_latest_renewal`

`dev_test` のみに存在:

- tables
  - `office_count`
  - `staff_count`
- functions
  - `search_objects_by_name`

判断:

- `dev` と `dev_test` は同一schemaではない。
- この状態で同じbaselineを記録すると、後続migrationの前提がDBブランチ間でずれる可能性がある。

### `main` vs `dev`

差分あり。

`dev` のみに存在:

- tables
  - `alembic_version`
  - `welfare_recipients_part_0`
  - `welfare_recipients_partitioned`
- materialized views
  - `dashboard_summary`
- indexes
  - `idx_dashboard_summary_office_deadline`
  - `idx_dashboard_summary_office_furigana`
  - `idx_notices_office_created`
  - `idx_notices_recipient_created`
  - `idx_notices_recipient_read_created`
  - `idx_office_welfare_recipients_office_welfare`
  - `idx_plan_deliverables_cycle_type`
  - `idx_support_plan_cycles_latest_renewal`
  - `idx_support_plan_cycles_office_latest_renewal`
  - `idx_support_plan_cycles_recipient_office_latest`
  - `idx_support_plan_statuses_office_latest_step`

`main` のみに存在:

- functions
  - `search_objects_by_name`

判断:

- `dev` は性能改善・試験的構造・Alembic管理状態が `main` より進んでいる。
- `main` と `dev` を同一baselineとして扱う前に、これらの差分を採用するか除外するか決める必要がある。

### `main_test` vs `dev_test`

差分あり。

`dev_test` のみに存在:

- tables
  - `office_count`
  - `staff_count`
- indexes
  - `idx_notices_office_created`
  - `idx_notices_recipient_created`
  - `idx_notices_recipient_read_created`
  - `idx_plan_deliverables_cycle_type`
  - `idx_support_plan_cycles_office_latest_renewal`
  - `idx_support_plan_cycles_recipient_office_latest`
  - `idx_support_plan_statuses_office_latest_step`

判断:

- `dev_test` も `main_test` より一部schemaが進んでいる。
- `office_count` / `staff_count` は一時的な検証テーブルの可能性があるため、baselineに含める前に用途確認が必要。

## baseline記録判断

現時点では、全DBブランチへ同じ `baseline_20260701` を記録しない。

理由:

- `main` / `main_test` は実質同一だが、`dev` / `dev_test` は差分がある。
- `dev` には `alembic_version` が既に存在し、他3ブランチには存在しない。
- `dev` にはpartition/materialized view/index差分がある。
- `dev_test` には `office_count` / `staff_count` のような用途不明テーブルがある。

## 次の判断事項

1. `dev` のみにある `welfare_recipients_partitioned` / `welfare_recipients_part_0` を正式採用するか。
2. `dev` のみにある `dashboard_summary` materialized viewを正式採用するか。
3. `dev` / `dev_test` にある性能改善indexを正式採用するか。
4. `dev_test` の `office_count` / `staff_count` を残す必要があるか。
5. `search_objects_by_name` を正式機能として残すか、確認用関数として削除候補にするか。
6. baselineを `main/main_test` 基準にするか、`dev/dev_test` の差分を整理してから全DB共通にするか。

## dev固有差分の追加確認

### `alembic_version`

`dev` には `alembic_version` が存在する。

値:

```text
m2n3o4p5q6r7
n3o4p5q6r7s8
```

判断:

- 既に確認済みの通り、現在のDB実態を完全には表していない。
- 新baselineへ移行する場合は、既存値を正とは見なさず、整理対象にする。

### `welfare_recipients_partitioned` / `welfare_recipients_part_0`

`dev` のみに存在するpartitioned table。

確認結果:

```text
welfare_recipients_partitioned: 0 rows
welfare_recipients_part_0: 0 rows
```

リポジトリ内確認:

- アプリコードからの参照は見つからない。
- migrationにも正式な作成手順は見つからない。
- `md_files_design_note/db/db.md` にDB調査結果として名前が残っている。

判断:

- 現時点では正式採用ではなく、検証用または途中実験の残骸である可能性が高い。
- baselineに含める前に削除候補として扱うのが妥当。
- 少なくとも `main` / `main_test` へ反映する理由は現時点では弱い。

### `dashboard_summary`

`dev` のみに存在するmaterialized view。

確認結果:

```text
dashboard_summary: 9 rows
```

関連index:

```text
idx_dashboard_summary_office_deadline
idx_dashboard_summary_office_furigana
```

リポジトリ内確認:

- `k_back/tests/crud/test_crud_dashboard_summary.py` が存在する。
- 一方、現時点の主要アプリコードで直接利用されているかは追加確認が必要。

判断:

- 完全な残骸とは断定しない。
- dashboard高速化の検証または未統合実装の可能性がある。
- baselineに含めるかは、アプリコードで利用する方針があるかを確認してから決める。
- 本番安全性を優先するなら、baseline前に正式採用/非採用を切り分ける。

### performance系index

`dev` に存在するperformance系index:

```text
idx_notices_office_created
idx_notices_recipient_created
idx_notices_recipient_read_created
idx_office_welfare_recipients_office_welfare
idx_plan_deliverables_cycle_type
idx_support_plan_cycles_latest_renewal
idx_support_plan_cycles_office_latest_renewal
idx_support_plan_cycles_recipient_office_latest
idx_support_plan_statuses_office_latest_step
```

関連ドキュメント:

```text
md_files_design_note/task/todo/refactor/performance/db_optimization_indexes.sql
md_files_design_note/task/todo/refactor/performance/performance.md
```

判断:

- 検証用の残骸ではなく、性能改善として正式採用候補。
- ただし、全DBブランチに揃っていないため、このままbaselineへ含めると環境差分が残る。
- 正式採用する場合は、baseline前またはbaseline直後のAlembic migrationとして整理するのが妥当。
- 本番適用済みかどうかを確認し、未適用なら本番反映計画が必要。

## dev固有差分の暫定分類

| 差分 | 暫定分類 | 理由 |
| --- | --- | --- |
| `alembic_version` | 整理対象 | 現在DB実態を表していない |
| `welfare_recipients_partitioned` | 削除候補 | 0件、コード参照なし、正式migrationなし |
| `welfare_recipients_part_0` | 削除候補 | 0件、partition検証の残骸の可能性 |
| `dashboard_summary` | 要判断 | 9件あり、テスト参照あり、未統合実装の可能性 |
| `idx_dashboard_summary_*` | 要判断 | `dashboard_summary` 採否に依存 |
| performance系index | 正式採用候補 | performanceドキュメントに対応、環境差分解消が必要 |

## 推奨

本番安全性を優先するなら、まず `main` / `main_test` を基準にする。

ただし、`dev` / `dev_test` にある性能改善indexがすでにアプリ性能改善として必要なら、正式なAlembic migrationとして整理したうえで `main` / `main_test` に反映する。

その後、4ブランチのschema差分が許容範囲に収まった時点で、`baseline_20260701` を記録する。
