# スタッフアーカイブ機能 要件定義書

## 📋 目次
1. [背景・目的](#背景目的)
2. [法的要件](#法的要件)
3. [データモデル設計](#データモデル設計)
4. [アーカイブ処理フロー](#アーカイブ処理フロー)
5. [実装詳細](#実装詳細)
6. [データ保持期間](#データ保持期間)
7. [セキュリティ考慮事項](#セキュリティ考慮事項)
8. [テスト要件](#テスト要件)

---

## 背景・目的

### 現状の課題

現在の実装では、スタッフ削除時に以下の処理が行われる：
1. 論理削除（is_deleted=true, deleted_at設定）
2. 30日経過後に物理削除（cleanup_service）

**問題点**：
- 物理削除により、法定保存義務のあるデータも削除される
- 労働基準法、障害者総合支援法の要件を満たせない
- 監査や法的紛争時に必要なデータが失われる

### 目的

法令遵守のため、以下を実現する：
1. **個人識別情報の即時匿名化**（GDPR・個人情報保護法対応）
2. **法定保存義務データのアーカイブ**（労働基準法・障害者総合支援法対応）
3. **二段階削除プロセスの実装**（匿名化 → アーカイブ → 期限後削除）

---

## 法的要件

### 1. 労働基準法（第109条）

**保存義務**：
- **労働者名簿**：退職・解雇から**5年間**（経過措置で3年も可）
- **賃金台帳**：最後の記入から**5年間**（経過措置で3年も可）

**対象データ**：
- 氏名（姓・名、フリガナ）
- 雇入れ日（created_at）
- 退職日（deleted_at）
- 役職・職種（role）
- 所属事務所情報

**参考**：
- [厚生労働省：賃金台帳等の保管期間](https://www.startup-roudou.mhlw.go.jp/qa/zigyonushi/syuugyoukisoku/q6.html)
- [労働基準法 第109条](https://laws.e-gov.go.jp/document?lawid=322AC0000000049)

### 2. 障害者総合支援法

**保存義務**：
- **サービス提供記録**：提供日から**5年間**
- **個別支援計画**：作成日から**5年間**

**対象データ**：
- サービス提供者（スタッフ）の情報
- 担当利用者の記録との紐付け

**参考**：
- [障害福祉事業の書類の保管期間](https://fukusi.kabudata-dll.com/hokankikan/)

### 3. 個人情報保護法（第22条）

**削除義務**：
- 利用目的達成後は「遅滞なく消去するよう努める」（**努力義務**）
- 本人からの削除要求には原則対応が必要

**対応方針**：
- 個人識別情報（メールアドレス、パスワード等）は即座に匿名化
- 法定保存義務のあるデータのみアーカイブ保持

**参考**：
- [個人情報保護委員会：取得した個人情報は、いつ廃棄しなければなりませんか](https://www.ppc.go.jp/all_faq_index/faq1-q5-2/)

---

## データモデル設計

### archived_staffs テーブル

法定保存義務のあるデータのみを匿名化した形で保存する。

#### スキーマ

| カラム名 | データ型 | 制約 | 説明 |
|---------|---------|------|------|
| id | UUID | PRIMARY KEY | アーカイブID |
| original_staff_id | UUID | NOT NULL, INDEX | 元のスタッフID（参照整合性なし） |
| anonymized_full_name | VARCHAR(255) | NOT NULL | 匿名化された氏名（例: "スタッフ-ABC123"） |
| anonymized_email | VARCHAR(255) | NOT NULL | 匿名化されたメール（例: "archived-ABC123@deleted.local"） |
| role | VARCHAR(20) | NOT NULL | 役職（owner/manager/employee） |
| office_id | UUID | NULLABLE, INDEX | 所属していた事務所ID |
| office_name | VARCHAR(255) | NULLABLE | 事務所名（スナップショット） |
| hired_at | TIMESTAMP | NOT NULL | 雇入れ日（created_at） |
| terminated_at | TIMESTAMP | NOT NULL | 退職日（deleted_at） |
| archived_at | TIMESTAMP | NOT NULL | アーカイブ作成日時 |
| archive_reason | VARCHAR(50) | NOT NULL | アーカイブ理由（staff_deletion/office_withdrawal） |
| legal_retention_until | TIMESTAMP | NOT NULL | 法定保存期限（terminated_at + 5年） |
| metadata | JSONB | NULLABLE | その他の法定保存が必要なメタデータ |
| is_test_data | BOOLEAN | NOT NULL, INDEX | テストデータフラグ |
| created_at | TIMESTAMP | NOT NULL | レコード作成日時 |

#### インデックス

```sql
CREATE INDEX idx_archived_staffs_original_id ON archived_staffs(original_staff_id);
CREATE INDEX idx_archived_staffs_office_id ON archived_staffs(office_id);
CREATE INDEX idx_archived_staffs_retention_until ON archived_staffs(legal_retention_until);
CREATE INDEX idx_archived_staffs_is_test_data ON archived_staffs(is_test_data);
CREATE INDEX idx_archived_staffs_archived_at ON archived_staffs(archived_at);
```

#### 外部キー

**重要**：`original_staff_id`と`office_id`には外部キー制約を**設定しない**

理由：
- 元のstaffsレコードは物理削除される
- officesも退会時に削除される可能性がある
- アーカイブは独立したデータとして保持

---

## アーカイブ処理フロー

### 全体フロー

```
┌─────────────────────┐
│  スタッフ削除要求   │
│  (DELETE /staffs/ID) │
└──────────┬──────────┘
           │
           ▼
┌─────────────────────────┐
│ 1. バリデーション        │
│   - 権限チェック         │
│   - 最後のOwnerチェック  │
└──────────┬──────────────┘
           │
           ▼
┌─────────────────────────┐
│ 2. アーカイブ作成        │
│   - 法定保存データ抽出   │
│   - 個人情報匿名化       │
│   - archived_staffsに保存│
└──────────┬──────────────┘
           │
           ▼
┌─────────────────────────┐
│ 3. 論理削除              │
│   - is_deleted = true    │
│   - deleted_at = now()   │
└──────────┬──────────────┘
           │
           ▼
┌─────────────────────────┐
│ 4. 監査ログ記録          │
│   - staff.deleted        │
│   - archive_created      │
└──────────┬──────────────┘
           │
           ▼
┌─────────────────────────┐
│ 5. 通知送信              │
│   - 事務所内スタッフへ   │
└──────────┬──────────────┘
           │
           ▼
┌─────────────────────────┐
│ 30日後: 物理削除         │
│   - cleanup_service      │
│   - staffsレコード削除   │
└─────────────────────────┘
           │
           ▼
┌─────────────────────────┐
│ 5年後: アーカイブ削除    │
│   - cleanup_service      │
│   - archived_staffs削除  │
└─────────────────────────┘
```

### トリガーとなるエンドポイント

#### 1. スタッフ削除（Owner権限）

**エンドポイント**：
```
DELETE /api/v1/staffs/{staff_id}
```

**処理内容**：
```python
# app/api/v1/endpoints/staffs.py:delete_staff
async def delete_staff(
    staff_id: UUID,
    current_user: Staff = Depends(deps.require_owner)
):
    # 1. バリデーション
    # 2. アーカイブ作成 ← NEW
    await crud.archived_staff.create_from_staff(
        db=db,
        staff=target_staff,
        reason="staff_deletion",
        deleted_by=current_user.id
    )

    # 3. 論理削除
    await crud.staff.soft_delete(db, staff_id=staff_id, deleted_by=current_user.id)

    # 4. 監査ログ・通知
```

#### 2. スタッフ退会（Withdrawal承認時）

**エンドポイント**：
```
POST /api/v1/withdrawal-requests/{request_id}/approve
```

**処理内容**：
```python
# app/services/withdrawal_service.py:_execute_staff_withdrawal
async def _execute_staff_withdrawal(
    request: ApprovalRequest,
    executor_id: UUID
):
    # 1. アーカイブ作成 ← NEW
    await crud.archived_staff.create_from_staff(
        db=db,
        staff=target_staff,
        reason="staff_withdrawal",
        deleted_by=executor_id
    )

    # 2. 論理削除
    await crud_staff.soft_delete(db, staff_id=target_staff_id, deleted_by=executor_id)

    # 3. 監査ログ
```

#### 3. 事務所退会（全スタッフ削除）

**エンドポイント**：
```
POST /api/v1/withdrawal-requests/{request_id}/approve
```

**処理内容**：
```python
# app/services/withdrawal_service.py:_execute_office_withdrawal
async def _execute_office_withdrawal(
    request: ApprovalRequest,
    executor_id: UUID
):
    # 所属スタッフ全員を取得
    office_staffs = await crud_staff.get_by_office_id(db, office_id=office_id)

    for staff in office_staffs:
        # 1. アーカイブ作成 ← NEW
        await crud.archived_staff.create_from_staff(
            db=db,
            staff=staff,
            reason="office_withdrawal",
            deleted_by=executor_id
        )

        # 2. 論理削除
        await crud_staff.soft_delete(db, staff_id=staff.id, deleted_by=executor_id)

    # 3. 事務所削除
    await crud_office.soft_delete(db, office_id=office_id)
```

---

## 実装詳細

### 1. SQLAlchemy モデル

**ファイル**: `app/models/archived_staff.py`

```python
import uuid
from datetime import datetime, timedelta, timezone
from typing import Optional
from sqlalchemy import String, DateTime, UUID, Boolean, func, Index
from sqlalchemy.dialects.postgresql import JSONB
from sqlalchemy.orm import Mapped, mapped_column

from app.db.base import Base


class ArchivedStaff(Base):
    """
    法定保存義務に基づくスタッフアーカイブ

    労働基準法、障害者総合支援法の要件を満たすため、
    退職・削除されたスタッフの法定保存データを5年間保持する。

    個人識別情報は匿名化され、法定保存が必要な情報のみを含む。
    """
    __tablename__ = 'archived_staffs'

    id: Mapped[uuid.UUID] = mapped_column(
        UUID(as_uuid=True),
        primary_key=True,
        server_default=func.gen_random_uuid()
    )
    original_staff_id: Mapped[uuid.UUID] = mapped_column(
        UUID(as_uuid=True),
        nullable=False,
        index=True,
        comment="元のスタッフID（参照整合性なし）"
    )
    anonymized_full_name: Mapped[str] = mapped_column(
        String(255),
        nullable=False,
        comment="匿名化された氏名（例: スタッフ-ABC123）"
    )
    anonymized_email: Mapped[str] = mapped_column(
        String(255),
        nullable=False,
        comment="匿名化されたメール（例: archived-ABC123@deleted.local）"
    )
    role: Mapped[str] = mapped_column(
        String(20),
        nullable=False,
        comment="役職（owner/manager/employee）"
    )
    office_id: Mapped[Optional[uuid.UUID]] = mapped_column(
        UUID(as_uuid=True),
        nullable=True,
        index=True,
        comment="所属していた事務所ID（参照整合性なし）"
    )
    office_name: Mapped[Optional[str]] = mapped_column(
        String(255),
        nullable=True,
        comment="事務所名（スナップショット）"
    )
    hired_at: Mapped[datetime] = mapped_column(
        DateTime(timezone=True),
        nullable=False,
        comment="雇入れ日（元のcreated_at）"
    )
    terminated_at: Mapped[datetime] = mapped_column(
        DateTime(timezone=True),
        nullable=False,
        index=True,
        comment="退職日（deleted_at）"
    )
    archived_at: Mapped[datetime] = mapped_column(
        DateTime(timezone=True),
        nullable=False,
        server_default=func.now(),
        index=True,
        comment="アーカイブ作成日時"
    )
    archive_reason: Mapped[str] = mapped_column(
        String(50),
        nullable=False,
        comment="アーカイブ理由（staff_deletion/staff_withdrawal/office_withdrawal）"
    )
    legal_retention_until: Mapped[datetime] = mapped_column(
        DateTime(timezone=True),
        nullable=False,
        index=True,
        comment="法定保存期限（terminated_at + 5年）"
    )
    metadata: Mapped[Optional[dict]] = mapped_column(
        JSONB,
        nullable=True,
        comment="その他の法定保存が必要なメタデータ"
    )
    is_test_data: Mapped[bool] = mapped_column(
        Boolean,
        default=False,
        nullable=False,
        index=True,
        comment="テストデータフラグ"
    )
    created_at: Mapped[datetime] = mapped_column(
        DateTime(timezone=True),
        nullable=False,
        server_default=func.now()
    )

    __table_args__ = (
        Index('idx_archived_staffs_retention_until', 'legal_retention_until'),
        Index('idx_archived_staffs_office_id', 'office_id'),
    )

    @classmethod
    def calculate_retention_until(cls, terminated_at: datetime, years: int = 5) -> datetime:
        """
        法定保存期限を計算（退職日 + 5年）

        Args:
            terminated_at: 退職日
            years: 保存年数（デフォルト5年）

        Returns:
            保存期限日時
        """
        return terminated_at + timedelta(days=365 * years)

    def is_retention_expired(self) -> bool:
        """
        法定保存期限が過ぎているかチェック

        Returns:
            期限切れの場合True
        """
        return datetime.now(timezone.utc) >= self.legal_retention_until
```

### 2. Alembic マイグレーション

**ファイル名**: `migrations/versions/xxxx_create_archived_staffs_table.py`

```python
"""create archived_staffs table

Revision ID: xxxx
Revises: yyyy
Create Date: 2025-12-01 12:00:00.000000

"""
from alembic import op
import sqlalchemy as sa
from sqlalchemy.dialects import postgresql

# revision identifiers
revision = 'xxxx'
down_revision = 'yyyy'
branch_labels = None
depends_on = None


def upgrade() -> None:
    """アーカイブテーブルを作成"""

    op.create_table(
        'archived_staffs',
        sa.Column('id', postgresql.UUID(as_uuid=True), server_default=sa.text('gen_random_uuid()'), nullable=False),
        sa.Column('original_staff_id', postgresql.UUID(as_uuid=True), nullable=False),
        sa.Column('anonymized_full_name', sa.String(length=255), nullable=False),
        sa.Column('anonymized_email', sa.String(length=255), nullable=False),
        sa.Column('role', sa.String(length=20), nullable=False),
        sa.Column('office_id', postgresql.UUID(as_uuid=True), nullable=True),
        sa.Column('office_name', sa.String(length=255), nullable=True),
        sa.Column('hired_at', sa.DateTime(timezone=True), nullable=False),
        sa.Column('terminated_at', sa.DateTime(timezone=True), nullable=False),
        sa.Column('archived_at', sa.DateTime(timezone=True), server_default=sa.text('now()'), nullable=False),
        sa.Column('archive_reason', sa.String(length=50), nullable=False),
        sa.Column('legal_retention_until', sa.DateTime(timezone=True), nullable=False),
        sa.Column('metadata', postgresql.JSONB(astext_type=sa.Text()), nullable=True),
        sa.Column('is_test_data', sa.Boolean(), server_default='false', nullable=False),
        sa.Column('created_at', sa.DateTime(timezone=True), server_default=sa.text('now()'), nullable=False),
        sa.PrimaryKeyConstraint('id')
    )

    # インデックスを作成
    op.create_index('idx_archived_staffs_original_id', 'archived_staffs', ['original_staff_id'])
    op.create_index('idx_archived_staffs_office_id', 'archived_staffs', ['office_id'])
    op.create_index('idx_archived_staffs_retention_until', 'archived_staffs', ['legal_retention_until'])
    op.create_index('idx_archived_staffs_is_test_data', 'archived_staffs', ['is_test_data'])
    op.create_index('idx_archived_staffs_archived_at', 'archived_staffs', ['archived_at'])

    # テーブルコメント
    op.execute("""
        COMMENT ON TABLE archived_staffs IS
        '法定保存義務に基づくスタッフアーカイブ（労働基準法・障害者総合支援法対応）'
    """)


def downgrade() -> None:
    """ロールバック"""

    op.drop_index('idx_archived_staffs_archived_at', table_name='archived_staffs')
    op.drop_index('idx_archived_staffs_is_test_data', table_name='archived_staffs')
    op.drop_index('idx_archived_staffs_retention_until', table_name='archived_staffs')
    op.drop_index('idx_archived_staffs_office_id', table_name='archived_staffs')
    op.drop_index('idx_archived_staffs_original_id', table_name='archived_staffs')
    op.drop_table('archived_staffs')
```

### 3. CRUD操作

**ファイル**: `app/crud/crud_archived_staff.py`

```python
import uuid
import hashlib
from datetime import datetime, timezone
from typing import Optional, List
from sqlalchemy.ext.asyncio import AsyncSession
from sqlalchemy import select, and_

from app.models.archived_staff import ArchivedStaff
from app.models.staff import Staff
from app.models.office import Office


class CRUDArchivedStaff:
    """アーカイブスタッフのCRUD操作"""

    def _generate_anonymized_id(self, staff_id: uuid.UUID) -> str:
        """
        スタッフIDから匿名化IDを生成

        Args:
            staff_id: 元のスタッフID

        Returns:
            匿名化ID（例: ABC123DEF）
        """
        # SHA-256ハッシュの先頭9文字を使用
        hash_hex = hashlib.sha256(str(staff_id).encode()).hexdigest()
        return hash_hex[:9].upper()

    async def create_from_staff(
        self,
        db: AsyncSession,
        *,
        staff: Staff,
        reason: str,
        deleted_by: uuid.UUID
    ) -> ArchivedStaff:
        """
        Staffレコードからアーカイブを作成

        個人識別情報を匿名化し、法定保存が必要なデータのみを保存する。

        Args:
            db: データベースセッション
            staff: アーカイブ対象のスタッフ
            reason: アーカイブ理由（staff_deletion/staff_withdrawal/office_withdrawal）
            deleted_by: 削除実行者のスタッフID

        Returns:
            作成されたアーカイブレコード
        """
        # 匿名化ID生成
        anon_id = self._generate_anonymized_id(staff.id)

        # 事務所情報取得（スナップショット）
        office_id = None
        office_name = None
        if staff.office_associations:
            # プライマリ事務所を優先
            primary_assoc = next(
                (assoc for assoc in staff.office_associations if assoc.is_primary),
                None
            )
            if primary_assoc and primary_assoc.office:
                office_id = primary_assoc.office.id
                office_name = primary_assoc.office.name
            elif staff.office_associations:
                # プライマリがなければ最初の事務所
                first_assoc = staff.office_associations[0]
                if first_assoc.office:
                    office_id = first_assoc.office.id
                    office_name = first_assoc.office.name

        # 退職日（deleted_atまたは現在日時）
        terminated_at = staff.deleted_at or datetime.now(timezone.utc)

        # 法定保存期限を計算（退職日 + 5年）
        retention_until = ArchivedStaff.calculate_retention_until(terminated_at, years=5)

        # メタデータ
        metadata = {
            "deleted_by_staff_id": str(deleted_by),
            "original_email_domain": staff.email.split("@")[1] if "@" in staff.email else None,
            "mfa_was_enabled": staff.is_mfa_enabled,
            "is_email_verified": staff.is_email_verified,
        }

        # アーカイブレコード作成
        archived_staff = ArchivedStaff(
            original_staff_id=staff.id,
            anonymized_full_name=f"スタッフ-{anon_id}",
            anonymized_email=f"archived-{anon_id}@deleted.local",
            role=staff.role.value,
            office_id=office_id,
            office_name=office_name,
            hired_at=staff.created_at,
            terminated_at=terminated_at,
            archive_reason=reason,
            legal_retention_until=retention_until,
            metadata=metadata,
            is_test_data=staff.is_test_data if hasattr(staff, 'is_test_data') else False
        )

        db.add(archived_staff)
        await db.flush()
        await db.refresh(archived_staff)

        return archived_staff

    async def get_by_original_staff_id(
        self,
        db: AsyncSession,
        *,
        staff_id: uuid.UUID
    ) -> Optional[ArchivedStaff]:
        """
        元のスタッフIDでアーカイブを取得

        Args:
            db: データベースセッション
            staff_id: 元のスタッフID

        Returns:
            アーカイブレコード、または None
        """
        stmt = select(ArchivedStaff).where(
            ArchivedStaff.original_staff_id == staff_id
        )
        result = await db.execute(stmt)
        return result.scalar_one_or_none()

    async def get_expired_archives(
        self,
        db: AsyncSession,
        *,
        exclude_test_data: bool = True
    ) -> List[ArchivedStaff]:
        """
        法定保存期限が過ぎたアーカイブを取得

        Args:
            db: データベースセッション
            exclude_test_data: テストデータを除外するか

        Returns:
            期限切れのアーカイブリスト
        """
        now = datetime.now(timezone.utc)

        stmt = select(ArchivedStaff).where(
            ArchivedStaff.legal_retention_until <= now
        )

        if exclude_test_data:
            stmt = stmt.where(ArchivedStaff.is_test_data == False)

        result = await db.execute(stmt)
        return list(result.scalars().all())

    async def delete_expired_archives(
        self,
        db: AsyncSession,
        *,
        exclude_test_data: bool = True
    ) -> int:
        """
        法定保存期限が過ぎたアーカイブを削除

        Args:
            db: データベースセッション
            exclude_test_data: テストデータを除外するか

        Returns:
            削除されたレコード数
        """
        expired_archives = await self.get_expired_archives(
            db,
            exclude_test_data=exclude_test_data
        )

        count = 0
        for archive in expired_archives:
            await db.delete(archive)
            count += 1

        return count


archived_staff = CRUDArchivedStaff()
```

### 4. cleanup_service への統合

**ファイル**: `app/services/cleanup_service.py`

```python
# 既存のcleanup_serviceに以下を追加

async def cleanup_expired_archives(
    self,
    db: AsyncSession
) -> Dict[str, Any]:
    """
    法定保存期限が過ぎたアーカイブを削除

    Args:
        db: データベースセッション

    Returns:
        削除結果のサマリー
    """
    from app.crud.crud_archived_staff import archived_staff

    result = {
        "deleted_archive_count": 0,
        "errors": []
    }

    try:
        # 期限切れアーカイブを削除
        count = await archived_staff.delete_expired_archives(
            db,
            exclude_test_data=True
        )
        result["deleted_archive_count"] = count

        await db.commit()

        logger.info(f"Expired archives cleanup completed: {count} archives deleted")

    except Exception as e:
        await db.rollback()
        error_msg = f"Archive cleanup failed: {str(e)}"
        logger.error(error_msg)
        result["errors"].append(error_msg)
        raise

    return result
```

---

## データ保持期間

### タイムライン

```
┌────────────┬───────────────┬──────────────┬──────────────┐
│ Day 0      │ Day 30        │ Year 5       │ Year 5+      │
├────────────┼───────────────┼──────────────┼──────────────┤
│ スタッフ削除│ 物理削除      │ アーカイブ   │ 完全削除     │
│            │               │ 保持期限     │              │
├────────────┼───────────────┼──────────────┼──────────────┤
│ ✓ Archive  │ ✓ staffs削除  │ ✓ 5年経過    │ ✓ archive削除│
│   作成     │               │              │              │
│ ✓ 論理削除  │               │              │              │
│   (staffs) │               │              │              │
└────────────┴───────────────┴──────────────┴──────────────┘
```

### 各段階の詳細

1. **Day 0（削除実行時）**
   - アーカイブレコード作成
   - 個人情報匿名化
   - staffsレコードを論理削除

2. **Day 30（物理削除）**
   - cleanup_serviceがstaffsレコードを物理削除
   - アーカイブは保持

3. **Year 5（法定保存期限）**
   - terminated_at + 5年が経過
   - `legal_retention_until`に到達

4. **Year 5+（完全削除）**
   - cleanup_serviceがアーカイブを削除
   - すべてのデータが完全に削除される

---

## セキュリティ考慮事項

### 1. 匿名化の徹底

**匿名化対象**：
- 氏名 → `スタッフ-ABC123DEF`（SHA-256ハッシュの先頭9文字）
- メールアドレス → `archived-ABC123DEF@deleted.local`

**匿名化しないデータ**：
- 役職（role）
- 雇入れ日（hired_at）
- 退職日（terminated_at）
- 所属事務所ID・名（スナップショット）

### 2. アクセス制御

**アーカイブデータへのアクセス**：
- app_admin のみが閲覧可能
- 通常のスタッフは閲覧不可
- API エンドポイントは`require_app_admin`で保護

**APIエンドポイント例**：
```python
# app/api/v1/endpoints/archived_staffs.py

@router.get("/", dependencies=[Depends(deps.require_app_admin)])
async def list_archived_staffs(
    db: AsyncSession = Depends(deps.get_db),
    skip: int = 0,
    limit: int = 100
):
    """アーカイブリスト取得（app_adminのみ）"""
    # ...
```

### 3. 監査ログ

**記録すべきイベント**：
- アーカイブ作成（`archive.created`）
- アーカイブ閲覧（`archive.accessed`）
- アーカイブ削除（`archive.deleted`）

```python
# アーカイブ作成時
await crud.audit_log.create_log(
    db=db,
    actor_id=deleted_by,
    action="archive.created",
    target_type="archived_staff",
    target_id=archived_staff.id,
    details={
        "original_staff_id": str(staff.id),
        "archive_reason": reason,
        "retention_until": retention_until.isoformat()
    }
)
```

### 4. データ暗号化

**考慮事項**：
- アーカイブテーブルは暗号化されたデータベースに保存
- バックアップも暗号化
- metadataフィールド（JSONB）には機密情報を含めない

---

## テスト要件

### 1. ユニットテスト

**ファイル**: `tests/crud/test_crud_archived_staff.py`

```python
import pytest
from datetime import datetime, timedelta, timezone

class TestCRUDArchivedStaff:
    """アーカイブCRUDのテスト"""

    async def test_create_from_staff(self, db, test_staff):
        """Staffからアーカイブ作成"""
        # ...

    async def test_anonymization(self, db, test_staff):
        """匿名化の確認"""
        # 氏名・メールが匿名化されているか
        # ...

    async def test_retention_calculation(self):
        """保存期限計算の確認"""
        # terminated_at + 5年が正しいか
        # ...

    async def test_get_expired_archives(self, db):
        """期限切れアーカイブ取得"""
        # ...

    async def test_delete_expired_archives(self, db):
        """期限切れアーカイブ削除"""
        # ...
```

### 2. 統合テスト

**ファイル**: `tests/integration/test_staff_deletion_with_archive.py`

```python
class TestStaffDeletionWithArchive:
    """スタッフ削除とアーカイブの統合テスト"""

    async def test_delete_staff_creates_archive(self, client, db, owner_token):
        """スタッフ削除時にアーカイブが作成される"""
        # DELETE /staffs/{id} を実行
        # archived_staffsにレコードが作成されるか確認
        # ...

    async def test_archive_data_anonymized(self, client, db, owner_token):
        """アーカイブデータが匿名化されている"""
        # 氏名・メールが匿名化されているか
        # ...

    async def test_archive_retention_period(self, db):
        """アーカイブ保存期間が正しい"""
        # legal_retention_until が terminated_at + 5年か
        # ...

    async def test_physical_deletion_keeps_archive(self, db):
        """物理削除後もアーカイブは保持される"""
        # cleanup_service実行後もarchived_staffsにレコードが残るか
        # ...
```

### 3. E2Eテスト

**ファイル**: `tests/e2e/test_archive_lifecycle.py`

```python
class TestArchiveLifecycle:
    """アーカイブのライフサイクルE2Eテスト"""

    async def test_full_lifecycle(self, db):
        """
        完全なライフサイクルのテスト：
        1. スタッフ削除 → アーカイブ作成
        2. 30日後 → 物理削除（アーカイブ保持）
        3. 5年後 → アーカイブ削除
        """
        # ...
```

---

## 付録

### A. プライバシーポリシーへの追記

```markdown
## 第X条（個人情報の保持期間）

1. 個人情報は、利用目的の達成に必要な期間保持します。

2. **スタッフアカウント削除後の保持期間**
   - 論理削除から**30日間**：誤削除からの復旧が可能な猶予期間
   - 30日経過後：個人識別情報（メールアドレス、パスワード等）を完全に削除（物理削除）
   - **法定保存義務のあるデータ**：以下の期間、匿名化した上で保持
     - 労働者名簿情報：退職後**5年間**（労働基準法第109条）
     - 雇用関連記録：退職後**5年間**
     - サービス提供記録：提供日から**5年間**（障害者総合支援法）

3. 法定保存データの取扱い
   - 個人を特定できる情報（氏名、メールアドレス等）は匿名化
   - 法令で定められた保存期間経過後、速やかに削除
   - アクセスは管理者のみに制限

4. ユーザーの権利
   - 個人情報の開示、訂正、削除を請求できます
   - ただし、法令に基づく保存義務があるデータは削除できません
```

### B. 実装チェックリスト

- [x] モデル作成（`app/models/archived_staff.py`）
- [x] マイグレーション作成・実行
- [x] CRUD作成（`app/crud/crud_archived_staff.py`）
  - [x] create_from_staff - アーカイブ作成
  - [x] get - ID取得
  - [x] get_by_original_staff_id - 元スタッフIDで取得
  - [x] get_multi - リスト取得（フィルタリング・ページネーション対応）
  - [x] get_expired_archives - 期限切れアーカイブ取得
  - [x] delete_expired_archives - 期限切れアーカイブ削除
- [x] スタッフ削除エンドポイントにアーカイブ作成処理を追加
- [x] Withdrawal サービスにアーカイブ作成処理を追加（staff_withdrawal, office_withdrawal）
- [x] cleanup_service にアーカイブ削除処理を追加（※既に実装済みを確認）
- [x] API エンドポイント作成（app_admin専用）
  - [x] GET /api/v1/admin/archived-staffs - リスト取得
  - [x] GET /api/v1/admin/archived-staffs/{id} - 詳細取得
  - [x] スキーマ定義作成（app/schemas/archived_staff.py）
  - [x] APIルーター登録（app/api/v1/api.py）
- [x] APIテスト作成（tests/api/v1/test_archived_staffs.py）
  - [x] リスト取得テスト（正常系）
  - [x] office_idフィルタリングテスト
  - [x] archive_reasonフィルタリングテスト
  - [x] ページネーションテスト
  - [x] 詳細取得テスト（正常系）
  - [x] 403 Forbiddenテスト（非app_admin）
  - [x] 404 Not Foundテスト
- [ ] ユニットテスト作成（CRUD層）
- [ ] 統合テスト作成（アーカイブ作成フロー全体）
- [ ] E2Eテスト作成
- [ ] プライバシーポリシー更新
- [ ] ドキュメント更新

---

**作成日**: 2025-12-01
**最終更新日**: 2025-12-01
**バージョン**: 1.0
