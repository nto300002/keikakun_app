ログイン時に異様にレスポンス時間がかかることがある

しばらくログインしていない、自動的にログアウトされた後のログイン、朝などに時間がかかりやすい

MFA認証に時間がかかりやすい

→全体的なパフォーマンス改善

loading画面において、5秒以上かかる時には更新を促す

認証画面でも登録ボタンを押した時に登録ボタンないにloadingを実装する

## 現段階の調査要点

調査日: 2026-06-29

ローカルDBは小規模だったため、実測での再現性は低い。現時点では、コードパスと実DBインデックス状況から見たボトルネック候補として整理する。

## 症状から見た原因仮説

- 朝、久々のログイン、自動ログアウト後に遅い場合、アプリ/DB/コンテナのコールドスタート、DB接続再確立、ログイン直後のAPI集中が重なっている可能性が高い。
- MFA認証そのものはTOTP検証だけなら重くないが、MFA成功後に初期表示用APIが一斉に走るため、ユーザーには「MFAが遅い」と見えやすい。
- ログイン直後に通知、期限アラート、Push購読、Dashboard、Billing、CurrentUser、Office取得が重なっている。

## アプリ側ボトルネック候補

### 1. ログイン/MFA後の `getCurrentUser()` 重複

該当箇所:

- `k_front/components/auth/LoginForm.tsx`
- `k_front/app/auth/mfa-verify/page.tsx`
- `k_front/components/protected/dashboard/Dashboard.tsx`
- `k_back/app/api/deps.py`

内容:

- ログイン成功後、フロントで `authApi.getCurrentUser()` を追加実行して遷移先を決めている。
- Dashboard初期表示でも `authApi.getCurrentUser()` を再度取得している。
- 各認証APIでは `deps.get_current_user()` が毎回 Staff + OfficeStaff + Office をDBから読む。

影響:

- ログイン直後に同じユーザー情報取得が複数回走る。
- 各APIで認証依存処理が重複し、DBアクセスが増える。

改善案:

- 認証レスポンスに最低限の `role` / `office_id` / `has_office` を含め、ログイン直後の追加 `getCurrentUser()` を削減する。
- Dashboard初期表示では `dashboard` APIのレスポンスに含まれる `staff_role` / `office_id` を活用し、不要な `getCurrentUser()` を減らせるか確認する。
- `get_current_user()` のOffice eager loadが必要なAPIと不要なAPIを分ける。

### 2. 保護レイアウト初期処理が重い

該当箇所:

- `k_front/components/protected/LayoutClient.tsx`

初回マウント時に走る処理:

- CSRFトークン初期化
- 事業所情報取得
- 未読通知件数取得
- 通知設定取得
- 期限アラート全件取得
- Push通知の自動購読

影響:

- Dashboard初期表示APIと同時に複数APIが走る。
- 画面表示に必須でない通知/Push処理が初期表示を圧迫する可能性がある。

改善案:

- 画面表示に必須な処理と後回しでよい処理を分ける。
- 通知設定、期限アラート、Push購読は初期描画後に遅延実行する。
- 期限アラートのトースト表示は同一ブラウザセッションで1回に制限する。

### 3. Dashboard初期表示で3 API並列

該当箇所:

- `k_front/components/protected/dashboard/Dashboard.tsx`

内容:

- `authApi.getCurrentUser()`
- `dashboardApi.getDashboardData()`
- `billingApi.getBillingStatus()`

影響:

- Dashboard表示時に認証依存処理が3回分走る。
- APIは並列だが、DB側には同時負荷としてかかる。

改善案:

- `dashboardApi.getDashboardData()` に必要な課金制限情報を含められるか検討する。
- BillingContextとDashboard内のbilling取得が重複していないか確認する。
- 初期表示に不要な情報は遅延取得する。

## DB/API側ボトルネック候補

### 1. 期限アラートAPIが全件取得後にPythonでページング

該当箇所:

- `k_back/app/services/welfare_recipient_service.py`
- `WelfareRecipientService.get_deadline_alerts()`

内容:

- 更新期限アラートを取得。
- アセスメント未完了候補を全件取得。
- `deliverables` を `selectinload` し、Python側でアセスメントPDF有無を判定。
- 最後に `alerts[offset:offset + limit]` でページングしている。

影響:

- 期限アラート対象が増えると、ログイン時通知やヘッダーホバーが重くなる。
- `limit` を指定してもDB取得量は減らない。

改善案:

