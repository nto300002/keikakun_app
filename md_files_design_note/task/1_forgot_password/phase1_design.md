<!--
作業ブランチ: issue/feature-パスワードを忘れた際の処理
注意: このファイルに変更を加える場合、必ず上記に現在作業しているブランチ名を明記し、変更はそのブランチへ push してください。
-->

# Phase 1: 設計フェーズ

パスワードリセット機能の要件定義とAPI設計

---

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
- **トークン有効期限：30分**（推奨）※セキュリティレビュー結果を反映（従来の1時間から短縮）
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

## 3. API エンドポイント設計

### 3.1 パスワードリセット要求

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

### 3.2 トークン有効性確認（オプション）

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

### 3.3 パスワードリセット実行

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

## 4. スキーマ定義

### 4.1 リクエストスキーマ

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

## 5. メッセージ定義

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

## 6. セキュリティ設計のポイント

### 6.1 トークンの取り扱い

**生成**:
- UUID v4を使用（暗号学的に安全なランダム値）
- 予測不可能性を保証

**保存**:
- 生のトークンはDBに保存しない
- SHA-256でハッシュ化してから保存
- DB侵害時でもトークンの漏洩を防ぐ

**送信**:
- URLフラグメント識別子（#token=xxx）を使用
- クエリパラメータ（?token=xxx）は使用しない
- ブラウザ履歴やサーバーログに記録されない
- リファラーヘッダーに含まれない

### 6.2 レート制限

```python
# forgot-password: 5回/10分
@limiter.limit("5/10minute")

# resend: 3回/10分（より厳しく）
@limiter.limit("3/10minute")
```

### 6.3 ユーザー存在の推測防止

存在しないメールアドレスでも成功レスポンスを返す：

```python
# セキュリティのため、常に成功メッセージを返す
return PasswordResetResponse(
    message=ja.AUTH_PASSWORD_RESET_EMAIL_SENT
)
```

### 6.4 セッション無効化

パスワード変更後は全セッションを無効化：

```python
# 全セッションを無効化
stmt = (
    update(Session)
    .where(Session.staff_id == staff.id)
    .values(is_active=False, revoked_at=datetime.now(timezone.utc))
)
await db.execute(stmt)
```

---

## 7. フロントエンド設計のポイント

### 7.1 URLフラグメントからトークン取得

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

### 7.2 画面遷移フロー

1. **パスワードリセット要求画面**（`/forgot-password`）
   - メールアドレス入力
   - 送信ボタン
   - 再送信機能

2. **確認画面**
   - メール送信完了メッセージ
   - メールが届かない場合の対処法

3. **パスワードリセット実行画面**（`/reset-password#token=xxx`）
   - トークン自動取得
   - 新しいパスワード入力
   - パスワード確認入力
   - リセットボタン

4. **完了画面**
   - パスワード変更完了メッセージ
   - ログイン画面へのリンク

---

---

## 8. セキュリティ & トランザクションレビュー

**レビュー実施日**: 2025-11-20
**レビュアー**: Claude Code (Anthropic AI)
**レビュー観点**: セキュリティ、トランザクション管理

---

### 8.1 セキュリティレビュー

#### ✅ 良好な設計ポイント

1. **トークンのハッシュ化** - SHA-256でDB保存により、DB侵害時の漏洩を防止
2. **URLフラグメント識別子** - ブラウザ履歴・サーバーログへの漏洩防止
3. **レート制限** - ブルートフォース攻撃への対策
4. **ユーザー存在の推測防止** - 常に成功レスポンスを返す
5. **セッション無効化** - パスワード変更後の全セッション無効化
6. **監査ログ** - アクセス履歴の記録
7. **トークン一度使用制限** - 楽観的ロックによる実装
8. **パスワードハッシュ化** - bcryptの使用

#### 🔴 重大な問題

##### 1. トークンハッシュ化の実装詳細の矛盾

**問題点**:
```python
# 設計書: 「SHA-256でハッシュ化してDB保存」
# しかし、処理フローでは実装の詳細が不明確
```

**影響**:
- トークンをハッシュ化して保存する場合、検証時にも同じハッシュ化が必要
- URLフラグメントで渡す平文トークンとDB上のハッシュの対応が不明確
- メールに含めるトークンは平文？ハッシュ？

