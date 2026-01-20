# けいかくん - 技術スタック

## 概要

けいかくんは、福祉サービス事業所向けの個別支援計画管理システムです。
このドキュメントでは、バックエンドとフロントエンドで使用している技術スタックを詳細に記載します。

---

## 📦 バックエンド (k_back)

### コア技術

| カテゴリ | 技術 | バージョン | 用途 |
|---------|------|-----------|------|
| **言語** | Python | 3.12 | アプリケーション開発言語 |
| **Webフレームワーク** | FastAPI | 0.115.0 | RESTful API構築 |
| **ASGIサーバー** | Uvicorn | 0.29.0 | 開発環境サーバー（ホットリロード） |
| **WSGIサーバー** | Gunicorn | latest | 本番環境サーバー（Cloud Run） |
| **ORM** | SQLAlchemy | 2.0.41 | データベース操作（非同期対応） |
| **データベース** | PostgreSQL | latest | メインデータストア |

### データベース関連

| 技術 | バージョン | 用途 |
|------|-----------|------|
| **psycopg** | 3.1.8+ | PostgreSQLドライバー（async対応） |
| **psycopg2-binary** | latest | PostgreSQL互換ドライバー |
| **Alembic** | 1.16.4 | データベースマイグレーション |

### データ検証・設定

| 技術 | バージョン | 用途 |
|------|-----------|------|
| **Pydantic** | 2.11.7 | スキーマ定義、バリデーション |
| **pydantic-settings** | 2.10.1 | 環境変数からの設定管理 |
| **python-dotenv** | 1.0.1 | .envファイル読み込み |
| **Zod** | 4.1.4 (フロント) | TypeScript型安全バリデーション |

### 認証・セキュリティ

| 技術 | バージョン | 用途 |
|------|-----------|------|
| **passlib[bcrypt]** | latest | パスワードハッシュ化 |
| **bcrypt** | 3.2.0 | パスワードハッシュアルゴリズム |
| **python-jose[cryptography]** | 3.3.0+ | JWT生成・検証 |
| **jwt** | latest | JWT処理 |
| **pyotp** | 2.8.0+ | 2要素認証（TOTP） |
| **qrcode[pil]** | 7.4.0+ | 2FA用QRコード生成 |
| **cryptography** | 3.4.8+ | 暗号化処理 |
| **fastapi-csrf-protect** | 0.3.4+ | CSRF保護 |
| **python-multipart** | latest | フォームデータ解析 |

### 決済・課金

| 技術 | バージョン | 用途 |
|------|-----------|------|
| **Stripe** | 7.0.0+ | サブスクリプション決済処理 |

### 通知システム

| 技術 | バージョン | 用途 |
|------|-----------|------|
| **fastapi-mail** | 1.4.1 | メール送信（期限アラート） |
| **pywebpush** | 1.14.0+ | Web Push通知送信 |
| **py-vapid** | 1.9.0+ | VAPID認証（Web Push） |

### 外部サービス連携

| 技術 | バージョン | 用途 |
|------|-----------|------|
| **google-api-python-client** | latest | Google Calendar API連携 |
| **google-auth** | latest | Google OAuth認証 |
| **google-auth-oauthlib** | latest | Google OAuthフロー |
| **boto3** | latest | AWS S3ファイルストレージ |

### バックグラウンド処理

| 技術 | バージョン | 用途 |
|------|-----------|------|
| **APScheduler** | 3.10.4 | バッチジョブスケジューリング |
| **tenacity** | 8.2.0+ | リトライロジック（メール送信など） |

### その他ユーティリティ

| 技術 | バージョン | 用途 |
|------|-----------|------|
| **slowapi** | latest | レートリミット |
| **jpholiday** | 0.1.8+ | 日本の祝日判定 |
| **httpx** | latest | 非同期HTTPクライアント（テスト用） |

### テスト

| 技術 | バージョン | 用途 |
|------|-----------|------|
| **pytest** | latest | ユニット・統合テスト |
| **pytest-order** | latest | テスト実行順序制御 |

---

## 🎨 フロントエンド (k_front)

### コア技術

| カテゴリ | 技術 | バージョン | 用途 |
|---------|------|-----------|------|
| **フレームワーク** | Next.js | 16.0.10 | Reactフレームワーク（App Router） |
| **ビルドツール** | Turbopack | latest | 高速バンドラー（Next.js統合） |
| **言語** | TypeScript | 5.x | 型安全な開発 |
| **UIライブラリ** | React | 19.1.2 | UIコンポーネント構築 |

### スタイリング

| 技術 | バージョン | 用途 |
|------|-----------|------|
| **Tailwind CSS** | 4.x | ユーティリティファーストCSS |
| **@tailwindcss/postcss** | 4.x | PostCSS統合 |
| **tailwind-merge** | 3.3.1 | Tailwindクラス名のマージ |
| **clsx** | 2.1.1 | 条件付きクラス名結合 |
| **class-variance-authority** | 0.7.1 | バリアントベースのスタイル管理 |
| **next-themes** | 0.4.6 | ダークモード切り替え |

