# パフォーマンス改善チェックリスト実装レビュー

作成日: 2026-06-30

## レビュー対象

- `md_files_design_note/task/todo/refactor/performance/performance.md`
- `md_files_design_note/task/todo/refactor/performance/app_fix_list.md`
- `md_files_design_note/task/todo/refactor/performance/db_fix_list.md`
- `md_files_design_note/task/todo/refactor/performance/db_optimization_indexes.sql`
- `k_front` の認証画面、保護レイアウト、Dashboard周辺
- `k_back` の通知API、通知CRUD、MFA/ログインログ、期限アラート周辺

## 総評

低リスクで先行できる改善は概ね実装済み。特にログイン直後の非必須通知処理の遅延、認証中UI、通知APIのCOUNT化/DBページング化、通知保持削除の一括化はチェックリストと実装が一致している。

一方で、ログイン/MFA後の `getCurrentUser()` 重複、Dashboard初期表示の3 API並列、PDF一覧、Google Calendar同期、CSRF初期化の削減は未対応。これらは仕様や画面状態管理への影響が大きいため、計測を取ってから段階的に進めるのが妥当。

## アプリ側チェックリストレビュー

### 実装済み

- [x] ログイン、MFA認証、サインアップの送信ボタン内に処理中表示を出す。
  - 実装確認:
    - `k_front/components/auth/LoginForm.tsx`
    - `k_front/app/auth/mfa-verify/page.tsx`
    - `k_front/components/auth/SignupForm.tsx`
    - `k_front/components/auth/admin/SignupForm.tsx`
  - `isLoading` 中にスピナーと処理中文言を表示し、既存の `disabled` により二重送信も抑制されている。

- [x] 認証処理が5秒以上続く場合、通信状況確認と更新を促す文言を出す。
  - 実装確認:
    - `k_front/hooks/useSlowLoadingMessage.ts`
  - 認証系フォームから共通hookを利用している。

- [x] 保護レイアウトの通知設定取得、期限通知、Push購読を初期描画後に遅延する。
  - 実装確認:
    - `k_front/components/protected/LayoutClient.tsx`
  - `window.setTimeout(..., 1200)` で初期描画後に `initializeNotifications()` を実行している。

- [x] 保護レイアウトの未読件数取得を初期描画後に遅延し、初期表示APIとの競合を減らす。
  - 実装確認:
    - `k_front/components/protected/LayoutClient.tsx`
  - 初回取得と30秒interval開始を遅延している。

### 未対応

- [ ] ログイン/MFA成功後の `getCurrentUser()` 追加取得を削減する。
  - 現状確認:
    - `k_front/components/auth/LoginForm.tsx` でログイン成功後に `authApi.getCurrentUser()` が残っている。
    - `k_front/app/auth/mfa-verify/page.tsx` でMFA成功後に `authApi.getCurrentUser()` が残っている。
  - コメント:
    - 認証レスポンスの契約変更が必要になるため、backend/frontend双方のテストを伴う別タスクが妥当。

- [ ] Dashboard初期表示で `authApi.getCurrentUser()` / `dashboardApi.getDashboardData()` / `billingApi.getBillingStatus()` の重複認証依存を減らす。
  - 現状確認:
    - `k_front/components/protected/dashboard/Dashboard.tsx` で3 API並列取得が残っている。
  - コメント:
    - Dashboard APIのレスポンス設計、BillingContextとの責務整理が必要。

- [ ] Dashboardの `filtered_count` が初期表示に必須か見直す。
  - 現状確認:
    - Dashboard API/CRUDのcount/list二重クエリ見直しは未完了。

- [ ] 実環境でログイン/MFA後の体感時間が改善したか確認する。
  - 現状確認:
    - ローカルの lint/build とbackendテストは通過済みだが、本番相当Network waterfallは未取得。

## DB/API側チェックリストレビュー

### 実装済み

