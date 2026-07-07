# Google Calendar連携機能要件

## 概要
新しく利用者が作成されたとき、新規にサイクルが作成されたとき、スケジューラーが5分ごとにカレンダーを更新し、サイクル期限（6ヶ月）のうち残り1ヶ月を通知する。

## 認証方式（ハイブリッド案）
管理者メニューで以下の2つの認証方式を選択可能とする：

### 1. OAuth 2.0方式（推奨・新規ユーザー向け）
- **特徴**: 3クリックで設定完了、技術的知識不要
- **仕組み**: ユーザーがGoogleアカウントで認証し、けいかくんが自動的にカレンダーを作成
- **カレンダー**: 「けいかくん - [事業所名]」を自動作成
- **対象ユーザー**: 新規で始める事業所、設定を簡単にしたい事業所

### 2. サービスアカウント方式（既存カレンダー利用）
- **特徴**: 既存の事業所共有カレンダーを利用可能
- **仕組み**: けいかくん側で用意したサービスアカウントに、ユーザーがカレンダー共有権限を付与
- **カレンダー**: ユーザーが既に作成済みのカレンダーを指定
- **対象ユーザー**: 既存カレンダーがある事業所、Google Workspaceを使用している事業所

---

## 機能要件

### 管理者メニュー（Owner権限のみ）

#### カレンダー連携設定画面
```
┌─────────────────────────────────────────────┐
│  Googleカレンダー連携の設定                    │
├─────────────────────────────────────────────┤
│  どちらの方式で連携しますか？                  │
│                                             │
│  ┌────────────────────────────────────┐   │
│  │ 【推奨】簡単設定（OAuth 2.0）            │   │
│  │ ✓ 3クリックで設定完了                  │   │
│  │ ✓ 技術的知識不要                       │   │
│  │ ✓ カレンダーを自動作成                 │   │
│  │   [この方法で連携する]                  │   │
│  └────────────────────────────────────┘   │
│                                             │
│  ┌────────────────────────────────────┐   │
│  │ 詳細設定（サービスアカウント）           │   │
│  │ • 既存の事業所共有カレンダーを利用      │   │
│  │ • Google Workspaceのカレンダーを利用   │   │
│  │ ⚠ 設定に技術的知識が必要です            │   │
│  │   [この方法で連携する]                  │   │
│  └────────────────────────────────────┘   │
└─────────────────────────────────────────────┘
```

### OAuth 2.0設定フロー
1. 「Googleで認証する」ボタンをクリック
2. Googleログイン画面で認証
3. カレンダーへのアクセス権限を許可
4. けいかくんが「けいかくん - [事業所名]」カレンダーを自動作成
5. 完了

### サービスアカウント設定フロー
1. けいかくんのサービスアカウントメールアドレスを表示
2. ユーザーが自分のGoogleカレンダーで、このメールアドレスに「予定の変更」権限を付与
3. ユーザーがカレンダーIDを入力
4. 接続テストを実行
5. 完了

### 認証方式の切り替え
- Owner権限のユーザーは、いつでも認証方式を切り替え可能
- 切り替え時、既存のカレンダー設定は削除され、新しい方式の設定に置き換わる
- 切り替え前の確認ダイアログを表示

---

## データベース要件

### OfficeCalendarAccountテーブルの拡張

```python
class CalendarAuthType(str, Enum):
    service_account = "service_account"
    oauth2 = "oauth2"

class OfficeCalendarAccount(Base):
    office_id: UUID  # unique制約あり（1事業所につき1カレンダーアカウント）

    # 認証方式
    auth_type: CalendarAuthType  # 'service_account' or 'oauth2'

    # 共通フィールド
    google_calendar_id: str
    calendar_name: str
    calendar_url: str
    connection_status: str  # 'connected', 'disconnected', 'error'

    # OAuth 2.0用（auth_type='oauth2'の場合のみ使用）
    oauth_access_token: str  # 暗号化
    oauth_refresh_token: str  # 暗号化
    oauth_token_expiry: datetime

    # サービスアカウント用（auth_type='service_account'の場合のみ使用）
    service_account_key: str  # 暗号化（現在は各事業所が提供）
    service_account_email: str
```

### マイグレーション
- 既存レコードの`auth_type`をデフォルト値`'service_account'`に設定
- OAuth関連フィールドを追加（nullable=True）

---

## バックエンド要件

### 新規APIエンドポイント

#### OAuth 2.0フロー
```python
# 認証フロー開始
GET /api/v1/calendar/oauth/authorize
- Owner権限チェック
- OAuth認証URLを生成してリダイレクト

# OAuth コールバック
GET /api/v1/calendar/oauth/callback?code=xxx&state=yyy
- 認証コードをトークンに交換
- カレンダーを自動作成
- OfficeCalendarAccountレコードを作成/更新
```

#### サービスアカウント設定
```python
# サービスアカウント情報取得
GET /api/v1/calendar/service-account-info
- けいかくんのサービスアカウントメールアドレスを返却

# サービスアカウント設定
POST /api/v1/calendar/service-account
- カレンダーIDを受け取る
- 接続テストを実行
- OfficeCalendarAccountレコードを作成/更新
```

#### 認証方式切り替え
```python
# OAuth 2.0に切り替え
POST /api/v1/calendar/switch-to-oauth
- 既存の設定を削除
- OAuth認証フローにリダイレクト

# サービスアカウントに切り替え
POST /api/v1/calendar/switch-to-service-account
- 既存の設定を削除
- サービスアカウント設定画面を表示
```

### Google Calendar Client の拡張

