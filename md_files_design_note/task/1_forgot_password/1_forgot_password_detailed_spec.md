# パスワードリセット機能 詳細仕様書

## 1. 概要

パスワードを忘れたユーザー向けに、メールによるパスワードリセット（ワンタイムトークン）を実装します。
既存のメール認証システム、認証フロー、セキュリティ機能と統合し、一貫性のある実装を目指します。

---

## 2. 要件定義

### 2.1 機能要件

#### 2.1.1 パスワードリセット要求
- ユーザーは登録済みメールアドレスを入力してパスワードリセットをリクエストできる
- システムは一意で期限付きのトークンを生成し、メールでリセットリンクを送信する
- セキュリティ考慮：存在しないメールアドレスでも成功レスポンスを返す（情報漏洩防止）
- レート制限：同一IPアドレスからの連続リクエストを制限（5回/10分）

#### 2.1.2 パスワードリセット実行
- ユーザーはメール内のリンクからパスワードリセット画面にアクセスする
- トークンの有効性を検証する（存在・未使用・期限内）
- 新しいパスワードを入力し、パスワード要件を満たす必要がある
- パスワードはbcryptでハッシュ化して保存する
- トークンは一度使用されたら無効化される（used=true）
- パスワード変更後、ユーザーに通知メールを送信する

#### 2.1.3 トークン検証（オプション）
- フロントエンドがトークンの有効性を事前確認できるエンドポイントを提供
- トークンが無効な場合、ユーザーに適切なエラーメッセージを表示

### 2.2 非機能要件

#### 2.2.1 セキュリティ
- HTTPS必須（本番環境）
- トークンは暗号学的に安全なランダム値（UUID v4）を使用
- **トークンはSHA-256でハッシュ化してDB保存**（DB侵害時の漏洩防止）
- トークン有効期限：1時間
- トークンは一度しか使用できない（楽観的ロックで実装）
- パスワードはbcryptでハッシュ化（既存実装と同じ）
- レート制限によるブルートフォース攻撃防止（forgot-password: 5/10分、resend: 3/10分）
- あいまいなエラーメッセージでユーザー存在の推測を防止
- **パスワード変更後は全セッション無効化**（セキュリティベストプラクティス）
- **URLフラグメント識別子でトークン渡し**（ブラウザ履歴・ログ漏洩防止）
- **監査ログの記録**（リクエスト元IP、User-Agent、アクション履歴）

#### 2.2.2 パフォーマンス
- トークン検索に複合インデックスを使用（staff_id, used, expires_at）
- 期限切れトークンの定期削除（クリーンアップジョブ、毎日実行推奨）

#### 2.2.3 監査・ログ
- **パスワードリセット監査ログテーブル**（password_reset_audit_logs）の作成
- リクエスト元情報の記録（IP アドレス、User-Agent、タイムスタンプ）
- アクションタイプの記録（requested, token_verified, completed, failed）
- パスワード変更履歴の記録（password_changed_at）
- 異常なアクセスパターンの検出とアラート

---

## 3. データベース設計

### 3.1 テーブル定義

#### 3.1.1 password_reset_tokens テーブル

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

-- トリガー: updated_atの自動更新（既存のupdate_updated_at_column関数を使用）
-- 注: update_updated_at_column関数は既存のマイグレーションで作成済みと仮定
-- CREATE TRIGGER update_password_reset_tokens_updated_at
--     BEFORE UPDATE ON password_reset_tokens
--     FOR EACH ROW
--     EXECUTE FUNCTION update_updated_at_column();
```

#### 3.1.2 実際のマイグレーション用生SQL

**Alembicマイグレーションファイル**: `migrations/versions/r3s4t5u6v7w8_add_password_reset_tokens.py`

実装された生SQLの内容：

```python
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

上記コードが実行するSQL（実際にPostgreSQLで実行される内容）:

```sql
-- アップグレード時
CREATE TABLE password_reset_tokens (
    id UUID NOT NULL DEFAULT gen_random_uuid(),
    staff_id UUID NOT NULL,
    token_hash VARCHAR(64) NOT NULL,  -- SHA-256ハッシュ
    expires_at TIMESTAMP WITH TIME ZONE NOT NULL,
    used BOOLEAN NOT NULL DEFAULT false,
    used_at TIMESTAMP WITH TIME ZONE,
    created_at TIMESTAMP WITH TIME ZONE NOT NULL DEFAULT now(),
    updated_at TIMESTAMP WITH TIME ZONE NOT NULL DEFAULT now(),
    PRIMARY KEY (id),
    FOREIGN KEY(staff_id) REFERENCES staffs (id) ON DELETE CASCADE
);

CREATE TABLE password_reset_audit_logs (
    id UUID NOT NULL DEFAULT gen_random_uuid(),
    staff_id UUID,
    action VARCHAR(50) NOT NULL,
    email VARCHAR(255),
    ip_address VARCHAR(45),
    user_agent TEXT,
    success BOOLEAN NOT NULL DEFAULT true,
    error_message TEXT,
    created_at TIMESTAMP WITH TIME ZONE NOT NULL DEFAULT now(),
    PRIMARY KEY (id),
    FOREIGN KEY(staff_id) REFERENCES staffs (id) ON DELETE SET NULL
);

CREATE UNIQUE INDEX idx_password_reset_token_hash ON password_reset_tokens (token_hash);
CREATE INDEX idx_password_reset_composite ON password_reset_tokens (staff_id, used, expires_at);

CREATE INDEX idx_audit_staff_id ON password_reset_audit_logs (staff_id);
CREATE INDEX idx_audit_created_at ON password_reset_audit_logs (created_at);
CREATE INDEX idx_audit_action ON password_reset_audit_logs (action);

-- ダウングレード時
DROP INDEX idx_audit_action;
DROP INDEX idx_audit_created_at;
DROP INDEX idx_audit_staff_id;
DROP INDEX idx_password_reset_composite;
DROP INDEX idx_password_reset_token_hash;
DROP TABLE password_reset_audit_logs;
DROP TABLE password_reset_tokens;
```

### 3.2 ORM モデル定義

`app/models/staff.py` に追加するモデル：