- [x] `/notices/unread-count` を全件取得 + `len()` から `COUNT(*)` に変更する。
  - 実装確認:
    - `k_back/app/api/v1/endpoints/notices.py`
    - `k_back/app/crud/crud_notice.py`
  - `crud_notice.count_unread_by_staff_id()` が追加され、APIから利用されている。
  - 再発防止テスト:
    - `tests/api/v1/test_notices.py::test_get_unread_count_uses_count_query_without_loading_rows`

- [x] 通知一覧APIにDB側ページングを適用する。
  - 実装確認:
    - `crud_notice.get_list_by_staff_id()` が `ORDER BY / OFFSET / LIMIT` をDBクエリに適用している。
    - `crud_notice.count_by_staff_id()` により総件数もCOUNTで取得している。
  - 再発防止テスト:
    - `tests/api/v1/test_notices.py::test_get_notices_uses_db_pagination_without_loading_all_rows`

- [x] 通知の保持上限削除を全件取得 + 1件ずつdeleteからDB側一括削除へ変更する。
  - 実装確認:
    - `k_back/app/crud/crud_notice.py`
  - 削除対象IDのみを `OFFSET limit` 以降で取得し、`DELETE ... WHERE id IN (...)` で一括削除している。
  - 再発防止テスト:
    - `tests/crud/test_crud_notice.py::test_delete_old_notices_over_limit_uses_bulk_delete`

- [x] MFA/ログイン処理の成功パス詳細ログを削減する。
  - 実装確認:
    - `k_back/app/api/v1/endpoints/auths.py`
    - `k_back/app/services/mfa.py`
    - `k_back/app/models/staff.py`
  - TOTPコード、secret長、メールアドレスに近い情報の `info` ログ出力を削除/`debug` 化している。

### 対応済み

- [x] 期限アラートAPIで全件取得後のPythonページングをやめ、DB側で `LIMIT / OFFSET` を適用する。
  - 実装確認:
    - `k_back/app/services/welfare_recipient_service.py`
    - `tests/services/test_welfare_recipient_service_batch.py`
  - `get_deadline_alerts()` は `LIMIT / OFFSET` をSQLへ押し込むテストが追加されている。
  - `get_deadline_alerts_batch()` も成果物一覧の eager load を使わない形に修正済み。

- [x] アセスメント未完了判定を `selectinload` + Python判定から、`NOT EXISTS` ベースに寄せる。
  - 実装確認:
    - `get_deadline_alerts()` では `exists` ベースの条件が使われている。
    - `get_deadline_alerts_batch()` でも `NOT EXISTS` 条件に寄せている。
  - テスト:
    - `test_get_deadline_alerts_does_not_eager_load_deliverables_for_assessment_alerts`
    - `test_get_deadline_alerts_batch_does_not_eager_load_deliverables_for_assessment_alerts`

- [x] Alembic migrationと必要に応じた確認SQLの適用手順が明記されている。
  - 実装確認:
    - `db_optimization_indexes.sql`
    - `k_back/migrations/versions/baseline_20260701_current_schema.py`
    - `md_files_design_note/task/todo/refactor/maintainability/alembic/alembic_baseline_check_20260701.md`
  - 運用前提:
    - 本アプリでは今後のDB変更はAlembic migrationを正とする。
    - 手動SQLは確認用、調査用、緊急対応用に限定する。
    - 既存migrationと実DBが大きく乖離していたため、個別のperformance index migrationを正とせず、新baseline `baseline_20260701` 以後をAlembic管理対象とする。

### 未対応

- [ ] Dashboard APIのcount/list二重クエリを軽量化する。
- [ ] `get_current_user()` のOffice eager loadが必要なAPIと不要なAPIを分ける。
- [ ] PDF一覧APIの署名付きURL生成タイミングと件数取得を見直す。
- [ ] Dashboard検索の `ILIKE '%word%'` / `concat()` 依存を見直す。
- [ ] Google Calendar同期/削除系の外部API逐次処理をバックグラウンド化する。
- [ ] CSRF初期化APIをログイン直後の必須APIから外せるか検討する。

## インデックス/DB適用レビュー

