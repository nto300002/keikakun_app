【task1】.icsファイルをGoogleCalendarにインポートする方法

【task2】アプリ内にカレンダー機能

**なぜ作ったか**

現事務所はDX化が進んでおり、Googleカレンダーを用いてスケジュール管理をしていたため、利用者の支援計画作成期限もそこに落とし込むことができれば便利になると思い、MVPに含めました。

**問題点**

実際に作成してみると、最小権限を設定する上でGoogleConsoleからサービスアカウントを設定する必要があり、（他事務所からカレンダーを見ることができてしまう恐れがあるため)利用するまでの設定がかなり煩雑なものになってしまいました。

また、Google Calendar 自体を日常業務で使っていない事業所も想定される。特にDX化が進んでいない事業所では、Google Calendar の導入・運用そのものが追加負担になるため、現在のGoogle自動同期機能は利用開始までのハードルに対して得られるメリットが薄い。

そのため、Google Calendar連携は今後の主軸機能として扱うのではなく、将来的な廃止も視野に入れる。

**今後の方針**

より多くの人に使ってもらうことを考えた時に、皆がGoogleカレンダーを使うわけではない点から、この機能を廃止するか、アプリ内にカレンダーを実装するもしくはアプリから.icsファイルというものをダウンロードし、それをGoogleCalendarにアップロードすることで利用者のスケジュールを反映させられる可能性があるため、方向性を変えることを検討しております。

今後は、Google Calendar連携を前提にした機能拡張ではなく、以下を優先する。

1. アプリ内で期限予定を確認できる状態を作る。
2. Google Calendarを使いたい事業所向けには、サービスアカウント不要の `.ics` ダウンロードを提供する。
3. 既存のサービスアカウント方式は、利用中の事業所への影響を避けるため当面は残す。
4. 利用状況と代替機能の整備状況を見て、サービスアカウント方式の新規提供停止または廃止を判断する。

## 現段階のアプリ実装との兼ね合い

現在の実装では、Google Calendar 連携は以下の構成になっている。

- Backend
  - `k_back/app/api/v1/endpoints/calendar.py`
    - サービスアカウントJSON、Google Calendar ID、接続確認、削除を扱う。
  - `k_back/app/services/calendar_service.py`
    - Google連携設定の作成/更新/削除。
    - `calendar_events` への期限イベント作成。
    - 未同期イベントのGoogle Calendar同期。
  - `k_back/app/models/calendar_events.py`
    - 更新期限、次回計画開始期限などのイベント情報を保存する。
  - `k_back/app/scheduler/calendar_sync_scheduler.py`
    - 未同期イベントをGoogle Calendarへ送る。
  - `k_back/app/services/google_calendar_client.py`
    - Google Calendar APIクライアント。
- Frontend
  - `k_front/components/protected/admin/AdminMenu.tsx`
    - 管理者設定 > 連携 でサービスアカウント方式のGoogle Calendar設定を行う。
  - `k_front/components/ui/google/CalendarLinkButton.tsx`
    - Google Calendar連携状況を確認する導線。
  - `k_front/lib/calendar.ts`
    - `/api/v1/calendar/*` を呼び出すクライアント。
  - `k_front/lib/api/deadline.ts`
    - 更新期限が近い利用者を取得するAPIクライアント。

重要な制約:

- 現在の `calendar_service.create_renewal_deadline_events()` / `create_next_plan_start_date_events()` は、事業所に接続済みGoogle Calendar設定がない場合、`calendar_events` を作成せずに終了する。
- `.ics` 出力やアプリ内カレンダー表示を実装する場合、Google Calendar接続の有無に関係なくイベント情報を作れる必要がある。
- そのため、Google同期そのものより先に「期限イベントを生成する責務」と「Googleへ同期する責務」を分離するのが安全。
- 既存のGoogle Calendar連携を即時削除すると、現在利用中の事務所に影響するため、段階的に並行運用する。
- ただし、サービスアカウント方式は設定難易度が高く、Google Calendarを使わない事業所には価値が届きにくいため、長期的には縮小または廃止候補として扱う。

