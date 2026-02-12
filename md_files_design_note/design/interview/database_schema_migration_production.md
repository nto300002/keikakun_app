# 本番環境でのスキーマ変更手順

**作成日**: 2026-01-28
**対象**: 2次面接 - データベース運用・マイグレーション
**関連技術**: Alembic, PostgreSQL, SQLAlchemy

---

## 概要

けいかくんアプリケーションでは、Alembic（SQLAlchemyのマイグレーションツール）を使用してデータベーススキーマの変更を管理しています。本番環境へのマイグレーション適用は、**データ損失ゼロ**と**ダウンタイム最小化**を最重視して慎重に行います。

---

## 1. マイグレーション管理の全体像

### 1.1 ディレクトリ構成

```
k_back/
├── alembic.ini                          # Alembic設定ファイル
├── migrations/
│   ├── env.py                          # Alembic環境設定
│   ├── README                          # Generic single-database configuration
│   ├── script.py.mako                  # マイグレーションテンプレート
│   ├── versions/                       # Pythonマイグレーションファイル
│   │   ├── z8a9b0c1d2e3_add_push_subscriptions_table.py
│   │   ├── b0c1d2e3f4g5_add_threshold_fields_to_notification_preferences.py
│   │   ├── a9b0c1d2e3f4_add_notification_preferences_to_staffs.py
│   │   ├── y7z8a9b0c1d2_make_audit_logs_staff_id_nullable.py
│   │   └── ...（69ファイル）
│   ├── sql/                            # 手動SQLマイグレーション（参考用）
│   ├── 20260112_140334_make_audit_logs_staff_id_nullable.sql
│   ├── 20260113_add_push_subscriptions_table.sql
│   └── manual_migration_add_enum_value.sql
```

---

### 1.2 マイグレーションファイルの種類

| 種類 | ファイル形式 | 使用ケース | 例 |
|------|------------|-----------|---|
| **Alembic Python** | `{revision_id}_{description}.py` | 通常のスキーマ変更（テーブル追加、カラム変更など） | `z8a9b0c1d2e3_add_push_subscriptions_table.py` |
| **手動SQL** | `{date}_{description}.sql` | ENUM値追加、複雑なデータ移行、トリガー作成など | `manual_migration_add_enum_value.sql` |

---

## 2. 開発環境でのマイグレーション作成

### 2.1 自動生成（autogenerate）

**使用ケース**: モデル定義を変更した場合（新しいテーブル、カラム追加など）

**手順**:

```bash
# 1. モデルファイルを編集
# 例: app/models/push_subscription.py を作成

# 2. マイグレーションファイルを自動生成
docker exec -it keikakun_app-backend-1 alembic revision --autogenerate -m "add push_subscriptions table"

# 生成されるファイル:
# migrations/versions/{revision_id}_add_push_subscriptions_table.py
```

**生成されるファイル例** (`z8a9b0c1d2e3_add_push_subscriptions_table.py`):

