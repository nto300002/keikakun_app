-- ╔══════════════════════════════════════════════════════════════╗
-- ║  テスト関連データの一括削除スクリプト（修正版）              ║
-- ║  対象: first_name/last_name/full_name に                      ║
-- ║        「テスト」「修復」「エラー」を含むデータ              ║
-- ╚══════════════════════════════════════════════════════════════╝

-- ========================================
-- Part 1: スタッフの削除
-- ========================================
BEGIN;

DO $$
DECLARE
    target_staff_id UUID;
    replacement_staff_id UUID;
    v_count INT;
    total_processed INT := 0;
BEGIN
    RAISE NOTICE '';
    RAISE NOTICE '╔══════════════════════════════════════════════════════════════╗';
    RAISE NOTICE '║              Part 1: スタッフの削除                          ║';
    RAISE NOTICE '╚══════════════════════════════════════════════════════════════╝';
    RAISE NOTICE '';
    
    -- ========================================
    -- 1. 再割当て先のスタッフを先に選択
    -- ========================================
    RAISE NOTICE '🔍 再割当先のスタッフを検索中...';
    
    SELECT s.id INTO replacement_staff_id
    FROM staffs s
    INNER JOIN office_staffs os ON s.id = os.staff_id
    WHERE s.role = 'owner'
      -- ⭐ 修正: first_name, last_name, full_name に除外キーワードが含まれていない
      AND (s.first_name IS NULL OR (
          s.first_name NOT LIKE '%テスト%' 
          AND s.first_name NOT LIKE '%修復%' 
          AND s.first_name NOT LIKE '%エラー%'
      ))
      AND (s.last_name IS NULL OR (
          s.last_name NOT LIKE '%テスト%' 
          AND s.last_name NOT LIKE '%修復%' 
          AND s.last_name NOT LIKE '%エラー%'
      ))
      AND (s.full_name IS NULL OR (
          s.full_name NOT LIKE '%テスト%' 
          AND s.full_name NOT LIKE '%修復%' 
          AND s.full_name NOT LIKE '%エラー%'
      ))
    LIMIT 1;
    
    IF replacement_staff_id IS NULL THEN
        RAISE EXCEPTION '❌ 再割当先の owner が見つかりません。削除を中止します。';
    END IF;
    
    RAISE NOTICE '✓ 再割当先スタッフID: %', replacement_staff_id;
    
    -- 再割当先の名前を表示
    SELECT 
        COALESCE(last_name || ' ' || first_name, full_name, email) 
    INTO v_count
    FROM staffs 
    WHERE id = replacement_staff_id;
    RAISE NOTICE '  名前: %', v_count;
    RAISE NOTICE '';
    
    -- ========================================
    -- 2. 削除対象のスタッフを確認
    -- ========================================
    SELECT COUNT(*) INTO v_count
    FROM staffs
    WHERE first_name LIKE '%テスト%' 
       OR first_name LIKE '%修復%' 
       OR first_name LIKE '%エラー%'
       OR last_name LIKE '%テスト%' 
       OR last_name LIKE '%修復%' 
       OR last_name LIKE '%エラー%'
       OR full_name LIKE '%テスト%' 
       OR full_name LIKE '%修復%' 
       OR full_name LIKE '%エラー%';
    
    RAISE NOTICE '🎯 削除対象スタッフ: % 人', v_count;
    RAISE NOTICE '';
    
    IF v_count = 0 THEN
        RAISE NOTICE '削除対象のスタッフが見つかりません。';
        RETURN;
    END IF;
    
    RAISE NOTICE '========================================';
    
    -- ========================================
    -- 3. 全ての対象スタッフを処理
    -- ========================================
    FOR target_staff_id IN 
        SELECT id 
        FROM staffs
        WHERE first_name LIKE '%テスト%' 
           OR first_name LIKE '%修復%' 
           OR first_name LIKE '%エラー%'
           OR last_name LIKE '%テスト%' 
           OR last_name LIKE '%修復%' 
           OR last_name LIKE '%エラー%'
           OR full_name LIKE '%テスト%' 
           OR full_name LIKE '%修復%' 
           OR full_name LIKE '%エラー%'
    LOOP
        RAISE NOTICE '';
        RAISE NOTICE '処理中のスタッフID: %', target_staff_id;
        
        -- スタッフ名を表示
        SELECT 
            COALESCE(last_name || ' ' || first_name, full_name, email) 
        INTO v_count
        FROM staffs 
        WHERE id = target_staff_id;
        RAISE NOTICE '  名前: %', v_count;
        
        -- ----------------------------------------
        -- 3-1. offices の created_by を再割当て
        -- ----------------------------------------
        UPDATE offices
        SET created_by = replacement_staff_id,
            updated_at = CURRENT_TIMESTAMP
        WHERE created_by = target_staff_id;
        GET DIAGNOSTICS v_count = ROW_COUNT;
        IF v_count > 0 THEN
            RAISE NOTICE '  ✓ offices.created_by を再割当て: % 件', v_count;
        END IF;
        
        -- ----------------------------------------
        -- 3-2. offices の last_modified_by を再割当て
        -- ----------------------------------------
        UPDATE offices
        SET last_modified_by = replacement_staff_id,
            updated_at = CURRENT_TIMESTAMP
        WHERE last_modified_by = target_staff_id;
        GET DIAGNOSTICS v_count = ROW_COUNT;
        IF v_count > 0 THEN
            RAISE NOTICE '  ✓ offices.last_modified_by を再割当て: % 件', v_count;
        END IF;
        
        -- ----------------------------------------
        -- 3-3. support_plan_statuses の completed_by を NULL に
        -- ----------------------------------------
        UPDATE support_plan_statuses
        SET completed_by = NULL
        WHERE completed_by = target_staff_id;
        GET DIAGNOSTICS v_count = ROW_COUNT;
        IF v_count > 0 THEN
            RAISE NOTICE '  ✓ support_plan_statuses.completed_by を NULL に: % 件', v_count;
        END IF;
        
        -- ----------------------------------------
        -- 3-4. plan_deliverables を削除
        -- （uploaded_by が NOT NULL のため）
        -- ----------------------------------------
        DELETE FROM plan_deliverables
        WHERE uploaded_by = target_staff_id;
        GET DIAGNOSTICS v_count = ROW_COUNT;
        IF v_count > 0 THEN
            RAISE NOTICE '  ✓ plan_deliverables を削除: % 件', v_count;
        END IF;
        
        -- ----------------------------------------
        -- 3-5. office_staffs を削除
        -- ----------------------------------------
        DELETE FROM office_staffs
        WHERE staff_id = target_staff_id;
        GET DIAGNOSTICS v_count = ROW_COUNT;
        IF v_count > 0 THEN
            RAISE NOTICE '  ✓ office_staffs を削除: % 件', v_count;
        END IF;
        
        -- ----------------------------------------
        -- 3-6. staff を削除
        -- （ON DELETE CASCADE で以下が自動削除される）
        -- - audit_logs
        -- - email_change_requests
        -- - employment_related (created_by_staff_id)
        -- - mfa_audit_logs
        -- - mfa_backup_codes
        -- - staff_calendar_accounts
        -- - issue_analyses (created_by_staff_id)
        -- - notices (recipient_staff_id)
        -- - password_histories
        -- ----------------------------------------
        DELETE FROM staffs
        WHERE id = target_staff_id;
        RAISE NOTICE '  ✓ スタッフを削除 (CASCADE)';
        
        total_processed := total_processed + 1;
    END LOOP;
    
    RAISE NOTICE '';
    RAISE NOTICE '========================================';
    RAISE NOTICE '✅ Part 1 完了: % 人のスタッフを削除しました', total_processed;
    RAISE NOTICE '========================================';
    RAISE NOTICE '';
    
