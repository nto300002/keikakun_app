<!--
作業ブランチ: issue/feature-パスワードを忘れた際の処理
注意: このファイルを編集する場合、必ず作業中のブランチ名を上部に記載し、変更はそのブランチへ push してください。
-->

# Phase 4: テストフェーズ

パスワードリセット機能のテスト戦略と実装

---

## 1. テスト項目

### 1.1 ユニットテスト

#### 1.1.1 モデルテスト

**ファイル**: `tests/unit/models/test_password_reset_token.py`

```python
import pytest
import uuid
from datetime import datetime, timedelta, timezone
from sqlalchemy.ext.asyncio import AsyncSession

from app.models.staff import PasswordResetToken, Staff
from app.core.security import hash_reset_token


class TestPasswordResetTokenModel:
    """PasswordResetTokenモデルのユニットテスト"""

    async def test_create_token(self, db: AsyncSession, test_staff: Staff):
        """トークンの作成"""
        token = str(uuid.uuid4())
        token_hash = hash_reset_token(token)
        expires_at = datetime.now(timezone.utc) + timedelta(hours=1)

        db_token = PasswordResetToken(
            staff_id=test_staff.id,
            token_hash=token_hash,
            expires_at=expires_at,
            used=False
        )
        db.add(db_token)
        await db.commit()
        await db.refresh(db_token)

        assert db_token.id is not None
        assert db_token.staff_id == test_staff.id
        assert db_token.token_hash == token_hash
        assert db_token.used is False
        assert db_token.used_at is None

    async def test_staff_relationship(self, db: AsyncSession, test_staff: Staff):
        """Staffモデルとのリレーション"""
        token = str(uuid.uuid4())
        token_hash = hash_reset_token(token)

        db_token = PasswordResetToken(
            staff_id=test_staff.id,
            token_hash=token_hash,
            expires_at=datetime.now(timezone.utc) + timedelta(hours=1),
        )
        db.add(db_token)
        await db.commit()
        await db.refresh(db_token)

        # リレーションの確認
        assert db_token.staff.id == test_staff.id
        assert db_token.staff.email == test_staff.email


class TestPasswordResetAuditLogModel:
    """PasswordResetAuditLogモデルのユニットテスト"""

    async def test_create_audit_log(self, db: AsyncSession, test_staff: Staff):
        """監査ログの作成"""
        from app.models.staff import PasswordResetAuditLog

        audit_log = PasswordResetAuditLog(
            staff_id=test_staff.id,
            action='requested',
            email=test_staff.email,
            ip_address='192.168.1.1',
            user_agent='Mozilla/5.0',
            success=True
        )
        db.add(audit_log)
        await db.commit()
        await db.refresh(audit_log)

        assert audit_log.id is not None
        assert audit_log.staff_id == test_staff.id
        assert audit_log.action == 'requested'
        assert audit_log.success is True
```

#### 1.1.2 CRUDテスト

**ファイル**: `tests/unit/crud/test_password_reset.py`

