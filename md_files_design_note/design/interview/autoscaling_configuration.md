# オートスケーリング設定ガイド

**作成日**: 2026-02-09
**対象システム**: けいかくん（個別支援計画管理システム）
**インフラ**: NeonDB + Google Cloud Run

---

## 📋 概要

このドキュメントでは、けいかくんのインフラストラクチャにおけるオートスケーリング設定について説明します。

### システム構成

```
┌─────────────────┐
│   Cloud Run     │ ← オートスケーリング（0-10インスタンス）
│  (FastAPI)      │
└────────┬────────┘
         │
         ▼
┌─────────────────┐
│     NeonDB      │ ← オートスケーリング（0.25-4 CU）
│  (PostgreSQL)   │
└─────────────────┘
```

---

## 🗄️ NeonDB オートスケーリング

### デフォルト設定

| 項目 | Free Tier | Pro Tier | 説明 |
|------|-----------|----------|------|
| **最小 Compute Units** | 0.25 CU | 0.25 CU | アイドル時の最小リソース |
| **最大 Compute Units** | 1 CU | 8 CU | 負荷時の最大リソース |
| **自動サスペンド** | 5分（300秒） | 5分（300秒） | 非アクティブ時に自動停止 |
| **スケールダウン遅延** | 5分 | 5分 | アイドル状態からスケールダウンまでの時間 |
| **コールドスタート時間** | 5-10秒 | 5-10秒 | サスペンド後の初回接続時間 |

**Compute Unit (CU) の内訳**:
- 1 CU = 1 vCPU + 4GB RAM
- 0.25 CU = 0.25 vCPU + 1GB RAM
- 0.5 CU = 0.5 vCPU + 2GB RAM

---

### けいかくんでの推奨設定

#### 本番環境（Production）

```bash
# Neon Dashboard or CLI
Min Compute Units: 0.5 CU
Max Compute Units: 4 CU
Auto-suspend delay: 600 seconds (10分)
```

**設定理由**:

| 設定項目 | 値 | 理由 |
|---------|---|------|
| Min: 0.5 CU | 0.5 vCPU + 2GB RAM | - コールドスタート時間短縮（0.25 CUより高速）<br>- 通常のクエリ性能を確保<br>- バッチ処理の基礎性能 |
| Max: 4 CU | 4 vCPU + 16GB RAM | - 500事業所のバッチ処理に対応<br>- 10並列クエリを高速処理<br>- ピーク時の性能確保 |
| Auto-suspend: 10分 | - | - 頻繁な停止/起動サイクルを回避<br>- 夜間バッチ処理後のウォームアップ維持<br>- コールドスタートによるユーザー体験悪化を防止 |

**期待されるパフォーマンス**:
- 通常時: 0.5 CU（クエリ応答時間: 50-100ms）
- バッチ処理時: 2-4 CU（500事業所処理: 3分以内）
- ピーク時: 4 CU（複数ユーザーの同時アクセス）

---

#### 開発環境（Development）

```bash
# Neon Dashboard or CLI
Min Compute Units: 0.25 CU
Max Compute Units: 1 CU
Auto-suspend delay: 300 seconds (5分)
```

**設定理由**:

| 設定項目 | 値 | 理由 |
|---------|---|------|
| Min: 0.25 CU | 0.25 vCPU + 1GB RAM | - コスト削減（最小限のリソース）<br>- 開発環境では性能より経済性優先 |
| Max: 1 CU | 1 vCPU + 4GB RAM | - 開発・テスト用途で十分<br>- Free Tierの範囲内 |
| Auto-suspend: 5分 | - | - 開発中の非アクティブ時間を考慮<br>- コスト最適化 |

---

### スケーリングトリガー

#### スケールアップ条件

NeonDBは以下の条件で自動的にCompute Unitsを増加させます：

```
1. CPU使用率 > 70%
   → 0.5 CU → 1 CU → 2 CU → 4 CU

2. メモリ使用率 > 80%
   → 次のCUレベルにスケールアップ

3. アクティブ接続数が多い
   → 接続プールが枯渇する前にスケールアップ

4. クエリ実行時間が長い
   → I/O待機時間が増加した場合
```

**スケールアップ速度**: 数秒〜10秒

---

#### スケールダウン条件

