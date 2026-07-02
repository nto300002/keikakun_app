# Stripe 課金ステータス整理 タスクリスト

作成日: 2026-06-18

## 背景

ローカル再検証により、Stripe CLI listener を起動していれば `customer.subscription.created` と `invoice.payment_succeeded` が local backend に到達し、`billing_status=early_payment` へ正常遷移することを確認した。

前回の `stripe_customer_id` はあるが `billing_status=free` のまま残る問題は、ローカル検証時に Stripe CLI listener を起動していなかったことが主因と判断する。

一方で、以下の設計課題は残る。

- Webhookイベント順序により、trial中でも `active` に上書きされる可能性がある。
- `past_due` に trial期限切れ、支払い失敗、機能制限対象という複数の意味が混在している。
- `past_due + trial中` が実装上は発生し得る。
- billing scheduler が job登録 wrapper を通らず起動している可能性がある。
- Frontend の書き込み制限・警告表示は主に `billing_status=past_due` を起点にしているため、backendで status を分離する場合は frontend も同時に修正範囲へ含める必要がある。

## 実装方針

TDDを前提に、実装範囲を段階分割する。

最初のPRでは、DB migration や status 追加までは行わず、Webhookイベント順序問題を小さく修正する。

status追加、既存データ移行、フロント表示変更は後続タスクとして扱う。

## タスク 1: Webhookイベント順序に強い `early_payment` 判定へ修正

ステータス: Green完了

優先度: 最優先

### 目的

`invoice.payment_succeeded` と `customer.subscription.created` の処理順が入れ替わっても、trial中なら最終的に `billing_status=early_payment` になるようにする。

### 現状の問題

`BillingService.process_subscription_created()` は、trial中判定に `billing_status == free` を含めている。

```python
is_trial_active = (
    billing.billing_status == BillingStatus.free and
    billing.trial_end_date and
    billing.trial_end_date > now
)
```

このため、`invoice.payment_succeeded` が先に来て `early_payment` になったあと、`customer.subscription.created` が後から来ると、`billing_status == free` ではないため `active` に上書きされる可能性がある。

### 実装箇所

- `k_back/app/services/billing_service.py`
  - `BillingService.process_subscription_created()`

### 実装方針

trial判定は `billing_status` ではなく `trial_end_date` を正とする。

```python
is_trial_active = (
    billing.trial_end_date and
    billing.trial_end_date > now
)
```

### Red テスト要件

- `tests/services/test_billing_service.py`
  - `invoice.payment_succeeded` を先に処理する。
  - `billing_status` が `early_payment` になることを確認する。
  - その後 `customer.subscription.created` を処理する。
  - trial中なら `billing_status` が `early_payment` のまま維持されることを確認する。
  - `stripe_subscription_id` が保存されることを確認する。

追加テスト候補名:

```text
test_subscription_created_after_payment_succeeded_keeps_early_payment_during_trial
```

### 受け入れ要件

- trial中に `invoice.payment_succeeded` が先、`customer.subscription.created` が後に来ても、最終状態が `early_payment` である。
- trial終了後に `customer.subscription.created` が来た場合は `active` になる。
- 既存の `process_subscription_created_early_payment` と `process_subscription_created_active_after_trial` が通る。
- 既存の課金周辺テストが通る。

### 実行テスト

```bash
docker exec keikakun_app-backend-1 pytest \
  tests/services/test_billing_service.py::TestBillingServiceTransactionIntegrity::test_process_payment_succeeded_atomic_transaction \
  tests/services/test_billing_service.py::TestBillingServiceTransactionIntegrity::test_process_subscription_created_early_payment \
  tests/services/test_billing_service.py::TestBillingServiceTransactionIntegrity::test_process_subscription_created_active_after_trial \
  tests/services/test_billing_service.py::TestBillingServiceTransactionIntegrity::test_subscription_created_after_payment_succeeded_keeps_early_payment_during_trial \
  -q
```

### 進捗記録

2026-06-18 実施。

Red:

- `tests/services/test_billing_service.py` に `test_subscription_created_after_payment_succeeded_keeps_early_payment_during_trial` を追加。
- 現行実装では、`invoice.payment_succeeded` 後に `customer.subscription.created` が来ると `billing_status=active` に上書きされ、期待どおり失敗した。

Green:

- `k_back/app/services/billing_service.py` の `BillingService.process_subscription_created()` を修正。
- trial判定から `billing_status == BillingStatus.free` を外し、`trial_end_date > now` を正として `early_payment` / `active` を決めるようにした。
- naive datetime 対策として既存の `_normalize_trial_end_date()` を利用した。

確認結果:

```text
4 passed, 15 warnings
```

実行済み:

```bash
docker exec keikakun_app-backend-1 pytest \
  tests/services/test_billing_service.py::TestBillingServiceTransactionIntegrity::test_process_payment_succeeded_atomic_transaction \
  tests/services/test_billing_service.py::TestBillingServiceTransactionIntegrity::test_process_subscription_created_early_payment \
  tests/services/test_billing_service.py::TestBillingServiceTransactionIntegrity::test_process_subscription_created_active_after_trial \
  tests/services/test_billing_service.py::TestBillingServiceTransactionIntegrity::test_subscription_created_after_payment_succeeded_keeps_early_payment_during_trial \
  -q
```

残確認:

- 課金周辺のより広いテストは未実行。
- タスク1単体の受け入れ要件は満たした。

