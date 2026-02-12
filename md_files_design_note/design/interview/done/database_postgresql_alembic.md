# けいかくん - データベース: PostgreSQL選定理由とマイグレーション管理

**作成日**: 2026-01-27
**対象**: 2次面接 - データベース系質問
**関連技術**: PostgreSQL, MySQL, Alembic, SQLAlchemy, Neon Postgres

---

## 概要

けいかくんアプリケーションのデータベース設計思想、PostgreSQL選定理由、MySQLとの比較、Alembicによるマイグレーション管理、本番環境でのスキーマ変更手順について説明します。

---

## 1. PostgreSQLを選んだ理由

### 1.1 技術的な選定理由

#### 理由1: JSON型のネイティブサポート

**けいかくんでの使用例**:
```python
# app/models/calendar_account.py
class CalendarAccount(Base):
    service_account_key = Column(Text)  # 暗号化されたJSON
    calendar_settings = Column(JSONB)   # 設定データをJSON形式で保存
```

**PostgreSQLの利点**:
- `JSONB`型で効率的なJSON保存・検索
- JSON内のフィールドにインデックス作成可能
- GIN/GiSTインデックスでJSONクエリを高速化

**MySQLとの比較**:
| 機能 | PostgreSQL | MySQL |
|-----|-----------|-------|
| JSON型 | JSONB（バイナリ、高速） | JSON（テキスト、遅い） |
| JSONインデックス | GIN/GiSTインデックス | 仮想カラム経由のみ |
| JSON検索 | ネイティブ演算子（`->`, `->>`, `@>`） | JSON関数のみ |

**具体例**:
```sql
-- PostgreSQL: 高速なJSON検索
SELECT * FROM calendar_accounts
WHERE calendar_settings @> '{"notify_enabled": true}';

-- MySQL: 関数を使った検索（遅い）
SELECT * FROM calendar_accounts
WHERE JSON_EXTRACT(calendar_settings, '$.notify_enabled') = true;
```

---

#### 理由2: UUID型のネイティブサポート

**けいかくんでの使用例**:
```python
# app/models/staff.py
class Staff(Base):
    id: Mapped[uuid.UUID] = mapped_column(
        UUID(as_uuid=True),  # PostgreSQL UUID型
        primary_key=True,
        server_default=func.gen_random_uuid()
    )
```

**PostgreSQLの利点**:
- UUID型でメモリ効率的（16バイト）
- `gen_random_uuid()`でDB側で生成
- インデックス効率が良い

**MySQLとの比較**:
| 機能 | PostgreSQL | MySQL |
|-----|-----------|-------|
| UUID型 | ネイティブUUID型（16バイト） | CHAR(36)またはBINARY(16) |
| UUID生成 | `gen_random_uuid()` | UUID()関数（36文字文字列） |
| インデックス効率 | 高い | CHAR(36)の場合低い |

**ストレージサイズ比較**:
```
PostgreSQL: 16バイト（UUID型）
MySQL CHAR(36): 36バイト（文字列）
MySQL BINARY(16): 16バイト（変換が必要）
```

---

#### 理由3: トランザクション分離レベルの厳格性

**PostgreSQLの利点**:
- デフォルトで`READ COMMITTED`
- `SERIALIZABLE`分離レベルでもパフォーマンス良好
- 同時書き込みの競合検出が確実

**けいかくんでの重要性**:
```python
# app/services/billing_service.py
async def process_payment(db: AsyncSession, office_id: UUID):
    """
    課金処理（トランザクション必須）
    - 課金ステータス更新
    - 監査ログ記録
    - Webhookイベント記録
    """
    async with db.begin():  # トランザクション開始
        billing = await crud.billing.get_by_office_id(db, office_id)
        billing.status = "active"
        await crud.audit_log.create(db, ...)
        await db.commit()  # 全て成功するか、全て失敗するか
```

