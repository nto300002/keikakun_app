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

## Next Steps

Phase 2: データベース設計へ進む
- テーブル定義
- マイグレーション作成
- ORM モデル実装