## タスク 2: billing scheduler 起動経路を修正

ステータス: Green完了

優先度: 高

### 目的

`check_trial_expiration` と `check_scheduled_cancellation` が確実に scheduler に登録されるようにする。

### 現状の問題

`app/scheduler/billing_scheduler.py` には job登録を行う `start()` wrapper がある。

しかし `app/main.py` では `billing_scheduler` インスタンスを import している。

```python
from app.scheduler.billing_scheduler import billing_scheduler
```

startup では以下を呼んでいる。

```python
billing_scheduler.start()
```

これは wrapper ではなく `AsyncIOScheduler.start()` を直接呼ぶため、job登録が行われない可能性がある。

### 次タスク確認メモ

2026-06-18 確認。

実コード上もタスク2の前提は正しい。

- `k_back/app/scheduler/billing_scheduler.py`
  - module-level に `billing_scheduler = AsyncIOScheduler()` がある。
  - module-level の `start()` wrapper 内で `check_trial_expiration` / `check_scheduled_cancellation` を `add_job()` している。
- `k_back/app/main.py`
  - `from app.scheduler.billing_scheduler import billing_scheduler` で scheduler インスタンスを import している。
  - startup で `billing_scheduler.start()` を呼んでいるため、module-level wrapper の `start()` ではなく `AsyncIOScheduler.start()` が呼ばれる。
  - その結果、billing scheduler の job登録処理が通らない可能性がある。

次にTDDで着手する場合は、まず `tests/scheduler/test_billing_scheduler.py` を追加し、wrapper の `start()` が job id `check_trial_expiration` / `check_scheduled_cancellation` を登録することを Red として固定する。

### 実装箇所

- `k_back/app/main.py`
- `k_back/app/scheduler/billing_scheduler.py`
- 必要に応じて scheduler テスト追加ファイル

### 実装方針

`main.py` では scheduler インスタンスではなく、module wrapper の `start()` / `shutdown()` を呼ぶ。

候補:

```python
from app.scheduler import billing_scheduler

billing_scheduler.start()
billing_scheduler.shutdown()
```

または明示的に alias する。

```python
from app.scheduler.billing_scheduler import start as start_billing_scheduler
from app.scheduler.billing_scheduler import shutdown as shutdown_billing_scheduler
```

### Red テスト要件

- `main.py` startup 相当の処理で、billing scheduler wrapper の `start()` が呼ばれること。
- `billing_scheduler.start()` wrapper を直接呼ぶと、以下の job id が登録されること。
  - `check_trial_expiration`
  - `check_scheduled_cancellation`
- shutdown が未起動状態でも安全に扱えること。

### 受け入れ要件

- backend起動時に `check_trial_expiration` と `check_scheduled_cancellation` が登録される。
- 二重起動で job が重複しない。
- `TESTING=1` の場合は scheduler 起動がスキップされる。
- `early_payment -> active` と `free -> past_due` の定期処理が実行可能な状態になる。

### 実行テスト

```bash
docker exec keikakun_app-backend-1 pytest \
  tests/tasks/test_billing_check.py \
  tests/scheduler/test_billing_scheduler.py \
  -q
```

### 進捗記録

2026-06-18 実施。

Red:

- `tests/scheduler/test_billing_scheduler.py` を追加。
- `main.py` が `billing_scheduler` module wrapper ではなく `AsyncIOScheduler` インスタンスを参照していることを検出した。
- `billing_scheduler.start()` の二重呼び出しで `SchedulerAlreadyRunningError` が発生することを検出した。
- 未起動状態の `billing_scheduler.shutdown()` で例外が発生することを検出した。

Green:

- `k_back/app/main.py` の import を `from app.scheduler import billing_scheduler` に変更し、module wrapper の `start()` / `shutdown()` が呼ばれるようにした。
- `k_back/app/scheduler/billing_scheduler.py` の `start()` を冪等化した。
  - job登録は `replace_existing=True` のまま維持。
  - scheduler 未起動時のみ `billing_scheduler.start()` を呼ぶ。
  - 既に起動済みの場合は job refresh のログだけ出す。
- `shutdown()` を未起動状態でも安全にした。

確認結果:

```text
20 passed, 15 warnings
```

実行済み:

```bash
docker exec keikakun_app-backend-1 pytest \
  tests/tasks/test_billing_check.py \
  tests/scheduler/test_billing_scheduler.py \
  -q
```

残確認:

- backend全体テストは未実行。
- タスク2単体の受け入れ要件は満たした。

## タスク 3: `past_due` の責務分離設計を確定する

ステータス: 完了

優先度: 高

### 目的

`past_due` に混在している意味を整理し、今後の状態追加方針を決める。

現状の `past_due` は以下をまとめて扱っている。

- trial期限切れ・未課金
- 支払い失敗
- 支払いアクションが必要
- 書き込み制限対象

### 実装箇所

このタスクでは原則コード変更しない。

- `md_files_design_note/task/bug_fix/stripe/billing_status_transition_investigation.md`
- 必要に応じて新規設計メモ

### 設計候補

新status:

```text
trial_expired
  trial終了後、未課金

payment_failed
  支払い失敗、または請求失敗
```

既存status:

```text
free
early_payment
active
canceling
canceled
```

`past_due` は互換用として一時的に残し、段階的に `trial_expired` / `payment_failed` へ移行する。