### 実装・手順あり

- `notices(recipient_staff_id, is_read, created_at DESC)`
- `notices(recipient_staff_id, created_at DESC)`
- `notices(office_id, created_at DESC)`
- `support_plan_cycles(office_id, is_latest_cycle, next_renewal_deadline)`
- `support_plan_cycles(welfare_recipient_id, office_id, is_latest_cycle)`
- `plan_deliverables(plan_cycle_id, deliverable_type)`
- `support_plan_statuses(office_id, is_latest_status, step_type)`

### 注意点

- 今後のDB変更の正はAlembic migrationとする。
- 手動SQLは確認用、調査用、緊急対応用に限定し、手動SQLだけでDB変更を完了扱いにしない。
- `CREATE INDEX CONCURRENTLY` はトランザクション内で実行できないため、Alembicで扱う場合は専用migrationまたは個別手順として明記する。
- 本番適用前に `EXPLAIN (ANALYZE, BUFFERS)` を取得し、不要なインデックス追加になっていないか確認する。
- NeonDBを共通利用している前提では、対象DB、実行日時、revision、確認SQL、rollback/復旧手順をPRまたはタスクmdに記録する。

## 確認済みテスト

- `docker exec keikakun_app-backend-1 pytest tests/api/v1/test_notices.py::test_get_unread_count_uses_count_query_without_loading_rows tests/api/v1/test_notices.py::test_get_notices_uses_db_pagination_without_loading_all_rows tests/crud/test_crud_notice.py::test_delete_old_notices_over_limit_uses_bulk_delete`
  - 3 passed
- `docker exec keikakun_app-backend-1 pytest tests/api/v1/test_notices.py tests/crud/test_crud_notice.py`
  - 26 passed
- `docker exec keikakun_app-backend-1 pytest tests/api/v1/test_mfa_api.py tests/api/v1/test_mfa_verify_error_handling.py`
  - 23 passed
- `docker exec keikakun_app-backend-1 pytest tests/services/test_welfare_recipient_service_batch.py`
  - 9 passed
- `docker exec keikakun_app-backend-1 pytest tests/services/test_welfare_recipient_service_batch.py tests/api/v1/test_deadline_alerts.py tests/api/v1/test_notices.py::test_get_unread_count_uses_count_query_without_loading_rows tests/api/v1/test_notices.py::test_get_notices_uses_db_pagination_without_loading_all_rows tests/crud/test_crud_notice.py::test_delete_old_notices_over_limit_uses_bulk_delete`
  - 18 passed
- `k_front npm run lint`
  - passed
- `k_front npm run build`
  - passed

## レビュー上の指摘

### High

- なし。

### Medium

- 本番相当DBで通知一覧、未読COUNT、期限アラートの `EXPLAIN ANALYZE` は未取得。
  - SQLと実装は揃っているが、実データ量での効果確認は別途必要。

- Dashboard API、`get_current_user()`、PDF一覧、Google Calendar同期、CSRF初期化は仕様判断が必要。
  - 性能面の候補ではあるが、レスポンス契約やUX、外部API処理に影響するため、このPRで即時修正する対象からは外す。

### Low

- `useSlowLoadingMessage()` は `isLoading` 変化時に0ms timerで状態リセットしている。
  - lint回避としては成立しているが、hookの意図が少し読み取りづらい。
  - 将来、React lint方針が変わる場合はより単純な実装に戻せるか再確認するとよい。

## 次に進める場合の優先度

1. 本番相当DBで通知一覧、未読COUNT、期限アラートの `EXPLAIN ANALYZE` を取得する。
2. ログイン/MFA後の `getCurrentUser()` 重複削減を、認証レスポンス契約変更タスクとして切り出す。
3. Dashboard APIの `filtered_count` とBilling取得を初期表示で必須にするか判断する。
4. PDF一覧APIの署名付きURL生成タイミングをUX要件込みで判断する。
5. Google Calendar同期/削除系をバックグラウンド化するか、将来的な廃止方針と合わせて判断する。
