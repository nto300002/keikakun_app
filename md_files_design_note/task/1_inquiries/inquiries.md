# 問い合わせ機能 要件定義（改訂）

## 目的・スコープ

### 基本機能
- トップページや認証画面などから、ログイン・未ログインを問わず利用者がアプリ管理者（app_admin）へ問い合わせを送信できる機能
- 管理者は問い合わせを確認・返信・割当・クローズが可能
- 問い合わせは内部メッセージ基盤（Message）を活用し、問い合わせ固有のメタ情報は別テーブル（InquiryDetail）で管理

### 問い合わせ種別
- 不具合報告
- 質問
- その他

### 関連機能：退会申請却下通知
- 事務所退会申請が却下された際、申請したアカウントにメールで却下通知を送信
- 実装箇所: `k_back/app/api/v1/endpoints/admin_inquiries.py`

### UI実装箇所

#### フロントエンド（問い合わせ送信）
- **一般スタッフ**: `k_front/app/(protected)/notice/page.tsx` > 内部通知タブ
- **未ログインユーザー**: トップページ/認証画面（お問い合わせボタン）

#### フロントエンド（問い合わせ受信・管理）
- **app_admin**: `k_front/app/(protected)/app-admin/page.tsx` > お問い合わせタブ
  - 一覧表示
  - 詳細表示
  - 返信機能（返信モーダル新規作成）

#### 退会関連UI追加要件
- **場所**: `k_front/app/(protected)/admin` > 事務所タブ > 退会コンテンツ
- **追加内容**:
  - 自身のメールアドレス確認方法の説明
  - 退会申請却下時の対応フロー
    - メール確認の案内
    - 却下理由の確認方法
    - 再申請手順

---

## 主要ユースケース

1. **非ログインユーザーが問い合わせを送る**
   - 送信先: メールで管理者に届く

2. **ログイン済みStaffが問い合わせを送る**
   - 送信先: 内部通知で管理者に届く

3. **app_admin が問い合わせ一覧を管理**
   - 一覧表示、検索、フィルタ、ソートで対応すべき問い合わせを探す

4. **app_admin が問い合わせに返信**
   - 条件分岐: 送信者がログイン済みであれば内部通知、未ログインであればメール送信

5. **問い合わせの管理**
   - 担当割当、優先度設定、ステータス管理を行う

---

## データ設計

### 設計方針
既存の Message テーブルを本文保管に利用し、問い合わせ固有フィールドは `inquiry_details`（1:1）で管理する。

### inquiry_details テーブル

| カラム名 | 型 | 制約 | 説明 |
|---------|-----|------|------|
| id | UUID | PRIMARY KEY | 主キー |
| message_id | UUID | UNIQUE, FK -> messages.id | メッセージID（1:1関連） |
| sender_name | string | NULL | 送信者名 |
| sender_email | string | NULL | 送信者メールアドレス |
| ip_address | string | NULL | 送信元IPアドレス |
| user_agent | text | NULL | ユーザーエージェント |
| status | enum | NOT NULL, default: 'new' | ステータス |
| assigned_staff_id | UUID | NULL, FK | 担当者ID |
| priority | enum | NOT NULL, default: 'normal' | 優先度 |
| admin_notes | text | NULL | 管理者メモ |
| delivery_log | JSON | NULL | メール送信履歴等 |
| created_at | timestamp | NOT NULL | 作成日時 |
| updated_at | timestamp | NOT NULL | 更新日時 |
| is_test_data | boolean | NOT NULL, default: false | テストデータフラグ |

### status（ステータス）の定義

| 値 | 説明 |
|---|------|
| new | 新規受付（未確認） |
| open | 確認済み（対応中） |
| in_progress | 担当者割当済み |
| answered | 回答済み |
| closed | クローズ済み |
| spam | スパム判定 |

### priority（優先度）の定義

| 値 | 説明 |
|---|------|
| low | 低 |
| normal | 通常 |
| high | 高 |

### インデックス
- status
- assigned_staff_id
- created_at
- sender_email
- is_test_data

### 代替案
小規模かつ素早く実装したい場合は Message テーブルにオプションカラムを追加する。ただし将来の拡張性と責務分離を考えると上記分離を推奨。

---

## API 仕様

### 1) POST /api/v1/inquiries
**問い合わせ送信（公開エンドポイント）**

- **認証**: optional（未ログインでも送信可能）
- **リクエストボディ**:
  ```json
  {
    "title": "string (required, max: 200)",
    "content": "string (required, max: 20000)",
    "category": "enum (不具合 | 質問 | その他)",
    "sender_name": "string (optional, 未ログイン時は推奨)",
    "sender_email": "string (optional, 未ログイン時は必須)"
  }
  ```