```python
class GoogleCalendarClient:
    def authenticate(self) -> None:
        """認証方式に応じて認証"""
        if self.account.auth_type == CalendarAuthType.service_account:
            self._authenticate_with_service_account()
        elif self.account.auth_type == CalendarAuthType.oauth2:
            self._authenticate_with_oauth2()

    def _authenticate_with_oauth2(self) -> None:
        """OAuth 2.0方式で認証、トークン期限切れ時は自動更新"""
        credentials = Credentials(
            token=self.account.oauth_access_token,
            refresh_token=self.account.oauth_refresh_token,
            token_uri="https://oauth2.googleapis.com/token",
            client_id=os.getenv("GOOGLE_OAUTH_CLIENT_ID"),
            client_secret=os.getenv("GOOGLE_OAUTH_CLIENT_SECRET"),
        )

        if credentials.expired:
            credentials.refresh(Request())
            # 更新されたトークンをDBに保存
            self.account.oauth_access_token = credentials.token
            self.account.oauth_token_expiry = credentials.expiry
```

### 環境変数

```bash
# OAuth 2.0設定（新規追加）
GOOGLE_OAUTH_CLIENT_ID=xxx.apps.googleusercontent.com
GOOGLE_OAUTH_CLIENT_SECRET=xxx
GOOGLE_OAUTH_REDIRECT_URI=https://keikakun.com/api/v1/calendar/oauth/callback

# サービスアカウント設定（マルチテナント方式）
GOOGLE_SERVICE_ACCOUNT_EMAIL=keikakun-calendar@xxx.iam.gserviceaccount.com
GOOGLE_SERVICE_ACCOUNT_KEY={"type":"service_account",...}
```

---

## フロントエンド要件

### カレンダー連携設定画面（新規作成）
- パス: `/admin/calendar/setup`
- 2つの認証方式を選択できるUI
- OAuth 2.0を「推奨」として表示

### OAuth 2.0認証フロー
1. 確認ダイアログ表示（事業所共有アカウントでの認証を推奨）
2. `/api/v1/calendar/oauth/authorize`にリダイレクト
3. Google認証後、コールバックURLに戻る
4. 完了画面を表示

### サービスアカウント設定画面
- けいかくんのサービスアカウントメールアドレスを表示
- カレンダーIDの入力フォーム
- ステップバイステップのガイド（スクリーンショット付き）
- 接続テストボタン

### 既存の管理画面への統合
- Admin Menuに「カレンダー連携設定」メニューを追加
- 現在の認証方式を表示
- 「認証方式を切り替える」ボタン

---

## セキュリティ要件

### OAuth 2.0
- スコープ: `https://www.googleapis.com/auth/calendar`（カレンダーの読み書き）
- stateパラメータでCSRF対策
- トークンは暗号化してDBに保存
- アクセストークン有効期限: 1時間（自動更新）

### サービスアカウント
- けいかくん側のサービスアカウントキーは環境変数で管理
- ユーザーはカレンダーIDのみを登録（JSONキーは不要）

---

## 運用要件

### 切り替え時の注意事項
1. **既存イベントの扱い**
   - 切り替え時、古いカレンダーのイベントは元の場所に残る
   - 新しいイベントは新しいカレンダーに同期
   - イベント移行機能は将来の検討課題

2. **通知の一時停止**
   - 切り替え処理中（1〜2分）は通知が一時停止
   - 完了後、即座に通知を再開
   - 推奨: 業務時間外に切り替え実施

3. **トランザクション処理**
   - 切り替え失敗時は自動的にロールバック
   - エラー時は元の状態に完全に戻る

### ユーザーへの推奨事項
- OAuth 2.0認証は事業所の共有Googleアカウントで実施
- 個人アカウントで認証した場合、退職時にカレンダーが削除される可能性がある

---

## 実装の優先順位

### Phase 1: OAuth 2.0実装（2〜3週間）
- OAuth認証フロー
- カレンダー自動作成
- トークン管理
- フロントエンドUI

### Phase 2: サービスアカウントのマルチテナント化（1週間）
- けいかくん側のサービスアカウント作成
- カレンダーID入力のみのUI
- ステップガイドの改善

### Phase 3: 切り替え機能（1週間）
- 認証方式切り替えAPI
- 確認ダイアログ
- エラーハンドリング

### Phase 4: テスト・ドキュメント（1週間）
- 統合テスト
- ユーザーガイド作成
- E2Eテスト

**総実装期間**: 約5〜6週間

---

## 既存実装との差異

### 現在の実装
- サービスアカウント方式のみ
- ユーザーが各自でGoogle Cloud Consoleでサービスアカウントを作成
- JSONキーファイルをアップロード

### 新しい実装
- OAuth 2.0とサービスアカウントの両方をサポート
- OAuth 2.0: 完全自動化
- サービスアカウント: けいかくん側で一元管理、ユーザーはカレンダーIDのみ入力
- 管理者メニューで切り替え可能

---

## よくある質問

**Q: 両方の認証方式を同時に使えますか？**
A: いいえ、1事業所につき1つの認証方式のみ使用可能です。切り替えは可能です。

**Q: 切り替え後、元に戻せますか？**
A: はい、いつでも切り替え可能です。ただし、古いカレンダーのイベントは元の場所に残ります。

**Q: OAuth 2.0で作成されたカレンダーは誰が所有しますか？**
A: OAuth認証を行ったユーザーのGoogleアカウントが所有します。事業所の共有アカウントでの認証を推奨します。

**Q: どちらの方式がおすすめですか？**
A: 新規ユーザーはOAuth 2.0（簡単）、既存カレンダーがある場合はサービスアカウントを推奨します。
