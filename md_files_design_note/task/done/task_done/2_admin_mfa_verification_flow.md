# Issue: 管理者によるMFA有効化後のユーザー初回検証フロー実装

## 🚨 Issue概要

### 問題の発見
管理者メニューの事務所タブでMFA認証を**無効→有効**に変更した際、対象スタッフがログイン不可になる重大な問題が発生。

### 問題の詳細

#### 現象
1. 管理者が事務所タブでスタッフAのMFAを有効化
2. スタッフAがログアウト
3. スタッフAが再ログイン試行
4. **MFA認証画面（TOTPコード入力）に遷移**
5. しかし、スタッフAはまだTOTPアプリに登録していない
6. → **ログイン不可**

#### 根本原因
- 管理者がMFAを有効化すると、`is_mfa_enabled = True` になる
- しかし、ユーザーはまだTOTPシークレットをアプリに登録していない
- ログインシステムは `is_mfa_enabled = True` を見て、TOTP入力を要求する
- ユーザーはコードを生成できないため、ログインできない

## ✅ 解決策: 2段階検証フローの導入

### 設計方針
**`is_mfa_verified_by_user` フラグを追加**して、「管理者が設定した」と「ユーザーが検証完了した」を分離管理

### データベーススキーマ変更

```python
# app/models/staff.py
class Staff(Base):
    # 既存
    is_mfa_enabled = Column(Boolean, default=False)
    # → MFAが有効化されているか（管理者またはユーザーが設定）

    # 新規追加
    is_mfa_verified_by_user = Column(Boolean, default=False)
    # → ユーザーが実際にTOTPアプリで検証を完了したか
```

### フロー設計

#### パターンA: ユーザー自身がMFA設定（既存フロー - 変更なし）
```
1. ユーザーが /mfa/enroll → QRコード取得
2. TOTPアプリに登録
3. /mfa/verify でコード検証成功
   → is_mfa_enabled = True
   → is_mfa_verified_by_user = True  ← 同時にTrue
4. 次回ログイン → 通常のMFA検証フロー
```

#### パターンB: 管理者がMFA設定（新フロー）
```
1. 管理者が /admin/staff/{id}/mfa/enable 実行
   → MFAシークレット・リカバリーコード生成
   → is_mfa_enabled = True
   → is_mfa_verified_by_user = False  ← ここがポイント

2. ユーザーが次回ログイン試行（Email + Password）
   → サーバーが「初回検証が必要」と判定
   → レスポンス:
      {
        "requires_mfa_first_setup": true,
        "temporary_token": "...",
        "qr_code_uri": "otpauth://totp/...",
        "secret_key": "JBSWY3DP...",
        "message": "管理者がMFAを設定しました。"
      }

3. フロントエンド: 初回検証画面へ遷移
   - QRコード表示（スキャン用）
   - シークレットキー表示（手動入力用）
   - TOTPコード入力フォーム
   - 説明テキスト

4. ユーザーがTOTPアプリに登録 → コード入力 → 検証
   → 新エンドポイント POST /auth/mfa/first-time-verify
   → TOTPコード検証成功
   → is_mfa_verified_by_user = True
   → アクセストークン発行
   → ログイン完了

5. 次回以降のログイン
   → 通常のMFA検証フロー
```

#### パターンC: 管理者がMFA無効化 → 再有効化
```
1. 管理者が /admin/staff/{id}/mfa/disable 実行
   → is_mfa_enabled = False
   → is_mfa_verified_by_user = False  ← リセット
   → mfa_secret = None
   → リカバリーコード削除

2. 管理者が再度 /admin/staff/{id}/mfa/enable 実行
   → 新しいMFAシークレット生成
   → is_mfa_enabled = True
   → is_mfa_verified_by_user = False  ← 明示的にFalse

3. ユーザーが次回ログイン
   → パターンBと同じ初回検証フロー
   → 新しいシークレットで再登録が必要
```