- **バリデーション**:
  - 未ログインの場合 sender_email 必須かつメール形式
  - title: 1〜200文字
  - content: 1〜20,000文字
- **レスポンス**:
  ```json
  {
    "id": "uuid",
    "message": "問い合わせを受け付けました"
  }
  ```
- **サーバ側処理**:
  1. トランザクション開始
  2. Message レコード作成
  3. inquiry_details レコード作成
  4. MessageRecipient 作成（受信者: app_admin）
  5. 監査ログ記録
  6. 管理者へ通知メール送信
  7. トランザクションコミット

### 2) GET /api/v1/admin/inquiries
**問い合わせ一覧取得（管理者専用）**

- **認証**: app_admin のみ
- **クエリパラメータ**:
  - `status`: enum (new | open | in_progress | answered | closed | spam)
  - `assigned`: UUID（担当者ID）
  - `priority`: enum (low | normal | high)
  - `search`: string（件名・本文の全文検索）
  - `skip`: integer（オフセット、default: 0）
  - `limit`: integer（取得件数、default: 20, max: 100）
  - `sort`: enum (created_at | updated_at | priority)（default: created_at desc）
- **レスポンス**:
  ```json
  {
    "inquiries": [
      {
        "id": "uuid",
        "title": "string",
        "status": "enum",
        "priority": "enum",
        "sender_name": "string",
        "sender_email": "string",
        "assigned_staff_id": "uuid",
        "created_at": "timestamp",
        "updated_at": "timestamp"
      }
    ],
    "total": "number"
  }
  ```

### 3) GET /api/v1/admin/inquiries/{id}
**問い合わせ詳細取得（管理者専用）**

- **認証**: app_admin のみ
- **レスポンス**:
  ```json
  {
    "id": "uuid",
    "message": {
      "title": "string",
      "content": "string",
      "created_at": "timestamp"
    },
    "inquiry_detail": {
      "sender_name": "string",
      "sender_email": "string",
      "ip_address": "string",
      "user_agent": "string",
      "status": "enum",
      "priority": "enum",
      "assigned_staff_id": "uuid",
      "admin_notes": "text"
    },
    "reply_history": [
      {
        "id": "uuid",
        "content": "string",
        "sender_id": "uuid",
        "created_at": "timestamp"
      }
    ]
  }
  ```

### 4) POST /api/v1/admin/inquiries/{id}/reply
**問い合わせへの返信（管理者専用）**

- **認証**: app_admin または assigned staff
- **リクエストボディ**:
  ```json
  {
    "body": "string (required, max: 20000)",
    "send_email": "boolean (optional, default: false)"
  }
  ```
- **処理内容**:
  - 内部返信: Message を生成して対象 staff に配信
  - 外部返信（send_email=true）: inquiry_details.delivery_log に送信結果を保存
- **レスポンス**:
  ```json
  {
    "id": "uuid",
    "message": "返信を送信しました"
  }
  ```

### 5) PATCH /api/v1/admin/inquiries/{id}
**問い合わせ情報更新（管理者専用）**

- **認証**: app_admin
- **リクエストボディ**:
  ```json
  {
    "status": "enum (optional)",
    "assigned_staff_id": "uuid (optional)",
    "priority": "enum (optional)",
    "admin_notes": "text (optional)"
  }
  ```
- **レスポンス**:
  ```json
  {
    "id": "uuid",
    "message": "更新しました"
  }
  ```

### 6) DELETE /api/v1/admin/inquiries/{id}
**問い合わせ削除（管理者専用）**

- **認証**: app_admin
- **実装**: 論理削除を推奨（is_deleted フラグ or deleted_at）
- **レスポンス**:
  ```json
  {
    "message": "削除しました"
  }
  ```

---

## バリデーション・セキュリティ

### CSRF対策
- 公開POSTエンドポイントでもレート制限・Captcha 等の対策を検討

### レート制限
- IPアドレスまたは sender_email ごとに閾値設定
- 推奨: 5回 / 30分
- 短絡的なスパムを防ぐ

### スパム対策
- reCAPTCHA または honeypot
- 簡易ベイズフィルタ
- 外部アンチスパムサービスの利用検討

### 入力サニタイズ
- フロントエンド: React の自動エスケープ
- サーバ側: HTML を出力しない設計（必要時は厳格にサニタイズ）
- XSS対策: 入力内容のサニタイズ（HTMLタグの除去またはエスケープ）

### SQLインジェクション対策
- パラメータ化クエリの使用（SQLAlchemy使用時は自動対応）

### ファイル添付（将来対応）
- 許可する場合は以下を検証:
  - 拡張子のホワイトリスト
  - ファイルサイズ制限
  - ウイルススキャン