```python
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

`Staff` モデルにリレーションを追加：

```python
# Staff モデルに追加
password_reset_tokens: Mapped[List["PasswordResetToken"]] = relationship(
    "PasswordResetToken",
    back_populates="staff",
    cascade="all, delete-orphan"
)
```

---

## 4. マイグレーション

### 4.1 Alembic マイグレーションファイル

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
        sa.PrimaryKeyConstraint('id'),
        sa.ForeignKeyConstraint(['staff_id'], ['staffs.id'], ondelete='CASCADE'),
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
        sa.PrimaryKeyConstraint('id'),
        sa.ForeignKeyConstraint(['staff_id'], ['staffs.id'], ondelete='SET NULL'),
    )

    # インデックスを作成（password_reset_tokens）
    op.create_index('idx_password_reset_token_hash', 'password_reset_tokens', ['token_hash'], unique=True)
    op.create_index('idx_password_reset_composite', 'password_reset_tokens', ['staff_id', 'used', 'expires_at'])

    # インデックスを作成（password_reset_audit_logs）
    op.create_index('idx_audit_staff_id', 'password_reset_audit_logs', ['staff_id'])
    op.create_index('idx_audit_created_at', 'password_reset_audit_logs', ['created_at'])
    op.create_index('idx_audit_action', 'password_reset_audit_logs', ['action'])


def downgrade() -> None:
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

---

## 5. API エンドポイント設計

### 5.1 パスワードリセット要求

**エンドポイント**: `POST /api/v1/auth/forgot-password`

**リクエスト**:
```json
{
  "email": "user@example.com"
}
```

**レスポンス**:
```json
{
  "message": "パスワードリセット用のメールを送信しました。メールをご確認ください。"
}
```

**ステータスコード**:
- `200 OK`: 成功（メールアドレスが存在しない場合も同じレスポンス）
- `400 Bad Request`: バリデーションエラー
- `429 Too Many Requests`: レート制限超過

**処理フロー**:
1. メールアドレスのバリデーション
2. レート制限チェック（5回/10分）
3. ユーザーの存在確認
4. 既存の未使用トークンを無効化（オプション：または有効なトークンがあれば再送信）
5. 新しいトークンを生成（UUID v4）
6. トークンをDBに保存（expires_at = now() + 1時間）
7. メールを送信
8. 成功レスポンスを返す（ユーザーの存在に関わらず）

---

### 5.2 トークン有効性確認（オプション）

**エンドポイント**: `GET /api/v1/auth/verify-reset-token`

**リクエストパラメータ**:
```
?token=xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx
```

**レスポンス**:
```json
{
  "valid": true,
  "message": "トークンは有効です"
}
```

または

```json
{
  "valid": false,
  "message": "トークンが無効または期限切れです"
}
```

**ステータスコード**:
- `200 OK`: トークンの状態を返す（valid: true/false）

**処理フロー**:
1. トークンをDBから検索
2. トークンの存在、未使用、期限内をチェック
3. 結果を返す

---

### 5.3 パスワードリセット実行

**エンドポイント**: `POST /api/v1/auth/reset-password`

**リクエスト**:
```json
{
  "token": "xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx",
  "new_password": "NewP@ssw0rd123"
}
```

**レスポンス**:
```json
{
  "message": "パスワードが正常にリセットされました"
}
```

**ステータスコード**:
- `200 OK`: 成功
- `400 Bad Request`: バリデーションエラー、トークン無効、期限切れ、既に使用済み
- `404 Not Found`: トークンが見つからない

**処理フロー**:
1. リクエストボディのバリデーション
2. トークンをDBから検索
3. トークンの有効性チェック（存在、未使用、期限内）
4. トランザクション開始
5. パスワードのバリデーション（既存のパスワード要件と同じ）
6. パスワードをハッシュ化（bcrypt）
7. スタッフのパスワードを更新
8. `password_changed_at` を更新
9. トークンを `used=true`, `used_at=now()` に更新
10. トランザクションコミット
11. パスワード変更通知メールを送信
12. 成功レスポンスを返す

**エラーハンドリング**:
- トランザクション内で処理し、エラー時はロールバック
- トークン再利用のレース条件を防ぐため、トークン更新時に `used=false` 条件を含める

---

## 6. スキーマ定義

### 6.1 リクエストスキーマ

`app/schemas/auth.py` または `app/schemas/staff.py` に追加：

```python
from pydantic import BaseModel, EmailStr, field_validator
import re
from app.messages import ja


class ForgotPasswordRequest(BaseModel):
    """パスワードリセット要求"""
    email: EmailStr


class ResetPasswordRequest(BaseModel):
    """パスワードリセット実行"""
    token: str
    new_password: str

    @field_validator("new_password")
    @classmethod
    def validate_password(cls, v: str) -> str:
        """パスワード要件の検証（既存のStaffCreateと同じロジック）"""
        if len(v) < 8:
            raise ValueError(ja.VALIDATION_PASSWORD_TOO_SHORT)

        checks = {
            "lowercase": lambda s: re.search(r'[a-z]', s),
            "uppercase": lambda s: re.search(r'[A-Z]', s),
            "digit": lambda s: re.search(r'\d', s),
            "symbol": lambda s: re.search(r'[!@#$%^&*(),.?":{}|<>]', s),
        }

        score = sum(1 for check in checks.values() if check(v))

        if score < 4:
            raise ValueError(ja.VALIDATION_PASSWORD_COMPLEXITY)

        return v


class VerifyResetTokenRequest(BaseModel):
    """トークン有効性確認"""
    token: str


class PasswordResetResponse(BaseModel):
    """パスワードリセットレスポンス"""
    message: str


class TokenValidityResponse(BaseModel):
    """トークン有効性レスポンス"""
    valid: bool
    message: str
```

---

## 7. CRUD 操作

### 7.1 トークンハッシュ化ヘルパー関数

`app/core/security.py` に追加：

```python
import hashlib

def hash_reset_token(token: str) -> str:
    """
    パスワードリセットトークンをSHA-256でハッシュ化

    Args:
        token: 生のトークン文字列（UUID v4）

    Returns:
        SHA-256ハッシュ（64文字の16進数）
    """
    return hashlib.sha256(token.encode()).hexdigest()
```

### 7.2 CRUD 関数

新しいファイル `app/crud/crud_password_reset.py` を作成：

```python
import uuid
from datetime import datetime, timedelta, timezone
from typing import Optional
from sqlalchemy.ext.asyncio import AsyncSession
from sqlalchemy import select, delete, and_, update
from sqlalchemy.exc import IntegrityError

from app.models.staff import PasswordResetToken, PasswordResetAuditLog, Staff
from app.core.security import hash_reset_token