### 受け入れ要件

- `trial_expired` と `payment_failed` の意味が明文化されている。
- `past_due` を互換用に残すか、廃止対象にするかが決まっている。
- 書き込み制限対象が明文化されている。
- フロント表示文言の方針が明文化されている。
- migration方針が決まっている。

### 次タスク確認メモ

2026-06-18 確認。

タスク3は実装前の設計確定タスクとして扱う。

確認対象:

- `past_due` を新規ロジックで使い続けるか、互換用 status として段階的に縮退させるか。
- `trial_expired` の定義。
  - trial終了後、未課金、Stripe Subscription なし。
  - 主な導線はサブスクリプション登録。
- `payment_failed` の定義。
  - Stripe Subscription / Invoice は存在するが、支払い失敗または支払いアクションが必要。
  - 主な導線は支払い方法更新、再決済、Customer Portal。
- 書き込み制限対象。
  - 制限対象候補: `trial_expired` / `payment_failed` / `past_due` / `canceled`
  - 許可対象候補: `free` / `early_payment` / `active` / `canceling`
- frontend 表示方針。
  - `trial_expired` は「無料期間終了」。
  - `payment_failed` は「支払い失敗」。
  - `past_due` は互換表示として残し、新規の意味付けには使わない。
- migration 方針。
  - Alembic migration と同内容の手動実行用SQLを作成する。
  - 既存 `past_due` は一括で機械的に移行せず、`stripe_subscription_id` の有無と必要に応じて Stripe 側状態を確認する。

次に作業する場合は、まず `billing_status_transition_investigation.md` に上記の設計結論を確定版として追記し、タスク4の Red テストに進む前提を固める。

### 確定記録

2026-06-18 確定。

- `past_due` は存在そのものは残す。
- 既存 `past_due` データは移行対象にする。
- 新規の状態遷移では `past_due` に複数の意味を持たせず、`trial_expired` / `payment_failed` へ分離する。
- `trial_expired` の定義は以下で確定。
  - trial終了後、未課金、Stripe Subscription なし。
  - 主な導線はサブスクリプション登録。
- `payment_failed` の定義は以下で確定。
  - trial期間外で、Stripe Subscription / Invoice は存在するが、支払い失敗または支払いアクションが必要。
  - 主な導線は支払い方法更新、再決済、Customer Portal。
- Frontend 表示方針は以下で確定。
  - `trial_expired` 専用モーダルを設定する。
  - `payment_failed` 専用モーダルを設定する。
  - `payment_failed` は trial期間外の場合に表示する。
  - `past_due` は互換表示として残す。
- `billing_status_transition_investigation.md` に確定方針を追記済み。

## タスク 4: 新status追加のRedテストを作成

ステータス: Red完了

優先度: 中

### 目的

`trial_expired` と `payment_failed` を追加する前に、期待する状態遷移をテストで固定する。

### 実装箇所

- `k_back/tests/tasks/test_billing_check.py`
- `k_back/tests/services/test_billing_service.py`
- `k_back/tests/crud/test_crud_billing.py`
- 必要に応じて `k_back/tests/api/test_billing.py`

### Red テスト要件

- `check_trial_expiration()` で `free + trial_end_date <= now -> trial_expired`。
- `check_trial_expiration()` で `early_payment + trial_end_date <= now -> active`。
- `invoice.payment_failed + trial_end_date <= now -> payment_failed`。
- `invoice.payment_failed + trial_end_date > now` は `past_due` にしない。
- `customer.subscription.created + trial_end_date > now -> early_payment`。
- `customer.subscription.created + trial_end_date <= now -> active`。
- `trial_end_date > now + billing_status=past_due` は不整合として検知される。

### 受け入れ要件

- 現行実装で失敗するRedテストが追加されている。
- テスト名から期待遷移が読める。
- `past_due` の曖昧な責務を前提にしたテストが整理されている。

### 進捗記録

2026-06-18 実施。

Redテスト追加:

- `k_back/tests/tasks/test_billing_check.py`
  - `test_expired_trial_updates_to_trial_expired`
  - `test_mixed_statuses_batch_update_uses_trial_expired`
- `k_back/tests/services/test_billing_service.py`
  - `test_process_payment_failed_after_trial_sets_payment_failed`
  - `test_process_payment_failed_during_trial_keeps_existing_status`
- `k_back/tests/services/test_billing_status_helpers.py`
  - `test_new_statuses_are_restricted_and_require_payment_action`
  - `test_get_status_display_message_for_new_statuses`
  - `test_get_next_action_message_for_new_statuses`

確認結果:

```text
7 failed, 15 warnings
```

主な失敗理由:

- `BillingStatus.trial_expired` が未定義。
- `BillingStatus.payment_failed` が未定義。
- `check_trial_expiration()` が `free + trial_end_date <= now` を `past_due` に更新している。
- `process_payment_failed()` が trial期間外・trial期間中を問わず `past_due` に更新している。
- `crud.billing` のステータス判定・表示文言・次アクションが `trial_expired` / `payment_failed` に未対応。

実行済み:

```bash
docker exec keikakun_app-backend-1 pytest \
  tests/tasks/test_billing_check.py::TestTrialExpirationCheck::test_expired_trial_updates_to_trial_expired \
  tests/tasks/test_billing_check.py::TestTrialExpirationCheck::test_mixed_statuses_batch_update_uses_trial_expired \
  tests/services/test_billing_service.py::TestBillingServiceTransactionIntegrity::test_process_payment_failed_after_trial_sets_payment_failed \
  tests/services/test_billing_service.py::TestBillingServiceTransactionIntegrity::test_process_payment_failed_during_trial_keeps_existing_status \
  tests/services/test_billing_status_helpers.py::TestBillingStatusChecks::test_new_statuses_are_restricted_and_require_payment_action \
  tests/services/test_billing_status_helpers.py::TestBillingStatusMessages::test_get_status_display_message_for_new_statuses \
  tests/services/test_billing_status_helpers.py::TestBillingStatusMessages::test_get_next_action_message_for_new_statuses \
  -q
```

## タスク 5: Backend に `trial_expired` / `payment_failed` を追加

ステータス: Green完了

優先度: 中

### 目的

Backendで新statusを扱えるようにする。

### 実装箇所

- `k_back/app/models/enums.py`
- `k_back/app/schemas/billing.py`
- `k_back/app/crud/crud_billing.py`
- `k_back/app/api/deps.py`
- `k_back/app/services/billing_service.py`
- `k_back/app/tasks/billing_check.py`
- Alembic migration
- Alembic migration と同内容の手動実行用SQLファイル
  - 例: `k_back/migrations/versions/<revision>_*.py`
  - 例: `k_back/migrations/sql/<revision>_*.sql`

### 実装要件

- `BillingStatus.trial_expired` を追加する。
- `BillingStatus.payment_failed` を追加する。
- `check_trial_expiration()` の `free -> past_due` を `free -> trial_expired` に変更する。
- `process_payment_failed()` の遷移先を `payment_failed` に変更する。
- `requires_payment_action()` が `trial_expired` / `payment_failed` を true にする。
- `can_access_paid_features()` が `trial_expired` / `payment_failed` を false にする。
- `require_active_billing()` が `trial_expired` / `payment_failed` / `canceled` を制限対象にする。
- DB定義変更が発生する場合は、Alembic migration ファイルと同じDDL/DML内容のSQLファイルを必ず作成する。
- SQLファイルはDB上で手動実行される前提のため、実行順、対象テーブル、既存データへの影響、rollback相当の戻し方が読める内容にする。

### 受け入れ要件

- 新statusを含むCRUDテストが通る。
- Webhook処理の状態遷移テストが通る。
- バッチテストが通る。
- Alembic migration と同内容のSQLファイルが作成されている。
- migration とSQLの内容差分がないことをレビューで確認している。
- 既存 `past_due` をすぐ削除せず、互換的に扱える。

### 進捗記録

2026-06-18 実施。

実装:

- `k_back/app/models/enums.py`
  - `BillingStatus.trial_expired` を追加。
  - `BillingStatus.payment_failed` を追加。
- `k_back/app/tasks/billing_check.py`
  - `check_trial_expiration()` の `free -> past_due` を `free -> trial_expired` に変更。
  - `early_payment -> active` は維持。
  - 遷移ログが更新後statusではなく、更新前statusからの遷移を出すように修正。
- `k_back/app/services/billing_service.py`
  - `process_payment_failed()` を trial期間で分岐。
  - trial期間外は `payment_failed` へ更新。
  - trial期間中は既存statusを維持し、`past_due` / `payment_failed` へ落とさない。
  - Checkout前の期限切れ `free` 補正も、新規遷移として `trial_expired` へ統一。
- `k_back/app/crud/crud_billing.py`
  - `trial_expired` / `payment_failed` を支払いアクション対象に追加。
  - `can_access_paid_features()` では引き続き非許可。
  - 表示文言と次アクション文言を追加。
- `k_back/app/api/deps.py`
  - 書き込み制限対象に `trial_expired` / `payment_failed` を追加。
- 旧仕様テストを新仕様へ更新。
  - `past_due` 既存データは互換用として維持され、バッチで `trial_expired` へ自動変換しない。
- レビュー指摘対応。
  - `test_process_payment_succeeded_rollback_on_error` の固定 `stripe_customer_id` / `event_id` をUUID付きに変更。
  - Checkout前の期限切れ `free` 補正テスト名・期待値を `recovers_to_trial_expired` へ変更。
  - `past_due + trial期間中` は互換用の既存状態として、期限切れバッチでは自動補正しないことをテストで固定。
  - `caplog` で `free -> trial_expired` / `early_payment -> active` のログ遷移を検証。

DB確認:

- `TEST_DATABASE_URL` 側の `billingstatus` enum に以下8値があることを確認。

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

確認結果:

```text
39 passed, 15 warnings
```

実行済み:

```bash
docker exec keikakun_app-backend-1 pytest \
  tests/services/test_billing_status_helpers.py \
  tests/tasks/test_billing_check.py \
  tests/services/test_billing_service.py::TestBillingServiceTransactionIntegrity \
  -q
```

補足:

- 直前の対象6件確認では、テスト後 safe cleanup で既存テストデータに対する `office_staffs_office_id_fkey` のFK警告が出た。
- 上記の39件確認では開始時 cleanup が残データを削除し、終了時 cleanup も成功した。
- backend全体テストは未実行。

### タスク5レビュー・周辺影響調査

2026-06-18 追加レビュー。

結論:

- Backend側のタスク5は、現在の受け入れ要件に対して完了扱いでよい。
- `trial_expired` / `payment_failed` の enum 追加、期限切れ無料トライアルの `trial_expired` 化、支払い失敗の `payment_failed` 化、`past_due` の後方互換維持は実装されている。
- checkout の新規 Customer ルート・既存 Customer ルートの両方で、期限切れ `free` が `trial_expired` に補正されることを確認した。
- `process_payment_failed()` は trial期間中の既存statusを維持し、trial期間外のみ `payment_failed` へ更新するため、Stripeイベント順序による trial中の誤制限リスクは抑えられている。
- migration ファイルと手動実行用SQLファイルは作成済み。ただし、本レビューではDB本体への手動SQL適用は実施していないため、環境反映時は upgrade SQL 実行後に confirm SQL でCHECK制約と既存データを確認する必要がある。

確認済みテスト:

```text
41 passed, 15 warnings
```

実行済み:

```bash
docker exec keikakun_app-backend-1 pytest \
  tests/services/test_billing_status_helpers.py \
  tests/tasks/test_billing_check.py \
  tests/services/test_billing_service.py::TestBillingServiceTransactionIntegrity \
  tests/api/test_billing.py::test_create_checkout_session_expired_free_without_customer_recovers_to_trial_expired \
  tests/api/test_billing.py::test_create_checkout_session_expired_free_with_existing_customer_recovers_to_trial_expired \
  -q
```

周辺機能への影響:

- `k_front/types/enums.ts` の `BillingStatus` に `trial_expired` / `payment_failed` が未追加。Backendから新statusが返ると、Frontend側の型・分岐と不一致になる。
- `k_front/components/protected/admin/PlanTab.tsx` の status badge は新status未対応。実行時に `getStatusBadge()` が未定義を返す場合、管理画面のプラン表示で描画エラーになる可能性がある。
- `k_front/contexts/BillingContext.tsx` の `canWrite` は `past_due` / `canceled` のみを制限している。`trial_expired` / `payment_failed` の事業所で、Frontend上は編集可能に見えるがBackendで拒否される不整合が起きる可能性がある。
- `k_front/components/billing/PastDueModalWrapper.tsx` は `past_due` のみをモーダル表示対象にしている。`payment_failed` では支払い方法更新導線、`trial_expired` では登録導線が出ない可能性がある。
- `k_front/components/billing/TrialExpiryBanner.tsx` は `free` 前提の表示であり、期限切れ後の `trial_expired` 用表示が未整理。
- `k_front/components/protected/Dashboard.tsx` は `past_due` の警告表示のみを扱っており、新statusではユーザーに制限理由が伝わりにくい。
- `k_back/app/api/v1/endpoints/billing.py` と `k_back/app/scheduler/billing_scheduler.py` に、旧仕様の `past_due` を前提にしたコメント・説明が残っている。動作影響は低いが、保守時の誤読を避けるため更新対象。
- `k_back/tests/scripts/setup_edge_case_states.py` と `k_back/tests/scripts/README.md` には、期限切れ・支払い失敗を `past_due` として扱う旧テストデータ説明が残っている。手動検証・E2E補助で混乱しないよう、新statusまたは legacy `past_due` として明示する必要がある。
- `k_back/tests/services/test_dashboard_service.py` では `trial_expired` / `payment_failed` のダッシュボード影響テストが不足している。Backend制限とFrontend表示の整合を詰める際に追加候補。

残タスク:

- タスク6でFrontendの enum、権限制御、警告表示、モーダル、プラン画面の status badge を新statusへ対応する。
- Stripe webhook・scheduler 周辺のコメントを `trial_expired` / `payment_failed` 前提へ更新する。
- 手動SQL適用環境では、upgrade SQL 実行後に confirm SQL で `ck_billings_billing_status` が8値を許可していることを確認する。
- 既存 `past_due` データを `trial_expired` / `payment_failed` へ寄せるかは、タスク7のデータ移行方針で判断する。

## タスク 6: Frontend 表示と権限制御を新statusへ対応

ステータス: 次タスク候補

優先度: 中

### 目的

ユーザーに「無料期間終了」と「支払い失敗」を別の状態として表示する。

また、backend の status 分離後も、書き込み制限対象が frontend 側で漏れないようにする。

現状の実装では、制限・警告の多くが `BillingStatus.PAST_DUE` に直接依存している。`trial_expired` / `payment_failed` を追加して backend の制限対象にしても、frontend の `canWrite` や各画面の分岐を更新しない場合、新statusの事業所で操作制限や警告表示が効かない可能性がある。

### 実装箇所

- `k_front/contexts/BillingContext.tsx`
  - `canWrite` が現在 `past_due` / `canceled` のみを制限している。
  - `isPastDue` が現在 `past_due` のみを表す。
- `k_front/types/enums.ts`
  - `BillingStatus` enum に backend と同じ status を追加する。
- `k_front/components/billing/BillingProtectedButton.tsx`
  - `canWrite` / `isPastDue` に依存してボタン無効化とツールチップ文言を決めている。
- `k_front/components/billing/PastDueModalWrapper.tsx`
  - `isPastDue` の場合のみモーダルを表示している。
- `k_front/components/billing/PastDueModal.tsx`
  - 表示文言が支払い遅延前提になっている。
- `k_front/components/billing/TrialExpiryBanner.tsx`
  - `free` のみを無料トライアル表示対象にしている。
  - trial期限切れ後は表示しないため、`trial_expired` 用の別表示方針が必要。
