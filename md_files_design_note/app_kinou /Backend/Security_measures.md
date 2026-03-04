# Security Measures（セキュリティ実装）

## JWT 認証

**ファイル**: `app/core/security.py`

### トークン種別

| トークン | 有効期限 | 用途 |
|---------|---------|------|
| `access_token` | 30分（デフォルト） | 通常API認証 |
| `refresh_token` | 7日 | アクセストークン再発行 |
| `temporary_token` | 10分 | MFA検証中の一時認証 |
| メール確認トークン | 24時間 | メールアドレス確認 |

### トークン生成・検証
- アルゴリズム: **HS256**
- `create_access_token()`: ペイロード＋有効期限でJWT生成
- `create_refresh_token()`: `jti`（JWT ID）で個別識別
- `decode_access_token()`: 検証失敗時はNone返却（例外を握りつぶさない）
- **パスワード変更後の無効化**: `password_changed_at > token.iat` でトークン失効

### Cookie 送信
- `access_token` は HTTPOnly Cookie として設定
- `credentials: 'include'` でフロントエンドから自動送信

---

## CSRF 対策

**ファイル**: `app/core/csrf.py`

- **方式**: Double Submit Cookie パターン
- Cookie名: `fastapi-csrf-token`
- ヘッダー名: `X-CSRF-Token`
- `cookie_samesite: lax`
- `cookie_secure: True`（本番環境のみ）
- httponly: False（JavaScriptからのアクセスを許可し、リクエストヘッダーに付与）

### 検証ロジック（`deps.py: validate_csrf()`）
- `Authorization: Bearer` ヘッダーが存在 → スキップ（APIクライアント向け）
- Cookie認証時のみ → `X-CSRF-Token` ヘッダーを検証
- 対象メソッド: POST / PUT / PATCH / DELETE

---

## パスワードハッシュ化

**ファイル**: `app/core/security.py`

```python
pwd_context = CryptContext(schemes=["bcrypt"], deprecated="auto")

def get_password_hash(password: str) -> str: ...
def verify_password(plain_password, hashed_password) -> bool: ...
```

- アルゴリズム: **bcrypt**（コストファクター自動管理）
- パスワードリセットトークン: SHA-256でハッシュ化してDBに保存

---

## MFA（多要素認証）

**ファイル**: `app/core/security.py`, `app/models/mfa.py`

### TOTP（Time-based One-Time Password）
- `generate_totp_secret()`: pyotp でシークレット生成
- `generate_qr_code()`: Base64エンコードQRコードを返却
- `verify_totp()`: 時間窓 ±30秒で検証
- `sanitize_totp_code()`: 6桁コードに正規化
- シークレットの保存: **Fernet暗号化**（`encrypt_mfa_secret()` / `decrypt_mfa_secret()`）

### リカバリーコード
- 形式: `XXXX-XXXX-XXXX-XXXX`（4-4-4-4）
- 発行数: 10個
- 保存: bcryptハッシュのみ（平文は保存しない）
- 使用済みフラグ: `is_used`, `used_at` で管理

### MFA 監査ログ（`MFAAuditLog`）
- 記録アクション: `enabled`, `disabled`, `login_success`, `login_failed`, `backup_used`
- 記録フィールド: `ip_address`, `user_agent`, `details`

---

## レート制限

**ファイル**: `app/core/limiter.py`, `app/core/config.py`

- ライブラリ: **slowapi**（Starlette/FastAPI 対応）
- IPアドレスベースで制限

| エンドポイント | 制限値 |
|--------------|--------|
| パスワードリセット | 5回 / 10分 |
| メール再送 | 3回 / 10分 |
| ダッシュボード | 60回 / 分 |

---

## CORS 設定

**ファイル**: `app/main.py`（行144-184）

### 本番環境
```python
allowed_origins = [
    "https://keikakun-front.vercel.app",
    "https://www.keikakun.com",
    "https://api.keikakun.com",
]
```

### 開発環境
```python
allowed_origins = [
    "http://localhost:3000",
    "https://keikakun-front.vercel.app",
]
```

- 許可ヘッダー: `Content-Type`, `Authorization`, `X-Requested-With`, `Accept`, `X-CSRF-Token`
- `allow_credentials: True`（Cookie送信のため）

---

## 入力バリデーション（Pydantic）

**ファイル**: `app/main.py`（行56-98）、`app/schemas/`

- Pydanticスキーマで全リクエストボディをバリデーション
- `RequestValidationError` カスタムハンドラ: バリデーションエラーを日本語化
- **XSS対策**: エラーレスポンスを `html.escape()` でサニタイズ

---

## SQLインジェクション対策

- **SQLAlchemy ORM** のパラメータバインディングのみ使用
- 生SQL（`text()`）は使用禁止
- 例: `select(Staff).where(Staff.id == id)` → プリペアドステートメントに変換

---

## 監査ログ

**ファイル**: `app/models/staff_profile.py`, `app/crud/crud_audit_log.py`

### AuditLog モデルのフィールド
- `actor_id`, `action`, `target_type`, `target_id`
- `office_id`, `ip_address`, `user_agent`
- `details`（JSONB）: 変更前後の値等

### 保持期間ポリシー
| カテゴリ | 保持期間 | 対象アクション |
|---------|---------|--------------|
| Legal | 5年 | `withdrawal.approved`, `staff.deleted` |
| Important | 3年 | `staff.created`, `staff.role_changed` |
| Standard | 1年 | `staff.updated`, `password_changed` |
| Short-term | 90日 | `staff.login`, `mfa.enabled` |

---

## 権限チェック（認可）

**ファイル**: `app/api/deps.py`

| Depends関数 | 許可ロール |
|------------|----------|
| `get_current_user` | 全認証済みスタッフ |
| `require_manager_or_owner` | Manager / Owner |
| `require_owner` | Owner のみ |
| `require_app_admin` | app_admin のみ |
| `require_active_billing` | 課金ステータスが `free` または `active` |

- `past_due` / `canceled` → 402 Payment Required