```
1. CPU使用率 < 30% が5分継続
   → 1段階スケールダウン（例: 2 CU → 1 CU）

2. メモリ使用率が低い
   → アイドル状態が続く場合

3. アクティブ接続数が少ない
   → min CUまでスケールダウン
```

**スケールダウン速度**: 5分のディレイ後

---

### パフォーマンスチューニング

#### 接続プーリング設定

NeonDBのオートスケーリングと連携するため、接続プールを適切に設定：

```python
# k_back/app/db/session.py

from sqlalchemy.ext.asyncio import create_async_engine

DATABASE_URL = os.getenv("DATABASE_URL")

engine = create_async_engine(
    DATABASE_URL,
    echo=False,
    pool_size=5,          # 基本接続数（0.5 CUで十分）
    max_overflow=10,      # 追加接続数（スケールアップ時）
    pool_timeout=30,      # 接続待機タイムアウト
    pool_recycle=3600,    # 1時間で接続を再作成
    pool_pre_ping=True,   # 接続の健全性チェック
)
```

**設定理由**:

| パラメータ | 値 | 理由 |
|-----------|---|------|
| pool_size | 5 | - 0.5 CUで処理可能な基本接続数<br>- Cloud Runの1インスタンスに最適 |
| max_overflow | 10 | - スケールアップ時の追加接続<br>- 4 CU時は最大15接続 |
| pool_recycle | 3600 | - NeonDBのアイドル接続タイムアウト対策<br>- 1時間で接続をリフレッシュ |
| pool_pre_ping | True | - サスペンド後の接続エラー防止<br>- 使用前に接続を検証 |

---

#### コールドスタート対策

**問題**: サスペンド後の初回接続に5-10秒かかる

**対策1: Auto-suspend延長**
```bash
# 本番環境: 10分に設定
Auto-suspend delay: 600 seconds

# 理由: 夜間バッチ処理後もウォームアップ維持
```

**対策2: ヘルスチェックの実装**
```python
# k_back/app/api/v1/endpoints/health.py

@router.get("/health")
async def health_check(db: AsyncSession = Depends(get_db)):
    """
    ヘルスチェックエンドポイント

    NeonDBの接続を維持し、コールドスタートを防止
    """
    try:
        # 軽量なクエリでDB接続を確認
        await db.execute(text("SELECT 1"))
        return {"status": "healthy", "database": "connected"}
    except Exception as e:
        return {"status": "unhealthy", "error": str(e)}
```

**対策3: 定期的なウォームアップ（Cloud Scheduler）**
```yaml
# Cloud Schedulerで5分ごとにヘルスチェック
schedule: "*/5 * * * *"
url: "https://keikakun-backend.run.app/api/v1/health"
```

---

### モニタリング指標

#### 監視すべきメトリクス

| メトリクス | 正常範囲 | 警告閾値 | アクション |
|-----------|---------|---------|----------|
| **CPU使用率** | 30-70% | > 80% | Max CUを増加 |
| **メモリ使用率** | 40-60% | > 85% | Max CUを増加 |
| **アクティブ接続数** | 5-15 | > 20 | 接続プールサイズを調整 |
| **クエリ実行時間** | < 100ms | > 500ms | クエリ最適化またはCU増加 |
| **コールドスタート頻度** | 1日1回以下 | 1時間1回以上 | Auto-suspend延長 |

---

## 🚀 Cloud Run オートスケーリング

### デフォルト設定

| 項目 | デフォルト値 | 範囲 | 説明 |
|------|------------|------|------|
| **最小インスタンス数** | 0 | 0-1000 | コールドスタート有効 |
| **最大インスタンス数** | 100 | 1-1000 | 最大同時インスタンス数 |
| **並行リクエスト数** | 80 | 1-1000 | 1インスタンスあたりの同時処理数 |
| **CPU割り当て** | リクエスト時のみ | 常時/リクエスト時 | アイドル時のCPU使用 |
| **タイムアウト** | 300秒 | 1-3600秒 | リクエストタイムアウト |
| **メモリ** | 512 MiB | 128MiB-32GiB | コンテナメモリ |
| **CPU** | 1 vCPU | 1-8 vCPU | コンテナCPU |

---

### けいかくんでの推奨設定

#### 本番環境（Production）

**Cloud Run YAMLファイル**: `k_back/cloudrun-prod.yaml`