```python
import pytest
import uuid
from datetime import datetime, timedelta, timezone
from sqlalchemy.ext.asyncio import AsyncSession

from app.crud import password_reset as crud_password_reset
from app.models.staff import Staff
from app.core.security import hash_reset_token


class TestCRUDPasswordReset:
    """CRUDPasswordResetのユニットテスト"""

    async def test_create_token(self, db: AsyncSession, test_staff: Staff):
        """トークン作成"""
        token = str(uuid.uuid4())
        db_token = await crud_password_reset.create_token(
            db,
            staff_id=test_staff.id,
            token=token,
            expires_in_hours=1
        )
        await db.commit()

        assert db_token.staff_id == test_staff.id
        assert db_token.token_hash == hash_reset_token(token)
        assert db_token.used is False
        assert db_token.expires_at > datetime.now(timezone.utc)

    async def test_get_valid_token_success(self, db: AsyncSession, test_staff: Staff):
        """有効なトークンの取得（成功）"""
        token = str(uuid.uuid4())
        await crud_password_reset.create_token(
            db,
            staff_id=test_staff.id,
            token=token,
            expires_in_hours=1
        )
        await db.commit()

        # 有効なトークンを取得
        db_token = await crud_password_reset.get_valid_token(db, token=token)

        assert db_token is not None
        assert db_token.staff_id == test_staff.id
        assert db_token.used is False

    async def test_get_valid_token_expired(self, db: AsyncSession, test_staff: Staff):
        """期限切れトークンは取得できない"""
        from app.models.staff import PasswordResetToken

        token = str(uuid.uuid4())
        token_hash = hash_reset_token(token)

        # 期限切れトークンを作成
        expired_token = PasswordResetToken(
            staff_id=test_staff.id,
            token_hash=token_hash,
            expires_at=datetime.now(timezone.utc) - timedelta(hours=1),  # 1時間前に期限切れ
            used=False
        )
        db.add(expired_token)
        await db.commit()

        # 期限切れトークンは取得できない
        db_token = await crud_password_reset.get_valid_token(db, token=token)
        assert db_token is None

    async def test_get_valid_token_already_used(self, db: AsyncSession, test_staff: Staff):
        """使用済みトークンは取得できない"""
        from app.models.staff import PasswordResetToken

        token = str(uuid.uuid4())
        token_hash = hash_reset_token(token)

        # 使用済みトークンを作成
        used_token = PasswordResetToken(
            staff_id=test_staff.id,
            token_hash=token_hash,
            expires_at=datetime.now(timezone.utc) + timedelta(hours=1),
            used=True,
            used_at=datetime.now(timezone.utc)
        )
        db.add(used_token)
        await db.commit()

        # 使用済みトークンは取得できない
        db_token = await crud_password_reset.get_valid_token(db, token=token)
        assert db_token is None

    async def test_mark_as_used(self, db: AsyncSession, test_staff: Staff):
        """トークンを使用済みにマーク"""
        token = str(uuid.uuid4())
        db_token = await crud_password_reset.create_token(
            db,
            staff_id=test_staff.id,
            token=token,
            expires_in_hours=1
        )
        await db.commit()

        # トークンを使用済みにマーク
        marked_token = await crud_password_reset.mark_as_used(db, token_id=db_token.id)
        await db.commit()

        assert marked_token is not None
        assert marked_token.used is True
        assert marked_token.used_at is not None

    async def test_mark_as_used_race_condition(self, db: AsyncSession, test_staff: Staff):
        """楽観的ロック: 既に使用済みの場合はNoneを返す"""
        token = str(uuid.uuid4())
        db_token = await crud_password_reset.create_token(
            db,
            staff_id=test_staff.id,
            token=token,
            expires_in_hours=1
        )
        await db.commit()

        # 1回目: 成功
        marked_token1 = await crud_password_reset.mark_as_used(db, token_id=db_token.id)
        await db.commit()
        assert marked_token1 is not None

        # 2回目: 失敗（既に使用済み）
        marked_token2 = await crud_password_reset.mark_as_used(db, token_id=db_token.id)
        assert marked_token2 is None

    async def test_invalidate_existing_tokens(self, db: AsyncSession, test_staff: Staff):
        """既存の未使用トークンを無効化"""
        # 複数のトークンを作成
        token1 = str(uuid.uuid4())
        token2 = str(uuid.uuid4())

        await crud_password_reset.create_token(db, staff_id=test_staff.id, token=token1)
        await crud_password_reset.create_token(db, staff_id=test_staff.id, token=token2)
        await db.commit()

        # 既存トークンを無効化
        count = await crud_password_reset.invalidate_existing_tokens(db, staff_id=test_staff.id)
        await db.commit()

        assert count == 2  # 2つのトークンが無効化された

        # 無効化されたトークンは取得できない
        db_token1 = await crud_password_reset.get_valid_token(db, token=token1)
        db_token2 = await crud_password_reset.get_valid_token(db, token=token2)
        assert db_token1 is None
        assert db_token2 is None

    async def test_delete_expired_tokens(self, db: AsyncSession, test_staff: Staff):
        """期限切れトークンの削除"""
        from app.models.staff import PasswordResetToken

        # 期限切れトークンを作成
        token1 = str(uuid.uuid4())
        expired_token = PasswordResetToken(
            staff_id=test_staff.id,
            token_hash=hash_reset_token(token1),
            expires_at=datetime.now(timezone.utc) - timedelta(hours=1),
            used=False
        )
        db.add(expired_token)

        # 有効なトークンを作成
        token2 = str(uuid.uuid4())
        valid_token = await crud_password_reset.create_token(
            db,
            staff_id=test_staff.id,
            token=token2,
            expires_in_hours=1
        )
        await db.commit()

        # 期限切れトークンを削除
        count = await crud_password_reset.delete_expired_tokens(db)
        await db.commit()

        assert count == 1  # 1つのトークンが削除された

        # 有効なトークンはまだ存在する
        db_token = await crud_password_reset.get_valid_token(db, token=token2)
        assert db_token is not None

    async def test_create_audit_log(self, db: AsyncSession, test_staff: Staff):
        """監査ログの作成"""
        audit_log = await crud_password_reset.create_audit_log(
            db,
            staff_id=test_staff.id,
            action='requested',
            email=test_staff.email,
            ip_address='192.168.1.1',
            user_agent='Mozilla/5.0',
            success=True
        )
        await db.commit()

        assert audit_log.staff_id == test_staff.id
        assert audit_log.action == 'requested'
        assert audit_log.success is True
```

