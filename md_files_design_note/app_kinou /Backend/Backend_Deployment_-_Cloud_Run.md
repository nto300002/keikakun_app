# Backend Deployment - Cloud Run（デプロイ構成）

## 概要

Google Cloud Build + Cloud Run による CI/CD パイプライン。
`main` ブランチへのプッシュをトリガーに自動ビルド・デプロイが実行される。

---

## Cloud Build パイプライン

**ファイル**: `k_back/cloudbuild.yml`

### ステップ 1: Dockerイメージのビルド

```yaml
- name: 'gcr.io/cloud-builders/docker'
  args:
    - 'build'
    - '--target=production'
    - '-t'
    - 'asia-northeast1-docker.pkg.dev/$PROJECT_ID/k-back-repo/k-back:$SHORT_SHA'
    - '-t'
    - 'asia-northeast1-docker.pkg.dev/$PROJECT_ID/k-back-repo/k-back:$BRANCH_NAME-$SHORT_SHA'
    - '-t'
    - 'asia-northeast1-docker.pkg.dev/$PROJECT_ID/k-back-repo/k-back:latest'
    - './k_back'
```

- `--target=production`: Dockerfileの本番ステージのみビルド
- 3つのタグを同時に付与（コミットSHA・ブランチ名付きSHA・latest）

### ステップ 2: Artifact Registry へプッシュ

```yaml
- name: 'gcr.io/cloud-builders/docker'
  args:
    - 'push'
    - '--all-tags'
    - 'asia-northeast1-docker.pkg.dev/$PROJECT_ID/k-back-repo/k-back'
```

- リージョン: `asia-northeast1`（東京）
- `--all-tags` で3タグを一括プッシュ

### ステップ 3: Cloud Run へデプロイ

```yaml
- name: 'gcr.io/google.com/cloudsdktool/cloud-sdk'
  entrypoint: gcloud
  args:
    - 'run'
    - 'deploy'
    - 'k-back'
    - '--image'
    - 'asia-northeast1-docker.pkg.dev/$PROJECT_ID/k-back-repo/k-back:$SHORT_SHA'
    - '--region'
    - 'asia-northeast1'
    - '--min-instances=0'
    - '--max-instances=5'
    - '--cpu=2'
    - '--memory=1Gi'
    - '--concurrency=80'
    - '--timeout=600'
    - '--update-env-vars'
    - '^##^DATABASE_URL=${_PROD_DATABASE_URL}##SECRET_KEY=${_PROD_SECRET_KEY}##...'
```

---

## Cloud Run スケーリング設定

| 設定 | 値 | 理由 |
|------|---|------|
| `min-instances` | 0 | 夜間・低負荷時のコストゼロ化 |
| `max-instances` | 5 | 朝8〜9時の集中アクセス対応 |
| `cpu` | 2 | Phase 4の10並列バッチ処理対応 |
| `memory` | 1Gi | 並列処理時のメモリ確保 |
| `concurrency` | 80 | 1インスタンスあたり最大80並行リクエスト |
| `timeout` | 600秒 | バッチ処理（デッドライン通知）の長時間タイムアウト対応 |

---

## 環境変数・シークレット管理

### Cloud Build 置換変数（`_` プレフィックス）

Cloud Build コンソールまたは `cloudbuild.yml` の `substitutions` セクションで定義。

| 置換変数 | 用途 |
|---------|------|
| `_PROD_DATABASE_URL` | 本番PostgreSQL接続URL |
| `_PROD_SECRET_KEY` | JWT署名キー |
| `_S3_ACCESS_KEY` | AWS S3アクセスキー |
| `_STRIPE_SECRET_KEY` | Stripe APIキー |
| `_STRIPE_WEBHOOK_SECRET` | Stripe Webhook署名検証キー |
| `_VAPID_PRIVATE_KEY` | Web Push VAPIDキー |
| `_MAIL_SERVER` | メールサーバー設定 |
| `_ENVIRONMENT` | `production` |
| `_MFA_ENCRYPTION_KEY` | MFAシークレット暗号化キー |

---

## デプロイフロー

```
git push origin main
       ↓
Cloud Build トリガー起動
       ↓
Step 1: docker build --target=production
       ↓
Step 2: docker push → Artifact Registry (asia-northeast1)
       ↓
Step 3: gcloud run deploy k-back
       ↓
Cloud Run: ゼロダウンタイムデプロイ（トラフィック切り替え）
       ↓
完了通知
```

---

## インフラ構成

| リソース | 設定値 |
|---------|--------|
| リージョン | asia-northeast1（東京） |
| サービス名 | `k-back` |
| イメージレジストリ | Artifact Registry |
| DBホスト | Neon PostgreSQL（サーバーレス） |
| ドメイン | api.keikakun.com |

---

## ゼロダウンタイムデプロイ

Cloud Run は新リビジョンへのトラフィック切り替えを自動的に行う。

1. 新リビジョンがデプロイされ起動待機
2. ヘルスチェック通過後、トラフィックを新リビジョンへ切り替え
3. 旧リビジョンは一定時間後に停止

---

## Neon DB との連携

- `pool_recycle=300`（5分）: Neon の auto-suspend による接続切断を防ぐ
- `pool_pre_ping=True`: リクエスト前に接続確認
- Cloud Run のコールドスタート時にも接続プールが正しく初期化される

---

## ロールバック手順

```bash
# 特定のリビジョンへ手動ロールバック
gcloud run services update-traffic k-back \
  --to-revisions=k-back-XXXX=100 \
  --region=asia-northeast1
```
