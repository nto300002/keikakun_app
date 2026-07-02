# セキュリティ改善アクションアイテム

**作成日**: 2025-11-24
**対象**: メッセージAPI機能

このドキュメントは、セキュリティレビューで発見された改善項目を優先度順にまとめたものです。

---

## 🔥 優先度: 高（即座に対応推奨）

### 1. レート制限の実装

**関連ファイル**: `k_back/app/api/v1/endpoints/messages.py`
**工数見積**: 4時間
**OWASP**: A04:2021 - Insecure Design

#### 実装内容

```bash
pip install fastapi-limiter redis
```

```python
# k_back/app/main.py
from fastapi_limiter import FastAPILimiter
import redis.asyncio as redis

@app.on_event("startup")
async def startup():
    redis_connection = redis.from_url("redis://localhost:6379", encoding="utf8")
    await FastAPILimiter.init(redis_connection)
```

```python
# k_back/app/api/v1/endpoints/messages.py
from fastapi_limiter.depends import RateLimiter

# 個別メッセージ送信: 10回/分
@router.post("/personal", dependencies=[Depends(RateLimiter(times=10, seconds=60))])

# 一斉通知送信: 3回/時
@router.post("/announcement", dependencies=[Depends(RateLimiter(times=3, seconds=3600))])

# 受信箱取得: 30回/分
@router.get("/inbox", dependencies=[Depends(RateLimiter(times=30, seconds=60))])

# 既読化: 100回/分
@router.post("/{message_id}/read", dependencies=[Depends(RateLimiter(times=100, seconds=60))])
```

#### テスト方法

```bash
# 連続リクエストでレート制限を確認
for i in {1..15}; do
  curl -X POST http://localhost:8000/api/v1/messages/personal \
    -H "Cookie: access_token=..." \
    -H "Content-Type: application/json" \
    -d '{"title":"test","content":"test","recipient_staff_ids":["..."]}'
  echo "Request $i"
done
```

---

### 2. CSRF対策の実装

**関連ファイル**: `k_back/app/api/v1/endpoints/auths.py`（ログイン処理）
**工数見積**: 3時間
**OWASP**: A01:2021 - Broken Access Control

#### 実装内容

##### 2.1 SameSite属性の設定

```python
# k_back/app/api/v1/endpoints/auths.py

# Cookie設定時
response.set_cookie(
    key="access_token",
    value=access_token,
    httponly=True,
    secure=True,  # HTTPS環境でTrue
    samesite="Lax",  # または "Strict"
    max_age=settings.ACCESS_TOKEN_EXPIRE_MINUTES * 60
)
```

##### 2.2 CSRFトークンの実装（オプション）

```bash
pip install fastapi-csrf-protect
```

```python
# k_back/app/core/config.py
class Settings(BaseSettings):
    ...
    CSRF_SECRET_KEY: str = "your-csrf-secret-key"
```

```python
# k_back/app/main.py
from fastapi_csrf_protect import CsrfProtect
from fastapi_csrf_protect.exceptions import CsrfProtectError

@CsrfProtect.load_config
def get_csrf_config():
    return {
        "secret_key": settings.CSRF_SECRET_KEY,
        "cookie_name": "csrf_token",
        "cookie_path": "/",
        "cookie_domain": None,
        "cookie_secure": True,
        "cookie_samesite": "Lax"
    }

@app.exception_handler(CsrfProtectError)
def csrf_protect_exception_handler(request: Request, exc: CsrfProtectError):
    return JSONResponse(
        status_code=exc.status_code,
        content={"detail": exc.message}
    )
```

```python
# k_back/app/api/v1/endpoints/messages.py
from fastapi_csrf_protect import CsrfProtect

@router.post("/personal")
async def send_personal_message(
    csrf_protect: CsrfProtect = Depends(),
    ...
):
    await csrf_protect.validate_csrf(request)
    ...
```

#### テスト方法

```bash
# CSRFトークンなしでリクエスト（403エラーになるべき）
curl -X POST http://localhost:8000/api/v1/messages/personal \
  -H "Cookie: access_token=..." \
  -H "Content-Type: application/json" \
  -d '{"title":"test","content":"test","recipient_staff_ids":["..."]}'

# CSRFトークンありでリクエスト（成功するべき）
curl -X POST http://localhost:8000/api/v1/messages/personal \
  -H "Cookie: access_token=...; csrf_token=..." \
  -H "X-CSRF-Token: ..." \
  -H "Content-Type: application/json" \
  -d '{"title":"test","content":"test","recipient_staff_ids":["..."]}'
```

---

### 3. アカウント有効性チェックの追加

**関連ファイル**: `k_back/app/api/v1/endpoints/messages.py:58-74`
**工数見積**: 2時間
**OWASP**: A01:2021 - Broken Access Control

#### 実装内容