class CRUDPasswordReset:
    """パスワードリセットトークンのCRUD操作"""

    async def create_token(
        self,
        db: AsyncSession,
        *,
        staff_id: uuid.UUID,
        token: str,
        expires_in_hours: int = 1
    ) -> PasswordResetToken:
        """
        パスワードリセットトークンを作成（トークンはハッシュ化して保存）

        Args:
            db: データベースセッション
            staff_id: スタッフID
            token: トークン文字列（UUID v4）- 生のトークン
            expires_in_hours: 有効期限（時間）

        Returns:
            作成されたトークン
        """
        expires_at = datetime.now(timezone.utc) + timedelta(hours=expires_in_hours)
        token_hash = hash_reset_token(token)

        db_obj = PasswordResetToken(
            staff_id=staff_id,
            token_hash=token_hash,
            expires_at=expires_at,
            used=False
        )
        db.add(db_obj)
        await db.flush()
        await db.refresh(db_obj)
        return db_obj

    async def get_valid_token(
        self,
        db: AsyncSession,
        *,
        token: str
    ) -> Optional[PasswordResetToken]:
        """
        有効なトークンを取得（未使用かつ期限内）

        トークンをハッシュ化してDB検索を行う

        Args:
            db: データベースセッション
            token: トークン文字列（生のトークン）

        Returns:
            有効なトークン、または None
        """
        now = datetime.now(timezone.utc)
        token_hash = hash_reset_token(token)

        query = select(PasswordResetToken).where(
            and_(
                PasswordResetToken.token_hash == token_hash,
                PasswordResetToken.used == False,
                PasswordResetToken.expires_at > now
            )
        )
        result = await db.execute(query)
        return result.scalar_one_or_none()

    async def mark_as_used(
        self,
        db: AsyncSession,
        *,
        token_id: uuid.UUID
    ) -> Optional[PasswordResetToken]:
        """
        トークンを使用済みにマーク（楽観的ロックで実装）

        レース条件を防ぐため、used=Falseの条件付きで更新

        Args:
            db: データベースセッション
            token_id: トークンID

        Returns:
            更新されたトークン、または None（既に使用済みの場合）
        """
        now = datetime.now(timezone.utc)

        # 楽観的ロック: used=Falseの条件付きで更新
        stmt = (
            update(PasswordResetToken)
            .where(
                and_(
                    PasswordResetToken.id == token_id,
                    PasswordResetToken.used == False
                )
            )
            .values(used=True, used_at=now)
            .returning(PasswordResetToken)
        )

        result = await db.execute(stmt)
        await db.flush()

        return result.scalar_one_or_none()

    async def invalidate_existing_tokens(
        self,
        db: AsyncSession,
        *,
        staff_id: uuid.UUID
    ) -> int:
        """
        スタッフの既存の未使用トークンを無効化

        Args:
            db: データベースセッション
            staff_id: スタッフID

        Returns:
            無効化されたトークン数
        """
        now = datetime.now(timezone.utc)

        stmt = (
            update(PasswordResetToken)
            .where(
                and_(
                    PasswordResetToken.staff_id == staff_id,
                    PasswordResetToken.used == False
                )
            )
            .values(used=True, used_at=now)
        )

        result = await db.execute(stmt)
        await db.flush()
        return result.rowcount

    async def delete_expired_tokens(self, db: AsyncSession) -> int:
        """
        期限切れのトークンを削除（クリーンアップ用）

        Args:
            db: データベースセッション

        Returns:
            削除されたトークン数
        """
        now = datetime.now(timezone.utc)

        stmt = delete(PasswordResetToken).where(
            PasswordResetToken.expires_at < now
        )
        result = await db.execute(stmt)
        await db.flush()
        return result.rowcount

    async def create_audit_log(
        self,
        db: AsyncSession,
        *,
        staff_id: Optional[uuid.UUID],
        action: str,
        email: Optional[str] = None,
        ip_address: Optional[str] = None,
        user_agent: Optional[str] = None,
        success: bool = True,
        error_message: Optional[str] = None
    ) -> PasswordResetAuditLog:
        """
        監査ログを作成

        Args:
            db: データベースセッション
            staff_id: スタッフID（存在しない場合はNone）
            action: アクション（'requested', 'token_verified', 'completed', 'failed'）
            email: メールアドレス
            ip_address: IPアドレス
            user_agent: User-Agent
            success: 成功フラグ
            error_message: エラーメッセージ

        Returns:
            作成された監査ログ
        """
        audit_log = PasswordResetAuditLog(
            staff_id=staff_id,
            action=action,
            email=email,
            ip_address=ip_address,
            user_agent=user_agent,
            success=success,
            error_message=error_message
        )
        db.add(audit_log)
        await db.flush()
        await db.refresh(audit_log)
        return audit_log


password_reset = CRUDPasswordReset()
```

### 7.3 監査ログモデル

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

`Staff` モデルに追加：

```python
password_reset_audit_logs: Mapped[List["PasswordResetAuditLog"]] = relationship(
    "PasswordResetAuditLog",
    back_populates="staff"
)
```

`app/crud/__init__.py` に追加：

```python
from .crud_password_reset import password_reset
```

---

## 8. サービス層（オプション）

複雑なビジネスロジックがある場合、サービス層を追加することを検討します。
現在の実装では、エンドポイント内で直接CRUD操作を呼び出す形でも十分です。

ただし、将来的な拡張（例：パスワード履歴の管理、複数のメール送信ロジック）を考慮する場合：

`app/services/password_reset_service.py`:

```python
import uuid
import secrets
from datetime import datetime, timezone
from typing import Optional
from sqlalchemy.ext.asyncio import AsyncSession
from sqlalchemy import select, update

from app import crud
from app.models.staff import Staff, Session  # セッションモデル
from app.core.mail import send_password_reset_email, send_password_changed_notification
from app.core.security import get_password_hash