```python
"""Add push_subscriptions table for Web Push notifications

Revision ID: z8a9b0c1d2e3
Revises: y7z8a9b0c1d2
Create Date: 2026-01-13

Task: Web Push通知のためのpush_subscriptionsテーブル作成
"""
from typing import Sequence, Union
from alembic import op
import sqlalchemy as sa
from sqlalchemy.dialects import postgresql

# revision identifiers, used by Alembic.
revision: str = 'z8a9b0c1d2e3'
down_revision: Union[str, None] = 'y7z8a9b0c1d2'
branch_labels: Union[str, Sequence[str], None] = None
depends_on: Union[str, Sequence[str], None] = None


def upgrade() -> None:
    """Add push_subscriptions table for Web Push notifications"""

    # 1. push_subscriptionsテーブル作成
    op.create_table(
        'push_subscriptions',
        sa.Column('id', postgresql.UUID(as_uuid=True), primary_key=True, server_default=sa.text('gen_random_uuid()')),
        sa.Column('staff_id', postgresql.UUID(as_uuid=True), nullable=False),
        sa.Column('endpoint', sa.Text(), nullable=False),
        sa.Column('p256dh_key', sa.Text(), nullable=False),
        sa.Column('auth_key', sa.Text(), nullable=False),
        sa.Column('user_agent', sa.Text(), nullable=True),
        sa.Column('created_at', sa.DateTime(timezone=True), server_default=sa.text('NOW()'), nullable=False),
        sa.Column('updated_at', sa.DateTime(timezone=True), server_default=sa.text('NOW()'), nullable=False),

        # 外部キー制約
        sa.ForeignKeyConstraint(
            ['staff_id'],
            ['staffs.id'],
            name='push_subscriptions_staff_id_fkey',
            ondelete='CASCADE'
        ),

        # UNIQUE制約（同一エンドポイントは1つのみ）
        sa.UniqueConstraint('endpoint', name='push_subscriptions_endpoint_key')
    )

    # 2. インデックス作成
    op.create_index(
        'idx_push_subscriptions_staff_id',
        'push_subscriptions',
        ['staff_id']
    )


def downgrade() -> None:
    """Remove push_subscriptions table

    WARNING: This will permanently delete all push subscription data.
    """
    op.drop_index('idx_push_subscriptions_staff_id', table_name='push_subscriptions')
    op.drop_table('push_subscriptions')
```

---

### 2.2 手動作成（空のマイグレーション）

**使用ケース**: 複雑なデータ移行、ENUM値追加など

**手順**:

```bash
# 1. 空のマイグレーションファイルを作成
docker exec -it keikakun_app-backend-1 alembic revision -m "add next_plan_start_date to calendar_event_type"

# 生成されるファイル:
# migrations/versions/{revision_id}_add_next_plan_start_date_to_calendar_event_type.py
```

**手動編集例** (`x6y7z8a9b0c1_add_next_plan_start_date_to_calendar_event_type.py`):

```python
"""add next_plan_start_date to calendar_event_type

Revision ID: x6y7z8a9b0c1
Revises: w5x6y7z8a9b0
Create Date: 2026-01-12
"""
from alembic import op

revision = 'x6y7z8a9b0c1'
down_revision = 'w5x6y7z8a9b0'


def upgrade() -> None:
    """Add 'next_plan_start_date' to calendar_event_type ENUM"""

    # PostgreSQLのENUM型に新しい値を追加
    op.execute(
        "ALTER TYPE calendar_event_type ADD VALUE IF NOT EXISTS 'next_plan_start_date'"
    )


def downgrade() -> None:
    """Remove 'next_plan_start_date' from calendar_event_type ENUM

    WARNING: PostgreSQL does not support removing ENUM values.
    This downgrade is NOT possible without recreating the entire ENUM type.
    """
    # PostgreSQLではENUM値の削除は不可能
    # ロールバックが必要な場合は、以下の手順が必要:
    # 1. 新しいENUM型を作成（古い値のみ）
    # 2. カラムを新しい型に変換
    # 3. 古いENUM型を削除
    # 4. 新しいENUM型を元の名前にリネーム
    raise NotImplementedError(
        "Cannot remove ENUM value 'next_plan_start_date' directly. "
        "See manual migration script for workaround."
    )
```

---

### 2.3 開発環境でのテスト

**重要**: 本番環境に適用する前に、必ず開発環境でテストする