**MySQLとの比較**:
| 機能 | PostgreSQL | MySQL |
|-----|-----------|-------|
| デフォルト分離レベル | READ COMMITTED | REPEATABLE READ |
| MVCC実装 | 優秀 | InnoDBで対応 |
| デッドロック検出 | 即座 | タイムアウト待ち |
| ギャップロック | なし | あり（性能低下） |

---

#### 理由4: 拡張性（Extension）

**PostgreSQLの拡張機能**:
```sql
-- Full-text search（将来的に使用可能）
CREATE EXTENSION pg_trgm;  -- 部分一致検索の高速化

-- PostGIS（位置情報、将来的に使用可能）
CREATE EXTENSION postgis;

-- UUID生成
CREATE EXTENSION "uuid-ossp";  -- gen_random_uuid()
```

**けいかくんで使用中**:
- `gen_random_uuid()`: UUID自動生成
- `pg_trgm`: 利用者名・スタッフ名の曖昧検索（将来実装予定）

**MySQLとの比較**:
- MySQLにはExtension機能がない
- プラグインは限定的

---

#### 理由5: 厳格なデータ型と制約

**PostgreSQLの厳格性**:
```sql
-- 日付時刻型の厳格なチェック
CREATE TABLE staffs (
    created_at TIMESTAMP WITH TIME ZONE NOT NULL DEFAULT NOW()
);

-- ❌ PostgreSQL: 不正な日付は拒否
INSERT INTO staffs (created_at) VALUES ('2026-02-30');  -- Error!

-- ⚠️ MySQL: ゼロ日付を許可（sql_modeによる）
INSERT INTO staffs (created_at) VALUES ('0000-00-00 00:00:00');  -- OK（危険）
```

**けいかくんでの重要性**:
- 不正データの混入を防ぐ
- データ整合性の保証
- バグの早期発見

---

#### 理由6: Neon Postgresの利用

**Neon Postgresの特徴**:
- サーバーレスPostgreSQL（自動スケーリング）
- ブランチ機能（テスト環境を即座に作成）
- ポイントインタイムリカバリ（PITR）
- 無料枠が豊富（月0.5GB、3つのブランチ）

**けいかくんの構成**:
```
production branch  ← 本番環境
    ├── dev_test branch   ← テスト環境（GitHub Actions用）
    └── local branch      ← ローカル開発環境
```

**MySQLのホスティングとの比較**:
| 機能 | Neon Postgres | MySQL（一般的なホスティング） |
|-----|--------------|------------------------------|
| 自動スケーリング | ✅ 自動 | ❌ 手動 |
| ブランチ機能 | ✅ Git風 | ❌ なし |
| PITR | ✅ 7日間無料 | ⚠️ 有料プランのみ |
| 接続プーリング | ✅ 自動 | ⚠️ 自前で設定 |
| 無料枠 | ✅ 0.5GB | ⚠️ 限定的 |

---

### 1.2 ビジネス的な選定理由

#### 理由1: コスト効率

**Neon Postgres無料枠**:
- 月0.5GBストレージ
- 月100時間のアクティブタイム
- 3つのブランチ
- **けいかくんの初期段階では実質無料**

**MySQL（例: PlanetScale）**:
- 無料枠: 5GBストレージ
- ブランチ機能はあるが、無料枠では1つのみ

**選定理由**:
- 初期コストを抑えつつ、本番レベルの機能を使用
- スケールアウト時も段階的にコスト増加

---

#### 理由2: 開発スピード

**Neonのブランチ機能**:
```bash
# テスト環境を即座に作成
neon branch create --project-id xxx --name test-feature-x

# DATABASE_URLを取得
neon connection-string test-feature-x

# テスト完了後、即座に削除
neon branch delete test-feature-x
```

**利点**:
- 機能開発ごとに独立したDB環境
- 本番データをコピーしてテスト可能
- マイグレーションの事前検証

**MySQLでは**:
- 別サーバーを立てる必要がある（コスト増）
- データコピーに時間がかかる

---

#### 理由3: デプロイの安全性

**Neonのポイントインタイムリカバリ（PITR）**:
```bash
# マイグレーション前の状態に戻す
neon branch create \
  --project-id xxx \
  --restore-to-time "2026-01-27T09:00:00Z"
```