### UIコンポーネント

#### Radix UI (アクセシブルなヘッドレスコンポーネント)

| コンポーネント | バージョン | 用途 |
|--------------|-----------|------|
| **@radix-ui/react-dialog** | 1.1.15 | モーダルダイアログ |
| **@radix-ui/react-dropdown-menu** | 2.1.16 | ドロップダウンメニュー |
| **@radix-ui/react-select** | 2.2.6 | セレクトボックス |
| **@radix-ui/react-slot** | 1.2.3 | コンポーネント合成 |

#### アイコン

| 技術 | バージョン | 用途 |
|------|-----------|------|
| **@heroicons/react** | 2.2.0 | Heroiconsアイコンセット |
| **lucide-react** | 0.544.0 | Lucideアイコンセット |
| **react-icons** | 5.5.0 | 汎用アイコンライブラリ |

### フォーム管理

| 技術 | バージョン | 用途 |
|------|-----------|------|
| **react-hook-form** | 7.62.0 | フォーム状態管理 |
| **@hookform/resolvers** | 5.2.1 | バリデーションスキーマリゾルバー |
| **zod** | 4.1.4 | TypeScript型安全バリデーション |

### その他UI機能

| 技術 | バージョン | 用途 |
|------|-----------|------|
| **sonner** | 2.0.7 | トースト通知 |
| **qrcode.react** | 4.2.0 | QRコード生成（2FA） |
| **react-dropzone** | 14.3.8 | ドラッグ&ドロップファイルアップロード |

### セキュリティ

| 技術 | バージョン | 用途 |
|------|-----------|------|
| **@lavamoat/allow-scripts** | 3.4.1 | npmパッケージのインストールスクリプト制御 |

### 開発ツール

| 技術 | バージョン | 用途 |
|------|-----------|------|
| **ESLint** | 9.34.0 | コード品質チェック |
| **eslint-config-next** | 16.0.10 | Next.js用ESLint設定 |

---

## 🏗️ インフラストラクチャ

### コンテナ化

| 技術 | 用途 |
|------|------|
| **Docker** | アプリケーションコンテナ化 |
| **Docker Compose** | ローカル開発環境オーケストレーション |

### バックエンドDockerイメージ

```dockerfile
# ベースイメージ: python:3.12-slim-bullseye
# ビルドステージ:
#   - base: 共通依存関係
#   - production: Cloud Run本番環境（gunicorn）
#   - development: ローカル開発環境（uvicorn + reload）
```

| 環境 | サーバー | ポート | 設定 |
|------|---------|-------|------|
| **開発** | Uvicorn | 8000 | ホットリロード有効 |
| **本番** | Gunicorn + Uvicorn Worker | 8080 | Cloud Run対応 |

### 本番デプロイ

| サービス | 用途 |
|---------|------|
| **Google Cloud Run** | サーバーレスコンテナホスティング |
| **PostgreSQL** | マネージドデータベース |
| **AWS S3** | ファイルストレージ（画像、添付ファイル） |

---

## 🔄 開発ワークフロー

### バックエンド

```bash
# 開発サーバー起動（ホットリロード）
docker exec keikakun_app-backend-1 uvicorn app.main:app --reload

# テスト実行
docker exec keikakun_app-backend-1 pytest tests/ -v

# マイグレーション作成
docker exec keikakun_app-backend-1 alembic revision --autogenerate -m "migration message"

# マイグレーション適用
docker exec keikakun_app-backend-1 alembic upgrade head

# バッチ処理実行（期限アラート）
docker exec keikakun_app-backend-1 python3 scripts/run_deadline_notification.py
```

### フロントエンド

```bash
# 開発サーバー起動
npm run dev              # Turbopack有効

# ビルド
npm run build

# 本番サーバー起動
npm run start

# Lint
npm run lint

# セキュリティチェック
npm run security-check   # npm audit (high以上)
npm run audit            # 全脆弱性チェック
npm run audit:fix        # 自動修正
npm run outdated-check   # パッケージ更新チェック
```

---

## 📊 アーキテクチャ設計

### バックエンド4層アーキテクチャ

```
API層 (endpoints/)       # HTTPリクエスト・レスポンス処理
  ↓
Services層 (services/)   # ビジネスロジック
  ↓
CRUD層 (crud/)          # データベース操作抽象化
  ↓
Models層 (models/)      # SQLAlchemyモデル定義
```

### 非同期処理設計

- **FastAPI**: 全エンドポイント非同期対応
- **SQLAlchemy**: AsyncSessionによる非同期DB操作
- **APScheduler**: バックグラウンドバッチ処理
  - 期限アラートメール送信（毎日0:00 UTC / 9:00 JST）
  - Web Push通知送信
  - 無料トライアル期限チェック

### セキュリティ設計

#### 認証フロー
1. JWT認証（Access Token + Refresh Token）
2. 2要素認証（TOTP: Time-based One-Time Password）
3. CSRF保護（fastapi-csrf-protect）