- `k_front/components/protected/admin/PlanTab.tsx`
  - status badge が既存statusのみ対応している。
  - `past_due` のみ支払い遅延警告を表示している。
  - サブスク登録ボタン、支払い方法変更・解約ボタンの表示条件に `past_due` が直接含まれている。
- `k_front/components/protected/dashboard/Dashboard.tsx`
  - `canEdit` が `free` / `active` / `early_payment` のみ許可している。
  - `past_due` のみ警告表示している。

### 実装要件

- `trial_expired` を「無料期間終了」として表示する。
- `payment_failed` を「支払い失敗」として表示する。
- `past_due` は互換表示として残す。
- `isPastDue` のような単一フラグを必要に応じて分離する。
  - `isTrialExpired`
  - `isPaymentFailed`
  - `requiresPaymentAction`
- `canWrite` は backend の `require_active_billing()` / `can_access_paid_features()` と同じ制限対象を参照する。
  - 制限対象候補: `trial_expired` / `payment_failed` / `past_due` / `canceled`
  - 許可対象候補: `free` / `early_payment` / `active` / `canceling`
- `BillingProtectedButton` の無効化理由は `trial_expired` と `payment_failed` で分ける。
  - `trial_expired`: 無料期間終了、プラン登録が必要。
  - `payment_failed`: 支払い失敗、支払い方法更新または再決済が必要。
- `PastDueModalWrapper` は `past_due` 専用ではなく、支払いアクションが必要な状態を扱う wrapper へ改名または責務変更を検討する。
- `PlanTab` は status ごとの導線を分ける。
  - `trial_expired`: サブスクリプション登録導線を表示する。
  - `payment_failed`: 支払い方法変更・再決済導線を表示する。
  - `past_due`: 互換用として既存導線を維持する。
- `Dashboard` の警告文言は `trial_expired` と `payment_failed` で分ける。
- 既存の `past_due` 文言「無料お試し期間が過ぎているため利用できません」は、支払い失敗にも使われ得るため、新status移行時に見直す。

### Frontend具体修正チェックリスト

方針:

- 既存 `past_due` で行っていたモーダル表示、ボタン無効化、作成・編集・削除の表示制限は、以下の状態へ引き継ぐ。
  - `trial_expired`
  - trial終了後かつ `payment_failed`
  - legacy互換の `past_due`
- `payment_failed` はBackend上は trial終了後のみ設定される想定。ただし、Frontendでは不整合データに備えて `trial_days_remaining <= 0` または `trial_end_date <= now` を確認できる helper を用意する。
- 書き込み可否の最終条件はBackendの `require_active_billing()` と揃える。
  - 制限: `trial_expired` / `payment_failed` / `past_due` / `canceled`
  - 許可: `free` / `early_payment` / `active` / `canceling`

#### 共通型・共通判定

- [ ] `k_front/types/enums.ts`
  - `BillingStatus.TRIAL_EXPIRED = 'trial_expired'` を追加する。
  - `BillingStatus.PAYMENT_FAILED = 'payment_failed'` を追加する。
- [ ] `k_front/contexts/BillingContext.tsx`
  - `canWrite` の条件に `trial_expired` / `payment_failed` を追加する。
  - 既存 `isPastDue` は互換用として残すか、利用箇所を置換したうえで段階的に削除する。
  - 追加候補:
    - `isTrialExpired`
    - `isPaymentFailed`
    - `isPaymentFailedAfterTrial`
    - `requiresPaymentAction`
    - `billingRestrictionReason`
  - `requiresPaymentAction` は `trial_expired` / `past_due` / trial終了後の `payment_failed` で true を返す。
  - `billingRestrictionReason` は以下の文言差し替えに使える値を返す。
    - `trial_expired`: 無料期間終了
    - `payment_failed`: 支払い失敗
    - `past_due`: 支払い確認が必要
    - `canceled`: プラン無効

#### 共通ボタン制限

- [ ] `k_front/components/billing/BillingProtectedButton.tsx`
  - disabled条件は `!canWrite` のまま維持し、`canWrite` 側で新statusを制限する。
  - tooltip文言を status 別に分ける。
    - `trial_expired`: `無料トライアル期間が終了しているため、この操作は無効化されています。サブスクリプションに登録してください。`
    - trial終了後かつ `payment_failed`: `サブスクリプションの支払いが失敗しているため、この操作は無効化されています。支払い方法を更新してください。`
    - `past_due`: `お支払いの確認が必要なため、この操作は無効化されています。プラン管理画面を確認してください。`
    - `canceled`: `課金プランが有効でないため、この操作は無効化されています。`
  - コメントの `past_due または canceled` を `支払いアクションが必要な状態または canceled` に更新する。

#### モーダル表示

- [ ] `k_front/components/billing/PastDueModalWrapper.tsx`
  - 表示条件を `isPastDue` だけではなく `requiresPaymentAction` に変更する。
  - `trial_expired` / trial終了後かつ `payment_failed` / `past_due` で、セッション中1回の自動表示を維持する。
  - sessionStorage key は、既存互換を優先するなら `pastDueModalShown` を維持する。責務変更を明確にするなら `billingActionRequiredModalShown` へ変更し、既存keyとの重複表示を避ける移行を検討する。
  - コメントの「支払い遅延状態の場合」を「支払いアクションが必要な状態の場合」に更新する。
