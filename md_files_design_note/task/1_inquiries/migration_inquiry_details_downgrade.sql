-- ============================================================================
-- 問い合わせ機能 - inquiry_details テーブル削除マイグレーション (DOWNGRADE)
-- Revision ID: inquiry_001
-- Create Date: 2025-12-03
-- Description: inquiry_detailsテーブルとenum型を削除
-- ============================================================================

-- ============================================================================
-- DOWNGRADE: テーブル、トリガー、関数、enum型の削除
-- ============================================================================

-- 1. トリガーを削除
DROP TRIGGER IF EXISTS trigger_update_inquiry_details_timestamp ON inquiry_details;

-- 2. トリガー関数を削除
DROP FUNCTION IF EXISTS update_inquiry_details_updated_at();

-- 3. inquiry_details テーブルを削除（CASCADE で関連するインデックスも削除）
DROP TABLE IF EXISTS inquiry_details CASCADE;

-- 4. enum型を削除
DROP TYPE IF EXISTS inquiry_status;
DROP TYPE IF EXISTS inquiry_priority;

-- ============================================================================
-- ダウングレード完了
-- ============================================================================