---

### 1.2 統合テスト（E2Eテスト）

**ファイル**: `tests/integration/test_password_reset_flow.py`

```python
import pytest
import uuid
from httpx import AsyncClient
from sqlalchemy.ext.asyncio import AsyncSession

from app.core.config import settings
from app.models.staff import Staff
from app.crud import password_reset as crud_password_reset


class TestPasswordResetFlow:
    """パスワードリセットフロー全体のE2Eテスト"""

    async def test_complete_password_reset_flow(
        self,
        client: AsyncClient,
        db: AsyncSession,
        test_staff: Staff
    ):
        """正常系: パスワードリセットフロー全体"""

        # 1. パスワードリセット要求
        response = await client.post(
            f"{settings.API_V1_STR}/auth/forgot-password",
            json={"email": test_staff.email}
        )
        assert response.status_code == 200
        assert "パスワードリセット用のメールを送信しました" in response.json()["message"]

        # 2. トークンを取得（テストでは直接DBから取得）
        token_obj = await crud_password_reset.get_valid_token(db, token=test_staff.email)
        # 注: 実際のテストではメール送信をモックして、トークンを取得する

        # 3. トークン検証
        response = await client.get(
            f"{settings.API_V1_STR}/auth/verify-reset-token",
            params={"token": "dummy_token"}  # 実際のトークンを使用
        )
        # assert response.status_code == 200
        # assert response.json()["valid"] is True

        # 4. パスワードリセット
        new_password = "NewP@ssw0rd123"
        response = await client.post(
            f"{settings.API_V1_STR}/auth/reset-password",
            json={
                "token": "dummy_token",  # 実際のトークンを使用
                "new_password": new_password
            }
        )
        # assert response.status_code == 200
        # assert "パスワードが正常にリセットされました" in response.json()["message"]

        # 5. 新しいパスワードでログイン確認
        # (ログインテストは別途実装)

    async def test_forgot_password_nonexistent_email(
        self,
        client: AsyncClient
    ):
        """存在しないメールアドレスでも成功レスポンス（セキュリティ）"""
        response = await client.post(
            f"{settings.API_V1_STR}/auth/forgot-password",
            json={"email": "nonexistent@example.com"}
        )
        assert response.status_code == 200
        assert "パスワードリセット用のメールを送信しました" in response.json()["message"]

    async def test_reset_password_expired_token(
        self,
        client: AsyncClient,
        db: AsyncSession,
        test_staff: Staff
    ):
        """期限切れトークンでリセット → エラー"""
        from app.models.staff import PasswordResetToken
        from datetime import datetime, timedelta, timezone
        from app.core.security import hash_reset_token

        # 期限切れトークンを作成
        token = str(uuid.uuid4())
        expired_token = PasswordResetToken(
            staff_id=test_staff.id,
            token_hash=hash_reset_token(token),
            expires_at=datetime.now(timezone.utc) - timedelta(hours=1),
            used=False
        )
        db.add(expired_token)
        await db.commit()

        # パスワードリセット試行
        response = await client.post(
            f"{settings.API_V1_STR}/auth/reset-password",
            json={
                "token": token,
                "new_password": "NewP@ssw0rd123"
            }
        )
        assert response.status_code == 400
        assert "無効または期限切れ" in response.json()["detail"]

    async def test_reset_password_already_used_token(
        self,
        client: AsyncClient,
        db: AsyncSession,
        test_staff: Staff
    ):
        """使用済みトークンでリセット → エラー"""
        # トークンを作成
        token = str(uuid.uuid4())
        db_token = await crud_password_reset.create_token(
            db,
            staff_id=test_staff.id,
            token=token,
            expires_in_hours=1
        )
        await db.commit()

        # 1回目: 成功
        response1 = await client.post(
            f"{settings.API_V1_STR}/auth/reset-password",
            json={
                "token": token,
                "new_password": "NewP@ssw0rd123"
            }
        )
        assert response1.status_code == 200

        # 2回目: 失敗（使用済み）
        response2 = await client.post(
            f"{settings.API_V1_STR}/auth/reset-password",
            json={
                "token": token,
                "new_password": "AnotherP@ssw0rd456"
            }
        )
        assert response2.status_code == 400
        assert "既に使用されています" in response2.json()["detail"]

    async def test_reset_password_weak_password(
        self,
        client: AsyncClient,
        db: AsyncSession,
        test_staff: Staff
    ):
        """パスワード要件を満たさない → バリデーションエラー"""
        token = str(uuid.uuid4())
        await crud_password_reset.create_token(
            db,
            staff_id=test_staff.id,
            token=token,
            expires_in_hours=1
        )
        await db.commit()

        # 弱いパスワード
        response = await client.post(
            f"{settings.API_V1_STR}/auth/reset-password",
            json={
                "token": token,
                "new_password": "weak"
            }
        )
        assert response.status_code == 422  # バリデーションエラー

    # TODO: レート制限のテスト（複数回リクエスト → 429エラー）
```