### ログイン判定ロジック

```python
# app/api/v1/endpoints/auths.py - login エンドポイント

# Email + Password 認証成功後
if user.is_mfa_enabled:
    if not user.is_mfa_verified_by_user:
        # ケース1: 管理者が設定したが、ユーザーが未検証
        try:
            decrypted_secret = user.get_mfa_secret()
        except ValueError:
            # シークレット復号化失敗 → MFAをリセット
            raise HTTPException(
                status_code=500,
                detail="MFA設定にエラーがあります。管理者に連絡してください。"
            )

        qr_code_uri = generate_totp_uri(user.email, decrypted_secret)
        temp_token = create_temporary_token(user.id)

        return {
            "requires_mfa_first_setup": True,
            "temporary_token": temp_token,
            "qr_code_uri": qr_code_uri,
            "secret_key": decrypted_secret,
            "message": "管理者がMFAを設定しました。以下の情報でTOTPアプリに登録してください。",
        }
    else:
        # ケース2: 通常のMFA検証フロー
        temp_token = create_temporary_token(user.id)
        return {
            "requires_mfa_verification": True,
            "temporary_token": temp_token,
        }
else:
    # ケース3: MFA未設定 → 通常ログイン
    access_token = create_access_token(subject=str(user.id))
    refresh_token = create_refresh_token(subject=str(user.id))
    return {
        "access_token": access_token,
        "refresh_token": refresh_token,
        "token_type": "bearer",
    }
```

## 📋 実装タスク（TDD方式）

### Phase 1: データベース準備 ✅

#### 1.1 Alembicマイグレーション作成
```bash
cd k_back
alembic revision -m "add_is_mfa_verified_by_user_to_staff"
```

#### 1.2 マイグレーションファイル編集

**ファイル**: `alembic/versions/XXXXXXXXXXXX_add_is_mfa_verified_by_user_to_staff.py`

```python
"""add is_mfa_verified_by_user to staff

Revision ID: XXXXXXXXXXXX
Revises: (前回のリビジョンID)
Create Date: 2025-11-19

"""
from typing import Sequence, Union

from alembic import op
import sqlalchemy as sa


# revision identifiers, used by Alembic.
revision: str = 'XXXXXXXXXXXX'
down_revision: Union[str, None] = None  # ← alembic revision コマンドが自動で設定
branch_labels: Union[str, Sequence[str], None] = None
depends_on: Union[str, Sequence[str], None] = None


def upgrade() -> None:
    """
    is_mfa_verified_by_user カラムを staff テーブルに追加
    """
    # 1. カラム追加（デフォルト値を False に設定）
    op.add_column(
        'staff',
        sa.Column(
            'is_mfa_verified_by_user',
            sa.Boolean(),
            nullable=False,
            server_default='false'
        )
    )

    # 2. 既存データの初期化
    # is_mfa_enabled = TRUE の既存ユーザーは、すでに自分で設定済みとみなす
    # → is_mfa_verified_by_user = TRUE に設定
    op.execute("""
        UPDATE staff
        SET is_mfa_verified_by_user = TRUE
        WHERE is_mfa_enabled = TRUE
    """)


def downgrade() -> None:
    """
    is_mfa_verified_by_user カラムを削除
    """
    op.drop_column('staff', 'is_mfa_verified_by_user')
```

#### 1.3 生SQL（参考用）

**Upgrade (適用)**:
```sql
-- 1. カラム追加
ALTER TABLE staff
ADD COLUMN is_mfa_verified_by_user BOOLEAN NOT NULL DEFAULT FALSE;

-- 2. 既存データの初期化
-- is_mfa_enabled = TRUE の既存ユーザーは、すでに自分で設定済みとみなす
UPDATE staff
SET is_mfa_verified_by_user = TRUE
WHERE is_mfa_enabled = TRUE;

-- 3. コメント追加（オプション）
COMMENT ON COLUMN staff.is_mfa_verified_by_user IS 'ユーザーが実際にTOTPアプリで検証を完了したか（管理者設定のみの場合はFalse）';
```

