# けいかくん - 技術アーキテクチャと処理フロー詳細

**最終更新**: 2026年1月25日
**バージョン**: 1.0
**管理者**: Claude Sonnet 4.5

---

## 目次

1. [概要](#概要)
2. [技術スタック全体像](#技術スタック全体像)
3. [アーキテクチャ図](#アーキテクチャ図)
4. [機能別処理フロー](#機能別処理フロー)
5. [インフラストラクチャ](#インフラストラクチャ)
6. [セキュリティ実装](#セキュリティ実装)
7. [データフロー図](#データフロー図)

---

## 概要

けいかくんは、福祉サービス事業所向けの個別支援計画管理システムです。FastAPI（バックエンド）と Next.js（フロントエンド）を中心に構築され、Google Cloud Run、AWS S3、PostgreSQL などのクラウドサービスと連携しています。

### システムの特徴

- **非同期処理**: FastAPI + SQLAlchemy (Async) による高速な API レスポンス
- **サーバーレス**: Google Cloud Run によるオートスケーリング
- **マルチテナント**: 複数の事業所を単一システムで管理
- **サブスクリプション課金**: Stripe による月額/年額課金
- **リアルタイム通知**: Web Push、メール、カレンダー連携

---

## 技術スタック全体像

### バックエンド

```
┌─────────────────────────────────────────────────────┐
│              Google Cloud Run (FastAPI)             │
├─────────────────────────────────────────────────────┤
│                                                     │
│  FastAPI 0.115.0                                    │
│    ├─ Uvicorn (開発: ホットリロード)                │
│    └─ Gunicorn + Uvicorn Worker (本番)              │
│                                                     │
│  SQLAlchemy 2.0.41 (Async)                          │
│    ├─ psycopg 3.1.8+ (非同期 PostgreSQL ドライバ)   │
│    └─ Alembic 1.16.4 (マイグレーション)             │
│                                                     │
│  認証・セキュリティ                                  │
│    ├─ python-jose (JWT 生成・検証)                   │
│    ├─ passlib + bcrypt (パスワードハッシュ)          │
│    ├─ pyotp + qrcode (2FA: TOTP)                    │
│    ├─ fastapi-csrf-protect (CSRF 保護)              │
│    └─ slowapi (レート制限)                          │
│                                                     │
│  外部連携                                            │
│    ├─ stripe (サブスクリプション課金)                │
│    ├─ boto3 (AWS S3: PDF ストレージ)                │
│    ├─ fastapi-mail (SMTP メール送信)                │
│    ├─ google-api-python-client (Google Calendar)   │
│    ├─ pywebpush + py-vapid (Web Push 通知)         │
│    └─ httpx (非同期 HTTP クライアント)               │
│                                                     │
│  バックグラウンド処理                                │
│    ├─ APScheduler 3.10.4 (バッチジョブ)             │
│    └─ tenacity 8.2.0+ (リトライロジック)            │
│                                                     │
└─────────────────────────────────────────────────────┘
```

### フロントエンド

```
┌─────────────────────────────────────────────────────┐
│              Vercel (Next.js)                       │
├─────────────────────────────────────────────────────┤
│                                                     │
│  Next.js 16.1.4 (App Router)                        │
│    ├─ React 19.2.3                                  │
│    ├─ Turbopack (高速バンドラー)                     │
│    └─ TypeScript 5.x                                │
│                                                     │
│  UI ライブラリ                                       │
│    ├─ Tailwind CSS 4.x                              │
│    ├─ Radix UI (アクセシブル UI コンポーネント)      │
│    ├─ lucide-react (アイコン)                       │
│    └─ next-themes (ダークモード)                    │
│                                                     │
│  フォーム・バリデーション                            │
│    ├─ react-hook-form 7.62.0                        │
│    └─ zod 4.1.4 (型安全バリデーション)              │
│                                                     │
│  その他                                              │
│    ├─ react-dropzone (ファイルアップロード)          │
│    ├─ qrcode.react (QR コード生成)                  │
│    └─ sonner (トースト通知)                         │
│                                                     │
└─────────────────────────────────────────────────────┘
```

### インフラストラクチャ

| サービス | 用途 | 技術 |
|---------|------|------|
| **API サーバー** | FastAPI ホスティング | Google Cloud Run (asia-northeast1) |
| **フロントエンド** | Next.js ホスティング | Vercel |
| **データベース** | メインストア | PostgreSQL (Neon マネージド) |
| **ファイルストレージ** | PDF 保存 | AWS S3 |
| **コンテナレジストリ** | Docker イメージ保存 | Google Artifact Registry |
| **CI/CD** | 自動デプロイ | GitHub Actions + Cloud Build |
| **課金処理** | サブスクリプション | Stripe |
| **メール送信** | SMTP | fastapi-mail (AWS SES 対応) |
| **カレンダー連携** | イベント管理 | Google Calendar API |

---

## アーキテクチャ図

### システム全体構成

```mermaid
graph TB
    subgraph "Client Layer"
        User[ユーザー<br/>ブラウザ]
    end

    subgraph "Frontend Layer (Vercel)"
        NextJS[Next.js 16.1.4<br/>React 19.2.3<br/>TypeScript]
    end

    subgraph "API Layer (Google Cloud Run)"
        FastAPI[FastAPI 0.115.0<br/>Gunicorn + Uvicorn]
        Scheduler[APScheduler<br/>バッチジョブ]
    end

    subgraph "Data Layer"
        PostgreSQL[(PostgreSQL<br/>Neon)]
        S3[(AWS S3<br/>PDF Storage)]
    end

    subgraph "External Services"
        Stripe[Stripe<br/>課金]
        GoogleCal[Google Calendar<br/>予定管理]
        SMTP[SMTP Server<br/>メール送信]
        WebPush[Web Push<br/>ブラウザ通知]
    end

    User -->|HTTPS| NextJS
    NextJS -->|REST API<br/>JWT Cookie| FastAPI
    FastAPI -->|SQLAlchemy<br/>Async| PostgreSQL
    FastAPI -->|boto3| S3
    FastAPI -->|stripe SDK| Stripe
    FastAPI -->|google-api-client| GoogleCal
    FastAPI -->|fastapi-mail| SMTP
    FastAPI -->|pywebpush| WebPush
    Scheduler -.->|定期実行| FastAPI
    Stripe -.->|Webhook| FastAPI
```

### バックエンド 4層アーキテクチャ

```
┌──────────────────────────────────────────────────┐
│         API 層 (endpoints/)                      │
│  - HTTP リクエスト/レスポンス処理                │
│  - 認証・認可チェック                             │
│  - 入力バリデーション (Pydantic)                  │
└──────────────────────────────────────────────────┘
                     ↓
┌──────────────────────────────────────────────────┐
│       Services 層 (services/)                    │
│  - ビジネスロジック実装                          │
│  - 複数 CRUD 操作の統合                          │
│  - トランザクション管理                          │
│  - DTO 生成                                       │
└──────────────────────────────────────────────────┘
                     ↓
┌──────────────────────────────────────────────────┐
│         CRUD 層 (crud/)                          │
│  - 単一モデルの CRUD 操作                        │
│  - データベース抽象化                            │
│  - selectinload() による N+1 問題回避           │
└──────────────────────────────────────────────────┘
                     ↓
┌──────────────────────────────────────────────────┐
│        Models 層 (models/)                       │
│  - SQLAlchemy モデル定義                         │
│  - リレーションシップ定義                        │
│  - テーブルスキーマ                              │
└──────────────────────────────────────────────────┘
```

---

## 機能別処理フロー

### 1. 認証・認可フロー

#### 使用技術

- **JWT**: python-jose (HS256)
- **パスワードハッシュ**: bcrypt (passlib)
- **2FA**: pyotp (TOTP), qrcode
- **CSRF**: fastapi-csrf-protect
- **Cookie**: HTTPOnly, Secure, SameSite

#### 処理フロー

```mermaid
sequenceDiagram
    participant User as ユーザー
    participant Frontend as Next.js
    participant API as FastAPI
    participant DB as PostgreSQL

    User->>Frontend: 1. ログイン (email, password)
    Frontend->>API: POST /api/v1/auth/login
    API->>DB: スタッフ情報取得
    DB-->>API: Staff (hashed_password, mfa_enabled)

    alt MFA無効
        API->>API: bcrypt でパスワード検証
        API->>API: JWT トークン生成 (7日間有効)
        API-->>Frontend: Set-Cookie: access_token (HTTPOnly)
        Frontend-->>User: ログイン成功
    else MFA有効
        API->>API: bcrypt でパスワード検証
        API-->>Frontend: MFA 必要レスポンス
        User->>Frontend: 2FA コード入力
        Frontend->>API: POST /api/v1/auth/verify-mfa
        API->>API: pyotp で TOTP 検証
        API->>API: JWT トークン生成
        API-->>Frontend: Set-Cookie: access_token
        Frontend-->>User: ログイン成功
    end

    Note over Frontend,API: 以降のリクエストは Cookie で認証
    User->>Frontend: 3. 保護されたページアクセス
    Frontend->>API: GET /api/v1/... (Cookie 自動送信)
    API->>API: get_current_user() - JWT 検証
    API->>DB: スタッフ・事業所情報取得
    DB-->>API: Staff + Associations
    API->>API: 権限チェック (role, office_id)
    API-->>Frontend: データレスポンス
```

#### コード参照

- 認証: `k_back/app/api/v1/endpoints/auths.py`
- JWT 検証: `k_back/app/core/security.py`
- 依存性注入: `k_back/app/api/deps.py`

---

### 2. PDF アップロード・管理フロー

#### 使用技術

- **ファイル処理**: FastAPI UploadFile (multipart/form-data)
- **S3 SDK**: boto3
- **暗号化**: S3 server-side encryption
- **署名付き URL**: boto3 presigned URL (有効期限 1時間)

#### 処理フロー

```mermaid
sequenceDiagram
    participant User as ユーザー
    participant Frontend as Next.js
    participant CloudRun as Google Cloud Run
    participant S3 as AWS S3
    participant DB as PostgreSQL

    User->>Frontend: 1. PDF ドラッグ&ドロップ
    Frontend->>Frontend: ファイル検証<br/>(PDF形式, 10MB以下)

    Frontend->>CloudRun: 2. POST /api/v1/support-plans/plan-deliverables<br/>FormData(file, plan_cycle_id, deliverable_type)
    Note over Frontend,CloudRun: Cookie で JWT 認証

    CloudRun->>CloudRun: 3. JWT 認証検証
    CloudRun->>CloudRun: 4. Content-Type 検証<br/>(application/pdf)
    CloudRun->>DB: 5. 権限チェック<br/>(plan_cycle, office_id)
    DB-->>CloudRun: plan_cycle 情報

    CloudRun->>CloudRun: 6. Employee 権限拒否
    CloudRun->>CloudRun: 7. ファイル読み取り<br/>await file.read()
    CloudRun->>CloudRun: 8. UUID 付きファイル名生成<br/>{uuid}_{filename}

    CloudRun->>S3: 9. boto3.upload_fileobj()<br/>ContentType: application/pdf<br/>ContentDisposition: inline
    S3-->>CloudRun: S3 URL<br/>s3://bucket/plan-deliverables/...

    CloudRun->>DB: 10. メタデータ保存<br/>plan_deliverables テーブル
    CloudRun->>DB: 11. ステータス更新<br/>completed: true
    DB-->>CloudRun: deliverable オブジェクト

    CloudRun-->>Frontend: 201 Created
    Frontend->>Frontend: UI 更新
    Frontend-->>User: アップロード完了

    Note over User,S3: PDF 取得フロー
    User->>Frontend: 12. PDF プレビュー表示
    Frontend->>CloudRun: GET /api/v1/support-plans/{recipient_id}/cycles
    CloudRun->>DB: deliverable 取得 (file_path)
    DB-->>CloudRun: s3://bucket/path/file.pdf

    CloudRun->>S3: 13. 署名付き URL 生成<br/>generate_presigned_url()<br/>有効期限: 3600秒
    S3-->>CloudRun: https://s3.../file.pdf?Signature=...

    CloudRun-->>Frontend: JSON (presigned_url)
    Frontend->>S3: 14. GET presigned_url
    S3-->>Frontend: PDF ファイル
    Frontend->>Frontend: iframe でプレビュー
```

#### データベーステーブル

**plan_deliverables**:
- `id`: Primary Key
- `plan_cycle_id`: FK to support_plan_cycles
- `deliverable_type`: Enum (assessment_sheet, draft_plan_pdf, etc.)
- `file_path`: S3 URL (s3://bucket/path/file.pdf)
- `original_filename`: ユーザーがアップロードした元ファイル名
- `uploaded_at`: アップロード日時
- `uploaded_by_staff_id`: FK to staffs

#### コード参照

- アップロード: `k_back/app/api/v1/endpoints/support_plans.py:151-230`
- S3 処理: `k_back/app/core/storage.py`

---

### 3. メール送信フロー

#### 使用技術

- **ライブラリ**: fastapi-mail
- **プロトコル**: SMTP (AWS SES 対応)
- **テンプレート**: Jinja2 (HTML)
- **リトライ**: tenacity (指数バックオフ, 最大3回)

#### 処理フロー

```mermaid
sequenceDiagram
    participant Trigger as トリガー<br/>(API/Scheduler)
    participant Service as メールサービス
    participant FastMail as fastapi-mail
    participant SMTP as SMTP Server<br/>(AWS SES)
    participant Recipient as 受信者

    Trigger->>Service: 1. メール送信要求<br/>(email, subject, template, context)
    Service->>Service: 2. Jinja2 テンプレート読込<br/>(templates/email/*.html)
    Service->>Service: 3. コンテキスト変数を埋め込み

    Service->>FastMail: 4. MessageSchema 作成<br/>+ ConnectionConfig
    Note over Service,FastMail: MAIL_SERVER, MAIL_PORT,<br/>MAIL_USERNAME, MAIL_PASSWORD

    FastMail->>SMTP: 5. SMTP 接続 (TLS/STARTTLS)
    FastMail->>SMTP: 6. HTML メール送信
    SMTP-->>FastMail: 送信成功

    alt 送信失敗
        FastMail->>Service: エラー
        Service->>Service: tenacity でリトライ<br/>(指数バックオフ)
        Service->>FastMail: 再送信試行
    end

    FastMail-->>Service: 送信完了
    Service-->>Trigger: 成功レスポンス

    SMTP->>Recipient: 7. メール配信
```

#### メール種別

| テンプレート | 用途 | トリガー |
|-------------|------|---------|
| `verify_email.html` | メールアドレス確認 | 新規登録 |
| `password_reset.html` | パスワードリセット | パスワード忘れ |
| `deadline_alert.html` | 期限アラート | APScheduler (毎日 0:00 UTC) |
| `inquiry_received.html` | 問い合わせ受信 | ユーザーからの問い合わせ |
| `inquiry_reply.html` | 問い合わせ返信 | 管理者の返信 |

#### 環境変数

```bash
MAIL_SERVER=email-smtp.ap-northeast-1.amazonaws.com  # AWS SES SMTP
MAIL_PORT=587
MAIL_USERNAME=AKIAXXXXXXXXXXXXXXXX
MAIL_PASSWORD=XXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXX
MAIL_FROM=noreply@keikakun.com
MAIL_STARTTLS=True
```

#### コード参照

- メール送信: `k_back/app/core/mail.py`
- テンプレート: `k_back/app/templates/email/`

---

### 4. Google Calendar 連携フロー (サービスアカウント方式)

#### 使用技術

- **認証**: Google Service Account
- **SDK**: google-api-python-client
- **暗号化**: cryptography.fernet (対称鍵暗号)
- **スコープ**: `https://www.googleapis.com/auth/calendar`

#### 初期設定フロー

```mermaid
sequenceDiagram
    participant User as 事業所担当者
    participant GCP as Google Cloud Console
    participant Frontend as Next.js
    participant API as FastAPI
    participant DB as PostgreSQL

    User->>GCP: 1. プロジェクト作成
    User->>GCP: 2. Calendar API 有効化
    User->>GCP: 3. サービスアカウント作成
    GCP-->>User: 4. JSON キーファイル<br/>ダウンロード

    User->>User: 5. Google Calendar で<br/>カレンダー作成
    User->>User: 6. サービスアカウントの<br/>メールアドレスに<br/>「予定の変更」権限付与
    User->>User: 7. カレンダー ID 取得

    User->>Frontend: 8. JSON + カレンダー ID<br/>アップロード
    Frontend->>API: POST /api/v1/calendar/setup

    API->>API: 9. JSON から<br/>service_account_email 抽出
    API->>API: 10. Fernet で暗号化<br/>(CALENDAR_ENCRYPTION_KEY)
    API->>DB: 11. office_calendar_accounts<br/>テーブルに保存
    DB-->>API: アカウント作成完了

    API-->>Frontend: 設定完了
    Frontend-->>User: カレンダー連携成功
```

#### イベント作成フロー

```mermaid
sequenceDiagram
    participant Scheduler as APScheduler
    participant Service as CalendarService
    participant Client as GoogleCalendarClient
    participant DB as PostgreSQL
    participant GoogleAPI as Google Calendar API

    Scheduler->>Service: 1. イベント作成要求<br/>(renewal deadline)
    Service->>DB: 2. office_calendar_account 取得
    DB-->>Service: encrypted_service_account_key

    Service->>Service: 3. Fernet で復号化
    Service->>Client: 4. GoogleCalendarClient 初期化<br/>(JSON キー)

    Client->>Client: 5. service_account.Credentials<br/>.from_service_account_info()
    Client->>Client: 6. build('calendar', 'v3')

    Service->>Client: 7. create_event()<br/>(calendar_id, title, start, end)
    Client->>GoogleAPI: 8. events().insert()<br/>calendarId, body
    GoogleAPI-->>Client: event_id

    Client-->>Service: event_id
    Service->>DB: 9. calendar_events テーブルに保存<br/>(google_event_id)
    DB-->>Service: 保存完了

    Service-->>Scheduler: イベント作成成功
```

#### データベーステーブル

**office_calendar_accounts**:
- `id`: Primary Key (UUID)
- `office_id`: FK to offices (1:1)
- `google_calendar_id`: カレンダー ID
- `service_account_key`: 暗号化された JSON キー (Text)
- `service_account_email`: サービスアカウントメールアドレス
- `connection_status`: Enum (connected, not_connected, error)

**calendar_events**:
- `id`: Primary Key
- `google_event_id`: Google Calendar のイベント ID
- `office_id`: FK to offices
- `welfare_recipient_id`: FK to welfare_recipients
- `event_type`: Enum (renewal_deadline, assessment, etc.)
- `sync_status`: Enum (synced, pending, failed)

#### セキュリティ対策

| 対策 | 実装 |
|------|------|
| **暗号化保存** | Fernet (対称鍵暗号) で JSON キー暗号化 |
| **最小権限** | サービスアカウントは共有されたカレンダーのみにアクセス |
| **権限エラー** | 未共有カレンダーへのアクセスは 403 エラーで停止 |
| **環境変数管理** | CALENDAR_ENCRYPTION_KEY で暗号化キー管理 |

#### コード参照

- カレンダーサービス: `k_back/app/services/calendar_service.py`
- Google クライアント: `k_back/app/services/google_calendar_client.py`
- モデル: `k_back/app/models/calendar_account.py`

---

### 5. Stripe サブスクリプション課金フロー

#### 使用技術

- **SDK**: stripe (Python)
- **決済方法**: クレジットカード (Stripe Elements)
- **課金タイプ**: 月額 ¥6,000 (税込)
- **Webhook**: 署名検証 (STRIPE_WEBHOOK_SECRET)

#### サブスクリプション作成フロー

```mermaid
sequenceDiagram
    participant User as 事務所オーナー
    participant Frontend as Next.js
    participant API as FastAPI
    participant Stripe as Stripe API
    participant DB as PostgreSQL

    User->>Frontend: 1. プラン選択<br/>(月額¥6,000)
    Frontend->>API: POST /api/v1/billing/create-checkout-session
    API->>Stripe: 2. Checkout Session 作成<br/>(price_id, customer_email)
    Stripe-->>API: session_url
    API-->>Frontend: checkout_url

    Frontend->>Stripe: 3. Stripe Checkout にリダイレクト
    User->>Stripe: 4. カード情報入力・決済
    Stripe->>Stripe: 5. Customer & Subscription 作成

    Stripe->>API: 6. Webhook: checkout.session.completed
    API->>API: 7. 署名検証<br/>(stripe.Webhook.construct_event)
    API->>DB: 8. Billing レコード作成/更新<br/>(status: active, stripe_customer_id)
    DB-->>API: 保存完了

    Stripe-->>Frontend: 9. リダイレクト (success_url)
    Frontend-->>User: 課金開始完了
```

#### Webhook イベント処理

| Webhook イベント | 処理内容 | Billing Status |
|-----------------|---------|---------------|
| `checkout.session.completed` | 初回課金成功 | `active` |
| `invoice.payment_succeeded` | 継続課金成功 | `active` |
| `invoice.payment_failed` | 支払い失敗 | `past_due` |
| `customer.subscription.deleted` | サブスクリプション削除 | `canceled` |

#### 課金ステータス管理

```
free (無料トライアル)
  ↓
early_payment (トライアル中の早期決済)
  ↓
active (課金中)
  ↓ (支払い失敗)
past_due (支払い遅延)
  ↓
canceled (キャンセル)
```

#### Webhook 冪等性処理

**webhook_events テーブル**:
- `stripe_event_id`: Stripe イベント ID (Unique)
- `event_type`: イベントタイプ
- `processed_at`: 処理日時

```python
# 重複処理防止
existing_event = await db.execute(
    select(WebhookEvent).where(WebhookEvent.stripe_event_id == event_id)
)
if existing_event.scalar_one_or_none():
    return  # 既に処理済み
```

#### コード参照

- Webhook 処理: `k_back/app/api/test_billing.py`
- サービス層: `k_back/app/services/billing_service.py`

---

### 6. Web Push 通知フロー

#### 使用技術

- **プロトコル**: Web Push Protocol (RFC 8030)
- **認証**: VAPID (Voluntary Application Server Identification)
- **SDK**: pywebpush (Python), Web Push API (JavaScript)
- **暗号化**: ECDH (Elliptic Curve Diffie-Hellman)

#### サブスクリプション登録フロー

```mermaid
sequenceDiagram
    participant User as ユーザー
    participant Browser as ブラウザ
    participant Frontend as Next.js
    participant API as FastAPI
    participant DB as PostgreSQL

    User->>Frontend: 1. 通知許可をリクエスト
    Frontend->>Browser: 2. Notification.requestPermission()
    Browser-->>User: 通知許可ダイアログ
    User->>Browser: 3. 許可
    Browser-->>Frontend: granted

    Frontend->>Browser: 4. serviceWorker.register()
    Browser-->>Frontend: ServiceWorker 登録完了

    Frontend->>Browser: 5. pushManager.subscribe()<br/>(VAPID 公開鍵)
    Browser->>Browser: 6. Push サブスクリプション生成<br/>(endpoint, keys)
    Browser-->>Frontend: PushSubscription オブジェクト

    Frontend->>API: 7. POST /api/v1/push-subscriptions<br/>(endpoint, p256dh, auth)
    API->>DB: 8. push_subscriptions テーブルに保存
    DB-->>API: 保存完了
    API-->>Frontend: 201 Created
```

#### 通知送信フロー

```mermaid
sequenceDiagram
    participant Scheduler as APScheduler
    participant Service as 通知サービス
    participant DB as PostgreSQL
    participant PyWebPush as pywebpush
    participant PushService as Push Service<br/>(FCM/Mozilla)
    participant Browser as ユーザーブラウザ

    Scheduler->>Service: 1. 期限アラート送信<br/>(毎日 0:00 UTC)
    Service->>DB: 2. 対象利用者取得<br/>(期限7日前)
    DB-->>Service: 利用者リスト

    Service->>DB: 3. スタッフの<br/>push_subscriptions 取得
    DB-->>Service: subscription データ

    loop 各サブスクリプション
        Service->>PyWebPush: 4. webpush()<br/>(subscription, payload, VAPID)
        PyWebPush->>PyWebPush: 5. VAPID 署名生成
        PyWebPush->>PyWebPush: 6. ペイロード暗号化<br/>(ECDH)

        PyWebPush->>PushService: 7. HTTP POST<br/>(endpoint, encrypted payload)

        alt 成功 (201 Created)
            PushService-->>PyWebPush: 成功
            PyWebPush-->>Service: 送信成功
        else 失敗 (410 Gone)
            PushService-->>PyWebPush: サブスクリプション無効
            PyWebPush-->>Service: 410 エラー
            Service->>DB: サブスクリプション削除
        end
    end

    PushService->>Browser: 8. Push 通知配信
    Browser->>Browser: 9. Service Worker 起動
    Browser->>User: 10. 通知表示
```

#### データベーステーブル

**push_subscriptions**:
- `id`: Primary Key
- `staff_id`: FK to staffs
- `endpoint`: Push サービスエンドポイント (Unique)
- `p256dh`: 公開鍵 (暗号化用)
- `auth`: 認証シークレット
- `created_at`: 登録日時

#### VAPID 設定

```bash
# バックエンド環境変数
VAPID_PRIVATE_KEY=<Base64エンコードされた秘密鍵>
VAPID_PUBLIC_KEY=<Base64エンコードされた公開鍵>
VAPID_SUBJECT=mailto:support@keikakun.com

# フロントエンド環境変数
NEXT_PUBLIC_VAPID_PUBLIC_KEY=<公開鍵>
```

#### コード参照

- Push サービス: `k_back/app/core/push.py`
- API: `k_back/app/api/v1/endpoints/push_subscriptions.py`
- フロントエンド: `k_front/hooks/usePushNotification.ts`

---

### 7. 期限アラートバッチ処理フロー

#### 使用技術

- **スケジューラー**: APScheduler
- **実行タイミング**: 毎日 0:00 UTC (日本時間 9:00)
- **通知チャネル**: メール + Web Push

#### 処理フロー

```mermaid
sequenceDiagram
    participant Scheduler as APScheduler
    participant Task as 期限通知タスク
    participant DB as PostgreSQL
    participant Mail as メールサービス
    participant Push as Push サービス

    Note over Scheduler: 毎日 0:00 UTC
    Scheduler->>Task: 1. run_deadline_notification()

    Task->>DB: 2. 更新期限が近い利用者を検索<br/>(7日以内)
    DB-->>Task: 利用者リスト

    Task->>DB: 3. アセスメント未完了の<br/>利用者を検索
    DB-->>Task: 利用者リスト

    loop 各事業所
        Task->>DB: 4. 事業所のスタッフ取得<br/>(role: manager/owner)
        DB-->>Task: スタッフリスト

        loop 各スタッフ
            Task->>Mail: 5. メール送信<br/>(deadline_alert.html)
            Mail-->>Task: 送信完了

            Task->>Push: 6. Web Push 通知<br/>(期限アラート)
            Push-->>Task: 送信完了

            Task->>DB: 7. 監査ログ記録<br/>(audit_logs)
            DB-->>Task: 保存完了
        end
    end

    Task-->>Scheduler: 処理完了
```

#### バッチジョブ一覧

| ジョブ名 | スケジュール | 処理内容 |
|---------|-------------|---------|
| **deadline_notification** | 毎日 0:00 UTC | 期限アラート送信 |
| **calendar_sync** | 1時間ごと | Google Calendar 同期 |
| **cleanup** | 毎日 3:00 UTC | 古いデータクリーンアップ |
| **billing_check** | 毎日 0:00 UTC | 無料トライアル期限チェック |

#### コード参照

- スケジューラー: `k_back/app/scheduler/deadline_notification_scheduler.py`
- タスク: `k_back/app/tasks/deadline_notification.py`

---

## インフラストラクチャ

### Google Cloud Run 構成

#### デプロイ設定

```yaml
# k_back/cloudbuild.yml
- name: 'gcr.io/google.com/cloudsdktool/cloud-sdk'
  entrypoint: gcloud
  args:
    - 'run'
    - 'deploy'
    - 'k-back'
    - '--image'
    - 'asia-northeast1-docker.pkg.dev/$PROJECT_ID/k-back-repo/k-back:latest'
    - '--region'
    - 'asia-northeast1'  # 東京リージョン
    - '--platform'
    - 'managed'
    - '--allow-unauthenticated'  # 公開アクセス
    - '--update-env-vars'
    - '<環境変数リスト>'
```

#### 自動提供される機能

| 機能 | 説明 |
|------|------|
| **HTTPS ロードバランサー** | 自動提供 (Let's Encrypt 証明書) |
| **オートスケーリング** | 0〜N インスタンス (トラフィックに応じて) |
| **ヘルスチェック** | 不健全なインスタンス自動除外 |
| **DDoS 保護** | Google Cloud Armor (基本レベル) |
| **グローバル Anycast IP** | 最適なリージョンにルーティング |

#### Docker イメージ構成

```dockerfile
# ベースイメージ
FROM python:3.12-slim-bullseye AS base

# 本番環境
FROM base AS production
RUN addgroup --system --gid 1001 pythonuser && \
    adduser --system --uid 1001 pythonuser
USER pythonuser
EXPOSE 8080
CMD exec gunicorn -w 1 -k uvicorn.workers.UvicornWorker \
    -b "0.0.0.0:${PORT}" app.main:app
```

### CI/CD パイプライン

```
GitHub Push (main)
  ↓
GitHub Actions
  ├─ Python セットアップ
  ├─ 依存関係インストール
  ├─ pytest 実行 (全テスト)
  └─ テスト成功
      ↓
  GCP 認証
      ↓
  Cloud Build Submit
      ├─ Docker イメージビルド (production)
      ├─ Artifact Registry Push
      └─ Cloud Run Deploy
          ↓
  HTTPS エンドポイント公開
```

### ネットワークセキュリティ

| レイヤー | 実装 |
|---------|------|
| **TLS/HTTPS** | Cloud Run 自動提供 (強制) |
| **CORS** | FastAPI Middleware (オリジン制限) |
| **JWT 認証** | FastAPI Dependency |
| **CSRF 保護** | fastapi-csrf-protect |
| **Rate Limiting** | slowapi (IP ベース) |
| **入力検証** | Pydantic (SQL Injection/XSS 対策) |

---

## セキュリティ実装

### 多層防御アーキテクチャ

```
┌─────────────────────────────────────────────────────┐
│  Layer 1: ネットワーク層                            │
│  - TLS 1.2+ (強制)                                   │
│  - HTTPS のみ許可                                    │
│  - Cloud Run DDoS 保護                               │
└─────────────────────────────────────────────────────┘
                     ↓
┌─────────────────────────────────────────────────────┐
│  Layer 2: アプリケーション層                         │
│  - CORS (許可されたオリジンのみ)                     │
│  - Rate Limiting (slowapi)                          │
│  - CSRF 保護 (トークン検証)                          │
└─────────────────────────────────────────────────────┘
                     ↓
┌─────────────────────────────────────────────────────┐
│  Layer 3: 認証・認可層                               │
│  - JWT 認証 (HTTPOnly Cookie)                       │
│  - 2FA (TOTP)                                        │
│  - 役割ベースアクセス制御 (RBAC)                     │
│  - 事業所単位のデータ分離                            │
└─────────────────────────────────────────────────────┘
                     ↓
┌─────────────────────────────────────────────────────┐
│  Layer 4: データ層                                   │
│  - SQL Injection 防止 (パラメータ化クエリ)           │
│  - XSS 防止 (Pydantic 検証 + HTML エスケープ)        │
│  - パスワードハッシュ (bcrypt)                       │
│  - 暗号化 (サービスアカウントキー, トークン)         │
└─────────────────────────────────────────────────────┘
                     ↓
┌─────────────────────────────────────────────────────┐
│  Layer 5: 監査・ロギング層                           │
│  - audit_logs テーブル (全操作記録)                  │
│  - Webhook 冪等性 (重複処理防止)                     │
│  - PII マスキング (ログ出力時)                       │
└─────────────────────────────────────────────────────┘
```

### パスワードセキュリティ

```python
# bcrypt でハッシュ化 (コスト: 12)
from passlib.context import CryptContext

pwd_context = CryptContext(schemes=["bcrypt"], deprecated="auto")

# ハッシュ生成
hashed = pwd_context.hash("plain_password")  # $2b$12$...

# 検証
pwd_context.verify("plain_password", hashed)  # True/False
```

### 暗号化実装

| データ | 暗号化方式 | キー管理 |
|--------|----------|---------|
| **サービスアカウントキー** | Fernet (対称鍵) | CALENDAR_ENCRYPTION_KEY (環境変数) |
| **JWT シークレット** | HS256 | SECRET_KEY (環境変数) |
| **S3 ファイル** | SSE-S3 | AWS 管理 |
| **通信** | TLS 1.2+ | Cloud Run 自動管理 |

---

## データフロー図

### 個別支援計画管理の全体フロー

```mermaid
graph TD
    subgraph "1. ユーザー登録・認証"
        A1[新規登録] --> A2[メール確認]
        A2 --> A3[ログイン JWT]
        A3 --> A4{2FA 有効?}
        A4 -->|Yes| A5[TOTP 検証]
        A4 -->|No| A6[認証完了]
        A5 --> A6
    end

    subgraph "2. 課金管理"
        B1[Stripe Checkout] --> B2[Webhook 受信]
        B2 --> B3[Billing 更新]
        B3 --> B4{ステータス}
        B4 -->|active| B5[全機能利用可能]
        B4 -->|past_due| B6[読み取り専用モード]
    end

    subgraph "3. 利用者管理"
        C1[利用者登録] --> C2[個別支援計画サイクル作成]
        C2 --> C3[ステータス管理]
        C3 --> C4[PDF アップロード]
        C4 --> C5[S3 保存]
    end

    subgraph "4. カレンダー連携"
        D1[サービスアカウント設定] --> D2[暗号化保存]
        D2 --> D3[期限イベント自動作成]
        D3 --> D4[Google Calendar 同期]
    end

    subgraph "5. 通知システム"
        E1[APScheduler 0:00 UTC] --> E2[期限チェック]
        E2 --> E3[対象利用者抽出]
        E3 --> E4[メール送信]
        E3 --> E5[Web Push 送信]
    end

    A6 --> B1
    B5 --> C1
    C2 --> D3
    C2 --> E2
```

### データベース ER 図（主要テーブル）

```
┌─────────────────┐
│    offices      │
│─────────────────│
│ id (PK)         │
│ name            │
│ billing_id (FK) │◄─────┐
└─────────────────┘      │
         │               │
         │ 1:N           │
         ▼               │
┌─────────────────┐      │
│    staffs       │      │
│─────────────────│      │
│ id (PK)         │      │
│ email           │      │
│ hashed_password │      │
│ role            │      │
│ mfa_enabled     │      │
└─────────────────┘      │
         │               │
         │ N:M           │
         ▼               │
┌──────────────────────┐ │
│ welfare_recipients   │ │
│──────────────────────│ │
│ id (PK)              │ │
│ full_name            │ │
└──────────────────────┘ │
         │               │
         │ 1:N           │
         ▼               │
┌──────────────────────┐ │
│ support_plan_cycles  │ │
│──────────────────────│ │
│ id (PK)              │ │
│ welfare_recipient_id │ │
│ cycle_number         │ │
│ is_latest_cycle      │ │
└──────────────────────┘ │
         │               │
         │ 1:N           │
         ▼               │
┌──────────────────────┐ │
│ plan_deliverables    │ │
│──────────────────────│ │
│ id (PK)              │ │
│ plan_cycle_id (FK)   │ │
│ deliverable_type     │ │
│ file_path (S3 URL)   │ │
└──────────────────────┘ │
                         │
┌─────────────────┐      │
│    billings     │──────┘
│─────────────────│
│ id (PK)         │
│ office_id (FK)  │
│ status          │
│ stripe_customer │
└─────────────────┘
```

---

## パフォーマンス最適化

### N+1 問題対策

```python
# ❌ 悪い例 (N+1 クエリ)
for cycle in cycles:
    for deliverable in cycle.deliverables:  # 追加クエリ発生
        print(deliverable.file_path)

# ✅ 良い例 (selectinload)
stmt = (
    select(SupportPlanCycle)
    .options(selectinload(SupportPlanCycle.deliverables))
)
cycles = await db.execute(stmt)
```

### 署名付き URL キャッシュ

```python
# PDF URL は 1時間有効なので、フロントエンドでキャッシュ可能
presigned_url = await storage.create_presigned_url(
    object_name=object_name,
    expiration=3600  # 1時間
)
```

### データベースインデックス

```sql
-- 頻繁に検索されるカラムにインデックス
CREATE INDEX idx_welfare_recipients_office_id ON welfare_recipients(office_id);
CREATE INDEX idx_support_plan_cycles_latest ON support_plan_cycles(is_latest_cycle);
CREATE INDEX idx_calendar_events_sync_status ON calendar_events(sync_status);
```

---

## 監視・ロギング

### 構造化ログ

```python
import logging

logger = logging.getLogger(__name__)

# 重要操作のログ
logger.info(f"[DEADLINE_NOTIFICATION] Sent alert to {staff.email}")
logger.warning(f"[WEB_PUSH] Subscription expired: {subscription.endpoint}")
logger.error(f"[BILLING] Webhook verification failed: {event_id}")
```

### 監査ログ

**audit_logs テーブル**:
- `action_type`: ActionType Enum (CREATE, UPDATE, DELETE, etc.)
- `resource_type`: ResourceType Enum (STAFF, PLAN, etc.)
- `staff_id`: 実行者
- `details`: JSON (変更内容)
- `ip_address`: リクエスト元 IP
- `created_at`: 実行日時

---

## 今後の技術的課題

### パフォーマンス最適化

- [ ] Redis 導入 (セッション、キャッシュ)
- [ ] データベースインデックス最適化
- [ ] CDN 導入 (静的コンテンツ)

### スケーラビリティ

- [ ] バッチ処理の並列化
- [ ] Cloud Run インスタンス数最適化
- [ ] PostgreSQL パーティショニング

### セキュリティ強化

- [ ] WAF (Web Application Firewall) 導入
- [ ] 定期的な脆弱性スキャン自動化
- [ ] OAuth 2.0 対応 (Google Calendar)

### 開発体験向上

- [ ] フロントエンド E2E テスト (Playwright)
- [ ] CI/CD パイプライン高速化
- [ ] OpenAPI ドキュメント自動生成

---

## 参考リンク

### 技術ドキュメント

- [tech_stack.md](../tech_stack.md) - 技術スタック一覧
- [CLAUDE.md](../../.claude/CLAUDE.md) - 開発ガイドライン
- [environment_variables_setup.md](../environment_variables_setup.md) - 環境変数設定

### 公式ドキュメント

- [FastAPI](https://fastapi.tiangolo.com/)
- [Next.js](https://nextjs.org/)
- [SQLAlchemy 2.0](https://docs.sqlalchemy.org/en/20/)
- [Stripe API](https://stripe.com/docs/api)
- [Google Calendar API](https://developers.google.com/calendar/api)
- [Web Push Protocol](https://web.dev/push-notifications-overview/)

---

**作成日**: 2026年1月25日
**最終更新**: 2026年1月25日
**管理者**: Claude Sonnet 4.5