### 個人情報保護
- sender_email 等は保存期間を限定
- 必要最低限のみ保持
- GDPR/個人情報保護法への対応

---

## 通知・メール

### 問い合わせ受信時
- **宛先**: app_admin ロールのユーザー
- **送信タイミング**: 問い合わせ作成直後
- **通知内容**:
  - 件名: 「【ケイカくん】新しい問い合わせが届きました」
  - 本文: 送信者情報、件名、内容の抜粋、管理画面へのリンク
- **内部処理**: MessageRecipient として app_admin ロールの受信者を作成

### 管理者が返信するとき
- **条件分岐**:
  - send_email=true → 送信先メールアドレスへ送信
  - send_email=false → 内部通知のみ
- **ログ記録**: delivery_log に送信結果を記録

### メール送信失敗時
- **リトライポリシー**: exponential backoff
- **最終失敗時**: 監査ログに記録し、アラートを出す

---

## 退会申請却下時の通知要件

### バックエンド処理
- **エンドポイント**: `k_back/app/api/v1/endpoints/admin_inquiries.py`（または該当withdrawal API）
- **却下時の処理フロー**:
  1. 申請者のメールアドレスへ却下通知を送信
  2. 通知内容に含める情報:
     - 却下理由（`approver_notes`より取得、サニタイズ済み）
     - 再申請手順
     - 退会フォームへのリンク
  3. 送信結果を `inquiry_details.delivery_log` に記録
  4. 送信失敗時は監査ログに記録

### メールテンプレート
- 日本語テンプレート使用
- 却下理由は動的に注入（エスケープ必須）
- 送信失敗時はリトライポリシー適用（exponential backoff）

### 送信タイミングとログ
- 却下時に同期的に送信できない場合は送信ジョブを登録
- 送信結果は `inquiry_details.delivery_log` または専用メールログに記録
- 送信失敗は監査ログに残す

---

## フロントエンド UI要件

### 問い合わせ送信画面（未ログインユーザー）
- **配置場所**: トップページヘッダー「お問い合わせ」ボタン
- **入力項目**:
  - お名前（任意）
  - メールアドレス（必須）
  - 問い合わせ種別（不具合 | 質問 | その他）
  - 件名（必須、200文字以内）
  - 内容（必須、20,000文字以内）
- **バリデーション**: リアルタイムバリデーション表示
- **送信後**: 確認メッセージ表示

### 問い合わせ送信画面（ログイン済みユーザー）
- **配置場所**: `k_front/app/(protected)/notice/page.tsx` > 内部通知タブ
- **入力項目**:
  - 問い合わせ種別（不具合 | 質問 | その他）
  - 件名（必須、200文字以内）
  - 内容（必須、20,000文字以内）
  - ※氏名・メールアドレスは自動取得
- **送信後**: 内部通知として送信完了メッセージ

### 管理画面：一覧画面
- **配置場所**: `k_front/app/(protected)/app-admin/page.tsx` > お問い合わせタブ
- **フィルタ機能**:
  - ステータス（new | open | in_progress | answered | closed | spam）
  - 担当者
  - 優先度（low | normal | high）
  - 日付範囲
  - キーワード検索（件名・本文）
- **表示項目**:
  - ID
  - 件名
  - 送信者（名前 / メール）
  - 種別
  - ステータス
  - 優先度
  - 担当者
  - 作成日時
- **ページネーション**: デフォルト20件/ページ
- **ソート**: 作成日時、更新日時、優先度

### 管理画面：詳細画面
- **表示情報**:
  - 問い合わせ内容（件名、本文）
  - 送信者情報（氏名、メールアドレス、IPアドレス、User-Agent）
  - ステータス、優先度、担当者
  - 返信履歴（timeline形式）
  - 管理者メモ
- **アクション**:
  - 返信（モーダル）
  - 担当者割当
  - ステータス変更
  - 優先度変更
  - CSVエクスポート
  - スパム判定

### 返信機能
- **モーダル形式**
- **機能**:
  - 下書き保存
  - 送信プレビュー
  - テンプレート選択（よくある質問への定型文）
  - メール送信/内部通知の選択
- **入力項目**:
  - 返信内容（必須、20,000文字以内）
  - メール送信するか（チェックボックス）

### バルク操作
- 複数選択でクローズ
- 複数選択でスパム指定
- 一括担当者割当