```yaml
apiVersion: serving.knative.dev/v1
kind: Service
metadata:
  name: keikakun-backend-prod
  labels:
    environment: production
    app: keikakun
spec:
  template:
    metadata:
      annotations:
        # =====================================
        # オートスケーリング設定
        # =====================================

        # 最小インスタンス数: 1
        # 理由: コールドスタート回避（レスポンス時間の安定化）
        autoscaling.knative.dev/minScale: "1"

        # 最大インスタンス数: 10
        # 理由: 適度な上限（コスト管理 + 十分なキャパシティ）
        autoscaling.knative.dev/maxScale: "10"

        # 並行リクエスト数: 80
        # 理由: FastAPI + asyncio に最適なデフォルト値
        autoscaling.knative.dev/target: "80"

        # =====================================
        # CPU設定
        # =====================================

        # CPU throttling無効（常時CPU割り当て）
        # 理由: バッチ処理（期限通知）がアイドル時にも実行される
        run.googleapis.com/cpu-throttling: "false"

        # 起動時のCPUブースト有効
        # 理由: コンテナ起動時間を短縮（コールドスタート対策）
        run.googleapis.com/startup-cpu-boost: "true"

        # =====================================
        # その他の設定
        # =====================================

        # 実行環境: 第2世代
        # 理由: ネットワーク性能向上、より多くのCPU/メモリオプション
        run.googleapis.com/execution-environment: gen2

    spec:
      # =====================================
      # コンテナ設定
      # =====================================

      containerConcurrency: 80  # 1インスタンスあたりの並行リクエスト数
      timeoutSeconds: 600       # タイムアウト: 10分（バッチ処理対応）

      containers:
      - name: keikakun-backend
        image: gcr.io/keikakun-prod/backend:latest

        # リソース制限
        resources:
          limits:
            cpu: "2"       # 2 vCPU
            memory: "1Gi"  # 1 GiB RAM

        # 環境変数
        env:
        - name: ENVIRONMENT
          value: "production"
        - name: DATABASE_URL
          valueFrom:
            secretKeyRef:
              name: neondb-url
              key: url
        - name: GOOGLE_APPLICATION_CREDENTIALS
          value: "/secrets/gcp-credentials.json"

        # ヘルスチェック
        livenessProbe:
          httpGet:
            path: /api/v1/health
            port: 8000
          initialDelaySeconds: 10
          periodSeconds: 30

        # ボリュームマウント（秘密鍵）
        volumeMounts:
        - name: gcp-credentials
          mountPath: /secrets
          readOnly: true

      # ボリューム定義
      volumes:
      - name: gcp-credentials
        secret:
          secretName: gcp-service-account-key
```

---

#### 本番環境設定の詳細解説

| 設定項目 | 値 | 理由 |
|---------|---|------|
| **minScale: 1** | 常時1インスタンス | - コールドスタート完全回避<br>- レスポンス時間の安定化（常時50ms以下）<br>- ヘルスチェック、監視の継続性 |
| **maxScale: 10** | 最大10インスタンス | - 80リクエスト/インスタンス × 10 = 800並行リクエスト<br>- 想定ピーク（100ユーザー × 5リクエスト/秒）に対応<br>- コスト管理（無制限スケールを防止） |
| **target: 80** | 80並行リクエスト | - FastAPI + asyncio の最適値<br>- I/O待機が多い処理に適している |
| **CPU: 2 vCPU** | 2 vCPU | - Phase 4の並列処理（10事業所並列）に対応<br>- バッチ処理の高速化 |
| **Memory: 1Gi** | 1 GiB RAM | - Phase 4の並列処理（50並行）に対応<br>- メモリ使用量: 35MB（Phase 4目標）で十分な余裕 |
| **cpu-throttling: false** | 常時CPU | - バッチ処理（期限通知）がアイドル時に実行<br>- スケジューラーが常時動作 |
| **timeout: 600秒** | 10分 | - バッチ処理（500事業所: 3分）に余裕を持たせる<br>- ロングポーリング対応 |

---

#### 開発環境（Development）

**Cloud Run YAMLファイル**: `k_back/cloudrun-dev.yaml`

