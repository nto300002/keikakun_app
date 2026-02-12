# けいかくん - デプロイ失敗時のロールバック戦略

**作成日**: 2026-01-27
**対象**: 2次面接 - CI/CD関連質問
**関連技術**: Cloud Run, Cloud Build, Alembic, GitHub

---

## 概要

デプロイ失敗やバグ発見時に迅速に前バージョンに戻すロールバック手順を説明します。Cloud Runの自動ロールバック機能とマニュアルロールバック手順の両方をカバーします。

---

## 1. ロールバックの種類

### 1.1 3つのロールバックシナリオ

| シナリオ | タイミング | 対応方法 | 所要時間 |
|---------|-----------|---------|---------|
| **自動ロールバック** | デプロイ中のヘルスチェック失敗 | Cloud Runが自動実行 | 0分（自動） |
| **即座のロールバック** | デプロイ直後の重大バグ発見 | Cloud Runリビジョン切り替え | 1-2分 |
| **完全ロールバック** | データベース変更を含む | DB + アプリの両方をロールバック | 5-10分 |

---

## 2. 自動ロールバック（Cloud Runのデフォルト機能）

### 2.1 仕組み

Cloud Runは新バージョンデプロイ時に自動的にヘルスチェックを実行:

```
[新バージョン起動]
        ↓
[ヘルスチェック: GET /health]
        ↓
    成功? ──No─→ [自動ロールバック]
      ↓ Yes           ↓
[トラフィック移行]  [旧バージョン継続]
```

**ヘルスチェック基準**:
- HTTPステータス200の応答
- レスポンス時間3秒以内
- 起動後10秒以内に応答可能

---

### 2.2 ヘルスチェックエンドポイント実装

**ファイル**: `k_back/app/api/v1/endpoints/health.py`

```python
@router.get("/health")
async def health_check():
    """
    ヘルスチェックエンドポイント
    Cloud Runがデプロイ成功判定に使用
    """
    return {
        "status": "healthy",
        "timestamp": datetime.now(timezone.utc).isoformat()
    }
```

**Cloud Runの設定**:
```yaml
# Cloud Run自動設定
healthCheck:
  path: /health
  initialDelaySeconds: 10
  timeoutSeconds: 3
  periodSeconds: 10
  failureThreshold: 3
```

**自動ロールバックの例**:
```
2026-01-27 10:00:00 - 新バージョンデプロイ開始
2026-01-27 10:00:15 - ヘルスチェック実行
2026-01-27 10:00:15 - ❌ 応答なし（データベース接続エラー）
2026-01-27 10:00:18 - ❌ リトライ1回目失敗
2026-01-27 10:00:21 - ❌ リトライ2回目失敗
2026-01-27 10:00:22 - 🔄 自動ロールバック開始
2026-01-27 10:00:25 - ✅ 旧バージョンに戻りました
```

---

## 3. 即座のロールバック（手動・アプリケーションのみ）

### 3.1 状況

- デプロイは成功したが、本番環境で重大バグを発見
- データベース変更は含まない
- 即座に前バージョンに戻す必要がある

---

### 3.2 方法1: Cloud Runリビジョン切り替え（最速）

**手順**:

#### Step 1: 現在のリビジョン確認

```bash
# 全リビジョンをリスト表示
gcloud run revisions list \
  --service k-back \
  --region asia-northeast1

# 出力例:
# REVISION                  ACTIVE  SERVICE  DEPLOYED
# k-back-00042-abc         yes     k-back   2026-01-27 10:00:00  ← 新バージョン（問題あり）
# k-back-00041-xyz         no      k-back   2026-01-27 09:00:00  ← 旧バージョン（安定）
# k-back-00040-def         no      k-back   2026-01-26 15:00:00
```

---

#### Step 2: トラフィックを旧バージョンに切り替え

```bash
# 1つ前のリビジョンに100%切り替え
gcloud run services update-traffic k-back \
  --to-revisions k-back-00041-xyz=100 \
  --region asia-northeast1

# 実行結果:
# ✅ Traffic updated successfully
# ✅ URL: https://k-back-xxxxxxxxx-an.a.run.app
```