class PasswordResetService:
    """パスワードリセットのビジネスロジック"""

    async def request_password_reset(
        self,
        db: AsyncSession,
        email: str,
        ip_address: Optional[str] = None,
        user_agent: Optional[str] = None
    ) -> bool:
        """
        パスワードリセットをリクエスト（監査ログ付き）

        Args:
            db: データベースセッション
            email: メールアドレス
            ip_address: リクエスト元IPアドレス
            user_agent: User-Agent

        Returns:
            True（常に成功を返す、セキュリティのため）
        """
        # ユーザーを検索
        staff = await crud.staff.get_by_email(db, email=email)

        if staff:
            try:
                # 既存の未使用トークンを無効化
                await crud.password_reset.invalidate_existing_tokens(db, staff_id=staff.id)

                # 新しいトークンを生成
                token = str(uuid.uuid4())
                await crud.password_reset.create_token(
                    db,
                    staff_id=staff.id,
                    token=token,
                    expires_in_hours=1
                )

                # 監査ログを記録
                await crud.password_reset.create_audit_log(
                    db,
                    staff_id=staff.id,
                    action='requested',
                    email=email,
                    ip_address=ip_address,
                    user_agent=user_agent,
                    success=True
                )

                await db.commit()

                # メールを送信（トランザクション外）
                await send_password_reset_email(
                    recipient_email=email,
                    staff_name=staff.full_name,
                    token=token
                )

            except Exception as e:
                # エラー時も監査ログを記録
                await crud.password_reset.create_audit_log(
                    db,
                    staff_id=staff.id,
                    action='requested',
                    email=email,
                    ip_address=ip_address,
                    user_agent=user_agent,
                    success=False,
                    error_message=str(e)
                )
                await db.commit()
                raise
        else:
            # ユーザーが存在しない場合も監査ログを記録（staff_id=None）
            await crud.password_reset.create_audit_log(
                db,
                staff_id=None,
                action='requested',
                email=email,
                ip_address=ip_address,
                user_agent=user_agent,
                success=False,
                error_message="User not found"
            )
            await db.commit()

        # セキュリティのため、ユーザーが存在しない場合も成功を返す
        return True

    async def verify_reset_token(
        self,
        db: AsyncSession,
        token: str,
        ip_address: Optional[str] = None,
        user_agent: Optional[str] = None
    ) -> bool:
        """
        トークンの有効性を確認（監査ログ付き）

        Args:
            db: データベースセッション
            token: トークン文字列
            ip_address: リクエスト元IPアドレス
            user_agent: User-Agent

        Returns:
            有効な場合True、無効な場合False
        """
        token_obj = await crud.password_reset.get_valid_token(db, token=token)
        is_valid = token_obj is not None

        if token_obj:
            # 監査ログを記録
            await crud.password_reset.create_audit_log(
                db,
                staff_id=token_obj.staff_id,
                action='token_verified',
                ip_address=ip_address,
                user_agent=user_agent,
                success=True
            )
            await db.commit()

        return is_valid

    async def reset_password(
        self,
        db: AsyncSession,
        token: str,
        new_password: str,
        ip_address: Optional[str] = None,
        user_agent: Optional[str] = None
    ) -> tuple[bool, Optional[str]]:
        """
        パスワードをリセット（セッション無効化・監査ログ付き）

        Args:
            db: データベースセッション
            token: トークン文字列
            new_password: 新しいパスワード
            ip_address: リクエスト元IPアドレス
            user_agent: User-Agent

        Returns:
            (成功フラグ, エラーメッセージ)
        """
        # トークンを検証
        token_obj = await crud.password_reset.get_valid_token(db, token=token)
        if not token_obj:
            return False, "トークンが無効または期限切れです"

        # スタッフを取得
        staff = await crud.staff.get(db, id=token_obj.staff_id)
        if not staff:
            return False, "ユーザーが見つかりません"

        try:
            # パスワードを更新
            staff.hashed_password = get_password_hash(new_password)
            staff.password_changed_at = datetime.now(timezone.utc)
            staff.failed_password_attempts = 0  # リセット試行回数をクリア
            staff.is_locked = False  # ロック状態を解除

            # トークンを使用済みにマーク（楽観的ロック）
            marked_token = await crud.password_reset.mark_as_used(db, token_id=token_obj.id)
            if not marked_token:
                # 既に使用済み（レース条件）
                await crud.password_reset.create_audit_log(
                    db,
                    staff_id=staff.id,
                    action='failed',
                    email=staff.email,
                    ip_address=ip_address,
                    user_agent=user_agent,
                    success=False,
                    error_message="Token already used (race condition)"
                )
                await db.commit()
                return False, "このトークンは既に使用されています"

            # 【重要】全セッションを無効化
            stmt = (
                update(Session)
                .where(Session.staff_id == staff.id)
                .values(is_active=False, revoked_at=datetime.now(timezone.utc))
            )
            await db.execute(stmt)

            # 監査ログを記録
            await crud.password_reset.create_audit_log(
                db,
                staff_id=staff.id,
                action='completed',
                email=staff.email,
                ip_address=ip_address,
                user_agent=user_agent,
                success=True
            )

            # 変更をコミット
            await db.commit()

            # 通知メールを送信（トランザクション外）
            await send_password_changed_notification(
                email=staff.email,
                staff_name=staff.full_name
            )

            return True, None

        except Exception as e:
            # エラー時も監査ログを記録
            await crud.password_reset.create_audit_log(
                db,
                staff_id=staff.id,
                action='failed',
                email=staff.email,
                ip_address=ip_address,
                user_agent=user_agent,
                success=False,
                error_message=str(e)
            )
            await db.commit()
            return False, "パスワードリセットに失敗しました"


password_reset_service = PasswordResetService()
```

---

## 9. メール送信

### 9.1 メール送信関数

`app/core/mail.py` に追加：

```python
async def send_password_reset_email(
    recipient_email: str,
    staff_name: str,
    token: str
) -> None:
    """
    パスワードリセット用のメールを送信します。

    セキュリティ上の理由により、トークンはURLフラグメント識別子（#token=xxx）で渡します。
    これにより、ブラウザ履歴やサーバーログにトークンが記録されるのを防ぎます。

    Args:
        recipient_email: 受信者のメールアドレス
        staff_name: スタッフの氏名
        token: パスワードリセットトークン
    """
    subject = "【ケイカくん】パスワードリセットのご案内"
    # フラグメント識別子を使用（#token= の形式）
    reset_url = f"{settings.FRONTEND_URL}/auth/reset-password#token={token}"

    context = {
        "title": subject,
        "staff_name": staff_name,
        "reset_url": reset_url,
        "expire_hours": 1,  # トークン有効期限
    }

    # メール送信はトランザクション外で行う（DB変更後）
    await send_email(
        recipient_email=recipient_email,
        subject=subject,
        template_name="password_reset.html",
        context=context,
    )


async def send_password_changed_notification(
    email: str,
    staff_name: str
) -> None:
    """
    パスワード変更完了通知メールを送信します。

    Args:
        email: 受信者のメールアドレス
        staff_name: スタッフの氏名
    """
    subject = "【ケイカくん】パスワードが変更されました"

    context = {
        "title": subject,
        "staff_name": staff_name,
    }

    await send_email(
        recipient_email=email,
        subject=subject,
        template_name="password_changed.html",
        context=context,
    )