```yaml
apiVersion: serving.knative.dev/v1
kind: Service
metadata:
  name: keikakun-backend-dev
  labels:
    environment: development
    app: keikakun
spec:
  template:
    metadata:
      annotations:
        # オートスケーリング設定（開発環境）
        autoscaling.knative.dev/minScale: "0"   # コールドスタート許容（コスト削減）
        autoscaling.knative.dev/maxScale: "3"   # 最大3インスタンス（開発用途で十分）
        autoscaling.knative.dev/target: "80"    # デフォルト

        # CPU設定
        run.googleapis.com/cpu-throttling: "true"  # リクエスト時のみCPU（コスト削減）
        run.googleapis.com/startup-cpu-boost: "false"  # ブーストなし
        run.googleapis.com/execution-environment: gen2

    spec:
      containerConcurrency: 80
      timeoutSeconds: 300  # 5分（バッチ処理は本番環境でテスト）

      containers:
      - name: keikakun-backend
        image: gcr.io/keikakun-dev/backend:latest

        resources:
          limits:
            cpu: "1"        # 1 vCPU（開発用途で十分）
            memory: "512Mi" # 512 MiB RAM

        env:
        - name: ENVIRONMENT
          value: "development"
        - name: DATABASE_URL
          valueFrom:
            secretKeyRef:
              name: neondb-url-dev
              key: url
```

**設定理由**:

| 設定項目 | 値 | 理由 |
|---------|---|------|
| **minScale: 0** | アイドル時は0インスタンス | - コスト削減（使用時のみ課金）<br>- 開発環境ではコールドスタート許容 |
| **maxScale: 3** | 最大3インスタンス | - 開発・テスト用途で十分<br>- 負荷テストは本番相当の環境で実施 |
| **CPU: 1 vCPU** | 1 vCPU | - 開発用途で十分<br>- コスト削減 |
| **Memory: 512Mi** | 512 MiB | - 開発用途で十分<br>- Phase 2までのテストに対応 |
| **cpu-throttling: true** | リクエスト時のみCPU | - コスト削減<br>- バッチ処理は本番環境でのみ実行 |

---

### スケーリングトリガー

#### スケールアップ条件

Cloud Runは以下の計算式でスケールアップを判断：

```
必要インスタンス数 = ceil(現在の並行リクエスト数 / target値)

例:
- 現在の並行リクエスト数: 160
- target値: 80
- 必要インスタンス数 = ceil(160 / 80) = 2

→ 1インスタンス → 2インスタンスにスケールアップ
```

**スケールアップ速度**:
- ウォームインスタンス使用時: 1-2秒
- コールドスタート時: 3-5秒（第2世代）

**トリガー条件**:
1. 並行リクエスト数が `target` を超える
2. 既存インスタンスがCPU/メモリ限界に達する
3. レスポンス時間が遅延している

---

#### スケールダウン条件

```
スケールダウン判断:
- 並行リクエスト数 < target × インスタンス数 × 0.5
- 上記状態が2-3分継続

例:
- 現在のインスタンス数: 3
- target値: 80
- スケールダウン閾値: 80 × 3 × 0.5 = 120

→ 並行リクエスト数が120未満で2-3分継続すると2インスタンスに削減
```

**スケールダウン速度**:
- 2-3分のディレイ後、徐々に削減
- min-instances まで削減（0または設定値）

---

### リソース設定のベストプラクティス

#### CPU設定

**cpu-throttling: false（常時CPU）を使用すべきケース**:
```yaml
run.googleapis.com/cpu-throttling: "false"
```

✅ 使用すべき場合:
- バックグラウンドジョブ（スケジューラー、バッチ処理）
- WebSocket接続の維持
- 定期的なヘルスチェック
- CPU使用量 < 1 vCPU でコスト影響が小さい

❌ 使用すべきでない場合:
- 純粋なAPI（リクエスト処理のみ）
- CPU使用量が多い（常時課金が高額になる）

**けいかくんの判断**: ✅ 使用
- 理由: 期限通知バッチ処理がアイドル時に実行される

---

#### メモリ設定

**メモリサイズの決定方法**:

```
必要メモリ = ベースメモリ + ワークロードメモリ + バッファ

けいかくんの場合:
- ベースメモリ: 200 MiB（FastAPI + SQLAlchemy）
- ワークロードメモリ: 35 MiB（Phase 4目標: 500事業所処理）
- バッファ: 30%（予期しないメモリ増加）

→ (200 + 35) × 1.3 ≈ 305 MiB
→ 安全マージンを考慮して 512 MiB（開発）、1 GiB（本番）
```