**利点**:
- マイグレーション失敗時に即座にロールバック
- データ損失のリスク最小化

**MySQLでは**:
- バックアップからの復元（時間がかかる）
- PITRは有料プランのみ

---

### 1.3 PostgreSQL vs MySQL 総合比較表

| 項目 | PostgreSQL | MySQL | けいかくんでの重要度 |
|-----|-----------|-------|---------------------|
| JSON型 | JSONB（高速） | JSON（遅い） | ★★★ 高 |
| UUID型 | ネイティブ | CHAR/BINARY | ★★★ 高 |
| トランザクション | 厳格 | 緩い | ★★★ 高 |
| Extension | 豊富 | 限定的 | ★★☆ 中 |
| データ型厳格性 | 厳格 | 緩い | ★★★ 高 |
| パフォーマンス（読み込み） | 優秀 | 非常に優秀 | ★☆☆ 低 |
| パフォーマンス（書き込み） | 優秀 | 優秀 | ★★☆ 中 |
| サーバーレス対応 | Neon | PlanetScale | ★★★ 高 |
| 学習コスト | やや高 | 低い | ★☆☆ 低 |
| コミュニティ | 活発 | 非常に活発 | ★☆☆ 低 |

**結論**: けいかくんの要件（JSON、UUID、厳格なトランザクション）ではPostgreSQLが最適

---

## 2. Alembicでマイグレーション管理する際の注意点

### 2.1 Alembicとは

**定義**:
- SQLAlchemy用のデータベースマイグレーションツール
- Djangoの`makemigrations`に相当
- Git風のバージョン管理

**けいかくんの構成**:
```
k_back/
├── alembic.ini          # Alembic設定ファイル
└── migrations/
    ├── env.py           # マイグレーション環境設定
    └── versions/        # マイグレーションファイル
        ├── 3f8d9e2a1b4c_add_password_reset_tokens.py
        ├── 2a1b3c4d5e6f_add_push_subscriptions.py
        └── ...
```

---

### 2.2 注意点1: 環境変数の管理

#### 問題

マイグレーション実行時に誤って本番DBに接続してしまうリスク

#### 解決策

**env.pyでの環境変数処理**:
```python
# migrations/env.py
import dotenv
import os

dotenv.load_dotenv()

# 環境変数からDATABASE_URLを取得
db_url = os.getenv('DATABASE_URL', "")

# asyncpg → psycopg（同期版）に変換
if db_url and db_url.startswith("postgresql+asyncpg://"):
    db_url = db_url.replace("postgresql+asyncpg://", "postgresql://", 1)

config.set_main_option('sqlalchemy.url', db_url)
```

**ポイント**:
- ✅ `.env`ファイルから`DATABASE_URL`を読み込む
- ✅ `postgresql+asyncpg://` → `postgresql://`に変換（Alembicは同期版のみ対応）
- ✅ 環境ごとに`.env`を分ける

**環境分離**:
```bash
# ローカル開発環境
DATABASE_URL=postgresql://localhost/keikakun_local

# テスト環境（GitHub Actions）
TEST_DATABASE_URL=postgresql://neon_test_branch

# 本番環境
PROD_DATABASE_URL=postgresql://neon_production_branch
```

---

### 2.3 注意点2: autogenerate の限界

#### 問題

`alembic revision --autogenerate`は完璧ではない

#### 検出できるもの

- ✅ テーブルの追加・削除
- ✅ カラムの追加・削除
- ✅ インデックスの追加・削除
- ✅ 外部キー制約の追加・削除

#### 検出できないもの

- ❌ カラムのリネーム（削除+追加と認識される）
- ❌ テーブルのリネーム
- ❌ データ型の変更（場合による）
- ❌ ENUM型の値追加
- ❌ カスタムSQL（トリガー、ビュー、関数）

#### 対処法