```python
# k_back/app/api/v1/endpoints/messages.py:58-74

# 受信者が存在し、同じ事務所に所属しているか確認
for recipient_id in message_in.recipient_staff_ids:
    recipient = await crud.staff.get(db=db, id=recipient_id)
    if not recipient:
        raise HTTPException(
            status_code=status.HTTP_400_BAD_REQUEST,
            detail="指定された受信者の一部が無効です"  # IDを含めない
        )

    # 🆕 アカウント有効性チェックを追加
    if hasattr(recipient, 'is_deactivated') and recipient.is_deactivated:
        raise HTTPException(
            status_code=status.HTTP_400_BAD_REQUEST,
            detail="無効なアカウントには送信できません"
        )

    # 🆕 削除済みチェックを追加
    if hasattr(recipient, 'deleted_at') and recipient.deleted_at:
        raise HTTPException(
            status_code=status.HTTP_400_BAD_REQUEST,
            detail="削除済みアカウントには送信できません"
        )

    # 受信者が同じ事務所に所属しているか確認
    recipient_office_ids = [
        assoc.office_id for assoc in recipient.office_associations
    ]
    if sender_office_id not in recipient_office_ids:
        raise HTTPException(
            status_code=status.HTTP_403_FORBIDDEN,
            detail="異なる事務所のスタッフには送信できません"
        )
```

#### テストケース追加

```python
# k_back/tests/api/v1/test_messages_api.py

async def test_send_message_to_deactivated_user(
    async_client: AsyncClient,
    db: AsyncSession,
    employee_user_factory,
    office_factory
):
    """無効化されたユーザーへのメッセージ送信は失敗する"""
    office = await office_factory()
    sender = await employee_user_factory(office=office)
    recipient = await employee_user_factory(office=office, is_deactivated=True)

    # 認証
    access_token = create_access_token(
        str(sender.id),
        timedelta(minutes=settings.ACCESS_TOKEN_EXPIRE_MINUTES)
    )
    async_client.cookies.set("access_token", access_token)

    # メッセージ送信
    response = await async_client.post(
        "/api/v1/messages/personal",
        json={
            "title": "テストメッセージ",
            "content": "テスト本文",
            "recipient_staff_ids": [str(recipient.id)],
            "priority": "normal"
        }
    )

    assert response.status_code == 400
    assert "無効なアカウント" in response.json()["detail"]
```

---

## 🟡 優先度: 中（1-2週間以内に対応）

### 4. 監査ログの実装

**関連ファイル**: `k_back/app/services/message_audit_service.py`（新規作成）
**工数見積**: 6時間

#### 実装内容

```python
# k_back/app/services/message_audit_service.py（新規作成）
from uuid import UUID
from fastapi import Request
from sqlalchemy.ext.asyncio import AsyncSession
from app.models.message import MessageAuditLog

class MessageAuditService:
    @staticmethod
    async def log_action(
        db: AsyncSession,
        staff_id: UUID,
        message_id: UUID,
        action: str,
        request: Request,
        success: bool = True,
        error_message: str = None
    ):
        """メッセージ操作を監査ログに記録"""
        audit_log = MessageAuditLog(
            staff_id=staff_id,
            message_id=message_id,
            action=action,
            ip_address=request.client.host if request.client else None,
            user_agent=request.headers.get("user-agent"),
            success=success,
            error_message=error_message
        )
        db.add(audit_log)
        await db.flush()

message_audit_service = MessageAuditService()
```

```python
# k_back/app/api/v1/endpoints/messages.py

from app.services.message_audit_service import message_audit_service

@router.post("/personal", response_model=MessageDetailResponse)
async def send_personal_message(
    *,
    db: AsyncSession = Depends(deps.get_db),
    current_user: Staff = Depends(deps.get_current_user),
    message_in: MessagePersonalCreate,
    request: Request  # 🆕 Requestを追加
):
    try:
        # メッセージ作成処理...
        message = await crud_message.create_personal_message(db=db, obj_in=message_data)
        await db.commit()

        # 🆕 監査ログ記録
        await message_audit_service.log_action(
            db=db,
            staff_id=current_user.id,
            message_id=message.id,
            action="sent",
            request=request
        )
        await db.commit()

        return response_dict

    except Exception as e:
        # 🆕 失敗も記録
        await message_audit_service.log_action(
            db=db,
            staff_id=current_user.id,
            message_id=None,
            action="sent",
            request=request,
            success=False,
            error_message=str(e)
        )
        await db.commit()
        raise
```

---

### 5. タイムゾーンの統一

**関連ファイル**: `k_back/app/crud/crud_message.py:247, 374`
**工数見積**: 1時間

#### 実装内容

```python
# k_back/app/crud/crud_message.py

from datetime import datetime, timezone

# 修正前
recipient.read_at = datetime.now()

# 修正後
recipient.read_at = datetime.now(timezone.utc)

# 修正前
.values(is_read=True, read_at=datetime.now())

# 修正後
.values(is_read=True, read_at=datetime.now(timezone.utc))
```

#### テスト方法