## 実装方針

### 方針A: アプリ内カレンダーを主軸にして、既存Google同期は段階的に縮小する

推奨。

- `calendar_events` を「Google同期専用」ではなく「アプリ内の期限イベント台帳」として扱う。
- Google Calendar設定がなくても、更新期限・次回計画開始期限イベントは `calendar_events` に作成する。
- Google Calendar設定があり、接続済みの事務所だけ、当面は `sync_pending_events()` で外部同期する。
- `.ics` とアプリ内カレンダーは同じ `calendar_events` を参照する。
- 新規の主導線はアプリ内カレンダーと `.ics` ダウンロードに寄せ、サービスアカウント方式は「既存利用者向け」または「高度な連携」として扱う。

メリット:

- 既存の重複防止制約、イベント種別、期限計算を活かせる。
- `.ics` とアプリ内カレンダーで表示差分が出にくい。
- Google連携を使っている事務所への影響を抑えながら、Google非利用の事務所にも価値を出せる。
- 将来的にGoogle自動同期を廃止する場合も、アプリ内カレンダーと `.ics` は残せる。

デメリット:

- `calendar_events.google_calendar_id` が現在 `nullable=False` のため、Google未接続でも保存できるようDB設計の見直しが必要。
- 既存テストの「カレンダー未設定時はイベントを作らない」という期待を変更する必要がある。
- 既存Google同期を残す期間は、アプリ内カレンダー / `.ics` / Google同期の3系統を管理する必要がある。

### 方針B: `.ics` / アプリ内カレンダーは `deadlineApi.getAlerts()` から都度生成する

短期実装向き。ただし将来的なカレンダー機能としては弱い。

- 更新期限が近い利用者だけをAPIで取得し、`.ics` や画面表示に変換する。
- DBの `calendar_events` はGoogle同期専用のまま残す。

メリット:

- DB変更が少ない。
- Task 1 の検証が早い。

デメリット:

- 30日以内など「アラート対象」しか扱えず、長期の予定一覧には向かない。
- Google同期、`.ics`、アプリ内カレンダーでイベント定義が分散する。
- 後からTask 2へ進むと再設計が必要になりやすい。

結論:

- Task 1だけなら方針Bでも可能。
- Task 2まで見据えるなら方針Aで進める。
- ただし方針Aでも、Google自動同期の恒久維持を前提にしない。主軸はアプリ内カレンダーと `.ics` に移し、サービスアカウント方式は縮小・廃止判断ができる構造にする。

## 【task1】.icsファイルをGoogleCalendarにインポートする方法 実装案

### ゴール

管理者または権限のあるスタッフが、事業所の利用者の期限予定を `.ics` ファイルとしてダウンロードし、Google Calendarへ手動インポートできるようにする。

この方法では、サービスアカウントJSONやGoogle Cloud Console設定を不要にする。

### 対象イベント

初期実装では以下に絞る。

- 個別支援計画の更新期限
  - 既存: `CalendarEventType.renewal_deadline`
  - 現行の表示意図: 更新期限30日前から期限日までを確認できるようにする。
- 次の個別支援計画の開始期限
  - 既存: `CalendarEventType.next_plan_start_date`
  - 現行の表示意図: 計画開始から7日以内の対応期限を確認できるようにする。

### Backend実装案

#### 1. イベント生成責務をGoogle接続から切り離す

修正候補:

- `k_back/app/services/calendar_service.py`
- `k_back/app/models/calendar_events.py`
- `k_back/app/schemas/calendar_event.py`
- `k_back/app/crud/crud_calendar_event.py`

実装案:

- `calendar_events` をGoogle未接続でも作成できるようにする。
- `CalendarEvent.google_calendar_id` は `nullable=True` に変更する。
- Google同期時のみ、事業所の `office_calendar_accounts.google_calendar_id` を使う。
- `sync_status` は以下のどちらかに整理する。
  - 案1: Google未接続でも `pending` で保存し、同期処理側でGoogle設定がない事務所をスキップする。
  - 案2: `local_only` のような新statusを追加する。