**手動でマイグレーションファイルを編集**:
```python
# autogenerateで生成されたファイル
def upgrade():
    op.drop_column('staffs', 'old_name')
    op.add_column('staffs', sa.Column('new_name', sa.String(50)))

# ❌ これではデータが失われる！

# ✅ 手動で修正（カラムリネーム）
def upgrade():
    op.alter_column('staffs', 'old_name', new_column_name='new_name')
```

**チェックリスト**:
- [ ] autogenerate実行後、生成されたファイルを必ず確認
- [ ] カラムリネームは手動で修正
- [ ] データ変換が必要な場合はupgrade/downgradeに追加

---

### 2.4 注意点3: downgrade() の実装

#### 問題

`downgrade()`を実装しないとロールバックできない

#### 悪い例

```python
def upgrade():
    op.add_column('staffs', sa.Column('new_field', sa.String(50)))

def downgrade():
    pass  # ❌ 何もしない！
```

**リスク**:
- マイグレーション失敗時にロールバックできない
- データ整合性が壊れる

#### 良い例

```python
def upgrade():
    op.add_column('staffs', sa.Column('new_field', sa.String(50)))

def downgrade():
    op.drop_column('staffs', 'new_field')  # ✅ 確実にロールバック
```

---

#### データ削除を伴う変更の注意

**危険なdowngrade**:
```python
def upgrade():
    op.drop_column('staffs', 'deprecated_field')  # データが失われる

def downgrade():
    op.add_column('staffs', sa.Column('deprecated_field', sa.String(50)))
    # ❌ カラムは復元できるが、データは復元できない！
```

**対策**:
1. **段階的削除**:
```python
# Phase 1: カラムを非推奨化（使用停止）
def upgrade():
    pass  # コード側で使用を停止

# Phase 2: 数週間後、データをバックアップ
def upgrade():
    # データをバックアップテーブルにコピー
    op.execute("INSERT INTO staffs_backup SELECT * FROM staffs")

# Phase 3: カラムを削除
def upgrade():
    op.drop_column('staffs', 'deprecated_field')
```

2. **データ変換の記録**:
```python
def upgrade():
    # JSON形式からリレーショナル形式に変換
    conn = op.get_bind()
    staffs = conn.execute("SELECT id, settings FROM staffs")
    for staff in staffs:
        settings = json.loads(staff.settings)
        conn.execute(
            "UPDATE staffs SET notify_enabled = %s WHERE id = %s",
            (settings['notify_enabled'], staff.id)
        )

def downgrade():
    # 逆変換を実装
    conn = op.get_bind()
    staffs = conn.execute("SELECT id, notify_enabled FROM staffs")
    for staff in staffs:
        settings = {'notify_enabled': staff.notify_enabled}
        conn.execute(
            "UPDATE staffs SET settings = %s WHERE id = %s",
            (json.dumps(settings), staff.id)
        )
```

---

### 2.5 注意点4: マイグレーションの順序

#### 問題

複数の開発者が並行でマイグレーションを作成すると、順序が壊れる

#### 例

```
main branch:
  ├── aaa_add_field_x.py (Developer A)
  └── bbb_add_field_y.py (Developer B)

Developer Aのブランチ:
  └── ccc_add_field_z.py  # aaa → ccc

Developer Bのブランチ:
  └── ddd_add_field_w.py  # bbb → ddd

マージ後:
  aaa → ccc → bbb → ddd  # ❌ 順序が壊れる！
```

#### 対処法

**1. マージ前にリベース**:
```bash
# mainブランチの最新を取得
git checkout main
git pull

# 自分のブランチでリベース
git checkout feature-x
git rebase main

# マイグレーションを再生成
alembic revision --autogenerate -m "add field z"
```

**2. down_revision を確認**:
```python
# migrations/versions/ccc_add_field_z.py
revision = 'ccc123456789'
down_revision = 'bbb987654321'  # ← 最新のmainブランチのリビジョンを指定
```

**3. マイグレーション履歴確認**:
```bash
# 現在のマイグレーション履歴
alembic history

# 出力例:
# ccc -> bbb -> aaa (head)
```

