# P1-P3 分割レビューと網羅率

作成日: 2026-07-01

対象:

- P1: `employee_action_service.py` の通知/承認フロー分離
- P2: `welfare_recipient_service.py` の期限アラート/整合性補正分離
- P3: `calendar_service.py` のGoogle副作用分離

参照:

- `md_files_design_note/task/todo/refactor/maintainability/maintainability_research.md`
- `k_back/app/services/employee_action_service.py`
- `k_back/app/services/approval/employee_action_notice_service.py`
- `k_back/app/services/welfare_recipient_service.py`
- `k_back/app/services/welfare_recipient/deadline_alert_service.py`
- `k_back/app/services/welfare_recipient/support_plan_integrity_service.py`
- `k_back/app/services/calendar_service.py`
- `k_back/app/services/calendar/calendar_event_ledger_service.py`
- `k_back/app/services/calendar/google_calendar_gateway.py`
- `k_back/app/services/calendar/google_calendar_sync_service.py`

## Findings

### 1. P3: `calendar_service.py` に到達不能な旧実装が残っている

重要度: Medium

`CalendarService` の facade 化は進んでいるが、委譲 `return` の後ろに旧実装が残っている。

該当箇所:

- `k_back/app/services/calendar_service.py:392` の `return await self.event_ledger_service.create_renewal_deadline_events(...)` 後に旧 `create_renewal_deadline_events` 実装が残存
- `k_back/app/services/calendar_service.py:526` の `return await self.event_ledger_service.create_next_plan_start_date_events(...)` 後に旧 `create_next_plan_start_date_events` 実装が残存
- `k_back/app/services/calendar_service.py:797` の `return await self.google_sync_service.sync_pending_events(...)` 後に旧 `sync_pending_events` 実装が残存
- `k_back/app/services/calendar_service.py:933` / `k_back/app/services/calendar_service.py:1004` の削除委譲後にも旧削除実装が残存

影響:

- 実行時バグには直結しにくいが、レビュー時に実際の責務境界を誤認しやすい。
- 旧実装内の import / CRUD / Google API 呼び出しが残るため、将来の修正で「どちらを直すべきか」が曖昧になる。
- 保守性改善タスクの目的である巨大ファイル縮小と責務分離が中途半端に見える。

推奨:

- `return` 後の旧実装を削除する。
- 削除後に `calendar_service.py` の未使用 import を整理する。
- `py_compile` だけでなく lint か static check で未使用 import / 到達不能コードを検出できる形にする。

### 2. P1: `EmployeeActionExecutor` 抽出は完了

重要度: Resolved

P1 の作業順序で残っていた「実処理実行は `EmployeeActionExecutor` へ抽出する」は完了した。

該当箇所:

- `k_back/app/services/approval/employee_action_executor.py`
- `k_back/app/services/employee_action_service.py`
- `k_back/tests/services/test_employee_action_executor.py`

対応内容:

- `EmployeeActionExecutor` を追加し、`welfare_recipient` / `support_plan_cycle` / `support_plan_status` の実行処理を移動。
- `EmployeeActionService` に `executor` 注入を追加し、`_execute_action()` は委譲だけに変更。
- `EmployeeActionService` 内の `_execute_welfare_recipient_action()` / `_execute_support_plan_cycle_action()` / `_execute_support_plan_status_action()` を削除。
- `employee_action_service.py` は `767行` から `349行` まで縮小。

確認:

- `tests/services/test_employee_action_executor.py` で executor 注入、委譲、既存placeholder、unsupported resource を固定。
- `tests/services/test_employee_action_executor.py tests/services/test_employee_action_notice_service.py tests/services/test_employee_action_service.py` は `25 passed, 4 skipped`。

### 3. 行カバレッジ測定ツールがコンテナにない

重要度: Low

`pytest-cov` / `coverage` が backend コンテナに入っていないため、行カバレッジは実測できなかった。

確認結果:

- `pytest --cov=...`: `unrecognized arguments: --cov=...`
- `python -c "import coverage"`: `ModuleNotFoundError: No module named 'coverage'`

影響:

- 今回は「作業項目ベース」「テストケースベース」の網羅率で代替した。
- 行単位・分岐単位の定量評価は未測定。

推奨:

- backend 開発コンテナに `pytest-cov` を入れる、または `coverage` を dev dependency として確実にインストールする。
- P1-P3 のレビューでは `--cov=app.services... --cov-report=term-missing` を標準コマンド化する。

### 4. P3 抽出先の直接テストは薄い

重要度: Low

`test_calendar_refactor_services.py` は `CalendarService` から `CalendarEventLedgerService` / `GoogleCalendarSyncService` への委譲を固定している。一方、抽出先サービス自体の内部分岐は既存 `test_calendar_service.py` 経由の間接確認が中心。

該当箇所:

- `k_back/tests/services/test_calendar_refactor_services.py:86`
- `k_back/tests/services/test_calendar_refactor_services.py:136`

影響:

- facade の委譲は固定されているが、抽出先を単独で変更した場合の失敗検出力は限定的。

推奨:

- `CalendarEventLedgerService` に対して、重複、カレンダー未設定、未接続、recipient/cycle/status欠落、正常作成を直接テストする。
- `GoogleCalendarSyncService` に対して、アカウント未設定、未接続、復号失敗、Google API失敗、削除失敗時のDB削除継続を直接テストする。

## 実装状況

| 優先度 | 作業項目 | 状態 | コメント |
|---|---:|---|---|
| P1 | employee action承認/却下時の通知文言・通知type・link_url・recipient固定 | 完了 | `test_employee_action_notice_service.py` と既存通知テストで固定 |
| P1 | 通知作成と古い通知削除を通知Serviceへ抽出 | 完了 | `EmployeeActionNoticeService` へ抽出済み |
| P1 | 実処理実行を `EmployeeActionExecutor` へ抽出 | 完了 | `EmployeeActionService._execute_action()` は executor 委譲のみ |
| P1 | 承認/却下差分を既存Serviceに明示 | 完了 | 承認/却下フローとトランザクション境界は既存Serviceに残存 |
| P2 | `get_deadline_alerts()` / batch のレスポンス固定 | 完了 | refactor serviceテストと既存batch/APIテストで確認 |
| P2 | 期限計算・分類を `DeadlineAlertService` へ抽出 | 完了 | facade委譲済み |
| P2 | 支援計画整合性補正を `SupportPlanIntegrityService` へ抽出 | 完了 | facade委譲済み |
| P2 | 利用者CRUD公開メソッドを既存Serviceに残す | 完了 | `WelfareRecipientService` が facade として残存 |
| P3 | credential/client/API失敗境界をテスト固定 | 完了 | `test_google_calendar_gateway.py` |
| P3 | Google client生成を `GoogleCalendarGateway` へ抽出 | 完了 | `GoogleCalendarGateway` 実装済み |
| P3 | DB台帳操作を `CalendarEventLedgerService` へ抽出 | 完了 | 実装済み。ただしメモ上は残タスクのまま |
| P3 | Google同期を `GoogleCalendarSyncService` へ隔離 | 完了 | 実装済み。ただし旧実装の到達不能コードが残存 |

## 網羅率

### 作業項目ベース

| 優先度 | 完了項目 | 総項目 | 網羅率 | 判定 |
|---|---:|---:|---:|---|
| P1 | 4 | 4 | 100% | 通知分離とexecutor抽出が完了 |
| P2 | 4 | 4 | 100% | 主要分割は完了 |
| P3 | 4 | 4 | 100% | 分割は完了。ただし旧実装削除が必要 |
| 合計 | 12 | 12 | 100% | P3 cleanupは別途品質改善として残る |

補足:

- P3 は実装上は `CalendarEventLedgerService` / `GoogleCalendarSyncService` まで抽出済み。
- `maintainability_research.md` のP3残タスクは現状とずれているため、メモ更新が必要。
- P1 は `EmployeeActionExecutor` 抽出完了により作業項目ベースでは完了。