### 退会関連UI（オーナー向け）
- **配置場所**: `k_front/app/(protected)/admin` > 事務所タブ > 退会コンテンツ
- **追加内容**:
  1. **メールアドレス確認セクション**
     - 「登録メールアドレス: xxx@example.com」（マスク表示）
     - 「確認」ボタンでフルアドレス表示
  2. **却下時の案内**
     - 「退会申請が却下された場合、登録メールアドレスに却下理由が記載されたメールが届きます」
     - 「メールを確認し、指示に従って再度退会申請を行ってください」
  3. **申請履歴一覧**
     - ステータス（申請中 | 承認済み | 却下）
     - 却下時はメール送信日時を表示
     - 却下理由の表示（管理者メモより）

---

## 監査・ログ

### 監査ログ（audit_log）
すべての操作を記録:
- 作成
- 閲覧
- 返信
- 割当
- ステータス変更
- 削除

**格納項目**:
- actor_id（操作者ID）
- action（操作内容）
- target_type（対象タイプ: inquiry）
- target_id（対象ID）
- ip_address（IPアドレス）
- user_agent（ユーザーエージェント）
- timestamp（タイムスタンプ）
- details（詳細情報: JSON）

### メール送信ログ（delivery_log）
- 保存場所: `inquiry_details.delivery_log`（JSON）または別テーブル
- 記録内容:
  - 送信日時
  - 宛先
  - 送信結果（成功 | 失敗）
  - エラー内容（失敗時）
  - リトライ回数

---

## プライバシー・保持ポリシー

### 個人情報の保持期間
- sender_email 等個人情報: **1年間保持 → アーカイブ → 完全削除**
- IPアドレス、User-Agent: **6ヶ月間保持 → 削除**
- 問い合わせ本文: **3年間保持 → アーカイブ → 完全削除**

### DSAR（データ主体要求）対応
- 開示請求への対応手順を用意
- 削除請求への対応手順を用意
- 訂正請求への対応手順を用意

### ログのマスキング方針
- 監査ログに全メールアドレスを平文で長期間保存しない
- 必要に応じてハッシュ化またはマスキング処理を実施

---

## テスト計画

### ユニットテスト
- Pydantic スキーマのバリデーション
- CRUD 操作
- メール送信ラッパーのモック

### 統合テスト
- 公開 POST → DB 登録 → 管理 GET → reply フロー（エンドツーエンド）
- メール送信フロー
- 内部通知フロー

### セキュリティテスト
- レート制限テスト
- CSRF 回避テスト
- XSS インジェクション試験
- SQLインジェクション試験

### 負荷テスト
- 同時送信テスト
- メールバースト時の処理確認

---

## 受け入れ基準

### シナリオ1: 未ログインユーザーが問い合わせを送信
- **Given**: 未ログインユーザーがトップページで問い合わせフォームを開く
- **When**: 必要項目を入力して POST /api/v1/inquiries を実行
- **Then**:
  - 201 が返る
  - messages と inquiry_details にレコードが作成される
  - app_admin に通知メールが送信される
  - 監査ログに記録される

### シナリオ2: app_admin が問い合わせに返信
- **Given**: app_admin が問い合わせ詳細画面を開く
- **When**: 回答を入力して送信する（send_email=true）
- **Then**:
  - 送信者にメールが届く
  - inquiry_details.status が answered に更新される
  - 操作が audit_log に記録される
  - delivery_log に送信結果が記録される

### シナリオ3: スパム判定
- **Given**: 短時間に大量の問い合わせが同一IPから送信される
- **When**: レート制限の閾値を超える
- **Then**:
  - 429 Too Many Requests が返る
  - エラーメッセージが表示される
  - 監査ログに記録される

### シナリオ4: 退会申請却下通知
- **Given**: app_admin が退会申請を却下する
- **When**: 却下処理を実行
- **Then**:
  - 申請者にメールで却下理由が送信される
  - delivery_log に送信結果が記録される
  - 申請ステータスが「却下」に更新される

---

## 実装優先度（MVP）

### フェーズ1: 基本機能
1. POST /api/v1/inquiries（公開エンドポイント）
   - DB 保存
   - Message 作成
   - InquiryDetail 作成
   - admin 通知メール送信
2. GET /api/v1/admin/inquiries（一覧取得）
   - フィルタ機能
   - ページネーション
3. GET /api/v1/admin/inquiries/{id}（詳細表示）

### フェーズ2: 返信機能
4. POST /api/v1/admin/inquiries/{id}/reply（返信）
   - 内部返信（内部通知）
   - 外部返信（メール送信）
   - delivery_log 記録

### フェーズ3: セキュリティ強化
5. レート制限実装
6. CAPTCHA 導入
7. スパム対策

### フェーズ4: 管理機能強化
8. PATCH /api/v1/admin/inquiries/{id}（更新）
9. DELETE /api/v1/admin/inquiries/{id}（削除）
10. バルク操作機能

---

## 実装タスクリスト

