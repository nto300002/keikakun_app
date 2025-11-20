-- 古い通知データのクリーンアップスクリプト
-- 実行日: 2025-11-10

-- 1. 古いNoticeType（'role_change_request', 'employee_action_request'）を持つ通知を確認
SELECT
    id,
    type,
    title,
    created_at,
    link_url
FROM notices
WHERE type IN ('role_change_request', 'employee_action_request')
ORDER BY created_at DESC;

-- 2. 古いNoticeTypeを持つ通知を削除（実行前に必ずバックアップを取ること！）
-- DELETE FROM notices
-- WHERE type IN ('role_change_request', 'employee_action_request');

-- 3. 承認済み/却下済みリクエストに対応するpending通知を確認
-- role_change_requestsで承認/却下済みのリクエスト
SELECT
    n.id as notice_id,
    n.type as notice_type,
    n.title,
    n.link_url,
    r.id as request_id,
    r.status as request_status,
    r.created_at as request_created,
    r.reviewed_at as request_reviewed
FROM notices n
LEFT JOIN role_change_requests r ON n.link_url = '/role-change-requests/' || r.id::text
WHERE n.type = 'role_change_pending'
  AND r.status IN ('approved', 'rejected')
ORDER BY r.reviewed_at DESC;

-- employee_action_requestsで承認/却下済みのリクエスト
SELECT
    n.id as notice_id,
    n.type as notice_type,
    n.title,
    n.link_url,
    r.id as request_id,
    r.status as request_status,
    r.created_at as request_created,
    r.approved_at as request_approved
FROM notices n
LEFT JOIN employee_action_requests r ON n.link_url = '/employee-action-requests/' || r.id::text
WHERE n.type = 'employee_action_pending'
  AND r.status IN ('approved', 'rejected')
ORDER BY r.approved_at DESC;

-- 4. 承認済みリクエストに対応するpending通知のtypeを更新
-- role_change_requests
UPDATE notices
SET
    type = CASE
        WHEN r.status = 'approved' THEN 'role_change_approved'
        WHEN r.status = 'rejected' THEN 'role_change_rejected'
        ELSE type
    END,
    updated_at = NOW()
FROM role_change_requests r
WHERE notices.link_url = '/role-change-requests/' || r.id::text
  AND notices.type = 'role_change_pending'
  AND r.status IN ('approved', 'rejected');

-- employee_action_requests
UPDATE notices
SET
    type = CASE
        WHEN r.status = 'approved' THEN 'employee_action_approved'
        WHEN r.status = 'rejected' THEN 'employee_action_rejected'
        ELSE type
    END,
    updated_at = NOW()
FROM employee_action_requests r
WHERE notices.link_url = '/employee-action-requests/' || r.id::text
  AND notices.type = 'employee_action_pending'
  AND r.status IN ('approved', 'rejected');

-- 5. 更新後の通知データを確認
SELECT
    type,
    COUNT(*) as count
FROM notices
GROUP BY type
ORDER BY type;

-- 6. （オプション）古い通知を完全に削除する場合
-- すべての古いNoticeTypeを削除
-- DELETE FROM notices
-- WHERE type IN ('role_change_request', 'employee_action_request');

-- 7. 確認：現在の通知の状態
SELECT
    n.id,
    n.type,
    n.title,
    n.created_at,
    n.is_read,
    r.status as request_status
FROM notices n
LEFT JOIN role_change_requests r ON n.link_url = '/role-change-requests/' || r.id::text
WHERE n.type LIKE 'role_change%'
ORDER BY n.created_at DESC
LIMIT 20;

SELECT
    n.id,
    n.type,
    n.title,
    n.created_at,
    n.is_read,
    r.status as request_status
FROM notices n
LEFT JOIN employee_action_requests r ON n.link_url = '/employee-action-requests/' || r.id::text
WHERE n.type LIKE 'employee_action%'
ORDER BY n.created_at DESC
LIMIT 20;
