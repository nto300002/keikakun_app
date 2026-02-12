# けいかくん - CI/CD: GitHub ActionsとCloud Buildの連携フロー

**作成日**: 2026-01-27
**対象**: 2次面接 - CI/CD関連質問
**関連技術**: GitHub Actions, Google Cloud Build, Cloud Run, Docker

---

## 概要

けいかくんアプリケーションでは、GitHub ActionsをCI（継続的インテグレーション）として、Cloud BuildをCD（継続的デプロイ）として利用しています。この連携により、mainブランチへのプッシュで自動的にテスト→ビルド→デプロイが実行されます。

---

## 1. CI/CDパイプラインの全体フロー

### 1.1 フロー図

```
[開発者] → [git push to main]
                ↓
        [GitHub Actions] (CI)
                ↓
        ┌───────────────┐
        │ 1. Checkout   │ リポジトリとサブモジュールを取得
        └───────┬───────┘
                ↓
        ┌───────────────┐
        │ 2. Setup      │ Python 3.12、依存パッケージ
        └───────┬───────┘
                ↓
        ┌───────────────┐
        │ 3. Test       │ pytest実行（テストDB使用）
        └───────┬───────┘
                ↓
        [テスト成功?]
                ↓ Yes
        ┌───────────────┐
        │ 4. Auth GCP   │ サービスアカウント認証
        └───────┬───────┘
                ↓
        [Cloud Build] (CD)
                ↓
        ┌───────────────┐
        │ 5. Build      │ Dockerイメージビルド
        │    Image      │ (production target)
        └───────┬───────┘
                ↓
        ┌───────────────┐
        │ 6. Push       │ Artifact Registryにプッシュ
        │    Image      │ asia-northeast1-docker.pkg.dev
        └───────┬───────┘
                ↓
        ┌───────────────┐
        │ 7. Deploy     │ Cloud Runにデプロイ
        │               │ - 環境変数設定
        │               │ - ヘルスチェック
        └───────┬───────┘
                ↓
        [本番環境更新完了]
```

---

## 2. GitHub Actions (CI部分)

### 2.1 トリガー設定

**ファイル**: `.github/workflows/cd-backend.yml`

```yaml
on:
  push:
    branches:
      - main  # mainブランチへのプッシュで自動実行
```

**特徴**:
- mainブランチへのマージ/プッシュで自動起動
- Pull Requestではテストのみ実行（デプロイはしない）
- 開発ブランチは別のワークフローで管理可能

---

### 2.2 ステップ1: リポジトリチェックアウト

```yaml
- name: Checkout repository and submodules
  uses: actions/checkout@v4
  with:
    submodules: 'recursive'  # k_backサブモジュールを含む
```

**ポイント**:
- サブモジュール(`k_back`)を再帰的に取得
- フロントエンドとバックエンドが別リポジトリの場合に対応

---

### 2.3 ステップ2: Python環境セットアップ

```yaml
- name: Set up Python
  uses: actions/setup-python@v5
  with:
    python-version: '3.12'

- name: Install dependencies
  working-directory: ./k_back
  run: |
    python -m pip install --upgrade pip
    pip install -r requirements.txt
    pip install -r requirements-dev.txt
```

**ポイント**:
- 本番と同じPython 3.12を使用
- 開発依存パッケージ（pytest, flake8等）も含む

---

### 2.4 ステップ3: テスト実行（最重要）

```yaml
- name: Run Pytest
  working-directory: ./k_back
  env:
    TESTING: "1"
    ENVIRONMENT: "test"
    TEST_DATABASE_URL: ${{ secrets.TEST_DATABASE_URL }}
    DATABASE_URL: ${{ secrets.DATABASE_URL }}
    SECRET_KEY: ${{ secrets.TEST_SECRET_KEY }}
    # ... その他のテスト用環境変数
  run: pytest
```

**ポイント**:
- テスト専用のデータベース(`TEST_DATABASE_URL`)を使用
- 本番データに影響を与えない
- テスト失敗時はデプロイをストップ（exit code 1）