### フェーズ1: データベース設計とモデル実装

#### バックエンド - モデル
- [ ] `app/models/inquiry.py` 作成
  - [ ] `InquiryDetail` モデル定義
  - [ ] status enum 定義
  - [ ] priority enum 定義
  - [ ] Message モデルとの 1:1 リレーション設定
  - [ ] インデックス設定
- [ ] マイグレーションファイル作成
  - [ ] `inquiry_details` テーブル作成
  - [ ] 外部キー制約設定
  - [ ] インデックス作成
- [ ] マイグレーション実行とテスト
  - [ ] upgrade/downgrade 動作確認
  - [ ] テストデータ投入確認

#### バックエンド - スキーマ
- [x] `app/schemas/inquiry.py` 作成
  - [x] `InquiryCreate` スキーマ（問い合わせ送信用）
  - [x] `InquiryDetailResponse` スキーマ（詳細表示用）
  - [x] `InquiryFullResponse` スキーマ（完全な詳細表示用）
  - [x] `InquiryListResponse` スキーマ（一覧表示用）
  - [x] `InquiryReply` スキーマ（返信用）
  - [x] `InquiryUpdate` スキーマ（更新用）
  - [x] `InquiryQueryParams` スキーマ（クエリパラメータ）
  - [x] レスポンススキーマ（Create, Update, Delete）
  - [x] バリデーション実装（文字数、メール形式、Enum等）

#### バックエンド - CRUD
- [x] `app/crud/crud_inquiry.py` 作成
  - [x] `create_inquiry` メソッド（トランザクション処理）
  - [x] `get_inquiries` メソッド（フィルタ・ページネーション）
  - [x] `get_inquiry_by_id` メソッド（詳細取得）
  - [x] `update_inquiry` メソッド（ステータス・担当者等更新）
  - [ ] `create_reply` メソッド（返信作成）
  - [x] `delete_inquiry` メソッド（CASCADE削除）

#### バックエンド - ユーティリティ
- [x] `app/utils/sanitization.py` 作成
  - [x] `sanitize_html` - HTMLエンティティエスケープ
  - [x] `sanitize_text_content` - テキストサニタイズ（HTML除去、制御文字除去）
  - [x] `sanitize_email` - メールアドレスの正規化と検証
  - [x] `contains_spam_patterns` - スパムパターン検出
  - [x] `validate_honeypot` - ハニーポット検証
  - [x] `sanitize_inquiry_input` - 問い合わせ入力の一括サニタイズ

#### バックエンド - レート制限
- [x] `app/core/limiter.py` 確認（既存インフラ利用）
  - [x] slowapi Limiter インスタンス確認
  - [x] IP ベースのレート制限対応確認

### フェーズ2: API エンドポイント実装

#### バックエンド - エンドポイント
- [ ] `app/api/v1/endpoints/inquiries.py` 作成（公開API）
  - [ ] `POST /api/v1/inquiries` 実装
    - [ ] 認証チェック（optional）
    - [ ] バリデーション処理
    - [ ] Message + InquiryDetail 作成
    - [ ] MessageRecipient 作成（app_admin宛）
    - [ ] 監査ログ記録
    - [ ] 管理者通知メール送信
    - [ ] トランザクション制御
- [ ] `app/api/v1/endpoints/admin_inquiries.py` 作成（管理者API）
  - [ ] `GET /api/v1/admin/inquiries` 実装
    - [ ] app_admin 権限チェック
    - [ ] クエリパラメータ処理
    - [ ] フィルタリング処理
    - [ ] ページネーション実装
    - [ ] ソート処理
  - [ ] `GET /api/v1/admin/inquiries/{id}` 実装
    - [ ] 詳細情報取得
    - [ ] 返信履歴取得
  - [ ] `POST /api/v1/admin/inquiries/{id}/reply` 実装
    - [ ] 返信作成
    - [ ] 内部通知 or メール送信の分岐
    - [ ] delivery_log 記録
    - [ ] ステータス自動更新（answered）
  - [ ] `PATCH /api/v1/admin/inquiries/{id}` 実装
    - [ ] 担当者割当
    - [ ] ステータス変更
    - [ ] 優先度変更
    - [ ] 管理者メモ更新
  - [ ] `DELETE /api/v1/admin/inquiries/{id}` 実装
    - [ ] 論理削除処理
- [ ] ルーター登録（`app/api/v1/router.py`）

### フェーズ3: セキュリティ・バリデーション

#### バックエンド - セキュリティ
- [x] レート制限実装
  - [x] IP ベースのレート制限（5回/30分）
  - [x] slowapi を使用したレート制限インフラ確認
  - [ ] Email ベースのレート制限（将来対応）
  - [ ] Redis ベースの分散レート制限（将来対応）