```

**重要な注意事項**:
- メール送信は必ずDB commitの**後**に実行すること（トランザクション外）
- メール送信が失敗してもDB変更はロールバックしない
- メール送信失敗時のリトライロジックは別途実装を検討

### 9.2 メールテンプレート

`app/templates/email/password_reset.html`:

```html
<!DOCTYPE html>
<html lang="ja">
<head>
    <meta charset="UTF-8">
    <meta name="viewport" content="width=device-width, initial-scale=1.0">
    <title>{{ title }}</title>
    <style>
        body {
            font-family: 'Helvetica Neue', Arial, 'Hiragino Kaku Gothic ProN', 'Hiragino Sans', Meiryo, sans-serif;
            background-color: #f4f4f4;
            margin: 0;
            padding: 0;
        }
        .container {
            max-width: 600px;
            margin: 20px auto;
            background-color: #ffffff;
            padding: 30px;
            border-radius: 8px;
            box-shadow: 0 2px 4px rgba(0,0,0,0.1);
        }
        h1 {
            color: #333333;
            font-size: 24px;
            margin-bottom: 20px;
        }
        p {
            color: #555555;
            line-height: 1.6;
            margin-bottom: 15px;
        }
        .button {
            display: inline-block;
            padding: 12px 24px;
            background-color: #007bff;
            color: #ffffff !important;
            text-decoration: none;
            border-radius: 4px;
            font-weight: bold;
            margin: 20px 0;
        }
        .button:hover {
            background-color: #0056b3;
        }
        .footer {
            margin-top: 30px;
            padding-top: 20px;
            border-top: 1px solid #eeeeee;
            font-size: 12px;
            color: #888888;
        }
        .warning {
            background-color: #fff3cd;
            border-left: 4px solid #ffc107;
            padding: 12px;
            margin: 20px 0;
        }
        .warning p {
            margin: 0;
            color: #856404;
        }
    </style>
</head>
<body>
    <div class="container">
        <h1>{{ title }}</h1>

        <p>{{ staff_name }} 様</p>

        <p>
            パスワードリセットのリクエストを受け付けました。<br>
            以下のボタンをクリックして、新しいパスワードを設定してください。
        </p>

        <a href="{{ reset_url }}" class="button">パスワードをリセット</a>

        <p>
            または、以下のURLをブラウザにコピー＆ペーストしてください：<br>
            <a href="{{ reset_url }}">{{ reset_url }}</a>
        </p>

        <div class="warning">
            <p>
                <strong>重要：</strong><br>
                このリンクは{{ expire_hours }}時間のみ有効です。<br>
                パスワードリセットをリクエストしていない場合は、このメールを無視してください。
            </p>
        </div>

        <div class="footer">
            <p>
                このメールは自動送信されています。返信しないでください。<br>
                ご不明な点がございましたら、システム管理者にお問い合わせください。
            </p>
        </div>
    </div>
</body>
</html>
```

---

## 10. エンドポイント実装

### 10.1 ヘルパー関数

リクエストからIPアドレスとUser-Agentを取得するヘルパー関数：

```python
def get_client_ip(request: Request) -> str:
    """リクエストからクライアントのIPアドレスを取得"""
    # X-Forwarded-Forヘッダーを優先（プロキシ経由の場合）
    forwarded_for = request.headers.get("X-Forwarded-For")
    if forwarded_for:
        return forwarded_for.split(",")[0].strip()

    # X-Real-IPヘッダー（nginxなど）
    real_ip = request.headers.get("X-Real-IP")
    if real_ip:
        return real_ip

    # 直接接続の場合
    return request.client.host if request.client else "unknown"


def get_user_agent(request: Request) -> str:
    """リクエストからUser-Agentを取得"""
    return request.headers.get("User-Agent", "unknown")
```

### 10.2 ルーター追加

`app/api/v1/endpoints/auths.py` に追加：

```python
import uuid
from datetime import datetime, timezone
from fastapi import APIRouter, Depends, HTTPException, Request, status
from sqlalchemy.ext.asyncio import AsyncSession
from sqlalchemy import update

from app.api import deps
from app.core.limiter import limiter
from app.schemas.auth import (
    ForgotPasswordRequest,
    ResetPasswordRequest,
    VerifyResetTokenRequest,
    PasswordResetResponse,
    TokenValidityResponse
)
from app.crud import password_reset as crud_password_reset
from app.core.mail import send_password_reset_email, send_password_changed_notification
from app.core.security import get_password_hash
from app.models.staff import Session as StaffSession
from app.messages import ja


@router.post(
    "/forgot-password",
    response_model=PasswordResetResponse,
    status_code=status.HTTP_200_OK,
)
@limiter.limit("5/10minute")
async def forgot_password(
    *,
    request: Request,
    db: AsyncSession = Depends(deps.get_db),
    data: ForgotPasswordRequest,
    staff_crud=Depends(deps.get_staff_crud),
):
    """
    パスワードリセットをリクエストします（監査ログ付き）
    メールアドレスが存在する場合、リセット用のメールを送信します。
    """
    # リクエスト情報を取得
    ip_address = get_client_ip(request)
    user_agent = get_user_agent(request)

    # ユーザーを検索
    staff = await staff_crud.get_by_email(db, email=data.email)

    if staff:
        try:
            # 既存の未使用トークンを無効化
            await crud_password_reset.invalidate_existing_tokens(db, staff_id=staff.id)

            # 新しいトークンを生成
            token = str(uuid.uuid4())
            await crud_password_reset.create_token(
                db,
                staff_id=staff.id,
                token=token,
                expires_in_hours=1
            )

            # 監査ログを記録
            await crud_password_reset.create_audit_log(
                db,
                staff_id=staff.id,
                action='requested',
                email=data.email,
                ip_address=ip_address,
                user_agent=user_agent,
                success=True
            )

            await db.commit()

            # メールを送信（トランザクション外）
            await send_password_reset_email(
                recipient_email=data.email,
                staff_name=staff.full_name,
                token=token
            )

        except Exception as e:
            # エラー時も監査ログを記録
            await crud_password_reset.create_audit_log(
                db,
                staff_id=staff.id,
                action='requested',
                email=data.email,
                ip_address=ip_address,
                user_agent=user_agent,
                success=False,
                error_message=str(e)
            )
            await db.commit()
            raise
    else:
        # ユーザーが存在しない場合も監査ログを記録（staff_id=None）
        await crud_password_reset.create_audit_log(
            db,
            staff_id=None,
            action='requested',
            email=data.email,
            ip_address=ip_address,
            user_agent=user_agent,
            success=False,
            error_message="User not found"
        )
        await db.commit()

    # セキュリティのため、常に成功メッセージを返す
    return PasswordResetResponse(
        message=ja.AUTH_PASSWORD_RESET_EMAIL_SENT
    )