**Downgrade (ロールバック)**:
```sql
-- カラム削除
ALTER TABLE staff
DROP COLUMN is_mfa_verified_by_user;
```

#### 1.4 マイグレーション実行
```bash
# Dockerコンテナ内で実行
docker exec keikakun_app-backend-1 alembic upgrade head

# マイグレーション確認
docker exec keikakun_app-backend-1 alembic current

# ロールバック（必要な場合）
docker exec keikakun_app-backend-1 alembic downgrade -1
```

### Phase 2: モデル修正 ✅

#### 2.1 Staff モデルにカラム追加
`k_back/app/models/staff.py`

```python
class Staff(Base):
    # 既存フィールド
    is_mfa_enabled = Column(Boolean, default=False)

    # 新規追加
    is_mfa_verified_by_user = Column(Boolean, default=False)
```

#### 2.2 disable_mfa メソッド修正
`k_back/app/models/staff.py`

```python
async def disable_mfa(self, db: AsyncSession) -> None:
    """MFAを無効化"""
    self.is_mfa_enabled = False
    self.is_mfa_verified_by_user = False  # ← 追加
    self.mfa_secret = None
    self.mfa_backup_codes_used = 0

    # バックアップコードを削除（明示的なDELETEクエリ）
    from app.models.mfa import MFABackupCode
    stmt = delete(MFABackupCode).where(MFABackupCode.staff_id == self.id)
    await db.execute(stmt)
```

### Phase 3: テスト作成（TDD Red） 🔴

#### 3.1 テストファイル作成
`k_back/tests/api/v1/test_mfa_admin_setup_flow.py`