**推奨修正**:
```python
# トークン生成時
raw_token = str(uuid.uuid4())  # 平文トークン（メールに含める）
token_hash = hashlib.sha256(raw_token.encode()).hexdigest()  # DB保存用

# メールに含めるURL
reset_url = f"https://example.com/reset-password#token={raw_token}"

# 検証時
received_token = request.token
received_hash = hashlib.sha256(received_token.encode()).hexdigest()
db_token = await db.execute(
    select(PasswordResetToken).where(
        PasswordResetToken.token_hash == received_hash,
        PasswordResetToken.used == False,
        PasswordResetToken.expires_at > datetime.now(timezone.utc)
    )
)
```

**追記すべき処理フロー**:
```
1. UUID v4で平文トークン生成
2. SHA-256でハッシュ化
3. ハッシュをDBに保存（平文は保存しない）
4. 平文トークンをメールURLに含める
5. 検証時、受け取った平文トークンをSHA-256ハッシュ化
6. DBのハッシュと比較
```

##### 2. トランザクション境界の不明確さ

**問題点**:
```python
# パスワードリセット要求の処理順序
1. トークン生成
2. DBに保存        # ← トランザクション開始？
3. メール送信      # ← トランザクション内？外？
4. 成功レスポンス  # ← トランザクションコミット？
```

**影響**:
- メール送信失敗時にトークンがDBに残る（ユーザーは受け取れない）
- メール送信が遅延した場合、トランザクションが長時間保持される
- データベースロックの長期化

**推奨修正**:
```python
# 正しいトランザクション境界
async def forgot_password(email: str, db: AsyncSession):
    # 1. トランザクション開始
    async with db.begin():
        # トークン生成・保存
        token = await create_reset_token(db, staff.id)
        # トランザクションコミット（暗黙的）

    # 2. トランザクション外でメール送信
    try:
        await send_password_reset_email(email, token.raw_value)
    except EmailSendError as e:
        # メール送信失敗時の処理
        logger.error(f"Email send failed: {e}")
        # トークンは既にDBに保存されているが、
        # 期限切れで自動削除されるので許容

    # 3. 常に成功レスポンス（セキュリティのため）
    return {"message": ja.AUTH_PASSWORD_RESET_EMAIL_SENT}
```

#### 🟠 中程度の問題

##### 3. タイミング攻撃への対策不足

**問題点**:
```python
# 現在の設計
if not token:
    raise HTTPException(404, "Token not found")  # 即座にレスポンス

if token.used:
    raise HTTPException(400, "Already used")  # 異なるタイミング

if token.expires_at < now():
    raise HTTPException(400, "Expired")  # さらに異なるタイミング
```

**影響**:
- レスポンス時間の違いから、トークンの状態を推測可能

**推奨修正**:
```python
import secrets

# Constant-time比較を使用
def verify_token_constant_time(token: PasswordResetToken,
                                received_hash: str) -> bool:
    """タイミング攻撃を防ぐトークン検証"""
    if not token:
        # ダミー処理で時間を揃える
        secrets.compare_digest("dummy", "dummy")
        return False

    # 全ての条件を先に評価
    is_hash_match = secrets.compare_digest(
        token.token_hash,
        received_hash
    )
    is_not_used = not token.used
    is_not_expired = token.expires_at > datetime.now(timezone.utc)

    # 全ての条件が真の場合のみ成功
    return is_hash_match and is_not_used and is_not_expired
```

##### 4. 楽観的ロックの実装不足

**問題点**:
```python
# 設計書: 「楽観的ロックで実装」
# しかし、具体的な実装方法が不明確
```

**推奨修正**:
```python
# Option 1: バージョン番号を使う楽観的ロック
class PasswordResetToken(Base):
    version: Mapped[int] = mapped_column(Integer, default=0)

# 更新時
result = await db.execute(
    update(PasswordResetToken)
    .where(
        PasswordResetToken.id == token.id,
        PasswordResetToken.used == False,
        PasswordResetToken.version == token.version  # ← 楽観的ロック
    )
    .values(used=True, used_at=now(), version=token.version + 1)
)

if result.rowcount == 0:
    raise HTTPException(409, "Token already used (conflict)")

# Option 2: データベースのユニーク制約を使う
# CREATE UNIQUE INDEX ON password_reset_tokens (id)
# WHERE used = false;
```

##### 5. 並行処理のレースコンディション

