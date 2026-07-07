# app-admin 機能全般 TODO

作成日: 2026-07-02

## 目的

app-admin に関する既存メモを、実装済みコードと突き合わせて TODO 化する。

元メモの主な要望:

- 管理者からの通知、返信がすべてその他扱いになるため、お知らせに入ってきて欲しい。
- 管理者が問い合わせへ返信した場合、相手のメールアドレスにも通知される。
  - アプリ内からの問い合わせ: アプリ内通知 + メール返信。
  - アプリ外からの問い合わせ: メール返信。
- 全事業所向けお知らせ POST が失敗する。
  - `api/v1/admin/announcements`
  - ブラウザ上では CORS エラーとして見えている。
- お知らせ送信リクエストのパフォーマンス面も確認する。

## 実装確認メモ

- app-admin ルーターは `k_back/app/api/v1/api.py` で `/admin/inquiries`、`/admin/announcements`、`/admin/offices` などが登録済み。
- 問い合わせ返信 API は `k_back/app/api/v1/endpoints/admin_inquiries.py` の `POST /admin/inquiries/{inquiry_id}/reply`。
  - リクエストは `body` と `send_email`。
  - `send_email=true` かつ `sender_email` がある場合のみメール送信を試行。
  - メール送信失敗はログのみで、返信処理自体は成功扱い。
- 問い合わせ返信のアプリ内通知は `k_back/app/crud/crud_inquiry.py` の `create_reply()`。
  - `MessageType.inquiry_reply` の `Message` を作成。
  - 元問い合わせの `sender_staff_id` がある場合のみ `MessageRecipient` を作成。
  - アプリ外問い合わせなど `sender_staff_id` がない場合はアプリ内通知先なし。
- バックエンド enum には `MessageType.inquiry_reply` が存在する。
- フロントの `k_front/types/message.ts` には `MessageType.INQUIRY_REPLY` がない。
- フロントの `k_front/components/notice/MessagesTab.tsx` はフィルターが `all` / `unread` / `personal` / `announcement` のみ。
  - `announcement` フィルターは `MessageType.ANNOUNCEMENT` だけを API に渡す。
  - `inquiry_reply` を「お知らせ」に含める処理がない。
- フロントの `k_front/components/notice/MessageCard.tsx` は `inquiry_reply` 用の表示ラベル・スタイルがない。
- app-admin ダッシュボードの問い合わせタブは `k_front/components/protected/app-admin/AppAdminDashboard.tsx` から `tabs/InquiriesTab.tsx` が使われている。
- `k_front/components/protected/app-admin/InquiryReplyModal.tsx` は `k_front/lib/api/inquiry.ts` の正しい `replyToInquiry(inquiryId, { body, send_email })` を使っている。
- 一方で `k_front/lib/api/appAdmin.ts` に残っている `replyToInquiry(inquiryId, content)` は `{ content }` を POST しており、バックエンド仕様と不一致。
- `k_front/lib/api/appAdmin.ts` の `markInquiryAsRead()` は `/admin/inquiries/{id}/read` を叩くが、バックエンドに該当ルートが見当たらない。
- app-admin お知らせ POST は `k_back/app/api/v1/endpoints/admin_announcements.py`。
  - `require_app_admin` と `validate_csrf` が必須。
  - 全スタッフを ORM オブジェクトとして取得し、`current_user` だけを除外。
  - `all_staff[0].office_associations` を eager load なしで参照しており、async lazy load 起因の `MissingGreenlet` / 500 の可能性がある。
  - `office_id` は最初の送信対象スタッフの所属事務所から取っているため、「全事業所向け」の意味とズレる可能性がある。
- お知らせ作成本体 `k_back/app/crud/crud_message.py` の `create_announcement()` は recipient を 500 件ずつ bulk insert しており、保存処理側の基本的な chunking は存在する。
- `k_front/lib/http.ts` は CSRF トークンがメモリにある場合だけ変更系リクエストへ `X-CSRF-Token` を付ける。app-admin お知らせ POST 前に CSRF が必ず取得済みかは別途確認が必要。

## P0: 管理者返信をユーザー側の「お知らせ」で扱えるようにする

### 課題

バックエンドは `inquiry_reply` を作成しているが、フロント側の通知型・表示・フィルターが `inquiry_reply` を知らない。
そのため管理者からの問い合わせ返信が専用表示されず、ユーザー期待の「お知らせ」導線にも入らない。

### TODO