```python
"""
管理者によるMFA設定後のユーザー初回検証フローのテスト
"""

import pytest
from httpx import AsyncClient
from sqlalchemy.ext.asyncio import AsyncSession

from app.core.security import create_access_token, generate_totp_secret, get_password_hash
from tests.utils import create_random_staff


class TestAdminMFASetupFlow:
    """管理者によるMFA設定フローのテスト"""

    @pytest.mark.asyncio
    async def test_admin_enable_mfa_sets_verified_false(
        self, async_client: AsyncClient, db_session: AsyncSession
    ):
        """
        管理者がMFA有効化すると、is_mfa_verified_by_user = False になる
        """
        # Owner（管理者）を作成
        admin = await create_random_staff(db_session, role="owner")
        admin_token = create_access_token(subject=str(admin.id))

        # 対象スタッフを作成
        target_staff = await create_random_staff(db_session, is_mfa_enabled=False)

        # 管理者がMFA有効化
        response = await async_client.post(
            f"/api/v1/auth/admin/staff/{target_staff.id}/mfa/enable",
            headers={"Authorization": f"Bearer {admin_token}"},
        )

        assert response.status_code == 200
        data = response.json()
        assert "qr_code_uri" in data
        assert "secret_key" in data

        # DBを確認
        await db_session.refresh(target_staff)
        assert target_staff.is_mfa_enabled is True
        assert target_staff.is_mfa_verified_by_user is False  # ← 重要

    @pytest.mark.asyncio
    async def test_login_with_admin_enabled_mfa_requires_first_setup(
        self, async_client: AsyncClient, db_session: AsyncSession
    ):
        """
        管理者が設定したMFAの場合、ログイン時に初回セットアップが必要
        """
        # スタッフを作成（管理者がMFA設定済み）
        password = "testpassword123"
        staff = await create_random_staff(db_session, is_mfa_enabled=True)
        staff.hashed_password = get_password_hash(password)
        staff.set_mfa_secret(generate_totp_secret())
        staff.is_mfa_verified_by_user = False  # 管理者が設定
        await db_session.commit()

        # ログイン試行
        response = await async_client.post(
            "/api/v1/auth/token",
            data={"username": staff.email, "password": password},
        )

        assert response.status_code == 200
        data = response.json()

        # 初回セットアップが必要
        assert data.get("requires_mfa_first_setup") is True
        assert "temporary_token" in data
        assert "qr_code_uri" in data
        assert "secret_key" in data
        assert "message" in data

    @pytest.mark.asyncio
    async def test_first_time_mfa_verify_success(
        self, async_client: AsyncClient, db_session: AsyncSession
    ):
        """
        初回MFA検証が成功すると、is_mfa_verified_by_user = True になる
        """
        from unittest.mock import patch

        # スタッフを作成（管理者がMFA設定済み）
        password = "testpassword123"
        staff = await create_random_staff(db_session, is_mfa_enabled=True)
        staff.hashed_password = get_password_hash(password)
        staff.set_mfa_secret(generate_totp_secret())
        staff.is_mfa_verified_by_user = False
        await db_session.commit()

        # ログインして一時トークン取得
        login_response = await async_client.post(
            "/api/v1/auth/token",
            data={"username": staff.email, "password": password},
        )
        temp_token = login_response.json()["temporary_token"]

        # 初回検証（TOTPコード検証をモック）
        with patch("app.api.v1.endpoints.auths.verify_totp") as mock_verify:
            mock_verify.return_value = True

            verify_response = await async_client.post(
                "/api/v1/auth/mfa/first-time-verify",
                json={
                    "temporary_token": temp_token,
                    "totp_code": "123456",
                },
            )

        assert verify_response.status_code == 200
        verify_data = verify_response.json()

        # アクセストークンが発行される
        assert "access_token" in verify_response.cookies or "access_token" in verify_data
        assert "refresh_token" in verify_data

        # DBを確認
        await db_session.refresh(staff)
        assert staff.is_mfa_verified_by_user is True  # ← 重要

    @pytest.mark.asyncio
    async def test_user_self_setup_sets_both_flags_true(
        self, async_client: AsyncClient, db_session: AsyncSession
    ):
        """
        ユーザー自身がMFA設定すると、両方のフラグがTrueになる
        """
        from unittest.mock import patch

        # スタッフを作成（MFA未設定）
        staff = await create_random_staff(db_session, is_mfa_enabled=False)
        token = create_access_token(subject=str(staff.id))
        headers = {"Authorization": f"Bearer {token}"}

        # MFA登録
        enroll_response = await async_client.post(
            "/api/v1/auth/mfa/enroll",
            headers=headers,
        )
        assert enroll_response.status_code == 200

        # MFA検証（TOTPコード検証をモック）
        with patch("app.services.mfa.verify_totp") as mock_verify:
            mock_verify.return_value = True

            verify_response = await async_client.post(
                "/api/v1/auth/mfa/verify",
                headers=headers,
                json={"totp_code": "123456"},
            )

        assert verify_response.status_code == 200

        # DBを確認
        await db_session.refresh(staff)
        assert staff.is_mfa_enabled is True
        assert staff.is_mfa_verified_by_user is True  # ← 両方True

    @pytest.mark.asyncio
    async def test_admin_disable_mfa_resets_verified_flag(
        self, async_client: AsyncClient, db_session: AsyncSession
    ):
        """
        管理者がMFA無効化すると、is_mfa_verified_by_user も False にリセット
        """
        # Owner（管理者）を作成
        admin = await create_random_staff(db_session, role="owner")
        admin_token = create_access_token(subject=str(admin.id))

        # 対象スタッフを作成（MFA有効化済み）
        target_staff = await create_random_staff(db_session, is_mfa_enabled=True)
        target_staff.set_mfa_secret(generate_totp_secret())
        target_staff.is_mfa_verified_by_user = True
        await db_session.commit()

        # 管理者がMFA無効化
        response = await async_client.post(
            f"/api/v1/auth/admin/staff/{target_staff.id}/mfa/disable",
            headers={"Authorization": f"Bearer {admin_token}"},
        )

        assert response.status_code == 200

        # DBを確認
        await db_session.refresh(target_staff)
        assert target_staff.is_mfa_enabled is False
        assert target_staff.is_mfa_verified_by_user is False  # ← リセット


class TestAdminMFAReEnable:
    """管理者によるMFA再有効化のテスト"""

    @pytest.mark.asyncio
    async def test_admin_reenable_mfa_requires_first_setup_again(
        self, async_client: AsyncClient, db_session: AsyncSession
    ):
        """
        管理者がMFA無効化→再有効化すると、再度初回セットアップが必要
        """
        # Owner（管理者）を作成
        admin = await create_random_staff(db_session, role="owner")
        admin_token = create_access_token(subject=str(admin.id))

        # 対象スタッフを作成
        password = "testpassword123"
        target_staff = await create_random_staff(db_session, is_mfa_enabled=True)
        target_staff.hashed_password = get_password_hash(password)
        target_staff.set_mfa_secret(generate_totp_secret())
        target_staff.is_mfa_verified_by_user = True
        await db_session.commit()

        # 1. 管理者がMFA無効化
        await async_client.post(
            f"/api/v1/auth/admin/staff/{target_staff.id}/mfa/disable",
            headers={"Authorization": f"Bearer {admin_token}"},
        )

        # 2. 管理者が再度MFA有効化
        enable_response = await async_client.post(
            f"/api/v1/auth/admin/staff/{target_staff.id}/mfa/enable",
            headers={"Authorization": f"Bearer {admin_token}"},
        )
        assert enable_response.status_code == 200

        # DBを確認
        await db_session.refresh(target_staff)
        assert target_staff.is_mfa_enabled is True
        assert target_staff.is_mfa_verified_by_user is False  # ← 再度False

        # 3. スタッフがログイン試行
        login_response = await async_client.post(
            "/api/v1/auth/token",
            data={"username": target_staff.email, "password": password},
        )

        assert login_response.status_code == 200
        login_data = login_response.json()

        # 初回セットアップが必要（新しいシークレットで再登録）
        assert login_data.get("requires_mfa_first_setup") is True
```

