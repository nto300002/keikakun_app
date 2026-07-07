# Docker Configuration（Docker構成）

## Dockerfile（マルチステージビルド）

**ファイル**: `k_back/Dockerfile`

3つのステージで構成されており、本番と開発で共通のベースを使用する。

### Stage 1: base（共通ベース）
```dockerfile
FROM python:3.12-slim-bullseye AS base

ENV PYTHONUNBUFFERED=1
ENV PYTHONPATH=/app

WORKDIR /app
COPY requirements.txt .

RUN pip install --no-cache-dir --upgrade pip && \
    pip install --no-cache-dir -r requirements.txt
```
- Python 3.12 slim イメージでサイズを最小化
- `PYTHONUNBUFFERED=1`: ログをリアルタイム出力
- `PYTHONPATH=/app`: モジュール解決パスを設定

---

### Stage 2: production（本番用）
```dockerfile
FROM base AS production

# 非rootユーザーを作成（セキュリティ）
RUN addgroup --system --gid 1001 pythonuser && \
    adduser --system --uid 1001 pythonuser
USER pythonuser

COPY . .
EXPOSE 8080

CMD exec gunicorn -w 1 -k uvicorn.workers.UvicornWorker \
    -b "0.0.0.0:${PORT}" app.main:app
```

#### ポイント
- **非rootユーザー実行**: セキュリティリスクを低減
- **gunicorn + UvicornWorker**: プロセス管理（gunicorn）＋非同期処理（uvicorn）
- **ポート8080**: Cloud Run のデフォルトポートに対応
- **ワーカー数1**: Cloud Run の `concurrency=80` で並行処理するため、マルチワーカーは不要

---

### Stage 3: development（開発用）
```dockerfile
FROM base AS development

COPY requirements-dev.txt .
RUN pip install --no-cache-dir --upgrade -r requirements-dev.txt

CMD ["uvicorn", "app.main:app", \
     "--host", "0.0.0.0", \
     "--port", "8000", \
     "--reload"]
```

- `--reload`: ファイル変更を検知して自動再起動
- `requirements-dev.txt`: pytest 等の開発用依存関係を追加

---

## 主な依存パッケージ（requirements.txt）

| パッケージ | バージョン | 用途 |
|-----------|---------|------|
| fastapi | 0.115.0 | Webフレームワーク |
| uvicorn | 0.29.0 | ASGIサーバー |
| gunicorn | latest | プロセスマネージャー |
| sqlalchemy | 2.0.41 | ORM |
| alembic | 1.16.4 | DBマイグレーション |
| psycopg[binary,pool] | >=3.1.8 | PostgreSQLドライバー（非同期対応） |
| pydantic | 2.11.7 | バリデーション |
| passlib[bcrypt] | latest | パスワードハッシュ |
| python-jose[cryptography] | >=3.3.0 | JWT |
| pyotp | >=2.8.0 | TOTP（MFA） |
| qrcode[pil] | >=7.4.0 | QRコード生成 |
| stripe | >=7.0.0 | 決済 |
| fastapi-csrf-protect | >=0.3.4 | CSRF対策 |
| slowapi | >=0.1.9 | レート制限 |
| APScheduler | 3.10.4 | バックグラウンドタスク |
| boto3 | latest | AWS S3（メール添付等） |
| pywebpush | >=1.14.0 | Web Push通知 |

---

## docker-compose.yml

**ファイル**: `docker-compose.yml`（ルートディレクトリ）

### サービス構成

```yaml
services:
  backend:
    build:
      context: ./k_back
      target: development      # 開発ステージを使用
    ports:
      - "8000:8000"
    volumes:
      - ./k_back:/app          # ホットリロード用マウント
    environment:
      - TESTING=0
      - DATABASE_URL=...
      - SECRET_KEY=...
    depends_on:
      - db

  db:
    image: postgres:15
    environment:
      POSTGRES_DB: keikakun
      POSTGRES_USER: ...
      POSTGRES_PASSWORD: ...
    volumes:
      - postgres_data:/var/lib/postgresql/data
    ports:
      - "5432:5432"
```

---

## 環境変数管理

### 主な環境変数

| 変数名 | 用途 |
|-------|------|
| `DATABASE_URL` | PostgreSQL接続URL（本番） |
| `TEST_DATABASE_URL` | テスト用DB接続URL |
| `SECRET_KEY` | JWT署名キー |
| `MFA_ENCRYPTION_KEY` | MFAシークレットの暗号化キー |
| `STRIPE_SECRET_KEY` | Stripe API シークレットキー |
| `STRIPE_WEBHOOK_SECRET` | Stripe Webhook署名検証 |
| `VAPID_PRIVATE_KEY` | Web Push用VAPIDキー |
| `MAIL_SERVER` | メールサーバー設定 |
| `ENVIRONMENT` | `production` / `development` |
| `TESTING` | `1` でテスト用DBを使用 |

### ローカル開発
- `.env` ファイルで管理（`.gitignore` に追加済み）
- `docker-compose.yml` の `environment` セクションで設定

### 本番環境
- Cloud Build の置換変数（`_PROD_DATABASE_URL` 等）
- Cloud Run のシークレット管理（Secret Manager 連携）

---

## ビルドの使い分け

```bash
# 開発環境
docker-compose up

# 本番イメージのローカルテスト
docker build --target=production -t k-back:local ./k_back
docker run -p 8080:8080 -e PORT=8080 k-back:local
```