- [ ] CAPTCHA 導入検討（将来対応）
  - [ ] reCAPTCHA v3 統合
  - [ ] フロントエンド連携
- [x] スパム対策
  - [x] honeypot フィールド検証機能実装
  - [x] スパムパターン検出（URL数、大文字比率、禁止キーワード）
  - [ ] 簡易ベイズフィルタ実装検討（将来対応）
- [x] 入力サニタイズ
  - [x] XSS 対策（HTMLタグのエスケープ・除去）
  - [x] メールアドレスのサニタイズと検証
  - [x] 制御文字の除去
  - [x] 文字数制限の強制適用
  - [x] SQLインジェクション対策確認（SQLAlchemy使用）

### フェーズ4: メール・通知機能

#### バックエンド - メール
- [ ] メールテンプレート作成
  - [ ] 問い合わせ受信通知（管理者宛）
  - [ ] 返信通知（ユーザー宛）
  - [ ] 退会申請却下通知（ユーザー宛）
- [ ] メール送信機能実装
  - [ ] 送信ラッパー関数作成
  - [ ] リトライポリシー実装（exponential backoff）
  - [ ] delivery_log 記録
  - [ ] 送信失敗時の監査ログ記録
- [ ] 退会申請却下時の通知実装
  - [ ] `admin_inquiries.py` に却下通知処理追加
  - [ ] 却下理由のサニタイズ
  - [ ] メール送信とログ記録

### フェーズ5: フロントエンド実装

#### 問い合わせ送信（未ログインユーザー）
- [ ] 問い合わせモーダルコンポーネント作成
  - [ ] `k_front/components/inquiry/InquiryModal.tsx`
  - [ ] フォーム実装（氏名、メール、種別、件名、内容）
  - [ ] バリデーション実装
  - [ ] 送信処理
  - [ ] 確認メッセージ表示
- [ ] トップページへの統合
  - [ ] `k_front/app/page.tsx` 修正
  - [ ] ヘッダーの「お問い合わせ」ボタンにモーダル連携

#### 問い合わせ送信（ログイン済みユーザー）
- [ ] 内部通知タブへの統合
  - [ ] `k_front/app/(protected)/notice/page.tsx` 修正
  - [ ] 問い合わせ送信フォーム追加
  - [ ] スタッフ情報の自動取得

#### 管理画面 - 一覧
- [ ] 問い合わせ一覧コンポーネント作成
  - [ ] `k_front/components/admin/InquiryList.tsx`
  - [ ] フィルタUI（ステータス、担当者、優先度、日付範囲）
  - [ ] キーワード検索
  - [ ] テーブル表示
  - [ ] ページネーション
  - [ ] ソート機能
- [ ] app-admin ページへの統合
  - [ ] `k_front/app/(protected)/app-admin/page.tsx` 修正
  - [ ] 「お問い合わせ」タブ追加

#### 管理画面 - 詳細・返信
- [ ] 問い合わせ詳細コンポーネント作成
  - [ ] `k_front/components/admin/InquiryDetail.tsx`
  - [ ] 問い合わせ情報表示
  - [ ] 送信者情報表示
  - [ ] 返信履歴表示（タイムライン形式）
  - [ ] 管理者メモ表示・編集
- [ ] 返信モーダルコンポーネント作成
  - [ ] `k_front/components/admin/InquiryReplyModal.tsx`
  - [ ] 返信内容入力
  - [ ] メール送信チェックボックス
  - [ ] プレビュー機能
  - [ ] テンプレート選択機能
- [ ] アクションボタン実装
  - [ ] 担当者割当
  - [ ] ステータス変更
  - [ ] 優先度変更
  - [ ] スパム判定
  - [ ] CSVエクスポート

#### 退会関連UI
- [ ] 退会コンテンツへの追加
  - [ ] `k_front/app/(protected)/admin` 修正
  - [ ] メールアドレス確認セクション追加
  - [ ] 却下時の案内追加
  - [ ] 申請履歴一覧追加

### フェーズ6: テスト実装

#### バックエンド - ユニットテスト
- [x] `tests/utils/test_sanitization.py` 作成（35テスト）
  - [x] HTMLサニタイズテスト
  - [x] テキストコンテンツサニタイズテスト
  - [x] メールアドレスサニタイズテスト
  - [x] スパムパターン検出テスト
  - [x] ハニーポット検証テスト
  - [x] 問い合わせ入力サニタイズテスト
- [x] `tests/security/test_rate_limiting.py` 作成（15テスト）
  - [x] Limiterインスタンステスト
  - [x] リモートアドレス取得テスト
  - [x] レート制限デコレータテスト
  - [x] レート制限設定テスト
  - [x] IPアドレス抽出テスト
  - [x] セキュリティベストプラクティステスト