#### 3.2 テスト実行（Red - 失敗を確認）
```bash
cd k_back
docker exec keikakun_app-backend-1 pytest tests/api/v1/test_mfa_admin_setup_flow.py -v
```

### Phase 4: バックエンド実装（TDD Green） 🟢

#### 4.1 管理者MFA有効化エンドポイント修正
`k_back/app/api/v1/endpoints/mfa.py` - `admin_enable_staff_mfa`

```python
# MFAシークレットとリカバリーコードを生成
secret = generate_totp_secret()
recovery_codes = generate_recovery_codes(count=10)

# MFAを有効化（暗号化とリカバリーコード保存を含む）
await target_staff.enable_mfa(db, secret, recovery_codes)

# 管理者による有効化なので、ユーザー検証は未完了
target_staff.is_mfa_verified_by_user = False  # ← 追加

db.add(target_staff)
await db.commit()
```

#### 4.2 ユーザー自身のMFA検証エンドポイント修正
`k_back/app/api/v1/endpoints/mfa.py` - `verify_mfa`

```python
# 検証成功後、エンドポイント層でMFAを有効化してコミット
current_user.is_mfa_enabled = True
current_user.is_mfa_verified_by_user = True  # ← 追加
await db.commit()

return {"message": ja.MFA_VERIFICATION_SUCCESS}
```

#### 4.3 ログインエンドポイント修正
`k_back/app/api/v1/endpoints/auths.py` - `login`

