-- マイグレーション: システム事務所検索の高速化
-- Office テーブルに name + is_deleted の複合インデックスを追加

-- UPGRADE
-- システム事務所検索を高速化するための複合インデックス
-- get_or_create_system_office() で使用
CREATE INDEX IF NOT EXISTS ix_offices_name_is_deleted ON offices (name, is_deleted);

-- DOWNGRADE
-- DROP INDEX IF EXISTS ix_offices_name_is_deleted;
