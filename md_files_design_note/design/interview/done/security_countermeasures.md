# けいかくん - セキュリティ対策ドキュメント

## 概要

本ドキュメントでは、けいかくんアプリケーションにおける主要なセキュリティリスクとその対策について説明します。

---

## 1. セッションハイジャック対策

### リスク概要
攻撃者がCookieを盗むことで、正当なユーザーになりすまし、アカウントに不正アクセスする可能性があります。特に、セッションIDが保存されたCookieが狙われることが多いです。

### 実装されている対策

#### 1.1 HTTPOnly Cookie属性
**実装箇所**: `k_back/app/api/v1/endpoints/auths.py`

```python
cookie_options = {
    "key": "access_token",
    "value": access_token,
    "httponly": True,  # JavaScriptからのアクセスを防止
    "secure": True if is_production else False,
    "samesite": cookie_samesite or ("none" if is_production else "lax"),
    "max_age": session_duration,
    "domain": cookie_domain
}
```

**効果**: JavaScriptからCookieへのアクセスを完全にブロックし、XSSによるCookie窃取を防止

#### 1.2 Secure Cookie属性（本番環境）
**実装箇所**: `k_back/app/api/v1/endpoints/auths.py`

```python
"secure": True if is_production else False
```

**効果**: HTTPS接続でのみCookieを送信し、中間者攻撃（MITM）によるCookie傍受を防止

#### 1.3 SameSite Cookie属性
**実装箇所**: `k_back/app/api/v1/endpoints/auths.py`

```python
"samesite": cookie_samesite or ("none" if is_production else "lax")
```

**効果**:
- `lax`: 開発環境で同一サイトからのリクエストのみCookieを送信
- `none`: 本番環境でクロスサイトリクエストを許可（Secure属性と併用必須）

#### 1.4 JWT（JSON Web Token）による認証
**実装箇所**: `k_back/app/core/security.py`

```python
def create_access_token(
    subject: str | Any,
    expires_delta: timedelta = None,
    session_type: str = "normal"
) -> str:
    now = datetime.now(timezone.utc)
    if expires_delta:
        expire = now + expires_delta
    else:
        expire = now + timedelta(minutes=ACCESS_TOKEN_EXPIRE_MINUTES)

    to_encode = {
        "exp": expire,
        "sub": str(subject),
        "iat": now,
        "session_type": session_type
    }
    encoded_jwt = jwt.encode(to_encode, secret_key, algorithm=ALGORITHM)
    return encoded_jwt
```

**特徴**:
- **アルゴリズム**: HS256（HMAC with SHA-256）
- **有効期限**: 通常7日間（`ACCESS_TOKEN_EXPIRE_MINUTES`で設定可能）
- **リフレッシュトークン**: 7日間（`REFRESH_TOKEN_EXPIRE_DAYS`）
- **セッションタイプ**: `normal`, `remember_me`を区別

**効果**:
- トークンベース認証によりサーバー側のセッション管理が不要
- トークンの有効期限により、盗まれたトークンの悪用期間を制限
- 署名検証により改ざんを検出

#### 1.5 トークンローテーション
**実装箇所**: `k_back/app/api/v1/endpoints/auths.py`

リフレッシュトークン使用時に新しいアクセストークンを発行し、古いトークンを無効化する仕組みを実装。

**効果**: トークンが盗まれた場合でも、次回のリフレッシュ時に攻撃者のセッションを無効化

#### 1.6 多要素認証（MFA / 2FA）
**実装箇所**: `k_back/app/core/security.py`

```python
def generate_totp_secret() -> str:
    """TOTP用のシークレットキーを生成"""
    return pyotp.random_base32()

def verify_totp(secret: str, token: str) -> bool:
    """TOTPトークンを検証"""
    totp = pyotp.TOTP(secret)
    return totp.verify(token, valid_window=1)
```

**特徴**:
- TOTP（Time-based One-Time Password）方式
- 30秒ごとに変わる6桁のコード
- 暗号化されたシークレットキーをDBに保存（Fernet暗号化）

**効果**: パスワードが漏洩してもワンタイムパスワードなしではログイン不可

#### 1.7 パスワードセキュリティ
**実装箇所**: `k_back/app/core/security.py`

```python
pwd_context = CryptContext(schemes=["bcrypt"], deprecated="auto")

def get_password_hash(password: str) -> str:
    """パスワードをハッシュ化"""
    return pwd_context.hash(password)

def verify_password(plain_password: str, hashed_password: str) -> bool:
    """パスワードを検証"""
    return pwd_context.verify(plain_password, hashed_password)
```

**特徴**:
- bcryptアルゴリズム使用（コスト係数調整可能）
- レインボーテーブル攻撃に耐性
- Have I Been Pwned APIによる漏洩パスワードチェック

**効果**: DBが漏洩してもパスワードの平文は取得不可

