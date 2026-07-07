# パフォーマンス以外の保守性課題リサーチ

作成日: 2026-06-30

## 目的

パフォーマンス改善とは別に、今後の不具合修正や仕様変更で破綻しやすい実装箇所を洗い出す。ここでは速度ではなく、責務分離、重複、テスト容易性、ログ/設定管理、外部API副作用、巨大ファイル化を主な観点にする。

## 調査対象

- `k_back/app`
- `k_front/app`
- `k_front/components`
- `k_front/lib`
- 既存の `md_files_design_note/task/todo/refactor`

## 総評

現状の最大課題は、機能追加を急いだ結果として、画面・API・Serviceが大きくなり、境界が曖昧になっていること。特に認証、利用者/支援計画、申請/通知、Google Calendar、課金は仕様変更が多く、責務が混ざるほど回帰リスクが高い。

一方で、全体を一気に作り替える必要はない。まずは「重複を共通化する」「副作用を境界に閉じ込める」「巨大ファイルを小さな責務に分割する」「debugログを運用可能な形に整理する」順で進めるのが保守的。

## 現在ステータス

2026-07-02時点の整理。実装済み項目の古い未完了チェックは、各セクションの実施結果を正とする。

### PR化ステータス

2026-07-02時点で、実装済みの保守性リファクタはレビューしやすい粒度に分けてPR化した。

- Backend PR: https://github.com/nto300002/keikakun_back/pull/73
  - 対象: P0 認証Cookie共通化、P0/P6 課金状態遷移分離、P1 employee action承認通知/実行分離、P2 welfare recipient期限/整合性分離、P3 Calendar副作用分離。
  - 粒度: auth / billing / approval / welfare recipient / calendar をコミット単位で分割。
  - 未混入: DB/Alembic、権限deps、admin audit logなど別テーマの未コミット差分。
- Frontend PR: https://github.com/nto300002/keikakun_front/pull/62
  - 対象: P4 Dashboard hook/permission分離、P5 recipient form共通化、P6 AdminMenu tab表示分離。
  - 粒度: Dashboard / recipient form / AdminMenu をコミット単位で分割。
  - 未混入: 通知UI、app-admin表示調整、フィードバック導線など別要望の未コミット差分。

| No | 項目 | 現状 | 残り |
| --- | --- | --- | --- |
| 1 | 認証Cookie設定 | 完了 | なし |
| 2 | 巨大Service/Component | 部分完了 | P4はDashboard table抽出、P6はGoogle/MFA/事業所編集hook抽出が残る |
| 3 | Application通知 | 部分完了 | role change側の通知共通化と監査ログ共通化 |
| 4 | ログ削除 | 部分完了 | ログ方針md追加済み。残る `console.error/warn` は方針に沿って個別判断 |
| 5 | Google Calendar | 仕様判断待ち | アプリ内カレンダー / `.ics` / Google縮退は別issueで扱う |
| 6 | 課金状態遷移 | backend共通化完了 | frontend/backend状態マッピングの継続照合 |
| 7 | Frontend API/state | Dashboardは進捗あり | Dashboard table抽出、他画面のhook化 |
| 8 | get_current_user | 完了寄り | endpoint大量移行は既存override影響を見ながら別途判断 |
| 9 | TODO/仮実装 | md化完了 | 実装対応は別issue |
| 10 | DB/Alembic | 方針とCD案は整理済み | main DB確認、ログ確認、破壊的migration運用のPR明記 |

## 優先度高

### 1. 認証Cookie設定処理が複数箇所に重複している

該当箇所:

- `k_back/app/api/v1/endpoints/auths.py`

確認内容:

- `login_for_access_token`
- `refresh_access_token`
- `verify_mfa_for_login`
- `verify_mfa_first_time`
- `logout`

上記で `COOKIE_DOMAIN` / `COOKIE_SAMESITE` / `secure` / `samesite` / `path` / `max_age` の組み立てが分散している。

リスク:

- 本番/ローカル/サンドボックスでCookie挙動がずれやすい。
- SameSiteやsecureの修正時に、片方だけ直して片方が残る可能性が高い。
- MFA・通常ログイン・refreshで認証維持の挙動差が生まれやすい。

推奨リファクタ:

- `app/core/auth_cookie.py` などに `build_access_cookie_options()` / `build_delete_access_cookie_options()` を作る。
- endpointでは `response.set_cookie(**options)` だけにする。
- 先に既存挙動固定のテストを追加する。

受け入れ要件:

- [x] 通常ログイン/MFA/初回MFA/refresh/logoutでCookie option生成が共通関数を通る。
  - `k_back/app/core/auth_cookie.py` に `build_access_cookie_options()` / `build_delete_access_cookie_options()` を追加。
  - `login_for_access_token` / `refresh_access_token` / `verify_mfa_for_login` / `verify_mfa_first_time` / `logout` は共通関数呼び出しに統一。
- [x] production/localそれぞれの `secure` / `samesite` / `domain` のテストがある。
  - `k_back/tests/core/test_auth_cookie.py` で local default、production default、domain/samesite env、invalid env、logout delete scope を固定。
- [x] endpoint側にCookie option組み立てロジックが残らない。
  - `auths.py` 内に `COOKIE_DOMAIN` / `COOKIE_SAMESITE` / `cookie_options` / `delete_cookie_options` が戻らないことをテストで固定。

実施結果:

- RED: `tests/core/test_auth_cookie.py` 追加直後、`ModuleNotFoundError: No module named 'app.core.auth_cookie'` を確認。
- GREEN: `app/core/auth_cookie.py` を追加し、`auths.py` のCookie option組み立てを共通関数へ移動。
- 確認:
  - `docker exec keikakun_app-backend-1 pytest tests/core/test_auth_cookie.py tests/api/v1/test_auth.py::TestCookieAuthentication -q`
    - `19 passed`
  - `docker exec keikakun_app-backend-1 pytest tests/api/v1/test_mfa_api.py::TestMFALogin tests/api/v1/test_mfa_verify_error_handling.py::TestMFALoginVerifyErrorHandling -q`
    - `7 passed`
  - `docker exec keikakun_app-backend-1 pytest tests/api/v1/test_auth.py tests/core/test_auth_cookie.py -q`
    - `51 passed`

### 2. 巨大Service/Componentが多く、単体変更の影響範囲が広い

該当箇所:

- `k_back/app/services/billing_service.py` 約1100行
- `k_back/app/services/employee_action_service.py` 約1060行
- `k_back/app/services/welfare_recipient_service.py` 約1030行
- `k_back/app/services/calendar_service.py` 約990行
- `k_front/components/protected/admin/AdminMenu.tsx` 約1500行
- `k_front/components/protected/dashboard/Dashboard.tsx` 約1160行
- `k_front/components/protected/recipients/RecipientRegistrationForm.tsx` 約1140行
- `k_front/components/protected/recipients/RecipientEditForm.tsx` 約1120行

リスク:

- 仕様変更時に、関係ない処理まで読み込む必要がある。
- テスト対象が大きくなり、TDDで小さくRed/Greenしづらい。
- UIでは表示、状態管理、API呼び出し、権限制御、変換処理が混ざりやすい。
- backendではDB更新、通知、外部API、監査ログ、権限判定が同じServiceに集まりやすい。

推奨リファクタ:

- ファイル分割を目的にせず、まず責務境界ごとに抽出する。
- backendは「判定」「DB更新」「通知作成」「外部API呼び出し」を分ける。
- frontendは「コンテナ」「表示コンポーネント」「フォーム状態」「API adapter」を分ける。
- 既存UI/レスポンスを変えず、テストを書ける単位から抽出する。

受け入れ要件:

- [x] 1000行超のファイルについて、分割単位と優先順位が決まっている。
- [ ] 抽出後も既存の公開API/画面表示は変わらない。
- [ ] 主要分岐に単体テストまたはコンポーネントテストがある。

### 2.1 現状行数と混在責務

2026-07-01時点の確認:

Backend:

- `k_back/app/services/billing_service.py`: 1104行
  - Checkout Session作成
  - Stripe Customer作成
  - Stripe Webhook処理
  - 課金状態遷移
  - trial期限補正
  - webhook event記録
  - ログ整形
- `k_back/app/services/employee_action_service.py`: 1064行
  - 申請作成
  - 承認/却下
  - 実処理実行
  - 通知作成
  - 古い通知削除
  - 支援計画/利用者/成果物ごとの個別処理
- `k_back/app/services/welfare_recipient_service.py`: 1004行
  - 利用者CRUD
  - 支援計画整合性チェック/補正
  - 期限アラート
  - バッチ取得
  - Google Calendar連携起点
- `k_back/app/services/calendar_service.py`: 996行
  - Google credential復号
  - Google client作成
  - 接続テスト
  - イベント作成/削除/同期
  - DB上のcalendar event管理

Frontend:

- `k_front/components/protected/admin/AdminMenu.tsx`: 1526行
  - 管理者設定タブ
  - Google Calendar設定
  - スタッフ一覧/MFA個別操作/MFA一括操作
  - 事業所情報編集
  - 退会導線
  - 各種modal表示状態
- `k_front/components/protected/dashboard/Dashboard.tsx`: 1165行
  - 初期データ取得
  - 課金制限表示
  - 検索/ソート/フィルタ
  - URL query/toast処理
  - 利用者削除
  - ダッシュボード一覧描画
- `k_front/components/protected/recipients/RecipientRegistrationForm.tsx`: 1142行
  - form初期値
  - section validation
  - 入力状態
  - API submit
  - employee時の申請modal
  - 全section描画
- `k_front/components/protected/recipients/RecipientEditForm.tsx`: 1120行
  - initialData変換
  - section validation
  - 入力状態
  - API submit
  - employee時の申請modal
  - 全section描画

### 2.2 作業順序と優先度

優先順位は「変更頻度」「障害時の影響」「既存テストで固定しやすいか」「他タスクとの依存」を基準にする。

#### P0: `billing_service.py` の状態遷移/Stripe副作用分離

理由:

- 課金状態は利用制限、Checkout、Webhook、バッチに波及する。
- 直近で `trial_expired` / `payment_failed` / `canceling` / `canceled` の変更が多く、回帰リスクが最も高い。
- 既に service/API テストが比較的あり、TDDで現行挙動を固定しやすい。
- 優先度中の「課金状態遷移の責務分散」解消にも直結する。