- DB側で `LIMIT / OFFSET` を適用する。
- アセスメント未完了判定は `NOT EXISTS` で `plan_deliverables` を見る。
- ログイン時トースト用は最大件数を決める。
- noticeページ等の一覧用APIと、ログイン時トースト用APIを分ける。

### 2. 通知未読件数がCOUNTではなく全件取得

該当箇所:

- `k_back/app/api/v1/endpoints/notices.py`
- `k_back/app/crud/crud_notice.py`

内容:

- `/notices/unread-count` で未読通知を全件取得し、`len()` で件数を返している。
- 通知一覧も全件取得後にPython側でページングしている。

影響:

- 通知が増えるほどログイン直後の未読件数取得が重くなる。
- noticeページ表示もデータ量に比例して重くなる。

改善案:

- 未読件数は `SELECT COUNT(*)` に変更する。
- 通知一覧はDB側で `OFFSET / LIMIT` を適用する。
- `notices(recipient_staff_id, is_read, created_at DESC)` の複合インデックスを追加する。
- `notices(recipient_staff_id, created_at DESC)` の複合インデックスを追加する。

### 3. Dashboard APIが重い集計を複数回実行

該当箇所:

- `k_back/app/api/v1/endpoints/dashboard.py`
- `k_back/app/crud/crud_dashboard.py`

内容:

- `count_office_recipients`
- `count_filtered_summaries`
- `get_filtered_summaries`
- `billing.get_by_office_id`

影響:

- `count_filtered_summaries` と `get_filtered_summaries` で似たサブクエリを2回組み立てている。
- 利用者数、サイクル数、ステータス数が増えると重くなる。

補足:

- 実DBではDashboard系インデックスは反映済みだった。
- ただし件数が増えると、countと一覧取得の二重実行は残る。

改善案:

- 初期表示で `filtered_count` が必須か確認する。
- 初期表示ではcountを省略し、必要時だけ取得する案を検討する。
- サマリー集計用の軽量APIを別に切る。

## 追加調査で見つかったボトルネック候補

調査日: 2026-06-30

既存の「期限アラート」「通知未読件数」「Dashboard集計」以外で、現行実装から見た候補を整理する。

### 追加候補チェックリスト

- [x] MFA/ログイン処理の成功パス詳細ログを削減する。
- [x] 通知の保持上限削除を全件取得 + 1件ずつdeleteからDB側一括削除へ変更する。
- [ ] PDF一覧APIの署名付きURL生成タイミングと件数取得を見直す。
- [ ] Dashboard検索の `ILIKE '%word%'` / `concat()` 依存を見直す。
- [ ] Google Calendar同期/削除系の外部API逐次処理をバックグラウンド化する。
- [ ] 開発/本番に残る `console.log` / debugログの出力方針を整理する。
- [ ] CSRF初期化APIをログイン直後の必須APIから外せるか検討する。

今回のbackend実装では、破壊的変更を避けるため、通知保持上限削除の一括化とMFA/ログイン成功パスログの抑制を先行する。PDF一覧、Dashboard検索、Google Calendar同期、CSRF初期化は仕様・UX・外部API影響が大きいため、別タスクで計測後に扱う。

### 4. MFA/ログイン処理のログ出力が多い

該当箇所:

- `k_back/app/api/v1/endpoints/auths.py`
- `k_back/app/services/mfa.py`
- `k_back/app/models/staff.py`

内容:

- MFA検証時に temporary token 長、TOTPコード、復号成否、secret長などを複数回 `logger.info()` で出している。
- `Staff.get_mfa_secret()` でも復号のたびに info ログを出している。
- ログイン時のCookie設定でも環境変数・Cookie option系の info ログが毎回出る。

影響:

- MFA/ログインのリクエストごとにログI/Oが増える。
- 本番ログ基盤やDocker logの出力量が増え、遅延調査時にノイズになる。
- TOTPコードやメールアドレスに近い情報がログに出ており、性能だけでなく運用・セキュリティ面でもリスクがある。

改善案:

- 通常成功パスの詳細ログは `debug` に下げる。
- TOTPコード、secret長、メールアドレスなどはログから除外する。
- MFA失敗・復号失敗など調査に必要なイベントのみ `warning` / `error` で残す。

### 5. 通知の保持上限削除が全件取得 + 1件ずつdelete

該当箇所:

- `k_back/app/crud/crud_notice.py`
- `CRUDNotice.delete_old_notices_over_limit()`
- 呼び出し元: `role_change_service.py` / `employee_action_service.py`

