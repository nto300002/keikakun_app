# DB/API側パフォーマンス修正リスト

作成日: 2026-06-30

## 目的

ログイン直後、通知、期限アラート、Dashboard表示でDBアクセスが増える箇所を、DB/API側で段階的に軽量化する。

## 優先度高

- [x] 期限アラートAPIで全件取得後のPythonページングをやめ、DB側で `LIMIT / OFFSET` を適用する。
  - `WelfareRecipientService.get_deadline_alerts()` で count と取得クエリを分け、`limit / offset` をSQLへ適用済み。
- [x] アセスメント未完了判定を `selectinload` + Python判定から、`NOT EXISTS` ベースに寄せる。
  - 単体経路 `get_deadline_alerts()` とバッチ経路 `get_deadline_alerts_batch()` の両方で対応済み。
- [x] `/notices/unread-count` を全件取得 + `len()` から `COUNT(*)` に変更する。
  - `crud_notice.count_unread_by_staff_id()` をAPIから利用済み。
- [x] 通知一覧APIにDB側ページングを適用する。
  - `crud_notice.get_list_by_staff_id()` / `count_by_staff_id()` をAPIから利用済み。

## 優先度中

- [x] `notices(recipient_staff_id, is_read, created_at DESC)` の複合インデックスを追加する。
  - 手動適用用SQLと同等内容のAlembic migrationを作成済み。
- [x] `notices(recipient_staff_id, created_at DESC)` の複合インデックスを追加する。
  - 手動適用用SQLと同等内容のAlembic migrationを作成済み。
- [x] `support_plan_cycles(office_id, is_latest_cycle, next_renewal_deadline)` のインデックスを検討する。
  - 期限アラートAPIの条件に合わせて作成対象に含めた。
- [x] `plan_deliverables(plan_cycle_id, deliverable_type)` のインデックスを検討する。
  - アセスメント未完了判定の `NOT EXISTS` に合わせて作成対象に含めた。

## 優先度低

- [ ] Dashboard APIのcount/list二重クエリを計測し、初期表示でcountを省略できるか判断する。
- [ ] `get_current_user()` のOffice eager loadが必要なAPIと不要なAPIを分ける。
- [ ] 本番相当DBで `EXPLAIN ANALYZE` を取得し、インデックス追加前後の差分を記録する。

## 受け入れ要件

- [x] 期限アラートAPIは `limit` 指定時にDB取得件数も制限される。
  - `tests/services/test_welfare_recipient_service_batch.py::test_get_deadline_alerts_applies_limit_offset_in_sql` で確認。
- [x] 未読件数APIは未読通知の全行をロードしない。
  - `tests/api/v1/test_notices.py::test_get_unread_count_uses_count_query_without_loading_rows` で確認。
- [x] 通知一覧APIはDB側で `ORDER BY / OFFSET / LIMIT` を適用する。
  - `tests/api/v1/test_notices.py::test_get_notices_uses_db_pagination_without_loading_all_rows` で確認。
- [x] Alembic migrationと必要に応じた確認SQLの適用手順が明記されている。
  - 本アプリでは今後のDB変更はAlembic migrationを正とする。
  - 手動SQLは確認用、調査用、緊急対応用に限定し、手動SQLだけでDB変更を完了扱いにしない。
  - SQL: `md_files_design_note/task/todo/refactor/performance/db_optimization_indexes.sql`
  - baseline: `k_back/migrations/versions/baseline_20260701_current_schema.py`
  - baseline確認: `md_files_design_note/task/todo/refactor/maintainability/alembic/alembic_baseline_check_20260701.md`
  - 補足: 既存migration履歴と実DBが大きく乖離していたため、個別のperformance index migrationを正とするのではなく、現在DB状態を `baseline_20260701` で固定し、baseline以後のDB変更をAlembic管理する方針に変更した。

## 今回のTDD確認

- [x] 期限アラート単体経路で `SupportPlanCycle.deliverables` を eager load しない。
  - `tests/services/test_welfare_recipient_service_batch.py::test_get_deadline_alerts_does_not_eager_load_deliverables_for_assessment_alerts`
- [x] 期限アラートバッチ経路で `SupportPlanCycle.deliverables` を eager load しない。
  - `tests/services/test_welfare_recipient_service_batch.py::test_get_deadline_alerts_batch_does_not_eager_load_deliverables_for_assessment_alerts`