- [ ] Red: `MessageType.INQUIRY_REPLY` が扱えることをフロントの単体テストで固定する。
- [ ] Red: `MessageCard` が `inquiry_reply` を「管理者からの返信」または「問い合わせ返信」として表示することをテストする。
- [ ] Red: `MessagesTab` の「お知らせ」フィルターで `announcement` と `inquiry_reply` が取得・表示対象になることをテストする。
- [ ] Green: `k_front/types/message.ts` に `INQUIRY_REPLY = 'inquiry_reply'` を追加する。
- [ ] Green: `k_front/components/notice/MessageCard.tsx` に `inquiry_reply` 用のラベル・アイコン・スタイルを追加する。
- [ ] Green: `k_front/components/notice/MessagesTab.tsx` の「お知らせ」扱いを調整する。
  - バックエンドが単一 `message_type` しか受けない現状では、候補は次のどちらか。
  - 案A: 「お知らせ」フィルター時は API を `message_type` なしで取得し、クライアントで `announcement` / `inquiry_reply` に絞る。
  - 案B: バックエンド `GET /messages/inbox` に複数 `message_types` 指定を追加する。
- [ ] Refactor: 「お知らせ」という UI 名に `announcement` 以外を含める仕様を helper に切り出し、表示条件を分散させない。
- [ ] Regression: ログイン済みユーザーが問い合わせし、app-admin が返信した後、ユーザー側メッセージ画面の「お知らせ」に返信が出ることを e2e または統合テストで確認する。

## P0: 問い合わせ返信のメール送信ポリシーを仕様に合わせる

### 課題

現状は `send_email` が false の場合、メールアドレスがあってもメール送信されない。
元メモの仕様では、管理者返信時に以下が期待されている。

- アプリ内からの問い合わせ: アプリ内通知 + メール返信。
- アプリ外からの問い合わせ: メール返信。

現在の実装は「管理者がチェックボックスでメール送信を選んだ場合のみメール」なので、仕様より任意度が高い。

### TODO

- [ ] Red: ログイン済み問い合わせで `sender_staff_id` と `sender_email` がある場合、返信により `MessageRecipient` とメール送信キュー/送信呼び出しが両方発生することを backend test で固定する。
- [ ] Red: アプリ外問い合わせで `sender_staff_id` がなく `sender_email` がある場合、`MessageRecipient` は作らずメール送信が発生することを backend test で固定する。
- [ ] Red: `sender_email` がない問い合わせではメール送信を行わず、可能ならアプリ内通知のみになることを backend test で固定する。
- [ ] Green: `admin_inquiries.reply_to_inquiry()` の `send_email` の扱いを、仕様に沿って自動化する。
  - 候補: `sender_email` がある返信は原則メール送信する。
  - 管理者がメール送信を明示的に外せる必要があるかは別仕様として判断する。
- [ ] Green: フロントの返信モーダルの初期値・文言を仕様に合わせる。
  - アプリ内問い合わせ + メールあり: 「アプリ内通知とメールで返信」。
  - アプリ外問い合わせ + メールあり: 「メールで返信」。
  - メールなし: 「アプリ内通知のみ」または送信不可理由を表示。
- [ ] Refactor: `send_email` が単なる UI チェック値なのか、バックエンド側の配信ポリシーなのか責務を明確にする。

## P0: app-admin 全事業所向けお知らせ POST の失敗原因を潰す

### 課題

ブラウザでは CORS エラーとして見えているが、実装上は CORS 設定だけでなく、CSRF 未設定、認証/権限エラー、バックエンド 500、preflight 失敗が同じように見える可能性がある。
特に `admin_announcements.py` では `all_staff[0].office_associations` を eager load なしで参照しており、async lazy load の 500 が疑わしい。

### TODO

- [ ] Red: app_admin + 有効 CSRF で `POST /api/v1/admin/announcements` が 201 を返し、全送信対象に `MessageRecipient` を作る backend integration test を追加する。
- [ ] Red: 送信対象の先頭スタッフに `office_associations` がない場合でも 500 にならない test を追加する。
- [ ] Red: 送信対象が存在しない場合に 400 が返る test を追加する。
- [ ] Red: CSRF なしの POST が期待通り拒否され、フロントで原因が分かるエラーになることを確認する。
- [ ] Green: `all_staff[0].office_associations` の lazy load をなくす。
  - 候補A: `selectinload(Staff.office_associations)` を付ける。
  - 候補B: そもそも `office_id` を先頭スタッフから決めない設計に変更する。
- [ ] Green: 全事業所向けお知らせの `office_id` を仕様化する。
  - 全体通知として `office_id = null` を許す。
  - または app-admin 用の system/global office を用意する。
  - 現状の「最初のスタッフの事務所 ID」は全体通知の意味とズレるため避ける。
- [ ] Green: フロントから POST する前に CSRF トークンが必ず取得されているか確認し、必要なら app 起動時または変更系 API 前に取得する。
- [ ] Regression: localhost のフロントから app-admin お知らせを送信し、CORS 表示ではなく成功/業務エラーが正しく見えることを確認する。