**メモリ不足の症状**:
- OOMKilled エラー
- コンテナの突然の再起動
- レスポンス時間の急激な悪化

**対策**:
- メモリ使用量の監視（Cloud Monitoring）
- メモリプロファイリング（`memory_profiler`）
- 必要に応じてメモリ増量

---

### スケーリング計算例

#### シナリオ1: 通常時（50ユーザー）

```
想定負荷:
- 50ユーザー × 2リクエスト/秒 = 100リクエスト/秒
- 平均レスポンス時間: 100ms
- 並行リクエスト数 = 100 × 0.1 = 10

必要インスタンス数 = ceil(10 / 80) = 1インスタンス

→ min-instances: 1 で常に対応可能
```

---

#### シナリオ2: ピーク時（200ユーザー）

```
想定負荷:
- 200ユーザー × 5リクエスト/秒 = 1000リクエスト/秒
- 平均レスポンス時間: 100ms
- 並行リクエスト数 = 1000 × 0.1 = 100

必要インスタンス数 = ceil(100 / 80) = 2インスタンス

→ 自動的に2インスタンスにスケールアップ
```

---

#### シナリオ3: バッチ処理時

```
バッチ処理（期限通知）:
- 500事業所 × 10スタッフ = 5000メール送信
- 処理時間: 3分（Phase 4目標）
- 並行リクエスト数: バッチ処理のみ（他のリクエストは少ない）

インスタンス数: 1インスタンス（min-instances）

リソース使用:
- CPU: 2 vCPU（10並列処理）
- メモリ: 35 MiB（Phase 4目標）

→ 1インスタンスで処理可能
```

---

## 📊 モニタリングとアラート

### Cloud Monitoring ダッシュボード

#### 監視すべきメトリクス

**Cloud Runメトリクス**:

| メトリクス | 正常範囲 | 警告閾値 | 重大閾値 | アクション |
|-----------|---------|---------|---------|----------|
| **リクエスト数** | 0-500/秒 | > 800/秒 | > 1000/秒 | maxScaleを増加 |
| **レスポンス時間（P95）** | < 200ms | > 500ms | > 1000ms | CPU/メモリ増加 |
| **インスタンス数** | 1-3 | > 8 | = maxScale | 負荷分散を確認 |
| **CPU使用率** | 30-70% | > 85% | > 95% | CPU増加 |
| **メモリ使用率** | 40-70% | > 85% | > 95% | メモリ増加 |
| **コールドスタート頻度** | 0-1回/日 | > 5回/日 | > 20回/日 | minScale増加 |
| **エラー率** | < 0.1% | > 1% | > 5% | アプリケーション調査 |

**NeonDBメトリクス**:

| メトリクス | 正常範囲 | 警告閾値 | 重大閾値 | アクション |
|-----------|---------|---------|---------|----------|
| **CPU使用率** | 30-70% | > 80% | > 90% | Max CUを増加 |
| **メモリ使用率** | 40-70% | > 85% | > 95% | Max CUを増加 |
| **アクティブ接続数** | 5-15 | > 20 | > 30 | 接続プール調整 |
| **クエリ実行時間（P95）** | < 100ms | > 300ms | > 1000ms | クエリ最適化 |
| **Current CU** | 0.5-2 CU | > 3 CU | = Max CU | Max CU増加検討 |

---

### アラート設定例

**Cloud Monitoring Alerting Policy**:

```yaml
# alerts/high-response-time.yaml
displayName: "High Response Time (P95 > 500ms)"
conditions:
  - displayName: "Response time too high"
    conditionThreshold:
      filter: |
        resource.type = "cloud_run_revision"
        metric.type = "run.googleapis.com/request_latencies"
      aggregations:
        - alignmentPeriod: 60s
          perSeriesAligner: ALIGN_DELTA
          crossSeriesReducer: REDUCE_PERCENTILE_95
      comparison: COMPARISON_GT
      thresholdValue: 500  # 500ms
      duration: 300s  # 5分継続
notificationChannels:
  - projects/keikakun-prod/notificationChannels/slack-backend-alerts
```

