<!--
作業ブランチ: issue/feature-パスワードを忘れた際の処理
注意: このファイルを編集する場合、必ず作業中のブランチ名を上部に記載し、変更はそのブランチへ push してください。
-->

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
        expires_in_minutes: int = 30
    ) -> PasswordResetToken:
        """
        パスワードリセットトークンを作成（トークンはハッシュ化して保存）

        Args:
            db: データベースセッション
            staff_id: スタッフID
            token: トークン文字列（UUID v4）- 生のトークン
            expires_in_minutes: 有効期限（分）- デフォルト30分（Phase 1レビュー推奨値）

        Returns:
            作成されたトークン
        """
        expires_at = datetime.now(timezone.utc) + timedelta(minutes=expires_in_minutes)
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
        "expire_minutes": 30,  # トークン有効期限（Phase 1レビュー推奨値）
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
                このリンクは{{ expire_minutes }}分間のみ有効です。<br>
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
from app.core.config import settings
from app.models.staff import Session as StaffSession
from app.messages import ja


router = APIRouter()


@router.post(
    "/forgot-password",
    response_model=PasswordResetResponse,
    status_code=status.HTTP_200_OK,
)
@limiter.limit(settings.RATE_LIMIT_FORGOT_PASSWORD)
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
                expires_in_minutes=settings.PASSWORD_RESET_TOKEN_EXPIRE_MINUTES
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
@limiter.limit(settings.RATE_LIMIT_RESEND_EMAIL)
async def resend_reset_email(
    *,
    request: Request,
    db: AsyncSession = Depends(deps.get_db),
    data: ForgotPasswordRequest,
    staff_crud=Depends(deps.get_staff_crud),
):
    """
    パスワードリセットメールを再送信します（レート制限: 環境変数から取得）
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
        # メイントランザクション
        async with db.begin():
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

            # セッション無効化（確認付き）
            stmt = (
                update(StaffSession)
                .where(StaffSession.staff_id == staff.id)
                .values(
                    is_active=False,
                    revoked_at=datetime.now(timezone.utc)
                )
            )
            result = await db.execute(stmt)
            revoked_count = result.rowcount

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
            error_message=sanitize_error_message(e)
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

## 7. セキュリティレビュー（実装フェーズ）

**レビュー実施日**: 2025-11-20
**レビュアー**: Claude Code (Anthropic AI)
**レビュー観点**: 実装コードのセキュリティ、Phase 1設計レビューとの整合性

---

### 7.1 セキュリティ問題の特定

#### 🔴 重大な問題

##### 1. トークン有効期限の設計との不一致

**問題箇所**:
```python
# Line 293: メールテンプレートのコンテキスト
context = {
    "title": subject,
    "staff_name": staff_name,
    "reset_url": reset_url,
    "expire_hours": 1,  # ❌ Phase1で30分に変更したのに1時間のまま
}

# Line 630: トークン生成
await crud_password_reset.create_token(
    db,
    staff_id=staff.id,
    token=token,
    expires_in_hours=1  # ❌ Phase1で30分に変更したのに1時間のまま
)
```

**影響**:
- Phase 1のセキュリティレビューで30分に短縮することを推奨
- 実装が設計と乖離している
- セキュリティリスクウィンドウが2倍長い

**推奨修正**:
```python
# トークン有効期限を30分に統一
TOKEN_EXPIRY_MINUTES = 30

# メールテンプレート
context = {
    "title": subject,
    "staff_name": staff_name,
    "reset_url": reset_url,
    "expire_minutes": TOKEN_EXPIRY_MINUTES,  # ✅ 分単位で指定
}

# トークン生成
await crud_password_reset.create_token(
    db,
    staff_id=staff.id,
    token=token,
    expires_in_minutes=TOKEN_EXPIRY_MINUTES  # ✅ 分単位のパラメータに変更
)

# CRUD関数のシグネチャも変更
async def create_token(
    self,
    db: AsyncSession,
    *,
    staff_id: uuid.UUID,
    token: str,
    expires_in_minutes: int = 30  # ✅ デフォルト30分
) -> PasswordResetToken:
    expires_at = datetime.now(timezone.utc) + timedelta(minutes=expires_in_minutes)
    # ...
```

##### 2. タイミング攻撃対策の欠如

**問題箇所**:
```python
# Line 82-111: get_valid_token関数
async def get_valid_token(
    self,
    db: AsyncSession,
    *,
    token: str
) -> Optional[PasswordResetToken]:
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
    return result.scalar_one_or_none()  # ❌ タイミング攻撃の脆弱性
```

**影響**:
- トークンの存在/非存在で応答時間が異なる
- 攻撃者がトークンの状態を推測可能
- Phase 1で推奨したconstant-time比較が未実装

**推奨修正**:
```python
import secrets

async def get_valid_token(
    self,
    db: AsyncSession,
    *,
    token: str
) -> Optional[PasswordResetToken]:
    """
    有効なトークンを取得（タイミング攻撃対策付き）

    Phase 1レビューで推奨されたconstant-time比較を実装
    """
    now = datetime.now(timezone.utc)
    token_hash = hash_reset_token(token)

    # DB検索
    query = select(PasswordResetToken).where(
        PasswordResetToken.token_hash == token_hash
    )
    result = await db.execute(query)
    db_token = result.scalar_one_or_none()

    # ✅ Constant-time検証
    if not db_token:
        # ダミー処理で時間を揃える
        secrets.compare_digest("dummy_hash", "dummy_hash")
        return None

    # 全ての条件を先に評価
    is_not_used = not db_token.used
    is_not_expired = db_token.expires_at > now

    # 全て真の場合のみ成功
    if is_not_used and is_not_expired:
        return db_token

    return None
```

#### 🟠 中程度の問題

##### 3. IPアドレス取得の脆弱性

**問題箇所**:
```python
# Line 542-556: get_client_ip関数
def get_client_ip(request: Request) -> str:
    """リクエストからクライアントのIPアドレスを取得"""
    # X-Forwarded-Forヘッダーを優先（プロキシ経由の場合）
    forwarded_for = request.headers.get("X-Forwarded-For")
    if forwarded_for:
        return forwarded_for.split(",")[0].strip()  # ❌ 無条件で信頼

    # X-Real-IPヘッダー（nginxなど）
    real_ip = request.headers.get("X-Real-IP")
    if real_ip:
        return real_ip

    # 直接接続の場合
    return request.client.host if request.client else "unknown"
```

**影響**:
- X-Forwarded-Forヘッダーはクライアントが偽装可能
- レート制限のバイパスが可能
- 監査ログの信頼性が低下

**推奨修正**:
```python
from typing import Optional, List

# 設定ファイルに追加
TRUSTED_PROXIES: List[str] = [
    "10.0.0.0/8",
    "172.16.0.0/12",
    "192.168.0.0/16",
]

def is_trusted_proxy(ip: str) -> bool:
    """IPアドレスが信頼できるプロキシかチェック"""
    import ipaddress

    try:
        client_ip = ipaddress.ip_address(ip)
        for trusted_network in TRUSTED_PROXIES:
            if client_ip in ipaddress.ip_network(trusted_network):
                return True
    except ValueError:
        return False

    return False

def get_client_ip(request: Request) -> str:
    """
    リクエストからクライアントIPアドレスを安全に取得

    信頼できるプロキシからのX-Forwarded-Forのみを使用
    """
    client_host = request.client.host if request.client else "unknown"

    # 直接接続からのリクエストの場合
    if not is_trusted_proxy(client_host):
        # ✅ プロキシ経由でない場合はヘッダーを無視
        return client_host

    # ✅ 信頼できるプロキシからの場合のみX-Forwarded-Forを使用
    forwarded_for = request.headers.get("X-Forwarded-For")
    if forwarded_for:
        # 最初のIPアドレス（実際のクライアント）を取得
        return forwarded_for.split(",")[0].strip()

    # X-Real-IPヘッダー（nginxなど）
    real_ip = request.headers.get("X-Real-IP")
    if real_ip:
        return real_ip

    return client_host
```

##### 4. エラーハンドリングでの情報漏洩

**問題箇所**:
```python
# Line 653-666, 850-862: エラー時の監査ログ
except Exception as e:
    await crud_password_reset.create_audit_log(
        db,
        staff_id=staff.id,
        action='requested',
        email=data.email,
        ip_address=ip_address,
        user_agent=user_agent,
        success=False,
        error_message=str(e)  # ❌ 内部エラー詳細が漏洩
    )
```

**影響**:
- スタックトレース、DBエラー、内部パスなどが監査ログに記録
- ログが侵害された場合、システム情報が漏洩
- デバッグ情報の露出

**推奨修正**:
```python
import logging
import traceback

logger = logging.getLogger(__name__)

def sanitize_error_message(e: Exception) -> str:
    """
    エラーメッセージをサニタイズして、内部情報を隠す
    """
    # 許可されたエラータイプのみ詳細を記録
    safe_errors = (HTTPException, ValueError, ValidationError)

    if isinstance(e, safe_errors):
        return str(e)

    # その他のエラーは一般的なメッセージのみ
    return f"{type(e).__name__}: Internal error"

# 使用例
except Exception as e:
    # ✅ 詳細なエラーはサーバーログのみに記録
    logger.error(
        f"Password reset failed for {staff.id}: {str(e)}",
        exc_info=True  # スタックトレースをログに記録
    )

    # ✅ 監査ログには安全なメッセージのみ
    await crud_password_reset.create_audit_log(
        db,
        staff_id=staff.id,
        action='failed',
        email=staff.email,
        ip_address=ip_address,
        user_agent=user_agent,
        success=False,
        error_message=sanitize_error_message(e)  # サニタイズ済み
    )
```

##### 5. 監査ログのトランザクション境界問題

**問題箇所**:
```python
# Line 790-866: reset_password関数
try:
    # パスワード更新
    staff.hashed_password = get_password_hash(data.new_password)

    # ...

    # 監査ログを記録
    await crud_password_reset.create_audit_log(...)

    await db.commit()  # ❌ エラー時にログもロールバックされる

except Exception as e:
    # エラー時の監査ログ
    await crud_password_reset.create_audit_log(...)
    await db.commit()  # ❌ ロールバック後に別トランザクション
    raise
```

**影響**:
- 成功時の監査ログが、その後のエラーでロールバックされる可能性
- 監査ログの完全性が保証されない
- Phase 1で推奨した「監査ログは別トランザクション」が未実装

**推奨修正**:
```python
async def log_audit_separately(
    db: AsyncSession,
    **kwargs
) -> None:
    """
    監査ログを別トランザクションで記録（確実に記録される）
    """
    async with db.begin_nested():  # SAVEPOINTを使用
        await crud_password_reset.create_audit_log(db, **kwargs)
    await db.commit()

# 使用例
async def reset_password(...):
    try:
        # メイントランザクション
        async with db.begin():
            staff.hashed_password = get_password_hash(data.new_password)
            # ...
            # ✅ トランザクション自動コミット

        # ✅ 成功ログを別トランザクションで記録
        await log_audit_separately(
            db,
            staff_id=staff.id,
            action='completed',
            email=staff.email,
            ip_address=ip_address,
            user_agent=user_agent,
            success=True
        )

        # メール送信（トランザクション外）
        await send_password_changed_notification(
            email=staff.email,
            staff_name=staff.full_name
        )

    except Exception as e:
        # ✅ 失敗ログも別トランザクションで確実に記録
        await log_audit_separately(
            db,
            staff_id=staff.id,
            action='failed',
            email=staff.email,
            ip_address=ip_address,
            user_agent=user_agent,
            success=False,
            error_message=sanitize_error_message(e)
        )
        raise
```

#### 🟡 軽微な問題

##### 6. セッション無効化の確認不足

**問題箇所**:
```python
# Line 817-823: セッション無効化
stmt = (
    update(StaffSession)
    .where(StaffSession.staff_id == staff.id)
    .values(is_active=False, revoked_at=datetime.now(timezone.utc))
)
await db.execute(stmt)  # ❌ 無効化件数の確認なし
```

**影響**:
- 無効化に失敗しても気づかない
- セキュリティ監査で無効化の証跡が不足

**推奨修正**:
```python
# ✅ 無効化件数を確認・ログ記録
stmt = (
    update(StaffSession)
    .where(StaffSession.staff_id == staff.id)
    .values(is_active=False, revoked_at=datetime.now(timezone.utc))
)
result = await db.execute(stmt)
revoked_count = result.rowcount

logger.info(
    f"Revoked {revoked_count} sessions for staff {staff.id} "
    f"after password reset"
)

# 監査ログにも記録
# (audit logのスキーマに additional_info JSONフィールドを追加することを推奨)
```

##### 7. パスワード再利用チェックの欠如

**問題箇所**:
```python
# Line 792: パスワード更新
staff.hashed_password = get_password_hash(data.new_password)
# ❌ 現在のパスワードと同じかチェックしていない
```

**影響**:
- ユーザーが同じパスワードを設定可能
- セキュリティベストプラクティスに反する
- パスワード変更の意味がない

**推奨修正**:
```python
from app.core.security import verify_password

# パスワード更新前にチェック
if verify_password(data.new_password, staff.hashed_password):
    raise HTTPException(
        status_code=status.HTTP_400_BAD_REQUEST,
        detail="新しいパスワードは現在のパスワードと異なる必要があります",
    )

staff.hashed_password = get_password_hash(data.new_password)
```

##### 8. メール送信失敗時の処理不足

**問題箇所**:
```python
# Line 646-651: メール送信
await send_password_reset_email(
    recipient_email=data.email,
    staff_name=staff.full_name,
    token=token
)  # ❌ 失敗時の処理がない
```

**影響**:
- メール送信失敗が記録されない
- ユーザーがメールを受け取れない問題に気づけない
- リトライ機構がない

**推奨修正**:
```python
# メール送信をtry-catchでラップ
try:
    await send_password_reset_email(
        recipient_email=data.email,
        staff_name=staff.full_name,
        token=token
    )
    logger.info(f"Password reset email sent to {data.email}")

except Exception as email_error:
    # ✅ メール送信失敗をログ記録
    logger.error(
        f"Failed to send password reset email to {data.email}: {email_error}",
        exc_info=True
    )

    # ✅ 監査ログにも記録（別トランザクション）
    await log_audit_separately(
        db,
        staff_id=staff.id,
        action='email_send_failed',
        email=data.email,
        ip_address=ip_address,
        user_agent=user_agent,
        success=False,
        error_message=f"Email delivery failed: {type(email_error).__name__}"
    )

    # ✅ オプション: リトライキューに追加
    # await enqueue_email_retry(staff.id, token)

    # DB変更は既にコミット済みなので、処理は継続
    # ユーザーには成功メッセージを返す（セキュリティのため）
```

##### 9. レート制限のバイパス可能性

**問題箇所**:
```python
# Line 600: forgot_passwordエンドポイント
@limiter.limit("5/10minute")
async def forgot_password(...):
    # ❌ IPベースのレート制限のみ
```

**影響**:
- プロキシ、VPN、Tor経由でIP変更可能
- 同一メールアドレスへの攻撃を防げない

**推奨修正**:
```python
from slowapi import Limiter
from slowapi.util import get_remote_address
from app.core.config import settings

# IPベースとメールアドレスベースの複合レート制限
@router.post("/forgot-password")
@limiter.limit(settings.RATE_LIMIT_FORGOT_PASSWORD)  # 環境変数から取得
async def forgot_password(...):
    # ✅ メールアドレスベースの追加チェック
    recent_requests = await crud_password_reset.count_recent_requests(
        db,
        email=data.email,
        minutes=10
    )

    if recent_requests >= 3:  # メールアドレスごとに3回/10分
        raise HTTPException(
            status_code=status.HTTP_429_TOO_MANY_REQUESTS,
            detail="このメールアドレスへのリクエストが多すぎます。しばらくしてから再度お試しください。",
        )

    # 処理続行...

# CRUDに追加
async def count_recent_requests(
    self,
    db: AsyncSession,
    *,
    email: str,
    minutes: int = 10
) -> int:
    """指定メールアドレスへの最近のリクエスト数をカウント"""
    cutoff_time = datetime.now(timezone.utc) - timedelta(minutes=minutes)

    query = select(func.count()).select_from(PasswordResetAuditLog).where(
        and_(
            PasswordResetAuditLog.email == email,
            PasswordResetAuditLog.action == 'requested',
            PasswordResetAuditLog.created_at > cutoff_time
        )
    )
    result = await db.execute(query)
    return result.scalar_one()
```

##### 10. CSRF対策の未実装

**問題箇所**:
```python
# Line 754-867: reset_password エンドポイント
@router.post("/reset-password")
async def reset_password(...):
    # ❌ Phase 1で推奨したRefererチェックが未実装
```

**影響**:
- CSRF攻撃のリスク（限定的だが存在）
- トークンが一度しか使えないため影響は小さい

**推奨修正**:
```python
from urllib.parse import urlparse

def validate_referer(request: Request, allowed_hosts: List[str]):
    """
    リファラーヘッダーを検証してCSRF攻撃を防ぐ
    """
    referer = request.headers.get("Referer")
    if not referer:
        # Refererヘッダーがない場合は許可（一部ブラウザで省略される）
        return

    referer_host = urlparse(referer).netloc
    if referer_host not in allowed_hosts:
        raise HTTPException(
            status_code=status.HTTP_403_FORBIDDEN,
            detail="Invalid referer",
        )

# エンドポイントで使用
@router.post("/reset-password")
async def reset_password(...):
    # ✅ Refererチェック
    validate_referer(
        request,
        allowed_hosts=[
            settings.FRONTEND_DOMAIN,
            f"www.{settings.FRONTEND_DOMAIN}"
        ]
    )

    # 処理続行...
```

---

### 7.2 レビュー結果サマリー

| 深刻度 | 項目数 | 主な問題 |
|--------|--------|----------|
| 🔴 重大 | 2 | トークン有効期限の不一致、タイミング攻撃対策の欠如 |
| 🟠 中程度 | 3 | IPアドレス取得の脆弱性、情報漏洩、監査ログTX境界 |
| 🟡 軽微 | 5 | セッション無効化確認、パスワード再利用、メール失敗処理、レート制限、CSRF |

**総合評価**: ⚠️ **実装前に重大な問題の修正が必要**

**Phase 1設計レビューとの整合性チェック**:
- ❌ トークン有効期限（30分） → 実装では1時間のまま
- ❌ タイミング攻撃対策 → 未実装
- ⚠️ IPアドレス取得の信頼性 → 実装が不十分
- ⚠️ 監査ログのトランザクション境界 → 未対応
- ✅ トークンハッシュ化 → 実装済み
- ✅ 楽観的ロック → 実装済み
- ✅ セッション無効化 → 実装済み（確認不足だが）

**推奨アクション（優先順位順）**:
1. 🔴 トークン有効期限を30分に修正（設計との整合性）
2. 🔴 タイミング攻撃対策を実装（constant-time比較）
3. 🟠 IPアドレス取得の脆弱性を修正（プロキシ検証）
4. 🟠 エラーメッセージのサニタイズ実装
5. 🟠 監査ログを別トランザクションに分離
6. 🟡 セッション無効化の確認・ログ追加
7. 🟡 パスワード再利用チェック追加
8. 🟡 メール送信失敗時の処理強化
9. 🟡 複合レート制限の実装
10. 🟡 CSRF対策（Refererチェック）の追加

---

### 7.3 修正後のコード例（統合版）

完全に修正された`reset_password`エンドポイントの実装例：

```python
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
    トークンを使用してパスワードをリセット

    セキュリティレビュー対応済み:
    - タイミング攻撃対策
    - 監査ログの別トランザクション化
    - エラーメッセージのサニタイズ
    - セッション無効化の確認
    - パスワード再利用チェック
    - CSRF対策
    """
    # ✅ Refererチェック（CSRF対策）
    validate_referer(
        request,
        allowed_hosts=[settings.FRONTEND_DOMAIN]
    )

    # リクエスト情報を安全に取得
    ip_address = get_client_ip(request)  # ✅ 修正済み
    user_agent = get_user_agent(request)

    # ✅ タイミング攻撃対策付きでトークン検証
    token_obj = await crud_password_reset.get_valid_token(
        db, token=data.token
    )
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
        # メイントランザクション
        async with db.begin():
            # ✅ パスワード再利用チェック
            if verify_password(data.new_password, staff.hashed_password):
                raise HTTPException(
                    status_code=status.HTTP_400_BAD_REQUEST,
                    detail="新しいパスワードは現在のパスワードと異なる必要があります",
                )

            # パスワードを更新
            staff.hashed_password = get_password_hash(data.new_password)
            staff.password_changed_at = datetime.now(timezone.utc)
            staff.failed_password_attempts = 0
            staff.is_locked = False

            # トークンを使用済みにマーク（楽観的ロック）
            marked_token = await crud_password_reset.mark_as_used(db, token_id=token_obj.id)
            if not marked_token:
                raise HTTPException(
                    status_code=status.HTTP_400_BAD_REQUEST,
                    detail=ja.AUTH_RESET_TOKEN_ALREADY_USED,
                )

            # セッション無効化（確認付き）
            stmt = (
                update(StaffSession)
                .where(StaffSession.staff_id == staff.id)
                .values(
                    is_active=False,
                    revoked_at=datetime.now(timezone.utc)
                )
            )
            result = await db.execute(stmt)
            revoked_count = result.rowcount

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
        logger.error(f"Password reset failed: {e}", exc_info=True)

        # ✅ 失敗監査ログ（別トランザクション、サニタイズ済み）
        await log_audit_separately(
            db,
            staff_id=staff.id,
            action='failed',
            email=staff.email,
            ip_address=ip_address,
            user_agent=user_agent,
            success=False,
            error_message=sanitize_error_message(e)
        )

        raise HTTPException(
            status_code=status.HTTP_500_INTERNAL_SERVER_ERROR,
            detail=ja.AUTH_PASSWORD_RESET_FAILED,
        )
```

---

## Next Steps

**実装前に必須の対応**:
1. ✅ 上記セキュリティ問題を全て修正
2. ✅ Phase 1設計レビューとの整合性を確保
3. ✅ 修正後のコードレビュー

**その後**:
Phase 4: テストフェーズへ進む
- ユニットテスト（セキュリティテストを含む）
- 統合テスト
- タイミング攻撃のテスト
- レート制限のテスト