```bash
# 1. 現在のマイグレーション状態を確認
docker exec -it keikakun_app-backend-1 alembic current

# 出力例:
# y7z8a9b0c1d2 (head)

# 2. マイグレーションを適用（upgrade）
docker exec -it keikakun_app-backend-1 alembic upgrade head

# 出力例:
# INFO  [alembic.runtime.migration] Running upgrade y7z8a9b0c1d2 -> z8a9b0c1d2e3, Add push_subscriptions table

# 3. データベースの状態を確認
docker exec -it keikakun_app-postgres-1 psql -U keikakun_user -d keikakun_db -c "\d push_subscriptions"

# 4. アプリケーションが正常動作するか確認
docker exec -it keikakun_app-backend-1 pytest tests/

# 5. ロールバックをテスト（downgrade）
docker exec -it keikakun_app-backend-1 alembic downgrade -1

# 出力例:
# INFO  [alembic.runtime.migration] Running downgrade z8a9b0c1d2e3 -> y7z8a9b0c1d2

# 6. 再度アップグレード
docker exec -it keikakun_app-backend-1 alembic upgrade head
```

---

## 3. 本番環境へのマイグレーション適用手順

### 3.1 事前準備（必須）

#### ステップ1: バックアップの取得

**目的**: 万が一のデータ損失に備える

```bash
# neonDB（本番データベース）のバックアップ取得
# neonDBの場合、コンソールから「Branch作成」でバックアップ

# または、pg_dumpでバックアップ
pg_dump -h {PROD_DB_HOST} -U {PROD_DB_USER} -d {PROD_DB_NAME} > backup_$(date +%Y%m%d_%H%M%S).sql
```

**バックアップの確認**:
- ✅ バックアップファイルのサイズを確認（0バイトでないこと）
- ✅ バックアップファイルを別の場所に保存（ローカル + クラウドストレージ）
- ✅ バックアップから復元できることを確認（ステージング環境でテスト）

---

#### ステップ2: メンテナンスモードの設定（任意）

**目的**: マイグレーション中のデータ変更を防ぐ

```bash
# Cloud Run のトラフィックを停止
gcloud run services update-traffic k-back --to-revisions=REVISION=0

# または、フロントエンドでメンテナンスモード表示
# 環境変数 MAINTENANCE_MODE=true を設定
```

---

#### ステップ3: マイグレーションファイルの確認

```bash
# 適用されていないマイグレーションを確認
alembic history

# 出力例:
# y7z8a9b0c1d2 -> z8a9b0c1d2e3 (head), Add push_subscriptions table
# w5x6y7z8a9b0 -> y7z8a9b0c1d2, Make audit_logs.staff_id nullable
# ...

# 現在の状態を確認
alembic current

# 出力例:
# y7z8a9b0c1d2 (本番環境の現在位置)
```

---

### 3.2 本番環境でのマイグレーション実行

#### 方法1: Cloud Runコンテナ内で実行（推奨）

```bash
# 1. Cloud Runのコンテナにアクセス
gcloud run services list
gcloud run services describe k-back --region=asia-northeast1

# 2. Cloud Runのインスタンスで直接実行
gcloud run services update k-back \
  --region=asia-northeast1 \
  --command="alembic upgrade head" \
  --no-traffic

# 3. 実行結果を確認
gcloud logging read "resource.type=cloud_run_revision AND resource.labels.service_name=k-back" \
  --limit=50 \
  --format=json
```

---

#### 方法2: ローカルから本番DBに接続して実行

**注意**: セキュリティリスクがあるため、VPN経由または許可されたIPからのみ実行

```bash
# 1. 本番環境の接続情報を設定
export DATABASE_URL="postgresql://{USER}:{PASSWORD}@{HOST}:{PORT}/{DB}"

# 2. 接続確認
alembic current

# 3. マイグレーション実行
alembic upgrade head

# 出力例:
# INFO  [alembic.runtime.migration] Context impl PostgresqlImpl.
# INFO  [alembic.runtime.migration] Will assume transactional DDL.
# INFO  [alembic.runtime.migration] Running upgrade y7z8a9b0c1d2 -> z8a9b0c1d2e3, Add push_subscriptions table
# INFO  [alembic.runtime.migration] Running upgrade z8a9b0c1d2e3 -> b0c1d2e3f4g5, add threshold fields to notification_preferences

# 4. マイグレーション完了を確認
alembic current

# 出力例:
# b0c1d2e3f4g5 (head)
```

---

