# Schema comparison summary after cleanup

作成日: 2026-07-01

## 前提

`dev` DBから以下を削除した後のschema-only dumpを比較した。

- `dashboard_summary`
- `welfare_recipients_partitioned`
- `welfare_recipients_part_0`

## 比較結果

### `main` vs `main_test`

オブジェクト名単位では差分なし。

判断:

- `main` と `main_test` は同じschemaと見なせる。

### `dev` vs `dev_test`

差分あり。

`dev` のみに存在:

- tables
  - `alembic_version`
- indexes
  - `idx_office_welfare_recipients_office_welfare`
  - `idx_support_plan_cycles_latest_renewal`

`dev_test` のみに存在:

- tables
  - `office_count`
  - `staff_count`
- functions
  - `search_objects_by_name`

判断:

- `dev` と `dev_test` はまだ完全一致ではない。
- `office_count` / `staff_count` は検証用テーブルの可能性が高く、baseline対象から除外するのが妥当。
- `idx_office_welfare_recipients_office_welfare` / `idx_support_plan_cycles_latest_renewal` はperformance indexとして正式採用候補。

### `main` vs `dev`

差分あり。

`dev` のみに存在:

- tables
  - `alembic_version`
- indexes
  - `idx_office_welfare_recipients_office_welfare`
  - `idx_support_plan_cycles_latest_renewal`

`main` のみに存在:

- functions
  - `search_objects_by_name`

判断:

- `dev` 固有だったpartition/materialized view差分は解消された。
- 残る主要差分は `alembic_version` と2つのperformance index。
- `search_objects_by_name` は `main` にのみ存在する確認用関数の可能性がある。

### `main_test` vs `dev_test`

差分あり。

`dev_test` のみに存在:

- tables
  - `office_count`
  - `staff_count`

判断:

- `dev_test` の差分は検証用テーブルだけになっている。

## baseline記録判断

まだ全DBブランチへ同じbaselineを記録する前に、以下の判断が必要。

1. `dev` の `alembic_version` をどう整理するか。
2. `dev` の2つのperformance indexを正式採用して全DBへ揃えるか。
3. `main` の `search_objects_by_name` を正式採用するか、確認用関数として削除候補にするか。
4. `dev_test` の `office_count` / `staff_count` を削除するか。

## 推奨

- `office_count` / `staff_count` は削除候補。
- `search_objects_by_name` は用途確認後、不要なら削除候補。
- 2つのperformance indexは正式採用候補。採用する場合はAlembic migrationとして全DBブランチへ揃える。
- 上記整理後、`baseline_20260701` のstampを検討する。