内容:

- 事務所の通知を全件取得して `notices[limit:]` をPython側で切り出している。
- 削除対象を1件ずつ `db.delete()` している。
- 承認通知・社員アクション通知の作成時に呼ばれるため、通知が多い事務所ほど通知作成が重くなる。

影響:

- 通知件数が増えると、通知作成や承認/却下処理のレスポンスが悪化する。
- ログイン直後の通知取得だけでなく、通知を作る操作にも負荷が偏る。

改善案:

- 削除対象IDだけを `OFFSET limit` 以降で取得し、`DELETE ... WHERE id IN (...)` にする。
- 可能なら `created_at` と `id` で安定ソートし、DB側で一括削除する。
- `notices(office_id, created_at DESC)` インデックスを使える形にする。

### 6. PDF一覧APIで一覧取得 + 件数取得 + 署名付きURL生成を同期的に実行

該当箇所:

- `k_front/app/(protected)/pdf-list/page.tsx`
- `k_back/app/services/support_plan_service.py`
- `k_back/app/crud/crud_support_plan.py`

内容:

- フロント側でPDF一覧表示前に `authApi.getCurrentUser()` を追加実行している。
- バックエンドでは一覧取得と総件数取得を別クエリで実行している。
- 取得した各PDFに対してS3署名付きURLを1件ずつ生成している。

影響:

- PDFが多い事務所では、一覧表示時のDB負荷とS3署名URL生成コストが積み上がる。
- `pdf-list` へ遷移した時に、認証情報取得とPDF一覧取得が直列になり体感待ち時間が伸びる。

改善案:

- `currentUser.office.id` は保護レイアウトや認証コンテキストから渡せないか確認する。
- 初期一覧では署名付きURLを返さず、ユーザーが開く/ダウンロードするタイミングで発行する案を検討する。
- 総件数が不要な画面では `limit + 1` で `has_more` 判定に切り替える。
- PDF一覧向けに `plan_deliverables(uploaded_at DESC)`、`plan_deliverables(deliverable_type, uploaded_at DESC)`、`support_plan_cycles(office_id, id)` の必要性をEXPLAINで確認する。

### 7. Dashboard検索が部分一致 `ILIKE '%word%'` と `concat()` に依存

該当箇所:

- `k_back/app/crud/crud_dashboard.py`
- `CRUDDashboard.get_filtered_summaries()`
- `CRUDDashboard.count_filtered_summaries()`

内容:

- 氏名/ふりがな検索で `ILIKE '%word%'` を複数カラムに対して実行している。
- ソートでも `concat(last_name_furigana, first_name_furigana)` を使う。
- 通常のB-treeインデックスだけでは部分一致検索や式ソートに効きづらい。

影響:

- 利用者数が増えた事務所で検索・絞り込みが遅くなりやすい。
- 検索時も一覧クエリとcountクエリの両方で同じ条件が走るため、負荷が二重になる。

改善案:

- 検索要件が前方一致でよいなら `word%` に寄せる。
- 部分一致を維持するなら PostgreSQL の `pg_trgm` + GIN index を検討する。
- `full_name_furigana` のような検索/ソート用正規化カラム、または式インデックスを検討する。
- 検索中は `filtered_count` を省略する、または遅延取得する。

### 8. Google Calendar同期/削除系が外部APIを逐次処理している

該当箇所:

- `k_back/app/services/calendar_service.py`
- `CalendarService.sync_pending_events()`
- `CalendarService.delete_event_by_cycle()`
- `CalendarService.delete_event_by_status()`

内容:

- 未同期イベントを取得後、事務所ごと・イベントごとにGoogle Calendar APIを逐次呼び出している。
- 事務所ごとにサービスアカウントキー復号、クライアント作成、認証を行う。
- 削除系でも対象イベントに対して外部API呼び出しが同期的に走る。

影響:

- Google Calendar連携を使っている事務所では、支援計画更新や削除操作が外部API遅延の影響を受ける。
- Google Calendarを使わない事務所も多い前提では、同期処理が通常操作の体感速度を悪化させない設計が必要。

改善案:

- ユーザー操作の同期レスポンスから外部API呼び出しを切り離し、バックグラウンドジョブ化する。
- 事務所ごとのCalendar設定が未接続なら早期returnし、イベント取得や復号処理を避ける。
- 同期対象数に上限を設け、失敗時は指数バックオフや次回再試行に回す。

