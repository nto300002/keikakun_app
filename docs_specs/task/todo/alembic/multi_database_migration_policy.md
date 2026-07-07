# Alembic 複数DB反映方針

## 目的

ローカル migration 実行時は `DEV_DATABASE_URL` と `DEV_TEST_DATABASE_URL` に同じ変更を反映する。

CI/CD の Cloud Build migration 実行時は `PROD_DATABASE_URL` と `PROD_TEST_DATABASE_URL` に同じ変更を反映する。

ただし Alembic 本体は単一 `DATABASE_URL` を前提にしたまま維持し、複数DB反映は実行ラッパーで制御する。

## 現状

- `k_back/migrations/env.py` は `DATABASE_URL` のみを読む。
- `alembic upgrade head` は `DATABASE_URL` にだけ反映される。
- `docker-compose.yml` はローカル向けに以下へ固定する方針。
  - `DATABASE_URL=${DEV_DATABASE_URL}`
  - `TEST_DATABASE_URL=${DEV_TEST_DATABASE_URL}`
- `k_back/cloudbuild.yml` は現在 `DATABASE_URL=${_PROD_DATABASE_URL}` だけで baseline guard と migration を実行している。
- `PROD_TEST_DATABASE_URL` は Cloud Build substitutions に渡されていない。
- 初回確認時点で `DEV_TEST_DATABASE_URL` と `PROD_TEST_DATABASE_URL` には `alembic_version` テーブルがなかった。
- 2026-07-07 に DEV / DEV_TEST は schema 確認後、`mrg20260703p9q0` に stamp し、#171 migration `c171deadlinecal` まで適用済み。
- PROD / PROD_TEST は本番反映前に同じ観点で read-only 確認し、必要な場合のみ stamp を管理作業として実施する。

## 採用方針

### 1. Alembic 本体は単一DB実行のままにする

`migrations/env.py` に複数DBループを入れない。

理由:

- `alembic current`、`history`、`revision --autogenerate` まで副作用を受ける。
- DBごとの失敗箇所が追いにくくなる。
- Alembic 標準の実行単位は単一 `DATABASE_URL` であり、既存運用と相性がよい。

### 2. 複数DB反映は専用 wrapper で行う

追加候補:

```text
k_back/scripts/run_alembic_for_pair.py
```

想定コマンド:

```bash
python scripts/run_alembic_for_pair.py --env local upgrade head
python scripts/run_alembic_for_pair.py --env prod upgrade head
```

対象:

| mode | 1つ目 | 2つ目 |
| --- | --- | --- |
| `local` | `DEV_DATABASE_URL` | `DEV_TEST_DATABASE_URL` |
| `prod` | `PROD_DATABASE_URL` | `PROD_TEST_DATABASE_URL` |

実行ルール:

- URL はログに出さない。
- `DATABASE_URL` に対象URLを一時セットして `alembic` を subprocess 実行する。
- 順序は main DB から test DB。
- どちらかが失敗したらそこで終了し、失敗した対象名をログに出す。
- 別DB間で単一 transaction は張れないため、完全な atomic 同時反映は目指さない。
- 再実行可能性を重視する。

### 3. ローカル migration は wrapper に統一する

今後のローカル実行:

```bash
docker compose exec backend python scripts/run_alembic_for_pair.py --env local upgrade head
```

直接実行の扱い:

```bash
docker compose exec backend alembic upgrade head
```

これは `DATABASE_URL`、つまり `DEV_DATABASE_URL` のみに反映されるため、通常手順としては使わない。

### 4. CI/CD は Cloud Build で PROD/PROD_TEST の両方に反映する

`.github/workflows/cd-backend.yml` で Cloud Build substitutions に追加する。

```text
_PROD_TEST_DATABASE_URL="${{ secrets.PROD_TEST_DATABASE_URL }}"
```

`k_back/cloudbuild.yml` は以下へ変更する。

