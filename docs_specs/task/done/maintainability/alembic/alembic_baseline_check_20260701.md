# Alembic baseline確認ログ

作成日: 2026-07-01

## 現在ステータス

この文書は、Alembic revisionグラフ破損の調査から新baseline作成までを時系列で残した確認ログである。

2026-07-02時点では、`baseline_20260701` を新しいAlembic管理開始地点として作成済みで、backendコンテナ内の `alembic heads` は次の単一headを返す。

```text
baseline_20260701 (head)
```

ただし、全DBブランチへ `baseline_20260701` をstamp済みという意味ではない。本文後半の「移行処理の現在位置」「index反映とmain baseline記録」を正とし、DBブランチごとのstamp状況とschema差分は引き続き確認対象とする。

## 目的

手動SQL中心で運用されてきたDBを、今後Alembic管理へ移行するために、baseline revisionを決める前提条件を確認する。

この確認ではDB変更は行わない。読み取り確認のみを対象にする。

## 確認対象

- `k_back/migrations/versions`
- backendコンテナ内のAlembic
- 現在backendが接続しているNeonDB `dev` ブランチ
- `dev` の `alembic_version`

## 初期確認結果サマリ（baseline作成前）

初期確認時点では、baseline revisionをまだ決めない判断だった。

理由:

- migrationファイル側のrevisionグラフが壊れている。
- `dev` の `alembic_version` は存在するが、現在DBの実スキーマを表していない。
- `main` / `main_test` / `dev_test` には `alembic_version` が存在しない。
- DB実態は `alembic_version` より後続の変更を含んでいる。

したがって、次の順で進めるのが妥当。

1. migrationファイル側のrevisionグラフを修復する。
2. 各DBブランチのschema snapshotを取得する。
3. `dev` の既存 `alembic_version` を正とは見なさず、参考情報として扱う。
4. 全DBブランチを同じ新baseline revisionへ揃える方針を検討する。

## Alembicコマンド確認

### `alembic heads`

backendコンテナ内で実行した結果、失敗。

主なエラー:

```text
Revision a1b2c3d4e5f6 is present more than once
Revision su6cug3oavuk referenced from su6cug3oavuk -> byddyrpnnpk5 (head), add_cycle_number is not present
KeyError: 'su6cug3oavuk'
```

### `alembic branches`

backendコンテナ内で実行した結果、同様に失敗。

原因は `alembic heads` と同じ。

### `alembic current`

DB接続自体は成功しているが、migrationグラフ解決で失敗。

主なエラー:

```text
Context impl PostgresqlImpl.
Will assume transactional DDL.
Revision a1b2c3d4e5f6 is present more than once
KeyError: 'su6cug3oavuk'
```

判断:

- DB接続はできている。
- ただし、Alembicのrevision mapが構築できないため、Alembic経由の `current` は現時点では信頼できない。

## migrationファイル側の破損

### 重複revision

`a1b2c3d4e5f6` が3つのmigrationファイルで使われている。

```text
migrations/versions/a1b2c3d4e5f6_add_dashboard_performance_indexes.py
migrations/versions/a1b2c3d4e5f6_add_inquiry_details_table.py
migrations/versions/a1b2c3d4e5f6_add_is_test_data_flag_to_all_tables.py
```

この状態では、Alembicはrevision IDから一意のmigrationを特定できない。

### 参照切れdown_revision

`byddyrpnnpk5_add_cycle_number.py` は次のように `su6cug3oavuk` を参照している。

```python
revision = "byddyrpnnpk5"
down_revision = "su6cug3oavuk"
```

しかし、`su6cug3oavuk_create_mfa.py` の実際のrevision IDは次の通り。

```python
revision = "001_create_mfa"
down_revision = "7fa9fdd58c84"
```

つまり、ファイル名は `su6cug3oavuk_create_mfa.py` だが、Alembic上のrevision IDは `su6cug3oavuk` ではない。

判断:

- `byddyrpnnpk5` の `down_revision` は存在しないrevisionを参照している。
- 修正候補は `down_revision = "001_create_mfa"` だが、実際にそれで正しいかは前後のmigration内容を確認してから決める。

