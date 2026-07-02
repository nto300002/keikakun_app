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

## 次のアクション提案

以下のいずれかを作成することを推奨します:

### A. SQLAlchemy モデルと Pydantic スキーマ草案
- `InquiryDetail` モデルの実装
- リクエスト/レスポンススキーマの定義

### B. OpenAPI 仕様書
- API の詳細なリクエスト/レスポンス例
- エラーレスポンスの定義

### C. フロントエンド画面設計
- ワイヤーフレーム
- 画面遷移図
- コンポーネント設計

どれを先に作成しますか？
