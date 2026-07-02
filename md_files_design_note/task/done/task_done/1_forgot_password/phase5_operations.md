<!--
作業ブランチ: issue/feature-パスワードを忘れた際の処理
注意: このファイルを編集する場合、必ず作業中のブランチ名を上部に記載し、変更はそのブランチへ push してください。
-->

# Phase 5: 運用フェーズ

パスワードリセット機能の運用、監視、保守

---

## 1. 環境変数設定

### 1.1 必須環境変数

`.env` ファイルに追加：

```bash
# フロントエンドURL（パスワードリセットメール用）
FRONTEND_URL=https://yourdomain.com

# パスワードリセットトークン有効期限（時間）
PASSWORD_RESET_TOKEN_EXPIRE_HOURS=1

# レート制限設定
RATE_LIMIT_FORGOT_PASSWORD=5/10minute
RATE_LIMIT_RESEND_EMAIL=3/10minute
```

### 1.2 設定ファイルへの追加

`app/core/config.py`:

```python
from pydantic_settings import BaseSettings


class Settings(BaseSettings):
    # 既存の設定...

    # パスワードリセット設定
    FRONTEND_URL: str
    PASSWORD_RESET_TOKEN_EXPIRE_HOURS: int = 1
    RATE_LIMIT_FORGOT_PASSWORD: str = "5/10minute"
    RATE_LIMIT_RESEND_EMAIL: str = "3/10minute"

    class Config:
        env_file = ".env"
        case_sensitive = True


settings = Settings()
```

### 1.3 使用例

```python
# メール送信時
reset_url = f"{settings.FRONTEND_URL}/auth/reset-password#token={token}"

# トークン作成時
await crud_password_reset.create_token(
    db,
    staff_id=staff.id,
    token=token,
    expires_in_hours=settings.PASSWORD_RESET_TOKEN_EXPIRE_HOURS
)

# レート制限
@limiter.limit(settings.RATE_LIMIT_FORGOT_PASSWORD)
async def forgot_password(...):
    ...
```

---

## 2. クリーンアップジョブ実装

期限切れトークンを定期的に削除するクリーンアップジョブの実装。

### 2.1 Celeryタスク実装

`app/tasks/cleanup_tasks.py`:

```python
from celery import shared_task
from sqlalchemy.ext.asyncio import create_async_engine, async_sessionmaker
from app.core.config import settings
from app.crud import password_reset as crud_password_reset
import logging

logger = logging.getLogger(__name__)


@shared_task(name="cleanup_expired_password_reset_tokens")
def cleanup_expired_tokens():
    """
    期限切れのパスワードリセットトークンを削除する

    実行頻度: 毎日1回（深夜推奨）
    """
    import asyncio

    async def _cleanup():
        # 非同期エンジンとセッションを作成
        engine = create_async_engine(settings.DATABASE_URL)
        async_session = async_sessionmaker(engine, expire_on_commit=False)

        async with async_session() as session:
            try:
                deleted_count = await crud_password_reset.delete_expired_tokens(session)
                await session.commit()
                logger.info(f"Deleted {deleted_count} expired password reset tokens")
                return deleted_count
            except Exception as e:
                logger.error(f"Error cleaning up expired tokens: {str(e)}")
                await session.rollback()
                raise
            finally:
                await engine.dispose()

    # 非同期関数を同期的に実行
    return asyncio.run(_cleanup())
```

### 2.2 Celery Beat スケジュール設定

`app/core/celery_config.py`:

```python
from celery.schedules import crontab

beat_schedule = {
    'cleanup-expired-password-reset-tokens': {
        'task': 'cleanup_expired_password_reset_tokens',
        'schedule': crontab(hour=3, minute=0),  # 毎日午前3時に実行
    },
}
```

### 2.3 代替: cronジョブ実装

Celeryを使用しない場合、cronジョブで直接実行する管理コマンドを作成：

`app/cli/cleanup.py`:

```python
import asyncio
import typer
from sqlalchemy.ext.asyncio import create_async_engine, async_sessionmaker
from app.core.config import settings
from app.crud import password_reset as crud_password_reset

app = typer.Typer()


@app.command()
def cleanup_expired_tokens():
    """期限切れのパスワードリセットトークンを削除"""

    async def _cleanup():
        engine = create_async_engine(settings.DATABASE_URL)
        async_session = async_sessionmaker(engine, expire_on_commit=False)

        async with async_session() as session:
            try:
                deleted_count = await crud_password_reset.delete_expired_tokens(session)
                await session.commit()
                typer.echo(f"✓ Deleted {deleted_count} expired password reset tokens")
                return deleted_count
            except Exception as e:
                typer.echo(f"✗ Error: {str(e)}", err=True)
                await session.rollback()
                raise
            finally:
                await engine.dispose()

    asyncio.run(_cleanup())


if __name__ == "__main__":
    app()
```