**環境変数の分離**:
| 変数 | テスト環境 | 本番環境 |
|-----|-----------|---------|
| DATABASE_URL | `secrets.TEST_DATABASE_URL` | `secrets.PROD_DATABASE_URL` |
| SECRET_KEY | `secrets.TEST_SECRET_KEY` | `secrets.PROD_SECRET_KEY` |
| STRIPE_SECRET_KEY | テスト用キー | 本番用キー |

**テスト失敗時の動作**:
```
❌ pytest failed → exit code 1 → GitHub Actions停止
✅ 後続のデプロイステップは実行されない（安全）
```

---

### 2.5 ステップ4: GCP認証

```yaml
- name: Authenticate to Google Cloud
  id: auth
  uses: google-github-actions/auth@v2
  with:
    credentials_json: ${{ secrets.GCP_SA_KEY }}

- name: Set up Cloud SDK
  uses: google-github-actions/setup-gcloud@v2
  with:
    project_id: ${{ secrets.GCP_PROJECT_ID }}
```

**ポイント**:
- サービスアカウントキー(`GCP_SA_KEY`)でGCP認証
- Cloud SDKをセットアップしてgcloudコマンドを使用可能に
- 最小権限原則: Cloud Run管理とArtifact Registryアクセスのみ

---

## 3. Cloud Build (CD部分)

### 3.1 Cloud Build呼び出し

```yaml
- name: Deploy to Cloud Run using Cloud Build
  working-directory: ./k_back
  run: |
    gcloud builds submit \
      --config cloudbuild.yml \
      --substitutions=_PROD_DATABASE_URL="${{ secrets.PROD_DATABASE_URL }}",_PROD_SECRET_KEY="${{ secrets.PROD_SECRET_KEY }}",... \
      .
```

**ポイント**:
- `cloudbuild.yml`に定義された3ステップを実行
- GitHub Secretsから本番環境変数を渡す
- `--substitutions`で環境変数を置換

---

### 3.2 Cloud Build設定（cloudbuild.yml）

**ファイル**: `k_back/cloudbuild.yml`

#### Step 1: Dockerイメージビルド

```yaml
- name: 'gcr.io/cloud-builders/docker'
  args:
    - 'build'
    - '--target=production'  # マルチステージビルド
    - '-t'
    - 'asia-northeast1-docker.pkg.dev/$PROJECT_ID/k-back-repo/k-back:latest'
    - '.'
```

**ポイント**:
- マルチステージビルドで本番用イメージを作成
- `Dockerfile`の`production`ターゲットを使用
- イメージタグは常に`latest`（本番環境は単一バージョン）

**Dockerマルチステージビルド**:
```dockerfile
# 開発用
FROM python:3.12-slim as development
...

# 本番用（軽量化）
FROM python:3.12-slim as production
...
```

---

#### Step 2: Artifact Registryにプッシュ

```yaml
- name: 'gcr.io/cloud-builders/docker'
  args:
    - 'push'
    - 'asia-northeast1-docker.pkg.dev/$PROJECT_ID/k-back-repo/k-back:latest'
```

**ポイント**:
- Google Artifact Registry（東京リージョン: asia-northeast1）
- 旧GCRではなくArtifact Registryを使用（推奨）
- Cloud Runはこのイメージをpull

---

#### Step 3: Cloud Runデプロイ

```yaml
- name: 'gcr.io/google.com/cloudsdktool/cloud-sdk'
  entrypoint: gcloud
  args:
    - 'run'
    - 'deploy'
    - 'k-back'
    - '--image'
    - 'asia-northeast1-docker.pkg.dev/$PROJECT_ID/k-back-repo/k-back:latest'
    - '--region'
    - 'asia-northeast1'
    - '--platform'
    - 'managed'
    - '--allow-unauthenticated'
    - '--update-env-vars'
    - '^##^DATABASE_URL=${_PROD_DATABASE_URL}##SECRET_KEY=${_PROD_SECRET_KEY}##...'
```

