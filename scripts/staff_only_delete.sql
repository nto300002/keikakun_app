-- staffのみ削除するSQL
--
-- 目的:
-- - 既存officeは削除しない。
-- - 削除対象staffのoffice所属だけを仮officeへ移動し、その仮officeと所属行を削除する。
-- - offices.created_by / offices.last_modified_by など、staff削除を阻害する参照は
--   削除対象以外の保持用staffへ付け替える。
--
-- 使い方:
-- 1. params.delete_staff_id を削除対象staff IDに変更する。
-- 2. 事前確認クエリを実行して、対象が正しいことを確認する。
-- 3. 削除SQLはまず末尾を ROLLBACK のまま実行して件数を確認する。
-- 4. 問題なければ末尾を COMMIT に変更して再実行する。

-- ============================
-- 1. 事前確認
-- ============================
WITH params AS (
  SELECT '7654fff4-9fb2-495d-81d5-bd947290908a'::uuid AS delete_staff_id
)
SELECT
  s.id AS staff_id,
  s.email AS staff_email,
  s.name AS staff_name,
  s.full_name AS staff_full_name,
  os.office_id,
  o.name AS office_name,
  os.is_primary,
  o.created_by = s.id AS is_office_created_by_target,
  o.last_modified_by = s.id AS is_office_last_modified_by_target
FROM params p
JOIN staffs s ON s.id = p.delete_staff_id
LEFT JOIN office_staffs os ON os.staff_id = s.id
LEFT JOIN offices o ON o.id = os.office_id
ORDER BY o.created_at DESC NULLS LAST;

-- staffを参照する外部キーの削除動作を確認する。
-- confdeltype: c=CASCADE, n=SET NULL, a=NO ACTION/RESTRICT相当
SELECT
  conrelid::regclass AS referencing_table,
  conname,
  array_agg(att.attname ORDER BY ord.ordinality) AS referencing_columns,
  confdeltype
FROM pg_constraint con
JOIN unnest(con.conkey) WITH ORDINALITY AS ord(attnum, ordinality) ON true
JOIN pg_attribute att
  ON att.attrelid = con.conrelid
 AND att.attnum = ord.attnum
WHERE con.contype = 'f'
  AND con.confrelid = 'staffs'::regclass
GROUP BY conrelid, conname, confdeltype
ORDER BY conrelid::regclass::text, conname;

-- 削除対象staffが作成者/更新者になっているoffice。
-- このSQLではofficeを残し、保持用staffへ付け替える。
WITH params AS (
  SELECT '7654fff4-9fb2-495d-81d5-bd947290908a'::uuid AS delete_staff_id
)
SELECT
  o.id AS office_id,
  o.name AS office_name,
  o.created_by,
  o.last_modified_by,
  o.deleted_by
FROM params p
JOIN offices o
  ON o.created_by = p.delete_staff_id
  OR o.last_modified_by = p.delete_staff_id
  OR o.deleted_by = p.delete_staff_id
ORDER BY o.created_at DESC;

-- ============================
-- 2. staffのみ削除
-- ============================
BEGIN;

CREATE TEMP TABLE target_delete_staff AS
SELECT '7654fff4-9fb2-495d-81d5-bd947290908a'::uuid AS staff_id;

-- 既存officeを残すために、created_by / last_modified_by などの退避先にするstaff。
-- 必要なら WHERE 条件を固定IDに変更する。
CREATE TEMP TABLE replacement_staff AS
SELECT s.id AS staff_id
FROM staffs s
WHERE s.id <> (SELECT staff_id FROM target_delete_staff)
  AND s.is_deleted = false
ORDER BY
  CASE s.role
    WHEN 'app_admin' THEN 1
    WHEN 'owner' THEN 2
    WHEN 'manager' THEN 3
    ELSE 4
  END,
  s.created_at ASC
LIMIT 1;

DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1
    FROM staffs
    WHERE id = (SELECT staff_id FROM target_delete_staff)
  ) THEN
    RAISE EXCEPTION 'delete target staff does not exist: %',
      (SELECT staff_id FROM target_delete_staff);
  END IF;

  IF NOT EXISTS (SELECT 1 FROM replacement_staff) THEN
    RAISE EXCEPTION 'replacement staff does not exist. staff-only delete cannot keep offices with NOT NULL staff FKs.';
  END IF;
END $$;

CREATE TEMP TABLE delete_work_office AS
SELECT gen_random_uuid() AS office_id;

-- 削除対象staffを所属させる仮office。
-- 後続でこのofficeは削除するため、既存officeには影響させない。
INSERT INTO offices (
  id,
  name,
  is_group,
  type,
  created_by,
  last_modified_by,
  is_test_data
)
SELECT
  dwo.office_id,
  'DELETE_WORK_OFFICE_FOR_STAFF_' || tds.staff_id::text,
  false,
  'type_B_office'::officetype,
  tds.staff_id,
  tds.staff_id,
  true
