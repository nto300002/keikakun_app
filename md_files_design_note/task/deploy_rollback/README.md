# Git + イメージタグによるロールバック戦略

**最終更新**: 2026-02-16
**ステータス**: 推奨（未実装）

---

## 📋 目次

1. [概要](#概要)
2. [現状の課題](#現状の課題)
3. [推奨実装](#推奨実装)
4. [実装しなかった場合の損失](#実装しなかった場合の損失)
5. [実装手順](#実装手順)
6. [ロールバック手順](#ロールバック手順)
7. [運用フロー](#運用フロー)

---

## 概要

### 目的

デプロイ失敗時に**迅速かつ確実に**特定のバージョンにロールバックできる体制を構築する。

### 現在の構成

```
GitHub (main push)
    ↓
GitHub Actions (pytest)
    ↓
Cloud Build (docker build)
    ↓
Artifact Registry (latest tag のみ)  ← 問題点
    ↓
Cloud Run (k-back service)
```

### 推奨構成

```
GitHub (main push)
    ↓
GitHub Actions (pytest)
    ↓
Cloud Build (docker build)
    ↓
Artifact Registry (latest + $SHORT_SHA tag)  ← 改善
    ↓
Cloud Run (k-back service)
```

---

## 現状の課題

### 問題1: イメージタグが `latest` のみ

**現状**: `cloudbuild.yml` L8
```yaml
- 'asia-northeast1-docker.pkg.dev/$PROJECT_ID/k-back-repo/k-back:latest'
```

**課題**:
- 特定バージョンへのロールバックが不可能
- 「どのコミットがデプロイされているか」の追跡が困難
- Cloud Runのリビジョン保持期限（数週間）を超えるとロールバック不可

### 問題2: Git履歴とイメージの紐付けなし

**現状**: イメージタグにコミットハッシュが含まれていない

**課題**:
- デバッグ時に「どのコードバージョンが動いているか」が不明
- 複数デプロイが短時間で発生した場合、追跡が困難
- インシデント時の原因特定に時間がかかる

### 問題3: 長期的なロールバック不可

**現状**: Cloud Runリビジョン履歴に依存

**課題**:
- リビジョン履歴は自動削除される（保持期限あり）
- 「1ヶ月前の安定版に戻す」が不可能
- Artifact Registryには `latest` のみで古いバージョンが残らない

---

## 実装しなかった場合の損失

### 💸 ビジネスインパクト

| シナリオ | 現状（latestのみ） | 改善後（Git tag） | 損失 |
|---------|-------------------|------------------|------|
| **本番障害発生** | Cloud Runリビジョンロールバック（不確実） | Git commitハッシュで確実にロールバック | **信頼性の欠如** |
| **ロールバック時間** | 5-30分（調査 + 手探り） | **1-2分**（明確な手順） | **平均20分のダウンタイム** |
| **古いバージョンへの復帰** | **不可能**（リビジョン削除済み） | 可能（Artifact Registryに永続保存） | **復旧不可能** |
| **デバッグ時の影響** | どのコードが動いているか不明 | コミットハッシュで即座に特定 | **調査時間 30分〜1時間** |
| **複数デプロイの追跡** | 混乱（どれがどれか不明） | Git履歴と完全一致 | **運用負荷 + ミス** |

### 📊 具体的な損失試算

#### ケース1: 本番障害（月1回発生を想定）

```
現状のロールバック時間: 20分（平均）
改善後のロールバック時間: 2分

削減時間 = 18分/回 × 12回/年 = 216分/年 = 3.6時間/年

影響ユーザー数: 500事業所 × 平均5人 = 2,500人
ダウンタイム損失: 18分 × 2,500人 = 750時間分のサービス停止

ビジネス損失:
- 信頼性低下による解約リスク: 1-2事業所/年（月額6,000円）
  → 年間損失: 72,000円〜144,000円
- サポート対応コスト: 20分 × 時給3,000円 × 12回 = 12,000円/年
```

#### ケース2: 重大インシデント（年1回発生を想定）

```
シナリオ: 「1週間前のバージョンに戻したい」

現状:
- Cloud Runリビジョンが削除済み → 復旧不可能
- 緊急でGitから手動ビルド・デプロイ → 30-60分
- または原因特定 + 修正 + デプロイ → 2-4時間

改善後:
- Artifact Registryからイメージタグ指定でロールバック → 2分

最悪ケース損失:
- ダウンタイム: 4時間
- 影響ユーザー: 2,500人 × 4時間 = 10,000時間分のサービス停止
- 信頼性損失: 大規模解約リスク（5-10事業所）
  → 潜在的損失: 360,000円〜720,000円/年
```

#### ケース3: デバッグ・調査時間の増加

```
現状のデバッグ時間: 平均30分（どのバージョンが動いているか特定する時間）
改善後のデバッグ時間: 0分（イメージタグで即座に特定）

月次デバッグ回数: 4回
削減時間 = 30分 × 4回 × 12ヶ月 = 24時間/年

エンジニア時給: 5,000円（想定）
コスト削減 = 24時間 × 5,000円 = 120,000円/年
```

### 📉 総合損失試算（年間）

| 項目 | 損失額（年間） |
|------|--------------|
| 障害時のダウンタイム延長 | 12,000円 |
| デバッグ時間の増加 | 120,000円 |
| 信頼性低下による解約リスク | 72,000円〜144,000円 |
| 重大インシデント時の損失（年1回想定） | 360,000円〜720,000円 |
| **合計** | **564,000円〜996,000円** |

### 🚨 定性的リスク

1. **復旧不可能リスク**
   - Cloud Runリビジョンが削除されている場合、ロールバック不可
   - Gitから手動ビルドが必要（30-60分）
   - 最悪ケース: 原因特定 + 修正が必要（数時間）

2. **信頼性低下**
   - 長時間のダウンタイム → ユーザーの信頼失墜
   - 福祉事業所は「個別支援計画」が法定義務 → サービス停止の影響大

3. **運用負荷**
   - 障害時の調査・復旧に膨大な時間がかかる
   - 深夜・休日対応の負担増加

4. **コンプライアンスリスク**
   - サービス停止時の責任問題
   - SLA（サービスレベル合意）違反のリスク

---

## 推奨実装

### 改善1: `cloudbuild.yml` の修正

**現状**: `k_back/cloudbuild.yml` L3-15

```yaml
steps:
# 1. Dockerイメージをビルドするステップ
- name: 'gcr.io/cloud-builders/docker'
  args:
    - 'build'
    - '--target=production'
    - '-t'
    - 'asia-northeast1-docker.pkg.dev/$PROJECT_ID/k-back-repo/k-back:latest'
    - '.'

# 2. ビルドしたイメージをArtifact Registryにプッシュするステップ
- name: 'gcr.io/cloud-builders/docker'
  args:
    - 'push'
    - 'asia-northeast1-docker.pkg.dev/$PROJECT_ID/k-back-repo/k-back:latest'
```

**改善後**:

```yaml
steps:
# 1. Dockerイメージをビルドするステップ（複数タグを付与）
- name: 'gcr.io/cloud-builders/docker'
  args:
    - 'build'
    - '--target=production'
    # Git commitハッシュをタグに使用（追跡可能性）
    - '-t'
    - 'asia-northeast1-docker.pkg.dev/$PROJECT_ID/k-back-repo/k-back:$SHORT_SHA'
    # ブランチ名 + commitハッシュ（デバッグ用）
    - '-t'
    - 'asia-northeast1-docker.pkg.dev/$PROJECT_ID/k-back-repo/k-back:$BRANCH_NAME-$SHORT_SHA'
    # latestタグも継続（互換性維持）
    - '-t'
    - 'asia-northeast1-docker.pkg.dev/$PROJECT_ID/k-back-repo/k-back:latest'
    - '.'

# 2. 全てのタグをプッシュ
- name: 'gcr.io/cloud-builders/docker'
  args:
    - 'push'
    - '--all-tags'
    - 'asia-northeast1-docker.pkg.dev/$PROJECT_ID/k-back-repo/k-back'
```

**変更点**:
1. `$SHORT_SHA` タグを追加（Git commit hashの最初の7文字）
2. `$BRANCH_NAME-$SHORT_SHA` タグを追加（デバッグ用）
3. `--all-tags` で全タグを一括プッシュ

### 改善2: Cloud Run デプロイで `$SHORT_SHA` を使用

**現状**: `k_back/cloudbuild.yml` L18-30

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
    # ...
```

**改善後**:

```yaml
- name: 'gcr.io/google.com/cloudsdktool/cloud-sdk'
  entrypoint: gcloud
  args:
    - 'run'
    - 'deploy'
    - 'k-back'
    - '--image'
    - 'asia-northeast1-docker.pkg.dev/$PROJECT_ID/k-back-repo/k-back:$SHORT_SHA'  # ← 変更
    - '--region'
    - 'asia-northeast1'
    # ...
```

**変更点**:
- デプロイ時に `$SHORT_SHA` タグを明示的に指定
- Cloud Runのリビジョン名にもコミットハッシュが反映される

### 改善3: イメージ保存設定

**現状**: `k_back/cloudbuild.yml` L64-66

```yaml
# ビルドしたイメージを保存する
images:
  - 'asia-northeast1-docker.pkg.dev/$PROJECT_ID/k-back-repo/k-back:latest'
```

**改善後**:

```yaml
# ビルドしたイメージを保存する（全タグ）
images:
  - 'asia-northeast1-docker.pkg.dev/$PROJECT_ID/k-back-repo/k-back:$SHORT_SHA'
  - 'asia-northeast1-docker.pkg.dev/$PROJECT_ID/k-back-repo/k-back:$BRANCH_NAME-$SHORT_SHA'
  - 'asia-northeast1-docker.pkg.dev/$PROJECT_ID/k-back-repo/k-back:latest'
```

### メリット

✅ **Git履歴と完全一致**: コミットハッシュでバージョン追跡が可能
✅ **長期保持**: Artifact Registryに永続保存（削除ポリシー設定可能）
✅ **確実なロールバック**: 特定のコミットに確実に戻せる
✅ **デバッグ容易**: Cloud Runのリビジョン名にコミットハッシュが含まれる
✅ **互換性維持**: `latest` タグも継続使用可能

---

## 実装手順

### ステップ1: `cloudbuild.yml` の更新

```bash
cd /Users/naotoyasuda/workspase/keikakun_app/k_back
```

`cloudbuild.yml` を上記の改善版に更新。

### ステップ2: ローカルテスト（オプション）

```bash
# ローカルでCloud Buildをシミュレーション
gcloud builds submit \
  --config cloudbuild.yml \
  --substitutions=SHORT_SHA=test123,BRANCH_NAME=main \
  --project=<YOUR_PROJECT_ID>
```

### ステップ3: mainブランチにマージ

```bash
git add k_back/cloudbuild.yml
git commit -m "feat: Git commit hashをDockerイメージタグに追加（ロールバック改善）"
git push origin main
```

### ステップ4: デプロイ確認

```bash
# Artifact Registryでイメージタグを確認
gcloud artifacts docker images list \
  asia-northeast1-docker.pkg.dev/<PROJECT_ID>/k-back-repo/k-back

# 期待される出力:
# IMAGE                                                                 TAGS
# asia-northeast1-docker.pkg.dev/.../k-back:latest                     latest
# asia-northeast1-docker.pkg.dev/.../k-back:6831359                    6831359
# asia-northeast1-docker.pkg.dev/.../k-back:main-6831359               main-6831359
```

### ステップ5: Cloud Runリビジョン確認

```bash
gcloud run revisions list \
  --service=k-back \
  --region=asia-northeast1 \
  --project=<YOUR_PROJECT_ID>

# リビジョン名に commitハッシュが含まれることを確認
# 例: k-back-00045-6831359
```

---

## ロールバック手順

### 🚀 基本的なロールバック

#### ステップ1: ロールバックしたいコミットを特定

```bash
# Git履歴を確認
git log --oneline -10

# 出力例:
# 930c691 chore: k_frontサブモジュール更新
# 2e9f171 fix: k_backサブモジュール更新
# 6831359 fix/issue-バッチ処理_スケール問題の修正  ← この安定版に戻したい
# 97bde75 chore: k_backサブモジュール更新
```

#### ステップ2: 該当イメージの存在確認

```bash
gcloud artifacts docker images list \
  asia-northeast1-docker.pkg.dev/<PROJECT_ID>/k-back-repo/k-back \
  --filter="tags:6831359"

# 出力例:
# asia-northeast1-docker.pkg.dev/.../k-back:6831359
# asia-northeast1-docker.pkg.dev/.../k-back:main-6831359
```

#### ステップ3: ロールバック実行

```bash
gcloud run deploy k-back \
  --image=asia-northeast1-docker.pkg.dev/<PROJECT_ID>/k-back-repo/k-back:6831359 \
  --region=asia-northeast1 \
  --project=<YOUR_PROJECT_ID>

# または短縮版（既存の設定を全て維持）
gcloud run services update k-back \
  --image=asia-northeast1-docker.pkg.dev/<PROJECT_ID>/k-back-repo/k-back:6831359 \
  --region=asia-northeast1
```

#### ステップ4: ロールバック確認

```bash
# デプロイ完了を確認
gcloud run services describe k-back \
  --region=asia-northeast1 \
  --format="value(status.url)"

# ヘルスチェック
curl https://k-back-xxxxx.a.run.app/

# ログ確認
gcloud logging read \
  "resource.type=cloud_run_revision AND resource.labels.service_name=k-back" \
  --limit=20
```

### 🔄 カナリアデプロイ（段階的ロールバック）

リスクを最小化したい場合:

```bash
# 新しいリビジョンに10%のトラフィックを流す
gcloud run services update-traffic k-back \
  --to-revisions=k-back-00045-6831359=10,LATEST=90 \
  --region=asia-northeast1

# 問題なければ徐々に増やす
gcloud run services update-traffic k-back \
  --to-revisions=k-back-00045-6831359=50,LATEST=50 \
  --region=asia-northeast1

# 最終的に100%切り替え
gcloud run services update-traffic k-back \
  --to-revisions=k-back-00045-6831359=100 \
  --region=asia-northeast1
```

### 📝 ロールバックスクリプト（推奨）

`scripts/rollback.sh` を作成:

```bash
#!/bin/bash
# Keikakun API ロールバックスクリプト

set -e

COMMIT_HASH=$1
PROJECT_ID="<YOUR_PROJECT_ID>"
REGION="asia-northeast1"
SERVICE_NAME="k-back"

# 使用方法チェック
if [ -z "$COMMIT_HASH" ]; then
  echo "Usage: $0 <commit_hash>"
  echo ""
  echo "Example:"
  echo "  $0 6831359"
  echo ""
  echo "Recent commits:"
  git log --oneline -5
  exit 1
fi

# 確認プロンプト
echo "============================================"
echo "Keikakun API Rollback"
echo "============================================"
echo "Target commit: $COMMIT_HASH"
echo "Service: $SERVICE_NAME"
echo "Region: $REGION"
echo ""
read -p "Are you sure you want to rollback? (yes/no): " confirm

if [ "$confirm" != "yes" ]; then
  echo "Rollback cancelled."
  exit 0
fi

# イメージの存在確認
echo ""
echo "Checking if image exists..."
IMAGE_URI="asia-northeast1-docker.pkg.dev/$PROJECT_ID/k-back-repo/k-back:$COMMIT_HASH"

if ! gcloud artifacts docker images describe "$IMAGE_URI" > /dev/null 2>&1; then
  echo "Error: Image not found: $IMAGE_URI"
  echo ""
  echo "Available images:"
  gcloud artifacts docker images list \
    asia-northeast1-docker.pkg.dev/$PROJECT_ID/k-back-repo/k-back \
    --limit=10
  exit 1
fi

# ロールバック実行
echo ""
echo "Rolling back to commit: $COMMIT_HASH"
echo "Image: $IMAGE_URI"
echo ""

gcloud run deploy $SERVICE_NAME \
  --image=$IMAGE_URI \
  --region=$REGION \
  --project=$PROJECT_ID

# 結果確認
echo ""
echo "============================================"
echo "Rollback completed successfully!"
echo "============================================"
echo ""
echo "Service URL:"
gcloud run services describe $SERVICE_NAME \
  --region=$REGION \
  --format="value(status.url)"

echo ""
echo "Checking health..."
SERVICE_URL=$(gcloud run services describe $SERVICE_NAME \
  --region=$REGION \
  --format="value(status.url)")

if curl -s -o /dev/null -w "%{http_code}" "$SERVICE_URL/" | grep -q "200"; then
  echo "✅ Health check passed!"
else
  echo "⚠️ Health check failed - please verify manually"
fi
```

使用方法:

```bash
chmod +x scripts/rollback.sh
./scripts/rollback.sh 6831359
```

---

## 運用フロー

### デプロイ前チェックリスト

- [ ] ローカルでpytestが全てパス
- [ ] マイグレーションがダウングレード可能か確認
- [ ] ステージング環境でテスト済み
- [ ] データベースバックアップ完了（DB変更がある場合）
- [ ] ロールバック手順を事前確認

### デプロイ後モニタリング（10分間）

```bash
# ログ監視
gcloud logging tail \
  "resource.type=cloud_run_revision AND resource.labels.service_name=k-back"

# エラー率確認
gcloud logging read \
  "resource.type=cloud_run_revision AND severity>=ERROR" \
  --limit=20
```

### 障害検知時のアクション

1. **即座にロールバック判断**（5分以内）
   - エラー率 > 5%
   - レスポンスタイム > 3秒
   - 500エラーが連続

2. **ロールバック実行**（1-2分）
   ```bash
   ./scripts/rollback.sh <前回の安定版commit>
   ```

3. **ポストモーテム**（翌営業日）
   - 原因分析
   - 再発防止策
   - ドキュメント更新

---

## まとめ

### 実装コスト

- **作業時間**: 30分（cloudbuild.yml修正 + テスト）
- **金銭コスト**: 0円（Artifact Registry容量増加は微小）

### 得られる価値

- **ロールバック時間**: 20分 → 2分（18分削減）
- **復旧成功率**: 不確実 → 100%確実
- **年間コスト削減**: **564,000円〜996,000円**
- **信頼性向上**: サービス停止リスクの大幅削減

### 推奨アクション

✅ **今すぐ実装を推奨**
投資対効果が非常に高く、実装コストが低い改善です。

---

**関連ドキュメント**:
- [データベースマイグレーションのロールバック](./database_rollback.md)
- [Cloud Runリビジョン管理](./cloud_run_revisions.md)
- [障害対応フロー](./incident_response.md)