- [ ] `k_front/components/billing/PastDueModal.tsx`
  - `PastDueModal` を汎用化する場合は名称を `BillingActionRequiredModal` などへ変更する。
  - 名称を維持する場合でも、内部文言は status 別に分ける。
  - `trial_expired` の文言:
    - タイトル: `無料トライアル期間が終了しました`
    - 説明: `サブスクリプション登録が完了するまで、一部の操作が制限されています。`
    - 主ボタン: `サブスクリプションに登録する`
    - 主ボタンの処理: `billingApi.createCheckoutSession()`
  - trial終了後かつ `payment_failed` の文言:
    - タイトル: `サブスクリプションの支払いが失敗しました`
    - 説明: `前回の請求処理が失敗したため、アカウントが一時的に制限されています。`
    - 主ボタン: `支払い方法を更新する`
    - 主ボタンの処理: `billingApi.createPortalSession()`
  - legacy `past_due` の文言:
    - タイトル: `お支払いの確認が必要です`
    - 説明: `お支払い状況の確認が必要なため、アカウントが一時的に制限されています。`
    - 主ボタン: `プラン管理を確認する` または `支払い方法を更新する`
  - 制限対象機能の文言は既存を引き継ぐ。
    - `利用者・支援計画の新規作成`
    - `既存データの編集・更新`
    - `個別支援計画のPDFアップロード`

#### 管理者設定 > プラン

- [ ] `k_front/components/protected/admin/PlanTab.tsx`
  - `getStatusBadge()` に `trial_expired` を追加する。
    - label: `無料期間終了`
    - 色: warning系またはred系。既存 `past_due` と近い警告色でよいが、`payment_failed` とは区別する。
  - `getStatusBadge()` に `payment_failed` を追加する。
    - label: `支払い失敗`
    - 色: red系。
  - `getStatusBadge()` に default fallback を追加し、未知statusで画面が落ちないようにする。
  - 「トライアル期限切れの警告」の条件を `daysUntilTrialEnd < 0 && free` から `trial_expired` も対象に変更する。
  - `trial_expired` の警告文言:
    - 見出し: `無料トライアル期間は終了しています`
    - 本文: `サブスクリプション登録が完了するまで、一部の操作が制限されています。登録時に月額料金が請求されます。`
  - `payment_failed` の警告文言を追加する。
    - 見出し: `サブスクリプションの支払いが失敗しています`
    - 本文: `サービスの利用が制限されています。支払い方法を更新し、請求処理を完了してください。`
  - legacy `past_due` の警告文言を残す。
    - 見出し: `お支払いの確認が必要です`
    - 本文: `サービスの利用が制限されています。プラン管理または支払い方法を確認してください。`
  - サブスク登録ボタンの表示条件に `trial_expired` を追加する。
    - 対象: `free` / `trial_expired` / `past_due` / `canceled`
  - 支払い方法変更・解約ボタンの表示条件に `payment_failed` を追加する。
    - 対象: `early_payment` / `active` / `payment_failed` / `past_due` / `canceling`
  - `payment_failed` の場合は、ボタン文言を `支払い方法を更新する` に寄せるか、既存の `支払い方法の変更・解約` のままでよいかを決める。
  - コメントの `free、past_due、またはcanceled`、`early_payment, active, past_due, canceling` を新status込みに更新する。

#### 利用者ダッシュボード

- [ ] `k_front/components/protected/dashboard/Dashboard.tsx`
  - `canEdit` は現状 `free` / `active` / `early_payment` のみ許可のため、新status追加後も結果として制限される。ただし意図が読み取れるよう、`canWrite` と同じ helper または制限statusリストに寄せる。
  - 警告表示条件を `billing_status === PAST_DUE` から `trial_expired` / trial終了後かつ `payment_failed` / legacy `past_due` に拡張する。
  - `trial_expired` の警告文言:
    - 見出し: `無料トライアル期間が終了しているため利用できません`
    - 本文: `新規作成・編集・削除などの操作はご利用いただけません。オーナーの方は管理者設定のプラン登録ページからサブスクリプションに登録してください。`
  - trial終了後かつ `payment_failed` の警告文言:
    - 見出し: `サブスクリプションの支払いが失敗しているため利用できません`
    - 本文: `新規作成・編集・削除などの操作はご利用いただけません。オーナーの方は管理者設定のプラン登録ページから支払い方法を更新してください。`
  - legacy `past_due` の警告文言:
    - 見出し: `お支払いの確認が必要なため利用できません`
    - 本文: `新規作成・編集・削除などの操作はご利用いただけません。オーナーの方は管理者設定のプラン登録ページを確認してください。`
  - 既存文言 `無料お試し期間が過ぎているため利用できません` は `payment_failed` には使わない。

#### トライアル期限バナー

- [ ] `k_front/components/billing/TrialExpiryBanner.tsx`
  - `free` の期限前表示は維持する。
  - `trial_expired` は通常バナーではなく、モーダルまたはDashboard/PlanTab警告に任せる方針でよい。
  - ただしコメントの `トライアル期限切れの場合は表示しない（別のモーダルで対応）` は、新しいモーダル条件と一致するように更新する。
  - trial終了後かつ `payment_failed` ではトライアルバナーを表示しない。

#### テスト観点