作業順序:

1. `process_subscription_updated` / `process_subscription_deleted` / `process_payment_failed` の現行状態遷移をテストで固定する。
2. 純粋判定に近い関数を `BillingStatusTransitionService` へ抽出する。
3. Stripe API呼び出しを `StripeCheckoutSessionService` または `StripeBillingGateway` へ抽出する。
4. `billing_service.py` は既存公開メソッドを残す facade として扱い、API層の呼び出し口は変えない。

#### P1: `employee_action_service.py` の通知/承認フロー分離

理由:

- role change と employee action で通知・承認・却下の重複がある。
- 優先度高の「申請系Serviceで通知作成・承認/却下フローが重複」に直結する。
- 通知文言・通知種別・保持上限削除を一箇所に寄せると、仕様変更時の二重修正を減らせる。

作業順序:

1. employee action承認/却下時の通知文言・通知type・link_url・recipientをテストで固定する。
2. 通知作成と古い通知削除を `ApprovalNoticeService` へ抽出する。
3. 実処理実行は `EmployeeActionExecutor` へ抽出する。
4. 承認/却下の差分は `employee_action_service.py` に明示的に残す。

実施結果:

- [x] `k_back/tests/services/test_employee_action_notice_service.py` を追加し、通知詳細文言生成と `EmployeeActionService` への通知サービス注入を単体テストで固定した。
- [x] RED確認:
  - `docker exec keikakun_app-backend-1 pytest tests/services/test_employee_action_notice_service.py -q`
  - 結果: `ModuleNotFoundError: No module named 'app.services.approval'`
- [x] `k_back/app/services/approval/employee_action_notice_service.py` を追加し、employee action の通知作成、承認/却下通知、承認者取得、保持上限削除を `EmployeeActionNoticeService` に抽出した。
- [x] `k_back/app/services/employee_action_service.py` は申請作成、承認/却下、実処理実行、トランザクション境界を維持し、通知処理だけを `notice_service` へ委譲した。
- [x] 通知作成は `auto_commit=False` に統一し、既存コメントどおり親Serviceで最後に1回だけcommitする形へ寄せた。
- [x] 既存テストで使われていた `full_name` のみの作成リクエストも姓・名へ分解して実行できるように補正した。
- [x] `k_back/app/services/approval/employee_action_executor.py` を追加し、承認後の実処理実行を `EmployeeActionExecutor` へ抽出した。
  - `welfare_recipient` の create/update/delete、`support_plan_cycle` の既存placeholder、`support_plan_status` の成果物確認処理を移動。
  - `EmployeeActionService` は `executor` を注入可能にし、`_execute_action()` は executor への委譲だけを行う構成に変更。
  - `EmployeeActionService` 内に残っていた `_execute_welfare_recipient_action()` / `_execute_support_plan_cycle_action()` / `_execute_support_plan_status_action()` は削除。
  - 行数は `767行` から `349行` まで縮小。
- [x] GREEN確認:
  - `docker exec keikakun_app-backend-1 pytest tests/services/test_employee_action_notice_service.py -q`
    - `3 passed`
  - `docker exec keikakun_app-backend-1 pytest tests/services/test_employee_action_notice_service.py tests/services/test_employee_action_service.py::test_create_employee_action_request_creates_notification tests/services/test_employee_action_service.py::test_approve_employee_action_request_creates_notification tests/services/test_employee_action_service.py::test_reject_employee_action_request_creates_notification tests/services/test_employee_action_service.py::test_create_request_sends_notification_to_requester tests/services/test_employee_action_service.py::test_create_request_sends_notifications_to_both_requester_and_approvers tests/services/test_employee_action_service.py::test_approve_request_updates_requester_notification_type tests/services/test_employee_action_service.py::test_reject_request_updates_requester_notification_type -q`
    - `10 passed`
  - `docker exec keikakun_app-backend-1 pytest tests/services/test_employee_action_service.py -q`
    - `18 passed, 4 skipped`
  - `docker exec keikakun_app-backend-1 python -m py_compile app/services/approval/employee_action_notice_service.py app/services/employee_action_service.py`
    - 成功
- [x] P1残タスク GREEN確認:
  - `docker exec keikakun_app-backend-1 python -m pytest tests/services/test_employee_action_executor.py -q`
    - `4 passed`
  - `docker exec keikakun_app-backend-1 python -m pytest tests/services/test_employee_action_executor.py tests/services/test_employee_action_notice_service.py tests/services/test_employee_action_service.py -q`
    - `25 passed, 4 skipped`
  - `docker exec keikakun_app-backend-1 python -m py_compile app/services/approval/employee_action_executor.py app/services/employee_action_service.py`
    - 成功

#### P2: `welfare_recipient_service.py` の期限アラート/整合性補正分離

理由:

- 利用者CRUD、支援計画補正、期限アラート、Google Calendar連携起点が同居している。
- 期限アラートはperformanceタスクとも関係し、軽量化・テストの影響が大きい。
- Google Calendar縮退方針に向けて、期限イベント生成と外部同期を分ける前段になる。

作業順序:

1. `get_deadline_alerts()` / `get_deadline_alerts_batch()` のレスポンス形をテストで固定する。
2. 期限計算・期限分類を `DeadlineAlertService` へ抽出する。
3. 支援計画整合性チェック/補正を `SupportPlanIntegrityService` へ抽出する。
4. 利用者CRUDの公開メソッドは既存Serviceに残す。

実施結果:

- [x] `k_back/tests/services/test_welfare_recipient_refactor_services.py` を追加し、P2抽出先サービスの存在と `WelfareRecipientService` からの委譲を固定した。
- [x] RED確認:
  - `docker exec keikakun_app-backend-1 pytest tests/services/test_welfare_recipient_refactor_services.py -q`
  - 結果: `ModuleNotFoundError: No module named 'app.services.welfare_recipient'`
- [x] `k_back/app/services/welfare_recipient/deadline_alert_service.py` を追加し、`get_deadline_alerts()` / `get_deadline_alerts_batch()` の期限アラート取得、期限分類、レスポンス整形を `DeadlineAlertService` に抽出した。
- [x] `k_back/app/services/welfare_recipient/support_plan_integrity_service.py` を追加し、支援計画整合性チェック、同期/非同期修復、不足ステータス補完を `SupportPlanIntegrityService` に抽出した。
- [x] `k_back/app/services/welfare_recipient_service.py` は利用者CRUD/削除などの公開入口を残し、期限アラートと支援計画整合性処理を抽出先へ委譲するfacadeにした。
  - 行数は `1004行` から `516行` まで縮小。
  - 既存テストがpatchしている `_repair_missing_statuses_async` は互換メソッドとして残した。
- [x] 同期修復側に残っていた古いフィールド名を現行モデルの `plan_cycle_id` / `step_type` に合わせた。
- [x] GREEN確認:
  - `docker exec keikakun_app-backend-1 pytest tests/services/test_welfare_recipient_refactor_services.py -q`
    - `4 passed`
  - `docker exec keikakun_app-backend-1 pytest tests/services/test_welfare_recipient_service_batch.py tests/services/test_support_plan_repair.py -q`
    - `9 passed`
  - `docker exec keikakun_app-backend-1 pytest tests/api/v1/test_deadline_alerts_overdue.py -q`
    - `2 passed`
  - `docker exec keikakun_app-backend-1 pytest tests/services/test_welfare_recipient_refactor_services.py tests/services/test_welfare_recipient_service_batch.py tests/services/test_support_plan_repair.py tests/api/v1/test_deadline_alerts_overdue.py -q`
    - `15 passed`
  - `docker exec keikakun_app-backend-1 python -m py_compile app/services/welfare_recipient/deadline_alert_service.py app/services/welfare_recipient/support_plan_integrity_service.py app/services/welfare_recipient_service.py`
    - 成功

#### P3: `calendar_service.py` のGoogle副作用分離

理由:

- Google Calendarは将来的な縮退/廃止も視野に入っているため、分割は「延命」ではなく「外部副作用を隔離する」目的で行う。
- 本体の支援計画作成/削除がGoogle API成功に依存しない設計へ寄せる準備になる。

作業順序:

1. credential復号、client生成、API呼び出し失敗時の戻り値をテストで固定する。
2. Google client生成を `GoogleCalendarGateway` へ抽出する。
3. DB上の期限イベント台帳操作を `CalendarEventLedgerService` へ抽出する。
4. Google同期は互換機能として `GoogleCalendarSyncService` に隔離する。

実施結果:

- [x] `k_back/tests/services/test_google_calendar_gateway.py` を追加し、Google副作用境界を単体テスト化した。
  - credential文字列からclientを生成し、`authenticate()` を呼んで返す。
  - 認証失敗は握りつぶさず `GoogleCalendarAuthenticationError` として呼び出し元へ伝える。
  - `create_event()` は認証済みclientへイベント作成を委譲する。
  - `delete_event()` は認証済みclientへイベント削除を委譲する。
- [x] RED確認:
  - `docker exec keikakun_app-backend-1 pytest tests/services/test_google_calendar_gateway.py -q`
  - 結果: `ModuleNotFoundError: No module named 'app.services.calendar'`
- [x] `k_back/app/services/calendar/google_calendar_gateway.py` を追加し、`GoogleCalendarGateway` にclient生成・認証・Google API呼び出し委譲を抽出した。
- [x] `k_back/app/services/calendar_service.py` のGoogle API直接呼び出しをGateway経由へ変更した。
  - `test_calendar_connection()` の接続確認イベント作成/削除
  - `sync_pending_events()` の未同期イベント作成
  - `delete_event_by_cycle()` / `delete_event_by_status()` のGoogle側イベント削除
