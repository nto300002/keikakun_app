# けいかくん

福祉サービス事業所向けの個別支援計画管理アプリケーションです。利用者、支援計画サイクル、PDF成果物、期限通知、事業所スタッフ、課金状態を一つの業務フローとして管理します。

この親リポジトリはバックエンドとフロントエンドを Git submodule として管理します。

## リポジトリ構成

```text
keikakun_app/
├── k_back/      # FastAPI backend submodule
├── k_front/     # Next.js frontend submodule
├── .github/     # parent repository workflows
└── docker-compose.yml
```

サブモジュールを含めて取得します。

```bash
git clone --recursive https://github.com/nto300002/keikakun_app.git
cd keikakun_app
```

既存の clone でサブモジュールが空の場合は次を実行します。

```bash
git submodule update --init --recursive
```

## 主な機能

- 認証、メール認証、MFA、リカバリーコード
- ロールベースアクセス制御: `owner`, `manager`, `employee`, `app_admin`
- 事業所、スタッフ、招待、権限変更、退会申請の管理
- 利用者、支援計画サイクル、PDF成果物、アセスメント関連ファイルの管理
- 期限ダッシュボード、メール通知、Web Push 通知
- Google Calendar / ICS 連携
- Stripe サブスクリプション課金: 現行価格は月額6,000円
- app_admin 向けの全体管理、お知らせ、監査ログ参照

## 技術スタック

### Backend

- Python 3.12
- FastAPI
- SQLAlchemy 2.x async ORM
- Alembic
- PostgreSQL / Neon
- Stripe
- AWS S3
- Web Push
- Google Calendar API
- Google Cloud Run / Cloud Build

### Frontend

- Next.js App Router
- React 19
- TypeScript
- Tailwind CSS 4
- Radix UI primitives and local UI components
- React Hook Form
- Zod
- lucide-react / react-icons / Heroicons
- Playwright
- Vercel

## 開発環境

### Backend

バックエンドの実行、テスト、マイグレーションは Docker Compose の `backend` サービス内で行います。

```bash
docker compose up -d backend
docker compose exec backend alembic upgrade head
docker compose exec backend pytest
```

個別テストの例です。

```bash
docker compose exec backend pytest tests/api/v1/test_csrf_protection.py
docker compose exec backend pytest tests/api/v1/test_csrf_protection.py -m "not performance"
```

### Frontend

フロントエンドのコマンドは `k_front` で実行します。

```bash
cd k_front
npm install
npm run dev
npm run lint
npm run build
```

## 環境変数

ローカル用の値は親リポジトリの `.env`、フロントエンドは `k_front/.env.local` を使います。実際の必須値は各アプリの設定クラス、Cloud Build、Vercel 設定を確認してください。

Backend の代表例:

- `DATABASE_URL`
- `TEST_DATABASE_URL`
- `SECRET_KEY`
- `ENCRYPTION_KEY`
- `CALENDAR_ENCRYPTION_KEY`
- `BACKEND_CORS_ORIGINS`
- `COOKIE_DOMAIN`, `COOKIE_SECURE`, `COOKIE_SAMESITE`
- `STRIPE_SECRET_KEY`, `STRIPE_WEBHOOK_SECRET`, `STRIPE_PRICE_ID`
- `AWS_ACCESS_KEY_ID`, `AWS_SECRET_ACCESS_KEY`, `AWS_REGION`, `S3_BUCKET_NAME`
- `MAIL_USERNAME`, `MAIL_PASSWORD`, `MAIL_FROM`
- `VAPID_PRIVATE_KEY`, `VAPID_PUBLIC_KEY`, `VAPID_SUBJECT`
- `GOOGLE_CLIENT_ID`, `GOOGLE_CLIENT_SECRET`

Frontend の代表例:

- `NEXT_PUBLIC_API_URL`
- `NEXT_PUBLIC_VAPID_PUBLIC_KEY`

## アーキテクチャ方針

Backend は次の階層を基本にします。

```text
app/api/v1/endpoints/  # HTTP, auth, request/response
app/services/          # business use cases and transaction boundaries
app/crud/              # focused data access
app/models/            # SQLAlchemy models
app/schemas/           # Pydantic schemas
```

API 層で新しい `commit()` / `flush()` を増やさず、複数モデルをまたぐ処理や業務トランザクションは service 層に寄せます。

Frontend は App Router を使い、認証が必要な画面を `app/(protected)` 配下に置きます。API 呼び出しは `lib/http.ts` と `lib/api/*` に集約し、画面固有の状態と表示コンポーネントを分けます。

## 主要ルート

Frontend:

- `/auth/login`, `/auth/signup`
- `/auth/admin/login`, `/auth/admin/signup`, `/auth/admin/office_setup`
- `/auth/app-admin/login`
- `/dashboard`
- `/recipients`, `/recipients/new`, `/recipients/[id]`
- `/support_plan/[id]`
- `/pdf-list`
- `/calendar/events`
- `/notice`, `/notice/[id]`
- `/messages/new`
- `/profile`
- `/admin`
- `/app-admin`

Backend API は `k_back/app/api/v1/endpoints` を参照してください。

## CI/CD

- Backend は parent repository の GitHub Actions と `k_back/cloudbuild.yml` でテスト、マイグレーション、Cloud Run デプロイを行います。
- Frontend は `k_front` の Next.js アプリとしてビルドし、Vercel で配信します。
- サブモジュール変更を親に反映する場合は、子リポジトリで commit / push した後、親リポジトリで submodule pointer の差分を commit します。

## 参考ドキュメント

- [Backend README](./k_back/README.md)
- [Frontend README](./k_front/README.md)
- [AGENTS.md](./AGENTS.md)
- [技術メモ](./md_files_design_note/)
