# main DB Alembic CD 方針

作成日: 2026-07-01

## 前提

- 対象DBは NeonDB の `main` ブランチ。
- backend のCDは `.github/workflows/cd-backend.yml` で `main` push 時に実行される。
- 実際のデプロイは GitHub Actions から `gcloud builds submit` を呼び、`k_back/cloudbuild.yml` の手順で Cloud Run へ反映する。
- Alembic は `k_back/migrations/env.py` で `DATABASE_URL` を参照する。
- アプリ本体も `k_back/app/core/config.py` で `DATABASE_URL` を参照する。
- 既存DBに対して通常CDで `alembic stamp` は実行しない。`stamp` は baseline 確定時の一度きりの管理操作として扱う。

## 方向性

`main` への反映は GitHub Actions / Cloud Build 経由に寄せる。

通常運用では、Cloud Build 内で本番用イメージをビルドした後、Cloud Run deploy の前に同じイメージでbaseline確認を行い、その後 `alembic upgrade head` を実行する。

理由:

- `upgrade head` が成功してから新しい Cloud Run revision を出すため、アプリだけ先に新しくなる事故を減らせる。
- Alembic 実行環境とCloud Run実行環境で、Python依存関係とソースコードの差分が出にくい。
- `k_back/migrations/env.py` が `DATABASE_URL` のみを見るため、既存の本番DB URL受け渡しをそのまま利用できる。
- `baseline_20260701` 未反映のDBではCDを止め、過去の分岐migrationを誤って実行しない。

注意:

- `alembic upgrade head` は前方互換のあるmigrationだけを通常CDに載せる。
- 通常CDでは、`scripts/alembic_baseline_guard.py` で接続先DBのcurrent revisionが `baseline_20260701` 以降であることを確認してから `upgrade head` を実行する。
- カラム削除、enum値削除、テーブル削除、NOT NULL化、制約強化など既存revisionに影響する変更は、原則として2段階migrationに分ける。
- 既存DBのbaseline合わせは `stamp baseline_20260701` のような管理操作であり、通常CDのたびに実行しない。
- `main_test` / `dev` / `dev_test` を同じbaselineへ揃える場合も、各DBのschema差分を確認してから個別にstampする。

## 現在の環境変数の流れ

### `.github/workflows/cd-backend.yml`

GitHub Actions 側では、`Deploy to Cloud Run using Cloud Build` step で `gcloud builds submit` を実行している。

現在、本番DB URLは次の形で Cloud Build substitution に渡されている。

```yaml
_PROD_DATABASE_URL="${{ secrets.PROD_DATABASE_URL }}"
```

この値は `k_back/cloudbuild.yml` 内で Cloud Run の `DATABASE_URL` として設定されている。

```yaml
DATABASE_URL=${_PROD_DATABASE_URL}
```

### `k_back/cloudbuild.yml`

現在は Cloud Run deploy step の `--update-env-vars` に以下の形で渡している。

```yaml
DATABASE_URL=${_PROD_DATABASE_URL}
```

AlembicをCDで実行する場合も、この `_PROD_DATABASE_URL` を使い、migration実行stepの環境変数として `DATABASE_URL` を渡す。

baseline確認step:

```yaml
- name: 'asia-northeast1-docker.pkg.dev/$PROJECT_ID/k-back-repo/k-back:$SHORT_SHA'
  entrypoint: python
  env:
    - 'DATABASE_URL=${_PROD_DATABASE_URL}'
    - 'ALEMBIC_BASELINE_REVISION=baseline_20260701'
  args:
    - 'scripts/alembic_baseline_guard.py'
```

migration実行step:

```yaml
- name: 'asia-northeast1-docker.pkg.dev/$PROJECT_ID/k-back-repo/k-back:$SHORT_SHA'
  entrypoint: alembic
  env:
    - 'DATABASE_URL=${_PROD_DATABASE_URL}'
  args:
    - 'upgrade'
    - 'head'
```

配置位置:

1. Docker image build
2. Docker image push
3. `scripts/alembic_baseline_guard.py`
4. `alembic upgrade head`
5. Cloud Run deploy

`push` の後に置く理由は、baseline確認とmigration実行に使ったイメージとデプロイ対象イメージがArtifact Registry上で追跡できるため。

### `k_back/migrations/env.py`

Alembicは以下の順で接続先を決めている。

```python
dotenv.load_dotenv()
db_url = os.getenv('DATABASE_URL', "")
```

`postgresql+asyncpg://` の場合はAlembic用に `postgresql://` へ置換する実装がある。

そのため、CDでは `DATABASE_URL` を明示的に渡すだけでよい。

## GitHub Actionsで追加・確認すべき変数

### 必須確認