- 最小変更なら案1。ただし将来的には案2の方が状態の意味が明確。

注意:

- DB変更が必要になる場合、本アプリの運用ルールに合わせて migration ファイルと同内容のSQLファイルを作成する。
- 既存のGoogle同期を残す場合、`sync_pending_events()` が `google_calendar_id IS NULL` のイベントで失敗しないようにする。

#### 2. `.ics` 生成サービスを追加

新規候補:

- `k_back/app/services/ics_export_service.py`
- `k_back/app/schemas/ics_export.py`

実装案:

- `calendar_events` から対象事務所のイベントを取得する。
- `text/calendar; charset=utf-8` のレスポンスとして返す。
- 外部ライブラリを追加せずに最小実装する場合は、RFC 5545 の最低限の形式を自前生成する。
- 追加ライブラリを許可するなら `icalendar` などを検討する。

最小フォーマット例:

```text
BEGIN:VCALENDAR
VERSION:2.0
PRODID:-//Keikakun//Deadline Calendar//JA
CALSCALE:GREGORIAN
METHOD:PUBLISH
BEGIN:VEVENT
UID:<calendar_event_id>@keikakun
DTSTAMP:20260629T000000Z
DTSTART;TZID=Asia/Tokyo:20260701T090000
DTEND;TZID=Asia/Tokyo:20260701T180000
SUMMARY:山田 太郎 更新期限まで残り1ヶ月
DESCRIPTION:個別支援計画の更新期限です。
END:VEVENT
END:VCALENDAR
```

エスケープ対象:

- 改行: `\n`
- カンマ: `\,`
- セミコロン: `\;`
- バックスラッシュ: `\\`

#### 3. `.ics` ダウンロードAPIを追加

追加候補:

- `GET /api/v1/calendar/export.ics`
- または `GET /api/v1/calendar/ics`

クエリ候補:

- `from_date`
- `to_date`
- `event_type`
- `recipient_id`

権限:

- owner / manager は事業所全体をエクスポート可能。
- employee は自分が閲覧できる範囲に限定するか、初期実装では不可にする。

レスポンス:

- `Content-Type: text/calendar; charset=utf-8`
- `Content-Disposition: attachment; filename="keikakun-calendar-YYYYMMDD.ics"`

#### 4. テスト

追加/修正候補:

- `k_back/tests/services/test_ics_export_service.py`
- `k_back/tests/api/v1/test_calendar_ics_export.py`
- 既存影響:
  - `k_back/tests/services/test_calendar_service.py`
  - `k_back/tests/integration/test_calendar_event_auto_creation.py`
  - `k_back/tests/integration/test_calendar_event_duplicate_prevention.py`

テスト観点:

- Google Calendar未設定でも `.ics` に必要なイベントを出力できる。
- `SUMMARY` / `DESCRIPTION` の日本語が壊れない。
- 改行やカンマを含む説明文がエスケープされる。
- 事業所Aのイベントが事業所Bの `.ics` に混ざらない。
- `from_date` / `to_date` で期間絞り込みできる。
- 権限のないユーザーは他事業所の `.ics` を取得できない。

### Frontend実装案

修正候補:

- `k_front/components/protected/admin/AdminMenu.tsx`
- `k_front/components/ui/google/CalendarLinkButton.tsx`
- `k_front/lib/calendar.ts`
- 必要なら新規: `k_front/components/calendar/IcsExportButton.tsx`

実装案:

- 管理者設定 > 連携 に「Googleカレンダー連携」と別に「カレンダーファイルをダウンロード」を追加する。
- 既存のサービスアカウント設定は「高度な連携」または「Google自動同期」として残す。
- `.ics` の使い方を短く表示する。
  - ダウンロードした `.ics` をGoogle Calendarにインポートする。
  - 再インポート時は重複する可能性があるため、取り込み先カレンダーを分けることを推奨する。
