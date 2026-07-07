# Backend CI failure investigation: billing check / safe cleanup

作成日: 2026-06-15

## ローカル実行環境メモ

backend はローカル Python 直実行ではなく、Docker コンテナ上で動作している。

確認済みコンテナ:

```text
d14219916d99   keikakun_app-backend   "uvicorn app.main:ap..."   Up 13 hours   0.0.0.0:8000->8000/tcp   keikakun_app-backend-1
```

そのため、backend の pytest や依存関係確認はホスト側で `.venv` を作成して実行するのではなく、原則として次のように既存コンテナ内で実行する。

```bash
docker exec keikakun_app-backend-1 pytest tests/tasks/test_billing_check.py tests/utils/test_safe_cleanup_with_flag.py -m "not performance"
```

## 対象ログ

GitHub Actions の backend CI で以下が失敗した。

- `tests/tasks/test_billing_check.py::TestTrialExpirationCheck::*` の 8 件
- `tests/utils/test_safe_cleanup_with_flag.py::TestSafeTestDataCleanupWithFlag::test_delete_only_test_data` の 1 件

代表的な失敗内容:

```text
FAILED tests/tasks/test_billing_check.py::TestTrialExpirationCheck::test_expired_trial_updates_to_past_due - assert 2 == 1
FAILED tests/tasks/test_billing_check.py::TestTrialExpirationCheck::test_active_trial_not_updated - assert 1 == 0
FAILED tests/tasks/test_billing_check.py::TestTrialExpirationCheck::test_mixed_statuses_batch_update - assert 3 == 2
FAILED tests/utils/test_safe_cleanup_with_flag.py::TestSafeTestDataCleanupWithFlag::test_delete_only_test_data
sqlalchemy.exc.OperationalError: (psycopg.errors.DeadlockDetected) deadlock detected
CONTEXT: while deleting tuple ... in relation "staffs"
[SQL: DELETE FROM staffs WHERE is_test_data = true]
```

## 結論

今回の失敗は、画面系の変更そのものではなく、backend CI の DB テストが `pytest -n auto` で並列実行される前提に対して、既存の backend テスト/cleanup が共有 DB 全体を更新・削除していることが主因。

課金バッチテストは「このテストで作った Billing だけが更新される」前提で `expired_count == 1` や `== 0` を検証しているが、実装の `check_trial_expiration()` は office や test run で絞らず、DB 全体の期限切れ `Billing` を対象にしている。そのため、並列 worker や過去の cleanup 漏れデータが混ざると更新件数が期待より増える。

safe cleanup の deadlock は、テスト実行中に `DELETE FROM staffs WHERE is_test_data = true` のような全体削除を行う一方で、別 worker が `staffs` / `offices` / `office_staffs` を作成・参照しているため、PostgreSQL の行ロック/外部キー検査ロックが競合したものと見られる。

## 実装との照合

### CI は backend テストを並列実行している

`.github/workflows/cd-backend.yml`:

```yaml
run: pytest -n auto -m "not performance"
```

`-n auto` により、複数 worker が同じ `TEST_DATABASE_URL` に対して同時にテストを実行する。

### db_session は rollback 前提だが、該当テストは commit している

`k_back/tests/conftest.py` の `db_session` コメント:

```python
# commit() を呼ぶとトランザクションがコミットされ、ロールバックできなくなる。
```

一方、`k_back/tests/tasks/test_billing_check.py` では各テスト内で `await db_session.commit()` を複数回実行している。

例:

```python
office = await office_factory(session=db_session, is_test_data=True)
await db_session.commit()

billing = await crud.billing.create_for_office(...)
await db_session.commit()

billing.trial_end_date = datetime.now(timezone.utc) - timedelta(days=1)
billing.billing_status = BillingStatus.free
await db_session.commit()
```

このため、function scope の rollback では該当テストデータを完全に隔離できない。

### check_trial_expiration は DB 全体を対象にする

`k_back/app/tasks/billing_check.py`:

```python
query = select(Billing).where(
    Billing.billing_status.in_([BillingStatus.free, BillingStatus.early_payment]),
    Billing.trial_end_date < now
)

expired_billings = result.scalars().all()
```

office_id、is_test_data、テスト実行 ID などの絞り込みがない。これは本番バッチとしては自然だが、共有 DB 並列テストでは「他テストが作った期限切れ Billing」も更新対象になる。