---

## 2. クロスサイトスクリプティング（XSS）対策

### リスク概要
悪意のあるスクリプトがWebサイトに注入されると、Cookieの内容が盗まれる危険性があります。これにより、攻撃者はユーザーのセッション情報を取得し、悪用することができます。

### 実装されている対策

#### 2.1 HTTPOnly Cookie（再掲）
**実装箇所**: `k_back/app/api/v1/endpoints/auths.py`

```python
"httponly": True
```

**効果**: XSSによるJavaScriptからのCookie窃取を完全に防止

#### 2.2 入力バリデーション（Pydantic）
**実装箇所**: すべてのAPIエンドポイント（`app/api/v1/endpoints/*`）

```python
# 例: ユーザー作成のバリデーション
class UserCreate(BaseModel):
    email: EmailStr
    password: str
    name: str

    @validator('name')
    def validate_name(cls, v):
        if len(v) > 100:
            raise ValueError('名前は100文字以内で入力してください')
        return v
```

**効果**:
- 型チェックにより不正な入力を拒否
- 文字列長制限により過度に長い入力を防止
- EmailStrによるメールアドレス形式検証

#### 2.3 出力エスケープ（HTMLサニタイゼーション）
**実装箇所**: `k_back/app/main.py`

```python
import html

@app.exception_handler(RequestValidationError)
async def validation_exception_handler(request: Request, exc: RequestValidationError):
    """
    バリデーションエラーのカスタムハンドラー
    XSS攻撃対策として、エラーレスポンスから危険な文字をサニタイズする
    """
    def sanitize_value(value):
        """危険な文字をHTMLエスケープ"""
        if isinstance(value, str):
            return html.escape(value)
        elif isinstance(value, dict):
            return {k: sanitize_value(v) for k, v in value.items()}
        elif isinstance(value, list):
            return [sanitize_value(v) for v in value]
        elif isinstance(value, Exception):
            return str(value)
        return value

    # エラー詳細をサニタイズ
    errors = []
    for error in exc.errors():
        sanitized_error = {}
        for key, value in error.items():
            if key == "input":
                sanitized_error[key] = sanitize_value(value)
            elif key == "ctx" and isinstance(value, dict):
                sanitized_ctx = {}
                for ctx_key, ctx_value in value.items():
                    if isinstance(ctx_value, Exception):
                        sanitized_ctx[ctx_key] = str(ctx_value)
                    else:
                        sanitized_ctx[ctx_key] = sanitize_value(ctx_value)
                sanitized_error[key] = sanitized_ctx
            else:
                sanitized_error[key] = value
        errors.append(sanitized_error)

    return JSONResponse(
        status_code=422,
        content={"detail": errors}
    )
```

**効果**: エラーメッセージに含まれる可能性のあるスクリプトタグをエスケープし、反射型XSSを防止

#### 2.4 Content-Security-Policy（CSP）ヘッダー
**実装箇所**: フロントエンド（Next.js）の`next.config.js`

Next.jsのデフォルトセキュリティヘッダーにより、以下のようなCSPが設定されます：

```javascript
// next.config.jsで設定可能
const securityHeaders = [
  {
    key: 'Content-Security-Policy',
    value: "default-src 'self'; script-src 'self' 'unsafe-eval' 'unsafe-inline'; ..."
  }
]
```

**効果**: ブラウザ側でスクリプトの実行元を制限し、インラインスクリプトの実行を制御

#### 2.5 CORS設定による外部ドメイン制限
**実装箇所**: `k_back/app/main.py`

```python
# 環境に応じてCORS設定を変更
is_production = os.getenv("ENVIRONMENT") == "production"

if is_production:
    # 本番環境: 必要最小限のオリジン・メソッド・ヘッダーのみ許可
    allowed_origins = [
        "https://keikakun-front.vercel.app",
        "https://www.keikakun.com",
        "https://api.keikakun.com",
    ]
    allowed_methods = ["GET", "POST", "PUT", "PATCH", "DELETE", "OPTIONS"]
    allowed_headers = [
        "Content-Type",
        "Authorization",
        "X-Requested-With",
        "Accept",
        "X-CSRF-Token",
    ]
else:
    # 開発環境: localhost + 本番確認用
    allowed_origins = [
        "http://localhost:3000",
        "https://keikakun-front.vercel.app",
    ]
```

**効果**: 許可されたオリジンからのリクエストのみを受け付け、不正なドメインからのAPIアクセスを防止

#### 2.6 レート制限
**実装箇所**: `k_back/app/core/limiter.py`

```python
from slowapi import Limiter
from slowapi.util import get_remote_address

limiter = Limiter(key_func=get_remote_address)
```

**実装例**: `k_back/app/api/v1/endpoints/auths.py`