### 9. 開発/本番に残る `console.log` / debugログが多い

該当箇所:

- `k_front/lib/support-plan.ts`
- `k_front/lib/pdf-deliverables.ts`
- `k_front/app/(protected)/pdf-list/page.tsx`
- `k_front/components/auth/LoginForm.tsx`
- `k_back/app/services/welfare_recipient_service.py`
- `k_back/app/services/dashboard_service.py`

内容:

- フロントのPDF/支援計画/ログイン周辺に詳細な `console.log` が残っている。
- バックエンドにも deadline/dashboard 周辺の debugログが多い。

影響:

- ブラウザ・Dockerログのノイズが増え、遅延調査のウォーターフォールや重要ログを追いづらい。
- ログ出力自体も低速端末や大量操作時には無視できないコストになる。

改善案:

- 本番ビルドではdebugログを出さない方針を明確化する。
- フロントは `process.env.NODE_ENV !== 'production'` でガードするか、専用debug loggerに寄せる。
- バックエンドは成功パスの詳細ログを `debug` に下げ、失敗・遅延・外部APIエラーだけを構造化ログで残す。

### 10. 認証後・保護ページでCSRF初期化が追加APIになる

該当箇所:

- `k_front/components/protected/LayoutClient.tsx`
- `k_front/lib/csrf.ts`
- `k_back/app/api/v1/endpoints/csrf.py`

内容:

- 保護レイアウト初回マウント時に `initializeCsrfToken()` が走る。
- ログイン/MFA直後のDashboard初期表示と同時に、CSRF取得APIも追加で走る。

影響:

- 1回あたりは軽いが、ログイン直後のAPI集中の一部になっている。
- コールドスタート/DB接続再確立が絡む時間帯では、軽量APIでも待ち行列を増やす可能性がある。

改善案:

- ログイン/MFA成功レスポンスでCSRFトークンを同時に返せるか検討する。
- すでに有効なCSRFトークンがある場合は初期化APIをスキップする。
- 初期描画に不要なら、ユーザー操作前まで遅延して取得する。

## 実DBインデックス確認結果

実DBでは以下のDashboard系インデックスは確認済み:

- `idx_support_plan_cycles_recipient_latest`
- `idx_support_plan_statuses_cycle_latest`
- `idx_welfare_recipients_furigana`
- `idx_office_welfare_recipients_office`
- `idx_support_plan_cycles_latest_renewal`

不足候補:

- `notices(recipient_staff_id, is_read, created_at DESC)`
- `notices(recipient_staff_id, created_at DESC)`
- `support_plan_cycles(office_id, is_latest_cycle, next_renewal_deadline)`
- `plan_deliverables(plan_cycle_id, deliverable_type)`

## 改善優先度

1. 期限アラートAPIの全件取得/ Pythonページングを修正する。
2. 通知未読件数を `COUNT(*)` に変更し、通知一覧をDBページングにする。
3. ログイン/MFA後の `getCurrentUser()` 重複を削減する。
4. 保護レイアウト初期処理を段階ロードにする。
5. Dashboard APIのcount/list二重クエリを軽量化する。
6. 5秒以上のloading時に更新案内を出す。
7. 認証画面の登録/ログイン/MFAボタン内loading表示を整理する。

## 受け入れ要件候補

- [ ] ログイン直後の必須API数を現状より削減する。
- [ ] MFA成功後、Dashboard表示までの体感待ち時間が短くなる。
- [ ] `/notices/unread-count` は全件取得ではなく `COUNT(*)` を使う。
- [ ] 期限アラートAPIは `limit` 指定時にDB側で取得件数を制限する。
- [ ] 期限通知は画面更新やヘッダーホバーのたびに重複表示されない。
- [ ] 5秒以上loadingが続いた場合、更新を促す文言を表示する。
- [ ] 認証画面の送信ボタンは処理中にloading状態を表示し、二重送信を防ぐ。

## 追加で確認したいこと

- [ ] 本番相当DBで `EXPLAIN ANALYZE` を取得する。
- [ ] 朝/久々ログイン時にAPIごとの所要時間をログで確認する。
- [ ] Render等のホスティング環境でスリープ/コールドスタートが発生しているか確認する。
- [ ] DB接続プールのサイズ、タイムアウト、接続再利用状況を確認する。
- [ ] ブラウザNetworkタブでMFA成功後からDashboard表示までのウォーターフォールを確認する。