---

### 2.6 注意点5: 本番環境での実行タイミング

#### 問題

デプロイ中にマイグレーション実行すると、アプリとDBのバージョン不整合が発生

#### 危険なシナリオ

```
1. 新バージョンのアプリをデプロイ（新カラムを使用）
2. マイグレーション実行（新カラムを追加）
   ↑
   この間、アプリは新カラムにアクセスしようとするが存在しない
   → エラー！
```

#### 安全な方法

**方法1: メンテナンスモード（推奨）**:
```bash
# 1. メンテナンスモードに切り替え
gcloud run services update k-back \
  --set-env-vars MAINTENANCE_MODE=true

# 2. マイグレーション実行
alembic upgrade head

# 3. 新バージョンデプロイ
gcloud builds submit ...

# 4. メンテナンスモード解除
gcloud run services update k-back \
  --remove-env-vars MAINTENANCE_MODE
```

**方法2: 後方互換性のあるマイグレーション**:
```python
# Phase 1: カラム追加（デフォルト値あり）
def upgrade():
    op.add_column('staffs', sa.Column('new_field', sa.String(50), server_default=''))

# アプリコードは新カラムを使わない（旧バージョンも動作）

# Phase 2: アプリデプロイ（新カラムを使用開始）

# Phase 3: デフォルト値削除（必要に応じて）
def upgrade():
    op.alter_column('staffs', 'new_field', server_default=None)
```

---

### 2.7 注意点6: テスト環境での事前検証

#### 重要性

本番環境でマイグレーション失敗は致命的

#### 検証手順

**1. ローカル環境でテスト**:
```bash
# マイグレーション実行
alembic upgrade head

# アプリ起動
uvicorn app.main:app --reload

# 動作確認
pytest tests/
```

**2. テスト環境（Neonブランチ）でテスト**:
```bash
# テストブランチ作成
neon branch create --name test-migration-xxx

# DATABASE_URL更新
export DATABASE_URL=<test_branch_url>

# マイグレーション実行
alembic upgrade head

# 本番データをコピーしてテスト（推奨）
neon branch create --name test-migration-xxx --parent production
```

**3. ダウングレードのテスト**:
```bash
# アップグレード
alembic upgrade head

# ダウングレード
alembic downgrade -1

# 再度アップグレード
alembic upgrade head

# データ整合性確認
psql $DATABASE_URL -c "SELECT COUNT(*) FROM staffs;"
```

---

## 3. 本番環境でスキーマ変更するときの手順

### 3.1 全体フロー

```
[計画・設計]
    ↓
[マイグレーションファイル作成]
    ↓
[ローカル環境でテスト]
    ↓
[テスト環境（Neonブランチ）でテスト]
    ↓
[ダウングレードテスト]
    ↓
[本番DBバックアップ]
    ↓
[メンテナンスモード開始]
    ↓
[マイグレーション実行]
    ↓
[動作確認]
    ↓
[メンテナンスモード解除]
    ↓
[監視・ログ確認]
```

---

### 3.2 詳細手順

#### Step 1: 計画・設計

**チェックリスト**:
- [ ] スキーマ変更の目的を明確化
- [ ] データ移行が必要か確認
- [ ] ダウンタイムが許容できるか確認
- [ ] ロールバック手順を計画

**設計書作成**:
```markdown
# スキーマ変更計画書

## 目的
パスワードリセット機能の追加

## 変更内容
- テーブル追加: password_reset_tokens
- テーブル追加: password_reset_audit_logs

## 影響範囲
- ダウンタイム: 約5分
- データ移行: なし
- 既存機能への影響: なし

## ロールバック手順
- alembic downgrade -1
```

---

#### Step 2: マイグレーションファイル作成

```bash
# autogenerateで雛形作成
docker exec keikakun_app-backend-1 alembic revision --autogenerate -m "add password reset tokens"

# 生成されたファイルを確認・修正
vim k_back/migrations/versions/3f8d9e2a1b4c_add_password_reset_tokens.py
```