- [x] `delete_event_by_cycle()` / `delete_event_by_status()` に残っていた未定義の `google_calendar_client` 参照を解消した。
- [x] GREEN確認:
  - `docker exec keikakun_app-backend-1 pytest tests/services/test_google_calendar_gateway.py -q`
    - `4 passed`
  - `docker exec keikakun_app-backend-1 pytest tests/services/test_calendar_service.py::TestCalendarService::test_sync_pending_events_success tests/services/test_calendar_service.py::TestCalendarService::test_sync_pending_events_with_api_error tests/services/test_calendar_service.py::TestEventDeletion::test_delete_renewal_event_by_cycle tests/services/test_calendar_service.py::TestEventDeletion::test_delete_monitoring_event_by_status -q`
    - `4 passed, 1 warning`
  - `docker exec keikakun_app-backend-1 python -m py_compile app/services/calendar/google_calendar_gateway.py app/services/calendar_service.py`
    - 成功

残タスク:

- [x] DB上の `calendar_events` 台帳操作を `CalendarEventLedgerService` へ抽出する。
  - `k_back/app/services/calendar/calendar_event_ledger_service.py` を追加。
  - `create_renewal_deadline_events()` / `create_next_plan_start_date_events()` のDB台帳作成を移動。
  - `get_event_by_cycle()` / `get_event_by_status()` / `delete_event()` を追加し、Google削除処理からDB削除を分離。
- [x] Google同期処理全体を `GoogleCalendarSyncService` へ隔離する。
  - `k_back/app/services/calendar/google_calendar_sync_service.py` を追加。
  - `sync_pending_events()` の未同期イベント同期、失敗時ステータス更新、Googleイベント削除を移動。
  - `CalendarService` は既存API互換のFacadeとして、イベント作成・同期・削除を新サービスへ委譲する構成に変更。
  - 委譲後に到達不能になった旧本文は `CalendarService` から削除し、巨大Service側の責務を縮小。
  - 既存テストの `app.services.calendar_service.GoogleCalendarClient` patch が効くように、委譲直前にGatewayを生成し直す互換性を維持。
- [ ] Google未接続でもアプリ内カレンダー/`.ics` 用の期限イベントを作れる設計へ寄せる。
  - 現在の `calendar_events.google_calendar_id` はDB上 `nullable=False` のため、Google未接続時に保存する値と `sync_status` の扱いを決める必要がある。
  - 候補: `google_calendar_id='local'` などのローカル台帳用固定値を許可し、Google同期対象外のステータス/条件を追加する。
  - 仕様判断が必要なため、今回のP3分割では挙動変更せず未着手。

P3残タスク実施結果:

- [x] RED確認:
  - `docker exec keikakun_app-backend-1 pytest tests/services/test_calendar_refactor_services.py -q`
  - 結果: `ModuleNotFoundError: No module named 'app.services.calendar.calendar_event_ledger_service'`
- [x] `k_back/tests/services/test_calendar_refactor_services.py` を追加し、Facade委譲をテストで固定した。
  - `CalendarService` が `CalendarEventLedgerService` / `GoogleCalendarSyncService` を保持する。
  - イベント作成メソッドが台帳サービスへ委譲される。
  - 同期・削除メソッドがGoogle同期サービスへ委譲される。
- [x] GREEN確認:
  - `docker exec keikakun_app-backend-1 pytest tests/services/test_calendar_refactor_services.py -q`
    - `3 passed`
  - `docker exec keikakun_app-backend-1 pytest tests/services/test_google_calendar_gateway.py tests/services/test_calendar_refactor_services.py tests/services/test_calendar_service.py::TestCalendarService::test_sync_pending_events_success tests/services/test_calendar_service.py::TestCalendarService::test_sync_pending_events_with_api_error tests/services/test_calendar_service.py::TestCalendarService::test_create_renewal_deadline_events_multiple tests/services/test_calendar_service.py::TestCalendarService::test_create_next_plan_start_date_events_for_cycle_2_or_more tests/services/test_calendar_service.py::TestEventDeletion::test_delete_renewal_event_by_cycle tests/services/test_calendar_service.py::TestEventDeletion::test_delete_monitoring_event_by_status -q`
    - `13 passed`
  - `docker exec keikakun_app-backend-1 python -m py_compile app/services/calendar/calendar_event_ledger_service.py app/services/calendar/google_calendar_sync_service.py app/services/calendar/google_calendar_gateway.py app/services/calendar_service.py`
    - 成功

#### P4: `Dashboard.tsx` のhook/表示分離

理由:

- ログイン後の主要画面で、検索/ソート/フィルタ/課金制限/削除が同じコンポーネントにある。
- UI表示は変えずに hook 単位でテストしやすい。

作業順序:

1. filter/sort/searchパラメータ生成を `useDashboardFilters` へ抽出する。
2. 初期データ取得と再取得を `useDashboardData` へ抽出する。
3. 課金制限表示判定を `lib/permissions/dashboard.ts` へ抽出する。
4. 一覧描画を `DashboardRecipientTable` へ切り出す。

実施結果:

- [x] `k_front/hooks/dashboard/useDashboardFilters.ts` を追加し、検索語、sort、filter状態、debounce、API query params生成、フィルタ解除、全解除、表示リセット用状態初期化を抽出した。
- [x] `Dashboard.tsx` はAPI取得、削除処理、課金制限表示、一覧描画を維持し、hookから受け取った `DashboardParams` で `dashboardApi.getDashboardData()` を呼ぶ形へ変更した。
- [x] `buildDashboardParams()` / `getNextDashboardSortOrder()` / `getDashboardSortButtonLabel()` / `hasDashboardFilter()` を純粋関数として切り出し、単体テストを追加した。
- [x] `Dashboard.tsx` は 1165行から 999行へ縮小した。
- [x] 追加対応で `k_front/hooks/dashboard/useDashboardData.ts` を追加し、初期取得、フィルタ再取得、表示リセット、利用者削除API、削除後の状態更新をDashboard本体から分離した。
- [x] 追加対応で `k_front/hooks/dashboard/dashboardDataState.ts` を追加し、Dashboard APIレスポンスの `recipients` 正規化を純関数化した。
- [x] 追加対応で `k_front/lib/permissions/dashboard.ts` を追加し、MFA + 課金状態による編集可否、課金制限警告、削除後のDashboard状態更新を共通関数化した。
- [x] 確認:
  - `npm run lint`
    - 成功。
  - `./node_modules/.bin/tsc --noEmit`
    - 成功。
  - `./node_modules/.bin/tsc --target ES2020 --module commonjs --moduleResolution node --esModuleInterop --skipLibCheck --outDir /tmp/dashboard-filter-tests hooks/dashboard/useDashboardFilters.ts hooks/dashboard/useDashboardFilters.test.ts`
    - 成功。
  - `NODE_PATH=$(pwd)/node_modules node --test /tmp/dashboard-filter-tests/useDashboardFilters.test.js`
    - `5 passed`
  - `node --import jiti/register --test hooks/dashboard/useDashboardFilters.test.ts hooks/dashboard/useDashboardData.test.ts lib/permissions/dashboard.test.ts`
    - `10 passed`
  - `npx eslint components/protected/dashboard/Dashboard.tsx hooks/dashboard/useDashboardData.ts hooks/dashboard/dashboardDataState.ts hooks/dashboard/useDashboardData.test.ts lib/permissions/dashboard.ts lib/permissions/dashboard.test.ts`
    - 成功

残タスク:

- [x] 初期データ取得と再取得を `useDashboardData` へ抽出する。
- [x] 課金制限表示判定を `lib/permissions/dashboard.ts` へ抽出する。
- [ ] 一覧描画を `DashboardRecipientTable` へ切り出す。

安全性判断:

- P4開始時は検索・sort・filter状態管理に限定したが、後続対応でAPI取得と課金制限判定も分離済み。
- 現在残っているP4の主タスクは一覧描画の `DashboardRecipientTable` 切り出しのみ。
- `filter=deadline_alert` query は従来と同じく初期表示状態の反映に留め、初期API取得条件は変更していない。

#### P5: `RecipientRegistrationForm.tsx` / `RecipientEditForm.tsx` の共通form分離

理由:

- 登録/編集で option定義、section validation、入力handler、section描画が重複している。
- ただし画面差分と申請modal差分があり、先に分割設計を固めないとUI回帰しやすい。

作業順序:

1. option定義と初期値を `recipientFormOptions.ts` / `recipientFormDefaults.ts` へ抽出する。
2. validationを `recipientFormValidation.ts` へ抽出し、単体テストを追加する。
3. 入力状態とhandlerを `useRecipientFormState` へ抽出する。
4. section描画を `BasicInfoSection` / `ContactSection` / `EmergencyContactsSection` / `DisabilitySection` へ分割する。
5. 登録/編集固有のsubmit処理とemployee申請modalは各コンテナに残す。

実施結果:

- [x] RED: `recipientFormValidation.test.ts` を追加し、未実装の `recipientFormValidation` / `recipientFormDefaults` / `recipientFormTypes` 参照で `tsc` が失敗することを確認。
- [x] `recipientFormTypes.ts` を追加し、登録/編集フォームで重複していた `BasicInfoData` / `ContactAddressData` / `EmergencyContactData` / `DisabilityInfoData` / `DisabilityDetailData` / `RecipientFormData` を共通化。
- [x] `recipientFormDefaults.ts` を追加し、フォームsection定義、空の緊急連絡先、空の手帳・年金詳細、登録フォーム初期値を共通化。
- [x] `recipientFormOptions.ts` を追加し、性別、居住形態、交通手段、生活保護、手帳カテゴリ、申請状況、身体障害種別、続柄、等級・レベルの選択肢を共通化。
- [x] `recipientFormValidation.ts` を追加し、section validationを共通化。既存差分として、登録では緊急連絡先ふりがな必須、編集では現行通り未必須を `mode` で固定。
- [x] `RecipientRegistrationForm.tsx` / `RecipientEditForm.tsx` はsubmit処理とemployee申請modalを各コンテナに残したまま、共通定義を参照する形へ変更。
- [x] RED: `recipientFormMapper.test.ts` / `recipientFormState.test.ts` を追加し、未実装の `recipientFormMapper` / `recipientFormState` 参照で `tsc` が失敗することを確認。
- [x] `recipientFormMapper.ts` を追加し、編集フォームの `initialData` 変換を `mapWelfareRecipientToFormData()` へ抽出。snake_case/camelCase混在レスポンスと、ネストデータ欠落時の空行生成を単体テストで固定。
- [x] `recipientFormState.ts` / `useRecipientFormState.ts` を追加し、緊急連絡先追加/削除、手帳・年金詳細追加/削除、各入力handler、カテゴリ変更時の等級リセットを共通化。
- [x] RED: `recipientFormSections.test.ts` を追加し、未実装の section component import で `tsc` が失敗することを確認。
- [x] `BasicInfoSection.tsx` / `ContactSection.tsx` / `EmergencyContactsSection.tsx` / `DisabilitySection.tsx` / `DisabilityDetailsSection.tsx` へsection描画を分割。
  - 登録/編集差分は `mode` prop で固定。
  - 登録フォームは約912行から340行、編集フォームは約917行から297行へ縮小。