@router.post(
    "/resend-reset-email",
    response_model=PasswordResetResponse,
    status_code=status.HTTP_200_OK,
)
@limiter.limit("3/10minute")
async def resend_reset_email(
    *,
    request: Request,
    db: AsyncSession = Depends(deps.get_db),
    data: ForgotPasswordRequest,
    staff_crud=Depends(deps.get_staff_crud),
):
    """
    パスワードリセットメールを再送信します（レート制限: 3回/10分）
    forgot_passwordと同じロジックだが、より厳しいレート制限を適用
    """
    return await forgot_password(
        request=request,
        db=db,
        data=data,
        staff_crud=staff_crud
    )


@router.get(
    "/verify-reset-token",
    response_model=TokenValidityResponse,
    status_code=status.HTTP_200_OK,
)
async def verify_reset_token(
    token: str,
    request: Request,
    db: AsyncSession = Depends(deps.get_db),
):
    """
    パスワードリセットトークンの有効性を確認します（監査ログ付き）
    """
    # リクエスト情報を取得
    ip_address = get_client_ip(request)
    user_agent = get_user_agent(request)

    token_obj = await crud_password_reset.get_valid_token(db, token=token)

    if token_obj:
        # 監査ログを記録
        await crud_password_reset.create_audit_log(
            db,
            staff_id=token_obj.staff_id,
            action='token_verified',
            ip_address=ip_address,
            user_agent=user_agent,
            success=True
        )
        await db.commit()

        return TokenValidityResponse(
            valid=True,
            message=ja.AUTH_RESET_TOKEN_VALID
        )
    else:
        return TokenValidityResponse(
            valid=False,
            message=ja.AUTH_RESET_TOKEN_INVALID_OR_EXPIRED
        )


@router.post(
    "/reset-password",
    response_model=PasswordResetResponse,
    status_code=status.HTTP_200_OK,
)
async def reset_password(
    *,
    request: Request,
    db: AsyncSession = Depends(deps.get_db),
    data: ResetPasswordRequest,
    staff_crud=Depends(deps.get_staff_crud),
):
    """
    トークンを使用してパスワードをリセットします
    セッション無効化・監査ログ・楽観的ロック対応
    """
    # リクエスト情報を取得
    ip_address = get_client_ip(request)
    user_agent = get_user_agent(request)

    # トークンを検証
    token_obj = await crud_password_reset.get_valid_token(db, token=data.token)
    if not token_obj:
        raise HTTPException(
            status_code=status.HTTP_400_BAD_REQUEST,
            detail=ja.AUTH_RESET_TOKEN_INVALID_OR_EXPIRED,
        )

    # スタッフを取得
    staff = await staff_crud.get(db, id=token_obj.staff_id)
    if not staff:
        raise HTTPException(
            status_code=status.HTTP_404_NOT_FOUND,
            detail=ja.AUTH_USER_NOT_FOUND,
        )

    try:
        # パスワードを更新
        staff.hashed_password = get_password_hash(data.new_password)
        staff.password_changed_at = datetime.now(timezone.utc)
        staff.failed_password_attempts = 0
        staff.is_locked = False

        # トークンを使用済みにマーク（楽観的ロック）
        marked_token = await crud_password_reset.mark_as_used(db, token_id=token_obj.id)
        if not marked_token:
            # 既に使用済み（レース条件）
            await crud_password_reset.create_audit_log(
                db,
                staff_id=staff.id,
                action='failed',
                email=staff.email,
                ip_address=ip_address,
                user_agent=user_agent,
                success=False,
                error_message="Token already used (race condition)"
            )
            await db.commit()
            raise HTTPException(
                status_code=status.HTTP_400_BAD_REQUEST,
                detail=ja.AUTH_RESET_TOKEN_ALREADY_USED,
            )

        # 【重要】全セッションを無効化
        stmt = (
            update(StaffSession)
            .where(StaffSession.staff_id == staff.id)
            .values(is_active=False, revoked_at=datetime.now(timezone.utc))
        )
        await db.execute(stmt)

        # 監査ログを記録
        await crud_password_reset.create_audit_log(
            db,
            staff_id=staff.id,
            action='completed',
            email=staff.email,
            ip_address=ip_address,
            user_agent=user_agent,
            success=True
        )

        await db.commit()

        # 通知メールを送信（トランザクション外）
        await send_password_changed_notification(
            email=staff.email,
            staff_name=staff.full_name
        )

        return PasswordResetResponse(
            message=ja.AUTH_PASSWORD_RESET_SUCCESS
        )

    except HTTPException:
        raise
    except Exception as e:
        # エラー時も監査ログを記録
        await crud_password_reset.create_audit_log(
            db,
            staff_id=staff.id,
            action='failed',
            email=staff.email,
            ip_address=ip_address,
            user_agent=user_agent,
            success=False,
            error_message=str(e)
        )
        await db.commit()
        raise HTTPException(
            status_code=status.HTTP_500_INTERNAL_SERVER_ERROR,
            detail=ja.AUTH_PASSWORD_RESET_FAILED,
        )
```

### 10.3 フロントエンドでのトークン処理

フラグメント識別子（#token=xxx）からトークンを取得する例：

```typescript
// React/Next.jsの例
useEffect(() => {
  // URLフラグメントからトークンを取得
  const hash = window.location.hash;
  if (hash.startsWith('#token=')) {
    const token = hash.substring(7); // '#token='の7文字を除去
    setToken(token);

    // セキュリティのため、履歴からフラグメントを削除
    window.history.replaceState(null, '', window.location.pathname);
  }
}, []);
```

---

## 11. メッセージ定義

`app/messages/ja.py` に追加：

```python
# パスワードリセット関連
AUTH_PASSWORD_RESET_EMAIL_SENT = "パスワードリセット用のメールを送信しました。メールをご確認ください。"
AUTH_RESET_TOKEN_VALID = "トークンは有効です"
AUTH_RESET_TOKEN_INVALID_OR_EXPIRED = "トークンが無効または期限切れです。新しいリセットリンクをリクエストしてください。"
AUTH_RESET_TOKEN_ALREADY_USED = "このトークンは既に使用されています。新しいリセットリンクをリクエストしてください。"
AUTH_PASSWORD_RESET_SUCCESS = "パスワードが正常にリセットされました。新しいパスワードでログインしてください。"
AUTH_PASSWORD_RESET_FAILED = "パスワードリセットに失敗しました。時間をおいて再度お試しください。"
AUTH_USER_NOT_FOUND = "ユーザーが見つかりません"