#### 方法3: GitHub Actionsでの自動実行（CD）

**ファイル**: `.github/workflows/cd-backend.yml` に追加

```yaml
- name: Run Database Migrations
  run: |
    cd k_back
    alembic upgrade head
  env:
    DATABASE_URL: ${{ secrets.PROD_DATABASE_URL }}
```

**注意**: マイグレーション失敗時のロールバック戦略を明確にする

---

### 3.3 マイグレーション後の確認

#### ステップ1: スキーマの確認

```bash
# テーブルが作成されたか確認
psql $DATABASE_URL -c "\d push_subscriptions"

# 出力例:
# Table "public.push_subscriptions"
# Column       | Type                     | Nullable | Default
# -------------+--------------------------+----------+---------
# id           | uuid                     | not null | gen_random_uuid()
# staff_id     | uuid                     | not null |
# endpoint     | text                     | not null |
# ...

# インデックスが作成されたか確認
psql $DATABASE_URL -c "\di push_subscriptions*"

# 出力例:
# idx_push_subscriptions_staff_id | btree | staff_id
# idx_push_subscriptions_endpoint_hash | hash | endpoint
```

---

#### ステップ2: データの整合性確認

```bash
# 外部キー制約が正しく動作するか確認
psql $DATABASE_URL -c "SELECT conname, conrelid::regclass, confrelid::regclass FROM pg_constraint WHERE contype = 'f' AND conrelid = 'push_subscriptions'::regclass;"

# 出力例:
# conname                        | conrelid           | confrelid
# -------------------------------+--------------------+-----------
# push_subscriptions_staff_id_fkey | push_subscriptions | staffs
```

---

#### ステップ3: アプリケーションの動作確認

```bash
# アプリケーションが起動するか確認
curl https://k-back-xxx.a.run.app/health

# 出力例:
# {"status": "healthy"}

# APIエンドポイントが正常動作するか確認
curl -X POST https://k-back-xxx.a.run.app/api/v1/push-subscriptions/subscribe \
  -H "Authorization: Bearer {TOKEN}" \
  -H "Content-Type: application/json" \
  -d '{"endpoint": "https://fcm.googleapis.com/...", "keys": {...}}'
```

---

### 3.4 メンテナンスモード解除

```bash
# Cloud Run のトラフィックを再開
gcloud run services update-traffic k-back --to-revisions=LATEST=100

# 環境変数 MAINTENANCE_MODE=false に戻す
```

---

## 4. ロールバック手順

### 4.1 ロールバックの判断基準

以下の場合はロールバックを検討:
- ❌ マイグレーション実行中にエラーが発生
- ❌ アプリケーションが起動しない
- ❌ 重大なバグが発見された
- ❌ データの不整合が発生

---

### 4.2 ロールバック実行

#### ステップ1: 1つ前のリビジョンに戻す

```bash
# 現在のリビジョンを確認
alembic current
# 出力: b0c1d2e3f4g5 (head)

# 1つ前に戻す
alembic downgrade -1

# 出力例:
# INFO  [alembic.runtime.migration] Running downgrade b0c1d2e3f4g5 -> a9b0c1d2e3f4

# 確認
alembic current
# 出力: a9b0c1d2e3f4
```

---

#### ステップ2: 特定のリビジョンに戻す

```bash
# y7z8a9b0c1d2 まで戻す
alembic downgrade y7z8a9b0c1d2

# 確認
alembic current
# 出力: y7z8a9b0c1d2
```

---

#### ステップ3: 全てのマイグレーションを取り消す（最終手段）

```bash
# 警告: 全てのテーブルが削除される可能性があります
alembic downgrade base

# 確認
alembic current
# 出力: (empty)
```

---

### 4.3 ロールバック不可能なケース

#### ENUM値の追加

**問題**: PostgreSQLではENUM値の削除は不可能

**対処法**: 新しいENUM型を作成し、カラムを変換