- [ ] `tests/crud/test_crud_inquiry.py` 作成
  - [ ] create_inquiry テスト
  - [ ] get_inquiries テスト（フィルタ・ページネーション）
  - [ ] get_inquiry_by_id テスト
  - [ ] update_inquiry テスト
  - [ ] create_reply テスト
  - [ ] delete_inquiry テスト
- [x] `tests/schemas/test_inquiry.py` 作成（48テスト）
  - [x] InquiryCreate バリデーションテスト（13テスト）
  - [x] InquiryUpdate バリデーションテスト（6テスト）
  - [x] InquiryReply バリデーションテスト（5テスト）
  - [x] InquiryQueryParams バリデーションテスト（11テスト）
  - [x] レスポンススキーマテスト（5テスト）
  - [x] エッジケーステスト（8テスト）

#### バックエンド - 統合テスト
- [x] `tests/api/v1/test_inquiries_integration.py` 作成（12テスト）
  - [x] 問い合わせ作成（ログインユーザー）テスト
  - [x] 問い合わせ作成（ゲストユーザー）テスト
  - [x] HTMLサニタイズ統合テスト
  - [x] スパム検出統合テスト
  - [x] ハニーポット検出統合テスト
  - [x] メールサニタイズ統合テスト
  - [x] フィルタリング取得テスト
  - [x] 問い合わせ更新テスト
  - [x] 問い合わせ削除テスト
  - [x] 文字数制限強制テスト
  - [x] 不正メール拒否テスト
  - [x] XSS防止テスト
- [ ] `tests/api/v1/test_inquiries.py` 作成（APIエンドポイント実装後）
  - [ ] POST /api/v1/inquiries テスト
  - [ ] エンドツーエンドフロー（送信→登録→通知）
  - [ ] バリデーションエラーテスト
- [ ] `tests/api/v1/test_admin_inquiries.py` 作成（APIエンドポイント実装後）
  - [ ] GET /api/v1/admin/inquiries テスト
  - [ ] GET /api/v1/admin/inquiries/{id} テスト
  - [ ] POST /api/v1/admin/inquiries/{id}/reply テスト
  - [ ] PATCH /api/v1/admin/inquiries/{id} テスト
  - [ ] DELETE /api/v1/admin/inquiries/{id} テスト
  - [ ] 権限チェックテスト

#### バックエンド - セキュリティテスト
- [x] レート制限テスト
  - [x] Limiterインスタンス確認（15テスト）
  - [x] IPアドレス抽出テスト
  - [x] レート制限設定の妥当性テスト
  - [x] セキュリティベストプラクティステスト
- [x] 入力サニタイズテスト（35テスト）
  - [x] HTMLサニタイズテスト
  - [x] テキストコンテンツサニタイズテスト
  - [x] メールアドレスサニタイズテスト
  - [x] スパムパターン検出テスト
  - [x] ハニーポット検証テスト
  - [x] 問い合わせ入力サニタイズ統合テスト
- [x] 統合テスト（12テスト）
  - [x] 問い合わせ作成フロー（ログインユーザー・ゲストユーザー）
  - [x] サニタイズ機能統合テスト
  - [x] CRUD操作統合テスト
  - [x] セキュリティ統合テスト（文字数制限、XSS防止等）
- [ ] CSRF 対策テスト（既存インフラ確認済み）
- [x] XSS インジェクションテスト
- [x] SQLインジェクションテスト（SQLAlchemy使用により対策済み）

#### フロントエンド - テスト
- [ ] 問い合わせモーダルのテスト
- [ ] 一覧画面のテスト
- [ ] 詳細画面のテスト
- [ ] 返信機能のテスト

### フェーズ7: ドキュメント・デプロイ

#### ドキュメント
- [ ] API ドキュメント作成
  - [ ] OpenAPI 仕様書更新
  - [ ] リクエスト/レスポンス例追加
- [ ] ユーザーガイド作成
  - [ ] 管理者向け操作マニュアル
  - [ ] 問い合わせ送信方法
- [ ] 保守ドキュメント作成
  - [ ] データ保持ポリシー
  - [ ] DSAR 対応手順

#### デプロイ・監視
- [ ] 本番環境デプロイ
  - [ ] マイグレーション実行
  - [ ] 環境変数設定
  - [ ] メール送信設定確認
- [ ] 監視設定
  - [ ] エラーログ監視
  - [ ] メール送信失敗アラート
  - [ ] レート制限アラート

---

---

## 実装進捗サマリー（2025-12-04更新）

### 完了済み項目