- [x] GREEN確認:
  - `./node_modules/.bin/tsc --target ES2020 --module commonjs --moduleResolution node --esModuleInterop --skipLibCheck --outDir /tmp/recipient-form-tests components/protected/recipients/forms/recipientFormValidation.ts components/protected/recipients/forms/recipientFormDefaults.ts components/protected/recipients/forms/recipientFormTypes.ts components/protected/recipients/forms/recipientFormValidation.test.ts`
    - 成功
  - `node --test /tmp/recipient-form-tests/recipientFormValidation.test.js`
    - `3 passed`
  - `./node_modules/.bin/tsc --noEmit`
    - 成功
  - `npm run lint`
    - 成功
  - `node --test /tmp/recipient-form-tests/components/protected/recipients/forms/recipientFormMapper.test.js /tmp/recipient-form-tests/components/protected/recipients/forms/recipientFormState.test.js /tmp/recipient-form-tests/recipientFormValidation.test.js`
    - `8 passed`
  - `NODE_PATH=$(pwd)/node_modules node --test /tmp/recipient-section-tests/protected/recipients/forms/recipientFormSections.test.js`
    - `1 passed`

P5残タスク:

- [x] 入力状態とhandlerを `useRecipientFormState` へ抽出する。
- [x] 編集フォームの `initialData` 変換を専用mapperへ抽出し、単体テストを追加する。
- [x] section描画を `BasicInfoSection` / `ContactSection` / `EmergencyContactsSection` / `DisabilitySection` へ分割する。

#### P6: `AdminMenu.tsx` のtab単位分離

理由:

- 1526行で最も大きいが、複数tabが比較的明確に分かれている。
- 先に課金/申請/利用者formのリファクタを進めた後の方が、変更衝突が少ない。

作業順序:

1. `OfficeInfoTab` / `StaffManagementTab` / `GoogleIntegrationTab` / `BillingPlanTab` に表示を分ける。
2. Google Calendar状態管理を `useOfficeCalendarSettings` へ抽出する。
3. スタッフMFA操作を `useOfficeStaffMfaManagement` へ抽出する。
4. 事業所編集modalを `OfficeEditModal` と `useOfficeEditForm` へ分離する。

実施結果:

- [x] `k_front/components/protected/admin/OfficeInfoTab.tsx` を追加し、事業所情報カードと退会セクションの表示を `AdminMenu.tsx` から分離した。
- [x] `k_front/components/protected/admin/StaffManagementTab.tsx` を追加し、スタッフ一覧、MFA個別操作、MFA一括操作、スタッフ削除の表示を分離した。
- [x] `k_front/components/protected/admin/GoogleIntegrationTab.tsx` を追加し、Google Calendar設定表示、アップロードフォーム、連携解除UIを分離した。
- [x] `AdminMenu.tsx` は既存のAPI呼び出し、状態管理、modal状態、submit処理を維持し、子コンポーネントへpropsを渡すcontainer寄りの構成にした。
- [x] `AdminMenu.tsx` は 1526行から 985行へ縮小した。
- [x] 安全範囲の追加リファクタとして、既存 `PlanTab` を残したまま `BillingPlanTab.tsx` から再exportし、`AdminMenu.tsx` 側のタブ名をP6方針に合わせた。
- [x] 安全範囲の追加リファクタとして、事業所編集modalの表示だけを `OfficeEditModal.tsx` に分離した。保存処理、入力state、差分生成、reload挙動は既存どおり `AdminMenu.tsx` に残した。
- [x] 追加リファクタ後、`AdminMenu.tsx` は 985行から 881行へ縮小した。
- [x] 確認:
  - `npm run lint`
    - 成功。
  - `./node_modules/.bin/tsc --noEmit`
    - 成功。

残タスク:

- [x] 有料会員タブは既存 `PlanTab` が既に分離済みのため、必要なら名前だけ `BillingPlanTab` 相当に揃える。
- [ ] Google Calendar状態管理を `useOfficeCalendarSettings` へ抽出する。
- [ ] スタッフMFA操作を `useOfficeStaffMfaManagement` へ抽出する。
- [x] 事業所編集modalの表示を `OfficeEditModal` へ分離する。
- [ ] 事業所編集form状態と保存処理を `useOfficeEditForm` へ分離する。

安全性判断:

- 今回はリスクを下げるため、外部API呼び出し、Google Calendar状態管理、MFA操作、事業所更新データ生成、保存後reloadの挙動は変更しなかった。
- 次に進める場合も、Google Calendar/MFAのhook抽出はAPI副作用と再取得処理を含むため、事前に現行挙動の確認観点を固定してから行う。

### 2.3 分割粒度のルール

共通ルール:

- 1回のPRで公開API、画面文言、DBスキーマを同時に変えない。
- 1回のPRで抽出する責務は1種類に限定する。
- 既存のService名/Component名は当面 facade/container として残す。
- 外部API副作用、DB更新、表示判定、変換処理を同じ抽出先に混ぜない。
- 抽出先のファイル目安は200〜400行以内。400行を超える場合は責務を再確認する。
- `index.ts` で過剰に再exportせず、依存方向が読めるimportにする。

Backendの粒度:

- `*TransitionService`: 入力データから状態や更新内容を決める。DB commitは持たない。
- `*Gateway`: Stripe/Google/S3など外部API呼び出しを閉じ込める。
- `*NoticeService`: 通知作成、保持上限削除を閉じ込める。
- `*Executor`: 申請に伴う実処理を閉じ込める。
- 既存ServiceはAPI層から呼ばれる facade とし、トランザクション境界を崩さない。

Frontendの粒度:

- `use*Data`: API取得、再取得、loading/error状態。
- `use*Filters`: search/sort/filterとURL query変換。
- `use*FormState`: form state、入力handler、section移動。
- `*Section`: propsを受けて描画するだけのsection。
- `*Modal`: modal表示とsubmit結果表示。API呼び出しはhookまたはcontainerに寄せる。

### 2.4 分割後の構成案

Backend:

```text
k_back/app/services/billing_service.py                  # facade。既存公開メソッドを維持
k_back/app/services/billing/
  status_transition.py                                  # BillingStatusTransitionService
  checkout_session.py                                   # Stripe Checkout/Portal作成
  webhook_processor.py                                  # Webhook event分類とService呼び出し
  webhook_event_recorder.py                             # webhook_events記録

k_back/app/services/approval/
  notice_service.py                                     # role/employee共通通知
  employee_action_executor.py                           # employee action実処理

k_back/app/services/welfare_recipient/
  deadline_alert_service.py                             # 期限アラート
  support_plan_integrity_service.py                     # 支援計画整合性補正

k_back/app/services/calendar/
  google_calendar_gateway.py                            # Google API client/API呼び出し
  event_ledger_service.py                               # calendar_events台帳
  google_sync_service.py                                # 互換機能としてのGoogle同期
```

Frontend:

```text
k_front/components/protected/dashboard/Dashboard.tsx     # container
k_front/hooks/dashboard/useDashboardData.ts
k_front/hooks/dashboard/useDashboardFilters.ts
k_front/lib/billing-restrictions.ts
k_front/components/protected/dashboard/DashboardRecipientTable.tsx

k_front/components/protected/recipients/forms/
  recipientFormOptions.ts
  recipientFormDefaults.ts
  recipientFormValidation.ts
  useRecipientFormState.ts
  BasicInfoSection.tsx
  ContactSection.tsx
  EmergencyContactsSection.tsx
  DisabilitySection.tsx

k_front/components/protected/admin/
  AdminMenu.tsx                                          # tab container
  OfficeInfoTab.tsx
  StaffManagementTab.tsx
  GoogleIntegrationTab.tsx
  BillingPlanTab.tsx
  hooks/useOfficeCalendarSettings.ts
  hooks/useOfficeStaffMfaManagement.ts
```

### 2.5 TDD/確認方針

Backend:

- 抽出前に既存Serviceの公開メソッド単位で現行挙動を固定する。
- 状態遷移など純粋判定に近いものは、抽出先に小さな単体テストを追加する。
- 外部API Gatewayはmock前提で、成功/失敗/例外時の戻り値を固定する。
- API層のレスポンス、DB commit/flushの責務境界は変えない。

Frontend:

- まずhook/utility単位でテスト可能なロジックを抽出する。
- 表示分割はスクリーンショットや主要DOM文言の回帰確認を行う。
- 既存の画面文言、ボタンラベル、制限表示条件、URL query挙動は変えない。
- コンポーネント分割だけのPRではAPI呼び出し契約を変えない。

### 2.6 最初に着手する具体タスク

次の実装タスクはP0-1とする。

- 対象: `k_back/app/services/billing_service.py`
- 目的: 課金状態遷移の判定を `BillingStatusTransitionService` に抽出する前段として、現行挙動をテストで固定する。
- RED候補:
  - trial期間中の `customer.subscription.created` は `early_payment` になる。
  - trial終了後の `customer.subscription.created` は `active` になる。
  - `payment_failed` はtrial有効中なら状態を変えず、trial終了後なら `payment_failed` になる。
  - `cancel_at_period_end` または `cancel_at` ありのsubscription updateは `canceling` になる。
  - `trial_expired` または期限切れfree相当でキャンセル信号が来た場合は `canceled` になる。
- GREEN候補:
  - `BillingStatusTransitionService` を追加し、既存 `BillingService` はそこを呼ぶ。
  - DB更新、webhook event記録、Stripe object parsingは既存Service側に残す。

実施結果:

- [x] `k_back/tests/services/test_billing_status_transition.py` を追加し、課金状態遷移の純粋判定を単体テスト化した。
  - `subscription.created`: trial有効中は `early_payment`、trial終了後/未設定は `active`
  - `payment_failed`: trial有効中は状態変更なし、trial終了後/未設定は `payment_failed`
  - `subscription.updated`: `trial_expired` または期限切れ未払い相当のキャンセル信号は即時 `canceled`
  - `canceling` 取り消し: trial中かつsubscriptionありは `early_payment`、subscriptionなしは `free`、trial外は `active`
  - `subscription.deleted`: 直近 `payment_failed` があれば `payment_failed`、なければ `canceled`
- [x] RED確認:
  - `docker exec keikakun_app-backend-1 pytest tests/services/test_billing_status_transition.py -q`
  - 結果: `ModuleNotFoundError: No module named 'app.services.billing'`
- [x] `k_back/app/services/billing/status_transition.py` を追加し、`BillingStatusTransitionService` に状態遷移判定を抽出した。
- [x] `k_back/app/services/billing_service.py` は既存公開メソッドを維持し、DB更新、webhook event記録、監査ログ、Stripe object parsingを残した。
- [x] GREEN確認:
  - `docker exec keikakun_app-backend-1 pytest tests/services/test_billing_status_transition.py -q`
    - `10 passed`
  - `docker exec keikakun_app-backend-1 pytest tests/services/test_billing_service.py::TestBillingServiceTransactionIntegrity tests/services/test_billing_canceling.py -q`
    - `20 passed`
  - `docker exec keikakun_app-backend-1 python -m py_compile app/services/billing/status_transition.py app/services/billing_service.py`
    - 成功
- [x] P0追加TDD: バッチ/APIに残っていた試用期限切れ・scheduled cancel期限切れの遷移判定を `BillingStatusTransitionService` へ集約した。
  - RED:
    - `determine_trial_expiration_status()` 未実装で `AttributeError`
    - `determine_scheduled_cancellation_status()` 未実装で `AttributeError`
  - GREEN:
    - `free -> trial_expired`
    - `early_payment -> active`
    - `canceling -> canceled`
    - その他statusは自動遷移なし
  - 反映箇所:
    - `k_back/app/tasks/billing_check.py`
      - `check_trial_expiration()`
      - `check_scheduled_cancellation()`
    - `k_back/app/api/v1/endpoints/billing.py`
      - `/billing/status` 取得時の期限切れ補正
    - `k_back/app/services/billing_service.py`
      - Checkout前の期限切れfree補正
  - 確認:
    - `docker exec keikakun_app-backend-1 pytest tests/services/test_billing_status_transition.py tests/tasks/test_billing_check.py -q`
      - `32 passed`
    - `docker exec keikakun_app-backend-1 pytest tests/services/test_billing_service.py::TestCancelingToCanceledTransition::test_subscription_deleted_audit_log -q`
      - `1 passed`
    - `docker exec keikakun_app-backend-1 pytest tests/services/test_billing_service.py::TestBillingServiceTransactionIntegrity::test_process_subscription_created_early_payment tests/services/test_billing_service.py::TestBillingServiceTransactionIntegrity::test_process_subscription_created_active_after_trial tests/services/test_billing_service.py::TestBillingServiceStripeIntegration::test_create_checkout_session_with_customer_excludes_expired_trial_end tests/services/test_billing_service.py::TestBillingServiceStripeIntegration::test_create_checkout_session_rollback_on_checkout_session_error -q`
      - `4 passed`
    - `docker exec keikakun_app-backend-1 python -m py_compile app/services/billing/status_transition.py app/tasks/billing_check.py app/api/v1/endpoints/billing.py app/services/billing_service.py`
      - 成功
  - 補足:
    - `tests/services/test_billing_service.py tests/services/test_billing_canceling.py -q` は一括実行で共有DB由来と見られる `StaleDataError` が1件発生したが、該当テスト単体ではpassした。

### 3. 申請系Serviceで通知作成・承認/却下フローが重複している

該当箇所:

- `k_back/app/services/role_change_service.py`
- `k_back/app/services/employee_action_service.py`
- `k_back/app/crud/crud_notice.py`

確認内容:

- 「通知作成用に一時的にリレーションシップを含めて取得」という処理が複数箇所にある。
- role change と employee action で、申請作成、承認、却下、通知、監査に似た流れがある。

リスク:

- 片方の申請種別だけ通知文言や既読/保持上限処理がずれる。
- 申請ステータスや監査要件の変更時に二重修正が必要。
- 権限チェックの差分が仕様なのか実装漏れなのか判断しづらい。

推奨リファクタ:

- 申請通知の共通ヘルパーを作る。
- 承認/却下の共通フローを薄い基底ロジックまたはユースケース関数へ寄せる。
- ただし、role change と employee action の業務差分は無理に継承で隠さない。

受け入れ要件:

- [ ] 通知作成、保持上限削除、監査ログ作成の共通処理が1箇所に集約される。
  - employee action 側の通知作成、承認/却下通知、保持上限削除は `EmployeeActionNoticeService` に集約済み。
  - role change 側の通知共通化と監査ログ共通化は未実施。
- [x] role change / employee action それぞれの差分は明示的に残る。
  - 今回は employee action の通知処理だけを抽出し、承認/却下、実処理実行、エラー時承認記録は既存 `EmployeeActionService` に残した。
- [x] 承認/却下時の通知テストが両方にある。
  - role change 側は既存 `tests/services/test_role_change_service.py` に承認/却下通知テストあり。
  - employee action 側は `tests/services/test_employee_action_service.py` と `tests/services/test_employee_action_notice_service.py` で確認済み。

### 4. debugログ/print/console.logが本番コードに多く残っている

該当箇所例:

- `k_front/lib/support-plan.ts`
- `k_front/lib/pdf-deliverables.ts`
- `k_front/app/(protected)/pdf-list/page.tsx`
- `k_front/components/protected/support_plan/SupportPlan.tsx`
- `k_front/components/protected/profile/Profile.tsx`
- `k_back/app/api/v1/endpoints/assessment.py`
- `k_back/app/api/v1/endpoints/role_change_requests.py`
- `k_back/app/api/v1/endpoints/employee_action_requests.py`
- `k_back/app/api/v1/endpoints/staffs.py`
- `k_back/app/services/welfare_recipient_service.py`

リスク:

- 個人情報、内部ID、支援計画データ、ファイル情報がログに出る可能性がある。
- 調査時に重要ログが埋もれる。
- `print()` は構造化ログやログレベル制御に乗らない。

推奨リファクタ:

- frontendは `debugLog()` のような小さなwrapperに寄せ、productionでは出さない。
- backendは `print()` を禁止し、`logger.debug/info/warning/error` に統一する。
- 個人情報・トークン・ファイル名・メールアドレス・支援計画内容はログに出さない方針を明文化する。

受け入れ要件:

- [x] backend endpoint内の `print()` がなくなる。
- [x] frontend production buildで業務データの `console.log` が出ない。
- [x] ログ出力方針のmdがある。
  - `md_files_design_note/task/todo/refactor/maintainability/log_policy.md` を追加。
  - 本番で出してよい情報、出さない情報、backend/frontend別の扱い、監査ログへ移すべき情報を整理。

再確認結果: 2026-07-01

確認コマンド:

- `rg -n "\bprint\(" k_back/app --glob '!**/*.md'`
- `rg -n "console\.log\(" k_front/app k_front/components k_front/lib k_front/hooks --glob '!**/*.md'`
- `rg -n "console\.(error|warn|info|debug)\(" k_front/app k_front/components k_front/lib k_front/hooks --glob '!**/*.md'`
- `rg -n "logger\.debug" k_back/app --glob '!**/*.md'`

確認結果:

- `console.log(` は `k_front/app` / `k_front/components` / `k_front/lib` / `k_front/hooks` では0件。
- frontendの `console.error` / `console.warn` / `console.info` / `console.debug` は合計80件。
  - 大半はcatch節の失敗ログ。
  - `Dashboard.tsx` にはAPI不整合時の `console.warn` と、filter/初期取得/reset/delete失敗時の `console.error` が残っている。
  - `LayoutClient.tsx`、`SupportPlan.tsx`、`PdfViewContent.tsx`、`NotificationSettings.tsx`、`AdminMenu.tsx` など、利用者情報・PDF・通知・Google連携に関わる画面にも残っている。
- backendの `print(` は合計30件。
  - endpoint内の実行ログは27件。
    - `k_back/app/api/v1/endpoints/employee_action_requests.py`: 9件
    - `k_back/app/api/v1/endpoints/role_change_requests.py`: 9件
    - `k_back/app/api/v1/endpoints/assessment.py`: 6件
    - `k_back/app/api/v1/endpoints/staffs.py`: 3件
  - docstring例としての `print(` が3件。
    - `k_back/app/tasks/deadline_notification.py`
    - `k_back/app/tasks/billing_check.py`
- backendの `logger.debug` は合計55件。
  - `k_back/app/services/welfare_recipient_service.py` に作成・削除・Google Calendar削除周辺の詳細debugが多く残っている。
  - `k_back/app/api/deps.py` に認証依存のdebugが残っている。
  - `k_back/app/services/staff_profile_service.py` にメールアドレス変更検証フローのdebugが残っている。
  - `k_back/app/tasks/deadline_notification.py` にbatch処理debugが残っている。

優先対応順:

1. backend endpoint内の `print()` を削除または `logger.debug/info/warning` へ置換する。
   - 最優先は `staffs.py` のメール変更token断片ログ。tokenの一部でも本番ログに出すべきではない。
   - 次に `assessment.py` の `current_user.email` と `recipient_id` 出力。
   - その後、role change / employee action の一覧件数・申請詳細debugを整理する。
2. frontendの `console.error/warn` は、まず業務データを含む可能性がある箇所から削る。
   - `Dashboard.tsx` の `newDashboardData.recipients` 出力。
   - `RecipientRegistrationForm.tsx` / `RecipientEditForm.tsx` のform submit error。
   - `SupportPlan.tsx` / `PdfViewContent.tsx` / `LayoutClient.tsx` の利用者・PDF・通知関連。