```python
def downgrade() -> None:
    """Remove 'next_plan_start_date' from calendar_event_type ENUM

    WARNING: PostgreSQL does not support removing ENUM values.
    """
    raise NotImplementedError(
        "Cannot remove ENUM value 'next_plan_start_date' directly. "
        "Manual intervention required."
    )
```

**手動ロールバック手順**:

```sql
-- 1. 新しいENUM型を作成（古い値のみ）
CREATE TYPE calendar_event_type_new AS ENUM ('renewal_deadline', 'monitoring_deadline', 'custom');

-- 2. カラムを一時的にTEXT型に変換
ALTER TABLE calendar_events ALTER COLUMN event_type TYPE TEXT;

-- 3. 削除する値を使用しているレコードを削除または更新
DELETE FROM calendar_events WHERE event_type = 'next_plan_start_date';

-- 4. カラムを新しいENUM型に変換
ALTER TABLE calendar_events ALTER COLUMN event_type TYPE calendar_event_type_new USING event_type::calendar_event_type_new;

-- 5. 古いENUM型を削除
DROP TYPE calendar_event_type;

-- 6. 新しいENUM型を元の名前にリネーム
ALTER TYPE calendar_event_type_new RENAME TO calendar_event_type;
```

---

#### データ損失を伴うロールバック

**例**: `push_subscriptions`テーブルの削除

```python
def downgrade() -> None:
    """Remove push_subscriptions table

    WARNING: This will permanently delete all push subscription data.
    Users will need to re-enable push notifications after upgrading again.
    """
    op.drop_table('push_subscriptions')
```

**対処法**: バックアップから復元

```bash
# バックアップから該当テーブルのデータを復元
pg_restore -h {HOST} -U {USER} -d {DB} -t push_subscriptions backup_20260128.sql
```

---

## 5. 手動SQLマイグレーション

### 5.1 手動SQLが必要なケース

| ケース | 理由 | 例 |
|-------|------|---|
| **ENUM値の追加** | Alembicの自動生成が不完全 | `manual_migration_add_enum_value.sql` |
| **複雑なデータ移行** | 複数テーブルにまたがる変更 | `20260112_140334_make_audit_logs_staff_id_nullable.sql` |
| **トリガーの作成** | Alembicでは表現が難しい | `updated_at`自動更新トリガー |
| **パフォーマンス最適化** | インデックスの再構築 | `REINDEX CONCURRENTLY` |

---

### 5.2 手動SQLマイグレーションの実行

**ファイル例**: `migrations/manual_migration_add_enum_value.sql`

```sql
-- =====================================================
-- Revision ID: x6y7z8a9b0c1
-- Revises: w5x6y7z8a9b0
-- Create Date: 2026-01-12
-- calendar_event_type enumに次回計画開始期限の値を追加
-- =====================================================

-- 1. 現在のenum値を確認
SELECT e.enumlabel
FROM pg_enum e
JOIN pg_type t ON e.enumtypid = t.oid
WHERE t.typname = 'calendar_event_type'
ORDER BY e.enumsortorder;

-- 2. 新しいenum値を追加
ALTER TYPE calendar_event_type ADD VALUE IF NOT EXISTS 'next_plan_start_date';

-- 3. 追加後の値を確認
SELECT e.enumlabel
FROM pg_enum e
JOIN pg_type t ON e.enumtypid = t.oid
WHERE t.typname = 'calendar_event_type'
ORDER BY e.enumsortorder;

-- 4. 既存のmonitoring_deadlineイベントをnext_plan_start_dateに更新
UPDATE calendar_events
SET event_type = 'next_plan_start_date'
WHERE event_type = 'monitoring_deadline';

-- 5. 更新結果を確認
SELECT event_type, COUNT(*) as count
FROM calendar_events
GROUP BY event_type
ORDER BY event_type;
```

**実行方法**:

```bash
# 本番DBに接続してSQLを実行
psql $DATABASE_URL -f migrations/manual_migration_add_enum_value.sql

# または、トランザクション内で実行（推奨）
psql $DATABASE_URL <<EOF
BEGIN;
\i migrations/manual_migration_add_enum_value.sql
-- 問題がなければ
COMMIT;
-- 問題があれば
-- ROLLBACK;
EOF
```

---

### 5.3 手動SQLマイグレーションの記録

**重要**: Alembicの履歴に手動マイグレーションを記録する

```bash
# 1. 空のマイグレーションファイルを作成
alembic revision -m "add next_plan_start_date to calendar_event_type"

# 2. upgrade()関数に手動SQL実行を記述
def upgrade() -> None:
    # 手動SQLファイルの内容を実行
    op.execute(
        "ALTER TYPE calendar_event_type ADD VALUE IF NOT EXISTS 'next_plan_start_date'"
    )

# 3. downgrade()関数には「不可能」と記述
def downgrade() -> None:
    raise NotImplementedError("Cannot remove ENUM value directly")
```

---

## 6. 注意事項とベストプラクティス

### 6.1 マイグレーション作成時

| ベストプラクティス | 理由 |
|-----------------|------|
| ✅ **downgrade()を必ず実装** | ロールバック時に必要 |
| ✅ **トランザクション内で実行** | 途中でエラーが発生した場合に自動ロールバック |
| ✅ **インデックスは後から追加** | テーブル作成時にインデックスを作ると時間がかかる |
| ✅ **NOT NULL制約は段階的に追加** | 既存データがある場合、先にDEFAULT値を設定 |
| ✅ **外部キー制約は最後に追加** | データ整合性を確認してから制約を追加 |
| ❌ **本番データを直接変更しない** | 必ずマイグレーションファイル経由で変更 |

---

### 6.2 本番環境での実行時

| ベストプラクティス | 理由 |
|-----------------|------|
| ✅ **必ずバックアップを取得** | データ損失リスクを最小化 |
| ✅ **メンテナンスウィンドウで実行** | ユーザー影響を最小化 |
| ✅ **ステージング環境で事前テスト** | 本番環境での失敗を防ぐ |
| ✅ **ロールバック計画を用意** | 問題発生時の対応を明確化 |
| ✅ **マイグレーション実行を監視** | ログを確認し、エラーを早期発見 |
| ❌ **複数のマイグレーションを一度に実行しない** | 問題の切り分けが困難になる |

---

### 6.3 ENUM型の変更

**推奨アプローチ**:

```sql
-- ❌ Bad: 直接削除は不可能
ALTER TYPE status_type DROP VALUE 'old_value';  -- エラー

-- ✅ Good: IF NOT EXISTS で冪等性を確保
ALTER TYPE status_type ADD VALUE IF NOT EXISTS 'new_value';

-- ✅ Good: 新しいENUM型を作成し、移行
CREATE TYPE status_type_new AS ENUM ('value1', 'value2');
ALTER TABLE table_name ALTER COLUMN status TYPE status_type_new USING status::text::status_type_new;
DROP TYPE status_type;
ALTER TYPE status_type_new RENAME TO status_type;
```

---

### 6.4 大量データのマイグレーション

**問題**: 数百万レコードの更新は時間がかかる

**解決策**: バッチ処理で段階的に更新

```python
def upgrade() -> None:
    """Add default value to large table in batches"""

    # バッチサイズ: 1000件ずつ
    batch_size = 1000

    # 対象レコード数を確認
    result = op.get_bind().execute(
        "SELECT COUNT(*) FROM large_table WHERE new_column IS NULL"
    )
    total = result.scalar()

    # バッチ処理で更新
    for offset in range(0, total, batch_size):
        op.execute(f"""
            UPDATE large_table
            SET new_column = 'default_value'
            WHERE id IN (
                SELECT id FROM large_table
                WHERE new_column IS NULL
                LIMIT {batch_size}
            )
        """)
        print(f"Updated {offset + batch_size}/{total} records")
```

---

## 7. ケーススタディ