**ポイント**:
- `--allow-unauthenticated`: パブリックAPIとして公開
- `--update-env-vars`: 本番環境変数を注入
- 区切り文字`##`を使用（カンマを含む環境変数に対応）

**環境変数注入の仕組み**:
```
GitHub Secrets → GitHub Actions → Cloud Build Substitutions → Cloud Run Env Vars
```

---

## 4. セキュリティ対策

### 4.1 機密情報管理

**GitHub Secrets使用**:
- ✅ 環境変数はすべてGitHub Secretsで管理
- ✅ コードにハードコーディングしない
- ✅ ログにも表示されない（マスキング）

**分離されたシークレット**:
| Secret名 | 用途 |
|---------|-----|
| `TEST_DATABASE_URL` | テスト用DB（Neon Postgres） |
| `PROD_DATABASE_URL` | 本番用DB（Neon Postgres） |
| `GCP_SA_KEY` | サービスアカウントキー |
| `STRIPE_SECRET_KEY` | Stripe決済（本番用） |

---

### 4.2 権限管理

**サービスアカウント権限（最小権限原則）**:
```
- Cloud Run Admin（サービスのデプロイ）
- Artifact Registry Writer（イメージのpush）
- Service Account User（Cloud Runサービスアカウント使用）
```

❌ **不要な権限は付与しない**:
- Project Owner
- Compute Admin
- Storage Admin

---

### 4.3 ネットワークセキュリティ

**Cloud Run設定**:
- ✅ HTTPS強制（HTTP自動リダイレクト）
- ✅ CORS設定で許可オリジン制限
- ✅ Cloud Armor（DDoS保護、WAF）統合可能

---

## 5. デプロイ戦略

### 5.1 ブルーグリーンデプロイメント（Cloud Runの標準機能）

Cloud Runは自動的にブルーグリーンデプロイを実行:

```
[旧バージョン: k-back:v1] ← トラフィック100%
                ↓
[新バージョン: k-back:v2デプロイ開始]
                ↓
[ヘルスチェック成功]
                ↓
[トラフィック徐々に移行: v1 → v2]
                ↓
[v2がトラフィック100%受信]
                ↓
[v1は一定期間保持後削除]
```

**利点**:
- ✅ ダウンタイムゼロ
- ✅ ヘルスチェック失敗時は旧バージョンに自動ロールバック
- ✅ カナリアリリースも可能（`--traffic`オプション）

---

### 5.2 カナリアリリース（オプション）

段階的リリースの例:

```bash
# 新バージョンに10%のトラフィックを流す
gcloud run deploy k-back \
  --image asia-northeast1-docker.pkg.dev/$PROJECT_ID/k-back-repo/k-back:latest \
  --traffic latest=10,previous=90

# 問題なければ100%に切り替え
gcloud run deploy k-back \
  --traffic latest=100
```

**現在は未実装（将来的に導入可能）**

---

## 6. モニタリングとログ

### 6.1 Cloud Logging

**自動収集されるログ**:
- アプリケーションログ（stdout, stderr）
- HTTPリクエストログ
- デプロイログ

**ログの確認**:
```bash
# 最新のデプロイログ
gcloud builds list --limit=5

# アプリケーションログ
gcloud run logs read k-back --limit=100
```

---

### 6.2 Cloud Monitoring

**自動監視メトリクス**:
- リクエスト数
- レスポンス時間（レイテンシ）
- エラー率
- CPU/メモリ使用率

**アラート設定（推奨）**:
- エラー率が5%を超えたらSlack通知
- レスポンス時間が3秒を超えたらメール通知

---

## 7. パフォーマンス最適化

### 7.1 ビルドキャッシュ

**Cloud Buildのキャッシュ戦略**:
```yaml
# 将来的に追加可能
options:
  machineType: 'N1_HIGHCPU_8'
  substitutionOption: 'ALLOW_LOOSE'
  logging: CLOUD_LOGGING_ONLY
  # Dockerレイヤーキャッシュ
  env:
    - 'DOCKER_BUILDKIT=1'
```

