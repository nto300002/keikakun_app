<!--
作業ブランチ: <ここに現在作業中のブランチ名を記入してください>
注意: このファイルを編集する場合、必ず作業中のブランチ名を上部に記載し、変更はそのブランチへ push してください。
-->

# Phase 2: データベースフェーズ

パスワードリセット機能のデータベース設計とマイグレーション

---

## 1. データベース設計

### 1.1 テーブル定義

#### 1.1.1 password_reset_tokens テーブル

既存の `staffs` テーブルに関連する新しいテーブルを作成します。

```sql
-- SQLAlchemy ORM モデルに対応する生SQL
CREATE TABLE password_reset_tokens (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    staff_id UUID NOT NULL REFERENCES staffs(id) ON DELETE CASCADE,
    token_hash VARCHAR(64) NOT NULL UNIQUE, -- SHA-256ハッシュ（64文字の16進数）
    expires_at TIMESTAMP WITH TIME ZONE NOT NULL,
    used BOOLEAN NOT NULL DEFAULT FALSE,
    used_at TIMESTAMP WITH TIME ZONE,
    created_at TIMESTAMP WITH TIME ZONE NOT NULL DEFAULT NOW(),
    updated_at TIMESTAMP WITH TIME ZONE NOT NULL DEFAULT NOW()
);

-- パスワードリセット監査ログテーブル
CREATE TABLE password_reset_audit_logs (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    staff_id UUID REFERENCES staffs(id) ON DELETE SET NULL,
    action VARCHAR(50) NOT NULL, -- 'requested', 'token_verified', 'completed', 'failed'
    email VARCHAR(255),
    ip_address VARCHAR(45), -- IPv6対応
    user_agent TEXT,
    success BOOLEAN NOT NULL DEFAULT TRUE,
    error_message TEXT,
    created_at TIMESTAMP WITH TIME ZONE NOT NULL DEFAULT NOW()
);

-- インデックス（password_reset_tokens）
CREATE UNIQUE INDEX idx_password_reset_token_hash ON password_reset_tokens(token_hash);
CREATE INDEX idx_password_reset_composite ON password_reset_tokens(staff_id, used, expires_at);

-- インデックス（password_reset_audit_logs）
CREATE INDEX idx_audit_staff_id ON password_reset_audit_logs(staff_id);
CREATE INDEX idx_audit_created_at ON password_reset_audit_logs(created_at);
CREATE INDEX idx_audit_action ON password_reset_audit_logs(action);
```

#### 1.1.2 インデックス設計の理由

**password_reset_tokens**:
- `idx_password_reset_token_hash`: トークン検索の高速化（UNIQUE制約）
- `idx_password_reset_composite`: 有効なトークン検索の高速化（staff_id, used, expires_atの複合インデックス）

**password_reset_audit_logs**:
- `idx_audit_staff_id`: スタッフIDでの監査ログ検索
- `idx_audit_created_at`: 時系列でのログ検索
- `idx_audit_action`: アクションタイプでのフィルタリング

---

## 2. マイグレーション

### 2.1 Alembic マイグレーションファイル

ファイル名: `migrations/versions/xxxxx_add_password_reset_tokens.py`

