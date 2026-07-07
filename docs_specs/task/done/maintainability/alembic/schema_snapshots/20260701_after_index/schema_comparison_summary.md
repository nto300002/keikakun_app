# Schema comparison summary after index reflection

作成日: 2026-07-01

## 前提

`idx_office_welfare_recipients_office_welfare` を全DBブランチへ反映した後のschema-only dumpを比較した。

## index反映結果

対象index:

```text
idx_office_welfare_recipients_office_welfare
```

全DBブランチで存在を確認済み。

## 比較結果

### `main` vs `main_test`

オブジェクト名単位では差分なし。

判断:

- `main` と `main_test` は同一schemaとして扱える。

### `main` vs `dev`

差分あり。

`dev` のみに存在:

- `alembic_version`
- `idx_support_plan_cycles_latest_renewal`

`main` のみに存在:

- `search_objects_by_name`

判断:

- 指定index反映後も、`dev` には別のperformance index差分が残る。
- `alembic_version` はmain stamp前の比較ではdev onlyだったが、mainは後続で `baseline_20260701` へstamp済み。

### `main` vs `dev_test`

差分あり。

`dev_test` のみに存在:

- `office_count`
- `staff_count`

判断:

- `dev_test` の差分は検証用テーブルと見てよい。

### `dev` vs `dev_test`

差分あり。

`dev` のみに存在:

- `alembic_version`
- `idx_support_plan_cycles_latest_renewal`

`dev_test` のみに存在:

- `office_count`
- `staff_count`
- `search_objects_by_name`

## mainのAlembic baseline記録

`main` DBは `baseline_20260701` にstamp済み。

確認結果:

```text
baseline_20260701 (head) (mergepoint)
```

## 残作業

- `main_test` を `baseline_20260701` にstampするか判断する。
- `dev` / `dev_test` をbaselineへ揃える前に残差分を整理する。
- `idx_support_plan_cycles_latest_renewal` を正式採用するか決める。
- `office_count` / `staff_count` の削除を検討する。
- `search_objects_by_name` の扱いを決める。