### 7.1 ケース1: 新しいテーブルの追加

**要件**: Web Push通知のための`push_subscriptions`テーブルを追加

**手順**:

1. **モデル作成**: `app/models/push_subscription.py`
2. **マイグレーション自動生成**:
   ```bash
   alembic revision --autogenerate -m "add push_subscriptions table"
   ```
3. **開発環境でテスト**:
   ```bash
   alembic upgrade head
   pytest tests/
   alembic downgrade -1
   alembic upgrade head
   ```
4. **本番環境で実行**:
   ```bash
   # バックアップ取得
   pg_dump ... > backup.sql

   # マイグレーション実行
   alembic upgrade head

   # 確認
   alembic current
   psql -c "\d push_subscriptions"
   ```

**結果**: ✅ 成功（ダウンタイムなし、データ損失なし）

---

### 7.2 ケース2: カラムをNULL許可に変更

**要件**: `audit_logs.staff_id`をNULL許可にし、外部キー制約を`ON DELETE SET NULL`に変更

**ファイル**: `20260112_140334_make_audit_logs_staff_id_nullable.sql`

**手順**:

```sql
-- UPGRADE
BEGIN;

-- 1. 既存の外部キー制約を削除
ALTER TABLE audit_logs
DROP CONSTRAINT IF EXISTS audit_logs_staff_id_fkey;

-- 2. カラムをNULL許可に変更
ALTER TABLE audit_logs
ALTER COLUMN staff_id DROP NOT NULL;

-- 3. 新しい外部キー制約を追加（SET NULL）
ALTER TABLE audit_logs
ADD CONSTRAINT audit_logs_staff_id_fkey
FOREIGN KEY (staff_id)
REFERENCES staffs(id)
ON DELETE SET NULL;

COMMIT;
```

**ロールバック**:

```sql
-- DOWNGRADE
-- 警告: staff_id IS NULL のレコードが存在する場合は失敗する

BEGIN;

-- 1. NULL値を持つレコードを削除または更新
DELETE FROM audit_logs WHERE staff_id IS NULL;
-- または
-- UPDATE audit_logs SET staff_id = 'SYSTEM_USER_UUID' WHERE staff_id IS NULL;

-- 2. 外部キー制約を削除
ALTER TABLE audit_logs
DROP CONSTRAINT IF EXISTS audit_logs_staff_id_fkey;

-- 3. カラムをNOT NULLに変更
ALTER TABLE audit_logs
ALTER COLUMN staff_id SET NOT NULL;

-- 4. 元の外部キー制約を追加（CASCADE）
ALTER TABLE audit_logs
ADD CONSTRAINT audit_logs_staff_id_fkey
FOREIGN KEY (staff_id)
REFERENCES staffs(id)
ON DELETE CASCADE;

COMMIT;
```

**結果**: ✅ 成功（監査ログがスタッフ削除後も保持される）

---

### 7.3 ケース3: JSONB カラムへのフィールド追加

**要件**: `staffs.notification_preferences` に `email_threshold_days`, `push_threshold_days` を追加

**ファイル**: `b0c1d2e3f4g5_add_threshold_fields_to_notification_preferences.py`

```python
def upgrade() -> None:
    """Add threshold fields to existing notification_preferences column"""

    # 既存レコードに新しいフィールドを追加
    op.execute("""
        UPDATE staffs
        SET notification_preferences = notification_preferences ||
            '{"email_threshold_days": 30, "push_threshold_days": 10}'::jsonb
        WHERE notification_preferences IS NOT NULL
    """)

    # カラムのデフォルト値を更新
    op.alter_column(
        'staffs',
        'notification_preferences',
        server_default=sa.text(
            "'{\"in_app_notification\": true, \"email_notification\": true, "
            "\"system_notification\": false, \"email_threshold_days\": 30, "
            "\"push_threshold_days\": 10}'::jsonb"
        )
    )


def downgrade() -> None:
    """Remove threshold fields from notification_preferences"""

    # フィールドを削除
    op.execute("""
        UPDATE staffs
        SET notification_preferences =
            notification_preferences - 'email_threshold_days' - 'push_threshold_days'
        WHERE notification_preferences IS NOT NULL
    """)

    # デフォルト値を元に戻す
    op.alter_column(
        'staffs',
        'notification_preferences',
        server_default=sa.text(
            "'{\"in_app_notification\": true, \"email_notification\": true, "
            "\"system_notification\": false}'::jsonb"
        )
    )
```

