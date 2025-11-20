# Phase 3: バックエンド実装フェーズ

パスワードリセット機能のCRUD操作、エンドポイント、メール送信の実装

---

## 1. トークンハッシュ化ヘルパー関数

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

---

## 2. CRUD 操作

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

### 2.1 CRUDのエクスポート

`app/crud/__init__.py` に追加：

```python
from .crud_password_reset import password_reset
```

---

## 3. メール送信

### 3.1 メール送信関数

`app/core/mail.py` に追加：

```python
from app.core.config import settings


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

### 3.2 メールテンプレート

#### 3.2.1 パスワードリセットメール

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

#### 3.2.2 パスワード変更完了メール

`app/templates/email/password_changed.html`:

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
        .success {
            background-color: #d4edda;
            border-left: 4px solid #28a745;
            padding: 12px;
            margin: 20px 0;
        }
        .success p {
            margin: 0;
            color: #155724;
        }
        .footer {
            margin-top: 30px;
            padding-top: 20px;
            border-top: 1px solid #eeeeee;
            font-size: 12px;
            color: #888888;
        }
    </style>
</head>
<body>
    <div class="container">
        <h1>{{ title }}</h1>

        <p>{{ staff_name }} 様</p>

        <div class="success">
            <p>
                <strong>パスワードが正常に変更されました。</strong>
            </p>
        </div>

        <p>
            アカウントのセキュリティのため、既存のセッションは全て無効化されました。<br>
            新しいパスワードで再度ログインしてください。
        </p>

        <p>
            もしこの変更に心当たりがない場合は、至急システム管理者にお問い合わせください。
        </p>

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

## 4. ヘルパー関数

リクエストからIPアドレスとUser-Agentを取得するヘルパー関数：

`app/api/v1/endpoints/auths.py` または `app/utils/request_helpers.py` に追加：

```python
from fastapi import Request


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

---

## 5. エンドポイント実装

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


router = APIRouter()


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

---

## 6. 実装のポイント

### 6.1 トランザクション管理

**重要な原則**:
1. DB変更をコミット
2. その後にメール送信
3. メール送信失敗してもロールバックしない

```python
# 正しい実装
await db.commit()  # 1. DBコミット
await send_password_reset_email(...)  # 2. メール送信

# 間違った実装
await send_password_reset_email(...)  # NG: コミット前にメール送信
await db.commit()
```

### 6.2 楽観的ロック

トークンの再利用を防ぐため、楽観的ロックを実装：

```python
# used=Falseの条件付きで更新
stmt = (
    update(PasswordResetToken)
    .where(
        and_(
            PasswordResetToken.id == token_id,
            PasswordResetToken.used == False  # 楽観的ロック
        )
    )
    .values(used=True, used_at=now)
    .returning(PasswordResetToken)
)
```

### 6.3 監査ログ

全てのアクションを記録：

```python
# 成功時
await crud_password_reset.create_audit_log(
    db,
    staff_id=staff.id,
    action='completed',
    email=staff.email,
    ip_address=ip_address,
    user_agent=user_agent,
    success=True
)

# 失敗時
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
```

---

## Next Steps

Phase 4: テストフェーズへ進む
- ユニットテスト
- 統合テスト
- セキュリティテスト
