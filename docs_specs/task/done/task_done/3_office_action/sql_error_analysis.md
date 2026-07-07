# スタッフ削除機能マイグレーションSQLエラー分析

## エラー概要

**発生日時**: 2024-11-24
**エラー内容**: `ERROR: column "office_id" does not exist (SQLSTATE 42703)`
**発生箇所**: `migration_staff_deletion_upgrade.sql` 実行時

## エラー詳細

### 実行されたSQL（18行目）
```sql
CREATE INDEX idx_staff_office_id_is_deleted ON staffs(office_id, is_deleted);
```

### エラーメッセージ
```
ERROR: column "office_id" does not exist (SQLSTATE 42703)
```

## 原因分析

### 根本原因

**staffsテーブルに`office_id`カラムが存在しない**

### Staffモデルの構造

`app/models/staff.py` を確認したところ、以下の構造になっています:

```python
class Staff(Base):
    __tablename__ = 'staffs'

    id: Mapped[uuid.UUID] = mapped_column(...)
    email: Mapped[str] = mapped_column(...)
    # ... 他のフィールド

    # 論理削除関連
    is_deleted: Mapped[bool] = mapped_column(Boolean, default=False, nullable=False, index=True)
    deleted_at: Mapped[Optional[datetime.datetime]] = mapped_column(...)
    deleted_by: Mapped[Optional[uuid.UUID]] = mapped_column(...)

    # office_idカラムは存在しない！

    # Relationships
    office_associations: Mapped[List["OfficeStaff"]] = relationship(
        "OfficeStaff",
        back_populates="staff",
        foreign_keys="[OfficeStaff.staff_id]"
    )
```

### StaffとOfficeの関連構造

StaffとOfficeは**多対多の関係**であり、中間テーブル`office_staffs`を経由しています:

```
staffs (1) ←→ (N) office_staffs (N) ←→ (1) offices
```

- **staffsテーブル**: `office_id`カラムなし
- **office_staffsテーブル**: `staff_id`, `office_id`, `is_primary`を持つ中間テーブル
- Staffモデルは`office_associations`リレーションシップでOfficeにアクセス

### なぜこのエラーが発生したか

マイグレーションスクリプトの作成時に、以下の想定ミスがありました:

1. **誤った想定**: staffsテーブルに`office_id`カラムが存在すると想定
2. **実際の構造**: StaffとOfficeは多対多関係で、`office_staffs`テーブル経由

## 解決方法

### 方法1: 問題のあるインデックスを削除（推奨）

`is_deleted`カラムのみのインデックスは既に17行目で作成されています:

```sql
CREATE INDEX idx_staff_is_deleted ON staffs(is_deleted);
```

18行目の複合インデックスは不要または誤りであるため、削除します。

**修正後のマイグレーションSQL（17-18行目）**:

```sql
-- 3. staffsテーブルのインデックス追加
CREATE INDEX idx_staff_is_deleted ON staffs(is_deleted);
-- 削除: CREATE INDEX idx_staff_office_id_is_deleted ON staffs(office_id, is_deleted);
```

### 方法2: office_staffsテーブルにインデックスを追加（オプション）

もし特定の事務所の削除済みスタッフを効率的に取得したい場合は、`office_staffs`テーブルに複合インデックスを追加します:

```sql
-- office_staffsテーブルに複合インデックスを追加
CREATE INDEX idx_office_staffs_office_id_staff_deleted
ON office_staffs(office_id)
WHERE NOT EXISTS (
    SELECT 1 FROM staffs
    WHERE staffs.id = office_staffs.staff_id
    AND staffs.is_deleted = true
);
```

ただし、このアプローチは複雑であり、通常はアプリケーション層でフィルタリングする方が適切です。

### 方法3: クエリの最適化

スタッフ削除機能で事務所内のスタッフを取得する際は、以下のようなクエリを使用します:

```python
# app/crud/crud_staff.py
async def get_by_office_id(
    self,
    db: AsyncSession,
    office_id: UUID,
    exclude_deleted: bool = True
) -> List[Staff]:
    """事務所内のスタッフを取得"""
    stmt = (
        select(Staff)
        .join(OfficeStaff, Staff.id == OfficeStaff.staff_id)
        .where(OfficeStaff.office_id == office_id)
    )

    if exclude_deleted:
        stmt = stmt.where(Staff.is_deleted == False)

    result = await db.execute(stmt)
    return result.scalars().all()
```

この場合、以下のインデックスが活用されます:
- `idx_staff_is_deleted` (staffsテーブル)
- `office_staffs`テーブルの既存インデックス（`office_id`, `staff_id`）

## 修正手順

### ステップ1: マイグレーションファイルの修正

`migration_staff_deletion_upgrade.sql` の18行目を削除またはコメントアウト:

```sql
-- 3. staffsテーブルのインデックス追加
CREATE INDEX idx_staff_is_deleted ON staffs(is_deleted);
-- CREATE INDEX idx_staff_office_id_is_deleted ON staffs(office_id, is_deleted);  -- 削除: office_idカラムは存在しない
```

### ステップ2: マイグレーションの再実行

既にエラーが発生している場合、以下の手順でリカバリ:

```bash
# 1. データベースに接続
docker exec -it keikakun_app-db-1 psql -U your_user -d your_database

# 2. 既に作成されたインデックスとカラムを確認
\d staffs

# 3. is_deleted関連のカラムとインデックスが既に存在する場合は、そのまま
# 存在しない場合は、修正後のマイグレーションを実行
```

または、修正したマイグレーションファイルを使用:

```bash
# 修正後のSQLファイルを実行
docker exec -i keikakun_app-db-1 psql -U your_user -d your_database < migration_staff_deletion_upgrade_fixed.sql
```

### ステップ3: downgrade処理の修正

downgrade処理（69行目）も同様に修正:

```sql
-- -- 3. staffsテーブルのインデックス削除
-- DROP INDEX IF EXISTS idx_staff_is_deleted;
-- -- DROP INDEX IF EXISTS idx_staff_office_id_is_deleted;  -- 削除: このインデックスは作成されていない
```

## 影響範囲

### 既に実行された処理

マイグレーションが18行目でエラーになった場合、以下の処理は完了している可能性があります:

- ✅ 1-16行目: `is_deleted`, `deleted_at`, `deleted_by`カラムの追加
- ✅ 17行目: `idx_staff_is_deleted`インデックスの作成
- ❌ 18行目: エラー発生（インデックス作成失敗）
- ❓ 20行目以降: 未実行の可能性

### 確認が必要な項目

```sql
-- データベース内の現在の状態を確認
SELECT column_name, data_type, is_nullable, column_default
FROM information_schema.columns
WHERE table_name = 'staffs'
AND column_name IN ('is_deleted', 'deleted_at', 'deleted_by');

-- インデックスの確認
SELECT indexname, indexdef
FROM pg_indexes
WHERE tablename = 'staffs'
AND indexname LIKE '%deleted%';

-- staff_audit_logsテーブルの確認
SELECT table_name
FROM information_schema.tables
WHERE table_name = 'staff_audit_logs';
```

## 再発防止策

### 1. モデル構造の事前確認

マイグレーションスクリプト作成前に、以下を確認:

- [ ] 対象テーブルのカラム構造
- [ ] リレーションシップの種類（1対多、多対多）
- [ ] 中間テーブルの有無

### 2. マイグレーションのテスト

開発環境で以下を実施:

```bash
# 1. マイグレーション実行
docker exec -i keikakun_app-db-1 psql -U user -d db < migration.sql

# 2. エラーがないか確認
echo $?  # 0 = 成功、非0 = エラー

# 3. 作成されたオブジェクトを確認
docker exec keikakun_app-db-1 psql -U user -d db -c "\d+ staffs"
```

### 3. モデル定義との整合性確認

- [ ] SQLAlchemyモデルの定義を確認
- [ ] `mapped_column`で定義されているカラムのみがテーブルに存在
- [ ] リレーションシップは別テーブル経由で管理