- ボタン押下で `/api/v1/calendar/export.ics` をダウンロードする。

受け入れ要件:

- [ ] Google Cloud Consoleやサービスアカウントを設定しなくても `.ics` をダウンロードできる。
- [ ] `.ics` をGoogle Calendarにインポートすると、利用者の期限予定が表示される。
- [ ] 事業所をまたいだイベント混入がない。
- [ ] 日本語の利用者名・説明文が文字化けしない。
- [ ] Google自動同期を使っている既存事務所の挙動が壊れない。
- [ ] Google Calendarを使わない事業所でも、`.ics` ダウンロード機能を無理に使わせない導線になっている。
- [ ] ライト/ダーク両テーマで導線が判読できる。

### リスク

- `.ics` は手動インポートなので、アプリ側で期限が変わってもGoogle Calendar側は自動更新されない。
- 同じ `.ics` を複数回インポートすると、Google Calendar側で重複表示される可能性がある。
- 既存 `calendar_events` の生成をGoogle接続から切り離す場合、DB制約と同期処理の見直しが必要。

## 【task2】アプリ内にカレンダー機能 実装案

### ゴール

Google Calendarを使わない事業所でも、アプリ内で利用者の更新期限・次回計画開始期限を月/週/一覧で確認できるようにする。

Task 1 の `.ics` 出力と同じイベントデータを参照し、Google利用の有無に依存しない期限管理機能にする。

### 実装範囲

初期実装では「予定作成カレンダー」ではなく「期限確認カレンダー」として作る。

対象:

- 個別支援計画の更新期限
- 次の個別支援計画の開始期限
- 必要に応じてアセスメント未完了アラート

対象外:

- 任意予定の手動作成
- スタッフ個人予定
- Google Calendarとの双方向同期
- ドラッグ&ドロップによる日付変更

### Backend実装案

#### 1. アプリ内カレンダー取得APIを追加

追加候補:

- `GET /api/v1/calendar/events`

クエリ候補:

- `from_date`
- `to_date`
- `event_type`
- `recipient_id`

レスポンス例:

```json
{
  "events": [
    {
      "id": "uuid",
      "event_type": "renewal_deadline",
      "title": "山田 太郎 更新期限まで残り1ヶ月",
      "description": "個別支援計画の更新期限です。",
      "start_datetime": "2026-07-01T09:00:00+09:00",
      "end_datetime": "2026-07-31T18:00:00+09:00",
      "welfare_recipient_id": "uuid",
      "welfare_recipient_name": "山田 太郎",
      "support_plan_cycle_id": 123,
      "support_plan_status_id": null
    }
  ]
}
```

権限:

- owner / manager は事業所内の全イベントを閲覧可能。
- employee は既存の利用者閲覧権限に合わせる。
- 他事業所のイベントは取得不可。

#### 2. イベントデータの生成元

推奨:

- Task 1 と同じく `calendar_events` を共通データソースにする。
- 期限作成/更新のたびに `calendar_events` を upsert する。
- 削除やサイクル再作成時は既存の `delete_event_by_cycle()` / `delete_event_by_status()` の考え方を利用する。

短期代替:

- 初期リリースでは `deadlineApi.getAlerts()` 相当のデータをカレンダー表示用に拡張して返す。
- ただし月表示や長期表示には弱いため、Task 2本実装では `calendar_events` ベースに寄せる。

#### 3. テスト

追加候補:

- `k_back/tests/api/v1/test_calendar_events.py`
- `k_back/tests/services/test_calendar_service.py` のイベント生成テスト拡張

テスト観点:

- Google Calendar未接続でもアプリ内カレンダーAPIがイベントを返す。
- `from_date` / `to_date` の範囲に合うイベントだけ返る。
- イベント種別で絞り込める。
- 他事業所のイベントは返らない。
- 削除済み利用者や削除済みサイクルのイベントが残らない。
- 更新期限変更時に古いイベントが重複しない。