```yaml
# alerts/high-cpu-usage.yaml
displayName: "High CPU Usage (> 85%)"
conditions:
  - displayName: "CPU usage too high"
    conditionThreshold:
      filter: |
        resource.type = "cloud_run_revision"
        metric.type = "run.googleapis.com/container/cpu/utilizations"
      aggregations:
        - alignmentPeriod: 60s
          perSeriesAligner: ALIGN_MEAN
      comparison: COMPARISON_GT
      thresholdValue: 0.85  # 85%
      duration: 300s  # 5分継続
notificationChannels:
  - projects/keikakun-prod/notificationChannels/slack-backend-alerts
```

---

## 🔧 トラブルシューティング

### 問題1: コールドスタートが頻繁に発生

**症状**:
- 初回リクエストが遅い（3-5秒）
- ユーザー体験の悪化

**原因**:
- `minScale: 0` でアイドル時にインスタンスがゼロになる

**対策**:
```yaml
# minScaleを1に変更
autoscaling.knative.dev/minScale: "1"
```

**効果**:
- コールドスタート完全回避
- レスポンス時間の安定化

---

### 問題2: メモリ不足（OOMKilled）

**症状**:
- コンテナが突然再起動
- ログに "OOMKilled" エラー

**原因**:
- メモリ使用量がlimitsを超過

**対策**:
```yaml
# メモリを増量
resources:
  limits:
    memory: "1Gi"  # 512Mi → 1Gi
```

**検証方法**:
```bash
# Cloud Logsでメモリ使用量を確認
gcloud logging read "resource.type=cloud_run_revision AND jsonPayload.message=~'memory'" --limit 50
```

---

### 問題3: NeonDBのコールドスタート

**症状**:
- サスペンド後の初回クエリが遅い（5-10秒）

**原因**:
- Auto-suspendにより自動停止

**対策**:
```bash
# Auto-suspend時間を延長
Auto-suspend delay: 600 seconds (10分)

# または
# Cloud Schedulerで定期的にヘルスチェック
schedule: "*/5 * * * *"
url: "https://keikakun-backend.run.app/api/v1/health"
```

---

### 問題4: 並行リクエスト数の設定が不適切

**症状**:
- インスタンスが過剰にスケールアップ
- または、レスポンス時間が遅延

**原因**:
- `target` 値が実際のワークロードに合っていない

**対策（同期処理が多い場合）**:
```yaml
# targetを削減
autoscaling.knative.dev/target: "10"  # 80 → 10
```

**対策（I/O待機が多い場合）**:
```yaml
# targetを増加
autoscaling.knative.dev/target: "200"  # 80 → 200
```

**けいかくんの場合**:
- FastAPI + asyncio + DB I/O待機が多い
- デフォルトの80が最適

---

## 💰 コスト最適化

### コスト構造

**Cloud Runの課金**:
```
月額コスト = (CPU時間 × CPU料金) + (メモリ時間 × メモリ料金) + (リクエスト数 × リクエスト料金)

CPU料金: $0.00002400 / vCPU秒
メモリ料金: $0.00000250 / GiB秒
リクエスト料金: $0.40 / 100万リクエスト
```

**NeonDBの課金（Pro Tier）**:
```
月額料金: $69（Pro Tier基本料金）
追加料金: Compute Units時間、ストレージ、データ転送
```

---

### コスト削減のベストプラクティス

#### 1. 適切なminScaleの設定

**本番環境**:
```yaml
# コールドスタート回避とコストのバランス
minScale: "1"

コスト影響:
- 1インスタンス × 2 vCPU × 86400秒/日 × $0.00002400 = $4.15/日
- 月額: 約$125（常時1インスタンス稼働）

メリット:
- レスポンス時間の安定化
- ユーザー体験の向上
- ヘルスチェックの継続性
```

**開発環境**:
```yaml
# コスト削減優先
minScale: "0"

コスト影響:
- 使用時のみ課金（開発時間: 8時間/日）
- 月額: 約$40（使用時間のみ）

デメリット:
- コールドスタート（3-5秒）
- 開発環境では許容範囲
```

---

#### 2. 適切なリソース設定

**過剰なリソース設定を避ける**:
```yaml
# ❌ 悪い例（過剰）
resources:
  limits:
    cpu: "4"      # 実際には2 vCPUで十分
    memory: "2Gi" # 実際には1 GiB で十分

# ✅ 良い例（適切）
resources:
  limits:
    cpu: "2"      # Phase 4の並列処理に対応
    memory: "1Gi" # メモリ使用量: 35 MiB + バッファ
```

