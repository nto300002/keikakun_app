-- ╔══════════════════════════════════════════════════════════════╗
-- ║  テストデータ完全削除スクリプト（型エラー修正版）            ║
-- ║  対象: staffs.full_name = 'テスト 管理者'                    ║
-- ║        offices.name = 'テスト事業所'                         ║
-- ╚══════════════════════════════════════════════════════════════╝

BEGIN;

DO $$
DECLARE
    -- スタッフ関連
    target_staff_ids UUID[];
    replacement_staff_id UUID;
    staff_id_loop UUID;
    staff_name_display VARCHAR;  -- ⭐ 追加
    
    -- 事業所関連
    target_office_ids UUID[];
    office_id_loop UUID;
    office_name_display VARCHAR;  -- ⭐ 追加
    
    -- 利用者関連
    orphaned_recipient_ids UUID[];
    
    -- カウンター
    v_count INT;
    total_staff INT := 0;
    total_office INT := 0;
BEGIN
    
    RAISE NOTICE '';
    RAISE NOTICE '╔══════════════════════════════════════════════════════════════╗';
    RAISE NOTICE '║              テストデータ削除プロセス開始                    ║';
    RAISE NOTICE '╚══════════════════════════════════════════════════════════════╝';
    RAISE NOTICE '';
    
    -- ========================================
    -- Phase 1: 削除対象の特定
    -- ========================================
    
    RAISE NOTICE '[Phase 1] 削除対象の特定...';
    RAISE NOTICE '';
    
    -- 1-1. 削除対象スタッフの特定
    SELECT ARRAY_AGG(id) INTO target_staff_ids
    FROM staffs
    WHERE last_name = 'テスト';
    
    IF target_staff_ids IS NULL THEN
        RAISE NOTICE '  削除対象スタッフ: なし';
    ELSE
        RAISE NOTICE '  削除対象スタッフ: % 人', array_length(target_staff_ids, 1);
    END IF;
    
    -- 1-2. 削除対象事業所の特定
    SELECT ARRAY_AGG(id) INTO target_office_ids
    FROM offices
    WHERE name = 'テスト事業所';
    
    IF target_office_ids IS NULL THEN
        RAISE NOTICE '  削除対象事業所: なし';
    ELSE
        RAISE NOTICE '  削除対象事業所: % 件', array_length(target_office_ids, 1);
    END IF;
    
    RAISE NOTICE '';
    
    -- ========================================
    -- Phase 2: 事業所データの削除
    -- ========================================
    
    IF target_office_ids IS NOT NULL THEN
        RAISE NOTICE '[Phase 2] 事業所データの削除...';
        RAISE NOTICE '';
        
        FOREACH office_id_loop IN ARRAY target_office_ids
        LOOP
            -- ⭐ 修正: VARCHAR型の変数に代入
            SELECT name INTO office_name_display FROM offices WHERE id = office_id_loop;
            RAISE NOTICE '  事業所: %', office_name_display;
            
            -- 2-1. 孤立する利用者を特定
            SELECT ARRAY_AGG(wr.id) INTO orphaned_recipient_ids
            FROM welfare_recipients wr
            WHERE wr.id IN (
                SELECT welfare_recipient_id 
                FROM office_welfare_recipients 
                WHERE office_id = office_id_loop
            )
            AND NOT EXISTS (
                SELECT 1 
                FROM office_welfare_recipients owr2 
                WHERE owr2.welfare_recipient_id = wr.id 
                AND owr2.office_id != office_id_loop
            );
            
            IF orphaned_recipient_ids IS NOT NULL THEN
                RAISE NOTICE '    孤立利用者: % 人', array_length(orphaned_recipient_ids, 1);
            ELSE
                RAISE NOTICE '    孤立利用者: なし';
            END IF;
            
            -- 2-2. plan_deliverables を削除
            DELETE FROM plan_deliverables
            WHERE plan_cycle_id IN (
                SELECT id FROM support_plan_cycles 
                WHERE office_id = office_id_loop
            );
            GET DIAGNOSTICS v_count = ROW_COUNT;
            IF v_count > 0 THEN
                RAISE NOTICE '    ✓ plan_deliverables: %', v_count;
            END IF;
            
            -- 2-3. support_plan_statuses を削除
            DELETE FROM support_plan_statuses
            WHERE office_id = office_id_loop;
            GET DIAGNOSTICS v_count = ROW_COUNT;
            IF v_count > 0 THEN
                RAISE NOTICE '    ✓ support_plan_statuses: %', v_count;
            END IF;
            
            -- 2-4. calendar_events を削除
            DELETE FROM calendar_events
            WHERE office_id = office_id_loop;
            GET DIAGNOSTICS v_count = ROW_COUNT;
            IF v_count > 0 THEN
                RAISE NOTICE '    ✓ calendar_events: %', v_count;
            END IF;
            
            -- 2-5. support_plan_cycles を削除 ⭐ 重要
            DELETE FROM support_plan_cycles
            WHERE office_id = office_id_loop;
            GET DIAGNOSTICS v_count = ROW_COUNT;
            IF v_count > 0 THEN
                RAISE NOTICE '    ✓ support_plan_cycles: %', v_count;
            END IF;
            
            -- 2-6. office_welfare_recipients を削除
            DELETE FROM office_welfare_recipients
            WHERE office_id = office_id_loop;
            GET DIAGNOSTICS v_count = ROW_COUNT;
            IF v_count > 0 THEN
                RAISE NOTICE '    ✓ office_welfare_recipients: %', v_count;
            END IF;
            
            -- 2-7. office_calendar_accounts を削除
            DELETE FROM office_calendar_accounts
            WHERE office_id = office_id_loop;
            GET DIAGNOSTICS v_count = ROW_COUNT;
            IF v_count > 0 THEN
                RAISE NOTICE '    ✓ office_calendar_accounts: %', v_count;
            END IF;
            
            -- 2-8. notices を削除
            DELETE FROM notices
            WHERE office_id = office_id_loop;
            GET DIAGNOSTICS v_count = ROW_COUNT;
            IF v_count > 0 THEN
                RAISE NOTICE '    ✓ notices: %', v_count;
            END IF;
            
            -- 2-9. office_staffs を削除
            DELETE FROM office_staffs
            WHERE office_id = office_id_loop;
            GET DIAGNOSTICS v_count = ROW_COUNT;
            IF v_count > 0 THEN
                RAISE NOTICE '    ✓ office_staffs: %', v_count;
            END IF;
            
            -- 2-10. 孤立利用者を削除 ⭐ support_plan_cycles削除後
            IF orphaned_recipient_ids IS NOT NULL THEN
                -- 確認: まだ参照されているsupport_plan_cyclesがないか
                SELECT COUNT(*) INTO v_count
                FROM support_plan_cycles
                WHERE welfare_recipient_id = ANY(orphaned_recipient_ids);
                
                IF v_count > 0 THEN
                    RAISE NOTICE '    ⚠ 警告: % 件のsupport_plan_cyclesが残っています', v_count;
                    RAISE NOTICE '       (他の事業所に属している可能性)';
                    -- 削除をスキップ
                    orphaned_recipient_ids := NULL;
                ELSE
                    DELETE FROM welfare_recipients
                    WHERE id = ANY(orphaned_recipient_ids);
                    GET DIAGNOSTICS v_count = ROW_COUNT;
                    RAISE NOTICE '    ✓ 孤立利用者 (CASCADE): %', v_count;
                END IF;
            END IF;
            
            -- 2-11. office を削除
            DELETE FROM offices
            WHERE id = office_id_loop;
            RAISE NOTICE '    ✓ 事業所を削除 (CASCADE)';
            RAISE NOTICE '';
            
            total_office := total_office + 1;
        END LOOP;
        
        RAISE NOTICE '✅ Phase 2 完了: % 件の事業所を削除', total_office;
        RAISE NOTICE '';
    ELSE
        RAISE NOTICE '[Phase 2] スキップ（削除対象なし）';
        RAISE NOTICE '';
    END IF;
    
    -- ========================================
    -- Phase 3: スタッフデータの削除
    -- ========================================
    
    IF target_staff_ids IS NOT NULL THEN
        RAISE NOTICE '[Phase 3] スタッフデータの削除...';
        RAISE NOTICE '';
        
        -- 3-1. 再割当先のスタッフを選択
        RAISE NOTICE '  🔍 再割当先のスタッフを検索中...';
        
        SELECT s.id INTO replacement_staff_id
        FROM staffs s
        INNER JOIN office_staffs os ON s.id = os.staff_id
        WHERE s.role = 'owner'
          AND s.id != ALL(target_staff_ids)
          AND (s.full_name IS NULL OR s.full_name NOT LIKE '%テスト%')
        LIMIT 1;
        
        IF replacement_staff_id IS NULL THEN
            RAISE EXCEPTION '❌ 再割当先のownerが見つかりません';
        END IF;
        
        -- ⭐ 修正: VARCHAR型の変数に代入
        SELECT COALESCE(full_name, email) INTO staff_name_display 
        FROM staffs 
        WHERE id = replacement_staff_id;
        RAISE NOTICE '  ✓ 再割当先: %', staff_name_display;
        RAISE NOTICE '';
        
        -- 3-2. 各スタッフを処理
        FOREACH staff_id_loop IN ARRAY target_staff_ids
        LOOP
            -- ⭐ 修正: VARCHAR型の変数に代入
            SELECT COALESCE(full_name, email) INTO staff_name_display 
            FROM staffs 
            WHERE id = staff_id_loop;
            RAISE NOTICE '  スタッフ: %', staff_name_display;
            
            -- offices の created_by を再割当て
            UPDATE offices
            SET created_by = replacement_staff_id,
                updated_at = CURRENT_TIMESTAMP
            WHERE created_by = staff_id_loop;
            GET DIAGNOSTICS v_count = ROW_COUNT;
            IF v_count > 0 THEN
                RAISE NOTICE '    ✓ offices.created_by: %', v_count;
            END IF;
            
            -- offices の last_modified_by を再割当て
            UPDATE offices
            SET last_modified_by = replacement_staff_id,
                updated_at = CURRENT_TIMESTAMP
            WHERE last_modified_by = staff_id_loop;
            GET DIAGNOSTICS v_count = ROW_COUNT;
            IF v_count > 0 THEN
                RAISE NOTICE '    ✓ offices.last_modified_by: %', v_count;
            END IF;
            
            -- support_plan_statuses の completed_by を NULL に
            UPDATE support_plan_statuses
            SET completed_by = NULL
            WHERE completed_by = staff_id_loop;
            GET DIAGNOSTICS v_count = ROW_COUNT;
            IF v_count > 0 THEN
                RAISE NOTICE '    ✓ support_plan_statuses.completed_by: %', v_count;
            END IF;
            
            -- plan_deliverables を削除
            DELETE FROM plan_deliverables
            WHERE uploaded_by = staff_id_loop;
            GET DIAGNOSTICS v_count = ROW_COUNT;
            IF v_count > 0 THEN
                RAISE NOTICE '    ✓ plan_deliverables: %', v_count;
            END IF;
            
            -- office_staffs を削除
            DELETE FROM office_staffs
            WHERE staff_id = staff_id_loop;
            GET DIAGNOSTICS v_count = ROW_COUNT;
            IF v_count > 0 THEN
                RAISE NOTICE '    ✓ office_staffs: %', v_count;
            END IF;
            
            -- staff を削除 (CASCADE)
            DELETE FROM staffs
            WHERE id = staff_id_loop;
            RAISE NOTICE '    ✓ スタッフを削除 (CASCADE)';
            RAISE NOTICE '';
            
            total_staff := total_staff + 1;
        END LOOP;
        
        RAISE NOTICE '✅ Phase 3 完了: % 人のスタッフを削除', total_staff;
        RAISE NOTICE '';
    ELSE
        RAISE NOTICE '[Phase 3] スキップ（削除対象なし）';
        RAISE NOTICE '';
    END IF;
    
    -- ========================================
    -- 完了
    -- ========================================
    
    RAISE NOTICE '╔══════════════════════════════════════════════════════════════╗';
    RAISE NOTICE '║                    ✅ 全ての削除完了                         ║';
    RAISE NOTICE '╚══════════════════════════════════════════════════════════════╝';
    RAISE NOTICE '';
    RAISE NOTICE '削除サマリー:';
    RAISE NOTICE '  事業所: % 件', total_office;
    RAISE NOTICE '  スタッフ: % 人', total_staff;
    RAISE NOTICE '';
    
EXCEPTION
    WHEN OTHERS THEN
        RAISE NOTICE '';
        RAISE NOTICE '╔══════════════════════════════════════════════════════════════╗';
        RAISE NOTICE '║                    ❌ エラー発生                             ║';
        RAISE NOTICE '╚══════════════════════════════════════════════════════════════╝';
        RAISE NOTICE '';
        RAISE NOTICE 'エラー: %', SQLERRM;
        RAISE NOTICE 'SQLSTATE: %', SQLSTATE;
        RAISE NOTICE '';
        RAISE EXCEPTION 'ロールバックします';
END $$;

COMMIT;

-- 削除確認クエリ
SELECT 
    'staffs' as table_name,
    COUNT(*) as remaining
FROM staffs
WHERE full_name = 'テスト 管理者'
UNION ALL
SELECT 
    'offices',
    COUNT(*)
FROM offices
WHERE name = 'テスト事業所';