**チェックポイント**:
- [ ] `upgrade()`が正しく実装されているか
- [ ] `downgrade()`が確実にロールバックできるか
- [ ] インデックスが適切に設定されているか
- [ ] 外部キー制約のカスケード設定が正しいか

---

#### Step 3: ローカル環境でテスト

```bash
# データベースリセット
docker-compose down -v
docker-compose up -d

# マイグレーション実行
docker exec keikakun_app-backend-1 alembic upgrade head

# アプリ起動
docker exec keikakun_app-backend-1 uvicorn app.main:app --reload

# テスト実行
docker exec keikakun_app-backend-1 pytest tests/ -v

# ダウングレードテスト
docker exec keikakun_app-backend-1 alembic downgrade -1
docker exec keikakun_app-backend-1 alembic upgrade head
```

---

#### Step 4: テスト環境（Neonブランチ）でテスト

```bash
# 本番データをコピーしたテストブランチ作成
neon branch create \
  --project-id xxx \
  --name test-migration-password-reset \
  --parent production

# DATABASE_URL取得
export DATABASE_URL=$(neon connection-string test-migration-password-reset)

# マイグレーション実行
alembic upgrade head

# データ確認
psql $DATABASE_URL -c "\d+ password_reset_tokens"
psql $DATABASE_URL -c "SELECT COUNT(*) FROM password_reset_tokens;"

# ダウングレードテスト
alembic downgrade -1

# 再度アップグレード
alembic upgrade head
```

**重要**: 本番データをコピーすることで、本番環境と同じ条件でテスト可能

---

#### Step 5: 本番DBバックアップ

**Neon Postgresの場合**:
- 自動的にPITR（ポイントインタイムリカバリ）が有効
- マイグレーション直前の時刻を記録

```bash
# 現在時刻を記録（ロールバック用）
echo "Backup time: $(date -u +"%Y-%m-%dT%H:%M:%SZ")" > backup_time.txt
# 出力例: Backup time: 2026-01-27T10:00:00Z
```

**追加バックアップ（推奨）**:
```bash
# pg_dumpでバックアップ
pg_dump $PROD_DATABASE_URL > backup_$(date +%Y%m%d_%H%M%S).sql

# S3にアップロード
aws s3 cp backup_*.sql s3://keikakun-backups/database/
```

---

#### Step 6: メンテナンスモード開始

**方法1: Cloud Run環境変数で制御**:
```bash
# メンテナンスモード有効化
gcloud run services update k-back \
  --set-env-vars MAINTENANCE_MODE=true \
  --region asia-northeast1
```

**方法2: メンテナンスページ表示**:
```python
# app/main.py
@app.middleware("http")
async def maintenance_mode_middleware(request: Request, call_next):
    """メンテナンスモード時はメンテナンスページを表示"""
    if os.getenv("MAINTENANCE_MODE") == "true":
        return JSONResponse(
            status_code=503,
            content={
                "detail": "システムメンテナンス中です。しばらくお待ちください。",
                "retry_after": 600  # 10分後に再試行
            }
        )
    return await call_next(request)
```

**ユーザー通知**:
- フロントエンドでメンテナンス画面を表示
- 事前にメール・Slack通知

---

#### Step 7: マイグレーション実行

**本番環境での実行**:
```bash
# Cloud Runコンテナに接続（推奨しない）
# 代わりに、Cloud Buildでジョブ実行

# 方法1: Cloud Run Jobsを使用（推奨）
gcloud run jobs create migration-job \
  --image asia-northeast1-docker.pkg.dev/xxx/k-back-repo/k-back:latest \
  --set-env-vars DATABASE_URL=$PROD_DATABASE_URL \
  --command alembic \
  --args "upgrade,head" \
  --region asia-northeast1

gcloud run jobs execute migration-job

# 方法2: ローカルから本番DBに接続（事前にIP許可が必要）
export DATABASE_URL=$PROD_DATABASE_URL
alembic upgrade head
```