# レート制限
AUTH_RATE_LIMIT_EXCEEDED = "リクエスト回数が多すぎます。しばらくしてから再度お試しください。"
```

---

## 12. テスト項目

### 12.1 ユニットテスト

#### 12.1.1 モデルテスト
- `PasswordResetToken` モデルの作成
- リレーションの動作確認（staff との関連）

#### 12.1.2 CRUDテスト
- トークンの作成（`create_token`）
- 有効なトークンの取得（`get_valid_token`）
  - 未使用かつ期限内のトークン
  - 使用済みトークンは取得できない
  - 期限切れトークンは取得できない
- トークンの使用済みマーク（`mark_as_used`）
- 既存トークンの無効化（`invalidate_existing_tokens`）
- 期限切れトークンの削除（`delete_expired_tokens`）

#### 12.1.3 サービステスト（サービス層を実装する場合）
- パスワードリセット要求（`request_password_reset`）
- トークン検証（`verify_reset_token`）
- パスワードリセット（`reset_password`）

### 12.2 統合テスト（E2Eテスト）

#### 12.2.1 正常系
1. パスワードリセット要求 → メール送信 → トークン検証 → パスワードリセット成功
2. 複数回リクエストした場合、最新のトークンのみ有効
3. パスワードリセット後、新しいパスワードでログインできる

#### 12.2.2 異常系
1. 存在しないメールアドレスでリクエスト → 成功レスポンス（セキュリティ）
2. 期限切れトークンでリセット → エラー
3. 使用済みトークンでリセット → エラー
4. 無効なトークンでリセット → エラー
5. パスワード要件を満たさない → バリデーションエラー
6. レート制限超過 → 429エラー

### 12.3 セキュリティテスト
1. トークンの予測不可能性（UUID v4）
2. トークンの一度のみ使用（再利用不可）
3. レート制限の動作確認
4. SQLインジェクション対策
5. XSS対策（メールテンプレート）
6. CSRF対策（既存の認証システムと同様）

---

## 13. TODO チェックリスト

### 13.1 バックエンド実装
- [ ] DBマイグレーションファイル作成
  - [ ] `password_reset_tokens` テーブル（token_hashカラム）
  - [ ] `password_reset_audit_logs` テーブル
  - [ ] 複合インデックス作成
- [ ] `PasswordResetToken` モデル実装（token_hashフィールド）
- [ ] `PasswordResetAuditLog` モデル実装
- [ ] `Staff` モデルにリレーション追加
- [ ] CRUD操作実装（`crud_password_reset.py`）
  - [ ] トークンハッシュ化ヘルパー関数（`hash_reset_token`）
  - [ ] 楽観的ロック実装（`mark_as_used`）
  - [ ] 監査ログCRUD操作（`create_audit_log`）
- [ ] スキーマ定義（`schemas/auth.py`）
- [ ] メール送信関数実装（`core/mail.py`）
  - [ ] URLフラグメント識別子使用（#token=xxx）
  - [ ] トランザクション外でのメール送信
- [ ] メールテンプレート作成
  - [ ] `templates/email/password_reset.html`
  - [ ] `templates/email/password_changed.html`
- [ ] エンドポイント実装（`api/v1/endpoints/auths.py`）
  - [ ] ヘルパー関数（`get_client_ip`, `get_user_agent`）
  - [ ] `POST /forgot-password`（監査ログ付き）
  - [ ] `POST /resend-reset-email`（厳しいレート制限）
  - [ ] `GET /verify-reset-token`（監査ログ付き）
  - [ ] `POST /reset-password`（セッション無効化・監査ログ付き）
- [ ] メッセージ定義（`messages/ja.py`）
  - [ ] 具体的なエラーメッセージ

### 13.2 テスト実装
- [ ] モデルのユニットテスト
  - [ ] `PasswordResetToken` モデル
  - [ ] `PasswordResetAuditLog` モデル
- [ ] CRUDのユニットテスト
  - [ ] トークンハッシュ化のテスト
  - [ ] 楽観的ロックのテスト（レース条件）
  - [ ] 監査ログ作成のテスト
- [ ] エンドポイントの統合テスト（E2E）
  - [ ] パスワードリセットフロー全体
  - [ ] セッション無効化の確認
  - [ ] 監査ログの記録確認
  - [ ] レート制限のテスト
- [ ] セキュリティテスト
  - [ ] トークンハッシュ化の確認
  - [ ] レース条件の確認
  - [ ] SQLインジェクション対策

### 13.3 フロントエンド実装
- [ ] パスワードリセット要求画面（`/forgot-password`）
  - [ ] 再送信機能
- [ ] パスワードリセット実行画面（`/reset-password`）
  - [ ] URLフラグメントからトークン取得
  - [ ] 履歴からフラグメント削除
- [ ] フォームバリデーション
- [ ] エラーハンドリング
- [ ] ユーザーフィードバック（成功/エラーメッセージ）

### 13.4 運用・監視
- [ ] 監査ログ実装完了
  - [ ] IPアドレス記録
  - [ ] User-Agent記録
  - [ ] アクション種別記録
- [ ] 期限切れトークンのクリーンアップジョブ（定期実行）
  - [ ] Celeryタスク実装
  - [ ] cronジョブ設定
- [ ] 監査ログ分析ツール
  - [ ] 異常なリクエストパターン検出
  - [ ] アラート設定
- [ ] 環境変数設定
  - [ ] `FRONTEND_URL`
  - [ ] トークン有効期限設定

---

## 14. 注意事項・ベストプラクティス

### 14.1 セキュリティ
- **HTTPS必須**: 本番環境では必ずHTTPSを使用する
- **トークンハッシュ化**: トークンはSHA-256でハッシュ化してDB保存（平文保存禁止）
- **URLフラグメント識別子**: トークンはクエリパラメータ（?token=xxx）ではなくフラグメント（#token=xxx）で渡す
  - ブラウザ履歴やサーバーログに記録されない
  - リファラーヘッダーに含まれない
- **トークンの有効期限**: 短め（1時間）を推奨
- **レート制限**: ブルートフォース攻撃を防ぐため、厳格に設定
  - forgot-password: 5回/10分
  - resend: 3回/10分（より厳しく）
- **ユーザー存在の推測防止**: 存在しないメールアドレスでも成功レスポンスを返す
- **トークンの再利用防止**: 楽観的ロックで一度使用されたトークンは無効化する
- **パスワードのハッシュ化**: bcryptで必ずハッシュ化する
- **セッション無効化**: パスワード変更後は全セッションを無効化する（セキュリティベストプラクティス）
- **監査ログ**: すべてのアクションを記録（IP、User-Agent、成否）

### 14.2 ユーザビリティ
- **明確なエラーメッセージ**: ユーザーが次に何をすべきかわかるようにする
  - 「トークンが無効または期限切れです。新しいリセットリンクをリクエストしてください。」
  - 「このトークンは既に使用されています。新しいリセットリンクをリクエストしてください。」
- **メールの送信確認**: 「メールを送信しました」というメッセージを表示
- **トークン有効期限の表示**: メール内で有効期限を明示する
- **再送信機能**: メールが届かない場合の再送信ボタンを提供
- **サポート情報の提供**: メールが届かない場合の対処法を提供

### 14.3 運用
- **期限切れトークンの削除**: 定期的にクリーンアップジョブを実行（毎日推奨）
- **監査ログの監視**: 異常なアクセスパターンを検出
  - 同一IPから大量のリクエスト
  - 短時間に複数のメールアドレスへのリクエスト
- **メール送信の監視**: 送信失敗時のリトライ・アラート設定
- **パスワードポリシー**: 複雑さ要件を明確にする

### 14.4 トランザクション管理
- **メール送信はトランザクション外**: DB commitの後にメール送信を行う
- **メール送信失敗時**: DB変更はロールバックしない（トークンは既に作成済み）
- **監査ログは常に記録**: 成功・失敗に関わらず監査ログを記録

---

## 15. クリーンアップジョブ実装

期限切れトークンを定期的に削除するクリーンアップジョブの実装。

### 15.1 Celeryタスク実装

`app/tasks/cleanup_tasks.py`:

```python
from celery import shared_task
from sqlalchemy.ext.asyncio import create_async_engine, async_sessionmaker
from app.core.config import settings
from app.crud import password_reset as crud_password_reset
import logging