```python
"""add password reset tokens table

Revision ID: xxxxx
Revises: <previous_revision>
Create Date: 2025-xx-xx

"""
from alembic import op
import sqlalchemy as sa
from sqlalchemy.dialects import postgresql

# revision identifiers, used by Alembic.
revision = 'xxxxx'
down_revision = '<previous_revision>'
branch_labels = None
depends_on = None


def upgrade() -> None:
    """パスワードリセットトークンテーブルを作成"""

    # password_reset_tokens テーブルを作成
    op.create_table(
        'password_reset_tokens',
        sa.Column('id', postgresql.UUID(as_uuid=True), server_default=sa.text('gen_random_uuid()'), nullable=False),
        sa.Column('staff_id', postgresql.UUID(as_uuid=True), nullable=False),
        sa.Column('token_hash', sa.String(length=64), nullable=False),  # SHA-256ハッシュ
        sa.Column('expires_at', sa.DateTime(timezone=True), nullable=False),
        sa.Column('used', sa.Boolean(), nullable=False, server_default=sa.text('false')),
        sa.Column('used_at', sa.DateTime(timezone=True), nullable=True),
        sa.Column('created_at', sa.DateTime(timezone=True), server_default=sa.text('now()'), nullable=False),
        sa.Column('updated_at', sa.DateTime(timezone=True), server_default=sa.text('now()'), nullable=False),
        sa.ForeignKeyConstraint(['staff_id'], ['staffs.id'], ondelete='CASCADE'),
        sa.PrimaryKeyConstraint('id')
    )

    # password_reset_audit_logs テーブルを作成
    op.create_table(
        'password_reset_audit_logs',
        sa.Column('id', postgresql.UUID(as_uuid=True), server_default=sa.text('gen_random_uuid()'), nullable=False),
        sa.Column('staff_id', postgresql.UUID(as_uuid=True), nullable=True),
        sa.Column('action', sa.String(length=50), nullable=False),
        sa.Column('email', sa.String(length=255), nullable=True),
        sa.Column('ip_address', sa.String(length=45), nullable=True),
        sa.Column('user_agent', sa.Text(), nullable=True),
        sa.Column('success', sa.Boolean(), nullable=False, server_default=sa.text('true')),
        sa.Column('error_message', sa.Text(), nullable=True),
        sa.Column('created_at', sa.DateTime(timezone=True), server_default=sa.text('now()'), nullable=False),
        sa.ForeignKeyConstraint(['staff_id'], ['staffs.id'], ondelete='SET NULL'),
        sa.PrimaryKeyConstraint('id')
    )

    # インデックスを作成（password_reset_tokens）
    op.create_index('idx_password_reset_token_hash', 'password_reset_tokens', ['token_hash'], unique=True)
    op.create_index('idx_password_reset_composite', 'password_reset_tokens', ['staff_id', 'used', 'expires_at'], unique=False)

    # インデックスを作成（password_reset_audit_logs）
    op.create_index('idx_audit_staff_id', 'password_reset_audit_logs', ['staff_id'], unique=False)
    op.create_index('idx_audit_created_at', 'password_reset_audit_logs', ['created_at'], unique=False)
    op.create_index('idx_audit_action', 'password_reset_audit_logs', ['action'], unique=False)


def downgrade() -> None:
    """ロールバック"""

    # インデックスを削除（password_reset_audit_logs）
    op.drop_index('idx_audit_action', table_name='password_reset_audit_logs')
    op.drop_index('idx_audit_created_at', table_name='password_reset_audit_logs')
    op.drop_index('idx_audit_staff_id', table_name='password_reset_audit_logs')

    # インデックスを削除（password_reset_tokens）
    op.drop_index('idx_password_reset_composite', table_name='password_reset_tokens')
    op.drop_index('idx_password_reset_token_hash', table_name='password_reset_tokens')

    # テーブルを削除
    op.drop_table('password_reset_audit_logs')
    op.drop_table('password_reset_tokens')
```

### 2.2 マイグレーション実行コマンド

```bash
# マイグレーションファイルを生成
alembic revision --autogenerate -m "add password reset tokens"

# マイグレーションを適用
alembic upgrade head

# ロールバック（必要な場合）
alembic downgrade -1
```

---

## 3. ORM モデル定義

### 3.1 PasswordResetToken モデル

`app/models/staff.py` に追加するモデル：

```python
import uuid
import datetime
from typing import Optional, List
from sqlalchemy import String, Boolean, DateTime, ForeignKey, Text, func
from sqlalchemy.orm import Mapped, mapped_column, relationship
from sqlalchemy.dialects.postgresql import UUID

from app.db.base_class import Base


class PasswordResetToken(Base):
    """パスワードリセットトークン（トークンはSHA-256でハッシュ化して保存）"""
    __tablename__ = 'password_reset_tokens'

    id: Mapped[uuid.UUID] = mapped_column(
        UUID(as_uuid=True),
        primary_key=True,
        server_default=func.gen_random_uuid()
    )
    staff_id: Mapped[uuid.UUID] = mapped_column(
        ForeignKey('staffs.id', ondelete="CASCADE"),
        nullable=False
    )
    token_hash: Mapped[str] = mapped_column(
        String(64),  # SHA-256ハッシュ（64文字の16進数）
        unique=True,
        index=True,
        nullable=False
    )
    expires_at: Mapped[datetime.datetime] = mapped_column(
        DateTime(timezone=True),
        nullable=False,
        index=True
    )
    used: Mapped[bool] = mapped_column(
        Boolean,
        default=False,
        nullable=False,
        index=True
    )
    used_at: Mapped[Optional[datetime.datetime]] = mapped_column(
        DateTime(timezone=True),
        nullable=True
    )
    created_at: Mapped[datetime.datetime] = mapped_column(
        DateTime(timezone=True),
        server_default=func.now()
    )
    updated_at: Mapped[datetime.datetime] = mapped_column(
        DateTime(timezone=True),
        server_default=func.now(),
        onupdate=func.now()
    )

    # リレーション
    staff: Mapped["Staff"] = relationship("Staff", back_populates="password_reset_tokens")
```

### 3.2 PasswordResetAuditLog モデル

`app/models/staff.py` に追加：

```python
class PasswordResetAuditLog(Base):
    """パスワードリセット監査ログ"""
    __tablename__ = 'password_reset_audit_logs'

    id: Mapped[uuid.UUID] = mapped_column(
        UUID(as_uuid=True),
        primary_key=True,
        server_default=func.gen_random_uuid()
    )
    staff_id: Mapped[Optional[uuid.UUID]] = mapped_column(
        ForeignKey('staffs.id', ondelete="SET NULL"),
        nullable=True,
        index=True
    )
    action: Mapped[str] = mapped_column(
        String(50),
        nullable=False,
        index=True
    )
    email: Mapped[Optional[str]] = mapped_column(
        String(255),
        nullable=True
    )
    ip_address: Mapped[Optional[str]] = mapped_column(
        String(45),  # IPv6対応
        nullable=True
    )
    user_agent: Mapped[Optional[str]] = mapped_column(
        Text,
        nullable=True
    )
    success: Mapped[bool] = mapped_column(
        Boolean,
        default=True,
        nullable=False
    )
    error_message: Mapped[Optional[str]] = mapped_column(
        Text,
        nullable=True
    )
    created_at: Mapped[datetime.datetime] = mapped_column(
        DateTime(timezone=True),
        server_default=func.now(),
        index=True
    )

    # リレーション
    staff: Mapped[Optional["Staff"]] = relationship("Staff", back_populates="password_reset_audit_logs")
```