---

### 1.3 セキュリティテスト

**ファイル**: `tests/security/test_password_reset_security.py`

```python
import pytest
import uuid
from httpx import AsyncClient
from sqlalchemy.ext.asyncio import AsyncSession

from app.models.staff import Staff
from app.crud import password_reset as crud_password_reset
from app.core.security import hash_reset_token


class TestPasswordResetSecurity:
    """パスワードリセットのセキュリティテスト"""

    async def test_token_hash_uniqueness(self, db: AsyncSession, test_staff: Staff):
        """トークンハッシュの一意性"""
        token1 = str(uuid.uuid4())
        token2 = str(uuid.uuid4())

        hash1 = hash_reset_token(token1)
        hash2 = hash_reset_token(token2)

        # 異なるトークンは異なるハッシュ
        assert hash1 != hash2

        # 同じトークンは同じハッシュ
        hash1_duplicate = hash_reset_token(token1)
        assert hash1 == hash1_duplicate

    async def test_token_not_predictable(self):
        """トークンの予測不可能性（UUID v4）"""
        tokens = [str(uuid.uuid4()) for _ in range(100)]

        # 全てのトークンがユニーク
        assert len(tokens) == len(set(tokens))

    async def test_rate_limiting(self, client: AsyncClient, test_staff: Staff):
        """レート制限のテスト（5回/10分）"""
        # TODO: レート制限をモックして、連続リクエストをテスト
        pass

    async def test_user_enumeration_prevention(
        self,
        client: AsyncClient,
        test_staff: Staff
    ):
        """ユーザー存在の推測防止"""
        from app.core.config import settings

        # 存在するメールアドレス
        response1 = await client.post(
            f"{settings.API_V1_STR}/auth/forgot-password",
            json={"email": test_staff.email}
        )

        # 存在しないメールアドレス
        response2 = await client.post(
            f"{settings.API_V1_STR}/auth/forgot-password",
            json={"email": "nonexistent@example.com"}
        )

        # 両方とも同じレスポンス
        assert response1.status_code == response2.status_code == 200
        assert response1.json()["message"] == response2.json()["message"]

    async def test_session_invalidation_after_password_reset(
        self,
        client: AsyncClient,
        db: AsyncSession,
        test_staff: Staff
    ):
        """パスワード変更後の全セッション無効化"""
        # TODO: セッションを作成し、パスワードリセット後に無効化されることを確認
        pass

    async def test_audit_log_records_all_actions(
        self,
        client: AsyncClient,
        db: AsyncSession,
        test_staff: Staff
    ):
        """監査ログの記録確認"""
        from app.models.staff import PasswordResetAuditLog
        from sqlalchemy import select

        # パスワードリセット要求
        await client.post(
            f"{settings.API_V1_STR}/auth/forgot-password",
            json={"email": test_staff.email}
        )

        # 監査ログを確認
        query = select(PasswordResetAuditLog).where(
            PasswordResetAuditLog.staff_id == test_staff.id
        )
        result = await db.execute(query)
        audit_logs = result.scalars().all()

        assert len(audit_logs) > 0
        assert any(log.action == 'requested' for log in audit_logs)

    async def test_sql_injection_prevention(
        self,
        client: AsyncClient
    ):
        """SQLインジェクション対策"""
        # SQLインジェクション試行
        malicious_email = "admin@example.com'; DROP TABLE staffs; --"

        response = await client.post(
            f"{settings.API_V1_STR}/auth/forgot-password",
            json={"email": malicious_email}
        )

        # バリデーションエラーまたは安全に処理される
        assert response.status_code in [200, 422]
```