### Frontend実装案

新規画面候補:

- `k_front/app/(protected)/calendar/page.tsx`
- `k_front/components/protected/calendar/AppCalendar.tsx`
- `k_front/components/protected/calendar/CalendarMonthView.tsx`
- `k_front/components/protected/calendar/CalendarEventList.tsx`
- `k_front/components/protected/calendar/CalendarFilters.tsx`

既存導線の修正候補:

- `k_front/components/protected/LayoutClient.tsx`
  - ヘッダーナビに `カレンダー` を追加するか、通知/メッセージ周辺から導線を置く。
- `k_front/components/protected/admin/AdminMenu.tsx`
  - 管理者設定 > 連携 のGoogle自動同期とは別に、アプリ内カレンダーの説明を追加する。
- `k_front/components/ui/google/CalendarLinkButton.tsx`
  - 将来的には `CalendarLinkButton` からGoogle専用説明を分離し、`.ics` とアプリ内カレンダーの導線へ置き換える。

UI案:

- 上部:
  - 月移動
  - 今日へ戻る
  - 表示切替: 月 / 一覧
  - `.ics` ダウンロード
- フィルター:
  - イベント種別
  - 利用者名検索
  - 期限超過のみ
- 月表示:
  - 日付ごとにイベントを最大数件表示。
  - クリックでその日のイベント一覧を表示。
- 一覧表示:
  - 期限が近い順に表示。
  - 利用者詳細または個別支援計画画面へ遷移。

受け入れ要件:

- [ ] Google Calendar未接続の事業所でも、アプリ内カレンダーを表示できる。
- [ ] 更新期限と次回計画開始期限がカレンダー上で確認できる。
- [ ] 月表示と一覧表示を切り替えられる。
- [ ] イベントから対象利用者の詳細または個別支援計画へ遷移できる。
- [ ] `.ics` ダウンロード導線がアプリ内カレンダー画面にもある。
- [ ] owner / manager / employee の権限で表示範囲が破綻しない。
- [ ] ライト/ダーク両テーマで判読できる。
- [ ] 既存のダッシュボード、期限アラート、通知/メッセージ導線に影響しない。

### 段階的移行案

#### Phase 1: `.ics` ダウンロードを追加

- Google自動同期は既存利用者向けに残す。
- 管理者設定 > 連携 に `.ics` ダウンロードを追加。
- DB設計をできるだけ小さく変更する。
- 新規利用者への主説明はサービスアカウント方式ではなく、`.ics` またはアプリ内カレンダーに寄せる。

#### Phase 2: アプリ内カレンダー閲覧を追加

- `/calendar` 画面を追加。
- `calendar_events` を事業所内予定の共通データソースにする。
- Google未接続でも表示できるようにする。
- アプリ内カレンダーを標準機能として扱い、Google自動同期は補助機能に下げる。

#### Phase 3: Google自動同期の扱いを再判断

- 利用状況を見て、サービスアカウント方式を以下のどちらかにする。
  - 高度な連携として残す。
  - 新規設定を停止し、既存事務所のみ維持する。
  - 既存事務所への告知期間を設けたうえで廃止する。

判断基準:

- サービスアカウント方式の設定完了率が低い。
- Google Calendar連携の利用事務所が少ない。
- アプリ内カレンダーと `.ics` で主要ユースケースを代替できている。
- Google Calendar連携の問い合わせ・設定支援コストが高い。

## 利用者ダッシュボードからの期限カレンダー導線要件

### 背景

利用者ダッシュボードには、計画期限超過、計画期限間近、アセスメント未完了などの期限系サマリーがすでに表示されている。

期限確認の主導線をGoogle自動同期ではなくアプリ内機能へ寄せる方針に合わせ、利用者一覧周辺から期限カレンダーへ直接遷移できる導線を追加する。

### UI配置要件