logger = logging.getLogger(__name__)


@shared_task(name="cleanup_expired_password_reset_tokens")
def cleanup_expired_tokens():
    """
    期限切れのパスワードリセットトークンを削除する

    実行頻度: 毎日1回（深夜推奨）
    """
    import asyncio

    async def _cleanup():
        # 非同期エンジンとセッションを作成
        engine = create_async_engine(settings.DATABASE_URL)
        async_session = async_sessionmaker(engine, expire_on_commit=False)

        async with async_session() as session:
            try:
                deleted_count = await crud_password_reset.delete_expired_tokens(session)
                await session.commit()
                logger.info(f"Deleted {deleted_count} expired password reset tokens")
                return deleted_count
            except Exception as e:
                logger.error(f"Error cleaning up expired tokens: {str(e)}")
                await session.rollback()
                raise
            finally:
                await engine.dispose()

    # 非同期関数を同期的に実行
    return asyncio.run(_cleanup())
```

### 15.2 Celery Beat スケジュール設定

`app/core/celery_config.py`:

```python
from celery.schedules import crontab

beat_schedule = {
    'cleanup-expired-password-reset-tokens': {
        'task': 'cleanup_expired_password_reset_tokens',
        'schedule': crontab(hour=3, minute=0),  # 毎日午前3時に実行
    },
}
```

### 15.3 代替: cronジョブ実装

Celeryを使用しない場合、cronジョブで直接実行する管理コマンドを作成：

`app/cli/cleanup.py`:

```python
import asyncio
import typer
from sqlalchemy.ext.asyncio import create_async_engine, async_sessionmaker
from app.core.config import settings
from app.crud import password_reset as crud_password_reset

app = typer.Typer()


@app.command()
def cleanup_expired_tokens():
    """期限切れのパスワードリセットトークンを削除"""

    async def _cleanup():
        engine = create_async_engine(settings.DATABASE_URL)
        async_session = async_sessionmaker(engine, expire_on_commit=False)

        async with async_session() as session:
            try:
                deleted_count = await crud_password_reset.delete_expired_tokens(session)
                await session.commit()
                typer.echo(f"✓ Deleted {deleted_count} expired password reset tokens")
                return deleted_count
            except Exception as e:
                typer.echo(f"✗ Error: {str(e)}", err=True)
                await session.rollback()
                raise
            finally:
                await engine.dispose()

    asyncio.run(_cleanup())


if __name__ == "__main__":
    app()
```

crontabに追加:

```bash
# 毎日午前3時に実行
0 3 * * * cd /path/to/project && python -m app.cli.cleanup cleanup-expired-tokens
```

---

## 16. 環境変数設定

### 16.1 必須環境変数

`.env` ファイルに追加：

```bash
# フロントエンドURL（パスワードリセットメール用）
FRONTEND_URL=https://yourdomain.com

# パスワードリセットトークン有効期限（時間）
PASSWORD_RESET_TOKEN_EXPIRE_HOURS=1

# レート制限設定
RATE_LIMIT_FORGOT_PASSWORD=5/10minute
RATE_LIMIT_RESEND_EMAIL=3/10minute
```

### 16.2 設定ファイルへの追加

`app/core/config.py`:

```python
from pydantic_settings import BaseSettings

class Settings(BaseSettings):
    # 既存の設定...

    # パスワードリセット設定
    FRONTEND_URL: str
    PASSWORD_RESET_TOKEN_EXPIRE_HOURS: int = 1
    RATE_LIMIT_FORGOT_PASSWORD: str = "5/10minute"
    RATE_LIMIT_RESEND_EMAIL: str = "3/10minute"

    class Config:
        env_file = ".env"
        case_sensitive = True


settings = Settings()
```

### 16.3 使用例

```python
# メール送信時
reset_url = f"{settings.FRONTEND_URL}/auth/reset-password#token={token}"

# トークン作成時
await crud_password_reset.create_token(
    db,
    staff_id=staff.id,
    token=token,
    expires_in_hours=settings.PASSWORD_RESET_TOKEN_EXPIRE_HOURS
)

# レート制限
@limiter.limit(settings.RATE_LIMIT_FORGOT_PASSWORD)
async def forgot_password(...):
    ...
```

---

## 17. 将来の拡張案

### 17.1 機能拡張
- パスワード履歴管理（過去のパスワードの再利用を防ぐ）
- アカウントロック機能の強化（連続失敗でロック）
- 多要素認証（MFA）との統合
- パスワード強度チェッカー（リアルタイム）
- SMS/電話によるパスワードリセット（代替手段）

### 17.2 UX改善
- パスワードリセットフローのステップ表示
- パスワード変更完了後の自動ログイン（オプション）
- メール未受信時の再送信機能（既に実装済み）

### 17.3 監査・コンプライアンス
- GDPR対応（個人データの管理・削除）
- パスワードリセット履歴の長期保存（監査ログで実装済み）
- 管理者向けダッシュボード（リセット統計）

---

以上がパスワードリセット機能の詳細な要件定義です。