---

## 2. テスト実行

### 2.1 全テスト実行

```bash
# 全テスト実行
pytest

# カバレッジ付き
pytest --cov=app --cov-report=html

# 特定のテストファイルのみ
pytest tests/unit/crud/test_password_reset.py

# 特定のテストクラスのみ
pytest tests/unit/crud/test_password_reset.py::TestCRUDPasswordReset

# 特定のテストメソッドのみ
pytest tests/unit/crud/test_password_reset.py::TestCRUDPasswordReset::test_create_token
```

### 2.2 カバレッジ目標

- **全体カバレッジ**: 80%以上
- **重要な機能（CRUD、エンドポイント）**: 90%以上
- **セキュリティ関連コード**: 100%

---

## 3. モックとフィクスチャ

### 3.1 テストフィクスチャ

**ファイル**: `tests/conftest.py`

```python
import pytest
import uuid
from sqlalchemy.ext.asyncio import AsyncSession

from app.models.staff import Staff
from app.core.security import get_password_hash


@pytest.fixture
async def test_staff(db: AsyncSession) -> Staff:
    """テスト用スタッフの作成"""
    staff = Staff(
        email="test@example.com",
        hashed_password=get_password_hash("TestP@ssw0rd123"),
        first_name="テスト",
        last_name="太郎",
        is_active=True,
        is_verified=True
    )
    db.add(staff)
    await db.commit()
    await db.refresh(staff)
    return staff


@pytest.fixture
async def test_password_reset_token(
    db: AsyncSession,
    test_staff: Staff
) -> tuple:
    """テスト用パスワードリセットトークンの作成"""
    from app.crud import password_reset as crud_password_reset

    token = str(uuid.uuid4())
    db_token = await crud_password_reset.create_token(
        db,
        staff_id=test_staff.id,
        token=token,
        expires_in_hours=1
    )
    await db.commit()

    return db_token, token  # DBトークンと生のトークンを返す
```

### 3.2 メール送信のモック

```python
import pytest
from unittest.mock import AsyncMock, patch


@pytest.fixture
def mock_send_email():
    """メール送信のモック"""
    with patch('app.core.mail.send_email', new_callable=AsyncMock) as mock:
        yield mock


async def test_forgot_password_sends_email(
    client: AsyncClient,
    test_staff: Staff,
    mock_send_email
):
    """パスワードリセット要求でメールが送信される"""
    response = await client.post(
        f"{settings.API_V1_STR}/auth/forgot-password",
        json={"email": test_staff.email}
    )

    assert response.status_code == 200
    mock_send_email.assert_called_once()
```

---

## Next Steps

Phase 5: 運用フェーズへ進む
- 環境変数設定
- クリーンアップジョブ
- 監視とアラート
- 注意事項とベストプラクティス