ログ上の差分もこの挙動と一致する。

- `assert 2 == 1`: 自分の 1 件 + 他 worker/残存データ 1 件が更新された可能性が高い
- `assert 1 == 0`: 自分のデータは対象外だが、他の期限切れデータ 1 件が更新された
- `assert 3 == 2`: 自分の 2 件 + 他の 1 件が更新された

### SafeTestDataCleanup は全体削除を行う

`k_back/tests/utils/safe_cleanup.py`:

```python
DELETE FROM office_staffs
WHERE is_test_data = true
   OR office_id IN (SELECT id FROM offices WHERE is_test_data = true)
```

```python
for table in ["welfare_recipients", "offices", "staffs"]:
    DELETE FROM {table} WHERE is_test_data = true
```

さらに `delete_test_data()` は最後に `await db.commit()` する。

`tests/utils/test_safe_cleanup_with_flag.py::test_delete_only_test_data` はテスト中にこの全体 cleanup を直接呼ぶ。CI の `pytest -n auto` 下では、別 worker が同時に staff/office 系テストを実行している可能性があり、今回のログの `DELETE FROM staffs WHERE is_test_data = true` で deadlock した状況と整合する。

## 直接原因

1. `check_trial_expiration()` が DB 全体の期限切れ Billing を更新する。
2. `test_billing_check.py` が件数を厳密に `0/1/2` として検証している。
3. 該当テストが `commit()` を使うため、function rollback による隔離が効きにくい。
4. CI は `pytest -n auto` で同一 test DB を複数 worker が共有している。
5. `SafeTestDataCleanup.delete_test_data()` が `is_test_data=true` 全体を削除し、並列 worker の作成/参照中データと競合する。

## 修正方針

優先度順:

1. `tests/tasks/test_billing_check.py` は DB 全体件数ではなく、作成した Billing の状態遷移を主検証にする。
   - `expired_count == 1` のような厳密件数は、共有 DB 並列では不安定。
   - 件数を検証したい場合は、テスト専用 DB/schema/worker isolation を導入してから行う。

2. 課金バッチテストでは `commit()` を避け、可能な範囲で `flush()` + 同一 transaction 内の検証に寄せる。
   - 本番バッチが commit する都合で難しい場合は、テストごとに一意な DB/schema を使うか、対象 office_id を指定できるテスト用引数を設ける。

3. `SafeTestDataCleanup.delete_test_data()` を通常の並列テスト中に実行しない。
   - cleanup 自体のテストは `xdist` で直列化する、または専用 marker を付けて CI では別ジョブ/別 DB で実行する。
   - `pytest -n auto` の共有 DB 上で `DELETE FROM staffs WHERE is_test_data = true` を実行するのは deadlock の温床になる。

4. CI の DB テスト隔離を強化する。
   - worker ごとに DB/schema を分ける。
   - もしくは DB 全体を更新/削除するテストだけ `-n 0` で別実行する。
   - 暫定回避として backend CI の `pytest -n auto` をやめる選択肢もあるが、実行時間が増えるため恒久策は DB isolation。

## 追加確認メモ

今回のログでは billing 系の失敗件数がすべて「期待より 1 件多い」または「0 のはずが 1」になっている。これはロジックの状態遷移が壊れているというより、バッチ対象に余剰 Billing が混入している症状に近い。

`test_multiple_expired_trials` だけは `assert expired_count >= 3` になっており、共有 DB に余剰対象がある可能性をすでに許容している。他のテストも同じリスクを持っているが、厳密件数で検証しているため CI で失敗した。

## 推奨する次アクション

短期:

- `test_billing_check.py` の件数 assertion を、作成した Billing の状態確認中心に変更する。
- cleanup テストを CI 並列対象から外す、または serial 実行に分離する。

中期:

- `pytest-xdist` worker ごとの test DB/schema 分離を導入する。
- DB 全体に作用する batch/cleanup テストには専用 marker を付与し、通常の並列テストと分離する。

長期:

- `check_trial_expiration()` の本番仕様は維持しつつ、テストでは対象範囲を注入できる設計を検討する。
  - 例: private helper に query 条件を分離し、ユニットテストでは office_id などで対象を限定する。
  - public batch API は引き続き全体実行にする。
