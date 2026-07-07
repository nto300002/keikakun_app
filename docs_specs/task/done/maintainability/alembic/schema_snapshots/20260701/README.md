# Schema snapshots 2026-07-01

取得日: 2026-07-01

## 目的

Alembic baseline revisionを決める前提として、NeonDBの各DBブランチのschema-only dumpを取得した。

DBデータ本体は含めず、スキーマ定義のみを対象にする。

## 取得対象

| DBブランチ | 環境変数 | 出力ファイル | サイズ | `alembic_version` |
| --- | --- | --- | ---: | --- |
| main | `PROD_DATABASE_URL` | `main_schema_20260701.sql` | 158199 bytes | なし |
| main_test | `PROD_TEST_DATABASE_URL` | `main_test_schema_20260701.sql` | 158199 bytes | なし |
| dev | `DEV_DATABASE_URL` | `dev_schema_20260701.sql` | 160957 bytes | あり |
| dev_test | `DEV_TEST_DATABASE_URL` | `dev_test_schema_20260701.sql` | 160154 bytes | なし |

## 取得方法

ホストの `pg_dump` はPostgreSQL 14系で、NeonDB側がPostgreSQL 17系だったため、version mismatchで使用できなかった。

そのため、`postgres:17-alpine` Docker image の `pg_dump` を利用した。

取得オプション:

```text
pg_dump --schema-only --no-owner --no-privileges
```

## SHA-256

```text
488465733abb2428b9a02b5135829c099b1610b18acb7e425508a149e71b4b13  dev_schema_20260701.sql
9848794bf8c89c9021414ba33bea6d9ee5eedef8d70441d60aed28b053923113  dev_test_schema_20260701.sql
ab23237d158057515828c83dfe6413b80a8d1017d5d37bdbc93f66ba512565ef  main_schema_20260701.sql
11a2f38b8216b0f65fd75a25b3e90a2ec38567dda7359269af58ad255d3ac681  main_test_schema_20260701.sql
```

## 初期確認

- `dev` のみ `alembic_version` テーブル定義が含まれる。
- `main` / `main_test` / `dev_test` には `alembic_version` テーブル定義が含まれない。

この結果は、事前に手動確認していたNeonDB上の状態と一致する。