**問題点**:
```python
# 同一ユーザーから複数リクエストが同時に来た場合
# Request A: 既存トークンを無効化 → 新トークン生成
# Request B: 既存トークンを無効化 → 新トークン生成
# どちらのトークンが有効？
```

**推奨修正**:
```python
async def create_reset_token(db: AsyncSession, staff_id: uuid.UUID):
    # SELECT ... FOR UPDATE でロック取得
    existing_tokens = await db.execute(
        select(PasswordResetToken)
        .where(
            PasswordResetToken.staff_id == staff_id,
            PasswordResetToken.used == False,
            PasswordResetToken.expires_at > datetime.now(timezone.utc)
        )
        .with_for_update()  # ← 悲観的ロック
    )

    # 既存トークンを無効化
    for token in existing_tokens.scalars():
        token.used = True
        token.used_at = datetime.now(timezone.utc)

    # 新トークン生成
    new_token = PasswordResetToken(...)
    db.add(new_token)

    return new_token
```

#### 🟡 軽微な問題

##### 6. IPアドレス取得の信頼性

**問題点**:
```python
# リバースプロキシ経由の場合、X-Forwarded-Forの検証が必要
# 複数プロキシ経由の場合の取得方法が不明確
```

**推奨修正**:
```python
from fastapi import Request

def get_client_ip(request: Request) -> str:
    """信頼できるクライアントIPアドレスを取得"""
    # 1. X-Forwarded-Forヘッダーをチェック
    forwarded_for = request.headers.get("X-Forwarded-For")
    if forwarded_for:
        # 最初のIPアドレスを取得（クライアント）
        # 注意: プロキシが信頼できる場合のみ
        return forwarded_for.split(",")[0].strip()

    # 2. X-Real-IPヘッダーをチェック
    real_ip = request.headers.get("X-Real-IP")
    if real_ip:
        return real_ip

    # 3. 直接接続の場合
    return request.client.host
```

##### 7. トークン有効期限の再検討

**現在**: 1時間
**推奨**: 15分〜30分

**理由**:
- パスワードリセットは緊急性が高い
- 短い期限の方がセキュリティリスクが低い
-  ユーザビリティとのバランスで30分が妥当

**追加機能**:
```python
# トークン再送信機能を追加
@router.post("/api/v1/auth/resend-reset-password")
@limiter.limit("3/10minute")  # より厳しいレート制限
async def resend_reset_password(email: EmailStr):
    # 既存の未使用トークンを無効化
    # 新しいトークンを生成・送信
    ...
```

##### 8. CSRF対策の追加

**問題点**:
パスワードリセット実行（POST /reset-password）でCSRF対策が言及されていない

**推奨修正**:
```python
# Option 1: CSRF トークンを使う（セッションベース）
# しかし、パスワードリセットは未認証なので不適切

# Option 2: Double Submit Cookie パターン
# しかし、実装が複雑

# Option 3: SameSite Cookie 属性
# 推奨: この場合、トークン自体が一度しか使えないため、
# CSRF攻撃のリスクは限定的。ただし、念のため追加対策を推奨

# 推奨実装: リファラーチェック
from urllib.parse import urlparse

def validate_referer(request: Request):
    referer = request.headers.get("Referer")
    if not referer:
        raise HTTPException(403, "Invalid request")

    referer_host = urlparse(referer).netloc
    allowed_hosts = [
        "yourdomain.com",
        "www.yourdomain.com"
    ]

    if referer_host not in allowed_hosts:
        raise HTTPException(403, "Invalid referer")
```

##### 9. メール経由の平文トークン送信のリスク分析

**⚠️ 重要な懸念事項**: メール内に平文トークンを含めることのセキュリティリスク

#### 🔴 リスク分析

##### リスク1: メールの傍受・盗聴
**問題**:
- メールは基本的に平文で送信される（メールサーバー間の通信）
- 中間者攻撃（MITM）でメール内容を傍受される可能性
- 公衆Wi-Fiなどの安全でないネットワークでのメール受信

**影響度**: 🟠 中程度
- 攻撃者がトークンを取得し、パスワードをリセット可能
- ただし、TLS/STARTTLSでメールサーバー間通信は暗号化されている（現代の標準）

##### リスク2: メールサーバー・プロバイダーのログ保存
**問題**:
- メールはメールサーバー（Gmail、Outlook等）に永続的に保存される
- メールプロバイダーの管理者がアクセス可能
- メールサーバーが侵害された場合、過去のメールが漏洩