```python
# パスワード認証成功後
if user.is_mfa_enabled:
    if not user.is_mfa_verified_by_user:
        # 管理者が設定したが、ユーザーが未検証
        decrypted_secret = user.get_mfa_secret()
        qr_code_uri = generate_totp_uri(user.email, decrypted_secret)
        temp_token = create_temporary_token(user.id, session_type="mfa_pending")

        return {
            "requires_mfa_first_setup": True,
            "temporary_token": temp_token,
            "qr_code_uri": qr_code_uri,
            "secret_key": decrypted_secret,
            "message": "管理者がMFAを設定しました。以下の情報でTOTPアプリに登録してください。",
        }
    else:
        # 通常のMFA検証フロー
        temp_token = create_temporary_token(user.id, session_type="mfa_pending")
        return {
            "requires_mfa_verification": True,
            "temporary_token": temp_token,
        }
```

#### 4.4 初回検証エンドポイント作成
`k_back/app/api/v1/endpoints/auths.py` - 新規追加

```python
@router.post(
    "/mfa/first-time-verify",
    status_code=status.HTTP_200_OK,
    summary="MFA初回検証（管理者設定後）",
    description="管理者が設定したMFAをユーザーが初回検証します。",
)
async def verify_mfa_first_time(
    *,
    db: AsyncSession = Depends(deps.get_db),
    verify_data: schemas.MFAVerifyRequest,
) -> dict:
    """
    管理者が設定したMFAをユーザーが初回検証

    - **temporary_token**: ログイン時に発行された一時トークン
    - **totp_code**: TOTPアプリで生成された6桁のコード
    """
    # 一時トークンを検証
    try:
        payload = jwt.decode(
            verify_data.temporary_token,
            settings.SECRET_KEY,
            algorithms=[ALGORITHM],
        )
        user_id = payload.get("sub")
        session_type = payload.get("session_type")

        if session_type != "mfa_pending":
            raise HTTPException(
                status_code=status.HTTP_401_UNAUTHORIZED,
                detail=ja.MFA_INVALID_TEMP_TOKEN,
            )
    except JWTError:
        raise HTTPException(
            status_code=status.HTTP_401_UNAUTHORIZED,
            detail=ja.MFA_INVALID_TEMP_TOKEN,
        )

    # ユーザーを取得
    user = await crud.staff.get(db, id=uuid.UUID(user_id))
    if not user:
        raise HTTPException(
            status_code=status.HTTP_401_UNAUTHORIZED,
            detail=ja.MFA_INVALID_TEMP_TOKEN,
        )

    # MFAシークレットを復号化
    try:
        decrypted_secret = user.get_mfa_secret()
    except ValueError:
        raise HTTPException(
            status_code=status.HTTP_500_INTERNAL_SERVER_ERROR,
            detail="MFA設定にエラーがあります。管理者に連絡してください。",
        )

    # TOTPコードを検証
    if not verify_totp(secret=decrypted_secret, token=verify_data.totp_code):
        raise HTTPException(
            status_code=status.HTTP_401_UNAUTHORIZED,
            detail=ja.MFA_INVALID_CODE,
        )

    # 検証成功 → is_mfa_verified_by_user = True
    user.is_mfa_verified_by_user = True
    await db.commit()

    # アクセストークン・リフレッシュトークン発行
    access_token = create_access_token(subject=str(user.id))
    refresh_token = create_refresh_token(subject=str(user.id))

    # Cookie に access_token を設定
    response = JSONResponse(
        content={
            "refresh_token": refresh_token,
            "token_type": "bearer",
            "message": "MFA初回検証に成功しました。",
        }
    )
    response.set_cookie(
        key="access_token",
        value=access_token,
        httponly=True,
        secure=True,
        samesite="lax",
        max_age=settings.ACCESS_TOKEN_EXPIRE_MINUTES * 60,
    )

    return response
```

#### 4.5 テスト実行（Green - 成功を確認）
```bash
cd k_back
docker exec keikakun_app-backend-1 pytest tests/api/v1/test_mfa_admin_setup_flow.py -v
```

