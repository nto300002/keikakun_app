-- ==========================================
-- セキュリティレビュー対応: password_reset_tokensテーブルへのカラム追加
-- ==========================================
-- 作成日: 2025-11-20
-- 目的: トークン有効期限30分、楽観的ロック、監査ログ強化

-- ==========================================
-- UPGRADE (カラム追加)
-- ==========================================

-- 1. 楽観的ロック用バージョン番号を追加
ALTER TABLE password_reset_tokens
ADD COLUMN version INTEGER NOT NULL DEFAULT 0;

-- 2. リクエスト元IPアドレスを追加（IPv6対応: 最大45文字）
ALTER TABLE password_reset_tokens
ADD COLUMN request_ip VARCHAR(45) NULL;

-- 3. リクエスト元User-Agentを追加
ALTER TABLE password_reset_tokens
ADD COLUMN request_user_agent VARCHAR(500) NULL;

-- ==========================================
-- DOWNGRADE (ロールバック: カラム削除)
-- ==========================================

-- 注意: 本番環境でロールバックを実行する前に、必ずバックアップを取得してください

-- 3. User-Agentカラムを削除
-- ALTER TABLE password_reset_tokens
-- DROP COLUMN request_user_agent;

-- 2. IPアドレスカラムを削除
-- ALTER TABLE password_reset_tokens
-- DROP COLUMN request_ip;

-- 1. バージョン番号カラムを削除
-- ALTER TABLE password_reset_tokens
-- DROP COLUMN version;

-- ==========================================
-- 補足情報
-- ==========================================

-- 【楽観的ロックの使用方法】
-- トークン更新時に以下のようなクエリを使用:
-- UPDATE password_reset_tokens
-- SET used = true,
--     used_at = NOW(),
--     version = version + 1
-- WHERE id = :token_id
--   AND version = :current_version
--   AND used = false;
--
-- 影響を受けた行数が0の場合、既に他のリクエストで使用済み（競合検出）

-- 【リクエスト元情報の記録】
-- トークン生成時にIPアドレスとUser-Agentを記録:
-- - 異常なアクセスパターンの検出
-- - セキュリティ監査ログとして使用
-- - IPアドレスの不一致時に警告（ただしブロックはしない）

-- 【トークン有効期限の変更】
-- セキュリティレビューにより、1時間→30分に短縮:
-- expires_at = NOW() + INTERVAL '30 minutes'