```python
# タイムゾーン情報が含まれているか確認
async def test_read_at_has_timezone(
    async_client: AsyncClient,
    db: AsyncSession,
    employee_user_factory,
    message_factory
):
    recipient = await employee_user_factory()
    message = await message_factory(recipient_ids=[recipient.id])

    # 既読化
    # ...

    # タイムゾーン情報の確認
    stmt = select(MessageRecipient).where(
        MessageRecipient.message_id == message.id,
        MessageRecipient.recipient_staff_id == recipient.id
    )
    result = await db.execute(stmt)
    recipient_record = result.scalar_one()

    assert recipient_record.read_at.tzinfo is not None
    assert recipient_record.read_at.tzinfo == timezone.utc
```

---

### 6. エラーメッセージの改善

**関連ファイル**: `k_back/app/api/v1/endpoints/messages.py`
**工数見積**: 1時間

#### 実装内容

```python
# 修正前
detail=f"受信者が見つかりません: {recipient_id}"

# 修正後
detail="指定された受信者の一部が無効です"

# 修正前（一斉通知）
detail="送信先のスタッフが存在しません"

# 修正後
detail="送信可能なスタッフが存在しません"
```

---

## 🟢 優先度: 低（時間があれば対応）

### 7. ページネーション上限の見直し

**関連ファイル**: `k_back/app/api/v1/endpoints/messages.py:170`
**工数見積**: 0.5時間

#### 実装内容

```python
# 修正前
limit: int = Query(20, ge=1, le=100, description="取得数上限")

# 修正後
limit: int = Query(20, ge=1, le=50, description="取得数上限（最大50）")
```

---

### 8. フロントエンドセキュリティガイドの作成

**関連ファイル**: `md_files_design_note/task/2_messages/frontend_security_guide.md`（新規作成）
**工数見積**: 2時間

#### 実装内容

```markdown
# メッセージAPI フロントエンド利用ガイド

## XSS対策

### 禁止事項

❌ メッセージ内容を直接HTMLとして表示しない

\`\`\`jsx
// React - 絶対にやってはいけない
<div dangerouslySetInnerHTML={{ __html: message.content }} />

// Vue - 絶対にやってはいけない
<div v-html="message.content"></div>
\`\`\`

### 推奨事項

✅ テキストとして表示する

\`\`\`jsx
// React - 推奨
<div>{message.content}</div>

// Vue - 推奨
<div>{{ message.content }}</div>
\`\`\`

✅ サニタイズライブラリを使用する（必要な場合のみ）

\`\`\`jsx
import DOMPurify from 'dompurify';

const sanitizedContent = DOMPurify.sanitize(message.content);
<div dangerouslySetInnerHTML={{ __html: sanitizedContent }} />
\`\`\`

## CSRF対策

### CSRFトークンの取得と送信

\`\`\`javascript
// CSRFトークンを取得
const csrfToken = document.cookie
  .split('; ')
  .find(row => row.startsWith('csrf_token='))
  ?.split('=')[1];

// リクエストヘッダーに含める
fetch('/api/v1/messages/personal', {
  method: 'POST',
  headers: {
    'Content-Type': 'application/json',
    'X-CSRF-Token': csrfToken
  },
  credentials: 'include',  // Cookieを含める
  body: JSON.stringify(messageData)
});
\`\`\`
\`\`\`

---

## 実装スケジュール（推奨）

| 週 | タスク | 担当者 | 工数 |
|----|--------|--------|------|
| Week 1 | 1. レート制限の実装 | Backend Dev | 4h |
| Week 1 | 2. CSRF対策（SameSite） | Backend Dev | 2h |
| Week 1 | 3. アカウント有効性チェック | Backend Dev | 2h |
| Week 2 | 2. CSRF対策（トークン） | Backend Dev | 1h |
| Week 2 | 4. 監査ログの実装 | Backend Dev | 6h |
| Week 2 | 5. タイムゾーンの統一 | Backend Dev | 1h |
| Week 2 | 6. エラーメッセージの改善 | Backend Dev | 1h |
| Week 3 | 7. ページネーション上限の見直し | Backend Dev | 0.5h |
| Week 3 | 8. フロントエンドガイド作成 | Tech Lead | 2h |

**合計工数**: 19.5時間（約3日）

---

## 実装後の確認事項

### セキュリティテスト

- [ ] レート制限の動作確認（連続リクエストで429エラー）
- [ ] CSRF攻撃の防止確認（トークンなしで403エラー）
- [ ] 無効アカウントへの送信拒否確認（400エラー）
- [ ] 監査ログの記録確認（DB確認）
- [ ] タイムゾーン情報の確認（UTC）
- [ ] エラーメッセージの情報漏洩確認（IDが含まれていない）

### パフォーマンステスト

- [ ] レート制限がパフォーマンスに悪影響を与えていないか
- [ ] 監査ログ記録が遅延を引き起こしていないか

### 既存機能の回帰テスト

- [ ] 全テストケースが通過（28/28）
- [ ] 既存の正常系フローが影響を受けていない

---

**作成日**: 2025-11-24
**最終更新**: 2025-11-24