crontabに追加:

```bash
# 毎日午前3時に実行
0 3 * * * cd /path/to/project && python -m app.cli.cleanup cleanup-expired-tokens
```

---

## 3. 監視とアラート

### 3.1 監視項目

#### 3.1.1 パフォーマンス監視

- **パスワードリセット要求の応答時間**
  - 目標: 500ms以下
  - アラート閾値: 1秒以上

- **トークン検証の応答時間**
  - 目標: 100ms以下
  - アラート閾値: 500ms以上

#### 3.1.2 エラー監視

- **パスワードリセット失敗率**
  - 目標: 1%以下
  - アラート閾値: 5%以上

- **メール送信失敗率**
  - 目標: 0.1%以下
  - アラート閾値: 1%以上

#### 3.1.3 セキュリティ監視

- **レート制限違反の頻度**
  - アラート閾値: 10回/時間以上

- **無効なトークンでのアクセス試行**
  - アラート閾値: 100回/日以上

### 3.2 監査ログ分析

#### 3.2.1 異常なパターンの検出

```python
# 同一IPからの大量のリクエスト
SELECT
    ip_address,
    COUNT(*) as request_count,
    COUNT(DISTINCT email) as unique_emails
FROM password_reset_audit_logs
WHERE action = 'requested'
  AND created_at > NOW() - INTERVAL '1 hour'
GROUP BY ip_address
HAVING COUNT(*) > 10
ORDER BY request_count DESC;

# 短時間での複数のメールアドレスへのリクエスト
SELECT
    email,
    COUNT(*) as request_count,
    MIN(created_at) as first_request,
    MAX(created_at) as last_request
FROM password_reset_audit_logs
WHERE action = 'requested'
  AND created_at > NOW() - INTERVAL '10 minutes'
GROUP BY email
HAVING COUNT(*) > 3
ORDER BY request_count DESC;
```

#### 3.2.2 監査ログの保持期間

- **推奨保持期間**: 1年
- **定期削除**: 年次で古いログを削除（法的要件に応じて調整）

```sql
-- 1年以上前の監査ログを削除
DELETE FROM password_reset_audit_logs
WHERE created_at < NOW() - INTERVAL '1 year';
```

---

## 4. 注意事項・ベストプラクティス

### 4.1 セキュリティ

#### 4.1.1 HTTPS必須
- **本番環境**: 必ずHTTPSを使用する
- **開発環境**: HTTPでも可（ただし本番に近い環境でHTTPSテスト推奨）

#### 4.1.2 トークンの取り扱い

**DO**:
- ✅ トークンはSHA-256でハッシュ化してDB保存
- ✅ URLフラグメント識別子（#token=xxx）を使用
- ✅ トークン有効期限は短め（1時間推奨）
- ✅ トークンは一度しか使用できないようにする

**DON'T**:
- ❌ トークンを平文でDB保存しない
- ❌ クエリパラメータ（?token=xxx）でトークンを渡さない
- ❌ トークンを再利用可能にしない
- ❌ 長すぎる有効期限（24時間以上）を設定しない

#### 4.1.3 レート制限

```python
# forgot-password: 5回/10分
@limiter.limit("5/10minute")

# resend: 3回/10分（より厳しく）
@limiter.limit("3/10minute")
```

**調整のガイドライン**:
- 攻撃検知時: レート制限を一時的に厳しくする
- 正当なユーザーが困難を感じる場合: 緩和を検討（ただし慎重に）

#### 4.1.4 ユーザー存在の推測防止

```python
# 存在しないメールアドレスでも成功レスポンスを返す
return PasswordResetResponse(
    message=ja.AUTH_PASSWORD_RESET_EMAIL_SENT
)
```

#### 4.1.5 セッション無効化

```python
# パスワード変更後は全セッションを無効化
stmt = (
    update(Session)
    .where(Session.staff_id == staff.id)
    .values(is_active=False, revoked_at=datetime.now(timezone.utc))
)
await db.execute(stmt)
```

### 4.2 ユーザビリティ

#### 4.2.1 明確なエラーメッセージ

**良い例**:
- ✅ 「トークンが無効または期限切れです。新しいリセットリンクをリクエストしてください。」
- ✅ 「このトークンは既に使用されています。新しいリセットリンクをリクエストしてください。」

**悪い例**:
- ❌ 「エラーが発生しました」
- ❌ 「無効なトークン」

