# パスワードリセット（Forgot Password）機能 - 詳細仕様と実装 TODO

## 概要
本ドキュメントは「パスワードを忘れたユーザー向けのパスワードリセット機能」についての詳細仕様、DB スキーマ、実装箇所、テスト計画、セキュリティ注意点などをまとめたものです。

目的:
- 利用者（スタッフユーザー）が登録済みメールアドレスでパスワードリセットを要求できること
- 安全な一時トークン（期限付き）を発行し、確認メールでリセットリンクを送付すること
- トークンは一度のみ使用可能とし、使用後は無効化すること
- 開発・テスト環境での E2E テストを容易にするため、トークンの即時失効 SQL を用意すること

---

## 要件（高レベル）
- API
  - POST /api/v1/auth/forgot-password : リセット要求を受け取り、存在する場合はメール送信（存在しない場合でも同じ成功レスポンスを返す）
  - POST /api/v1/auth/reset-password : トークンと新しいパスワードを受け取り、検証後にパスワードを更新
  - GET /api/v1/auth/verify-reset-token : トークンの有効性確認（任意）
  - POST /api/v1/auth/resend-reset-email : 再送（レート制御あり）

- DB
  - トークンは UUID もしくはランダムな長い文字列をハッシュ化して保存（token_hash）
  - expires_at を持ち、有効期限を設定（例: 発行から1時間）
  - used フラグ／used_at を持つ
  - 監査ログテーブルでリクエスト・成功・失敗を記録（IP・User-Agent・email・success 等）

- セキュリティ
  - トークンは DB にはハッシュ（SHA-256 等）で保存し、メールには原文のトークンを送付
  - HTTPS 必須
  - レート制限（IP とメールアドレス単位）
  - ブルートフォース対策（短時間に多数のトークン確認を拒否）
  - トランザクション内で used フラグを更新し、再利用を防止
  - エラーメッセージは情報漏洩を防ぐため曖昧にする（例: "再送を検討してください" など）。ただし E2E/API テストでは日本語メッセージを検証するため、テスト用にメッセージを明示的に設定する。 

---

## DB スキーマ（サンプル）
```sql
CREATE TABLE password_reset_tokens (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  staff_id UUID REFERENCES staff(id) NOT NULL,
  token_hash VARCHAR(128) NOT NULL UNIQUE,
  expires_at TIMESTAMPTZ NOT NULL,
  used BOOLEAN DEFAULT FALSE,
  used_at TIMESTAMPTZ,
  created_at TIMESTAMPTZ DEFAULT now(),
  updated_at TIMESTAMPTZ DEFAULT now()
);

CREATE TABLE password_reset_audit_logs (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  staff_id UUID,
  action VARCHAR(50) NOT NULL, -- 'requested','token_verified','completed','failed','resend'
  email VARCHAR(255),
  ip_address VARCHAR(45),
  user_agent TEXT,
  success BOOLEAN,
  error_message TEXT,
  created_at TIMESTAMPTZ DEFAULT now()
);

CREATE INDEX idx_password_reset_token_hash ON password_reset_tokens(token_hash);
CREATE INDEX idx_password_reset_expires ON password_reset_tokens(expires_at);
CREATE INDEX idx_audit_staff_id ON password_reset_audit_logs(staff_id);
```

注意: 実際のプロジェクトでは table 名・カラム名を合わせてマイグレーションを作成してください（alembic での migration ファイル推奨）。

---

## 実装箇所（候補）
- モデル
  - app/models/password_reset_token.py（必要に応じて staff モデルにリレーション）
  - app/models/password_reset_audit_log.py

- CRUD
  - app/crud/crud_password_reset.py
    - create_token(db, staff_id, token_plain)
    - get_by_token_hash(db, token_hash)
    - mark_token_used(db, token_id)
    - cleanup_expired_tokens(db)

- サービス
  - app/services/password_reset_service.py
    - request_reset(email, client_ip, user_agent)
    - verify_token(token)
    - reset_password(token, new_password)

- API エンドポイント
  - app/api/v1/endpoints/auths.py にエンドポイント追加

- メール
  - app/core/mail.py に send_password_reset_email(), send_password_changed_notification()
  - app/templates/email/password_reset.html
  - app/templates/email/password_changed.html

- スキーマ（Pydantic）
  - app/schemas/auth.py に ForgotPasswordRequest, ResetPasswordRequest, VerifyResetTokenRequest, PasswordResetResponse を追加

- テスト
  - tests/models/test_password_reset_token.py
  - tests/crud/test_crud_password_reset.py
  - tests/api/v1/test_password_reset.py（E2E スタイル）

---

## レート制御と運用設定
- 環境変数
  - PASSWORD_RESET_TOKEN_EXPIRE_HOURS（例: 1）
  - RATE_LIMIT_FORGOT_PASSWORD（例: 5 / hour）
  - RATE_LIMIT_RESEND_EMAIL（例: 3 / hour）
- 実装: Redis や内製のインメモリカウントで簡易対応可能。ただし E2E では固定設定でテスト可能にする。

---

## テスト計画
### ユニットテスト
- トークン生成・ハッシュ化の単体テスト
- token の有効期限計算
- mark_token_used の再利用防止

### CRUD テスト
- create_token, get_by_token_hash, cleanup_expired_tokens の動作

### API テスト（統合）
- POST /forgot-password で既存ユーザー・非既存ユーザー双方で成功レスポンスを返す
- POST /reset-password で有効トークン・期限切れトークン・既に使用済みトークンの検証
- GET /verify-reset-token で有効性確認
- POST /resend-reset-email のレート制御検証

### E2E テスト
- フロー: forgot -> 受信したメール中のトークンで reset -> ログイン確認
- テスト用にメール送信は外部サービスをモック（またはローカルでキャプチャ）
- セットアップ／クリーンアップ用の SQL を用意してトークンを即時失効させる

---

## E2E 用: トークン／セッションを即時失効させる SQL（例）
- PostgreSQL (expires_at を過去にする)
```sql
UPDATE password_reset_tokens SET expires_at = NOW() - INTERVAL '1 second';
```

- PostgreSQL (epoch にする)
```sql
UPDATE password_reset_tokens SET expires_at = TO_TIMESTAMP(0);
```

- max_age カラムを持つ場合
```sql
UPDATE auth_tokens SET max_age = 0;
```

注意: テスト専用 DB でのみ実行してください。

---

## セキュリティ考慮事項（要点）
- トークンはメール本文にそのまま送るが、DB ではハッシュで保存
- メール文言でユーザー存在の有無を漏らさない
- レートリミッタで Abuse を防止
- IP と User-Agent を監査ログに残す
- トークン検証は常にタイムスタンプと used フラグをチェック。更新は楽観的ロックまたはトランザクションで行う。

---

## TODO（実装タスク）
- [ ] DB マイグレーションファイルを作成（password_reset_tokens, password_reset_audit_logs）
- [ ] モデルと CRUD を実装
- [ ] サービス層を実装（例: app/services/password_reset_service.py）
- [ ] メールテンプレートと send 関数を実装
- [ ] API エンドポイントを追加（auths.py）
- [ ] ユニット・統合・E2E テストを追加
- [ ] 設定（ENV）とレート制御の実装
- [ ] 運用向けログ・監査・クリーンアップタスクを追加

---

最後に: 実装中に文字化けやエンコーディング問題が発生した場合は、ファイルが UTF-8 で保存されていることを確認してください。必要なら私がマイグレーションやテンプレートの日本語文言もチェックして統一します。