## head候補

機械的にrevision/down_revisionを読んだ場合、head候補は次の5つ。

```text
001_create_mfa
b0c1d2e3f4g5
n3o4p5q6r7s8
q2r3s4t5u6v7
q8r9s0t1u2v3
```

注意:

- `001_create_mfa` は参照切れの影響でhead候補になっている可能性が高い。
- `n3o4p5q6r7s8` は `dev` の `alembic_version` に存在する。
- `q8r9s0t1u2v3` は課金status追加の後続migrationで、DB実態にはこの内容が反映済み。

## `dev` の `alembic_version`

直接SELECTした結果:

```text
m2n3o4p5q6r7
n3o4p5q6r7s8
```

該当migration:

- `m2n3o4p5q6r7_add_early_payment_billing_status.py`
- `n3o4p5q6r7s8_make_audit_log_staff_id_nullable.py`

判断:

- `n3o4p5q6r7s8` は `m2n3o4p5q6r7` を `down_revision` としている。
- 通常の単一路線であれば、`alembic_version` にはhead側の `n3o4p5q6r7s8` だけが残るはず。
- `m2n3o4p5q6r7` と `n3o4p5q6r7s8` が両方ある状態は、複数head運用または手動挿入/途中stampの可能性がある。
- 現在のDB実態はこの2つより後続の変更を含むため、この `alembic_version` は現在地点として信頼しない。

## DB実スキーマ確認

### billing status enum

`billingstatus` enumには次の値が存在する。

```text
free
early_payment
active
past_due
trial_expired
payment_failed
canceling
canceled
```

判断:

- `m2n3o4p5q6r7` の `early_payment` だけでなく、後続の `canceling`、`trial_expired`、`payment_failed` もDBに存在する。
- `dev` の `alembic_version` よりDB実態の方が進んでいる。

### `ck_billings_billing_status`

CHECK制約は次のstatusを許可している。

```text
free
early_payment
active
past_due
trial_expired
payment_failed
canceling
canceled
```

判断:

- DB側のCHECK制約も最新の課金status構成に近い。
- `q8r9s0t1u2v3` 相当の変更はDBに反映済みと考えられる。

### `audit_logs.staff_id`

確認結果:

```text
column_name: staff_id
is_nullable: YES
data_type: uuid
```

判断:

- `n3o4p5q6r7s8` 相当の変更はDBに反映済み。

### 後続migration相当のテーブル/カラム

存在確認:

```text
webhook_events: true
mfa_audit_logs: true
mfa_backup_codes: true
push_subscriptions: true
calendar_event_series: true
```

staffs MFA関連カラム:

```text
is_mfa_enabled: NOT NULL
is_mfa_verified_by_user: NOT NULL
mfa_backup_codes_used: NOT NULL
mfa_secret: NULL
```

billings関連カラム:

```text
billing_status: NOT NULL, USER-DEFINED
scheduled_cancel_at: NULL, timestamp with time zone
stripe_customer_id: NULL, character varying
stripe_subscription_id: NULL, character varying
```

support_plan_cycles関連カラム:

```text
cycle_number: NULL
office_id: NOT NULL
```

判断:

- DBには `dev` の `alembic_version` より後の変更が多数存在する。
- 手動SQLまたはAlembic外の手段で反映された変更が混在している可能性が高い。

## 暫定判断

### baseline候補

現時点では、既存の `n3o4p5q6r7s8` や `q8r9s0t1u2v3` をそのままbaselineにするのは危険。

理由:

- migrationグラフが壊れている。
- DB実態は複数head相当の変更を含んでいる。
- `dev` の `alembic_version` が現在状態を表していない。
- 他DBブランチには `alembic_version` が存在しない。

推奨:

- 既存履歴の末尾をbaselineにするのではなく、新しい空のbaseline revisionを作る。
- その前に、既存migrationグラフを最低限Alembicが読める状態に修復する。
- baseline revisionは「現在DB状態を管理開始地点として固定する」ためのrevisionにする。

