# 問い合わせ機能 要件定義（改訂）

## 目的・スコープ
- 抽象
- どこからどこへ、何を使って何を送信するか

- トップページや認証画面などから、ログイン・未ログインを問わず利用者がアプリ管理者（app_admin）へ問い合わせを送信できる機能。
- 管理者は問い合わせを確認・返信・割当・クローズできる。問い合わせは内部メッセージ基盤（Message）を活用し、問い合わせ固有のメタ情報は別テーブル（InquiryDetail）で管理する。

## 主要ユースケース
- 条件分岐
- 入出力
- 管理する情報

1. 非ログインユーザーが問い合わせを送る（メール必須）
2. ログイン済みStaffが問い合わせを送る（メールは任意）
3. app_admin が問い合わせ一覧を一覧・検索・フィルタして対応する
4. app_admin が問い合わせに返信（メール送信 or 内部通知）する
5. 問い合わせの担当割当、優先度、ステータス管理を行う

## データ設計（推奨）
- 利用方針: 既存の Message テーブルを本文保管に利用し、問い合わせ固有フィールドは `inquiry_details`（1:1）で管理する。

### inquiry_details テーブル（最小セット）
- id: UUID (主キー)
- message_id: UUID (UNIQUE, FK -> messages.id)
- sender_name: string | null
- sender_email: string | null
- ip_address: string | null
- user_agent: text | null
- status: enum (pending | open | answered | closed | spam)  -- default pending, index
- assigned_staff_id: UUID | null -- index
- priority: enum (low | normal | high) -- default normal
- admin_notes: text | null
- delivery_log: JSON | null  # メール送信履歴等
- created_at: timestamp
- updated_at: timestamp
- is_test_data: boolean (index)

インデックス: status, assigned_staff_id, created_at, sender_email

代替: 小規模かつ素早く実装したい場合は Message テーブルにオプションカラムを追加する。ただし将来の拡張性と責務分離を考えると上記分離を推奨。

## API 仕様（要点）
1) POST /api/v1/admin/inquiries
- 認証: optional（公開エンドポイント）
- リクエストボディ: { title: string, content: string, sender_name?: string, sender_email?: string }
- バリデーション: 未ログインの場合 sender_email 必須かつメール形式。title/content は長さ制限（例: title <= 200, content <= 20000）。
- レスポンス: 201 { id: string, message: "作成しました" }
- 振る舞い（サーバ側）: トランザクションで Message を作成 → inquiry_details を作成 → MessageRecipient を作成（受信者: app_admin ロールの代表または通知キュー）→ 監査ログ記録 → 管理者へ通知メール

2) GET /api/v1/admin/inquiries
- 認証: app_admin のみ
- クエリ: status, assigned, priority, search, skip, limit, sort
- レスポンス: { inquiries: [...], total: number }

3) GET /api/v1/admin/inquiries/{id}
- 認証: app_admin のみ
- レスポンス: Message + InquiryDetail + reply_history

4) POST /api/v1/admin/inquiries/{id}/reply
- 認証: app_admin または assigned staff
- ボディ: { body: string, send_email?: boolean }
- 振る舞い: 内部返信は Message を生成して対象 staff に配信。外部返信（send_email=true）は inquiry_details.delivery_log に送信結果を保存。

5) PATCH /api/v1/admin/inquiries/{id}
- 認証: app_admin
- 更新可能フィールド: status, assigned_staff_id, priority, admin_notes

6) DELETE /api/v1/admin/inquiries/{id}
- 認証: app_admin
- 実装: 論理削除を推奨（is_deleted フラグ or deleted_at）

## バリデーション・セキュリティ
- CSRF: 公開POSTでもレート制限・Captcha 等の対策を検討
- レート制限: IP または sender_email ごとに閾値（例: 5 回 / 30 分）。短絡的なスパムを防ぐ。
- スパム対策: reCAPTCHA か honeypot、簡易ベイズフィルタや外部アンチスパムサービス
- 入力サニタイズ: フロントは React の自動エスケープ、サーバは HTML を出力しない設計（必要時は厳格にサニタイズ）
- 個人情報保護: sender_email 等は保存期間を限定し、必要最低限のみ保持する

## 通知・メール
- 問い合わせ受信時: app_admin に通知メール（テンプレ日本語）を送信し、MessageRecipient として app_admin ロールの受信者を作成する
- 管理者が返信するとき: send_email=true なら送信先メールアドレスへ送信し、delivery_log に結果を記録
- メール送信失敗時: retry ポリシー（exponential backoff）、最終失敗は監査ログに記録しアラートを出す

## 管理画面（UI）要件
- 一覧画面: フィルタ（status, assigned, priority, date, keyword）、ページネーション、件数表示
- 詳細画面: original content, sender info (email if present), IP/UA, reply history, admin_notes, アクションボタン（返信・割当・ステータス変更・CSVエクスポート）
- 返信UX: 下書き保存、送信プレビュー、テンプレート選択
- バルク操作: 複数選択でクローズ／スパム指定

## 監査・ログ
- すべての操作（作成、閲覧、返信、割当、ステータス変更）は audit_log に記録
  - 格納項目: actor_id, action, target_type, target_id, ip_address, user_agent, timestamp, details
- delivery_log（メール送信履歴）は inquiry_details に保存（JSON）または別テーブルで管理

## プライバシー・保持ポリシー
- sender_email 等個人情報は保持期間を定義（例: 1 年 → アーカイブ → さらに削除）
- DSAR（データ主体要求）への対応手順を用意する
- ログや request_data のマスキング方針を定義する（監査ログに全メールアドレスを平文で長期間保存しない等）

## テスト計画
- ユニット: Pydantic スキーマ、CRUD、メール送信ラッパーのモック
- 統合: 公開 POST → DB 登録 → 管理 GET → reply フロー（エンドツーエンド）
- セキュリティ: レート制限テスト、CSRF 回避、XSS インジェクション試験
- 負荷: 同時送信・メールバースト時の処理確認

## 受け入れ基準（例）
- Given: 未ログインユーザーがトップページで問い合わせを送る
  - When: POST /api/v1/admin/inquiries を実行
  - Then: 201 が返り、messages と inquiry_details にレコードが作成され、app_admin に通知メールが送信される

- Given: app_admin が問い合わせ詳細画面を開く
  - When: 回答を送信する（send_email=true）
  - Then: 送信者にメールが届き、inquiry_details.status が answered に更新され、操作が audit_log に記録される

## 実装優先度（MVP）
1. POST 公開エンドポイント（DB 保存、Message 作成、InquiryDetail 作成、admin 通知）
2. GET 一覧（app_admin） + フィルタ/ページネーション
3. 詳細表示 + 返信（内部返信）
4. 外部メール返信（delivery_log）
5. レート制限 / CAPTCHA / スパム対策

## 次のアクション提案
- A. 上記に基づく SQLAlchemy モデル（InquiryDetail）と Pydantic スキーマ草案を作成する
- B. API の OpenAPI 風のリクエスト/レスポンス例を作る

どちらを先に作成しますか？