**結果**: ✅ 成功（既存データを保持したままフィールド追加）

---

## 8. トラブルシューティング

### 8.1 よくあるエラーと対処法

#### エラー1: `alembic.util.exc.CommandError: Can't locate revision identified by 'xxx'`

**原因**: マイグレーション履歴が壊れている

**対処法**:

```bash
# 現在のDBのリビジョンを確認
psql $DATABASE_URL -c "SELECT * FROM alembic_version;"

# マイグレーションファイルのリビジョンを確認
alembic history

# 手動でalembic_versionテーブルを更新
psql $DATABASE_URL -c "UPDATE alembic_version SET version_num = 'correct_revision_id';"
```

---

#### エラー2: `sqlalchemy.exc.ProgrammingError: relation "xxx" already exists`

**原因**: テーブルが既に存在する

**対処法**:

```bash
# マイグレーションをスキップ
alembic stamp head

# または、既存テーブルを削除してから再実行
psql $DATABASE_URL -c "DROP TABLE xxx;"
alembic upgrade head
```

---

#### エラー3: `psycopg2.errors.NotNullViolation: null value in column "xxx" violates not-null constraint`

**原因**: NOT NULL制約を追加したが、NULL値が存在する

**対処法**:

```python
def upgrade() -> None:
    # 1. 先にDEFAULT値を設定
    op.execute("UPDATE table_name SET column_name = 'default_value' WHERE column_name IS NULL")

    # 2. その後にNOT NULL制約を追加
    op.alter_column('table_name', 'column_name', nullable=False)
```

---

#### エラー4: `alembic.util.exc.CommandError: Target database is not up to date`

**原因**: ローカルのマイグレーションファイルと本番DBの状態が一致しない

**対処法**:

```bash
# 本番DBの現在位置を確認
alembic current

# ローカルのマイグレーション履歴を確認
alembic history

# 本番DBを最新に更新
alembic upgrade head
```

---

## 9. まとめ

### 本番環境でのスキーマ変更の鉄則

| 鉄則 | 内容 |
|------|------|
| 1️⃣ **バックアップ必須** | 必ずバックアップを取得してから実行 |
| 2️⃣ **段階的適用** | 複数のマイグレーションを一度に実行しない |
| 3️⃣ **downgrade実装** | 必ずロールバック手順を用意 |
| 4️⃣ **ステージングテスト** | 本番と同じ環境で事前テスト |
| 5️⃣ **監視とログ** | 実行中のログを監視し、エラーを早期発見 |
| 6️⃣ **メンテナンスウィンドウ** | ユーザー影響が少ない時間帯に実行 |
| 7️⃣ **トランザクション** | 可能な限りトランザクション内で実行 |
| 8️⃣ **手動確認** | スキーマとデータの整合性を手動確認 |

### マイグレーションファイル一覧

- **Alembic Python**: 69ファイル（`migrations/versions/`）
- **手動SQL**: 3ファイル（`migrations/*.sql`）
- **最新リビジョン**: `b0c1d2e3f4g5` (add threshold fields to notification_preferences)

### 実装ファイル参照

- `k_back/alembic.ini` - Alembic設定
- `k_back/migrations/env.py` - Alembic環境設定
- `k_back/migrations/versions/` - マイグレーションファイル
- `k_back/migrations/*.sql` - 手動SQLマイグレーション

---

**Last Updated**: 2026-01-28
**Maintained by**: Claude Sonnet 4.5