**コスト削減効果**:
- 4 vCPU → 2 vCPU: 50%削減
- 2 GiB → 1 GiB: 50%削減
- 合計: 月額$60程度の削減

---

#### 3. NeonDBのAuto-suspend最適化

**過度に短いAuto-suspend時間を避ける**:
```bash
# ❌ 悪い例（頻繁な停止/起動）
Auto-suspend: 60 seconds (1分)

問題:
- 頻繁なサスペンド/起動サイクル
- コールドスタートの頻発
- ユーザー体験の悪化

# ✅ 良い例（適切）
Auto-suspend: 600 seconds (10分)

メリット:
- コールドスタート頻度の削減
- ウォームアップ維持
- コスト影響は小さい（0.5 CU × 10分）
```

---

#### 4. 開発環境でのコスト削減

**開発環境の推奨設定**:
```yaml
# Cloud Run
minScale: "0"          # アイドル時は0インスタンス
maxScale: "3"          # 最大3インスタンス
cpu: "1"               # 1 vCPU
memory: "512Mi"        # 512 MiB
cpu-throttling: "true" # リクエスト時のみCPU

# NeonDB
Min CU: 0.25 CU        # 最小限
Max CU: 1 CU           # Free Tierの範囲内
Auto-suspend: 300s     # 5分
```

**コスト削減効果**:
- Cloud Run: 月額$40程度（開発時間のみ）
- NeonDB: $0（Free Tier範囲内）

---

### コスト監視

**予算アラートの設定**:

```yaml
# budgets/monthly-budget.yaml
displayName: "Monthly Budget - Keikakun Backend"
amount:
  specifiedAmount:
    currencyCode: "USD"
    units: "300"  # 月額$300
thresholdRules:
  - thresholdPercent: 0.5   # 50%で警告
  - thresholdPercent: 0.9   # 90%で警告
  - thresholdPercent: 1.0   # 100%で重大警告
notificationChannels:
  - projects/keikakun-prod/notificationChannels/email-billing
```

---

## 📝 まとめ

### 推奨設定の一覧

#### 本番環境

| コンポーネント | 設定 | 値 |
|-------------|------|---|
| **Cloud Run** | minScale | 1 |
| | maxScale | 10 |
| | CPU | 2 vCPU |
| | Memory | 1 GiB |
| | cpu-throttling | false |
| **NeonDB** | Min CU | 0.5 CU |
| | Max CU | 4 CU |
| | Auto-suspend | 600秒（10分） |

**月額コスト見積もり**:
- Cloud Run: $125-$200（負荷に応じて）
- NeonDB: $69-$150（Pro Tier + 使用量）
- 合計: $200-$350/月

---

#### 開発環境

| コンポーネント | 設定 | 値 |
|-------------|------|---|
| **Cloud Run** | minScale | 0 |
| | maxScale | 3 |
| | CPU | 1 vCPU |
| | Memory | 512 MiB |
| | cpu-throttling | true |
| **NeonDB** | Min CU | 0.25 CU |
| | Max CU | 1 CU |
| | Auto-suspend | 300秒（5分） |

**月額コスト見積もり**:
- Cloud Run: $30-$50（開発時間のみ）
- NeonDB: $0（Free Tier範囲内）
- 合計: $30-$50/月

---

### チェックリスト

#### デプロイ前

- [ ] Cloud Run YAMLファイルの確認
- [ ] NeonDB設定の確認
- [ ] 環境変数の設定
- [ ] シークレットの設定
- [ ] ヘルスチェックエンドポイントの実装

#### デプロイ後

- [ ] モニタリングダッシュボードの確認
- [ ] アラート設定の確認
- [ ] ヘルスチェックの動作確認
- [ ] 負荷テストの実施
- [ ] コスト監視の設定

#### 運用中

- [ ] 月次でメトリクスレビュー
- [ ] コスト分析（予算内か確認）
- [ ] スケーリング設定の最適化
- [ ] パフォーマンステストの定期実行

---

**作成日**: 2026-02-09
**作成者**: Claude Sonnet 4.5
**最終更新**: 2026-02-09
**バージョン**: 1.0.0