- `PROD_DATABASE_URL`
  - NeonDB `main` ブランチを指していること。
  - Alembicが接続できる形式であること。
  - `main_test` / `dev` / `dev_test` を指していないこと。
- `GCP_SA_KEY`
  - Cloud Build 実行権限を持つこと。
  - Artifact Registry push 権限を持つこと。
  - Cloud Run deploy 権限を持つこと。
- `GCP_PROJECT_ID`
  - `k-back` をデプロイするGCP projectと一致していること。

### 既存のまま使う変数

Cloud Run runtime用として、現行の `cd-backend.yml` から `cloudbuild.yml` へ渡している以下は継続利用する。

- `PROD_SECRET_KEY`
- `AWS_ACCESS_KEY_ID`
- `AWS_SECRET_ACCESS_KEY`
- `AWS_REGION`
- `S3_ACCESS_KEY`
- `S3_SECRET_KEY`
- `S3_REGION`
- `S3_BUCKET_NAME`
- `SENDER_EMAIL`
- `MAIL_USERNAME`
- `MAIL_PASSWORD`
- `MAIL_SERVER`
- `MAIL_PORT`
- `FRONTEND_URL`
- `CALENDAR_ENCRYPTION_KEY`
- `ENVIRONMENT`
- `COOKIE_SECURE`
- `COOKIE_DOMAIN`
- `COOKIE_SAMESITE`
- `PASSWORD_RESET_TOKEN_EXPIRE_MINUTES`
- `RATE_LIMIT_FORGOT_PASSWORD`
- `RATE_LIMIT_RESEND_EMAIL`
- `STRIPE_SECRET_KEY`
- `STRIPE_PUBLISHABLE_KEY`
- `STRIPE_WEBHOOK_SECRET`
- `STRIPE_PRICE_ID`
- `VAPID_PRIVATE_KEY`
- `VAPID_PUBLIC_KEY`
- `VAPID_SUBJECT`

### 今回は追加しない変数

以下の変数は、運用分岐を増やすため今回は追加しない。

- `RUN_ALEMBIC_MIGRATIONS`
- `ALEMBIC_TARGET_REVISION`

通常CDでは `alembic upgrade head` を固定で実行する。

## セキュリティ上の注意

現状は `gcloud builds submit --substitutions` にsecret値を直接渡している。

既存運用との互換性を優先するなら短期的にはこのまま進められるが、長期的には以下を検討する。

- Cloud Build から Secret Manager を参照する。
- GitHub Actions のコマンドラインにDB URLやsecret値を展開しない。
- Cloud Run runtime secretも `--update-secrets` へ寄せる。

短期方針:

- Alembic CD対応では新しいsecretを増やさず、既存の `PROD_DATABASE_URL` を使う。
- ログにはDB URLを出さない。
- `alembic current` や `alembic heads` の結果だけを出力する。
- baseline確認ログにはrevision値だけを出し、DB URLは出さない。

## baseline反映手順

既存DBをAlembic管理へ移す場合は、対象DBのschema差分を確認し、baseline対象として問題ないことを確認してから一度だけ以下を実行する。

```bash
DATABASE_URL="$PROD_DATABASE_URL" alembic stamp baseline_20260701
DATABASE_URL="$PROD_DATABASE_URL" alembic current
```

期待値:

```text
baseline_20260701 (head) (mergepoint)
```

この確認が取れたDBだけを、通常CDの `scripts/alembic_baseline_guard.py` と `alembic upgrade head` の対象にする。

## 実装時の確認項目

- [x] `k_back/cloudbuild.yml` に `alembic upgrade head` stepを追加する。
- [x] `k_back/cloudbuild.yml` に baseline確認stepを追加する。
- [x] Alembic stepは Cloud Run deploy より前に置く。
- [x] Alembic stepには `DATABASE_URL=${_PROD_DATABASE_URL}` を渡す。
- [x] `RUN_ALEMBIC_MIGRATIONS` / `ALEMBIC_TARGET_REVISION` は追加しない。
- [ ] `main` DBの `alembic_version` が `baseline_20260701` 以降に揃っていることを本番接続で確認する。
- [ ] CD実行ログにDB URLやsecret値が出ていないことを確認する。
- [ ] 破壊的migrationを通常CDに混ぜない運用ルールをPR本文に明記する。

## 現時点の推奨

今回のbaseline整理では、まず `main` DBを `baseline_20260701` に合わせる。

その後の通常変更から、`main` push時にCloud Build内で `alembic upgrade head` を実行する。

`main_test` / `dev` / `dev_test` は、schema差分を解消または許容した上で、同じbaselineへ個別に揃える。これらを未確認のまま `upgrade head` 対象に含めない。