### 次にやるべきこと

1. `a1b2c3d4e5f6` の重複revisionをどう扱うか決める。
2. `byddyrpnnpk5` の `down_revision` 参照切れを修正する。
3. `alembic heads` が成功する状態にする。
4. `main` / `dev` / `main_test` / `dev_test` のschema snapshotを取得する。
5. DBブランチ間の差分を比較する。
6. 新baseline revision名を決める。
7. 各DBブランチへ同じbaselineを記録する手順を作る。

## 注意

この段階では、`alembic stamp`、`upgrade head`、`alembic_version` の直接更新は行わない。

先にmigrationグラフとDBスキーマ差分を整理しないと、誤ったbaselineを記録するリスクが高い。

## 最小修正方針

### `a1b2c3d4e5f6` 重複revisionの扱い

方針は、過去履歴を完全に正しく復元することではなく、今後のbaseline運用を壊さないためにAlembicがrevisionグラフを読める状態へ戻すこと。

判断基準:

1. 既存DBに対して再実行する前提にしない。
   - 既に手動SQLでDBへ反映済みの可能性が高い。
   - この3 migrationを今から本番DBへ順番通りに流すことは目的にしない。

2. revision IDは一意にする。
   - Alembicでは `revision` が主キーに近い。
   - 3ファイルが同じ `a1b2c3d4e5f6` を持つ状態は不可。

3. 後続参照があるrevisionを優先して残す。
   - `r3s4t5u6v7w8_add_password_reset_tokens.py` が `a1b2c3d4e5f6` を参照していた。
   - 問い合わせ機能の `a1b2c3d4e5f6_add_inquiry_details_table.py` は `x1y2z3a4b5c6_add_messages_tables.py` の後続で、内容上もmessage tableに依存する。
   - そのため、問い合わせmigrationを `a1b2c3d4e5f6` として残すのが最小影響と判断する。

4. 他2件は新revision IDへ変更する。
   - `a1b2c3d4e5f6_add_is_test_data_flag_to_all_tables.py`
   - `a1b2c3d4e5f6_add_dashboard_performance_indexes.py`

5. revision修正とDB適用判断は分ける。
   - 今回の修正はAlembicグラフ修復が目的。
   - DBにmigrationを適用する判断は、各DBブランチのschema snapshot比較後に行う。

採用した扱い:

```text
a1b2c3d4e5f6_add_inquiry_details_table.py
  revision = a1b2c3d4e5f6 のまま維持

a1b2c3d4e5f6_add_is_test_data_flag_to_all_tables.py
  revision = a1b2c3d4e5f7 へ変更

a1b2c3d4e5f6_add_dashboard_performance_indexes.py
  revision = a1b2c3d4e5f8 へ変更
```

### 参照切れdown_revisionの扱い

`byddyrpnnpk5_add_cycle_number.py` は `su6cug3oavuk` を参照していたが、実在するrevision IDは `001_create_mfa` だった。

採用した扱い:

```text
byddyrpnnpk5_add_cycle_number.py
  down_revision = su6cug3oavuk
  -> down_revision = 001_create_mfa
```

理由:

- `su6cug3oavuk_create_mfa.py` はファイル名に `su6cug3oavuk` を含むが、Alembic上のrevision IDは `001_create_mfa`。
- `byddyrpnnpk5` はMFA作成の直後に置かれたmigrationとして扱うのが最小修正。

### 循環参照の扱い

重複revisionと参照切れを解消した後、次の循環が顕在化した。

```text
r3s4t5u6v7w8
-> a1b2c3d4e5f6
-> x1y2z3a4b5c6
-> w9x0y1z2a3b4
-> r3s4t5u6v7w8
```

原因:

- `r3s4t5u6v7w8_add_password_reset_tokens.py` が `a1b2c3d4e5f6` を参照していた。
- 一方で `a1b2c3d4e5f6_add_inquiry_details_table.py` は `x1y2z3a4b5c6` の後続。
- `x1y2z3a4b5c6` は `w9x0y1z2a3b4` の後続。
- `w9x0y1z2a3b4` は `r3s4t5u6v7w8` の後続。

