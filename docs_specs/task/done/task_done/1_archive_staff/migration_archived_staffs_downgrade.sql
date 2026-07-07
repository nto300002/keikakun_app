-- ║  archived_staffsテーブル削除 (DOWNGRADE)
-- Revision ID: f4g5h6i7j8k9
-- Revises to: e3f4g5h6i7j8
--
-- 警告:
--   このスクリプトはアーカイブテーブルとすべてのデータを削除します
--   法定保存期間中のデータも失われるため、慎重に実行してください
--

BEGIN;

-- ========================================
-- 削除前確認（オプション）
-- ========================================

-- アーカイブ件数確認
SELECT
    COUNT(*) as total_archives,
    COUNT(*) FILTER (WHERE is_test_data = false) as production_archives,
    COUNT(*) FILTER (WHERE is_test_data = true) as test_archives,
    MIN(archived_at) as oldest_archive,
    MAX(archived_at) as newest_archive
FROM archived_staffs;

-- 保存期限内のレコード確認
SELECT
    COUNT(*) as active_retention_count,
    MIN(legal_retention_until) as earliest_expiry
FROM archived_staffs
WHERE legal_retention_until > now();

-- インデックス削除
DROP INDEX IF EXISTS idx_archived_staffs_is_test_data;
DROP INDEX IF EXISTS idx_archived_staffs_retention_until;
DROP INDEX IF EXISTS idx_archived_staffs_archived_at;
DROP INDEX IF EXISTS idx_archived_staffs_terminated_at;
DROP INDEX IF EXISTS idx_archived_staffs_office_id;
DROP INDEX IF EXISTS idx_archived_staffs_original_id;

-- テーブル削除
DROP TABLE IF EXISTS archived_staffs;

COMMIT;

-- ========================================
-- 削除確認
-- ========================================

-- テーブルが存在しないことを確認
SELECT
    table_name
FROM information_schema.tables
WHERE table_name = 'archived_staffs';
-- (0件が返されるべき)