- [ ] `trial_expired` で、Dashboardの作成・編集・削除導線が既存 `past_due` と同等に制限される。
- [ ] trial終了後かつ `payment_failed` で、Dashboardの作成・編集・削除導線が既存 `past_due` と同等に制限される。
- [ ] `trial_expired` で、ログイン後または画面表示時に支払いアクションモーダルがセッション中1回表示される。
- [ ] trial終了後かつ `payment_failed` で、ログイン後または画面表示時に支払いアクションモーダルがセッション中1回表示される。
- [ ] `trial_expired` のモーダル主ボタンはCheckoutへ誘導する。
- [ ] `payment_failed` のモーダル主ボタンはCustomer Portalへ誘導する。
- [ ] 管理者設定 > プランで、`trial_expired` は `無料期間終了` badge とサブスク登録ボタンを表示する。
- [ ] 管理者設定 > プランで、`payment_failed` は `支払い失敗` badge と支払い方法更新導線を表示する。
- [ ] legacy `past_due` でも画面が落ちず、既存相当の制限と導線が表示される。
- [ ] `free` / `early_payment` / `active` / `canceling` の既存表示・導線が退行していない。

### Red テスト要件

- `BillingContext` の単体テストまたは hook テストで、以下を固定する。
  - `trial_expired` は `canWrite=false`。
  - `payment_failed` は `canWrite=false`。
  - `past_due` は互換のため `canWrite=false`。
  - `free` / `early_payment` / `active` / `canceling` は `canWrite=true`。
- `BillingProtectedButton` のテストで、`trial_expired` / `payment_failed` / `past_due` のとき disabled になることを確認する。
- `PlanTab` のテストで、`trial_expired` と `payment_failed` の badge・警告文・表示ボタンが分かれることを確認する。
- `Dashboard` のテストで、`trial_expired` と `payment_failed` の警告文が分かれることを確認する。

### 受け入れ要件

- `trial_expired` と `payment_failed` の表示が分かれている。
- backendの書き込み制限対象と frontend の `canWrite` が一致する。
- 既存 `past_due` データでも破綻しない。
- status追加後、`trial_expired` / `payment_failed` の事業所で新規作成・編集・削除などの保護対象操作が frontend でも無効化される。
- 管理画面のプランタブで、ユーザーが次に行うべき操作が status ごとに判別できる。
- `past_due` だけを見て制限する新規コードが増えない。

## タスク 7: 既存データ移行と不整合検知

優先度: 中から低

### 目的

既存の `past_due` データを新しい意味へ移行する。

### 実装箇所

- Alembic migration
- Alembic migration と同内容の手動実行用SQL
- 管理用SQL
- 必要に応じて診断スクリプト

### 移行候補

```sql
-- trial期限切れ・未課金候補
UPDATE billings
SET billing_status = 'trial_expired'
WHERE billing_status = 'past_due'
  AND stripe_subscription_id IS NULL;

-- 支払い失敗・購読あり候補
UPDATE billings
SET billing_status = 'payment_failed'
WHERE billing_status = 'past_due'
  AND stripe_subscription_id IS NOT NULL;
```

### 注意

- 上記SQLは仮案。
- 実行前に Stripe Subscription / Invoice の実状態を確認する。
- `past_due + trial中` は一括移行せず、個別確認する。
- rollback可能なmigrationにする。
- 本アプリでは migration ファイルを作成するだけで完了にしない。
- migration と同じ内容のSQLファイルを作成し、DB上で実行できる形式にする。
- SQLファイルには、既存データ更新件数の確認SQL、実行前確認SQL、実行後確認SQL、rollback相当の戻しSQLまたは戻し手順を含める。
- enum/check constraint などDB定義変更を含む場合は、migration とSQLの両方で制約名・enum値・追加順が一致していることを確認する。

### 受け入れ要件

- 移行前後の件数が記録される。
- 不整合データが検知できる。
- Alembic migration と同内容のSQLファイルが作成されている。
- DB上で実行するSQLの手順が明文化されている。
- rollback手順がある。

## タスク 8: ローカル課金検証手順を固定する

優先度: 中

### 目的

Webhook未到達による誤判定を防ぐ。

### 実装箇所

- `md_files_design_note/task/bug_fix/stripe/`
- READMEまたは開発者向け手順書

### 手順に含める内容

- Stripe CLI の起動。

```bash
stripe listen --forward-to localhost:8000/api/v1/billing/webhook
```

- `whsec_...` を local backend の `STRIPE_WEBHOOK_SECRET` に設定する。
- backendコンテナを再作成する。
- `webhook_events` で `customer.subscription.created` と `invoice.payment_succeeded` を確認する。
- `billings` で `early_payment`、`stripe_subscription_id`、`last_payment_date` を確認する。

### 受け入れ要件

- ローカル検証で必要な起動コマンドと確認SQLが記載されている。
- Stripe CLI listener未起動時に `free` のまま残る理由が説明されている。

## 全体の完了条件

- trial中の課金成功は `early_payment` になる。
- trial終了後の課金成功は `active` になる。
- trial終了後の未課金は `trial_expired` になる。
- 支払い失敗は `payment_failed` として表現できる。
- `past_due` の責務が曖昧なまま新規実装に使われない。
- frontend の制限・警告表示が `past_due` 専用前提から脱却している。
- Webhookイベント順序が入れ替わっても最終状態が安定する。
- billing scheduler が正しく job 登録される。
- backend / frontend / migration / local検証手順が揃っている。