### 3.3 Staff モデルへのリレーション追加

`Staff` モデルに以下のリレーションを追加：

```python
# app/models/staff.py の Staff クラスに追加

class Staff(Base):
    # ... 既存のフィールド ...

    # パスワードリセットトークンのリレーション
    password_reset_tokens: Mapped[List["PasswordResetToken"]] = relationship(
        "PasswordResetToken",
        back_populates="staff",
        cascade="all, delete-orphan"
    )

    # パスワードリセット監査ログのリレーション
    password_reset_audit_logs: Mapped[List["PasswordResetAuditLog"]] = relationship(
        "PasswordResetAuditLog",
        back_populates="staff"
    )
```

---

## 4. データベーススキーマ図

```
┌─────────────────────────────────┐
│        staffs                   │
├─────────────────────────────────┤
│ id (UUID, PK)                   │
│ email                           │
│ hashed_password                 │
│ password_changed_at             │
│ ...                             │
└─────────────────────────────────┘
         ↑                ↑
         │                │
         │ (1:N)          │ (1:N)
         │                │
┌────────┴─────────┐  ┌──┴──────────────────────────┐
│ password_reset_  │  │ password_reset_audit_logs   │
│ tokens           │  │                             │
├──────────────────┤  ├─────────────────────────────┤
│ id (UUID, PK)    │  │ id (UUID, PK)               │
│ staff_id (FK)    │  │ staff_id (FK, nullable)     │
│ token_hash       │  │ action                      │
│ expires_at       │  │ email                       │
│ used             │  │ ip_address                  │
│ used_at          │  │ user_agent                  │
│ created_at       │  │ success                     │
│ updated_at       │  │ error_message               │
└──────────────────┘  │ created_at                  │
                      └─────────────────────────────┘
```

---

## 5. セキュリティ考慮事項

### 5.1 トークンハッシュ化

**なぜSHA-256でハッシュ化するのか？**

1. **DB侵害時の安全性**: データベースが侵害されても、生のトークンは復元できない
2. **パスワードハッシュとの一貫性**: パスワードと同様に、トークンも平文で保存しない
3. **検索性能**: SHA-256ハッシュは固定長（64文字）なので、インデックス効率が良い

**実装例**:

```python
import hashlib

def hash_reset_token(token: str) -> str:
    """トークンをSHA-256でハッシュ化"""
    return hashlib.sha256(token.encode()).hexdigest()

# トークン生成
token = str(uuid.uuid4())  # 生のトークン
token_hash = hash_reset_token(token)  # ハッシュ化

# DBに保存
db_token = PasswordResetToken(
    staff_id=staff.id,
    token_hash=token_hash,  # ハッシュ化されたトークンを保存
    expires_at=datetime.now(timezone.utc) + timedelta(hours=1)
)

# メールで送信
send_password_reset_email(email, token)  # 生のトークンを送信
```

### 5.2 カスケード削除の設定

**password_reset_tokens**:
- `ON DELETE CASCADE`: スタッフが削除されたら、関連するトークンも削除
- 孤立したトークンを防ぐ

**password_reset_audit_logs**:
- `ON DELETE SET NULL`: スタッフが削除されても、監査ログは保持
- 監査の完全性を保つ

---

## 6. テストデータ作成

開発環境でのテストデータ作成例：

```python
# tests/utils/test_data.py

import uuid
from datetime import datetime, timedelta, timezone
from app.models.staff import Staff, PasswordResetToken
from app.core.security import hash_reset_token


async def create_test_password_reset_token(
    db: AsyncSession,
    staff: Staff,
    expired: bool = False,
    used: bool = False
) -> tuple[PasswordResetToken, str]:
    """テスト用のパスワードリセットトークンを作成"""

    token = str(uuid.uuid4())
    token_hash = hash_reset_token(token)

    expires_at = datetime.now(timezone.utc) + timedelta(hours=1)
    if expired:
        expires_at = datetime.now(timezone.utc) - timedelta(hours=1)

    db_token = PasswordResetToken(
        staff_id=staff.id,
        token_hash=token_hash,
        expires_at=expires_at,
        used=used,
        used_at=datetime.now(timezone.utc) if used else None
    )

    db.add(db_token)
    await db.commit()
    await db.refresh(db_token)

    return db_token, token  # DBトークンと生のトークンを返す
```

---

## Next Steps

Phase 3: バックエンド実装フェーズへ進む
- CRUD操作の実装
- エンドポイント実装
- メール送信機能