### Phase 5: フロントエンド実装 🎨

#### 5.1 型定義追加
`k_front/types/auth.ts`

```typescript
export interface MFAFirstSetupResponse {
  requires_mfa_first_setup: true;
  temporary_token: string;
  qr_code_uri: string;
  secret_key: string;
  message: string;
}
```

#### 5.2 初回検証画面コンポーネント作成
`k_front/app/auth/mfa-first-setup/page.tsx`

```typescript
'use client';

import { useState, useEffect } from 'react';
import { useRouter, useSearchParams } from 'next/navigation';
import { authApi } from '@/lib/auth';
import Image from 'next/image';

export default function MFAFirstSetupPage() {
  const router = useRouter();
  const searchParams = useSearchParams();

  const [qrCodeUri, setQrCodeUri] = useState('');
  const [secretKey, setSecretKey] = useState('');
  const [temporaryToken, setTemporaryToken] = useState('');
  const [message, setMessage] = useState('');
  const [totpCode, setTotpCode] = useState('');
  const [error, setError] = useState('');
  const [loading, setLoading] = useState(false);

  useEffect(() => {
    const qr = searchParams.get('qr_code_uri');
    const secret = searchParams.get('secret_key');
    const token = searchParams.get('temporary_token');
    const msg = searchParams.get('message');

    if (!qr || !secret || !token) {
      router.push('/auth/login');
      return;
    }

    setQrCodeUri(qr);
    setSecretKey(secret);
    setTemporaryToken(token);
    setMessage(msg || '');
  }, [searchParams, router]);

  const handleVerify = async (e: React.FormEvent) => {
    e.preventDefault();
    setError('');
    setLoading(true);

    try {
      await authApi.verifyMFAFirstTime({
        temporary_token: temporaryToken,
        totp_code: totpCode,
      });

      router.push('/dashboard');
    } catch (err: any) {
      setError(err.response?.data?.detail || 'MFA検証に失敗しました。');
    } finally {
      setLoading(false);
    }
  };

  return (
    <div className="min-h-screen flex items-center justify-center bg-gray-50">
      <div className="max-w-md w-full bg-white rounded-lg shadow-lg p-8">
        <h1 className="text-2xl font-bold text-center mb-4">
          MFA初回セットアップ
        </h1>

        {message && (
          <div className="mb-6 p-4 bg-blue-50 border border-blue-200 rounded">
            <p className="text-sm text-blue-800">{message}</p>
          </div>
        )}

        <div className="mb-6">
          <h2 className="text-lg font-semibold mb-2">1. QRコードをスキャン</h2>
          <p className="text-sm text-gray-600 mb-4">
            Google Authenticatorなどのアプリで以下のQRコードをスキャンしてください。
          </p>
          <div className="flex justify-center">
            <Image
              src={`https://api.qrserver.com/v1/create-qr-code/?size=200x200&data=${encodeURIComponent(qrCodeUri)}`}
              alt="QR Code"
              width={200}
              height={200}
            />
          </div>
        </div>

        <div className="mb-6">
          <h2 className="text-lg font-semibold mb-2">2. シークレットキー（手動入力用）</h2>
          <div className="bg-gray-100 p-3 rounded font-mono text-sm break-all">
            {secretKey}
          </div>
        </div>

        <form onSubmit={handleVerify} className="mb-4">
          <h2 className="text-lg font-semibold mb-2">3. 認証コードを入力</h2>
          <input
            type="text"
            value={totpCode}
            onChange={(e) => setTotpCode(e.target.value)}
            placeholder="6桁のコード"
            maxLength={6}
            className="w-full px-4 py-2 border rounded mb-4"
            required
          />

          {error && (
            <div className="mb-4 p-3 bg-red-50 border border-red-200 rounded">
              <p className="text-sm text-red-800">{error}</p>
            </div>
          )}

          <button
            type="submit"
            disabled={loading || totpCode.length !== 6}
            className="w-full bg-blue-600 text-white py-2 rounded hover:bg-blue-700 disabled:bg-gray-400"
          >
            {loading ? '検証中...' : '検証して続ける'}
          </button>
        </form>
      </div>
    </div>
  );
}
```

#### 5.3 ログインフロー修正
`k_front/app/auth/login/page.tsx` - ログイン成功後の処理

```typescript
// ログインAPIレスポンス後
if (data.requires_mfa_first_setup) {
  // 初回セットアップが必要
  const params = new URLSearchParams({
    qr_code_uri: data.qr_code_uri,
    secret_key: data.secret_key,
    temporary_token: data.temporary_token,
    message: data.message,
  });
  router.push(`/auth/mfa-first-setup?${params.toString()}`);
  return;
}