採用した扱い:

```text
r3s4t5u6v7w8_add_password_reset_tokens.py
  down_revision = a1b2c3d4e5f6
  -> down_revision = q2r3s4t5u6v7
```

理由:

- `password_reset_tokens` は `messages` / `inquiry_details` に依存していない。
- `r3s4t5u6v7w8` の作成日は `2025-01-20` と記録されており、少なくとも `messages` / `inquiry_details` より後続である必然性は低い。
- `q2r3s4t5u6v7` はrole permission系のmigrationで、`password_reset_tokens` の前段として置いても業務依存が比較的薄い。
- 循環を断つための最小変更として妥当。

## 最小修正後の確認結果

### 機械チェック

重複revision:

```text
なし
```

存在しないdown_revision:

```text
なし
```

head候補:

```text
a1b2c3d4e5f6  inquiry_details
a1b2c3d4e5f7  is_test_data flag
a1b2c3d4e5f8  dashboard performance indexes
b0c1d2e3f4g5  notification preferences threshold fields
n3o4p5q6r7s8  audit_logs.staff_id nullable
q8r9s0t1u2v3  trial_expired/payment_failed billing status
```

### `alembic heads`

成功。

```text
a1b2c3d4e5f8 (head)
a1b2c3d4e5f6 (head)
a1b2c3d4e5f7 (head)
b0c1d2e3f4g5 (head)
n3o4p5q6r7s8 (head)
q8r9s0t1u2v3 (head)
```

### `alembic branches`

成功。

確認できたbranchpoint:

```text
z8a9b0c1d2e3
p7q8r9s0t1u2
x1y2z3a4b5c6
r3s4t5u6v7w8
```

### `alembic current`

成功。

```text
n3o4p5q6r7s8 (head)
```

注意:

- DBの `alembic_version` には `m2n3o4p5q6r7` と `n3o4p5q6r7s8` が存在していた。
- Alembic上は `n3o4p5q6r7s8` を現在headとして解決できるようになった。
- ただし、DB実態は `q8r9s0t1u2v3` 相当など後続変更を含むため、baseline決定にはまだschema snapshot比較が必要。

## 最小修正後の残課題

- 複数headが6つ存在する。
- `dev` の `alembic_version` は現在DB実態を完全には表していない。
- `main` / `main_test` / `dev_test` には `alembic_version` がない。
- `a1b2c3d4e5f7` / `a1b2c3d4e5f8` はファイル名上は `a1b2c3d4e5f6_...` のままなので、必要なら後続でファイル名も整理する。
- 既存DBにどのmigration相当が反映済みかは、DBブランチごとのschema snapshot比較が必要。

## 次の推奨作業

1. `main` / `dev` / `main_test` / `dev_test` のschema snapshotを取得する。
2. 6つのhead相当の変更が各DBブランチに存在するか確認する。
3. 複数headをmerge revisionでまとめるか、新baseline revisionを別に作るか判断する。
4. 既存DBに対しては `upgrade head` を実行せず、baseline記録方針を別途決める。

## schema snapshot取得

2026-07-01に、NeonDBの4つのDBブランチからschema-only dumpを取得した。

保存先:

```text
md_files_design_note/task/todo/refactor/maintainability/schema_snapshots/20260701/
```

取得ファイル:

```text
main_schema_20260701.sql
main_test_schema_20260701.sql
dev_schema_20260701.sql
dev_test_schema_20260701.sql
```

取得方法:

- `pg_dump --schema-only --no-owner --no-privileges`
- ホストの `pg_dump` はPostgreSQL 14系でNeonDB PostgreSQL 17系とversion mismatchしたため、`postgres:17-alpine` Docker image の `pg_dump` を使用した。

初期確認:

- `dev` のみ `alembic_version` が含まれる。
- `main` / `main_test` / `dev_test` には `alembic_version` が含まれない。

詳細:

- `schema_snapshots/20260701/README.md` を参照。