**実行ログ確認**:
```bash
# リアルタイムログ監視
gcloud run jobs logs tail migration-job

# 出力例:
# INFO [alembic.runtime.migration] Running upgrade aaa -> bbb, add password reset tokens
# INFO [alembic.runtime.migration] Running upgrade bbb -> ccc
```

---

#### Step 8: 動作確認

**データベース確認**:
```bash
# PostgreSQLに接続
psql $PROD_DATABASE_URL

# テーブル存在確認
\d+ password_reset_tokens

# データ確認
SELECT COUNT(*) FROM password_reset_tokens;

# インデックス確認
\di password_reset_tokens*

# 外部キー制約確認
SELECT conname, contype FROM pg_constraint WHERE conrelid = 'password_reset_tokens'::regclass;
```

**アプリケーション動作確認**:
```bash
# ヘルスチェック
curl https://k-back-xxxxxxxxx-an.a.run.app/health

# 新機能のテスト
curl -X POST https://k-back-xxxxxxxxx-an.a.run.app/api/v1/auth/forgot-password \
  -H "Content-Type: application/json" \
  -d '{"email": "test@example.com"}'
```

---

#### Step 9: アプリケーションデプロイ

```bash
# 新バージョンのアプリをデプロイ
gcloud builds submit \
  --config cloudbuild.yml \
  --substitutions=_PROD_DATABASE_URL="$PROD_DATABASE_URL",... \
  .
```

**デプロイ後の確認**:
```bash
# Cloud Runログ確認
gcloud run logs read k-back --limit=50

# エラーがないか確認
gcloud run logs read k-back | grep ERROR
```

---

#### Step 10: メンテナンスモード解除

```bash
# メンテナンスモード無効化
gcloud run services update k-back \
  --remove-env-vars MAINTENANCE_MODE \
  --region asia-northeast1
```

**ユーザー通知**:
- メンテナンス完了をメール・Slack通知
- フロントエンドで通常画面に戻す

---

#### Step 11: 監視・ログ確認

**監視項目**:
- [ ] エラー率（5xxエラー）
- [ ] レスポンス時間
- [ ] データベース接続数
- [ ] 新機能の使用状況

**Cloud Monitoring確認**:
```bash
# エラー率確認
gcloud logging read "resource.type=cloud_run_revision AND severity>=ERROR" --limit=50

# レスポンス時間確認
gcloud logging read "resource.type=cloud_run_revision AND httpRequest.latency>3s" --limit=20
```

**1時間後、1日後、1週間後に再確認**

---

### 3.3 トラブルシューティング

#### 問題1: マイグレーション失敗

**症状**:
```
Error: relation "password_reset_tokens" already exists
```

**原因**:
- 以前のマイグレーションが途中で失敗
- テーブルが残っている

**解決法**:
```bash
# PostgreSQLに接続
psql $DATABASE_URL

# 手動でテーブル削除
DROP TABLE IF EXISTS password_reset_tokens CASCADE;

# Alembicバージョンテーブル確認
SELECT * FROM alembic_version;

# 前のバージョンにリセット
UPDATE alembic_version SET version_num = '前のバージョンID';

# 再度マイグレーション実行
alembic upgrade head
```

---

#### 問題2: データ整合性エラー

**症状**:
```
IntegrityError: null value in column "staff_id" violates not-null constraint
```

**原因**:
- 既存データとの整合性が取れていない
- NOT NULL制約の追加時にデフォルト値がない

**解決法**:
```python
# マイグレーションファイルを修正
def upgrade():
    # 段階的に追加
    # Step 1: カラム追加（NULL許可）
    op.add_column('password_reset_tokens', sa.Column('staff_id', UUID, nullable=True))

    # Step 2: データ移行
    op.execute("UPDATE password_reset_tokens SET staff_id = '既存のUUID'")

    # Step 3: NOT NULL制約追加
    op.alter_column('password_reset_tokens', 'staff_id', nullable=False)
```

---

#### 問題3: ロールバックが必要

