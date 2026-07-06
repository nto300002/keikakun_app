-- DB performance optimization indexes
-- Target: login/MFA aftermath, protected layout startup, notices, deadline alerts.
-- Database: PostgreSQL
--
-- Execution note:
-- - Run during a low-traffic window.
-- - CREATE INDEX CONCURRENTLY cannot run inside an explicit transaction block.
-- - If your SQL client wraps files in BEGIN/COMMIT automatically, disable that behavior.

-- ============================================================
-- Upgrade
-- ============================================================

-- /notices/unread-count:
-- Supports COUNT(*) by recipient_staff_id + is_read.
-- Also helps unread notification previews ordered by newest first.
CREATE INDEX CONCURRENTLY IF NOT EXISTS idx_notices_recipient_read_created
ON notices (recipient_staff_id, is_read, created_at DESC);

-- /notices list:
-- Supports recipient_staff_id filtered notification list ordered by newest first.
CREATE INDEX CONCURRENTLY IF NOT EXISTS idx_notices_recipient_created
ON notices (recipient_staff_id, created_at DESC);

-- Office-scoped notification operations:
-- Helps office-specific notice maintenance and future office-scoped unread/count queries.
CREATE INDEX CONCURRENTLY IF NOT EXISTS idx_notices_office_created
ON notices (office_id, created_at DESC);

-- Deadline alerts:
-- Supports latest support-plan-cycle lookup and next_renewal_deadline filtering by office.
CREATE INDEX CONCURRENTLY IF NOT EXISTS idx_support_plan_cycles_office_latest_renewal
ON support_plan_cycles (office_id, is_latest_cycle, next_renewal_deadline);

-- Deadline alerts / dashboard summary:
-- Supports joining latest cycle by recipient and office.
CREATE INDEX CONCURRENTLY IF NOT EXISTS idx_support_plan_cycles_recipient_office_latest
ON support_plan_cycles (welfare_recipient_id, office_id, is_latest_cycle);

-- Assessment incomplete detection:
-- Supports NOT EXISTS / EXISTS checks for deliverables by plan cycle and type.
CREATE INDEX CONCURRENTLY IF NOT EXISTS idx_plan_deliverables_cycle_type
ON plan_deliverables (plan_cycle_id, deliverable_type);

-- Latest status / assessment incomplete detection:
-- Supports filtering latest statuses by office and step type.
CREATE INDEX CONCURRENTLY IF NOT EXISTS idx_support_plan_statuses_office_latest_step
ON support_plan_statuses (office_id, is_latest_status, step_type);

-- Keep planner statistics fresh after index creation.
ANALYZE notices;
ANALYZE support_plan_cycles;
ANALYZE support_plan_statuses;
ANALYZE plan_deliverables;

-- ============================================================
-- Verification
-- ============================================================

-- Confirm created indexes.
SELECT
    schemaname,
    tablename,
    indexname,
    indexdef
FROM pg_indexes
WHERE indexname IN (
    'idx_notices_recipient_read_created',
    'idx_notices_recipient_created',
    'idx_notices_office_created',
    'idx_support_plan_cycles_office_latest_renewal',
    'idx_support_plan_cycles_recipient_office_latest',
    'idx_plan_deliverables_cycle_type',
    'idx_support_plan_statuses_office_latest_step'
)
ORDER BY tablename, indexname;

-- Check approximate table sizes and row counts for impact review.
SELECT
    relname AS table_name,
    n_live_tup AS estimated_rows,
    pg_size_pretty(pg_total_relation_size(relid)) AS total_size
FROM pg_stat_user_tables
WHERE relname IN (
    'notices',
    'support_plan_cycles',
    'support_plan_statuses',
    'plan_deliverables'
)
ORDER BY relname;

-- Optional EXPLAIN samples.
-- Replace the UUID values before running.
--
-- EXPLAIN (ANALYZE, BUFFERS)
-- SELECT COUNT(*)
-- FROM notices
-- WHERE recipient_staff_id = '00000000-0000-0000-0000-000000000000'
--   AND is_read = false;
--
-- EXPLAIN (ANALYZE, BUFFERS)
-- SELECT *
-- FROM notices
-- WHERE recipient_staff_id = '00000000-0000-0000-0000-000000000000'
-- ORDER BY created_at DESC
-- LIMIT 20 OFFSET 0;
--
-- EXPLAIN (ANALYZE, BUFFERS)
-- SELECT id, welfare_recipient_id, next_renewal_deadline
-- FROM support_plan_cycles
-- WHERE office_id = '00000000-0000-0000-0000-000000000000'
--   AND is_latest_cycle = true
--   AND next_renewal_deadline IS NOT NULL
-- ORDER BY next_renewal_deadline ASC
-- LIMIT 30;

-- ============================================================
-- Downgrade
-- ============================================================

-- Run only if these indexes need to be removed.
-- DROP INDEX CONCURRENTLY IF EXISTS idx_support_plan_statuses_office_latest_step;
-- DROP INDEX CONCURRENTLY IF EXISTS idx_plan_deliverables_cycle_type;
-- DROP INDEX CONCURRENTLY IF EXISTS idx_support_plan_cycles_recipient_office_latest;
-- DROP INDEX CONCURRENTLY IF EXISTS idx_support_plan_cycles_office_latest_renewal;
-- DROP INDEX CONCURRENTLY IF EXISTS idx_notices_office_created;
-- DROP INDEX CONCURRENTLY IF EXISTS idx_notices_recipient_created;
-- DROP INDEX CONCURRENTLY IF EXISTS idx_notices_recipient_read_created;