#### 4.2.2 メール送信の確認

- メール送信完了メッセージの表示
- メールが届かない場合の対処法の提供
- 再送信機能の提供

### 4.3 トランザクション管理

**重要な原則**:

1. **DB変更をコミット**
2. **その後にメール送信**
3. **メール送信失敗してもロールバックしない**

```python
# 正しい実装
await db.commit()  # 1. DBコミット
await send_password_reset_email(...)  # 2. メール送信

# 間違った実装
await send_password_reset_email(...)  # NG: コミット前にメール送信
await db.commit()
```

**理由**:
- メール送信は外部サービスに依存
- メール送信失敗時にトークンが作成されていないと、ユーザーがリトライできない
- トークンが既に作成されていれば、管理者が手動でメール送信することも可能

---

## 5. TODO チェックリスト

### 5.1 バックエンド実装

- [ ] DBマイグレーションファイル作成
  - [ ] `password_reset_tokens` テーブル（token_hashカラム）
  - [ ] `password_reset_audit_logs` テーブル
  - [ ] 複合インデックス作成
- [ ] `PasswordResetToken` モデル実装（token_hashフィールド）
- [ ] `PasswordResetAuditLog` モデル実装
- [ ] `Staff` モデルにリレーション追加
- [ ] CRUD操作実装（`crud_password_reset.py`）
  - [ ] トークンハッシュ化ヘルパー関数（`hash_reset_token`）
  - [ ] 楽観的ロック実装（`mark_as_used`）
  - [ ] 監査ログCRUD操作（`create_audit_log`）
- [ ] スキーマ定義（`schemas/auth.py`）
- [ ] メール送信関数実装（`core/mail.py`）
  - [ ] URLフラグメント識別子使用（#token=xxx）
  - [ ] トランザクション外でのメール送信
- [ ] メールテンプレート作成
  - [ ] `templates/email/password_reset.html`
  - [ ] `templates/email/password_changed.html`
- [ ] エンドポイント実装（`api/v1/endpoints/auths.py`）
  - [ ] ヘルパー関数（`get_client_ip`, `get_user_agent`）
  - [ ] `POST /forgot-password`（監査ログ付き）
  - [ ] `POST /resend-reset-email`（厳しいレート制限）
  - [ ] `GET /verify-reset-token`（監査ログ付き）
  - [ ] `POST /reset-password`（セッション無効化・監査ログ付き）
- [ ] メッセージ定義（`messages/ja.py`）
  - [ ] 具体的なエラーメッセージ

### 5.2 テスト実装

- [ ] モデルのユニットテスト
  - [ ] `PasswordResetToken` モデル
  - [ ] `PasswordResetAuditLog` モデル
- [ ] CRUDのユニットテスト
  - [ ] トークンハッシュ化のテスト
  - [ ] 楽観的ロックのテスト（レース条件）
  - [ ] 監査ログ作成のテスト
- [ ] エンドポイントの統合テスト（E2E）
  - [ ] パスワードリセットフロー全体
  - [ ] セッション無効化の確認
  - [ ] 監査ログの記録確認
  - [ ] レート制限のテスト
- [ ] セキュリティテスト
  - [ ] トークンハッシュ化の確認
  - [ ] レース条件の確認
  - [ ] SQLインジェクション対策

### 5.3 フロントエンド実装

- [ ] パスワードリセット要求画面（`/forgot-password`）
  - [ ] 再送信機能
- [ ] パスワードリセット実行画面（`/reset-password`）
  - [ ] URLフラグメントからトークン取得
  - [ ] 履歴からフラグメント削除
- [ ] フォームバリデーション
- [ ] エラーハンドリング
- [ ] ユーザーフィードバック（成功/エラーメッセージ）

### 5.4 運用・監視

- [ ] 監査ログ実装完了
  - [ ] IPアドレス記録
  - [ ] User-Agent記録
  - [ ] アクション種別記録
- [ ] 期限切れトークンのクリーンアップジョブ（定期実行）
  - [ ] Celeryタスク実装
  - [ ] cronジョブ設定
- [ ] 監査ログ分析ツール
  - [ ] 異常なリクエストパターン検出
  - [ ] アラート設定
- [ ] 環境変数設定
  - [ ] `FRONTEND_URL`
  - [ ] トークン有効期限設定

---

## 6. 将来の拡張案

### 6.1 機能拡張

#### 6.1.1 パスワード履歴管理
- 過去のパスワードの再利用を防ぐ
- 最近3〜5回のパスワードハッシュを記録
- 新しいパスワードが過去のパスワードと一致しないことを確認