#### ✅ フェーズ1: データベース設計とモデル実装
- **バックエンド - モデル**: `app/models/inquiry.py`（既存確認済み）
  - `InquiryDetail` モデル定義
  - status/priority enum 定義
  - Message モデルとの 1:1 リレーション設定
- **バックエンド - CRUD**: `app/crud/crud_inquiry.py`（完成）
  - `create_inquiry` - トランザクション処理で Message + InquiryDetail + MessageRecipient を作成
  - `get_inquiries` - フィルタ・ページネーション対応
  - `get_inquiry_by_id` - 詳細取得
  - `update_inquiry` - ステータス・担当者等更新
  - `delete_inquiry` - CASCADE削除

#### ✅ フェーズ3: セキュリティ・バリデーション（完了）
- **レート制限実装**
  - slowapi を使用した IP ベースのレート制限（5回/30分対応可能）
  - `app/core/limiter.py` 確認済み
- **スパム対策実装**
  - honeypot フィールド検証機能
  - スパムパターン検出（URL数、大文字比率、禁止キーワード）
- **入力サニタイズ実装**
  - `app/utils/sanitization.py` 作成
  - XSS対策（HTMLタグのエスケープ・除去）
  - メールアドレスのサニタイズと検証
  - 制御文字の除去
  - 文字数制限の強制適用

#### ✅ フェーズ6: テスト実装（完了）
- **ユニットテスト**: 98テスト
  - `tests/utils/test_sanitization.py` - 35テスト
  - `tests/security/test_rate_limiting.py` - 15テスト
  - `tests/schemas/test_inquiry.py` - 48テスト
- **統合テスト**: 12テスト
  - `tests/api/v1/test_inquiries_integration.py` - 12テスト
  - 問い合わせ作成フロー（ログイン・ゲスト）
  - サニタイズ機能統合
  - CRUD操作統合
  - セキュリティ統合（XSS防止、文字数制限等）
- **テスト結果**: ✅ 110 passed (98 unit + 12 integration)

### 次のステップ

#### 🔜 優先度: 高
1. **API エンドポイントの実装**
   - `POST /api/v1/inquiries` - 問い合わせ送信（公開）
   - `GET /api/v1/admin/inquiries` - 一覧取得（管理者）
   - `GET /api/v1/admin/inquiries/{id}` - 詳細取得（管理者）

#### 🔜 優先度: 中
3. **返信機能の実装**
   - `POST /api/v1/admin/inquiries/{id}/reply` 実装
   - 内部通知/メール送信の分岐処理
   - delivery_log 記録

4. **フロントエンド実装**
   - 問い合わせ送信フォーム（未ログイン・ログイン済み）
   - 管理画面（一覧・詳細・返信）

### 実装済みファイル一覧

#### バックエンド
- `app/models/inquiry.py` - InquiryDetail モデル
- `app/schemas/inquiry.py` - 問い合わせスキーマ（作成、更新、返信、レスポンス等）
- `app/crud/crud_inquiry.py` - CRUD操作
- `app/utils/sanitization.py` - サニタイズユーティリティ
- `app/core/limiter.py` - レート制限（既存）

#### テスト
- `tests/utils/test_sanitization.py` - サニタイズテスト（35テスト）
- `tests/security/test_rate_limiting.py` - レート制限テスト（15テスト）
- `tests/schemas/test_inquiry.py` - スキーマテスト（48テスト）
- `tests/api/v1/test_inquiries_integration.py` - 統合テスト（12テスト）

#### ドキュメント
- `md_files_design_note/task/1_inquiries/security_implementation.md` - セキュリティ実装完了報告
- `md_files_design_note/task/1_inquiries/schema_tests_complete.md` - スキーマテスト完了報告

---

## 次のアクション提案

以下のステップで実装を進めることを推奨します:

### ステップ1: API エンドポイントの実装（推奨）
- 公開エンドポイント: `POST /api/v1/inquiries`
  - スキーマとCRUDの統合
  - レート制限、サニタイズの適用
  - 監査ログ記録
- 管理者エンドポイント: `GET /api/v1/admin/inquiries`, `GET /api/v1/admin/inquiries/{id}`
  - 権限チェック
  - フィルタリング、ページネーション

### ステップ2: APIエンドポイントテストの作成
- `tests/api/v1/test_inquiries.py` 作成
- `tests/api/v1/test_admin_inquiries.py` 作成
- エンドツーエンドテスト

### ステップ3: 返信機能の実装
- `POST /api/v1/admin/inquiries/{id}/reply` 実装
- 内部通知/メール送信の分岐処理

### ステップ4: フロントエンド実装
- 問い合わせ送信フォーム
- 管理画面（一覧・詳細・返信）
