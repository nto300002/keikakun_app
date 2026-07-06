  High

  - k_back/cloudbuild.yml:25 で alembic upgrade head がCloud Run deploy前に実行
    される実装は入っています。ただし、対象DBが baseline_20260701 にstamp済みであ
    ることをCD内で検査していません。
    現在Docker内で確認した alembic current は n3o4p5q6r7s8 で、baseline_20260701
    ではありませんでした。未stampのDBに upgrade head が走ると、古い分岐migration
    を実行しようとして事故る可能性があります。

  - md_files_design_note/task/todo/refactor/maintainability/alembic/
    cd_main.md:175 でも main DBの alembic_version が baseline_20260701 以降に
    揃っていることを確認 が未完了です。ここが完了するまでは、CDの upgrade head
    は本番向けに有効化済みとして扱うにはまだ危険です。

  Medium

  - alembic heads は baseline_20260701 (head) の単一headになっています。これは良
    い状態です。
    一方で alembic branches では過去のbranchpointが複数残っています。baseline
    mergeでheadは一本化されていますが、今後のmigrationは必ず down_revision =
    "baseline_20260701" 以降から作る、という運用ルールを強めた方がよいです。

  - md_files_design_note/task/todo/refactor/maintainability/alembic/
    schema_snapshots/20260701_after_cleanup/schema_comparison_summary.md:86 上、
    main / main_test は同一schemaと見なせますが、dev / dev_test にはまだ差分があ
    ります。
    特に dev の alembic_version、2つのperformance index、dev_test の
    office_count / staff_count、search_objects_by_name の扱いが未判断です。全環
    境をAlembic管理へ移すなら、ここは未完了です。

  - .github/workflows/cd-backend.yml:88 で多数のsecretを gcloud builds submit
    --substitutions=... に直接渡しています。GitHub側ではmaskされるはずですが、
    Cloud Build側ログ・ビルドメタデータで値が露出しないことは未確認です。
    md_files_design_note/task/todo/refactor/maintainability/alembic/
    cd_main.md:176 の「CD実行ログにDB URLやsecret値が出ていないことを確認」が未
    完了なので、ここは確認必須です。

  Low

  - baseline_20260701 のno-op baseline方針自体は妥当です。既存DBへ過去migration
    を流さず、実スキーマ確認後にstampする設計になっています。

  - migrationファイル名と内部revisionがずれている既存ファイルがあります。Alembic
    実行上は内部revisionが正ですが、人間が読む時に混乱しやすいので、後続で整理対
    象にしてよいです。

  不足点まとめ

  現時点では「Alembicの単一head化」は完了していますが、「全環境を安全にAlembic運
  用へ移行済み」とはまだ言えません。最低限、次が残っています。

  1. main の alembic current == baseline_20260701 を本番接続で再確認する。
  2. CD実行前に alembic current を確認するpreflight、または運用チェックを追加す
     る。

  3. main_test / dev / dev_test のstamp方針を確定する。
  4. dev/dev_test差分を採用・削除・許容に分類する。
  5. secretがCDログに出ないことを実ログで確認する。

## 2026-07-02 High対応後レビュー

### 対応内容

- `k_back/cloudbuild.yml` に `alembic upgrade head` の前段として baseline 確認stepを追加した。
- baseline 確認処理として `k_back/scripts/alembic_baseline_guard.py` を追加した。
- `baseline_20260701` 未反映のDBでは、Cloud Run deploy前にCDを停止する構成にした。
- 通常CDで `alembic stamp baseline_20260701` は実行しない方針を維持した。
  - `stamp` はschema確認後に一度だけ行う管理操作。
  - 通常CDに入れると、未検証DBまでbaseline反映済みとして扱ってしまうため。
- `md_files_design_note/task/todo/refactor/maintainability/alembic/cd_main.md` に baseline 確認stepと反映手順を追記した。

### 確認結果

```text
docker exec keikakun_app-backend-1 pytest tests/scripts/test_alembic_baseline_guard.py -q
-> 6 passed

docker exec keikakun_app-backend-1 alembic heads
-> baseline_20260701 (head)

docker exec keikakun_app-backend-1 python scripts/alembic_baseline_guard.py
-> baseline未反映として停止
```

現在のDocker接続先DBでは、`alembic current` 相当のrevisionが `m2n3o4p5q6r7, n3o4p5q6r7s8` であり、`baseline_20260701` ではない。

そのため、追加したguardは以下のメッセージで期待通り停止した。

```text
Alembic baseline check failed. Current revision(s) [m2n3o4p5q6r7, n3o4p5q6r7s8] are not at or after baseline_20260701.
```

### 不足点の解消状況