## まとめ

- **原因**: staffsテーブルに存在しない`office_id`カラムへのインデックス作成を試みた
- **解決**: マイグレーションSQL 18行目を削除
- **教訓**: マイグレーション作成前にモデル構造を確認する

## 修正版マイグレーションファイル

`migration_staff_deletion_upgrade_fixed.sql` として保存:

```sql
-- スタッフ削除機能のためのスキーマ追加（upgrade）修正版
-- Revision ID: b2c3d4e5f6g7_fixed
-- Revises: a7b8c9d0e1f2
-- Create Date: 2025-11-24 14:30:00.000000

-- 1. staffsテーブルに論理削除カラムを追加
ALTER TABLE staffs ADD COLUMN IF NOT EXISTS is_deleted BOOLEAN NOT NULL DEFAULT false;
ALTER TABLE staffs ADD COLUMN IF NOT EXISTS deleted_at TIMESTAMP WITH TIME ZONE;
ALTER TABLE staffs ADD COLUMN IF NOT EXISTS deleted_by UUID;

-- 2. deleted_byの外部キー制約を追加
ALTER TABLE staffs
ADD CONSTRAINT IF NOT EXISTS fk_staffs_deleted_by_staffs
FOREIGN KEY (deleted_by) REFERENCES staffs(id);

-- 3. staffsテーブルのインデックス追加
CREATE INDEX IF NOT EXISTS idx_staff_is_deleted ON staffs(is_deleted);
-- office_idカラムは存在しないため、このインデックスは削除

-- 4. staff_audit_logsテーブル作成
CREATE TABLE IF NOT EXISTS staff_audit_logs (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    staff_id UUID NOT NULL,
    action VARCHAR(50) NOT NULL,
    performed_by UUID NOT NULL,
    ip_address VARCHAR(45),
    user_agent TEXT,
    details JSONB,
    created_at TIMESTAMP WITH TIME ZONE NOT NULL DEFAULT now(),
    CONSTRAINT fk_staff_audit_logs_staff_id_staffs
        FOREIGN KEY (staff_id) REFERENCES staffs(id) ON DELETE CASCADE,
    CONSTRAINT fk_staff_audit_logs_performed_by_staffs
        FOREIGN KEY (performed_by) REFERENCES staffs(id) ON DELETE SET NULL
);

-- 5. staff_audit_logsテーブルのインデックス追加
CREATE INDEX IF NOT EXISTS ix_staff_audit_logs_staff_id ON staff_audit_logs(staff_id);
CREATE INDEX IF NOT EXISTS ix_staff_audit_logs_action ON staff_audit_logs(action);
CREATE INDEX IF NOT EXISTS ix_staff_audit_logs_performed_by ON staff_audit_logs(performed_by);
CREATE INDEX IF NOT EXISTS ix_staff_audit_logs_created_at ON staff_audit_logs(created_at);

-- 完了
COMMENT ON TABLE staff_audit_logs IS 'スタッフ操作の監査ログ（削除、作成、更新等）';
COMMENT ON COLUMN staff_audit_logs.staff_id IS '対象スタッフID';
COMMENT ON COLUMN staff_audit_logs.action IS '操作種別（deleted, created, updated等）';
COMMENT ON COLUMN staff_audit_logs.performed_by IS '操作実行者のスタッフID';
COMMENT ON COLUMN staff_audit_logs.ip_address IS '操作元のIPアドレス';
COMMENT ON COLUMN staff_audit_logs.user_agent IS '操作元のUser-Agent';
COMMENT ON COLUMN staff_audit_logs.details IS '操作の詳細情報（JSON形式）';
COMMENT ON COLUMN staff_audit_logs.created_at IS '記録日時（UTC）';

COMMENT ON COLUMN staffs.is_deleted IS '論理削除フラグ';
COMMENT ON COLUMN staffs.deleted_at IS '削除日時（UTC）';
COMMENT ON COLUMN staffs.deleted_by IS '削除を実行したスタッフのID';
```