**影響度**: 🟠 中程度
- トークンが長期間メールボックスに残る
- メールプロバイダーのセキュリティに依存

##### リスク3: メールの誤転送・共有
**問題**:
- ユーザーがメールを第三者に転送する可能性
- メールの「返信」や「全員に返信」での意図しない共有
- スクリーンショット共有などでトークンが漏洩

**影響度**: 🟡 低〜中程度
- ユーザーの操作ミス
- トークンの有効期限と一度使用制限で軽減

##### リスク4: メールクライアントのバックアップ
**問題**:
- メールクライアント（Outlook、Apple Mail等）のローカルバックアップ
- デバイス紛失・盗難時にバックアップからトークン取得

**影響度**: 🟡 低程度
- デバイスレベルのセキュリティに依存

##### リスク5: リファラーヘッダー漏洩（一部軽減済み）
**問題**:
- メール内のリンククリック時、次のサイトへ遷移するとリファラーヘッダーに含まれる可能性

**影響度**: 🟢 低（URLフラグメントで軽減済み）
- 設計書の「URLフラグメント識別子」使用で対策済み

#### ✅ 既存の軽減策（設計書に含まれている）

1. **トークンの短い有効期限** - 1時間（推奨: 15-30分に短縮）
2. **一度しか使用できない** - `used=true`フラグによる無効化
3. **DB上でのハッシュ化保存** - DB侵害時の防御層
4. **URLフラグメント識別子** - ブラウザ履歴・リファラー漏洩の防止
5. **監査ログ** - 不正使用の検出と追跡
6. **レート制限** - ブルートフォース攻撃の防止

#### 🔵 追加推奨対策

##### 1. トークン有効期限の短縮
```python
# 現在: 1時間
TOKEN_EXPIRY = timedelta(hours=1)

# 推奨: 15-30分
TOKEN_EXPIRY = timedelta(minutes=30)

# 理由:
# - パスワードリセットは緊急性が高い（ユーザーはすぐに実行する）
# - 短い期限ほどリスクウィンドウが小さい
# - 期限切れの場合は再リクエスト可能
```

##### 2. メール送信時のセキュリティヘッダー
```python
# メールヘッダーに機密情報であることを示す
email_headers = {
    "X-Priority": "1",  # 高優先度
    "Importance": "high",
    "Sensitivity": "private",  # プライベート情報
    "X-Auto-Response-Suppress": "All",  # 自動返信を抑制
}
```

##### 3. メール本文での注意喚起
```
件名: 【重要】パスワードリセットのご案内

本文:
━━━━━━━━━━━━━━━━━━━━━━━━━━
⚠️ このメールには重要なセキュリティ情報が含まれています
━━━━━━━━━━━━━━━━━━━━━━━━━━

パスワードリセットのリクエストを受け付けました。

以下のリンクをクリックして、新しいパスワードを設定してください。
このリンクは30分間有効で、一度しか使用できません。

[パスワードをリセット]

⚠️ セキュリティ上の注意:
• このメールを他の人に転送しないでください
• パスワード設定後、このメールは削除することをお勧めします
• 心当たりがない場合は、このメールを無視してください

有効期限: {expires_at} まで
━━━━━━━━━━━━━━━━━━━━━━━━━━
```

##### 4. 使用済みトークンの即時無効化通知
```python
# パスワードリセット完了後、トークンリンクを含むメールが無効になったことを通知
async def send_token_invalidation_notice(email: str):
    """
    パスワード変更完了後、古いメール内のリンクが無効になったことを通知
    """
    await send_email(
        to=email,
        subject="パスワードが正常に変更されました",
        body="""
        パスワードが正常に変更されました。

        以前送信したパスワードリセットメール内のリンクは
        すべて無効になりました。

        受信箱から削除することをお勧めします。
        """
    )
```

##### 5. IPアドレス・デバイス指紋による検証（オプション）
```python
# トークン生成時のIPアドレス・User-Agentを記録
class PasswordResetToken(Base):
    request_ip: Mapped[Optional[str]] = mapped_column(String(45))
    request_user_agent: Mapped[Optional[str]] = mapped_column(String(500))

# 使用時に異なるIPからのアクセスを警告
async def validate_token_context(token: PasswordResetToken, request: Request):
    current_ip = get_client_ip(request)

    if token.request_ip and current_ip != token.request_ip:
        # 異なるIPからのアクセスを監査ログに記録
        await log_audit(
            action="ip_mismatch_warning",
            original_ip=token.request_ip,
            current_ip=current_ip
        )

        # 必要に応じて追加確認を要求
        # （ただし、モバイルネットワークなどでIPは変わるため、ブロックはしない）
```