| No | 初回レビューの不足点 | 状態 | コメント |
| --- | --- | --- | --- |
| 1 | `main` の `alembic current == baseline_20260701` を本番接続で再確認する | 未解消 | 本番DBへ接続しての再確認はまだ未実施。実DBのschema確認後、`alembic stamp baseline_20260701` と `alembic current` 確認が必要。 |
| 2 | CD実行前に `alembic current` を確認するpreflight、または運用チェックを追加する | 解消 | `scripts/alembic_baseline_guard.py` をCloud Buildの `alembic upgrade head` 前に追加済み。未baseline DBではdeploy前に停止する。 |
| 3 | `main_test` / `dev` / `dev_test` のstamp方針を確定する | 未解消 | 今回はHigh対応に限定。各DBブランチのschema差分確認とstamp判断は別途必要。 |
| 4 | `dev` / `dev_test` 差分を採用・削除・許容に分類する | 未解消 | performance index、検証用テーブル、確認用関数の扱いは未確定。 |
| 5 | secretがCDログに出ないことを実ログで確認する | 未解消 | Cloud Build / GitHub Actionsの実ログ確認が必要。今回のguard自体はDB URLを出力しない。 |

### High指摘の現在評価

High指摘のうち、最も危険だった「未stampのDBに `alembic upgrade head` が走り、過去の分岐migrationを誤実行する」リスクは実装上ほぼ解消された。

ただし、`baseline_20260701` を本番DBへ実際に反映する作業はまだ別途必要である。現状のCDは、未反映DBに対して自動で修正するのではなく、安全に停止する状態になっている。

### 残る判断事項

- 本番 `main` DBのschemaがbaseline対象として妥当であることを再確認する。
- 確認後、本番 `main` DBに対して一度だけ `alembic stamp baseline_20260701` を実行する。
- `alembic current` が `baseline_20260701 (head) (mergepoint)` になることを確認する。
- その後、Cloud Buildで baseline guard と `alembic upgrade head` が通ることを実ログで確認する。
- `main_test` / `dev` / `dev_test` を同じbaselineへ揃えるか、環境ごとに移行タイミングを分けるか決める。

## 2026-07-02 CD確認

### 確認対象

- `.github/workflows/cd-backend.yml`
- `k_back/cloudbuild.yml`
- `k_back/Dockerfile`
- `k_back/requirements.txt`
- `k_back/scripts/alembic_baseline_guard.py`

### CD上の実行順

`main` push後のbackend CDは以下の順で実行される。

1. GitHub Actionsでtestを実行する。
2. GitHub Actionsから `gcloud builds submit --config cloudbuild.yml` を実行する。
3. Cloud Buildでproduction imageをbuildする。
4. Artifact Registryへimageをpushする。
5. push済みimageで `python scripts/alembic_baseline_guard.py` を実行する。
6. guardが通った場合だけ、同じimageで `alembic upgrade head` を実行する。
7. migration成功後にCloud Run deployを実行する。

### baseline反映の見通し

CDは `baseline_20260701` を自動でstampしない。

これは意図した挙動である。既存DBへの `stamp baseline_20260701` は、schema確認後に一度だけ行う管理操作であり、通常CDに入れるべきではない。

そのため、baseline反映の見通しは次の2段階で判断する。

1. 事前作業として、本番 `main` DBに `baseline_20260701` をstampする。
2. その後のCDで、baseline guardが `baseline_20260701` 以降であることを確認し、`alembic upgrade head` へ進む。

この前提が満たされれば、CDはbaselineを正しく参照してmigrationを適用できる見通し。

### 現在の確認結果

- `k_back/cloudbuild.yml` では、`alembic upgrade head` の前に baseline guard step が配置されている。
- baseline guard step と migration step は、どちらも同じ `asia-northeast1-docker.pkg.dev/$PROJECT_ID/k-back-repo/k-back:$SHORT_SHA` imageを使う。
- `DATABASE_URL=${_PROD_DATABASE_URL}` が guard step と migration step の両方に渡されている。
- `ALEMBIC_BASELINE_REVISION=baseline_20260701` が guard step に渡されている。
- `k_back/Dockerfile` のproduction imageは `WORKDIR /app` で、`COPY . .` により `scripts/alembic_baseline_guard.py` と `alembic.ini` を参照できる構成。
- `k_back/requirements.txt` には `alembic==1.16.4`、`sqlalchemy==2.0.41`、`psycopg` が含まれているため、production image内でguardとAlembic実行に必要な依存関係は入る。
- `docker exec keikakun_app-backend-1 alembic heads` は `baseline_20260701 (head)` を返しており、migration graph上の参照先は単一head。
- 現在のDocker接続先DBではbaseline未反映としてguardが停止したため、未反映DBに対して `upgrade head` を進めない挙動は確認済み。

### 残る確認

- 本番 `PROD_DATABASE_URL` がNeonDBの `main` ブランチを指していること。
- 本番 `main` DBで一度だけ `alembic stamp baseline_20260701` を実行済みであること。
- 本番 `main` DBで `alembic current` が `baseline_20260701 (head) (mergepoint)` を返すこと。
- Cloud Build実ログで、baseline guardが通過し、その後 `alembic upgrade head` が成功すること。
- Cloud Build / GitHub Actionsログに `PROD_DATABASE_URL` やsecret値が露出していないこと。

### 判断

CD実装の構成上、baselineが事前に本番DBへ反映されていれば、`baseline_20260701` を正しく参照してからmigrationへ進む見通しはある。

一方で、CD単体ではbaselineをDBへ反映しないため、本番 `main` DBへの一度きりのstamp確認が完了するまでは「反映済み」とは判断しない。
