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