EXCEPTION
    WHEN OTHERS THEN
        RAISE EXCEPTION '❌ スタッフ削除中にエラー: % (SQLSTATE: %)', SQLERRM, SQLSTATE;
END $$;

COMMIT;


-- ========================================
-- Part 2: 事業所の削除
-- ========================================
BEGIN;

DO $$
DECLARE
    target_office_id UUID;
    v_count INT;
    total_processed INT := 0;
    orphaned_recipients UUID[];
    office_name_display VARCHAR;
BEGIN
    RAISE NOTICE '';
    RAISE NOTICE '╔══════════════════════════════════════════════════════════════╗';
    RAISE NOTICE '║              Part 2: 事業所の削除                            ║';
    RAISE NOTICE '╚══════════════════════════════════════════════════════════════╝';
    RAISE NOTICE '';
    
    -- ========================================
    -- 削除対象の事業所を確認
    -- ========================================
    SELECT COUNT(*) INTO v_count
    FROM offices
    WHERE name LIKE '%テスト%' 
       OR name LIKE '%修復%' 
       OR name LIKE '%エラー%';
    
    RAISE NOTICE '🎯 削除対象事業所: % 件', v_count;
    RAISE NOTICE '';
    
    IF v_count = 0 THEN
        RAISE NOTICE '削除対象の事業所が見つかりません。';
        RETURN;
    END IF;
    
    RAISE NOTICE '========================================';
    
    -- ========================================
    -- 全ての対象事業所を処理
    -- ========================================
    FOR target_office_id, office_name_display IN 
        SELECT id, name 
        FROM offices 
        WHERE name LIKE '%テスト%' 
           OR name LIKE '%修復%' 
           OR name LIKE '%エラー%'
    LOOP
        RAISE NOTICE '';
        RAISE NOTICE '処理中の事業所ID: %', target_office_id;
        RAISE NOTICE '  名前: %', office_name_display;
        
        -- ----------------------------------------
        -- 1. 孤立する welfare_recipients を記録
        -- ----------------------------------------
        SELECT ARRAY_AGG(wr.id) INTO orphaned_recipients
        FROM welfare_recipients wr
        WHERE wr.id IN (
            SELECT welfare_recipient_id 
            FROM office_welfare_recipients 
            WHERE office_id = target_office_id
        )
        AND NOT EXISTS (
            SELECT 1 
            FROM office_welfare_recipients owr2 
            WHERE owr2.welfare_recipient_id = wr.id 
            AND owr2.office_id != target_office_id
        );
        
        IF orphaned_recipients IS NOT NULL THEN
            RAISE NOTICE '  → 孤立する利用者: % 人', array_length(orphaned_recipients, 1);
        ELSE
            RAISE NOTICE '  → 孤立する利用者: なし';
        END IF;
        
        -- ----------------------------------------
        -- 2. plan_deliverables を削除
        -- （support_plan_cycles経由）
        -- ----------------------------------------
        DELETE FROM plan_deliverables
        WHERE plan_cycle_id IN (
            SELECT id FROM support_plan_cycles 
            WHERE office_id = target_office_id
        );
        GET DIAGNOSTICS v_count = ROW_COUNT;
        IF v_count > 0 THEN
            RAISE NOTICE '  ✓ plan_deliverables を削除: % 件', v_count;
        END IF;
        
        -- ----------------------------------------
        -- 3. support_plan_statuses を削除
        -- ----------------------------------------
        DELETE FROM support_plan_statuses
        WHERE office_id = target_office_id;
        GET DIAGNOSTICS v_count = ROW_COUNT;
        IF v_count > 0 THEN
            RAISE NOTICE '  ✓ support_plan_statuses を削除: % 件', v_count;
        END IF;
        
        -- ----------------------------------------
        -- 4. calendar_events を削除
        -- ----------------------------------------
        DELETE FROM calendar_events
        WHERE office_id = target_office_id;
        GET DIAGNOSTICS v_count = ROW_COUNT;
        IF v_count > 0 THEN
            RAISE NOTICE '  ✓ calendar_events を削除: % 件', v_count;
        END IF;
        
        -- ----------------------------------------
        -- 5. support_plan_cycles を削除
        -- ----------------------------------------
        DELETE FROM support_plan_cycles
        WHERE office_id = target_office_id;
        GET DIAGNOSTICS v_count = ROW_COUNT;
        IF v_count > 0 THEN
            RAISE NOTICE '  ✓ support_plan_cycles を削除: % 件', v_count;
        END IF;
        
        -- ----------------------------------------
        -- 6. office_staffs を削除
        -- ----------------------------------------
        DELETE FROM office_staffs
        WHERE office_id = target_office_id;
        GET DIAGNOSTICS v_count = ROW_COUNT;
        IF v_count > 0 THEN
            RAISE NOTICE '  ✓ office_staffs を削除: % 件', v_count;
        END IF;
        
        -- ----------------------------------------
        -- 7. office_welfare_recipients を削除
        -- ----------------------------------------
        DELETE FROM office_welfare_recipients
        WHERE office_id = target_office_id;
        GET DIAGNOSTICS v_count = ROW_COUNT;
        IF v_count > 0 THEN
            RAISE NOTICE '  ✓ office_welfare_recipients を削除: % 件', v_count;
        END IF;
        
        -- ----------------------------------------
        -- 8. office_calendar_accounts を削除
        -- ----------------------------------------
        DELETE FROM office_calendar_accounts
        WHERE office_id = target_office_id;
        GET DIAGNOSTICS v_count = ROW_COUNT;
        IF v_count > 0 THEN
            RAISE NOTICE '  ✓ office_calendar_accounts を削除: % 件', v_count;
        END IF;
        
        -- ----------------------------------------
        -- 9. notices を削除
        -- ----------------------------------------
        DELETE FROM notices
        WHERE office_id = target_office_id;
        GET DIAGNOSTICS v_count = ROW_COUNT;
        IF v_count > 0 THEN
            RAISE NOTICE '  ✓ notices を削除: % 件', v_count;
        END IF;
        
        -- ----------------------------------------
        -- 10. 孤立した welfare_recipients を削除
        -- （ON DELETE CASCADE により関連データも自動削除）
        -- ----------------------------------------
        IF orphaned_recipients IS NOT NULL THEN
            DELETE FROM welfare_recipients
            WHERE id = ANY(orphaned_recipients);
            GET DIAGNOSTICS v_count = ROW_COUNT;
            RAISE NOTICE '  ✓ 孤立利用者を削除 (CASCADE): % 件', v_count;
        END IF;
        
        -- ----------------------------------------
        -- 11. office を削除
        -- （ON DELETE CASCADE により残りが自動削除）
        -- ----------------------------------------
        DELETE FROM offices
        WHERE id = target_office_id;
        RAISE NOTICE '  ✓ 事業所を削除 (CASCADE)';
        
        total_processed := total_processed + 1;
    END LOOP;
    
    
EXCEPTION
    WHEN OTHERS THEN
        RAISE EXCEPTION '❌ 事業所削除中にエラー: % (SQLSTATE: %)', SQLERRM, SQLSTATE;
END $$;

COMMIT;


-- ========================================
-- 最終確認クエリ
-- ========================================
-- 削除後、残っているテスト関連データを確認
SELECT 
    'staffs' as table_name, 
    COUNT(*) as remaining_count 
FROM staffs
WHERE first_name LIKE '%テスト%' 
   OR first_name LIKE '%修復%' 
   OR first_name LIKE '%エラー%'
   OR last_name LIKE '%テスト%' 
   OR last_name LIKE '%修復%' 
   OR last_name LIKE '%エラー%'
   OR full_name LIKE '%テスト%' 
   OR full_name LIKE '%修復%' 
   OR full_name LIKE '%エラー%'
UNION ALL
SELECT 
    'offices', 
    COUNT(*) 
FROM offices
WHERE name LIKE '%テスト%' 
   OR name LIKE '%修復%' 
   OR name LIKE '%エラー%';