-- ===========================================
-- Migration: audit_logs テーブル統合
-- Direction: UPGRADE
-- Create Date: 2025-11-26
--
-- 既存のaudit_logsテーブルを拡張し、
-- staff_audit_logs, office_audit_logs を統合
-- 既存カラム（維持）:
--   id, staff_id, action, old_value, new_value, ip_address, user_agent, timestamp
-- 追加カラム:
--   actor_role, target_type, target_id, office_id, details, is_test_data
-- ===========================================

BEGIN;

-- 1. 既存のaudit_logsテーブルにカラム追加
-- actor_role: 操作実行時のロール
ALTER TABLE audit_logs ADD COLUMN IF NOT EXISTS actor_role VARCHAR(50);
COMMENT ON COLUMN audit_logs.actor_role IS '実行時のロール';

-- target_type: 対象リソースタイプ
ALTER TABLE audit_logs ADD COLUMN IF NOT EXISTS target_type VARCHAR(50);
COMMENT ON COLUMN audit_logs.target_type IS '対象リソースタイプ: staff, office, withdrawal_request など';

-- target_id: 対象リソースのID
ALTER TABLE audit_logs ADD COLUMN IF NOT EXISTS target_id UUID;
COMMENT ON COLUMN audit_logs.target_id IS '対象リソースのID';

-- office_id: 事務所ID（横断検索用）
ALTER TABLE audit_logs ADD COLUMN IF NOT EXISTS office_id UUID;
COMMENT ON COLUMN audit_logs.office_id IS '事務所ID（横断検索用、app_adminはNULL可）';

-- details: 変更内容（JSONB形式）
ALTER TABLE audit_logs ADD COLUMN IF NOT EXISTS details JSONB;
COMMENT ON COLUMN audit_logs.details IS '変更内容（old_values, new_valuesなど）';

-- is_test_data: テストデータフラグ
ALTER TABLE audit_logs ADD COLUMN IF NOT EXISTS is_test_data BOOLEAN NOT NULL DEFAULT false;
COMMENT ON COLUMN audit_logs.is_test_data IS 'テストデータフラグ';

-- 2. 外部キー制約追加
ALTER TABLE audit_logs
ADD CONSTRAINT fk_audit_logs_office
FOREIGN KEY (office_id) REFERENCES offices(id) ON DELETE SET NULL;

-- 3. インデックス追加
CREATE INDEX IF NOT EXISTS idx_audit_logs_target_type ON audit_logs (target_type);
CREATE INDEX IF NOT EXISTS idx_audit_logs_office_id ON audit_logs (office_id);
CREATE INDEX IF NOT EXISTS idx_audit_logs_is_test_data ON audit_logs (is_test_data);
CREATE INDEX IF NOT EXISTS idx_audit_logs_timestamp ON audit_logs (timestamp);

-- 複合インデックス（よく使う検索パターン用）
CREATE INDEX IF NOT EXISTS idx_audit_logs_office_timestamp ON audit_logs (office_id, timestamp);
CREATE INDEX IF NOT EXISTS idx_audit_logs_action_timestamp ON audit_logs (action, timestamp);

-- 4. 既存データの更新（プロフィール変更ログ）
UPDATE audit_logs
SET
    target_type = 'staff',
    target_id = staff_id,
    details = CASE
        WHEN old_value IS NOT NULL OR new_value IS NOT NULL THEN
            jsonb_build_object(
                'old_value', old_value,
                'new_value', new_value
            )
        ELSE NULL
    END
WHERE target_type IS NULL;

-- 5. staff_audit_logs → audit_logs データ移行
INSERT INTO audit_logs (
    id,
    staff_id,
    actor_role,
    action,
    target_type,
    target_id,
    office_id,
    ip_address,
    user_agent,
    details,
    timestamp,
    is_test_data
)
SELECT
    sal.id,
    sal.performed_by,                           -- staff_id = 操作実行者
    NULL,                                       -- actor_role (取得不可)
    'staff.' || sal.action,                     -- action (例: staff.deleted)
    'staff',                                    -- target_type
    sal.staff_id,                               -- target_id = 対象スタッフ
    (                                           -- office_id (スタッフの所属事務所から取得)
        SELECT os.office_id
        FROM office_staffs os
        WHERE os.staff_id = sal.staff_id
        LIMIT 1
    ),
    sal.ip_address,
    sal.user_agent,
    sal.details,
    sal.created_at,
    false                                       -- is_test_data
FROM staff_audit_logs sal
ON CONFLICT (id) DO NOTHING;

-- 6. office_audit_logs → audit_logs データ移行
INSERT INTO audit_logs (
    id,
    staff_id,
    actor_role,
    action,
    target_type,
    target_id,
    office_id,
    ip_address,
    user_agent,
    details,
    timestamp,
    is_test_data
)
SELECT
    oal.id,
    oal.staff_id,                               -- staff_id = 操作実行者
    NULL,                                       -- actor_role
    oal.action_type,                            -- action (例: office_info_updated)
    'office',                                   -- target_type
    oal.office_id,                              -- target_id = 対象事務所
    oal.office_id,                              -- office_id
    NULL,                                       -- ip_address (元テーブルにカラムなし)
    NULL,                                       -- user_agent (元テーブルにカラムなし)
    CASE
        WHEN oal.details IS NOT NULL THEN oal.details::jsonb
        ELSE NULL
    END,                                        -- details (TEXT → JSONB)
    oal.created_at,
    oal.is_test_data
FROM office_audit_logs oal
ON CONFLICT (id) DO NOTHING;

-- 7. 旧監査ログテーブル削除
DROP TABLE IF EXISTS staff_audit_logs CASCADE;
DROP TABLE IF EXISTS office_audit_logs CASCADE;

COMMIT;