**所要時間**: **約30秒〜1分**

---

#### Step 3: 動作確認

```bash
# ヘルスチェック
curl https://k-back-xxxxxxxxx-an.a.run.app/health

# ログ確認
gcloud run logs read k-back --limit=20
```

---

### 3.3 方法2: 段階的ロールバック（カナリアリリース）

重大度が低い場合は段階的に戻す:

```bash
# まず10%だけ旧バージョンに戻す
gcloud run services update-traffic k-back \
  --to-revisions k-back-00041-xyz=10,k-back-00042-abc=90 \
  --region asia-northeast1

# 問題なければ50%に
gcloud run services update-traffic k-back \
  --to-revisions k-back-00041-xyz=50,k-back-00042-abc=50 \
  --region asia-northeast1

# 最後に100%
gcloud run services update-traffic k-back \
  --to-revisions k-back-00041-xyz=100 \
  --region asia-northeast1
```

**利点**:
- 一部ユーザーへの影響を確認しながら戻せる
- バグの影響範囲を最小化

---

### 3.4 方法3: GitHub Actionsで再デプロイ

特定のコミットを再デプロイ:

#### Step 1: 安定していたコミットを確認

```bash
# コミット履歴確認
git log --oneline -10

# 出力例:
# 9bb1fbf (HEAD -> main) chore: 新機能追加（バグあり）← これが問題
# 832c940 feat: 本番環境ログ削減 ← この状態に戻したい
# 82c8fa1 fix: pytest.iniに-sフラグ追加
```

---

#### Step 2: 該当コミットにリバート

```bash
# 方法A: revert（推奨）
git revert 9bb1fbf
git push origin main

# 方法B: リセット（慎重に）
git reset --hard 832c940
git push origin main --force
```

**GitHub Actionsが自動的に再デプロイ**（約4分）

---

## 4. 完全ロールバック（データベース変更を含む）

### 4.1 状況

- データベースマイグレーション実行後に問題発生
- テーブル変更やカラム追加を元に戻す必要がある
- アプリケーションとDBの両方をロールバック

---

### 4.2 手順

#### Step 1: 状況確認

```bash
# 現在のマイグレーション状態を確認
docker exec keikakun_app-backend-1 alembic current

# 出力例:
# 3f8d9e2a1b4c (head)  # 最新のマイグレーション
```

---

#### Step 2: データベースマイグレーションをロールバック

```bash
# 1つ前のマイグレーションに戻す
docker exec keikakun_app-backend-1 alembic downgrade -1

# 特定のリビジョンに戻す
docker exec keikakun_app-backend-1 alembic downgrade 2a1b3c4d5e6f

# 全てのマイグレーションを取り消す（最終手段）
docker exec keikakun_app-backend-1 alembic downgrade base
```

**重要**: 本番環境でのダウングレードは慎重に！

**本番環境での実行**:
```bash
# Cloud Runコンテナに接続
gcloud run services describe k-back --region asia-northeast1

# Alembicダウングレード（直接実行は推奨しない）
# 代わりに、メンテナンスモードに切り替えてから実行
```

---

#### Step 3: アプリケーションをロールバック

```bash
# Cloud Runリビジョンを切り替え
gcloud run services update-traffic k-back \
  --to-revisions k-back-00041-xyz=100 \
  --region asia-northeast1
```

---

#### Step 4: データ整合性確認

```bash
# PostgreSQLに接続
psql $DATABASE_URL

# テーブル構造確認
\d+ staffs

# データ確認
SELECT COUNT(*) FROM staffs;

# トランザクションログ確認
SELECT * FROM audit_logs ORDER BY created_at DESC LIMIT 10;
```

---

### 4.3 マイグレーションロールバックの注意点

#### ✅ ロールバック可能なケース

```python
# マイグレーションファイル
def upgrade():
    op.add_column('staffs', sa.Column('new_field', sa.String(50)))

def downgrade():
    op.drop_column('staffs', 'new_field')  # ロールバック可能
```

---

#### ❌ ロールバック困難なケース

```python
# ケース1: データ削除を伴う変更
def upgrade():
    op.drop_column('staffs', 'old_field')  # データが失われる

def downgrade():
    op.add_column('staffs', sa.Column('old_field', sa.String(50)))
    # ❌ データは復元できない！
```