```python
# パスワード履歴テーブル
CREATE TABLE password_histories (
    id UUID PRIMARY KEY,
    staff_id UUID REFERENCES staffs(id),
    password_hash VARCHAR(255),
    created_at TIMESTAMP WITH TIME ZONE
);
```

#### 6.1.2 多要素認証（MFA）との統合
- パスワードリセット時に追加の認証要求
- SMS/TOTPでの本人確認
- より高いセキュリティレベル

#### 6.1.3 パスワード強度チェッカー
- リアルタイムでパスワード強度を表示
- よくあるパスワードのブロック
- 漏洩パスワードデータベースとの照合（HaveIBeenPwned API）

#### 6.1.4 SMS/電話によるパスワードリセット
- メール以外の代替手段
- 携帯電話番号による本人確認
- SMS/音声通話でのワンタイムコード送信

### 6.2 UX改善

#### 6.2.1 パスワードリセットフローのステップ表示
```
Step 1: メールアドレス入力
  ↓
Step 2: メール確認
  ↓
Step 3: 新しいパスワード設定
  ↓
Step 4: 完了
```

#### 6.2.2 パスワード変更完了後の自動ログイン
- オプション: ユーザーの選択に応じて
- セキュリティとUXのバランス

### 6.3 監査・コンプライアンス

#### 6.3.1 GDPR対応
- 個人データの管理・削除
- ユーザーによるデータエクスポート要求
- プライバシーポリシーの明記

#### 6.3.2 管理者向けダッシュボード
- パスワードリセット統計
- 監査ログの検索・フィルタリング
- 異常なアクセスパターンの可視化

```python
# パスワードリセット統計
SELECT
    DATE(created_at) as date,
    COUNT(*) as total_requests,
    COUNT(CASE WHEN success = TRUE THEN 1 END) as successful,
    COUNT(CASE WHEN success = FALSE THEN 1 END) as failed
FROM password_reset_audit_logs
WHERE action = 'requested'
  AND created_at > NOW() - INTERVAL '30 days'
GROUP BY DATE(created_at)
ORDER BY date DESC;
```

---

## 7. デプロイチェックリスト

### 7.1 本番デプロイ前

- [ ] 全テストがパス（カバレッジ80%以上）
- [ ] セキュリティレビュー完了
- [ ] 環境変数設定確認（`.env.production`）
- [ ] HTTPS設定確認
- [ ] レート制限設定確認
- [ ] メール送信設定確認（本番SMTPサーバー）
- [ ] 監査ログ確認（書き込み可能）
- [ ] クリーンアップジョブ設定確認

### 7.2 デプロイ後

- [ ] パスワードリセットフローのE2Eテスト（本番環境）
- [ ] メール送信確認（実際のメールアドレス）
- [ ] レート制限動作確認
- [ ] 監査ログ記録確認
- [ ] 監視・アラート設定確認
- [ ] ドキュメント更新（運用マニュアル）

---

## 8. トラブルシューティング

### 8.1 よくある問題

#### 8.1.1 メールが届かない

**原因**:
- SMTPサーバーの設定ミス
- スパムフィルタによるブロック
- メールアドレスのタイプミス

**対処法**:
1. 監査ログで送信履歴を確認
2. SMTPサーバーのログを確認
3. スパムフォルダを確認
4. 再送信機能を使用

#### 8.1.2 トークンが無効と表示される

**原因**:
- 期限切れ（1時間経過）
- 既に使用済み
- トークンの入力ミス

**対処法**:
1. 新しいリセットリンクをリクエスト
2. 監査ログでトークンの状態を確認
3. URLフラグメントが正しく読み込まれているか確認

#### 8.1.3 レート制限に引っかかる

**原因**:
- 短時間に複数回リクエスト
- 同一IPから大量のリクエスト

**対処法**:
1. しばらく待ってから再試行
2. 管理者に連絡（正当な理由がある場合）
3. IPベースの制限を一時的に解除（管理者）

---

## まとめ

パスワードリセット機能の実装を5つのフェーズに分けて詳細に記載しました：

1. **Phase 1: 設計フェーズ** - 要件定義、API設計
2. **Phase 2: データベースフェーズ** - DB設計、マイグレーション、ORM モデル
3. **Phase 3: バックエンド実装フェーズ** - CRUD、エンドポイント、メール送信
4. **Phase 4: テストフェーズ** - ユニットテスト、統合テスト、セキュリティテスト
5. **Phase 5: 運用フェーズ** - 環境変数、クリーンアップ、監視、保守

各フェーズを順番に実装することで、安全で信頼性の高いパスワードリセット機能を構築できます。