FROM delete_work_office dwo
CROSS JOIN target_delete_staff tds;

-- 削除対象staffの所属を既存officeから仮officeへ移動する。
-- これにより、既存officeを残したまま対象staffの所属だけを切り離せる。
UPDATE office_staffs
SET
  office_id = (SELECT office_id FROM delete_work_office),
  is_primary = true,
  updated_at = now()
WHERE staff_id = (SELECT staff_id FROM target_delete_staff);

-- staff削除を阻害するNO ACTION系の参照を、削除対象以外のstaffへ付け替える。
UPDATE offices
SET
  created_by = CASE
    WHEN created_by = (SELECT staff_id FROM target_delete_staff)
      THEN (SELECT staff_id FROM replacement_staff)
    ELSE created_by
  END,
  last_modified_by = CASE
    WHEN last_modified_by = (SELECT staff_id FROM target_delete_staff)
      THEN (SELECT staff_id FROM replacement_staff)
    ELSE last_modified_by
  END,
  deleted_by = CASE
    WHEN deleted_by = (SELECT staff_id FROM target_delete_staff)
      THEN NULL
    ELSE deleted_by
  END,
  updated_at = now()
WHERE created_by = (SELECT staff_id FROM target_delete_staff)
   OR last_modified_by = (SELECT staff_id FROM target_delete_staff)
   OR deleted_by = (SELECT staff_id FROM target_delete_staff);

UPDATE plan_deliverables
SET uploaded_by = (SELECT staff_id FROM replacement_staff)
WHERE uploaded_by = (SELECT staff_id FROM target_delete_staff);

UPDATE support_plan_statuses
SET completed_by = (SELECT staff_id FROM replacement_staff)
WHERE completed_by = (SELECT staff_id FROM target_delete_staff);

UPDATE staffs
SET deleted_by = NULL
WHERE deleted_by = (SELECT staff_id FROM target_delete_staff);

-- SET NULL想定の参照は明示的にNULL化する。
UPDATE audit_logs
SET staff_id = NULL
WHERE staff_id = (SELECT staff_id FROM target_delete_staff);

UPDATE approval_requests
SET reviewed_by_staff_id = NULL
WHERE reviewed_by_staff_id = (SELECT staff_id FROM target_delete_staff);

UPDATE inquiry_details
SET assigned_staff_id = NULL
WHERE assigned_staff_id = (SELECT staff_id FROM target_delete_staff);

UPDATE message_audit_logs
SET staff_id = NULL
WHERE staff_id = (SELECT staff_id FROM target_delete_staff);

UPDATE messages
SET sender_staff_id = NULL
WHERE sender_staff_id = (SELECT staff_id FROM target_delete_staff);

UPDATE offices
SET deleted_by = NULL
WHERE deleted_by = (SELECT staff_id FROM target_delete_staff);

UPDATE password_reset_audit_logs
SET staff_id = NULL
WHERE staff_id = (SELECT staff_id FROM target_delete_staff);

-- 仮officeに移動した所属行を削除する。
-- office_staffs.office_id / staff_id は現行スナップショットではCASCADEなしのため明示削除する。
DELETE FROM office_staffs
WHERE office_id = (SELECT office_id FROM delete_work_office)
  AND staff_id = (SELECT staff_id FROM target_delete_staff);

-- 仮office本体を削除する。既存officeは削除しない。
DELETE FROM offices
WHERE id = (SELECT office_id FROM delete_work_office);

-- staff本体を削除する。
-- CASCADE制約のある関連データはここで削除される。
DELETE FROM staffs
WHERE id = (SELECT staff_id FROM target_delete_staff);

-- ============================
-- 3. トランザクション内の削除後確認
-- ============================
SELECT
  'staffs' AS table_name,
  count(*) AS remaining_count
FROM staffs
WHERE id = (SELECT staff_id FROM target_delete_staff)
UNION ALL
SELECT
  'office_staffs' AS table_name,
  count(*) AS remaining_count
FROM office_staffs
WHERE staff_id = (SELECT staff_id FROM target_delete_staff)
UNION ALL
SELECT
  'offices_created_by_or_last_modified_by' AS table_name,
  count(*) AS remaining_count
FROM offices
WHERE created_by = (SELECT staff_id FROM target_delete_staff)
   OR last_modified_by = (SELECT staff_id FROM target_delete_staff)
   OR deleted_by = (SELECT staff_id FROM target_delete_staff)
UNION ALL
SELECT
  'delete_work_office' AS table_name,
  count(*) AS remaining_count
FROM offices
WHERE id = (SELECT office_id FROM delete_work_office);

-- 最初はROLLBACKで確認する。問題なければCOMMITへ変更して再実行する。
ROLLBACK;
-- COMMIT;