**対策**:
- カラム削除の前にデータをバックアップ
- すぐに削除せず、まず非推奨化（deprecated）

---

```python
# ケース2: 複雑なデータ変換
def upgrade():
    # JSON形式からリレーショナル形式に変換
    ...

def downgrade():
    # 逆変換が複雑
    ...
```

**対策**:
- 段階的マイグレーション
- データ変換スクリプトを別途用意

---

## 5. ロールバック戦略のベストプラクティス

### 5.1 デプロイ前の準備

#### チェックリスト

- [ ] マイグレーションファイルに`downgrade()`を実装
- [ ] ダウングレードが安全に実行できることをテスト環境で確認
- [ ] データベースのバックアップを取得
- [ ] ロールバック手順を事前に文書化

---

#### データベースバックアップ（Neon Postgres）

**自動バックアップ設定**:
- Neonは自動的にポイントインタイムリカバリ（PITR）を提供
- 過去7日間の任意の時点に復元可能

**手動バックアップ**:
```bash
# pg_dumpでバックアップ
pg_dump $PROD_DATABASE_URL > backup_$(date +%Y%m%d_%H%M%S).sql

# S3にアップロード
aws s3 cp backup_*.sql s3://keikakun-backups/
```

---

### 5.2 デプロイ中の監視

#### Cloud Runログ監視

```bash
# リアルタイムログ監視
gcloud run logs tail k-back --region asia-northeast1

# エラーのみ表示
gcloud run logs read k-back --region asia-northeast1 | grep ERROR
```

---

#### アラート設定（推奨）

Cloud Monitoringでアラート設定:

```yaml
# アラートポリシー例
displayName: "高エラー率アラート"
conditions:
  - displayName: "エラー率5%超過"
    conditionThreshold:
      filter: 'resource.type="cloud_run_revision" metric.type="run.googleapis.com/request_count" metric.label.response_code_class="5xx"'
      comparison: COMPARISON_GT
      thresholdValue: 5  # 5%
      duration: 60s
notificationChannels:
  - projects/xxx/notificationChannels/slack-channel
```

**アラート発火時の自動ロールバック**:
- Cloud Functionsでアラートを受信
- 自動的に前バージョンに切り替え（将来的に実装可能）

---

### 5.3 ロールバック後の対応

#### Step 1: 根本原因分析

```bash
# Cloud Runログ取得
gcloud run logs read k-back --region asia-northeast1 --limit=500 > error_logs.txt

# エラーパターン抽出
grep -E "ERROR|CRITICAL|Exception" error_logs.txt
```

---

#### Step 2: 問題の修正

```python
# バグ修正
# テスト追加
# 再デプロイ前にテスト環境で十分に検証
```

---

#### Step 3: 段階的再デプロイ

```bash
# カナリアリリースで再デプロイ
gcloud run services update-traffic k-back \
  --to-revisions k-back-00043-fix=10,k-back-00041-xyz=90 \
  --region asia-northeast1

# 監視しながら徐々に増やす
```

---

## 6. マイグレーション失敗時の特殊対応

### 6.1 状況: マイグレーション途中で失敗

```
Applying migration 3f8d9e2a1b4c...
Error: duplicate column name "new_field"
❌ Migration failed
```

---

### 6.2 対処法

#### Option 1: 手動でSQLを修正

```bash
# PostgreSQLに接続
psql $DATABASE_URL

# 問題のテーブルを確認
\d+ staffs

# 手動で修正
ALTER TABLE staffs DROP COLUMN new_field;

# Alembicのバージョンテーブルを更新
UPDATE alembic_version SET version_num = '前のバージョンID';
```

---

#### Option 2: ダウングレードを強制

```bash
# Alembicのバージョンを手動で戻す
docker exec keikakun_app-backend-1 alembic stamp 2a1b3c4d5e6f

# 再度マイグレーション実行
docker exec keikakun_app-backend-1 alembic upgrade head
```

---

### 6.3 最悪のシナリオ: データベース復元

**ポイントインタイムリカバリ（Neon Postgres）**:

```bash
# Neon CLIを使用してPITR実行
neon branch create \
  --project-id xxx \
  --restore-to-time "2026-01-27T09:00:00Z"

# 新しいブランチのDATABASE_URLを取得
# Cloud Run環境変数を更新
gcloud run services update k-back \
  --update-env-vars DATABASE_URL=新しいURL \
  --region asia-northeast1
```

**所要時間**: 5-15分

---

## 7. ロールバック判断基準

### 7.1 即座にロールバックすべき状況（Critical）

- ✅ データ損失の可能性
- ✅ 決済機能の停止
- ✅ 認証・認可の失敗（全ユーザーがログインできない）
- ✅ データベース接続エラー
- ✅ 5xxエラーが50%以上

**判断時間**: 5分以内にロールバック開始

---

### 7.2 様子見可能な状況（Warning）

- ⚠️ 一部機能の軽微なバグ
- ⚠️ UI表示の崩れ
- ⚠️ パフォーマンス低下（許容範囲内）
- ⚠️ 5xxエラーが5-10%

**判断時間**: 30分以内に判断

---

### 7.3 ロールバック不要（Info）

- ℹ️ 軽微なログ出力の誤り
- ℹ️ 非推奨機能の警告
- ℹ️ パフォーマンス微改善

**対応**: 次回デプロイで修正

---

## 8. 面接で強調すべきポイント

### 8.1 多層防御アプローチ

**1. 自動ロールバック（第1層）**
- Cloud Runのヘルスチェックで自動検出
- 人間の介入不要

**2. 即座のロールバック（第2層）**
- リビジョン切り替えで1分以内に復旧
- データベース変更を伴わない場合に有効

**3. 完全ロールバック（第3層）**
- DBマイグレーションも含めた完全復旧
- バックアップからの復元も可能

---

### 8.2 リスク最小化戦略

**デプロイ前**:
- テスト環境での十分な検証
- マイグレーションのdowngrade実装
- データベースバックアップ

**デプロイ中**:
- ヘルスチェック監視
- リアルタイムログ監視
- アラート設定

**デプロイ後**:
- 監視メトリクス確認（エラー率、レスポンス時間）
- ユーザーフィードバック収集

---

### 8.3 実際の対応時間

| シナリオ | 検出時間 | ロールバック時間 | 合計 |
|---------|---------|----------------|------|
| 自動ロールバック | 即座 | 0分（自動） | 0分 |
| リビジョン切り替え | 1-5分 | 1分 | 2-6分 |
| DBロールバック | 5-10分 | 5分 | 10-15分 |
| PITR復元 | 10-30分 | 15分 | 25-45分 |

**目標**: 重大バグは10分以内に復旧

---

## 9. 将来的な改善案

### 9.1 自動ロールバックトリガー

```python
# Cloud FunctionでCloud Monitoringアラートを受信
@functions_framework.cloud_event
def auto_rollback(cloud_event):
    """エラー率5%超過で自動ロールバック"""

    # Cloud Runの前バージョンに切り替え
    subprocess.run([
        "gcloud", "run", "services", "update-traffic", "k-back",
        "--to-revisions", "previous=100",
        "--region", "asia-northeast1"
    ])

    # Slackに通知
    send_slack_notification("⚠️ 自動ロールバック実行")
```

---

### 9.2 ブルーグリーンデプロイの強化

```bash
# 本番環境を2つ用意（Blue/Green）
gcloud run services create k-back-blue --image xxx
gcloud run services create k-back-green --image xxx

# Load Balancerで切り替え
gcloud compute url-maps update k-back-lb \
  --default-service=k-back-green
```

---

## 10. 関連資料

- [Cloud Run公式ドキュメント - リビジョン管理](https://cloud.google.com/run/docs/managing/revisions)
- [Alembic公式ドキュメント - Downgrade](https://alembic.sqlalchemy.org/en/latest/tutorial.html#downgrading)
- 内部資料: `cicd_github_actions_cloud_build.md` - CI/CDフロー
- 内部資料: `phase2_database.md` - マイグレーション設計

---

**最終更新**: 2026-01-27
**作成者**: Claude Sonnet 4.5
