# Schema snapshots 2026-07-01 after cleanup

取得日: 2026-07-01

## 目的

`dev` DBから検証用と判断した以下を削除した後、NeonDBの各DBブランチのschema-only dumpを再取得した。

- `dashboard_summary`
- `welfare_recipients_partitioned`
- `welfare_recipients_part_0`

## 取得対象

| DBブランチ | 環境変数 | 出力ファイル | サイズ | `alembic_version` |
| --- | --- | --- | ---: | --- |
| main | `PROD_DATABASE_URL` | `main_schema_20260701_after_cleanup.sql` | 159774 bytes | なし |
| main_test | `PROD_TEST_DATABASE_URL` | `main_test_schema_20260701_after_cleanup.sql` | 159774 bytes | なし |
| dev | `DEV_DATABASE_URL` | `dev_schema_20260701_after_cleanup.sql` | 157515 bytes | あり |
| dev_test | `DEV_TEST_DATABASE_URL` | `dev_test_schema_20260701_after_cleanup.sql` | 160154 bytes | なし |

## 取得方法

`postgres:17-alpine` Docker image の `pg_dump` を利用した。

取得オプション:

```text
pg_dump --schema-only --no-owner --no-privileges
```

## SHA-256

```text
5a8c69f2878b6bd4f2d488d880114ee506aa0017b5a2e4c21dc106c2591dfb14  dev_schema_20260701_after_cleanup.sql
d9e1206f7b652e8eafd1dbb1dd2e4792c3656e0bf6a2143056351c06afa7ff50  dev_test_schema_20260701_after_cleanup.sql
9bfc72ea1d999530de7f471a2f9da64e2a8be2e9872e7189c7af9285dac8f5c0  main_schema_20260701_after_cleanup.sql
aec9d235abe0be45d6bca8ecd5c48cb83cc65d832b9da63f088ea179025698ce  main_test_schema_20260701_after_cleanup.sql
```

## 初期確認

- `dev` にはまだ `alembic_version` が含まれる。
- `dev` から `dashboard_summary` / `welfare_recipients_partitioned` / `welfare_recipients_part_0` は消えている。
- `main` / `main_test` / `dev_test` には `alembic_version` が含まれない。