if (data.requires_mfa_verification) {
  // 通常のMFA検証フロー
  const params = new URLSearchParams({
    temporary_token: data.temporary_token,
  });
  router.push(`/auth/mfa-verify?${params.toString()}`);
  return;
}

// 通常ログイン成功
router.push('/dashboard');
```

#### 5.4 APIクライアント追加
`k_front/lib/auth.ts`

```typescript
verifyMFAFirstTime: (data: {
  temporary_token: string;
  totp_code: string;
}): Promise<{ message: string }> => {
  return http.post(`${API_V1_PREFIX}/auth/mfa/first-time-verify`, data);
},
```

### Phase 6: 動作確認・検証 ✅

#### 6.1 全テスト実行
```bash
cd k_back
docker exec keikakun_app-backend-1 pytest tests/api/v1/test_mfa*.py -v
```

#### 6.2 エンドツーエンドテスト
1. 管理者でログイン
2. 事務所タブでスタッフAのMFAを有効化
3. QRコード・シークレットキー・リカバリーコードを保存（表示のみ）
4. スタッフAでログアウト
5. スタッフAで再ログイン
6. 初回セットアップ画面が表示される
7. QRコードをTOTPアプリでスキャン
8. 6桁のコードを入力
9. 検証成功 → ダッシュボードへ遷移
10. 再度ログアウト
11. 再ログイン → 通常のMFA検証画面へ遷移

## 📊 期待される動作

| ケース | 操作 | is_mfa_enabled | is_mfa_verified_by_user | 次回ログイン |
|--------|------|----------------|-------------------------|--------------|
| 1. ユーザー自身が設定 | /mfa/enroll + verify | True | True | 通常MFA検証 |
| 2. 管理者が有効化（初回） | /admin/.../enable | True | False | **初回検証フロー** |
| 3. 管理者が無効化 | /admin/.../disable | False | False | 通常ログイン |
| 4. 管理者が再有効化 | /admin/.../enable | True | False | **初回検証フロー（新シークレット）** |

## 🔐 セキュリティ考慮事項

- ✅ 管理者が設定しただけではログインできない（ユーザー検証必須）
- ✅ TOTPシークレットの暗号化保存（既存実装を維持）
- ✅ 初回検証時も一時トークンによる認証が必要
- ✅ 検証成功後のみ `is_mfa_verified_by_user = True` に更新
- ✅ MFA無効化時に両方のフラグをリセット
- ✅ 再有効化時に新しいシークレットを生成し、再検証を強制

## 📝 注意事項

### マイグレーション実行時
- 既存の `is_mfa_enabled = True` のユーザーは、自分で設定済みとみなす
- → `is_mfa_verified_by_user = True` に初期化

### 既存ユーザーへの影響
- 既にMFAを有効化しているユーザー: 影響なし（次回ログインでも通常のMFA検証）
- MFA未設定のユーザー: 影響なし

### 管理者への注意
- MFA有効化後、対象スタッフにQRコード・シークレットキー・リカバリーコードを共有する必要がある
- スタッフが初回ログイン時にTOTPアプリに登録するまで、実質的にログインできない状態になる