**PITRでロールバック**:
```bash
# バックアップ時刻を確認
cat backup_time.txt
# Backup time: 2026-01-27T10:00:00Z

# 該当時刻に復元
neon branch create \
  --project-id xxx \
  --name rollback-branch \
  --restore-to-time "2026-01-27T10:00:00Z"

# 新しいブランチのDATABASE_URLを取得
export NEW_DATABASE_URL=$(neon connection-string rollback-branch)

# Cloud Run環境変数を更新
gcloud run services update k-back \
  --update-env-vars DATABASE_URL=$NEW_DATABASE_URL \
  --region asia-northeast1
```

**Alembicでロールバック**:
```bash
# 1つ前のバージョンに戻す
alembic downgrade -1

# 特定のバージョンに戻す
alembic downgrade 2a1b3c4d5e6f
```

---

## 4. 面接で強調すべきポイント

### 4.1 データベース選定の技術的根拠

**PostgreSQL選定は感覚ではなく、具体的な要件に基づく**:

1. **JSON型のネイティブサポート**
   - 設定データをJSONB型で保存
   - MySQLのJSON型より高速

2. **UUID型のネイティブサポート**
   - 分散システムで一意性を保証
   - MySQLのCHAR(36)よりメモリ効率的

3. **トランザクション分離レベルの厳格性**
   - 課金処理の整合性を保証
   - 同時書き込みの競合を確実に検出

4. **Neon Postgresの優位性**
   - サーバーレス（自動スケーリング）
   - ブランチ機能でテスト環境を即座に作成
   - PITRで安全なロールバック

---

### 4.2 マイグレーション管理の実践的知識

**Alembicの注意点を理解している**:

1. **autogenerateの限界を知っている**
   - カラムリネームは手動修正が必要
   - 必ず生成されたファイルを確認

2. **downgrade()を確実に実装**
   - ロールバック可能性を常に確保
   - データ削除を伴う変更は段階的に実行

3. **環境分離の徹底**
   - テスト環境と本番環境を完全分離
   - 誤って本番DBに接続しない設計

4. **本番環境での慎重な実行**
   - メンテナンスモードで安全に実行
   - 事前にテスト環境で十分に検証

---

### 4.3 本番環境での実運用経験

**スキーマ変更の手順を体系化している**:

1. **11ステップの確立された手順**
   - 計画 → テスト → バックアップ → 実行 → 監視

2. **リスク管理**
   - PITRでいつでもロールバック可能
   - メンテナンスモードでダウンタイムを最小化

3. **トラブルシューティング経験**
   - マイグレーション失敗時の対処法を把握
   - データ整合性エラーの解決経験

---

## 5. 将来的な改善案

### 5.1 ゼロダウンタイムマイグレーション

**段階的スキーマ変更**:
```python
# Phase 1: 新カラム追加（NULL許可、デフォルト値あり）
def upgrade():
    op.add_column('staffs', sa.Column('new_field', sa.String(50), server_default=''))

# Phase 2: アプリデプロイ（新旧両方のカラムを使用）

# Phase 3: データ移行

# Phase 4: 旧カラム削除
```

---

### 5.2 マイグレーション自動実行

**Cloud Run起動時に自動マイグレーション**:
```dockerfile
# Dockerfile
CMD alembic upgrade head && uvicorn app.main:app --host 0.0.0.0 --port 8080
```

**注意**: 複数インスタンス起動時の競合に注意

---

### 5.3 スキーマドリフト検出

**定期的にスキーマ比較**:
```bash
# 本番DBとモデル定義の差分検出
alembic check
```

---

## 6. 関連資料

- [PostgreSQL公式ドキュメント](https://www.postgresql.org/docs/)
- [Alembic公式ドキュメント](https://alembic.sqlalchemy.org/)
- [Neon Postgres公式ドキュメント](https://neon.tech/docs)
- 内部資料: `phase2_database.md` - データベース設計
- 内部資料: `deployment_rollback_strategy.md` - ロールバック戦略

---

**最終更新**: 2026-01-27
**作成者**: Claude Sonnet 4.5