3. backendの `logger.debug` は、PII/内部ID/Google連携情報を含むものを棚卸しし、必要なものだけ構造化ログへ残す。
   - `welfare_recipient_service.py` の氏名、recipient_id、google_event_id、service account有無などは本番debugとして過剰。
   - `api/deps.py` の認証debugは、障害調査用ならログレベルと出力内容を絞る。
4. ログ出力方針mdを追加する。
   - 出してよいもの: 件数、処理名、匿名化された状態、エラー種別。
   - 出さないもの: 氏名、メールアドレス、token、recipient_id、staff_id、Google event id、PDF名、支援計画本文、ファイル内容。

受け入れ要件の現状:

- [x] backend endpoint内の `print()` がなくなる。
  - 2026-07-01対応でendpoint実行ログ27件を削除。
  - docstring例の `print()` 3件も `logger.info()` 例へ置換。
  - `rg -n "\bprint\(" k_back/app --glob '!**/*.md'` は0件。
- [x] frontend production対象コードに無条件の `console.log` が残っていない。
  - `console.log(` は0件。
  - 2026-07-01対応で、業務データを含む可能性が高い `console.error/warn` を一部削除し、80件から59件へ減少。
- [x] ログ出力方針のmdがある。
  - `log_policy.md` に本番許可ログ、禁止ログ、開発時限定ログ、監査ログへ移すべき情報を整理。

2026-07-01 削除対応:

- backend:
  - `k_back/app/api/v1/endpoints/employee_action_requests.py`
    - employee action一覧取得時の `print()` debug 9件を削除。
  - `k_back/app/api/v1/endpoints/role_change_requests.py`
    - role change一覧取得時の `print()` debug 9件を削除。
  - `k_back/app/api/v1/endpoints/assessment.py`
    - assessment取得時の `print()` 6件を削除。
    - 同じ内容を出していた `logger.info()` 3件も削除。`recipient_id` と `current_user.email` をログに出さない形へ変更。
  - `k_back/app/api/v1/endpoints/staffs.py`
    - email change verify時のtoken断片、成功結果、例外詳細の `print()` 3件を削除。
    - `traceback.print_exc()` も削除。
  - `k_back/app/tasks/billing_check.py`
    - docstring例の `print()` 2件を `logger.info()` 例へ置換。
  - `k_back/app/tasks/deadline_notification.py`
    - docstring例の `print()` 1件を `logger.info()` 例へ置換。
- frontend:
  - `k_front/components/protected/dashboard/Dashboard.tsx`
    - `newDashboardData.recipients` を含む `console.warn` を削除。
    - filter、初期取得、reset、delete失敗時の `console.error` を削除。ユーザー向けtoastは維持。
  - `k_front/components/protected/recipients/RecipientRegistrationForm.tsx`
    - form submit失敗時の `console.error` を削除。画面上のエラー表示は維持。
  - `k_front/components/protected/recipients/RecipientEditForm.tsx`
    - form submit失敗時の `console.error` を削除。画面上のエラー表示は維持。
  - `k_front/components/protected/support_plan/SupportPlan.tsx`
    - 支援計画取得、PDF upload/reupload、モニタリング期限設定の `console.error` を削除。toast/error stateは維持。
  - `k_front/components/protected/pdf-list/PdfViewContent.tsx`
    - 利用者一覧取得、PDF一覧取得の `console.error` を削除。画面上のエラー表示は維持。
  - `k_front/components/protected/LayoutClient.tsx`
    - 未読件数、未読メッセージ、期限通知、CSRF、事業所情報、通知初期化、logout失敗時の `console.error` を削除。既存のフォールバック処理は維持。

確認:

- `rg -n "\bprint\(" k_back/app --glob '!**/*.md'`
  - 0件。
- `rg -n "console\.log\(" k_front/app k_front/components k_front/lib k_front/hooks --glob '!**/*.md'`
  - 0件。
- `rg -n "console\.(error|warn|info|debug)\(" k_front/app k_front/components k_front/lib k_front/hooks --glob '!**/*.md' | wc -l`
  - 59件。
- `python3 -m py_compile k_back/app/api/v1/endpoints/employee_action_requests.py k_back/app/api/v1/endpoints/role_change_requests.py k_back/app/api/v1/endpoints/assessment.py k_back/app/api/v1/endpoints/staffs.py k_back/app/tasks/billing_check.py k_back/app/tasks/deadline_notification.py`
  - 成功。
- `npm run lint`
  - 成功。
- `./node_modules/.bin/tsc --noEmit`
  - 成功。

## 優先度中

### 5. Google Calendar連携は廃止・縮退・代替機能化を前提に整理する

該当箇所:

- `k_back/app/services/calendar_service.py`
- `k_back/app/services/welfare_recipient_service.py`
- `md_files_design_note/task/todo/refactor/google_calendar/google_calendar.md`

確認内容:

- 支援計画作成/削除とGoogle Calendarイベント作成/削除が同じ同期処理内に混ざっている。
- サービスアカウントキー復号、Google client作成、外部API呼び出し、DBイベント更新が近い場所にある。
- 既存のGoogle Calendar方針ドキュメントでは、サービスアカウント方式のGoogle自動同期は主軸機能として扱わず、将来的な新規提供停止・縮退・廃止も視野に入れている。
- 代替候補として、アプリ内カレンダー機能と `.ics` ダウンロードを優先する方針が示されている。

リスク:

- Google API障害が本体機能の成功/失敗に影響しやすい。
- リトライ、冪等性、失敗時の補償が追いづらい。
- Google Calendar未接続事務所にも関連処理が読み込まれ、仕様理解が難しくなる。
- 廃止・縮退予定の機能にリファクタ工数をかけすぎると、代替機能の整備が遅れる。
- サービスアカウント方式を前提にしたDB/画面/APIを増やすと、後の廃止コストが大きくなる。

推奨リファクタ:

- Google Calendar自動同期の恒久維持を前提にしない。
- まず「期限イベント生成」と「Googleへ同期する処理」を分離する。
- `calendar_events` をGoogle同期専用ではなく、アプリ内カレンダー/`.ics` 用の期限イベント台帳として扱えるようにする。
- Google未接続でも期限イベントを作成できる設計に寄せる。
- Google自動同期は既存利用者向けの互換機能として当面残し、新規導線はアプリ内カレンダーと `.ics` ダウンロードへ寄せる。
- 廃止までの移行期間中だけ、Google同期失敗を再試行可能な副作用として扱う。

代替機能候補:

- アプリ内カレンダー:
  - 期限予定をアプリ内で確認する主機能にする。
  - Google Calendarを使わない事業所にも価値が届く。
- `.ics` ダウンロード:
  - Google Cloud Consoleやサービスアカウント設定を不要にする。
  - Google Calendarを使いたい事業所は手動インポートで利用できる。
  - 自動同期ではないため、設定難易度と権限リスクを下げられる。

受け入れ要件:

- [x] 支援計画作成/削除の成功条件がGoogle Calendar API成功に依存しない。
  - `SupportPlanCalendarEventService` を追加し、支援計画作成/完了処理から `calendar_service` 直接呼び出しを外した。
  - `welfare_recipient_service.delete_recipient()` から `GoogleCalendarClient` 直接生成/削除を外し、Google側削除は `GoogleCalendarSyncService.delete_google_events_for_recipient()` に隔離した。
  - Google側削除に失敗しても、既存仕様どおり支援計画/利用者削除の本体処理は継続する。
- [ ] Google未接続でもアプリ内カレンダー/`.ics` 用の期限イベントを生成できる。
- [x] Google自動同期は既存利用者向けの互換機能として分離される。
  - `GoogleCalendarAccountService` を追加し、サービスアカウント取得・接続状態確認・credential復号を分離した。
  - `CalendarSyncResultService` を追加し、同期成功/失敗のDB反映を分離した。
  - `GoogleCalendarSyncService.sync_event_group()` を追加し、同期対象グループごとに「認証情報取得」「外部API呼び出し」「DB結果更新」を分けた。
  - `GoogleCalendarGateway` は外部API境界として残し、既存テストのpatch互換も維持した。
- [ ] 新規導線はサービスアカウント方式ではなく、アプリ内カレンダーまたは `.ics` を優先する。
- [ ] Google同期の新規提供停止・縮退・廃止判断に必要な利用状況を確認できる。

TDD実施結果:

- [x] RED確認:
  - `docker exec keikakun_app-backend-1 pytest tests/services/test_calendar_deprecation_boundary_services.py -q`
  - 結果: `ModuleNotFoundError: No module named 'app.services.calendar.calendar_sync_result_service'`
  - recipient単位削除追加時のRED:
    - `AttributeError: 'GoogleCalendarSyncService' object has no attribute 'delete_google_events_for_recipient'`
- [x] GREEN確認:
  - `docker exec keikakun_app-backend-1 pytest tests/services/test_calendar_deprecation_boundary_services.py -q`
    - `4 passed`
  - `docker exec keikakun_app-backend-1 pytest ... -q`
    - Google Calendar境界、既存カレンダー同期、支援計画、利用者削除の関連 `21 passed`
  - `docker exec keikakun_app-backend-1 python -m py_compile app/services/calendar/google_calendar_account_service.py app/services/calendar/calendar_sync_result_service.py app/services/calendar/support_plan_calendar_event_service.py app/services/calendar/google_calendar_sync_service.py app/services/calendar/google_calendar_gateway.py app/services/calendar/calendar_event_ledger_service.py app/services/calendar_service.py app/services/support_plan_service.py app/services/welfare_recipient_service.py`
    - 成功

### 6. 課金状態遷移の責務がWebhook/バッチ/APIに分散している

該当箇所:

- `k_back/app/services/billing_service.py`
- `k_back/app/tasks/billing_check.py`
- `k_back/app/api/v1/endpoints/billing.py`
- `k_front/components/billing`

リスク:

- `trial_expired` / `payment_failed` / `canceling` / `canceled` の遷移条件が複数箇所に分かれる。
- Stripe Webhook順序やTest Clock挙動への対応が属人的になりやすい。
- frontendの制限表示とbackendの書き込み制限がずれる可能性がある。

推奨リファクタ:

- Billing状態遷移を `BillingStatusTransitionService` のような小さな単位に切る。
- Webhook/バッチ/APIは「イベント入力」として扱い、状態決定ロジックを一箇所へ寄せる。
- 状態遷移表をテストデータとして持つ。

受け入れ要件:

- [x] 状態遷移の判定ロジックが1箇所に集約される。
  - `BillingStatusTransitionService` に、subscription created / payment failed / trial expiration / scheduled cancellation / canceling restore / subscription deleted の判定を集約。
- [x] Webhook/バッチ/APIで同じ遷移関数を使う。
  - Webhook: `BillingService`
  - バッチ: `app/tasks/billing_check.py`
  - API: `app/api/v1/endpoints/billing.py`
- [x] frontend表示とbackend制限の対応表がドキュメント化される。
  - 現行コードの `k_front/lib/billing/status.ts` / `k_front/lib/permissions/dashboard.ts` / backend `require_active_billing` をもとに下表へ整理。

現行の課金状態マッピング:

| status | backend遷移上の意味 | 書き込み可否 | primary action | frontend警告 |
| --- | --- | --- | --- | --- |
| `free` | 無料トライアル中 | 可 | なし | なし |
| `early_payment` | 無料期間中に課金設定済み | 可 | なし | なし |
| `active` | 課金中 | 可 | なし | なし |
| `canceling` | 期間終了時キャンセル予定 | 可 | なし | なし |
| `trial_expired` | 無料期間終了・未課金 | 不可 | checkout | 無料試用期間終了 |
| `payment_failed` | 支払い失敗。frontendではtrial終了後のみ制限理由扱い | trial終了後は不可 | portal | 支払い失敗 |
| `past_due` | 互換用の支払い対応必要状態 | 不可 | portal | 支払い確認必要 |
| `canceled` | キャンセル済み | 不可 | checkout | キャンセル済み |

補足:

- frontendの `payment_failed` は `isTrialEnded()` がtrueの場合だけ制限理由になる。
- backendの `require_active_billing` は `past_due` / `trial_expired` / `payment_failed` / `canceled` を書き込み制限対象にする。
- 上記の差分は仕様として維持するか追加照合テストで固定するかを、次の課金タスクで判断する。

### 7. frontendのAPI呼び出しと画面状態管理がコンポーネント内に混在している

該当箇所:

- `k_front/components/protected/dashboard/Dashboard.tsx`
- `k_front/components/protected/recipients/RecipientRegistrationForm.tsx`
- `k_front/components/protected/recipients/RecipientEditForm.tsx`
- `k_front/components/protected/support_plan/SupportPlan.tsx`
- `k_front/app/(protected)/pdf-list/page.tsx`

リスク:

- APIレスポンス変換、バリデーション、表示状態、権限判定が同じファイルに混ざる。
- 画面テストが重くなり、ロジックだけをテストしづらい。
- 同じ変換・同じ権限判定が複数画面に散らばる。

推奨リファクタ:

- `hooks/useDashboardData`、`hooks/useRecipientForm` など画面単位のhookへAPI/状態管理を分離する。
- 表示コンポーネントはpropsを受けて描画に集中させる。
- 権限判定は `lib/permissions` に寄せる。

受け入れ要件:

- [x] 主要画面でAPI取得と表示コンポーネントが分離される。
  - `k_front/hooks/dashboard/useDashboardData.ts` を追加し、Dashboardの初期取得、フィルタ再取得、表示リセット、利用者削除APIと削除後の状態更新を分離した。
  - `k_front/hooks/dashboard/dashboardDataState.ts` を追加し、APIレスポンスの `recipients` 正規化を純関数化した。
  - `k_front/components/protected/dashboard/Dashboard.tsx` は新hookから状態と操作を受け取り、表示とUIイベントに寄せた。
- [x] 権限判定が画面内のインライン条件から共通関数へ移る。
  - `k_front/lib/permissions/dashboard.ts` を追加し、MFA + 課金状態による編集可否、課金制限警告文、削除後のDashboard状態更新を共通関数化した。
- [x] hook単位のテストが追加できる。
  - `k_front/hooks/dashboard/useDashboardData.test.ts` を追加し、Dashboard APIレスポンス正規化をテストした。
  - `k_front/lib/permissions/dashboard.test.ts` を追加し、編集可否、課金制限警告、削除後状態更新をテストした。
  - 既存の `useDashboardFilters.test.ts` と同じ `node:test` 形式で実行可能にした。

TDD実施結果:

- [x] RED確認:
  - `npx tsc --noEmit`
  - 結果:
    - `Cannot find module './useDashboardData'`
    - `Cannot find module './dashboard'`
- [x] GREEN確認:
  - `npx tsc --noEmit`
    - 成功
  - `node --import jiti/register --test hooks/dashboard/useDashboardFilters.test.ts hooks/dashboard/useDashboardData.test.ts lib/permissions/dashboard.test.ts`
    - `10 passed`
  - `npx eslint components/protected/dashboard/Dashboard.tsx hooks/dashboard/useDashboardData.ts hooks/dashboard/dashboardDataState.ts hooks/dashboard/useDashboardData.test.ts lib/permissions/dashboard.ts lib/permissions/dashboard.test.ts`
    - 成功

### 8. `get_current_user()` が広範囲で使われ、必要な情報量を選べない

該当箇所:

- `k_back/app/api/deps.py`
- 多数の `k_back/app/api/v1/endpoints/*.py`

確認内容:

- 多くのendpointが同じ `deps.get_current_user` に依存している。
- 軽量な認証確認だけでよいAPIと、Office/role/associationまで必要なAPIが同じ入口を使っている。

リスク:

- 依存処理の変更が全APIへ影響する。
- 権限要件がendpointごとに見えづらい。
- テストで必要以上にStaff/Office fixtureが必要になる。

推奨リファクタ:

- `get_current_user_minimal`
- `get_current_user_with_office`
- `require_owner_or_manager`

のように用途別依存へ分ける。

受け入れ要件:

- [x] 軽量依存とOffice必須依存が分かれる。
  - `get_current_user_minimal`: Staff本体だけを取得し、`office_associations` / `office` を eager load しない。
  - `get_current_user_with_office`: `office_associations.office` を eager load し、所属事務所の削除済みチェックも実施する。
  - 既存互換のため `get_current_user = get_current_user_with_office` として残した。
- [x] endpointの権限要件が依存名から読める。
  - role判定だけの `require_manager_or_owner` / `require_owner` / `require_app_admin` は `get_current_user_minimal` に変更。
  - office association が必要な `require_active_billing` は `get_current_user_with_office` を明示。
- [x] 既存APIのレスポンスは変えない。
  - 既存 `get_current_user` は office付き依存として残し、既存endpoint/テストoverrideの互換性を維持。
  - endpoint大量移行は既存override前提を崩しやすいため、今回は依存境界の追加と代表依存の切り替えに限定。

実施結果:

- [x] RED確認:
  - `docker exec keikakun_app-backend-1 python -m pytest tests/api/test_deps_permissions.py -q`
  - 結果: `get_current_user_minimal` / `get_current_user_with_office` 未定義で `3 failed, 11 passed`
- [x] `k_back/app/api/deps.py` に `_get_current_user(load_office=...)` を追加し、トークン検証・Staff取得・削除済みスタッフ確認・パスワード変更後トークン無効化チェックを共通化。
- [x] `get_current_user_minimal` / `get_current_user_with_office` を追加し、必要な情報量を依存名で選べるようにした。
- [x] `tests/api/test_deps_permissions.py` に以下を追加:
  - 依存関数の公開/互換alias確認。
  - role依存が軽量依存を使うことの確認。
  - 課金依存がoffice付き依存を使うことの確認。
  - minimalが `office_associations` を eager load しないことのDB挙動確認。
  - with_officeが `office_associations.office` を eager load することのDB挙動確認。
- [x] GREEN確認:
  - `docker exec keikakun_app-backend-1 python -m pytest tests/api/test_deps_permissions.py -q`
    - `16 passed`
  - `docker exec keikakun_app-backend-1 python -m pytest tests/api/v1/test_mfa_admin.py tests/api/v1/test_office.py -q`
    - `30 passed`
  - `docker exec keikakun_app-backend-1 python -m py_compile app/api/deps.py`
    - 成功

## 優先度低

### 9. TODO/仮実装が利用者向け機能に残っている

詳細タスク:

- `md_files_design_note/task/todo/refactor/maintainability/todo_placeholder_cleanup.md`

該当箇所例:

- `k_front/components/admin/inquiry/InquiryReplyModal.tsx`
- `k_front/components/protected/app-admin/tabs/NewInquiriesTab.tsx`
- `k_back/app/services/employee_action_service.py`
- `k_back/app/api/v1/endpoints/admin_audit_logs.py`
- `k_back/app/crud/crud_welfare_recipient.py`

リスク:

- 実装済みなのか未実装なのか判断できない。
- 画面上は動いているように見えて、実際は仮データ/仮待機の可能性がある。

推奨リファクタ:

- TODOを「仕様未確定」「未実装」「削除予定」に分類する。
- 利用者に見える導線の仮実装はissue化し、期限を決める。

受け入れ要件:

- [x] TODO一覧がmd化される。
  - `todo_placeholder_cleanup.md` にP0/P1/P2、調査コマンド、対象外条件、TDD方針を整理。
- [ ] ユーザー導線にある仮実装はissueまたはタスクに紐づく。

### 10. 手動SQL/Alembic/運用ドキュメントが併存し、正が分かりづらい

該当箇所:

- `md_files_design_note/task/todo/refactor/performance/db_optimization_indexes.sql`
- `k_back/migrations/versions/*`
- 各種 `migration_*.sql` ドキュメント

リスク:

- 本番に何を適用したか追いづらい。
- NeonDB共通利用のため、手動反映漏れや二重適用が起きやすい。
- rollback手順がドキュメントとmigrationでずれる可能性がある。

推奨リファクタ:

- DB変更の正は原則Alembicに寄せる。
- 手動SQLは「確認用」「緊急用」「Alembic反映前の検証用」に限定する。
- 手動実行したSQLは日時、環境、結果を記録する。

受け入れ要件:

- [x] DB変更方針のmdがある。
  - `md_files_design_note/task/todo/refactor/maintainability/alembic/alembic_migration_reality_plan.md`
  - `md_files_design_note/task/todo/refactor/maintainability/alembic/alembic_baseline_check_20260701.md`
  - `md_files_design_note/task/todo/refactor/maintainability/alembic/cd_main.md`
- [x] 手動SQLとAlembicの役割が分かれている。
  - DB変更の正はAlembic migrationとする。
  - 手動SQLは確認用、調査用、緊急対応用に限定する。
  - 既存migrationと実DBが大きく乖離していたため、`baseline_20260701` を新しいAlembic管理開始地点として扱う。
- [x] PRテンプレートにmigration確認項目がある。
  - `md_files_design_note/pull_request/pull_request.md` にDB migration確認項目を追加。
- [x] CDでmigrationを実行する方針がある。
  - `cd_main.md` に Cloud Build 内で `alembic upgrade head` を Cloud Run deploy 前に実行する案を整理。
  - `DATABASE_URL=${_PROD_DATABASE_URL}` の受け渡し、secretをログに出さない注意、`stamp` を通常CDで実行しない方針を記録。
- [ ] main DBの `alembic_version` が `baseline_20260701` 以降に揃っていることを確認する。
- [ ] CD実行ログにDB URLやsecret値が出ていないことを確認する。
- [ ] 破壊的migrationを通常CDに混ぜない運用ルールをPR本文に明記する。

実施結果:

- [x] `db_fix_list.md` / `performance_checklist_implementation_review.md` の「手動SQLを正」とする記述を、Alembic正の方針へ更新した。
- [x] `p9q0r1s2t3u4_add_performance_optimization_indexes.py` 参照は、既存migrationと実DBの乖離を踏まえ、個別migrationではなく `baseline_20260701` 以後をAlembic管理する説明へ置き換えた。
- [x] `docker exec keikakun_app-backend-1 alembic heads` を確認し、`baseline_20260701 (head)` の単一headであることを確認した。

## 推奨する実行順

2026-07-02時点では、初期候補の多くは完了または部分完了している。次に使う実行順は以下。

1. Dashboardの一覧描画を `DashboardRecipientTable` へ分離する。
2. P6 AdminMenuのGoogle Calendar状態管理、スタッフMFA操作、事業所編集form状態をhookへ分離する。
3. role change側の通知共通化と監査ログ共通化を進める。
4. 課金状態マッピングのfrontend/backend照合テストを追加する。
5. Alembic CD運用の残確認を行う。

別issue扱い:

- Google Calendarのアプリ内カレンダー / `.ics` / Google自動同期縮退の仕様判断。
- TODO/仮実装のP0実装対応。

## 最初のTDD候補

### 認証Cookie共通化

- [x] local環境の通常ログインCookie optionが現行通りである。
- [x] production環境の通常ログインCookie optionが現行通りである。
- [x] MFAログインCookie optionが通常ログインと同じ共通関数を使う。
- [x] logoutのdelete cookie optionがset cookieと同じdomain/path/samesiteを使う。

### ログ整理

- [x] backend endpoint内に `print(` が残っていない。
- [x] frontend production対象コードに無条件の `console.log` が残っていない。
- [x] トークン、メール、個人名、支援計画本文、ファイル名をログ出力しない方針を `log_policy.md` に明文化した。

### 申請系共通化

- [ ] role change承認時の通知作成が共通helper経由で行われる。
- [x] employee action承認時の通知作成が `EmployeeActionNoticeService` 経由で行われる。
- [x] employee action側の既存通知文言と通知タイプは変わらない。

## 注意点

- いずれも一括リファクタは避ける。
- 既存の画面文言、APIレスポンス、DBスキーマを変えない範囲から始める。
- 課金は外部API・Webhook・バッチが絡むため、テストで現行挙動を固定してから変更する。
- Google Calendarは廃止・縮退・代替機能化を見込むため、既存自動同期の改善に深く投資する前に、アプリ内カレンダー/`.ics` への移行設計を固める。
- 巨大ファイルは「行数を減らすこと」自体を目的にせず、テスト可能な責務単位に分ける。

## 段階的リファクタリング方法

このリファクタリングは、保守性改善そのものが目的だが、既存機能の挙動を変えないことを最優先にする。特に認証、課金、利用者情報、申請、通知、Google Calendar関連は本番影響が大きいため、1PRで複数領域を同時に変更しない。

### 基本方針

- 1PRにつき1つの責務だけを対象にする。
- backendはTDDを前提に、先に現行挙動を固定するRedテストを書く。
- frontendは表示変更を伴わない抽出から始め、画面文言・導線・APIレスポンスを変えない。
- 外部API連携はadapter境界を作るだけに留め、同じPRで仕様変更しない。
- DB変更は原則Alembicを正とし、手動SQLは確認用または緊急用として扱う。
- ログ・TODO・命名整理は、業務ロジック変更PRと混ぜない。

### Phase 0: 現行挙動の固定

目的:

- 変更前に「壊してはいけない挙動」をテストとドキュメントで明確にする。
- 巨大ファイルをいきなり分割せず、変更対象の入力・出力・副作用を確認する。

実施内容:

- 対象機能の既存テストを実行し、失敗があれば先に記録する。
- 認証Cookie、課金状態遷移、申請通知、Google Calendar同期など、外部影響がある処理は現行挙動テストを追加する。
- 画面系は主要な表示条件とAPI呼び出し条件をチェックリスト化する。
- 本番ログに出してはいけない情報を整理する。

完了条件:

- [ ] 変更対象の正常系・主要分岐・失敗系がテストまたはチェックリストで確認できる。
- [ ] 既存テストの失敗が、今回変更によるものか既知の失敗か区別できる。
- [ ] 対象領域の「変えない挙動」がPR本文に書ける。

### Phase 1: 低リスクな整理

目的:

- 挙動を変えず、以降のリファクタリングを読みやすくする。

実施内容:

- backendの `print()` や不要なdebugログを削除する。
- frontendの無条件 `console.log` を削除または開発時のみの出力に寄せる。
- TODOを「仕様未確定」「未実装」「削除予定」に分類する。
- Cookie option、通知作成、権限判定など、重複している小さな処理をhelperへ抽出する。

完了条件:

- [ ] 本番コードに不要なdebug出力が残っていない。
- [ ] 抽出前後でAPIレスポンス、DB更新、画面表示が変わらない。
- [ ] helper抽出に対する単体テストがある。

### Phase 2: 責務境界の明確化

目的:

- 大きなService/Componentを、業務判断・DB更新・外部API・表示に分ける。

実施内容:

- backendでは、endpointから直接業務判断を減らし、ServiceまたはUseCaseへ寄せる。
- Service内では「判定関数」「DB更新」「外部API呼び出し」「通知/監査ログ」を分ける。
- frontendでは、API取得・フォーム状態・表示コンポーネントを分ける。
- 権限判定は画面ごとのインライン条件から共通関数へ移す。

完了条件:

- [ ] 変更対象ファイルの責務が説明できる単位に分かれている。
- [ ] 外部APIを呼ぶ処理が業務判定ロジックに直接混ざっていない。
- [ ] 表示コンポーネントはprops中心で描画できる。

### Phase 3: 高リスク領域の局所リファクタ

目的:

- 不具合が起きやすい領域を、小さな状態遷移・副作用単位で安全に整理する。

優先対象:

1. 課金状態遷移
2. 認証/MFA/Cookie
3. 申請/通知/監査ログ
4. 利用者/支援計画
5. Google Calendar縮退・代替機能化

実施内容:

- 課金は `trial_expired` / `payment_failed` / `canceling` / `canceled` の状態遷移表を先に固定する。
- 認証はCookie設定と削除を共通化し、MFA有無で差分が出ないようにする。
- 申請系は通知作成と承認/却下の共通フローを切り出す。
- Google Calendarは自動同期の改善より先に、期限イベント生成とGoogle同期を分離する。

完了条件:

- [ ] 状態遷移や権限判定が1箇所で読める。
- [ ] Webhook、バッチ、APIが同じ判定ロジックを使う。
- [ ] Google未接続でもアプリ内期限イベントまたは `.ics` 用データを作れる。

### Phase 4: DB/運用境界の整理

目的:

- 手動SQL、Alembic、運用確認手順の正を明確にする。

実施内容:

- DBスキーマ変更はAlembicへ寄せる。
- 手動SQLは確認用、緊急用、検証用に分類する。
- NeonDBのlocal/test/prod共通利用を前提に、実行環境と実行日時を記録する形式にする。
- indexや制約追加は、事前SELECT、migration、rollback確認をセットにする。

完了条件:

- [ ] 手動SQLとAlembicの差分確認手順がある。
- [ ] migration適用前後の確認SQLがある。
- [ ] rollbackまたは復旧方針がPRに書かれている。

### Phase 5: PR分割の目安

推奨PR粒度と現状:

- [x] PR 1: ログ整理のみ
- [x] PR 2: 認証Cookie option共通化
- [ ] PR 3: 申請通知helper抽出
  - employee action側は完了。role change側は未完了。
- [x] PR 4: 課金状態遷移の判定関数抽出
- [ ] PR 5: Google Calendar期限イベント生成と同期処理の分離
  - 仕様判断を別issueで先に行う。
- [ ] PR 6: frontend巨大コンポーネントのhook分離
  - Dashboardは進捗あり。P6 AdminMenuとDashboard table抽出が残る。
- [x] PR 7: `get_current_user()` の用途別依存分割

TODO/仮実装の実装修正は、`todo_placeholder_cleanup.md` を根拠に別issueで扱う。

各PRの受け入れ要件:

- [ ] 対象領域が1つに限定されている。
- [ ] 既存挙動を固定するテストがある。
- [ ] 仕様変更を含む場合は、リファクタPRとは分けている。
- [ ] 本番影響、rollback、手動確認方法がPR本文にある。

### 実施しないこと

- 全体再設計を1PRで行う。
- 巨大ファイルを行数削減だけを目的に分割する。
- 認証、課金、Google Calendar、DB migrationを同じPRで変更する。
- テストなしで課金状態遷移やCookie設定を変更する。
- 廃止・縮退予定のGoogle Calendar自動同期に大きな追加投資をする。