#### 📊 業界標準との比較

**主要サービスの実装**:
| サービス | メール送信 | 有効期限 | 使用回数 |
|---------|----------|---------|---------|
| GitHub | ✅ メールでトークン送信 | 1時間 | 一度のみ |
| Google | ✅ メールでトークン送信 | 30分 | 一度のみ |
| Microsoft | ✅ メールでトークン送信 | 1時間 | 一度のみ |
| Amazon | ✅ メールでトークン送信 | 30分 | 一度のみ |

**業界のベストプラクティス**:
- メール経由のパスワードリセットは**業界標準**のアプローチ
- リスクは存在するが、**適切な軽減策により許容可能なレベル**に抑制
- 代替手段（SMS、アプリ内通知）もそれぞれリスクを持つ

#### 🔐 リスク受容の判断基準

**許容可能な理由**:
1. **短い有効期限** - リスクウィンドウが限定的（30分推奨）
2. **一度しか使用できない** - トークン再利用不可
3. **DB侵害への防御** - トークンハッシュ化により、DBが漏洩してもトークン自体は安全
4. **監査ログ** - 不正使用を追跡・検出可能
5. **セッション無効化** - 万が一不正使用されても、パスワード変更後は全セッション無効
6. **業界標準** - OWASP、NISTなどのセキュリティガイドラインでも推奨される方法

**代替案のリスク比較**:
- **SMS**: SIM swapping攻撃、通信事業者の傍受リスク
- **アプリ内通知**: デバイス紛失時にアクセス不可
- **セキュリティ質問**: ソーシャルエンジニアリングのリスク

#### 📝 結論

**総合評価**: ✅ **許容可能（条件付き）**

メール経由の平文トークン送信は、以下の条件下で**セキュリティ上許容可能**:

1. ✅ トークン有効期限を**30分以内**に設定
2. ✅ 一度しか使用できない仕組みの実装
3. ✅ DB上でのトークンハッシュ化
4. ✅ HTTPS必須（本番環境）
5. ✅ メール本文での注意喚起
6. ✅ 監査ログによる追跡
7. ✅ レート制限によるブルートフォース防止

**追加推奨事項**:
- メール送信後、ユーザーに「メールが届かない場合の対処法」を案内
- 完了後、「古いメールを削除することを推奨」する通知を送信
- 不審なアクセスパターンを検出した場合のアラート機能

---

### 8.2 トランザクション管理レビュー

#### ✅ 良好な設計ポイント

1. **トランザクションの使用** - パスワードリセット実行時
2. **エラー時のロールバック** - データ整合性の保証

#### 🔴 重大な問題

##### 1. メール送信のトランザクション境界

**問題**: 上記 8.1 の「重大な問題 #2」を参照

**修正済み推奨パターン**:
```python
# パターン1: メール送信はトランザクション外（推奨）
async with db.begin():
    # DB操作のみ
    token = await create_token(...)

# トランザクション完了後
await send_email(...)  # 失敗してもDB状態は一貫

# パターン2: Sagaパターン（複雑な場合）
try:
    async with db.begin():
        token = await create_token(...)

    await send_email(...)
except EmailError:
    # 補償トランザクション
    async with db.begin():
        await mark_token_as_failed(token.id)
```

#### 🟠 中程度の問題

##### 2. セッション無効化のトランザクション

**問題点**:
```python
# パスワードリセット実行時の処理順序
1. パスワード更新
2. password_changed_at 更新
3. トークン無効化
4. セッション無効化  # ← どのトランザクション？
```