### テスト実行ベース

実行コマンド:

```bash
docker exec keikakun_app-backend-1 python -m pytest \
  tests/services/test_employee_action_notice_service.py \
  tests/services/test_employee_action_service.py \
  tests/services/test_welfare_recipient_refactor_services.py \
  tests/services/test_welfare_recipient_service_batch.py \
  tests/services/test_support_plan_repair.py \
  tests/api/v1/test_deadline_alerts_overdue.py \
  tests/services/test_google_calendar_gateway.py \
  tests/services/test_calendar_service.py::TestCalendarService::test_sync_pending_events_success \
  tests/services/test_calendar_service.py::TestCalendarService::test_sync_pending_events_with_api_error \
  tests/services/test_calendar_service.py::TestEventDeletion::test_delete_renewal_event_by_cycle \
  tests/services/test_calendar_service.py::TestEventDeletion::test_delete_monitoring_event_by_status \
  -q
```

結果:

```text
44 passed, 4 skipped in 341.33s (0:05:41)
```

P3追加確認:

```bash
docker exec keikakun_app-backend-1 python -m pytest \
  tests/services/test_calendar_refactor_services.py \
  tests/services/test_google_calendar_gateway.py \
  -q
```

結果:

```text
7 passed in 9.17s
```

P1追加確認:

```bash
docker exec keikakun_app-backend-1 python -m pytest \
  tests/services/test_employee_action_executor.py \
  tests/services/test_employee_action_notice_service.py \
  tests/services/test_employee_action_service.py \
  -q
```

結果:

```text
25 passed, 4 skipped in 226.48s (0:03:46)
```

### 行カバレッジ

状態: 未測定

理由:

- backend コンテナに `pytest-cov` が入っていない。
- backend コンテナに `coverage` も入っていない。

代替評価:

- 作業項目ベース網羅率: 100%
- 対象テスト実行: pass
- 抽出先の存在/委譲テスト: P1/P2/P3 すべてあり

## ファイルサイズ変化の現状

| ファイル | 現在行数 | コメント |
|---|---:|---|
| `k_back/app/services/employee_action_service.py` | 349 | 承認/却下フローとトランザクション境界に縮小 |
| `k_back/app/services/approval/employee_action_executor.py` | 455 | employee action実処理責務 |
| `k_back/app/services/approval/employee_action_notice_service.py` | 248 | 通知責務として適正範囲 |
| `k_back/app/services/welfare_recipient_service.py` | 516 | P2で約1000行級から縮小 |
| `k_back/app/services/welfare_recipient/deadline_alert_service.py` | 244 | 期限アラート責務として適正範囲 |
| `k_back/app/services/welfare_recipient/support_plan_integrity_service.py` | 304 | 整合性補正責務として適正範囲 |
| `k_back/app/services/calendar_service.py` | 1006 | P3後も旧実装残存により大きい |
| `k_back/app/services/calendar/calendar_event_ledger_service.py` | 201 | 台帳責務として適正範囲 |
| `k_back/app/services/calendar/google_calendar_gateway.py` | 50 | 外部API境界として適正範囲 |
| `k_back/app/services/calendar/google_calendar_sync_service.py` | 193 | Google同期責務として適正範囲 |

## 結論

P1〜P3 の分割は作業項目ベースでは完了扱いでよい。P1は通知分離に加えて `EmployeeActionExecutor` 抽出まで完了し、`EmployeeActionService` は承認/却下フローとトランザクション境界に縮小した。P3は実装上は予定より進んでいるが、`calendar_service.py` の到達不能な旧実装削除は別途品質改善として残る。

次にやるべきこと:

1. `calendar_service.py` の `return` 後に残る旧実装を削除する。
2. `maintainability_research.md` のP3残タスクを現状に合わせて更新する。
3. backend コンテナに coverage 測定ツールを入れて、行カバレッジを再測定する。