#### データ保護
- パスワード: bcryptでハッシュ化
- PII（個人情報）: ログ出力時にマスキング
- 通信: HTTPS強制
- SQL Injection防止: SQLAlchemyのパラメータ化クエリ
- XSS防止: Pydanticによる入力検証

---

## 🔌 外部サービス連携

### 決済: Stripe

- **用途**: サブスクリプション課金（月額/年額プラン）
- **Webhook**: リアルタイム課金ステータス更新
- **冪等性**: `webhook_events`テーブルで重複処理防止

### カレンダー: Google Calendar API

- **用途**: スタッフのスケジュール管理
- **認証**: OAuth 2.0（Service Account / OAuth Flow）

### ストレージ: AWS S3

- **用途**: ユーザープロフィール画像、添付ファイル保存
- **SDK**: boto3

### メール: fastapi-mail

- **用途**: 期限アラート通知、パスワードリセット
- **リトライ**: tenacityによる指数バックオフ（最大3回）

### Web Push: pywebpush

- **プロトコル**: Web Push API + VAPID認証
- **用途**: ブラウザ通知（期限アラート）
- **購読管理**: `push_subscriptions`テーブル
- **自動クリーンアップ**: 410 Goneエラー時にDB削除

---

## 📦 依存関係管理

### バックエンド

- **ファイル**: `requirements.txt`, `requirements-dev.txt`
- **ツール**: pip
- **更新方針**:
  - セキュリティアップデート: 即座に適用
  - メジャーバージョンアップ: テスト後に慎重に適用

### フロントエンド

- **ファイル**: `package.json`
- **ツール**: npm
- **セキュリティ**: @lavamoat/allow-scripts（インストールスクリプト制御）
- **更新チェック**: `npm run outdated-check`, `npm run security-check`

---

## 🧪 テスト戦略

### バックエンドテスト

- **フレームワーク**: pytest
- **カバレッジ**:
  - ユニットテスト（CRUD, Service層）
  - 統合テスト（API エンドポイント）
  - セキュリティテスト（SQL Injection, XSS, 認可）
- **非同期テスト**: pytest-asyncio
- **データベース**: トランザクションロールバックで分離

### フロントエンドテスト

- **Lint**: ESLint（Next.js推奨設定）
- **型チェック**: TypeScript strict mode

---

## 🌍 国際化・ローカライゼーション

- **ターゲット**: 日本国内の福祉事業所
- **言語**: 日本語（UI、エラーメッセージ、ログ）
- **タイムゾーン**: UTC（バックエンド）→ JST表示（フロントエンド）
- **祝日判定**: jpholidayライブラリ（日本の祝日）

---

## 📈 監視・ロギング

### ログ設計

- **形式**: 構造化ログ（JSON）
- **レベル**: DEBUG, INFO, WARNING, ERROR
- **PII保護**: メールアドレス等はマスキング (`mask_email()`)
- **監査ログ**: `audit_logs`テーブルで全ての重要操作を記録

### 主要ログタグ

- `[DEADLINE_NOTIFICATION]`: 期限アラートバッチ
- `[WEB_PUSH]`: Web Push通知
- `[PUSH]`: pywebpush処理
- `[BILLING]`: Stripe課金処理

---

## 🔐 環境変数管理

### バックエンド (.env)

```bash
# データベース
DATABASE_URL=postgresql+psycopg://user:pass@host:5432/db

# JWT
SECRET_KEY=...
ALGORITHM=HS256

# Stripe
STRIPE_SECRET_KEY=sk_test_...
STRIPE_WEBHOOK_SECRET=whsec_...

# VAPID (Web Push)
VAPID_PRIVATE_KEY=...
VAPID_PUBLIC_KEY=...
VAPID_SUBJECT=mailto:support@keikakun.com

# Google Calendar
GOOGLE_CLIENT_ID=...
GOOGLE_CLIENT_SECRET=...

# AWS S3
AWS_ACCESS_KEY_ID=...
AWS_SECRET_ACCESS_KEY=...
AWS_S3_BUCKET_NAME=...
```

### フロントエンド (.env.local)

```bash
# API URL
NEXT_PUBLIC_API_URL=http://localhost:8000

# VAPID公開鍵（Web Push）
NEXT_PUBLIC_VAPID_PUBLIC_KEY=...
```

---

## 🚀 今後の技術的課題

### パフォーマンス最適化
- [ ] データベースインデックス最適化
- [ ] N+1クエリ削減（selectinload徹底）
- [ ] Redis導入（セッション、キャッシュ）

### スケーラビリティ
- [ ] バッチ処理の並列化
- [ ] Cloud Runのオートスケーリング設定調整

### 開発体験向上
- [ ] フロントエンドE2Eテスト（Playwright検討）
- [ ] CI/CDパイプライン強化（GitHub Actions）

### セキュリティ強化
- [ ] 定期的な依存関係脆弱性スキャン自動化
- [ ] Web Application Firewall（WAF）導入検討

---

**作成日**: 2026-01-19
**最終更新**: 2026-01-19
**管理者**: Claude Sonnet 4.5