```python
@router.post("/forgot-password")
@limiter.limit(settings.RATE_LIMIT_FORGOT_PASSWORD)  # 例: "5/hour"
async def forgot_password(request: Request, ...):
    ...
```

**効果**: XSS攻撃による大量リクエストやブルートフォース攻撃を防止

---

## 3. クロスサイトリクエストフォージェリ（CSRF）対策

### リスク概要
攻撃者がユーザーのブラウザを利用して不正なリクエストを送信することで、ユーザーの意図しない操作を実行させることができます。Cookieが自動的に送信されるため、特に危険です。

### 実装されている対策

#### 3.1 CSRF保護（Double Submit Cookie Pattern）
**実装箇所**: `k_back/app/core/csrf.py`

```python
from fastapi_csrf_protect import CsrfProtect
from pydantic import BaseModel

class CsrfSettings(BaseModel):
    secret_key: str
    cookie_name: str = "fastapi-csrf-token"
    header_name: str = "X-CSRF-Token"
    cookie_samesite: str = "lax"
    cookie_secure: bool  # 本番環境でTrue
    cookie_httponly: bool = False  # JavaScriptからアクセス可能にする必要がある
    cookie_domain: str | None = None

@CsrfProtect.load_config
def get_csrf_config():
    return CsrfSettings(
        secret_key=settings.SECRET_KEY,
        cookie_secure=settings.COOKIE_SECURE,
        cookie_domain=settings.COOKIE_DOMAIN
    )
```

**実装パターン**:
1. サーバーがCSRFトークンをCookieとして発行（`fastapi-csrf-token`）
2. クライアントがトークンを読み取り、リクエストヘッダー（`X-CSRF-Token`）に含める
3. サーバーがCookieのトークンとヘッダーのトークンを比較検証

**効果**: 攻撃者のサイトからのリクエストではCSRFトークンを取得できないため、不正なリクエストを防止

#### 3.2 CSRF検証ミドルウェア
**実装箇所**: `k_back/app/core/csrf.py`

```python
async def validate_csrf_token(request: Request, csrf_protect: CsrfProtect):
    """
    CSRF保護の検証を行う
    Bearer認証の場合はCSRF検証をスキップ
    Cookie認証の場合のみCSRF検証を実施
    """
    # Authorization ヘッダーをチェック
    auth_header = request.headers.get("Authorization")

    # Bearer認証の場合はCSRF検証をスキップ
    if auth_header and auth_header.startswith("Bearer "):
        return

    # Cookie認証の場合のみCSRF検証を実施
    access_token_cookie = request.cookies.get("access_token")
    if access_token_cookie:
        await csrf_protect.validate_csrf(request)
```

**効果**:
- Cookie認証では必ずCSRF検証を実施
- Bearer認証（API通信）ではCSRF検証をスキップ（同一オリジンポリシーで保護）

#### 3.3 CSRFエラーハンドリング
**実装箇所**: `k_back/app/main.py`

```python
from fastapi_csrf_protect.exceptions import CsrfProtectError

@app.exception_handler(CsrfProtectError)
async def csrf_protect_exception_handler(request: Request, exc: CsrfProtectError):
    """CSRF保護のエラーハンドラー"""
    return JSONResponse(
        status_code=403,
        content={"detail": f"CSRF token validation failed: {exc.message}"}
    )
```

**効果**: CSRF検証失敗時に適切なエラーレスポンスを返し、攻撃を検知

#### 3.4 SameSite Cookie属性（再掲）
**実装箇所**: `k_back/app/api/v1/endpoints/auths.py`

```python
"samesite": cookie_samesite or ("none" if is_production else "lax")
```

**効果**:
- `lax`: GET以外のクロスサイトリクエストでCookieが送信されないため、CSRF攻撃を大幅に軽減
- `none`: 本番環境でクロスオリジンが必要な場合でも、CSRF保護と併用することで安全性を確保

#### 3.5 ステート変更操作のメソッド制限
**実装方針**: すべてのAPIエンドポイント

```python
# 読み取り操作: GET
@router.get("/users/{user_id}")
async def get_user(...):
    ...

# 作成操作: POST
@router.post("/users")
async def create_user(...):
    ...

# 更新操作: PUT / PATCH
@router.put("/users/{user_id}")
async def update_user(...):
    ...

# 削除操作: DELETE
@router.delete("/users/{user_id}")
async def delete_user(...):
    ...
```

**効果**:
- GETリクエストでは状態変更を行わない設計により、単純なCSRF攻撃を防止
- POST/PUT/PATCH/DELETEでは必ずCSRF検証が必要

#### 3.6 Refererヘッダー検証（オプション）
**実装箇所**: 必要に応じてカスタムミドルウェアで実装可能

```python
# 実装例（現在は未使用）
async def validate_referer(request: Request):
    referer = request.headers.get("referer")
    if referer and not referer.startswith(settings.FRONTEND_URL):
        raise HTTPException(status_code=403, detail="Invalid referer")
```