- 利用者ダッシュボードの `利用者追加` ボタンの右側に、`期限カレンダー表示` ボタンを追加する。
- 既存の `利用者追加`、`PDF一覧`、`表示リセット` の操作導線を崩さない。
- ボタンは期限確認の導線であり、Google Calendar自動同期設定の導線ではない。
- 初期文言候補:
  - `期限カレンダー表示`
  - 画面幅が狭い場合は `期限カレンダー` でも可。
- アイコンを使う場合はカレンダー系アイコンを用いる。

### 期限カレンダー画面/モーダル要件

`期限カレンダー表示` から、以下を確認できる画面またはモーダルを開く。

- アプリ内期限カレンダー
  - 更新期限、期限間近、期限超過、アセスメント未完了など、期限管理に関係する予定を確認できる。
  - 少なくとも月表示または一覧表示のどちらかを提供する。
  - 将来的には月表示 / 一覧表示の切り替えを想定する。
- `.ics` ファイルダウンロード
  - 表示中または指定期間内の期限予定を `.ics` としてダウンロードできる。
  - Google Calendarを使う事業所は、この `.ics` を手動インポートできる。
  - サービスアカウント設定を必須にしない。
- Google Calendar反映チュートリアル
  - `.ics` ファイルをGoogle Calendarへインポートする手順をモーダルで確認できる。
  - Google Cloud Console、サービスアカウント、JSONキー設定を前提にしない。
  - 「自動同期」ではなく「手動インポート」であることを明記する。

### チュートリアルモーダル要件

- `Google Calendarに反映する方法` のようなユーザー向け文言で開ける。
- 以下の手順を簡潔に表示する。
  1. アプリから `.ics` ファイルをダウンロードする。
  2. Google Calendarを開く。
  3. 設定 > インポート/エクスポートを開く。
  4. ダウンロードした `.ics` ファイルを選択する。
  5. 反映先カレンダーを選び、インポートする。
- 注意書き:
  - `.ics` は手動インポートのため、アプリ側で期限が変わった場合は再ダウンロード/再インポートが必要。
  - 既存のGoogle自動同期とは別機能として扱う。
  - Google Calendarを使わない事業所は、アプリ内期限カレンダーだけで確認できる。

### 受け入れ要件

- [ ] 利用者ダッシュボードの `利用者追加` ボタン右側に `期限カレンダー表示` 導線がある。
- [ ] `期限カレンダー表示` からアプリ内の期限カレンダーを確認できる。
- [ ] 期限カレンダーから `.ics` ファイルをダウンロードできる。
- [ ] `.ics` ダウンロードはGoogle Calendarサービスアカウント未設定でも利用できる。
- [ ] Google Calendarへ `.ics` を手動インポートするチュートリアルモーダルを開ける。
- [ ] チュートリアルでは、サービスアカウント方式ではなく `.ics` 手動インポート方式を説明する。
- [ ] 既存の利用者追加、PDF一覧、表示リセット、絞り込み操作に影響しない。

### リスク

- `calendar_events` を共通データソースに変える場合、既存Google同期テストの期待値変更が必要。
- カレンダーUIを作ると、期限変更時のイベント更新漏れが利用者に見えやすくなる。
- `.ics`、アプリ内カレンダー、Google同期の3経路が並行すると、同じ予定の見え方がずれる可能性がある。

### 実装前に決めること

- [ ] `.ics` は「全期間」ではなく、初期表示として何ヶ月分を出すか。
- [ ] `calendar_events.google_calendar_id` をnullableにするか、アプリ内用に別テーブルを作るか。
- [ ] Google未接続時の `sync_status` をどう表現するか。
- [ ] アプリ内カレンダーの初期導線をヘッダーに置くか、通知/メッセージページに置くか。
- [ ] employee権限にカレンダー閲覧を許可するか。
- [ ] サービスアカウント方式の新規設定導線を残すか、非推奨表示にするか。
- [ ] 将来的にGoogle自動同期を廃止する場合の告知・移行期間をどう設けるか。