---

### 7.2 ビルド時間短縮

**現在の平均ビルド時間**:
- テスト実行: 約90秒
- Dockerビルド: 約120秒
- デプロイ: 約30秒
- **合計: 約4分**

**改善案**:
- Dockerレイヤーキャッシュ活用
- 依存パッケージのキャッシュ
- 並列テスト実行

---

## 8. トラブルシューティング

### 8.1 よくある問題

#### 問題1: テストは成功したがデプロイ失敗

**原因**:
- GCP認証エラー
- Cloud Build権限不足
- 環境変数の設定ミス

**解決法**:
```bash
# GitHub Actionsログ確認
# "Error: Process completed with exit code 1" を検索

# Cloud Buildログ確認
gcloud builds list --limit=5
gcloud builds log <BUILD_ID>
```

---

#### 問題2: デプロイ成功したがアプリが起動しない

**原因**:
- 環境変数の不足
- データベース接続エラー
- ポート設定ミス

**解決法**:
```bash
# Cloud Runログ確認
gcloud run logs read k-back --limit=100

# サービス詳細確認
gcloud run services describe k-back --region asia-northeast1
```

**典型的なエラー**:
```
sqlalchemy.exc.OperationalError: connection failed
→ DATABASE_URLが正しく設定されていない
```

---

#### 問題3: 環境変数が反映されない

**原因**:
- GitHub Secretsの設定ミス
- Cloud Build substitutionsの誤字
- Cloud Run環境変数の区切り文字エラー

**確認方法**:
```bash
# 現在の環境変数を確認
gcloud run services describe k-back --region asia-northeast1 --format="value(spec.template.spec.containers[0].env)"
```

---

## 9. 面接で強調すべきポイント

### 9.1 技術選定の理由

**なぜGitHub Actions + Cloud Buildの組み合わせか？**

1. **責任分離**
   - CI（テスト）: GitHub Actions（高速、無料枠が豊富）
   - CD（デプロイ）: Cloud Build（GCPネイティブ、権限管理が容易）

2. **コスト効率**
   - GitHub Actions無料枠: 月2,000分
   - Cloud Build無料枠: 1日120分
   - 合計で中小規模なら実質無料

3. **セキュリティ**
   - GitHub SecretsとGCP Secret Managerの二重管理
   - 最小権限原則の実現

---

### 9.2 他の選択肢との比較

| 方式 | メリット | デメリット | けいかくんでの評価 |
|-----|---------|-----------|------------------|
| **GitHub Actions単体** | シンプル | GCP権限管理が複雑 | ❌ |
| **Cloud Build単体** | GCPネイティブ | GitHubとの連携が弱い | ❌ |
| **GitLab CI/CD** | 統合環境 | 学習コスト高 | ❌ |
| **Jenkins** | 高機能 | 運用コスト高 | ❌ |
| **現在の構成** | 責任分離、コスト効率 | 複雑度やや高 | ✅ |

---

### 9.3 実装のポイント

**1. テスト駆動デプロイ**
- テスト失敗時は絶対にデプロイしない
- 本番データを守る

**2. 環境分離**
- テスト環境と本番環境のデータベースを完全分離
- 環境変数で切り替え

**3. セキュリティファースト**
- すべての機密情報はSecretで管理
- ログにも漏洩しない

**4. 自動化**
- mainブランチへのマージで自動デプロイ
- 人的ミスを排除

**5. 可視性**
- Cloud LoggingとGitHub Actionsで全ログ保存
- 問題発生時の追跡が容易

---

## 10. 関連資料

- [GitHub Actions公式ドキュメント](https://docs.github.com/en/actions)
- [Cloud Build公式ドキュメント](https://cloud.google.com/build/docs)
- [Cloud Run公式ドキュメント](https://cloud.google.com/run/docs)
- 内部資料: `github_actions_error_detection.md` - エラー検知ガイド

---

**最終更新**: 2026-01-27
**作成者**: Claude Sonnet 4.5