**推奨修正**:
```python
async def reset_password(token: str, new_password: str, db: AsyncSession):
    # 単一トランザクション内で全て実行
    async with db.begin():
        # 1. トークン検証・取得（FOR UPDATE）
        token_record = await db.execute(
            select(PasswordResetToken)
            .where(PasswordResetToken.token_hash == hash(token))
            .with_for_update()
        )

        # 2. スタッフ取得（FOR UPDATE）
        staff = await db.execute(
            select(Staff)
            .where(Staff.id == token_record.staff_id)
            .with_for_update()
        )

        # 3. パスワード更新
        staff.hashed_password = hash_password(new_password)
        staff.password_changed_at = datetime.now(timezone.utc)

        # 4. トークン無効化
        token_record.used = True
        token_record.used_at = datetime.now(timezone.utc)

        # 5. 全セッション無効化（同一トランザクション内）
        await db.execute(
            update(Session)
            .where(Session.staff_id == staff.id)
            .values(
                is_active=False,
                revoked_at=datetime.now(timezone.utc)
            )
        )

        # トランザクション自動コミット

    # トランザクション完了後
    await send_password_changed_notification(staff.email)
```

##### 3. デッドロック防止のためのロック順序

**問題点**:
複数テーブルを更新する際、ロック順序が統一されていないとデッドロックが発生

**推奨修正**:
```python
# ロック順序を統一
# 推奨順序: 1. staffs → 2. password_reset_tokens → 3. sessions → 4. audit_logs

async def reset_password_with_proper_lock_order(...):
    async with db.begin():
        # 1. まず Staff をロック
        staff = await db.execute(
            select(Staff).where(...).with_for_update()
        )

        # 2. 次に PasswordResetToken をロック
        token = await db.execute(
            select(PasswordResetToken).where(...).with_for_update()
        )

        # 3. Sessions を更新（ロック不要、UPDATEで自動ロック）
        await db.execute(update(Session).where(...))

        # 4. 最後に監査ログを挿入
        db.add(PasswordResetAuditLog(...))
```

#### 🟡 軽微な問題

##### 4. 監査ログ記録のトランザクション戦略

**問題点**:
監査ログがトランザクション内だと、ロールバック時にログも消える

**推奨修正**:
```python
# Option 1: 監査ログは別トランザクション（推奨）
async def reset_password(...):
    try:
        async with db.begin():
            # メイン処理
            ...

        # 成功ログ（別トランザクション）
        await log_audit(action="completed", ...)

    except Exception as e:
        # 失敗ログ（別トランザクション、確実に記録）
        await log_audit(action="failed", error=str(e), ...)
        raise

# Option 2: PostgreSQL AUTONOMOUS TRANSACTION (pg 拡張)
# しかし、SQLAlchemy では標準サポートされていない
```

##### 5. クリーンアップジョブとの競合

**問題点**:
期限切れトークン削除ジョブとアプリケーションの競合

**推奨修正**:
```python
# クリーンアップジョブ（毎日実行）
async def cleanup_expired_tokens(db: AsyncSession):
    # DELETE ではなく論理削除を使う
    await db.execute(
        update(PasswordResetToken)
        .where(
            PasswordResetToken.expires_at < datetime.now(timezone.utc),
            PasswordResetToken.used == False
        )
        .values(used=True, used_at=datetime.now(timezone.utc))
    )

    # 古いレコードの物理削除（例: 30日以上前）
    await db.execute(
        delete(PasswordResetToken)
        .where(
            PasswordResetToken.created_at <
            datetime.now(timezone.utc) - timedelta(days=30)
        )
    )
```

---

### 8.3 推奨される追加実装

#### 1. トークン検証の完全な実装例

```python
import hashlib
import secrets
from datetime import datetime, timezone

async def verify_reset_token(
    token: str,
    db: AsyncSession
) -> Optional[PasswordResetToken]:
    """
    パスワードリセットトークンを検証

    タイミング攻撃対策を含む
    """
    # トークンをハッシュ化
    token_hash = hashlib.sha256(token.encode()).hexdigest()

    # DBから取得
    result = await db.execute(
        select(PasswordResetToken)
        .where(PasswordResetToken.token_hash == token_hash)
    )
    db_token = result.scalar_one_or_none()

    # Constant-time検証
    if not db_token:
        # ダミー処理で時間を揃える
        secrets.compare_digest("dummy_hash", "dummy_hash")
        return None

    # 全条件を評価
    is_not_used = not db_token.used
    is_not_expired = db_token.expires_at > datetime.now(timezone.utc)

    # 全て真の場合のみ成功
    if is_not_used and is_not_expired:
        return db_token

    return None
```

#### 2. 完全なトランザクション実装例