## 新baseline revision方針

本番DBや安全な移行判断を優先し、過去migrationを既存DBへ流して追いつかせる方式は採用しない。

採用方針:

- 現在の実DB状態を管理開始地点として扱う。
- 既存DBには `upgrade head` を実行しない。
- 新しい空のbaseline revisionを作成する。
- schema snapshot比較で各DBブランチの実態を確認する。
- DBブランチ間の差分を許容または解消した後、明示的に承認してから `stamp` 相当でbaselineを記録する。

### 実施順序

1. Alembic revisionグラフを読める状態にする。
   - 重複revisionを解消する。
   - 参照切れdown_revisionを解消する。
   - 循環参照を解消する。

2. Alembic上の複数headを新baseline revisionで束ねる。
   - baseline revisionは空のmigrationにする。
   - 既存DBにDDLを流すためのrevisionにはしない。

3. `alembic heads` が単一headになることを確認する。

4. `main` / `dev` / `main_test` / `dev_test` のschema snapshotを取得する。

5. schema snapshotを比較する。
   - 同一schemaか確認する。
   - 差分がある場合、正式採用する差分と除外する差分を分ける。

6. baseline記録方針を決める。
   - どのDBブランチにいつ `baseline_20260701` を記録するか決める。
   - 既存 `alembic_version` があるDBブランチは整理方法を決める。

7. 承認後にのみ `stamp` 相当のDB更新を行う。
   - schemaを変更しない。
   - `alembic_version` のみをbaselineへ揃える。

8. baseline後の最初のmigrationは小さく非破壊的な変更で検証する。

## baseline revision作成

新baseline revisionを追加した。

ファイル:

```text
k_back/migrations/versions/baseline_20260701_current_schema.py
```

revision:

```text
baseline_20260701
```

down_revision:

```text
a1b2c3d4e5f6
a1b2c3d4e5f7
a1b2c3d4e5f8
b0c1d2e3f4g5
n3o4p5q6r7s8
q8r9s0t1u2v3
```

内容:

- `upgrade()` は no-op。
- `downgrade()` も no-op。
- 既存DBに対して過去migrationを実行するためのrevisionではない。
- schema検証後に `stamp` するための管理開始地点として扱う。

確認結果:

```text
alembic heads
-> baseline_20260701 (head)
```

```text
alembic current
-> n3o4p5q6r7s8
```

判断:

- Alembic上のheadは `baseline_20260701` の1つにまとまった。
- 現在接続中DBの `alembic_version` はまだ `baseline_20260701` ではない。
- この時点ではDBへ `stamp` は実行していない。

## schema snapshot比較

比較結果は以下に記録した。

```text
schema_snapshots/20260701/schema_comparison_summary.md
```

要点:

- `main` と `main_test` は実質同一。
- `dev` と `dev_test` は差分あり。
- `main` と `dev` も差分あり。
- `main_test` と `dev_test` も差分あり。

主な差分:

- `dev` のみ:
  - `alembic_version`
  - `welfare_recipients_partitioned`
  - `welfare_recipients_part_0`
  - `dashboard_summary`
  - dashboard/performance系index
- `dev_test` のみ:
  - `office_count`
  - `staff_count`
  - 一部performance系index
- `main` のみ:
  - `search_objects_by_name`

判断:

- 4ブランチのschemaはまだ同一ではない。
- この状態で全DBブランチへ同じbaselineを記録するのは保留する。
- 先に差分を正式採用するか、整理するか判断する必要がある。

## 移行処理の現在位置

完了:

- [x] Alembic revisionグラフの破損を最小修正した。
- [x] `alembic heads` / `branches` / `current` が実行できる状態にした。
- [x] 新baseline revision `baseline_20260701` を作成した。
- [x] `alembic heads` が単一headになることを確認した。
- [x] 4つのNeonDBブランチからschema snapshotを取得した。
- [x] schema snapshotの初期比較を行った。

未実施:

- [ ] DBへ `baseline_20260701` をstampする。
- [ ] `dev` の既存 `alembic_version` を整理する。
- [ ] `main` / `main_test` / `dev_test` に `alembic_version` を作成する。

未実施の理由:

- DBブランチ間にschema差分がある。
- どの差分を正式schemaとして採用するか未決定。
- 誤ったbaseline記録は後続migrationの適用判断を誤らせる。

## dev検証用オブジェクト削除と再dump

2026-07-01に、`dev` DBから検証用と判断した以下を削除した。

削除対象:

```text
dashboard_summary
welfare_recipients_partitioned
welfare_recipients_part_0
```

理由:

- `welfare_recipients_partitioned` / `welfare_recipients_part_0` は0件で、アプリコード参照や正式migrationが見つからなかった。
- `dashboard_summary` はmaterialized viewとして存在していたが、baseline対象として正式採用する判断材料が不足していた。
- 本番安全性を優先し、baseline前の環境差分から除外した。

削除後、4つのNeonDBブランチからschema-only dumpを再取得した。

保存先:

```text
md_files_design_note/task/todo/refactor/maintainability/schema_snapshots/20260701_after_cleanup/
```

取得ファイル:

```text
main_schema_20260701_after_cleanup.sql
main_test_schema_20260701_after_cleanup.sql
dev_schema_20260701_after_cleanup.sql
dev_test_schema_20260701_after_cleanup.sql
```

確認結果:

- `dev` から `dashboard_summary` / `welfare_recipients_partitioned` / `welfare_recipients_part_0` は消えた。
- `dev` にはまだ `alembic_version` が存在する。
- `main` と `main_test` はオブジェクト名単位で差分なし。
- `dev_test` にはまだ `office_count` / `staff_count` が存在する。
- `dev` にはまだ2つのperformance index差分が存在する。

残る主な差分:

```text
dev only:
  alembic_version
  idx_office_welfare_recipients_office_welfare
  idx_support_plan_cycles_latest_renewal

dev_test only:
  office_count
  staff_count

main only:
  search_objects_by_name
```

詳細:

- `schema_snapshots/20260701_after_cleanup/README.md`
- `schema_snapshots/20260701_after_cleanup/schema_comparison_summary.md`

## index反映とmain baseline記録

2026-07-01に、`dev` に存在していた以下のindexを他DBブランチにも反映した。

対象index:

```text
idx_office_welfare_recipients_office_welfare
```

定義:

```sql
CREATE INDEX IF NOT EXISTS idx_office_welfare_recipients_office_welfare
ON public.office_welfare_recipients USING btree (office_id, welfare_recipient_id);
```

反映対象:

- `main`
- `main_test`
- `dev`
- `dev_test`

結果:

- `main` / `main_test` / `dev_test` では新規作成。
- `dev` では既存のためskip。
- 全DBブランチで存在を確認済み。

その後、`main` DBを新しいAlembic管理開始地点として扱うため、`baseline_20260701` を記録した。

実行:

```text
DATABASE_URL="$PROD_DATABASE_URL" alembic stamp baseline_20260701
```

確認:

```text
DATABASE_URL="$PROD_DATABASE_URL" alembic current
-> baseline_20260701 (head) (mergepoint)
```

注意:

- この操作はschema objectを変更しない。
- `main` DBには `alembic_version` テーブルが作成され、`baseline_20260701` が現在revisionとして記録された。
- `main_test` / `dev` / `dev_test` にはまだ `baseline_20260701` をstampしていない。

index反映後のschema snapshot:

```text
md_files_design_note/task/todo/refactor/maintainability/schema_snapshots/20260701_after_index/
```

追加取得:

```text
main_schema_20260701_after_index_and_stamp.sql
```

詳細:

- `schema_snapshots/20260701_after_index/README.md`
- `schema_snapshots/20260701_after_index/schema_comparison_summary.md`

残差分:

- `dev` には `idx_support_plan_cycles_latest_renewal` が残る。
- `dev_test` には `office_count` / `staff_count` が残る。
- `search_objects_by_name` は `main` 側に存在するが、DBブランチによって有無が異なる。