**効果**: リクエストの送信元を検証し、不正なサイトからのリクエストを拒否

---

## 4. その他のセキュリティ対策

### 4.1 環境変数による機密情報管理
**実装箇所**: `k_back/app/core/config.py`

```python
class Settings(BaseSettings):
    SECRET_KEY: str
    DATABASE_URL: str
    STRIPE_SECRET_KEY: str
    AWS_SECRET_ACCESS_KEY: str
    # ... その他の機密情報

    class Config:
        env_file = ".env"
        case_sensitive = True
```

**効果**: 機密情報をコードにハードコーディングせず、環境変数で管理

### 4.2 監査ログ（Audit Log）
**実装箇所**: `k_back/app/models/audit_log.py`

すべての重要な操作（作成・更新・削除）を記録し、不正アクセスの追跡を可能にする。

### 4.3 暗号化（Fernet）
**実装箇所**: `k_back/app/models/calendar_account.py`

```python
from cryptography.fernet import Fernet

def encrypt_service_account_key(self, key_data: str):
    """サービスアカウントキーを暗号化して保存"""
    encryption_key = settings.CALENDAR_ENCRYPTION_KEY
    fernet = Fernet(encryption_key.encode())
    encrypted_key = fernet.encrypt(key_data.encode())
    self.service_account_key = encrypted_key.decode()

def decrypt_service_account_key(self) -> str:
    """暗号化されたサービスアカウントキーを復号化"""
    encryption_key = settings.CALENDAR_ENCRYPTION_KEY
    fernet = Fernet(encryption_key.encode())
    decrypted_key = fernet.decrypt(self.service_account_key.encode())
    return decrypted_key.decode()
```

**効果**: 機密データ（サービスアカウントキーなど）をDB保存時に暗号化

### 4.4 Stripeウェブフック署名検証
**実装箇所**: `k_back/app/api/v1/endpoints/webhooks.py`

```python
import stripe

@router.post("/stripe")
async def stripe_webhook(request: Request, ...):
    payload = await request.body()
    sig_header = request.headers.get("stripe-signature")

    try:
        event = stripe.Webhook.construct_event(
            payload, sig_header, settings.STRIPE_WEBHOOK_SECRET
        )
    except ValueError:
        raise HTTPException(status_code=400, detail="Invalid payload")
    except stripe.error.SignatureVerificationError:
        raise HTTPException(status_code=400, detail="Invalid signature")
```

**効果**: Stripeからのウェブフックが本物であることを検証し、偽装リクエストを防止

---

## 5. セキュリティチェックリスト

### 開発時の確認事項
- [ ] すべてのAPIエンドポイントで認証チェックを実施
- [ ] 入力値をPydanticスキーマでバリデーション
- [ ] エラーメッセージに機密情報を含めない
- [ ] CSRF保護が必要なエンドポイントで検証を実施
- [ ] SQLクエリはORMを使用（生SQLを避ける）
- [ ] パスワードは必ずハッシュ化
- [ ] 機密情報は環境変数で管理

### デプロイ前の確認事項
- [ ] `ENVIRONMENT=production`が設定されている
- [ ] `COOKIE_SECURE=True`が設定されている（HTTPS）
- [ ] CORS設定が本番ドメインのみに制限されている
- [ ] レート制限が適切に設定されている
- [ ] すべての依存パッケージが最新の安全なバージョン
- [ ] 環境変数がGitにコミットされていない
- [ ] 監査ログが有効化されている

---

## 6. セキュリティアップデート履歴

### 2026-01-24: Next.js/React CVE対応
- **対応内容**:
  - Next.js: 16.0.10 → 16.1.4
  - React: 19.1.2 → 19.2.3
  - React-dom: 19.1.2 → 19.2.3
  - Node.js: 22.15.0 → 22.22.0
- **対応CVE**:
  - CVE-2025-55182 (React2Shell, CVSS 10.0)
  - CVE-2025-66478, CVE-2025-55184, CVE-2025-67779
  - CVE-2025-55183, CVE-2025-59466
- **詳細**: `md_files_design_note/task/fix_front/nextjs_react_security_patch_2026-01-24.md`

---

## 7. 参考資料

- [OWASP Top 10](https://owasp.org/www-project-top-ten/)
- [FastAPI Security](https://fastapi.tiangolo.com/tutorial/security/)
- [CSRF Protection Best Practices](https://cheatsheetseries.owasp.org/cheatsheets/Cross-Site_Request_Forgery_Prevention_Cheat_Sheet.html)
- [Content Security Policy](https://developer.mozilla.org/en-US/docs/Web/HTTP/CSP)

---

**最終更新日**: 2026-01-26
**文書管理者**: 開発チーム