- baseline guard を `PROD_DATABASE_URL` と `PROD_TEST_DATABASE_URL` の両方に対して実行する。
- migration は wrapper で `--env prod upgrade head` を実行する。
- Cloud Run の runtime `DATABASE_URL=${_PROD_DATABASE_URL}` は変更しない。

## alembic_version 反映方針

### 原則

`alembic_version` の作成・stamp は通常 migration ではなく、管理操作として扱う。

`alembic stamp` は deploy pipeline に混ぜない。

理由:

- stamp は schema を変更せず、Alembic の管理位置だけを変更する。
- schema 実態と revision がずれると、以降の migration が壊れる。
- `AGENTS.md` でも `alembic stamp` は managed operation とされている。

### TEST DB の現状対応

初回確認時点では、`DEV_TEST_DATABASE_URL` と `PROD_TEST_DATABASE_URL` は `calendar_events` などの実 table はあるが、`alembic_version` がなかった。

そのため、wrapper 導入前に以下を実施する。

1. TEST DB の schema が baseline 以降相当であることを read-only で確認する。
2. 必要な差分があれば、通常 migration ではなく個別 remediation として整理する。
3. 承認後、各 TEST DB に対して `alembic stamp mrg20260703p9q0` 相当を実行する。
4. stamp 後に `alembic current` が `mrg20260703p9q0` を返すことを確認する。
5. その後、通常 migration wrapper の対象に含める。

2026-07-07 に DEV_TEST はこの手順を実施済み。

補足:

- `employee_action_requests` と `role_change_requests` は `approval_requests` に統合済み。
- `office_audit_logs` は `audit_logs` に統合済み。
- 旧 model / CRUD は互換性コメント付きで残っているため、`Base.metadata` を使った schema 比較ではこの3テーブルを除外して判定する。

### PROD DB の現状対応

`PROD_DATABASE_URL` は `alembic_version=mrg20260703p9q0` を持つため、今回の追加 migration の親 revision と整合している。

ただし `PROD_TEST_DATABASE_URL` は `alembic_version` がないため、Cloud Build に PROD_TEST migration を追加する前に stamp が必要。

## 実装タスク

1. `scripts/run_alembic_for_pair.py` を追加する。
2. wrapper の unit test を追加する。
   - URL値をログしない。
   - `local` で DEV/DEV_TEST を順に使う。
   - `prod` で PROD/PROD_TEST を順に使う。
   - 1つ目失敗時は2つ目へ進まない。
   - 2つ目失敗時は非0終了する。
3. `docker-compose.yml` で local の `DATABASE_URL` / `TEST_DATABASE_URL` を明示する。
4. `.github/workflows/cd-backend.yml` に `_PROD_TEST_DATABASE_URL` substitution を追加する。
5. `k_back/cloudbuild.yml` の migration step を wrapper 実行へ変更する。
6. `PROD_TEST_DATABASE_URL` / `DEV_TEST_DATABASE_URL` の baseline stamp 手順書を作る。
7. stamp 実施後、`alembic current` と対象 migration の適用確認を記録する。

## 運用ルール

- 通常 migration は wrapper 経由で2 DBへ反映する。
- `alembic stamp` は明示承認された管理作業としてのみ実行する。
- 本番 deploy 時、PROD への migration 成功後に PROD_TEST が失敗した場合は deploy を止める。
- 失敗時は、どのDBまで反映されたかをログで確認し、同じ wrapper を再実行して復旧する。
- rollback migration は自動実行しない。必要時は影響DBを明示して手動判断する。

## 未決事項

- `PROD_TEST_DATABASE_URL` を Cloud Build secret/substitution として追加済みか確認する。
- `PROD_TEST_DATABASE_URL` の schema が `mrg20260703p9q0` と同等かを本番反映前に検証する。
- `PROD_TEST_DATABASE_URL` の `alembic_version` を `mrg20260703p9q0` に stamp する承認タイミングを決める。
