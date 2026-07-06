# Schema snapshots 2026-07-01 after index reflection

取得日: 2026-07-01

## 目的

`idx_office_welfare_recipients_office_welfare` を4つのNeonDBブランチへ反映した後、schema-only dumpを再取得した。

その後、`main` DBへ `baseline_20260701` をAlembic currentとして記録し、mainのみstamp後dumpも取得した。

## 実施内容

### 1. index反映

対象index:

```sql
CREATE INDEX IF NOT EXISTS idx_office_welfare_recipients_office_welfare
ON public.office_welfare_recipients USING btree (office_id, welfare_recipient_id);
```

反映対象:

- `main`
- `main_test`
- `dev`
- `dev_test`

`dev` では既に存在していたため、作成はskipされた。

### 2. schema-only dump

取得ファイル:

```text
main_schema_20260701_after_index.sql
main_test_schema_20260701_after_index.sql
dev_schema_20260701_after_index.sql
dev_test_schema_20260701_after_index.sql
```

取得方法:

```text
pg_dump --schema-only --no-owner --no-privileges
```

`postgres:17-alpine` Docker image の `pg_dump` を使用した。

### 3. main DBへのAlembic baseline記録

`main` DBに対して次を実行した。

```text
alembic stamp baseline_20260701
```

確認結果:

```text
alembic current
-> baseline_20260701 (head) (mergepoint)
```

stamp後のmain dump:

```text
main_schema_20260701_after_index_and_stamp.sql
```

注意:

- `pg_dump --schema-only` には `alembic_version` の行データは含まれない。
- `baseline_20260701` の値は `alembic current` で確認した。

## SHA-256

```text
3cb67bc4c979c9f558d19d8fbf1cb2fc18ae16efa563b1de2bab81fa2c9139a2  main_schema_20260701_after_index_and_stamp.sql
```

## 現時点の残差分

オブジェクト名単位の比較では、主な差分は次の通り。

```text
main vs main_test:
  no object-name differences

main vs dev:
  only dev:
    alembic_version
    idx_support_plan_cycles_latest_renewal
  only main:
    search_objects_by_name

main vs dev_test:
  only dev_test:
    office_count
    staff_count

dev vs dev_test:
  only dev:
    alembic_version
    idx_support_plan_cycles_latest_renewal
  only dev_test:
    office_count
    staff_count
    search_objects_by_name
```

補足:

- `main` はstamp済みのため、再dumpでは `alembic_version` テーブル定義が含まれる。
- 上記比較はstamp前の `main_schema_20260701_after_index.sql` を基準にした差分。
- stamp後のmainを基準にする場合、`alembic_version` はmainにも存在する。

## 次の判断

- `main_test` にも `baseline_20260701` をstampするか。
- `dev_test` の `office_count` / `staff_count` を削除するか。
- `dev` の `idx_support_plan_cycles_latest_renewal` を正式採用して他DBへ反映するか、devから削除するか。
- `search_objects_by_name` を正式採用するか、確認用関数として削除するか。