```python
async def execute_password_reset(
    token: str,
    new_password: str,
    db: AsyncSession,
    request: Request
) -> None:
    """
    パスワードリセットの完全な実装

    トランザクション管理とエラーハンドリングを含む
    """
    # 1. トークン検証（読み取りのみ）
    token_record = await verify_reset_token(token, db)
    if not token_record:
        await log_audit_async(
            action="failed",
            reason="invalid_token",
            ip=get_client_ip(request)
        )
        raise HTTPException(400, ja.AUTH_RESET_TOKEN_INVALID_OR_EXPIRED)

    # 2. トランザクション開始
    try:
        async with db.begin():
            # 2.1 ロック順序: Staff → PasswordResetToken → Session

            # Staff をロック
            staff = await db.execute(
                select(Staff)
                .where(Staff.id == token_record.staff_id)
                .with_for_update()
            )
            staff = staff.scalar_one()

            # トークンを再検証 & ロック（楽観的ロック）
            update_result = await db.execute(
                update(PasswordResetToken)
                .where(
                    PasswordResetToken.id == token_record.id,
                    PasswordResetToken.used == False  # 楽観的ロック条件
                )
                .values(
                    used=True,
                    used_at=datetime.now(timezone.utc)
                )
            )

            if update_result.rowcount == 0:
                raise HTTPException(409, ja.AUTH_RESET_TOKEN_ALREADY_USED)

            # パスワード更新
            staff.hashed_password = get_password_hash(new_password)
            staff.password_changed_at = datetime.now(timezone.utc)

            # 全セッション無効化
            await db.execute(
                update(Session)
                .where(Session.staff_id == staff.id)
                .values(
                    is_active=False,
                    revoked_at=datetime.now(timezone.utc)
                )
            )

            # トランザクション自動コミット

        # 3. トランザクション外の処理
        # 通知メール送信
        try:
            await send_password_changed_notification(staff.email)
        except EmailError as e:
            # メール送信失敗はログのみ（処理は成功扱い）
            logger.error(f"Failed to send notification email: {e}")

        # 成功監査ログ（別トランザクション）
        await log_audit_async(
            action="completed",
            staff_id=staff.id,
            ip=get_client_ip(request)
        )

    except HTTPException:
        # 既知のエラーは再送出
        raise
    except Exception as e:
        # 予期しないエラー
        logger.error(f"Password reset failed: {e}")
        await log_audit_async(
            action="failed",
            reason="unexpected_error",
            error=str(e),
            ip=get_client_ip(request)
        )
        raise HTTPException(
            500,
            ja.AUTH_PASSWORD_RESET_FAILED
        )
```

---

### 8.4 レビュー結果サマリー

| 深刻度 | 項目数 | 主な問題 |
|--------|--------|----------|
| 🔴 重大 | 2 | トークンハッシュ化の矛盾、トランザクション境界 |
| 🟠 中程度 | 5 | タイミング攻撃、楽観的ロック、並行処理 |
| 🟡 軽微 | 5 | IP取得、有効期限、CSRF、監査ログ |
| ℹ️ 情報 | 1 | **メール平文トークン送信リスク（許容可能）** |

**総合評価**: ⚠️ **Phase 2 進行前に重大な問題の修正が必要**

**推奨アクション**:
1. ✅ トークンハッシュ化の処理フローを明確化（8.1 #1）
2. ✅ トランザクション境界を明確化（8.1 #2、8.2 #1）
3. ✅ 楽観的ロックの具体的実装を追加（8.1 #4）
4. ⚠️ タイミング攻撃対策を追加（8.1 #3）
5. ⚠️ 並行処理のレースコンディション対策（8.1 #5）
6. ℹ️ メール平文トークンのリスク軽減策を実装（8.1 #9）
   - トークン有効期限を30分に短縮
   - メール本文に注意喚起を追加
   - パスワード変更完了後の通知強化

**メール平文トークンに関する補足**:
- ✅ **業界標準のアプローチ**（GitHub、Google、Microsoft等が採用）
- ✅ **適切な軽減策により許容可能なリスクレベル**
- ⚠️ ただし、追加推奨対策の実装を強く推奨（有効期限短縮、注意喚起等）

---

## Next Steps

**修正後のフェーズ進行**:
1. 本レビュー結果に基づき Phase 1 設計を修正
2. Phase 2: データベース設計へ進む
   - テーブル定義（バージョン番号カラム追加）
   - マイグレーション作成
   - ORM モデル実装（楽観的ロック対応）