## P1: 全事業所向けお知らせの送信対象とパフォーマンスを整理する

### 課題

保存処理は 500 件 chunk の bulk insert があるが、エンドポイント側は全スタッフ ORM オブジェクトを一括ロードしている。
また、現状は `Staff.is_deleted == False` と `Staff.id != current_user.id` だけなので、他の app_admin アカウントや未承認スタッフを送信対象に含めるかが曖昧。

### TODO

- [ ] Red: 送信対象の仕様を test data で固定する。
  - 削除済みスタッフを除外。
  - 送信者 app_admin を除外。
  - 他の app_admin を含める/除外する仕様を決めて固定。
  - 未承認・事業所未所属スタッフを含める/除外する仕様を決めて固定。
- [ ] Green: recipient 取得は `Staff.id` のみを取得する query に寄せ、不要な ORM リレーションロードを避ける。
- [ ] Green: 大量件数時もメモリ使用量が増えすぎないよう、必要なら recipient id の取得も chunk 化する。
- [ ] Green: 管理画面に送信予定件数の preview を出すか検討する。
- [ ] Regression: 1,000 件以上の recipient を持つお知らせ作成で timeout しないことを backend test または負荷確認で見る。

## P1: app-admin 問い合わせ API クライアントの重複と不一致を解消する

### 課題

問い合わせ返信の実利用モーダルは `k_front/lib/api/inquiry.ts` の正しい API を使っている一方、`k_front/lib/api/appAdmin.ts` に古い/不正な API が残っている。
残骸があると、今後の UI 差し替えや再利用時に `{ content }` 送信で 422 を再発させる。

### TODO

- [ ] Red: app-admin 問い合わせ返信 API クライアントが `{ body, send_email }` を送ることを unit test で固定する。
- [ ] Green: `appAdminApi.replyToInquiry()` を削除するか、`inquiryApi.replyToInquiry()` と同じ型・payload に修正する。
- [ ] Green: `appAdminApi.markInquiryAsRead()` はバックエンド route がないため、未使用なら削除する。必要なら backend route を TDD で追加する。
- [ ] Green: `InquiriesTab` と `NewInquiriesTab` のどちらを app-admin の正とするか決める。
  - 既存 `AppAdminDashboard.tsx` は `InquiriesTab` を使用中。
  - `NewInquiriesTab` は helper test 付きの改善版があるため、統合候補。
- [ ] Regression: app-admin 問い合わせ一覧、詳細、返信の主要導線をフロントテストで固定する。

## P1: app-admin お知らせ履歴レスポンスと UI 型を合わせる

### 課題

`k_front/lib/api/appAdmin.ts` の `AnnouncementResponse` は `sender_name` を期待している。
一方、`admin_announcements.py` の GET は `MessageResponse.model_validate(message).model_dump()` を返しており、`sender_name` が必ず含まれる形には見えない。
UI 側で送信者表示が `undefined` になる可能性がある。

### TODO

- [ ] Red: `getAnnouncements()` の返却形と `AnnouncementsTab` 表示が一致することを test で固定する。
- [ ] Green: バックエンドで `sender_name` を明示的に詰めるか、フロント型を `sender` オブジェクトに合わせる。
- [ ] Green: `AnnouncementCreate` に backend schema が受けられる `priority` を含めるか、UI で使わないなら型と仕様から除く。
- [ ] Regression: お知らせ履歴で送信者・作成日時・宛先数が表示崩れしないことを確認する。

## P2: app-admin 全体の回帰テストを薄く追加する

### TODO

- [ ] app-admin dashboard のタブ表示 smoke test。
- [ ] 権限なしユーザーが `/admin/*` API を叩いた場合に拒否される backend test。
- [ ] app-admin でログ、問い合わせ、承認、事業所、お知らせタブを開ける frontend smoke test。
- [ ] 既存 TODO `todo_placeholder_cleanup.md` で完了済みの「固定問い合わせ情報」「fake reply」は再発防止テストだけ確認する。

## 実装順

1. P0 の `inquiry_reply` 表示分類を TDD で修正する。
2. P0 の問い合わせ返信メール送信ポリシーを backend test から固定する。
3. P0 の app-admin お知らせ POST 失敗を backend integration test で再現して直す。
4. P1 の API クライアント重複、不一致、不要 route 呼び出しを整理する。
5. P1 のお知らせ大量送信・送信対象仕様を固定する。

## 完了済みとして扱うもの

`md_files_design_note/task/todo/refactor/maintainability/admin_todo/todo_placeholder_cleanup.md` の確認結果より、以下はこの TODO では再修正対象にしない。

- 問い合わせ返信モーダルの fake 実装除去。
- `NewInquiriesTab` の固定 title/email 受け渡し修正。
- 監査ログの名前解決修正。
