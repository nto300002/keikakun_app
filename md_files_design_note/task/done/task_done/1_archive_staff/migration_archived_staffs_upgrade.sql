-- ║  archived_staffsテーブル作成 (UPGRADE)
-- Revision ID: f4g5h6i7j8k9
-- Revises: e3f4g5h6i7j8
-- Create Date: 2025-12-02 14:00:00.000000
--
-- 法定要件:
--   - 労働基準法第109条：労働者名簿を退職後5年間保存
--   - 障害者総合支援法：サービス提供記録を5年間保存
--   - 個人情報保護法：個人識別情報は匿名化

BEGIN;

-- ========================================
-- archived_staffs テーブル作成
-- ========================================

CREATE TABLE archived_staffs (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    original_staff_id UUID NOT NULL,
    anonymized_full_name VARCHAR(255) NOT NULL,
    anonymized_email VARCHAR(255) NOT NULL,
    role VARCHAR(20) NOT NULL,
    office_id UUID,
    office_name VARCHAR(255),
    hired_at TIMESTAMP WITH TIME ZONE NOT NULL,
    terminated_at TIMESTAMP WITH TIME ZONE NOT NULL,
    archived_at TIMESTAMP WITH TIME ZONE NOT NULL DEFAULT now(),
    archive_reason VARCHAR(50) NOT NULL,
    legal_retention_until TIMESTAMP WITH TIME ZONE NOT NULL,
    metadata JSONB,
    is_test_data BOOLEAN NOT NULL DEFAULT false,
    created_at TIMESTAMP WITH TIME ZONE NOT NULL DEFAULT now()
);

-- ========================================
-- インデックス作成
-- ========================================

CREATE INDEX idx_archived_staffs_original_id ON archived_staffs(original_staff_id);
CREATE INDEX idx_archived_staffs_office_id ON archived_staffs(office_id);
CREATE INDEX idx_archived_staffs_terminated_at ON archived_staffs(terminated_at);
CREATE INDEX idx_archived_staffs_archived_at ON archived_staffs(archived_at);
CREATE INDEX idx_archived_staffs_retention_until ON archived_staffs(legal_retention_until);
CREATE INDEX idx_archived_staffs_is_test_data ON archived_staffs(is_test_data);

-- ========================================
-- カラムコメント
-- ========================================

COMMENT ON TABLE archived_staffs IS '法定保存義務に基づくスタッフアーカイブ（労働基準法・障害者総合支援法対応）';

COMMENT ON COLUMN archived_staffs.original_staff_id IS '元のスタッフID（参照整合性なし）';
COMMENT ON COLUMN archived_staffs.anonymized_full_name IS '匿名化された氏名（例: スタッフ-ABC123）';
COMMENT ON COLUMN archived_staffs.anonymized_email IS '匿名化されたメール（例: archived-ABC123@deleted.local）';
COMMENT ON COLUMN archived_staffs.role IS '役職（owner/manager/employee）';
COMMENT ON COLUMN archived_staffs.office_id IS '所属していた事務所ID（参照整合性なし）';
COMMENT ON COLUMN archived_staffs.office_name IS '事務所名（スナップショット）';
COMMENT ON COLUMN archived_staffs.hired_at IS '雇入れ日（元のcreated_at）';
COMMENT ON COLUMN archived_staffs.terminated_at IS '退職日（deleted_at）';
COMMENT ON COLUMN archived_staffs.archived_at IS 'アーカイブ作成日時';
COMMENT ON COLUMN archived_staffs.archive_reason IS 'アーカイブ理由（staff_deletion/staff_withdrawal/office_withdrawal）';
COMMENT ON COLUMN archived_staffs.legal_retention_until IS '法定保存期限（terminated_at + 5年）';
COMMENT ON COLUMN archived_staffs.metadata IS 'その他の法定保存が必要なメタデータ';
COMMENT ON COLUMN archived_staffs.is_test_data IS 'テストデータフラグ';

COMMIT;

-- ========================================
-- 確認クエリ
-- ========================================

-- テーブル作成確認
SELECT
    table_name,
    table_type
FROM information_schema.tables
WHERE table_name = 'archived_staffs';

-- カラム確認
SELECT
    column_name,
    data_type,
    is_nullable,
    column_default
FROM information_schema.columns
WHERE table_name = 'archived_staffs'
ORDER BY ordinal_position;

-- インデックス確認
SELECT
    indexname,
    indexdef
FROM pg_indexes
WHERE tablename = 'archived_staffs';
