--
-- PostgreSQL database dump
--

\restrict GmDt5F7ECiyOLwIZ1eFkvIvdgQWmxsaTrJWc1kyhkrMeDs4w87XNW41t7iIz0RU

-- Dumped from database version 17.10 (9f6157c)
-- Dumped by pg_dump version 17.10

SET statement_timeout = 0;
SET lock_timeout = 0;
SET idle_in_transaction_session_timeout = 0;
SET transaction_timeout = 0;
SET client_encoding = 'UTF8';
SET standard_conforming_strings = on;
SELECT pg_catalog.set_config('search_path', '', false);
SET check_function_bodies = false;
SET xmloption = content;
SET client_min_messages = warning;
SET row_security = off;

--
-- Name: neon_auth; Type: SCHEMA; Schema: -; Owner: -
--

CREATE SCHEMA neon_auth;


--
-- Name: pg_trgm; Type: EXTENSION; Schema: -; Owner: -
--

CREATE EXTENSION IF NOT EXISTS pg_trgm WITH SCHEMA public;


--
-- Name: EXTENSION pg_trgm; Type: COMMENT; Schema: -; Owner: -
--

COMMENT ON EXTENSION pg_trgm IS 'text similarity measurement and index searching based on trigrams';


--
-- Name: pgcrypto; Type: EXTENSION; Schema: -; Owner: -
--

CREATE EXTENSION IF NOT EXISTS pgcrypto WITH SCHEMA public;


--
-- Name: EXTENSION pgcrypto; Type: COMMENT; Schema: -; Owner: -
--

COMMENT ON EXTENSION pgcrypto IS 'cryptographic functions';


--
-- Name: actiontype; Type: TYPE; Schema: public; Owner: -
--

CREATE TYPE public.actiontype AS ENUM (
    'create',
    'update',
    'delete'
);


--
-- Name: aiding_type; Type: TYPE; Schema: public; Owner: -
--

CREATE TYPE public.aiding_type AS ENUM (
    'none',
    'subsidized',
    'full_exemption'
);


--
-- Name: application_status; Type: TYPE; Schema: public; Owner: -
--

CREATE TYPE public.application_status AS ENUM (
    'acquired',
    'applying',
    'planning',
    'not_applicable'
);


--
-- Name: approvalresourcetype; Type: TYPE; Schema: public; Owner: -
--

CREATE TYPE public.approvalresourcetype AS ENUM (
    'role_change',
    'employee_action',
    'withdrawal'
);


--
-- Name: billingstatus; Type: TYPE; Schema: public; Owner: -
--

CREATE TYPE public.billingstatus AS ENUM (
    'free',
    'early_payment',
    'active',
    'past_due',
    'trial_expired',
    'payment_failed',
    'canceling',
    'canceled'
);


--
-- Name: calendar_connection_status; Type: TYPE; Schema: public; Owner: -
--

CREATE TYPE public.calendar_connection_status AS ENUM (
    'not_connected',
    'connected',
    'error',
    'suspended'
);


--
-- Name: calendar_event_type; Type: TYPE; Schema: public; Owner: -
--

CREATE TYPE public.calendar_event_type AS ENUM (
    'renewal_deadline',
    'monitoring_deadline',
    'custom',
    'next_plan_start_date'
);


--
-- Name: calendar_sync_status; Type: TYPE; Schema: public; Owner: -
--

CREATE TYPE public.calendar_sync_status AS ENUM (
    'pending',
    'synced',
    'failed',
    'cancelled'
);


--
-- Name: deliverabletype; Type: TYPE; Schema: public; Owner: -
--

CREATE TYPE public.deliverabletype AS ENUM (
    'assessment_sheet',
    'draft_plan_pdf',
    'staff_meeting_minutes',
    'final_plan_signed_pdf',
    'monitoring_report_pdf'
);


--
-- Name: disability_category; Type: TYPE; Schema: public; Owner: -
--

CREATE TYPE public.disability_category AS ENUM (
    'physical_handbook',
    'intellectual_handbook',
    'mental_health_handbook',
    'disability_basic_pension',
    'other_disability_pension',
    'public_assistance'
);


--
-- Name: event_instance_status; Type: TYPE; Schema: public; Owner: -
--

CREATE TYPE public.event_instance_status AS ENUM (
    'pending',
    'created',
    'modified',
    'cancelled',
    'completed'
);


--
-- Name: form_of_residence; Type: TYPE; Schema: public; Owner: -
--

CREATE TYPE public.form_of_residence AS ENUM (
    'home_with_family',
    'home_alone',
    'group_home',
    'institution',
    'hospital',
    'other'
);


--
-- Name: gendertype; Type: TYPE; Schema: public; Owner: -
--

CREATE TYPE public.gendertype AS ENUM (
    'male',
    'female',
    'other'
);


--
-- Name: household; Type: TYPE; Schema: public; Owner: -
--

CREATE TYPE public.household AS ENUM (
    'same',
    'separate'
);


--
-- Name: inquiry_priority; Type: TYPE; Schema: public; Owner: -
--

CREATE TYPE public.inquiry_priority AS ENUM (
    'low',
    'normal',
    'high'
);


--
-- Name: TYPE inquiry_priority; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON TYPE public.inquiry_priority IS '問い合わせ優先度';


--
-- Name: inquiry_status; Type: TYPE; Schema: public; Owner: -
--

CREATE TYPE public.inquiry_status AS ENUM (
    'new',
    'open',
    'in_progress',
    'answered',
    'closed',
    'spam'
);


--
-- Name: TYPE inquiry_status; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON TYPE public.inquiry_status IS '問い合わせステータス';


--
-- Name: livelihood_protection; Type: TYPE; Schema: public; Owner: -
--

CREATE TYPE public.livelihood_protection AS ENUM (
    'not_receiving',
    'receiving_with_allowance',
    'receiving_without_allowance',
    'applying',
    'planning'
);


--
-- Name: means_of_transportation; Type: TYPE; Schema: public; Owner: -
--

CREATE TYPE public.means_of_transportation AS ENUM (
    'walk',
    'bicycle',
    'motorbike',
    'car_self',
    'car_transport',
    'public_transport',
    'welfare_transport',
    'other'
);


--
-- Name: medical_care_insurance; Type: TYPE; Schema: public; Owner: -
--

CREATE TYPE public.medical_care_insurance AS ENUM (
    'national_health_insurance',
    'mutual_aid',
    'social_insurance',
    'livelihood_protection',
    'other'
);


--
-- Name: notification_timing; Type: TYPE; Schema: public; Owner: -
--

CREATE TYPE public.notification_timing AS ENUM (
    'early',
    'standard',
    'minimal',
    'custom'
);


--
-- Name: officetype; Type: TYPE; Schema: public; Owner: -
--

CREATE TYPE public.officetype AS ENUM (
    'transition_to_employment',
    'type_B_office',
    'type_A_office'
);


--
-- Name: physical_disability_type; Type: TYPE; Schema: public; Owner: -
--

CREATE TYPE public.physical_disability_type AS ENUM (
    'visual',
    'hearing',
    'limb',
    'internal',
    'other'
);


--
-- Name: reminder_pattern_type; Type: TYPE; Schema: public; Owner: -
--

CREATE TYPE public.reminder_pattern_type AS ENUM (
    'single',
    'multiple_fixed',
    'recurring_rule'
);


--
-- Name: requeststatus; Type: TYPE; Schema: public; Owner: -
--

CREATE TYPE public.requeststatus AS ENUM (
    'pending',
    'approved',
    'rejected'
);


--
-- Name: resourcetype; Type: TYPE; Schema: public; Owner: -
--

CREATE TYPE public.resourcetype AS ENUM (
    'welfare_recipient',
    'support_plan_cycle',
    'support_plan_status'
);


--
-- Name: staffrole; Type: TYPE; Schema: public; Owner: -
--

CREATE TYPE public.staffrole AS ENUM (
    'employee',
    'manager',
    'owner',
    'app_admin'
);


--
-- Name: supportplanstep; Type: TYPE; Schema: public; Owner: -
--

CREATE TYPE public.supportplanstep AS ENUM (
    'assessment',
    'draft_plan',
    'staff_meeting',
    'final_plan_signed',
    'monitoring'
);


--
-- Name: work_conditions; Type: TYPE; Schema: public; Owner: -
--

CREATE TYPE public.work_conditions AS ENUM (
    'general_employment',
    'part_time',
    'transition_support',
    'continuous_support_a',
    'continuous_support_b',
    'main_employment',
    'other'
);


--
-- Name: work_outside_facility; Type: TYPE; Schema: public; Owner: -
--

CREATE TYPE public.work_outside_facility AS ENUM (
    'hope',
    'not_hope',
    'undecided'
);


--
-- Name: create_calendar_event(uuid, uuid, public.calendar_event_type, date, uuid, uuid); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.create_calendar_event(p_office_id uuid, p_welfare_recipient_id uuid, p_event_type public.calendar_event_type, p_event_date date, p_cycle_id uuid DEFAULT NULL::uuid, p_status_id uuid DEFAULT NULL::uuid) RETURNS uuid
    LANGUAGE plpgsql
    AS $$
DECLARE
    v_event_id UUID;
    v_recipient_name TEXT;
    v_event_title TEXT;
    v_event_description TEXT;
    v_calendar_id TEXT;
    v_event_start TIMESTAMP WITH TIME ZONE;
    v_event_end TIMESTAMP WITH TIME ZONE;
BEGIN
    -- 利用者名取得
    SELECT first_name || ' ' || last_name INTO v_recipient_name
    FROM welfare_recipients
    WHERE id = p_welfare_recipient_id;

    IF v_recipient_name IS NULL THEN
        RAISE EXCEPTION 'Welfare recipient not found: %', p_welfare_recipient_id;
    END IF;

    -- カレンダーID取得
    SELECT google_calendar_id INTO v_calendar_id
    FROM office_calendar_accounts
    WHERE office_id = p_office_id
      AND connection_status = 'connected'
      AND google_calendar_id IS NOT NULL;

    IF v_calendar_id IS NULL THEN
        RAISE EXCEPTION 'Office calendar not connected for office_id: %', p_office_id;
    END IF;

    -- イベントタイトル・説明生成
    CASE p_event_type
        WHEN 'renewal_deadline' THEN
            v_event_title := v_recipient_name || ' 更新期限';
            v_event_description := v_recipient_name || 'さんの個別支援計画の更新期限です。';
        WHEN 'monitoring_deadline' THEN
            v_event_title := v_recipient_name || ' モニタリング期限';
            v_event_description := v_recipient_name || 'さんのモニタリング期限です。';
        ELSE
            v_event_title := v_recipient_name || ' カレンダーイベント';
            v_event_description := v_recipient_name || 'さんに関するイベントです。';
    END CASE;

    -- イベント時刻設定（9:00-10:00）
    v_event_start := p_event_date::TIMESTAMP WITH TIME ZONE + INTERVAL '9 hours';
    v_event_end := p_event_date::TIMESTAMP WITH TIME ZONE + INTERVAL '10 hours';

    -- カレンダーイベントレコード作成
    INSERT INTO calendar_events (
        office_id,
        welfare_recipient_id,
        support_plan_cycle_id,
        support_plan_status_id,
        event_type,
        google_calendar_id,
        event_title,
        event_description,
        event_start_datetime,
        event_end_datetime,
        sync_status
    ) VALUES (
        p_office_id,
        p_welfare_recipient_id,
        p_cycle_id,
        p_status_id,
        p_event_type,
        v_calendar_id,
        v_event_title,
        v_event_description,
        v_event_start,
        v_event_end,
        'pending'
    ) RETURNING id INTO v_event_id;

    RETURN v_event_id;
END;
$$;


--
-- Name: create_calendar_events_batch(); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.create_calendar_events_batch() RETURNS TABLE(created_event_id uuid, office_id uuid, recipient_name text, event_type public.calendar_event_type, deadline_date date, success boolean, error_message text)
    LANGUAGE plpgsql
    AS $$
DECLARE
    deadline_record RECORD;
    v_event_id UUID;
    v_error_msg TEXT;
BEGIN
    -- 期限が近いものを検出してイベント作成
    FOR deadline_record IN
        SELECT * FROM detect_upcoming_deadlines()
    LOOP
        BEGIN
            -- イベント作成
            SELECT create_calendar_event(
                deadline_record.office_id,
                deadline_record.welfare_recipient_id,
                deadline_record.event_type,
                deadline_record.deadline_date,
                deadline_record.cycle_id,
                deadline_record.status_id
            ) INTO v_event_id;

            -- 成功レコード返却
            RETURN QUERY SELECT
                v_event_id,
                deadline_record.office_id,
                deadline_record.recipient_name,
                deadline_record.event_type,
                deadline_record.deadline_date,
                TRUE,
                NULL::TEXT;

        EXCEPTION WHEN OTHERS THEN
            v_error_msg := SQLERRM;

            -- エラーレコード返却
            RETURN QUERY SELECT
                NULL::UUID,
                deadline_record.office_id,
                deadline_record.recipient_name,
                deadline_record.event_type,
                deadline_record.deadline_date,
                FALSE,
                v_error_msg;
        END;
    END LOOP;
END;
$$;


--
-- Name: detect_series_candidates(); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.detect_series_candidates() RETURNS TABLE(office_id uuid, welfare_recipient_id uuid, recipient_name text, event_type public.calendar_event_type, deadline_date date, cycle_id uuid, status_id uuid, suggested_pattern_id uuid)
    LANGUAGE plpgsql
    AS $$
BEGIN
    RETURN QUERY

    -- 更新期限の候補
    SELECT
        owr.office_id,
        spc.welfare_recipient_id,
        wr.first_name || ' ' || wr.last_name as recipient_name,
        'renewal_deadline'::calendar_event_type,
        spc.next_renewal_deadline,
        spc.id as cycle_id,
        NULL::UUID as status_id,
        np.id as suggested_pattern_id
    FROM support_plan_cycles spc
    JOIN welfare_recipients wr ON spc.welfare_recipient_id = wr.id
    JOIN office_welfare_recipients owr ON wr.id = owr.welfare_recipient_id
    CROSS JOIN notification_patterns np
    WHERE spc.next_renewal_deadline IS NOT NULL
      AND spc.next_renewal_deadline > CURRENT_DATE
      AND np.event_type = 'renewal_deadline'
      AND np.is_system_default = TRUE
      AND NOT EXISTS (
          SELECT 1 FROM calendar_event_series ces
          WHERE ces.support_plan_cycle_id = spc.id
            AND ces.event_type = 'renewal_deadline'
      )

    UNION ALL

    -- モニタリング期限の候補
    SELECT
        owr.office_id,
        spc.welfare_recipient_id,
        wr.first_name || ' ' || wr.last_name as recipient_name,
        'monitoring_deadline'::calendar_event_type,
        sps.due_date,
        NULL::UUID as cycle_id,
        sps.id as status_id,
        np.id as suggested_pattern_id
    FROM support_plan_statuses sps
    JOIN support_plan_cycles spc ON sps.plan_cycle_id = spc.id
    JOIN welfare_recipients wr ON spc.welfare_recipient_id = wr.id
    JOIN office_welfare_recipients owr ON wr.id = owr.welfare_recipient_id
    CROSS JOIN notification_patterns np
    WHERE sps.due_date IS NOT NULL
      AND sps.due_date > CURRENT_DATE
      AND np.event_type = 'monitoring_deadline'
      AND np.is_system_default = TRUE
      AND NOT EXISTS (
          SELECT 1 FROM calendar_event_series ces
          WHERE ces.support_plan_status_id = sps.id
            AND ces.event_type = 'monitoring_deadline'
      );
END;
$$;


--
-- Name: detect_upcoming_deadlines(); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.detect_upcoming_deadlines() RETURNS TABLE(office_id uuid, welfare_recipient_id uuid, recipient_name text, event_type public.calendar_event_type, deadline_date date, cycle_id uuid, status_id uuid, days_until_deadline integer)
    LANGUAGE plpgsql
    AS $$
BEGIN
    RETURN QUERY

    -- 更新期限（30日以内）
    SELECT
        owr.office_id,
        spc.welfare_recipient_id,
        wr.first_name || ' ' || wr.last_name as recipient_name,
        'renewal_deadline'::calendar_event_type as event_type,
        spc.next_renewal_deadline as deadline_date,
        spc.id as cycle_id,
        NULL::UUID as status_id,
        (spc.next_renewal_deadline - CURRENT_DATE)::INTEGER as days_until_deadline
    FROM support_plan_cycles spc
    JOIN welfare_recipients wr ON spc.welfare_recipient_id = wr.id
    JOIN office_welfare_recipients owr ON wr.id = owr.welfare_recipient_id
    WHERE spc.next_renewal_deadline IS NOT NULL
      AND spc.next_renewal_deadline BETWEEN CURRENT_DATE AND CURRENT_DATE + INTERVAL '30 days'
      AND NOT EXISTS (
          SELECT 1 FROM calendar_events ce
          WHERE ce.support_plan_cycle_id = spc.id
            AND ce.event_type = 'renewal_deadline'
            AND ce.sync_status IN ('pending', 'synced')
      )

    UNION ALL

    -- モニタリング期限（7日以内）
    SELECT
        owr.office_id,
        spc.welfare_recipient_id,
        wr.first_name || ' ' || wr.last_name as recipient_name,
        'monitoring_deadline'::calendar_event_type as event_type,
        sps.due_date as deadline_date,
        NULL::UUID as cycle_id,
        sps.id as status_id,
        (sps.due_date - CURRENT_DATE)::INTEGER as days_until_deadline
    FROM support_plan_statuses sps
    JOIN support_plan_cycles spc ON sps.plan_cycle_id = spc.id
    JOIN welfare_recipients wr ON spc.welfare_recipient_id = wr.id
    JOIN office_welfare_recipients owr ON wr.id = owr.welfare_recipient_id
    WHERE sps.due_date IS NOT NULL
      AND sps.due_date BETWEEN CURRENT_DATE AND CURRENT_DATE + INTERVAL '7 days'
      AND NOT EXISTS (
          SELECT 1 FROM calendar_events ce
          WHERE ce.support_plan_status_id = sps.id
            AND ce.event_type = 'monitoring_deadline'
            AND ce.sync_status IN ('pending', 'synced')
      );
END;
$$;


--
-- Name: search_objects_by_name(text, boolean); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.search_objects_by_name(search_name text, exact_match boolean DEFAULT false) RETURNS TABLE(object_type text, schema_name text, object_name text, parent_object text, definition text)
    LANGUAGE plpgsql
    AS $$
BEGIN
    RETURN QUERY

    -- TYPE検索
    SELECT
        'TYPE'::TEXT,
        n.nspname::TEXT,
        t.typname::TEXT,
        NULL::TEXT,
        CASE
            WHEN t.typtype = 'e' THEN
                'ENUM: ' || COALESCE((
                    SELECT string_agg(e.enumlabel, ', ' ORDER BY e.enumsortorder)
                    FROM pg_enum e WHERE e.enumtypid = t.oid
                ), '')
            ELSE 'TYPE: ' || format_type(t.oid, NULL)
        END::TEXT
    FROM pg_type t
    JOIN pg_namespace n ON t.typnamespace = n.oid
    WHERE n.nspname = 'public'
        AND (
            CASE
                WHEN exact_match THEN t.typname = search_name
                ELSE t.typname ILIKE '%' || search_name || '%'
            END
        )
        AND t.typtype IN ('e', 'c', 'd')

    UNION ALL

    -- TABLE検索
    SELECT
        'TABLE'::TEXT,
        pt.schemaname::TEXT,
        pt.tablename::TEXT,
        NULL::TEXT,
        'TABLE'::TEXT
    FROM pg_tables pt
    WHERE pt.schemaname = 'public'
        AND (
            CASE
                WHEN exact_match THEN pt.tablename = search_name
                ELSE pt.tablename ILIKE '%' || search_name || '%'
            END
        )

    UNION ALL

    -- INDEX検索
    SELECT
        CASE
            WHEN pi.indexdef LIKE '%UNIQUE%' THEN 'UNIQUE INDEX'
            ELSE 'INDEX'
        END::TEXT,
        pi.schemaname::TEXT,
        pi.indexname::TEXT,
        pi.tablename::TEXT,
        pi.indexdef::TEXT
    FROM pg_indexes pi
    WHERE pi.schemaname = 'public'
        AND (
            CASE
                WHEN exact_match THEN pi.indexname = search_name
                ELSE pi.indexname ILIKE '%' || search_name || '%'
            END
        )

    UNION ALL

    -- TRIGGER検索
    SELECT
        'TRIGGER'::TEXT,
        n.nspname::TEXT,
        t.tgname::TEXT,
        c.relname::TEXT,
        ('TRIGGER ON ' || c.relname)::TEXT
    FROM pg_trigger t
    JOIN pg_class c ON t.tgrelid = c.oid
    JOIN pg_namespace n ON c.relnamespace = n.oid
    WHERE n.nspname = 'public'
        AND NOT t.tgisinternal
        AND (
            CASE
                WHEN exact_match THEN t.tgname = search_name
                ELSE t.tgname ILIKE '%' || search_name || '%'
            END
        )

    UNION ALL

    -- FUNCTION検索
    SELECT
        'FUNCTION'::TEXT,
        n.nspname::TEXT,
        p.proname::TEXT,
        NULL::TEXT,
        ('FUNCTION ' || p.proname)::TEXT
    FROM pg_proc p
    JOIN pg_namespace n ON p.pronamespace = n.oid
    WHERE n.nspname = 'public'
        AND (
            CASE
                WHEN exact_match THEN p.proname = search_name
                ELSE p.proname ILIKE '%' || search_name || '%'
            END
        )

    ORDER BY 1, 2, 3;

END;
$$;


--
-- Name: update_calendar_accounts_updated_at(); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.update_calendar_accounts_updated_at() RETURNS trigger
    LANGUAGE plpgsql
    AS $$
BEGIN
    NEW.updated_at = NOW();
    RETURN NEW;
END;
$$;


--
-- Name: update_calendar_event_instances_updated_at(); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.update_calendar_event_instances_updated_at() RETURNS trigger
    LANGUAGE plpgsql
    AS $$
BEGIN
    NEW.updated_at = NOW();
    RETURN NEW;
END;
$$;


--
-- Name: update_calendar_event_series_updated_at(); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.update_calendar_event_series_updated_at() RETURNS trigger
    LANGUAGE plpgsql
    AS $$
BEGIN
    NEW.updated_at = NOW();
    RETURN NEW;
END;
$$;


--
-- Name: update_calendar_events_updated_at(); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.update_calendar_events_updated_at() RETURNS trigger
    LANGUAGE plpgsql
    AS $$
BEGIN
    NEW.updated_at = NOW();
    RETURN NEW;
END;
$$;


--
-- Name: update_inquiry_details_updated_at(); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.update_inquiry_details_updated_at() RETURNS trigger
    LANGUAGE plpgsql
    AS $$
BEGIN
    NEW.updated_at = NOW();
    RETURN NEW;
END;
$$;


--
-- Name: FUNCTION update_inquiry_details_updated_at(); Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON FUNCTION public.update_inquiry_details_updated_at() IS 'inquiry_detailsのupdated_atを自動更新する関数';


--
-- Name: update_notices_updated_at(); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.update_notices_updated_at() RETURNS trigger
    LANGUAGE plpgsql
    AS $$
BEGIN
    NEW.updated_at = NOW();
    RETURN NEW;
END;
$$;


--
-- Name: update_notification_patterns_updated_at(); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.update_notification_patterns_updated_at() RETURNS trigger
    LANGUAGE plpgsql
    AS $$
BEGIN
    NEW.updated_at = NOW();
    RETURN NEW;
END;
$$;


--
-- Name: update_push_subscriptions_updated_at(); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.update_push_subscriptions_updated_at() RETURNS trigger
    LANGUAGE plpgsql
    AS $$
BEGIN
    NEW.updated_at = NOW();
    RETURN NEW;
END;
$$;


--
-- Name: update_series_progress(uuid); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.update_series_progress(p_series_id uuid) RETURNS void
    LANGUAGE plpgsql
    AS $$
DECLARE
    v_total INTEGER;
    v_completed INTEGER;
BEGIN
    -- インスタンス数をカウント
    SELECT
        COUNT(*),
        COUNT(CASE WHEN instance_status = 'completed' THEN 1 END)
    INTO v_total, v_completed
    FROM calendar_event_instances
    WHERE event_series_id = p_series_id;

    -- シリーズの進捗を更新
    UPDATE calendar_event_series
    SET
        total_instances = v_total,
        completed_instances = v_completed,
        updated_at = NOW()
    WHERE id = p_series_id;
END;
$$;


--
-- Name: update_updated_at_column(); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.update_updated_at_column() RETURNS trigger
    LANGUAGE plpgsql
    AS $$
BEGIN
    NEW.updated_at = now();
    RETURN NEW;
END;
$$;


SET default_tablespace = '';

SET default_table_access_method = heap;

--
-- Name: users_sync; Type: TABLE; Schema: neon_auth; Owner: -
--

CREATE TABLE neon_auth.users_sync (
    raw_json jsonb NOT NULL,
    id text GENERATED ALWAYS AS ((raw_json ->> 'id'::text)) STORED NOT NULL,
    name text GENERATED ALWAYS AS ((raw_json ->> 'display_name'::text)) STORED,
    email text GENERATED ALWAYS AS ((raw_json ->> 'primary_email'::text)) STORED,
    created_at timestamp with time zone GENERATED ALWAYS AS (to_timestamp((trunc((((raw_json ->> 'signed_up_at_millis'::text))::bigint)::double precision) / (1000)::double precision))) STORED,
    updated_at timestamp with time zone,
    deleted_at timestamp with time zone
);


--
-- Name: alembic_version; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.alembic_version (
    version_num character varying(32) NOT NULL
);


--
-- Name: approval_requests; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.approval_requests (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    requester_staff_id uuid NOT NULL,
    office_id uuid NOT NULL,
    resource_type public.approvalresourcetype NOT NULL,
    status public.requeststatus DEFAULT 'pending'::public.requeststatus NOT NULL,
    request_data jsonb,
    reviewed_by_staff_id uuid,
    reviewed_at timestamp with time zone,
    reviewer_notes text,
    execution_result jsonb,
    created_at timestamp with time zone DEFAULT now() NOT NULL,
    updated_at timestamp with time zone DEFAULT now() NOT NULL,
    is_test_data boolean DEFAULT false NOT NULL
);


--
-- Name: COLUMN approval_requests.requester_staff_id; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN public.approval_requests.requester_staff_id IS 'リクエスト作成者のスタッフID';


--
-- Name: COLUMN approval_requests.office_id; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN public.approval_requests.office_id IS '対象事務所ID';


--
-- Name: COLUMN approval_requests.resource_type; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN public.approval_requests.resource_type IS 'リクエスト種別';


--
-- Name: COLUMN approval_requests.status; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN public.approval_requests.status IS 'ステータス';


--
-- Name: COLUMN approval_requests.request_data; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN public.approval_requests.request_data IS 'リクエスト固有のデータ';


--
-- Name: COLUMN approval_requests.reviewed_by_staff_id; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN public.approval_requests.reviewed_by_staff_id IS '承認/却下したスタッフID';


--
-- Name: COLUMN approval_requests.reviewed_at; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN public.approval_requests.reviewed_at IS '承認/却下日時';


--
-- Name: COLUMN approval_requests.reviewer_notes; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN public.approval_requests.reviewer_notes IS '承認者のメモ';


--
-- Name: COLUMN approval_requests.execution_result; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN public.approval_requests.execution_result IS '実行結果';


--
-- Name: COLUMN approval_requests.is_test_data; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN public.approval_requests.is_test_data IS 'テストデータフラグ';


--
-- Name: archived_staffs; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.archived_staffs (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    original_staff_id uuid NOT NULL,
    anonymized_full_name character varying(255) NOT NULL,
    anonymized_email character varying(255) NOT NULL,
    role character varying(20) NOT NULL,
    office_id uuid,
    office_name character varying(255),
    hired_at timestamp with time zone NOT NULL,
    terminated_at timestamp with time zone NOT NULL,
    archived_at timestamp with time zone DEFAULT now() NOT NULL,
    archive_reason character varying(50) NOT NULL,
    legal_retention_until timestamp with time zone NOT NULL,
    metadata jsonb,
    is_test_data boolean DEFAULT false NOT NULL,
    created_at timestamp with time zone DEFAULT now() NOT NULL
);


--
-- Name: TABLE archived_staffs; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON TABLE public.archived_staffs IS '法定保存義務に基づくスタッフアーカイブ（労働基準法・障害者総合支援法対応）';


--
-- Name: COLUMN archived_staffs.original_staff_id; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN public.archived_staffs.original_staff_id IS '元のスタッフID（参照整合性なし）';


--
-- Name: COLUMN archived_staffs.anonymized_full_name; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN public.archived_staffs.anonymized_full_name IS '匿名化された氏名（例: スタッフ-ABC123）';


--
-- Name: COLUMN archived_staffs.anonymized_email; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN public.archived_staffs.anonymized_email IS '匿名化されたメール（例: archived-ABC123@deleted.local）';


--
-- Name: COLUMN archived_staffs.role; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN public.archived_staffs.role IS '役職（owner/manager/employee）';


--
-- Name: COLUMN archived_staffs.office_id; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN public.archived_staffs.office_id IS '所属していた事務所ID（参照整合性なし）';


--
-- Name: COLUMN archived_staffs.office_name; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN public.archived_staffs.office_name IS '事務所名（スナップショット）';


--
-- Name: COLUMN archived_staffs.hired_at; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN public.archived_staffs.hired_at IS '雇入れ日（元のcreated_at）';


--
-- Name: COLUMN archived_staffs.terminated_at; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN public.archived_staffs.terminated_at IS '退職日（deleted_at）';


--
-- Name: COLUMN archived_staffs.archived_at; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN public.archived_staffs.archived_at IS 'アーカイブ作成日時';


--
-- Name: COLUMN archived_staffs.archive_reason; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN public.archived_staffs.archive_reason IS 'アーカイブ理由（staff_deletion/staff_withdrawal/office_withdrawal）';


--
-- Name: COLUMN archived_staffs.legal_retention_until; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN public.archived_staffs.legal_retention_until IS '法定保存期限（terminated_at + 5年）';


--
-- Name: COLUMN archived_staffs.metadata; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN public.archived_staffs.metadata IS 'その他の法定保存が必要なメタデータ';


--
-- Name: COLUMN archived_staffs.is_test_data; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN public.archived_staffs.is_test_data IS 'テストデータフラグ';


--
-- Name: audit_logs; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.audit_logs (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    staff_id uuid,
    action character varying(100) NOT NULL,
    old_value text,
    new_value text,
    ip_address character varying(45),
    user_agent text,
    "timestamp" timestamp with time zone DEFAULT now() NOT NULL,
    actor_role character varying(50),
    target_type character varying(50),
    target_id uuid,
    office_id uuid,
    details jsonb,
    is_test_data boolean DEFAULT false NOT NULL
);


--
-- Name: COLUMN audit_logs.staff_id; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN public.audit_logs.staff_id IS '操作実行者のスタッフID（システム処理の場合はNULL、削除されたスタッフの場合もNULL）';


--
-- Name: COLUMN audit_logs.actor_role; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN public.audit_logs.actor_role IS '実行時のロール';


--
-- Name: COLUMN audit_logs.target_type; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN public.audit_logs.target_type IS '対象リソースタイプ: staff, office, withdrawal_request など';


--
-- Name: COLUMN audit_logs.target_id; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN public.audit_logs.target_id IS '対象リソースのID';


--
-- Name: COLUMN audit_logs.office_id; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN public.audit_logs.office_id IS '事務所ID（横断検索用、app_adminはNULL可）';


--
-- Name: COLUMN audit_logs.details; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN public.audit_logs.details IS '変更内容（old_values, new_valuesなど）';


--
-- Name: COLUMN audit_logs.is_test_data; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN public.audit_logs.is_test_data IS 'テストデータフラグ';


--
-- Name: billings; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.billings (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    office_id uuid NOT NULL,
    stripe_customer_id character varying(255),
    stripe_subscription_id character varying(255),
    billing_status public.billingstatus DEFAULT 'free'::public.billingstatus NOT NULL,
    trial_start_date timestamp with time zone NOT NULL,
    trial_end_date timestamp with time zone NOT NULL,
    subscription_start_date timestamp with time zone,
    next_billing_date timestamp with time zone,
    current_plan_amount integer DEFAULT 6000 NOT NULL,
    last_payment_date timestamp with time zone,
    created_at timestamp with time zone DEFAULT now() NOT NULL,
    updated_at timestamp with time zone DEFAULT now() NOT NULL,
    scheduled_cancel_at timestamp with time zone,
    CONSTRAINT ck_billings_billing_status CHECK (((billing_status)::text = ANY (ARRAY[('free'::character varying)::text, ('early_payment'::character varying)::text, ('active'::character varying)::text, ('past_due'::character varying)::text, ('trial_expired'::character varying)::text, ('payment_failed'::character varying)::text, ('canceling'::character varying)::text, ('canceled'::character varying)::text])))
);


--
-- Name: TABLE billings; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON TABLE public.billings IS '事業所の課金情報（Officeと1:1リレーション）';


--
-- Name: COLUMN billings.billing_status; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN public.billings.billing_status IS 'Billing status: free (無料トライアル), early_payment (早期支払い完了・無料期間中), active (課金中), past_due (互換用の支払い対応必要状態), trial_expired (無料期間終了・未課金), payment_failed (支払い失敗), canceling (キャンセル予定), canceled (キャンセル済み)';


--
-- Name: calendar_event_instances; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.calendar_event_instances (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    event_series_id uuid NOT NULL,
    instance_title character varying(500) NOT NULL,
    instance_description text,
    event_datetime timestamp with time zone NOT NULL,
    days_before_deadline integer NOT NULL,
    google_event_id character varying(255),
    google_event_url text,
    instance_status public.event_instance_status DEFAULT 'pending'::public.event_instance_status,
    sync_status public.calendar_sync_status DEFAULT 'pending'::public.calendar_sync_status,
    last_sync_at timestamp with time zone,
    last_error_message text,
    reminder_sent boolean DEFAULT false,
    reminder_sent_at timestamp with time zone,
    created_at timestamp with time zone DEFAULT now(),
    updated_at timestamp with time zone DEFAULT now(),
    is_test_data boolean DEFAULT false NOT NULL
);


--
-- Name: COLUMN calendar_event_instances.is_test_data; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN public.calendar_event_instances.is_test_data IS 'テストデータフラグ。Factory関数で生成されたデータはTrue';


--
-- Name: calendar_event_series; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.calendar_event_series (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    office_id uuid NOT NULL,
    welfare_recipient_id uuid NOT NULL,
    event_type public.calendar_event_type NOT NULL,
    series_title character varying(500) NOT NULL,
    base_deadline_date date NOT NULL,
    pattern_type public.reminder_pattern_type DEFAULT 'multiple_fixed'::public.reminder_pattern_type NOT NULL,
    notification_pattern_id uuid,
    reminder_days_before integer[] NOT NULL,
    google_rrule text,
    google_calendar_id character varying(255) NOT NULL,
    google_master_event_id character varying(255),
    series_status public.calendar_sync_status DEFAULT 'pending'::public.calendar_sync_status,
    total_instances integer DEFAULT 0,
    completed_instances integer DEFAULT 0,
    created_at timestamp with time zone DEFAULT now(),
    updated_at timestamp with time zone DEFAULT now(),
    support_plan_cycle_id integer,
    support_plan_status_id integer,
    is_test_data boolean DEFAULT false NOT NULL
);


--
-- Name: COLUMN calendar_event_series.is_test_data; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN public.calendar_event_series.is_test_data IS 'テストデータフラグ。Factory関数で生成されたデータはTrue';


--
-- Name: calendar_events; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.calendar_events (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    office_id uuid NOT NULL,
    welfare_recipient_id uuid NOT NULL,
    event_type public.calendar_event_type NOT NULL,
    google_calendar_id character varying(255) NOT NULL,
    google_event_id character varying(255),
    google_event_url text,
    event_title character varying(500) NOT NULL,
    event_description text,
    event_start_datetime timestamp with time zone NOT NULL,
    event_end_datetime timestamp with time zone NOT NULL,
    created_by_system boolean DEFAULT true,
    sync_status public.calendar_sync_status DEFAULT 'pending'::public.calendar_sync_status,
    last_sync_at timestamp with time zone,
    last_error_message text,
    created_at timestamp with time zone DEFAULT now(),
    updated_at timestamp with time zone DEFAULT now(),
    support_plan_cycle_id integer,
    support_plan_status_id integer,
    is_test_data boolean DEFAULT false NOT NULL,
    CONSTRAINT chk_calendar_events_ref_exclusive CHECK ((((support_plan_cycle_id IS NOT NULL) AND (support_plan_status_id IS NULL)) OR ((support_plan_cycle_id IS NULL) AND (support_plan_status_id IS NOT NULL))))
);


--
-- Name: COLUMN calendar_events.is_test_data; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN public.calendar_events.is_test_data IS 'テストデータフラグ。Factory関数で生成されたデータはTrue';


--
-- Name: disability_details; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.disability_details (
    id integer NOT NULL,
    disability_status_id integer NOT NULL,
    category public.disability_category NOT NULL,
    grade_or_level text,
    physical_disability_type public.physical_disability_type,
    physical_disability_type_other_text text,
    application_status public.application_status NOT NULL,
    created_at timestamp with time zone DEFAULT now() NOT NULL,
    updated_at timestamp with time zone DEFAULT now() NOT NULL,
    is_test_data boolean DEFAULT false NOT NULL
);


--
-- Name: COLUMN disability_details.is_test_data; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN public.disability_details.is_test_data IS 'テストデータフラグ。Factory関数で生成されたデータはTrue';


--
-- Name: disability_details_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public.disability_details_id_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: disability_details_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE public.disability_details_id_seq OWNED BY public.disability_details.id;


--
-- Name: disability_statuses; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.disability_statuses (
    id integer NOT NULL,
    welfare_recipient_id uuid NOT NULL,
    disability_or_disease_name text NOT NULL,
    livelihood_protection public.livelihood_protection NOT NULL,
    special_remarks text,
    created_at timestamp with time zone DEFAULT now() NOT NULL,
    updated_at timestamp with time zone DEFAULT now() NOT NULL,
    is_test_data boolean DEFAULT false NOT NULL
);


--
-- Name: COLUMN disability_statuses.is_test_data; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN public.disability_statuses.is_test_data IS 'テストデータフラグ。Factory関数で生成されたデータはTrue';


--
-- Name: disability_statuses_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public.disability_statuses_id_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: disability_statuses_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE public.disability_statuses_id_seq OWNED BY public.disability_statuses.id;


--
-- Name: email_change_requests; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.email_change_requests (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    staff_id uuid NOT NULL,
    old_email character varying(255) NOT NULL,
    new_email character varying(255) NOT NULL,
    verification_token character varying(255) NOT NULL,
    status character varying(50) NOT NULL,
    expires_at timestamp with time zone NOT NULL,
    created_at timestamp with time zone DEFAULT now() NOT NULL,
    updated_at timestamp with time zone DEFAULT now() NOT NULL
);


--
-- Name: emergency_contacts; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.emergency_contacts (
    id integer NOT NULL,
    service_recipient_detail_id integer NOT NULL,
    first_name character varying(255) NOT NULL,
    last_name character varying(255) NOT NULL,
    first_name_furigana character varying(255) NOT NULL,
    last_name_furigana character varying(255) NOT NULL,
    relationship character varying(255) NOT NULL,
    tel text NOT NULL,
    address text,
    notes text,
    priority integer DEFAULT 0 NOT NULL,
    created_at timestamp with time zone DEFAULT now() NOT NULL,
    updated_at timestamp with time zone DEFAULT now() NOT NULL,
    is_test_data boolean DEFAULT false NOT NULL
);


--
-- Name: COLUMN emergency_contacts.is_test_data; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN public.emergency_contacts.is_test_data IS 'テストデータフラグ。Factory関数で生成されたデータはTrue';


--
-- Name: emergency_contacts_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public.emergency_contacts_id_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: emergency_contacts_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE public.emergency_contacts_id_seq OWNED BY public.emergency_contacts.id;


--
-- Name: employment_related; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.employment_related (
    id integer NOT NULL,
    welfare_recipient_id uuid NOT NULL,
    created_by_staff_id uuid NOT NULL,
    work_conditions public.work_conditions NOT NULL,
    regular_or_part_time_job boolean NOT NULL,
    employment_support boolean NOT NULL,
    work_experience_in_the_past_year boolean NOT NULL,
    suspension_of_work boolean NOT NULL,
    qualifications text,
    main_places_of_employment text,
    general_employment_request boolean NOT NULL,
    desired_job text,
    special_remarks text,
    work_outside_the_facility public.work_outside_facility NOT NULL,
    special_note_about_working_outside_the_facility text,
    created_at timestamp with time zone DEFAULT now() NOT NULL,
    updated_at timestamp with time zone DEFAULT now() NOT NULL,
    is_test_data boolean DEFAULT false NOT NULL,
    desired_tasks_on_asobe text,
    no_employment_experience boolean DEFAULT false NOT NULL,
    attended_job_selection_office boolean DEFAULT false NOT NULL,
    received_employment_assessment boolean DEFAULT false NOT NULL,
    employment_other_experience boolean DEFAULT false NOT NULL,
    employment_other_text text
);


--
-- Name: COLUMN employment_related.is_test_data; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN public.employment_related.is_test_data IS 'テストデータフラグ。Factory関数で生成されたデータはTrue';


--
-- Name: COLUMN employment_related.desired_tasks_on_asobe; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN public.employment_related.desired_tasks_on_asobe IS 'asoBeで希望する作業内容（最大1000文字、Pydanticでバリデーション）';


--
-- Name: COLUMN employment_related.no_employment_experience; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN public.employment_related.no_employment_experience IS '就労経験なし（親チェックボックス）';


--
-- Name: COLUMN employment_related.attended_job_selection_office; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN public.employment_related.attended_job_selection_office IS '就職選択事務所を利用したことがある';


--
-- Name: COLUMN employment_related.received_employment_assessment; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN public.employment_related.received_employment_assessment IS '就労アセスメントを受けたことがある';


--
-- Name: COLUMN employment_related.employment_other_experience; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN public.employment_related.employment_other_experience IS 'その他の就労関連経験がある';


--
-- Name: COLUMN employment_related.employment_other_text; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN public.employment_related.employment_other_text IS 'その他の就労関連経験の詳細';


--
-- Name: employment_related_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public.employment_related_id_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: employment_related_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE public.employment_related_id_seq OWNED BY public.employment_related.id;


--
-- Name: family_of_service_recipients; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.family_of_service_recipients (
    id integer NOT NULL,
    welfare_recipient_id uuid NOT NULL,
    name text NOT NULL,
    relationship text NOT NULL,
    household public.household NOT NULL,
    ones_health text NOT NULL,
    remarks text,
    family_structure_chart text,
    created_at timestamp with time zone DEFAULT now() NOT NULL,
    updated_at timestamp with time zone DEFAULT now() NOT NULL,
    is_test_data boolean DEFAULT false NOT NULL
);


--
-- Name: COLUMN family_of_service_recipients.is_test_data; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN public.family_of_service_recipients.is_test_data IS 'テストデータフラグ。Factory関数で生成されたデータはTrue';


--
-- Name: family_of_service_recipients_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public.family_of_service_recipients_id_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: family_of_service_recipients_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE public.family_of_service_recipients_id_seq OWNED BY public.family_of_service_recipients.id;


--
-- Name: history_of_hospital_visits; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.history_of_hospital_visits (
    id integer NOT NULL,
    medical_matters_id integer NOT NULL,
    disease text NOT NULL,
    frequency_of_hospital_visits text NOT NULL,
    symptoms text NOT NULL,
    medical_institution text NOT NULL,
    doctor text NOT NULL,
    tel text NOT NULL,
    taking_medicine boolean NOT NULL,
    date_started date,
    date_ended date,
    special_remarks text,
    created_at timestamp with time zone DEFAULT now() NOT NULL,
    updated_at timestamp with time zone DEFAULT now() NOT NULL,
    is_test_data boolean DEFAULT false NOT NULL
);


--
-- Name: COLUMN history_of_hospital_visits.is_test_data; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN public.history_of_hospital_visits.is_test_data IS 'テストデータフラグ。Factory関数で生成されたデータはTrue';


--
-- Name: history_of_hospital_visits_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public.history_of_hospital_visits_id_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: history_of_hospital_visits_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE public.history_of_hospital_visits_id_seq OWNED BY public.history_of_hospital_visits.id;


--
-- Name: inquiry_details; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.inquiry_details (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    message_id uuid NOT NULL,
    sender_name character varying(100),
    sender_email character varying(255),
    ip_address character varying(45),
    user_agent text,
    status public.inquiry_status DEFAULT 'new'::public.inquiry_status NOT NULL,
    assigned_staff_id uuid,
    priority public.inquiry_priority DEFAULT 'normal'::public.inquiry_priority NOT NULL,
    admin_notes text,
    delivery_log jsonb,
    created_at timestamp with time zone DEFAULT now() NOT NULL,
    updated_at timestamp with time zone DEFAULT now() NOT NULL,
    is_test_data boolean DEFAULT false NOT NULL,
    content character varying(255)
);


--
-- Name: TABLE inquiry_details; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON TABLE public.inquiry_details IS '問い合わせ詳細情報（Messageと1:1の関係）';


--
-- Name: COLUMN inquiry_details.id; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN public.inquiry_details.id IS '問い合わせ詳細ID';


--
-- Name: COLUMN inquiry_details.message_id; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN public.inquiry_details.message_id IS 'メッセージID（UNIQUE, messages.idへの外部キー）';


--
-- Name: COLUMN inquiry_details.sender_name; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN public.inquiry_details.sender_name IS '送信者名（未ログインユーザー用）';


--
-- Name: COLUMN inquiry_details.sender_email; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN public.inquiry_details.sender_email IS '送信者メールアドレス（未ログインユーザー用）';


--
-- Name: COLUMN inquiry_details.ip_address; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN public.inquiry_details.ip_address IS '送信元IPアドレス（IPv6対応）';


--
-- Name: COLUMN inquiry_details.user_agent; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN public.inquiry_details.user_agent IS 'ユーザーエージェント文字列';


--
-- Name: COLUMN inquiry_details.status; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN public.inquiry_details.status IS 'ステータス（new, open, in_progress, answered, closed, spam）';


--
-- Name: COLUMN inquiry_details.assigned_staff_id; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN public.inquiry_details.assigned_staff_id IS '担当者スタッフID';


--
-- Name: COLUMN inquiry_details.priority; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN public.inquiry_details.priority IS '優先度（low, normal, high）';


--
-- Name: COLUMN inquiry_details.admin_notes; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN public.inquiry_details.admin_notes IS '管理者メモ';


--
-- Name: COLUMN inquiry_details.delivery_log; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN public.inquiry_details.delivery_log IS 'メール送信履歴（JSONB形式）';


--
-- Name: COLUMN inquiry_details.created_at; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN public.inquiry_details.created_at IS '作成日時';


--
-- Name: COLUMN inquiry_details.updated_at; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN public.inquiry_details.updated_at IS '更新日時';


--
-- Name: COLUMN inquiry_details.is_test_data; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN public.inquiry_details.is_test_data IS 'テストデータフラグ';


--
-- Name: issue_analyses; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.issue_analyses (
    id integer NOT NULL,
    welfare_recipient_id uuid NOT NULL,
    created_by_staff_id uuid NOT NULL,
    what_i_like_to_do text,
    im_not_good_at text,
    the_life_i_want text,
    the_support_i_want text,
    points_to_keep_in_mind_when_providing_support text,
    future_dreams text,
    other text,
    created_at timestamp with time zone DEFAULT now() NOT NULL,
    updated_at timestamp with time zone DEFAULT now() NOT NULL,
    is_test_data boolean DEFAULT false NOT NULL
);


--
-- Name: COLUMN issue_analyses.is_test_data; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN public.issue_analyses.is_test_data IS 'テストデータフラグ。Factory関数で生成されたデータはTrue';


--
-- Name: issue_analyses_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public.issue_analyses_id_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: issue_analyses_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE public.issue_analyses_id_seq OWNED BY public.issue_analyses.id;


--
-- Name: medical_matters; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.medical_matters (
    id integer NOT NULL,
    welfare_recipient_id uuid NOT NULL,
    medical_care_insurance public.medical_care_insurance NOT NULL,
    medical_care_insurance_other_text text,
    aiding public.aiding_type NOT NULL,
    history_of_hospitalization_in_the_past_2_years boolean NOT NULL,
    created_at timestamp with time zone DEFAULT now() NOT NULL,
    updated_at timestamp with time zone DEFAULT now() NOT NULL,
    is_test_data boolean DEFAULT false NOT NULL
);


--
-- Name: COLUMN medical_matters.is_test_data; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN public.medical_matters.is_test_data IS 'テストデータフラグ。Factory関数で生成されたデータはTrue';


--
-- Name: medical_matters_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public.medical_matters_id_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: medical_matters_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE public.medical_matters_id_seq OWNED BY public.medical_matters.id;


--
-- Name: message_audit_logs; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.message_audit_logs (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    staff_id uuid,
    message_id uuid,
    action character varying(50) NOT NULL,
    ip_address character varying(45),
    user_agent text,
    success boolean DEFAULT true NOT NULL,
    error_message text,
    created_at timestamp with time zone DEFAULT now() NOT NULL,
    is_test_data boolean DEFAULT false NOT NULL
);


--
-- Name: TABLE message_audit_logs; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON TABLE public.message_audit_logs IS 'メッセージ操作の監査ログ';


--
-- Name: COLUMN message_audit_logs.id; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN public.message_audit_logs.id IS '監査ログID';


--
-- Name: COLUMN message_audit_logs.staff_id; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN public.message_audit_logs.staff_id IS '操作者スタッフID（削除時NULL保持）';


--
-- Name: COLUMN message_audit_logs.message_id; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN public.message_audit_logs.message_id IS 'メッセージID（削除時NULL保持）';


--
-- Name: COLUMN message_audit_logs.action; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN public.message_audit_logs.action IS '操作種別: sent, read, archived, deleted';


--
-- Name: COLUMN message_audit_logs.ip_address; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN public.message_audit_logs.ip_address IS 'IPアドレス（IPv6対応）';


--
-- Name: COLUMN message_audit_logs.user_agent; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN public.message_audit_logs.user_agent IS 'User-Agent文字列';


--
-- Name: COLUMN message_audit_logs.success; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN public.message_audit_logs.success IS '操作成功フラグ';


--
-- Name: COLUMN message_audit_logs.error_message; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN public.message_audit_logs.error_message IS 'エラーメッセージ（失敗時）';


--
-- Name: COLUMN message_audit_logs.is_test_data; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN public.message_audit_logs.is_test_data IS 'テストデータフラグ（テスト環境でのデータクリーンアップ用）';


--
-- Name: message_recipients; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.message_recipients (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    message_id uuid NOT NULL,
    recipient_staff_id uuid NOT NULL,
    is_read boolean DEFAULT false NOT NULL,
    read_at timestamp with time zone,
    is_archived boolean DEFAULT false NOT NULL,
    created_at timestamp with time zone DEFAULT now() NOT NULL,
    updated_at timestamp with time zone DEFAULT now() NOT NULL,
    is_test_data boolean DEFAULT false NOT NULL
);


--
-- Name: TABLE message_recipients; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON TABLE public.message_recipients IS 'メッセージ受信者管理（中間テーブル）';


--
-- Name: COLUMN message_recipients.id; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN public.message_recipients.id IS '受信者レコードID';


--
-- Name: COLUMN message_recipients.message_id; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN public.message_recipients.message_id IS 'メッセージID';


--
-- Name: COLUMN message_recipients.recipient_staff_id; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN public.message_recipients.recipient_staff_id IS '受信者スタッフID';


--
-- Name: COLUMN message_recipients.is_read; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN public.message_recipients.is_read IS '既読フラグ';


--
-- Name: COLUMN message_recipients.read_at; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN public.message_recipients.read_at IS '既読日時';


--
-- Name: COLUMN message_recipients.is_archived; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN public.message_recipients.is_archived IS 'アーカイブフラグ';


--
-- Name: COLUMN message_recipients.is_test_data; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN public.message_recipients.is_test_data IS 'テストデータフラグ（テスト環境でのデータクリーンアップ用）';


--
-- Name: messages; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.messages (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    sender_staff_id uuid,
    office_id uuid NOT NULL,
    message_type character varying(20) DEFAULT 'personal'::character varying NOT NULL,
    priority character varying(20) DEFAULT 'normal'::character varying NOT NULL,
    title character varying(200) NOT NULL,
    content text NOT NULL,
    created_at timestamp with time zone DEFAULT now() NOT NULL,
    updated_at timestamp with time zone DEFAULT now() NOT NULL,
    is_test_data boolean DEFAULT false NOT NULL
);


--
-- Name: TABLE messages; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON TABLE public.messages IS 'メッセージ本体';


--
-- Name: COLUMN messages.id; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN public.messages.id IS 'メッセージID';


--
-- Name: COLUMN messages.sender_staff_id; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN public.messages.sender_staff_id IS '送信者スタッフID（削除時NULL）';


--
-- Name: COLUMN messages.office_id; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN public.messages.office_id IS '所属事務所ID';


--
-- Name: COLUMN messages.message_type; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN public.messages.message_type IS 'メッセージタイプ: personal, announcement, system, inquiry';


--
-- Name: COLUMN messages.priority; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN public.messages.priority IS '優先度: low, normal, high, urgent';


--
-- Name: COLUMN messages.title; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN public.messages.title IS 'タイトル（最大200文字）';


--
-- Name: COLUMN messages.content; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN public.messages.content IS '本文（最大10,000文字）';


--
-- Name: COLUMN messages.is_test_data; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN public.messages.is_test_data IS 'テストデータフラグ（テスト環境でのデータクリーンアップ用）';


--
-- Name: mfa_audit_logs; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.mfa_audit_logs (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    staff_id uuid NOT NULL,
    action character varying(50) NOT NULL,
    ip_address character varying(45),
    user_agent character varying(500),
    details character varying(1000),
    created_at timestamp with time zone DEFAULT now() NOT NULL
);


--
-- Name: mfa_backup_codes; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.mfa_backup_codes (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    staff_id uuid NOT NULL,
    code_hash character varying(255) NOT NULL,
    is_used boolean DEFAULT false NOT NULL,
    used_at timestamp with time zone,
    created_at timestamp with time zone DEFAULT now() NOT NULL
);


--
-- Name: notices; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.notices (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    recipient_staff_id uuid NOT NULL,
    office_id uuid NOT NULL,
    type character varying(50) NOT NULL,
    title character varying(255) NOT NULL,
    content text,
    link_url character varying(255),
    is_read boolean DEFAULT false NOT NULL,
    created_at timestamp with time zone DEFAULT now(),
    updated_at timestamp with time zone DEFAULT now(),
    is_test_data boolean DEFAULT false NOT NULL
);


--
-- Name: COLUMN notices.is_test_data; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN public.notices.is_test_data IS 'テストデータフラグ。Factory関数で生成されたデータはTrue';


--
-- Name: notification_patterns; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.notification_patterns (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    pattern_name character varying(100) NOT NULL,
    pattern_description text,
    event_type public.calendar_event_type NOT NULL,
    reminder_days_before integer[] NOT NULL,
    title_template character varying(500) NOT NULL,
    description_template text,
    is_system_default boolean DEFAULT false,
    is_active boolean DEFAULT true,
    created_at timestamp with time zone DEFAULT now(),
    updated_at timestamp with time zone DEFAULT now()
);


--
-- Name: office_calendar_accounts; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.office_calendar_accounts (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    office_id uuid NOT NULL,
    google_calendar_id character varying(255),
    calendar_name character varying(255),
    calendar_url text,
    service_account_key text,
    service_account_email character varying(255),
    connection_status public.calendar_connection_status DEFAULT 'not_connected'::public.calendar_connection_status NOT NULL,
    last_sync_at timestamp with time zone,
    last_error_message text,
    auto_invite_staff boolean DEFAULT true NOT NULL,
    default_reminder_minutes integer DEFAULT 1440 NOT NULL,
    created_at timestamp with time zone DEFAULT now(),
    updated_at timestamp with time zone DEFAULT now()
);


--
-- Name: office_staffs; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.office_staffs (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    staff_id uuid NOT NULL,
    office_id uuid NOT NULL,
    is_primary boolean NOT NULL,
    created_at timestamp with time zone DEFAULT now() NOT NULL,
    updated_at timestamp with time zone DEFAULT now() NOT NULL,
    is_test_data boolean DEFAULT false NOT NULL
);


--
-- Name: COLUMN office_staffs.is_test_data; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN public.office_staffs.is_test_data IS 'テストデータフラグ。Factory関数で生成されたデータはTrue';


--
-- Name: office_welfare_recipients; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.office_welfare_recipients (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    welfare_recipient_id uuid NOT NULL,
    office_id uuid NOT NULL,
    created_at timestamp with time zone DEFAULT now() NOT NULL,
    updated_at timestamp with time zone DEFAULT now() NOT NULL,
    is_test_data boolean DEFAULT false NOT NULL
);


--
-- Name: COLUMN office_welfare_recipients.is_test_data; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN public.office_welfare_recipients.is_test_data IS 'テストデータフラグ。Factory関数で生成されたデータはTrue';


--
-- Name: offices; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.offices (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    name character varying(255) NOT NULL,
    is_group boolean NOT NULL,
    type public.officetype NOT NULL,
    created_by uuid NOT NULL,
    last_modified_by uuid NOT NULL,
    deactivated_at timestamp with time zone,
    created_at timestamp with time zone DEFAULT now() NOT NULL,
    updated_at timestamp with time zone DEFAULT now() NOT NULL,
    is_test_data boolean DEFAULT false NOT NULL,
    address character varying(500),
    phone_number character varying(20),
    email character varying(255),
    is_deleted boolean DEFAULT false NOT NULL,
    deleted_at timestamp with time zone,
    deleted_by uuid
);


--
-- Name: COLUMN offices.is_test_data; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN public.offices.is_test_data IS 'テストデータフラグ。Factory関数で生成されたデータはTrue';


--
-- Name: password_histories; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.password_histories (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    staff_id uuid NOT NULL,
    hashed_password character varying(255) NOT NULL,
    changed_at timestamp with time zone DEFAULT now() NOT NULL
);


--
-- Name: password_reset_audit_logs; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.password_reset_audit_logs (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    staff_id uuid,
    action character varying(50) NOT NULL,
    email character varying(255),
    ip_address character varying(45),
    user_agent text,
    success boolean DEFAULT true NOT NULL,
    error_message text,
    created_at timestamp with time zone DEFAULT now() NOT NULL
);


--
-- Name: password_reset_tokens; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.password_reset_tokens (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    staff_id uuid NOT NULL,
    token_hash character varying(64) NOT NULL,
    expires_at timestamp with time zone NOT NULL,
    used boolean DEFAULT false NOT NULL,
    used_at timestamp with time zone,
    created_at timestamp with time zone DEFAULT now() NOT NULL,
    updated_at timestamp with time zone DEFAULT now() NOT NULL,
    version integer DEFAULT 0 NOT NULL,
    request_ip character varying(45),
    request_user_agent character varying(500)
);


--
-- Name: plan_deliverables; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.plan_deliverables (
    id integer NOT NULL,
    plan_cycle_id integer NOT NULL,
    deliverable_type public.deliverabletype NOT NULL,
    file_path text NOT NULL,
    original_filename text NOT NULL,
    uploaded_by uuid NOT NULL,
    uploaded_at timestamp with time zone DEFAULT now() NOT NULL,
    is_test_data boolean DEFAULT false NOT NULL
);


--
-- Name: COLUMN plan_deliverables.is_test_data; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN public.plan_deliverables.is_test_data IS 'テストデータフラグ。Factory関数で生成されたデータはTrue';


--
-- Name: plan_deliverables_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public.plan_deliverables_id_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: plan_deliverables_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE public.plan_deliverables_id_seq OWNED BY public.plan_deliverables.id;


--
-- Name: push_subscriptions; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.push_subscriptions (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    staff_id uuid NOT NULL,
    endpoint text NOT NULL,
    p256dh_key text NOT NULL,
    auth_key text NOT NULL,
    user_agent text,
    created_at timestamp with time zone DEFAULT now() NOT NULL,
    updated_at timestamp with time zone DEFAULT now() NOT NULL
);


--
-- Name: TABLE push_subscriptions; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON TABLE public.push_subscriptions IS 'Web Push通知の購読情報（スタッフのデバイス登録）';


--
-- Name: COLUMN push_subscriptions.id; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN public.push_subscriptions.id IS '購読ID（UUID）';


--
-- Name: COLUMN push_subscriptions.staff_id; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN public.push_subscriptions.staff_id IS 'スタッフID（削除時はCASCADE）';


--
-- Name: COLUMN push_subscriptions.endpoint; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN public.push_subscriptions.endpoint IS 'Push Service提供のエンドポイントURL（UNIQUE）';


--
-- Name: COLUMN push_subscriptions.p256dh_key; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN public.push_subscriptions.p256dh_key IS 'P-256公開鍵（暗号化用、Base64エンコード）';


--
-- Name: COLUMN push_subscriptions.auth_key; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN public.push_subscriptions.auth_key IS '認証シークレット（Base64エンコード）';


--
-- Name: COLUMN push_subscriptions.user_agent; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN public.push_subscriptions.user_agent IS 'デバイス/ブラウザ情報（任意）';


--
-- Name: COLUMN push_subscriptions.created_at; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN public.push_subscriptions.created_at IS '購読登録日時';


--
-- Name: COLUMN push_subscriptions.updated_at; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN public.push_subscriptions.updated_at IS '最終更新日時';


--
-- Name: refresh_token_blacklist; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.refresh_token_blacklist (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    jti character varying(64) NOT NULL,
    staff_id uuid NOT NULL,
    blacklisted_at timestamp with time zone DEFAULT now() NOT NULL,
    reason character varying(100) DEFAULT 'password_changed'::character varying NOT NULL,
    expires_at timestamp with time zone NOT NULL
);


--
-- Name: TABLE refresh_token_blacklist; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON TABLE public.refresh_token_blacklist IS 'リフレッシュトークンブラックリスト - パスワード変更時に既存のリフレッシュトークンを無効化';


--
-- Name: COLUMN refresh_token_blacklist.jti; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN public.refresh_token_blacklist.jti IS 'JWT ID - トークンを一意に識別';


--
-- Name: COLUMN refresh_token_blacklist.staff_id; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN public.refresh_token_blacklist.staff_id IS 'スタッフID';


--
-- Name: COLUMN refresh_token_blacklist.blacklisted_at; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN public.refresh_token_blacklist.blacklisted_at IS 'ブラックリスト登録日時';


--
-- Name: COLUMN refresh_token_blacklist.reason; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN public.refresh_token_blacklist.reason IS 'ブラックリスト登録理由 (password_changed, logout_all, etc)';


--
-- Name: COLUMN refresh_token_blacklist.expires_at; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN public.refresh_token_blacklist.expires_at IS 'トークンの有効期限 (cleanup用)';


--
-- Name: service_recipient_details; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.service_recipient_details (
    id integer NOT NULL,
    welfare_recipient_id uuid NOT NULL,
    address text NOT NULL,
    form_of_residence public.form_of_residence NOT NULL,
    form_of_residence_other_text text,
    means_of_transportation public.means_of_transportation NOT NULL,
    means_of_transportation_other_text text,
    tel text NOT NULL,
    created_at timestamp with time zone DEFAULT now() NOT NULL,
    updated_at timestamp with time zone DEFAULT now() NOT NULL,
    is_test_data boolean DEFAULT false NOT NULL
);


--
-- Name: COLUMN service_recipient_details.is_test_data; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN public.service_recipient_details.is_test_data IS 'テストデータフラグ。Factory関数で生成されたデータはTrue';


--
-- Name: service_recipient_details_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public.service_recipient_details_id_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: service_recipient_details_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE public.service_recipient_details_id_seq OWNED BY public.service_recipient_details.id;


--
-- Name: staff_calendar_accounts; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.staff_calendar_accounts (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    staff_id uuid NOT NULL,
    calendar_notifications_enabled boolean DEFAULT true NOT NULL,
    email_notifications_enabled boolean DEFAULT true NOT NULL,
    in_app_notifications_enabled boolean DEFAULT true NOT NULL,
    notification_email character varying(255),
    notification_timing public.notification_timing DEFAULT 'standard'::public.notification_timing NOT NULL,
    custom_reminder_days character varying(100),
    notifications_paused_until date,
    pause_reason character varying(255),
    has_calendar_access boolean DEFAULT false NOT NULL,
    calendar_access_granted_at timestamp with time zone,
    total_notifications_sent integer DEFAULT 0 NOT NULL,
    last_notification_sent_at timestamp with time zone,
    created_at timestamp with time zone DEFAULT now(),
    updated_at timestamp with time zone DEFAULT now()
);


--
-- Name: staffs; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.staffs (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    email character varying(255) NOT NULL,
    hashed_password character varying(255) NOT NULL,
    name character varying(255),
    role public.staffrole NOT NULL,
    created_at timestamp with time zone DEFAULT now() NOT NULL,
    updated_at timestamp with time zone DEFAULT now() NOT NULL,
    is_email_verified boolean DEFAULT false NOT NULL,
    is_mfa_enabled boolean DEFAULT false NOT NULL,
    mfa_secret character varying(255),
    mfa_backup_codes_used integer DEFAULT 0 NOT NULL,
    last_name character varying(50),
    first_name character varying(50),
    last_name_furigana character varying(100),
    first_name_furigana character varying(100),
    full_name character varying(255) DEFAULT ''::character varying NOT NULL,
    password_changed_at timestamp with time zone,
    failed_password_attempts integer DEFAULT 0 NOT NULL,
    is_locked boolean DEFAULT false NOT NULL,
    locked_at timestamp with time zone,
    is_test_data boolean DEFAULT false NOT NULL,
    is_mfa_verified_by_user boolean DEFAULT false NOT NULL,
    is_deleted boolean DEFAULT false NOT NULL,
    deleted_at timestamp with time zone,
    deleted_by uuid,
    hashed_passphrase character varying(255),
    passphrase_changed_at timestamp with time zone,
    notification_preferences jsonb DEFAULT '{"email_notification": true, "in_app_notification": true, "push_threshold_days": 10, "system_notification": false, "email_threshold_days": 30}'::jsonb NOT NULL
);


--
-- Name: COLUMN staffs.is_test_data; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN public.staffs.is_test_data IS 'テストデータフラグ。Factory関数で生成されたデータはTrue';


--
-- Name: COLUMN staffs.is_mfa_verified_by_user; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN public.staffs.is_mfa_verified_by_user IS 'ユーザーが実際にTOTPアプリで検証を完了したか（管理者設定のみの場合はFalse）';


--
-- Name: COLUMN staffs.is_deleted; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN public.staffs.is_deleted IS '論理削除フラグ';


--
-- Name: COLUMN staffs.deleted_at; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN public.staffs.deleted_at IS '削除日時（UTC）';


--
-- Name: COLUMN staffs.deleted_by; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN public.staffs.deleted_by IS '削除を実行したスタッフのID';


--
-- Name: COLUMN staffs.notification_preferences; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN public.staffs.notification_preferences IS 'User notification channel preferences (in_app, email, system) + threshold settings (email_threshold_days: 5/10/20/30, push_threshold_days: 5/10/20/30)';


--
-- Name: support_plan_cycles; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.support_plan_cycles (
    id integer NOT NULL,
    welfare_recipient_id uuid NOT NULL,
    plan_cycle_start_date date,
    final_plan_signed_date date,
    next_renewal_deadline date,
    is_latest_cycle boolean NOT NULL,
    google_calendar_id text,
    google_event_id text,
    google_event_url text,
    created_at timestamp with time zone DEFAULT now() NOT NULL,
    updated_at timestamp with time zone DEFAULT now() NOT NULL,
    cycle_number integer DEFAULT 1,
    next_plan_start_date integer DEFAULT 7,
    office_id uuid NOT NULL,
    is_test_data boolean DEFAULT false NOT NULL
);


--
-- Name: COLUMN support_plan_cycles.next_plan_start_date; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN public.support_plan_cycles.next_plan_start_date IS '次回計画開始期限（日数）';


--
-- Name: COLUMN support_plan_cycles.is_test_data; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN public.support_plan_cycles.is_test_data IS 'テストデータフラグ。Factory関数で生成されたデータはTrue';


--
-- Name: support_plan_cycles_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public.support_plan_cycles_id_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: support_plan_cycles_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE public.support_plan_cycles_id_seq OWNED BY public.support_plan_cycles.id;


--
-- Name: support_plan_statuses; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.support_plan_statuses (
    id integer NOT NULL,
    plan_cycle_id integer NOT NULL,
    step_type public.supportplanstep NOT NULL,
    completed boolean NOT NULL,
    completed_at timestamp with time zone,
    completed_by uuid,
    notes text,
    created_at timestamp with time zone DEFAULT now() NOT NULL,
    updated_at timestamp with time zone DEFAULT now() NOT NULL,
    is_latest_status boolean DEFAULT true NOT NULL,
    due_date date,
    welfare_recipient_id uuid NOT NULL,
    office_id uuid NOT NULL,
    is_test_data boolean DEFAULT false NOT NULL
);


--
-- Name: COLUMN support_plan_statuses.is_test_data; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN public.support_plan_statuses.is_test_data IS 'テストデータフラグ。Factory関数で生成されたデータはTrue';


--
-- Name: support_plan_statuses_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public.support_plan_statuses_id_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: support_plan_statuses_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE public.support_plan_statuses_id_seq OWNED BY public.support_plan_statuses.id;


--
-- Name: terms_agreements; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.terms_agreements (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    staff_id uuid NOT NULL,
    terms_of_service_agreed_at timestamp with time zone,
    privacy_policy_agreed_at timestamp with time zone,
    terms_version character varying(50),
    privacy_version character varying(50),
    ip_address character varying(45),
    user_agent character varying(500),
    created_at timestamp with time zone DEFAULT now() NOT NULL,
    updated_at timestamp with time zone DEFAULT now() NOT NULL
);


--
-- Name: TABLE terms_agreements; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON TABLE public.terms_agreements IS '利用規約・プライバシーポリシーの同意履歴';


--
-- Name: COLUMN terms_agreements.staff_id; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN public.terms_agreements.staff_id IS 'スタッフID（1:1関係）';


--
-- Name: COLUMN terms_agreements.terms_of_service_agreed_at; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN public.terms_agreements.terms_of_service_agreed_at IS '利用規約同意日時';


--
-- Name: COLUMN terms_agreements.privacy_policy_agreed_at; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN public.terms_agreements.privacy_policy_agreed_at IS 'プライバシーポリシー同意日時';


--
-- Name: COLUMN terms_agreements.terms_version; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN public.terms_agreements.terms_version IS '同意した利用規約のバージョン（例: "1.0", "1.1"）';


--
-- Name: COLUMN terms_agreements.privacy_version; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN public.terms_agreements.privacy_version IS '同意したプライバシーポリシーのバージョン（例: "1.0", "1.1"）';


--
-- Name: COLUMN terms_agreements.ip_address; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN public.terms_agreements.ip_address IS '同意時のIPアドレス（監査用）';


--
-- Name: COLUMN terms_agreements.user_agent; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN public.terms_agreements.user_agent IS '同意時のユーザーエージェント（監査用）';


--
-- Name: webhook_events; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.webhook_events (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    event_id character varying(255) NOT NULL,
    event_type character varying(100) NOT NULL,
    source character varying(50) DEFAULT 'stripe'::character varying NOT NULL,
    billing_id uuid,
    office_id uuid,
    payload jsonb,
    processed_at timestamp with time zone DEFAULT now() NOT NULL,
    status character varying(20) DEFAULT 'success'::character varying NOT NULL,
    error_message text,
    created_at timestamp with time zone DEFAULT now() NOT NULL
);


--
-- Name: TABLE webhook_events; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON TABLE public.webhook_events IS 'Webhook冪等性管理テーブル - Stripeから送信されるWebhookイベントの重複処理を防止';


--
-- Name: COLUMN webhook_events.event_id; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN public.webhook_events.event_id IS 'Stripe Event ID (例: evt_1234567890)';


--
-- Name: COLUMN webhook_events.event_type; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN public.webhook_events.event_type IS 'イベントタイプ (例: invoice.payment_succeeded)';


--
-- Name: COLUMN webhook_events.source; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN public.webhook_events.source IS 'Webhook送信元 (stripe, etc.)';


--
-- Name: COLUMN webhook_events.billing_id; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN public.webhook_events.billing_id IS '関連するBilling ID';


--
-- Name: COLUMN webhook_events.office_id; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN public.webhook_events.office_id IS '関連するOffice ID';


--
-- Name: COLUMN webhook_events.payload; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN public.webhook_events.payload IS 'Webhookペイロード（デバッグ用）';


--
-- Name: COLUMN webhook_events.processed_at; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN public.webhook_events.processed_at IS '処理日時';


--
-- Name: COLUMN webhook_events.status; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN public.webhook_events.status IS '処理ステータス (success, failed, skipped)';


--
-- Name: COLUMN webhook_events.error_message; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN public.webhook_events.error_message IS 'エラーメッセージ（処理失敗時）';


--
-- Name: welfare_recipients; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.welfare_recipients (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    first_name character varying(255) NOT NULL,
    last_name character varying(255) NOT NULL,
    birth_day date NOT NULL,
    gender public.gendertype NOT NULL,
    created_at timestamp with time zone DEFAULT now() NOT NULL,
    updated_at timestamp with time zone DEFAULT now() NOT NULL,
    first_name_furigana character varying(255),
    last_name_furigana character varying(255),
    is_test_data boolean DEFAULT false NOT NULL
);


--
-- Name: COLUMN welfare_recipients.is_test_data; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN public.welfare_recipients.is_test_data IS 'テストデータフラグ。Factory関数で生成されたデータはTrue';


--
-- Name: welfare_services_used; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.welfare_services_used (
    id integer NOT NULL,
    welfare_recipient_id uuid NOT NULL,
    office_name text NOT NULL,
    starting_day date NOT NULL,
    amount_used text NOT NULL,
    service_name text NOT NULL,
    created_at timestamp with time zone DEFAULT now() NOT NULL,
    updated_at timestamp with time zone DEFAULT now() NOT NULL,
    is_test_data boolean DEFAULT false NOT NULL
);


--
-- Name: COLUMN welfare_services_used.is_test_data; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN public.welfare_services_used.is_test_data IS 'テストデータフラグ。Factory関数で生成されたデータはTrue';


--
-- Name: welfare_services_used_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public.welfare_services_used_id_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: welfare_services_used_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE public.welfare_services_used_id_seq OWNED BY public.welfare_services_used.id;


--
-- Name: disability_details id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.disability_details ALTER COLUMN id SET DEFAULT nextval('public.disability_details_id_seq'::regclass);


--
-- Name: disability_statuses id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.disability_statuses ALTER COLUMN id SET DEFAULT nextval('public.disability_statuses_id_seq'::regclass);


--
-- Name: emergency_contacts id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.emergency_contacts ALTER COLUMN id SET DEFAULT nextval('public.emergency_contacts_id_seq'::regclass);


--
-- Name: employment_related id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.employment_related ALTER COLUMN id SET DEFAULT nextval('public.employment_related_id_seq'::regclass);


--
-- Name: family_of_service_recipients id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.family_of_service_recipients ALTER COLUMN id SET DEFAULT nextval('public.family_of_service_recipients_id_seq'::regclass);


--
-- Name: history_of_hospital_visits id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.history_of_hospital_visits ALTER COLUMN id SET DEFAULT nextval('public.history_of_hospital_visits_id_seq'::regclass);


--
-- Name: issue_analyses id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.issue_analyses ALTER COLUMN id SET DEFAULT nextval('public.issue_analyses_id_seq'::regclass);


--
-- Name: medical_matters id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.medical_matters ALTER COLUMN id SET DEFAULT nextval('public.medical_matters_id_seq'::regclass);


--
-- Name: plan_deliverables id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.plan_deliverables ALTER COLUMN id SET DEFAULT nextval('public.plan_deliverables_id_seq'::regclass);


--
-- Name: service_recipient_details id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.service_recipient_details ALTER COLUMN id SET DEFAULT nextval('public.service_recipient_details_id_seq'::regclass);


--
-- Name: support_plan_cycles id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.support_plan_cycles ALTER COLUMN id SET DEFAULT nextval('public.support_plan_cycles_id_seq'::regclass);


--
-- Name: support_plan_statuses id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.support_plan_statuses ALTER COLUMN id SET DEFAULT nextval('public.support_plan_statuses_id_seq'::regclass);


--
-- Name: welfare_services_used id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.welfare_services_used ALTER COLUMN id SET DEFAULT nextval('public.welfare_services_used_id_seq'::regclass);


--
-- Name: users_sync users_sync_pkey; Type: CONSTRAINT; Schema: neon_auth; Owner: -
--

ALTER TABLE ONLY neon_auth.users_sync
    ADD CONSTRAINT users_sync_pkey PRIMARY KEY (id);


--
-- Name: alembic_version alembic_version_pkc; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.alembic_version
    ADD CONSTRAINT alembic_version_pkc PRIMARY KEY (version_num);


--
-- Name: approval_requests approval_requests_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.approval_requests
    ADD CONSTRAINT approval_requests_pkey PRIMARY KEY (id);


--
-- Name: archived_staffs archived_staffs_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.archived_staffs
    ADD CONSTRAINT archived_staffs_pkey PRIMARY KEY (id);


--
-- Name: audit_logs audit_logs_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.audit_logs
    ADD CONSTRAINT audit_logs_pkey PRIMARY KEY (id);


--
-- Name: billings billings_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.billings
    ADD CONSTRAINT billings_pkey PRIMARY KEY (id);


--
-- Name: calendar_event_instances calendar_event_instances_google_event_id_key; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.calendar_event_instances
    ADD CONSTRAINT calendar_event_instances_google_event_id_key UNIQUE (google_event_id);


--
-- Name: calendar_event_instances calendar_event_instances_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.calendar_event_instances
    ADD CONSTRAINT calendar_event_instances_pkey PRIMARY KEY (id);


--
-- Name: calendar_event_series calendar_event_series_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.calendar_event_series
    ADD CONSTRAINT calendar_event_series_pkey PRIMARY KEY (id);


--
-- Name: calendar_events calendar_events_google_event_id_key; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.calendar_events
    ADD CONSTRAINT calendar_events_google_event_id_key UNIQUE (google_event_id);


--
-- Name: calendar_events calendar_events_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.calendar_events
    ADD CONSTRAINT calendar_events_pkey PRIMARY KEY (id);


--
-- Name: disability_details disability_details_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.disability_details
    ADD CONSTRAINT disability_details_pkey PRIMARY KEY (id);


--
-- Name: disability_statuses disability_statuses_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.disability_statuses
    ADD CONSTRAINT disability_statuses_pkey PRIMARY KEY (id);


--
-- Name: disability_statuses disability_statuses_welfare_recipient_id_key; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.disability_statuses
    ADD CONSTRAINT disability_statuses_welfare_recipient_id_key UNIQUE (welfare_recipient_id);


--
-- Name: email_change_requests email_change_requests_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.email_change_requests
    ADD CONSTRAINT email_change_requests_pkey PRIMARY KEY (id);


--
-- Name: emergency_contacts emergency_contacts_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.emergency_contacts
    ADD CONSTRAINT emergency_contacts_pkey PRIMARY KEY (id);


--
-- Name: employment_related employment_related_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.employment_related
    ADD CONSTRAINT employment_related_pkey PRIMARY KEY (id);


--
-- Name: employment_related employment_related_welfare_recipient_id_key; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.employment_related
    ADD CONSTRAINT employment_related_welfare_recipient_id_key UNIQUE (welfare_recipient_id);


--
-- Name: family_of_service_recipients family_of_service_recipients_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.family_of_service_recipients
    ADD CONSTRAINT family_of_service_recipients_pkey PRIMARY KEY (id);


--
-- Name: history_of_hospital_visits history_of_hospital_visits_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.history_of_hospital_visits
    ADD CONSTRAINT history_of_hospital_visits_pkey PRIMARY KEY (id);


--
-- Name: inquiry_details inquiry_details_message_id_key; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.inquiry_details
    ADD CONSTRAINT inquiry_details_message_id_key UNIQUE (message_id);


--
-- Name: inquiry_details inquiry_details_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.inquiry_details
    ADD CONSTRAINT inquiry_details_pkey PRIMARY KEY (id);


--
-- Name: issue_analyses issue_analyses_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.issue_analyses
    ADD CONSTRAINT issue_analyses_pkey PRIMARY KEY (id);


--
-- Name: issue_analyses issue_analyses_welfare_recipient_id_key; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.issue_analyses
    ADD CONSTRAINT issue_analyses_welfare_recipient_id_key UNIQUE (welfare_recipient_id);


--
-- Name: medical_matters medical_matters_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.medical_matters
    ADD CONSTRAINT medical_matters_pkey PRIMARY KEY (id);


--
-- Name: medical_matters medical_matters_welfare_recipient_id_key; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.medical_matters
    ADD CONSTRAINT medical_matters_welfare_recipient_id_key UNIQUE (welfare_recipient_id);


--
-- Name: message_audit_logs message_audit_logs_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.message_audit_logs
    ADD CONSTRAINT message_audit_logs_pkey PRIMARY KEY (id);


--
-- Name: message_recipients message_recipients_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.message_recipients
    ADD CONSTRAINT message_recipients_pkey PRIMARY KEY (id);


--
-- Name: messages messages_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.messages
    ADD CONSTRAINT messages_pkey PRIMARY KEY (id);


--
-- Name: mfa_audit_logs mfa_audit_logs_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.mfa_audit_logs
    ADD CONSTRAINT mfa_audit_logs_pkey PRIMARY KEY (id);


--
-- Name: mfa_backup_codes mfa_backup_codes_code_hash_key; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.mfa_backup_codes
    ADD CONSTRAINT mfa_backup_codes_code_hash_key UNIQUE (code_hash);


--
-- Name: mfa_backup_codes mfa_backup_codes_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.mfa_backup_codes
    ADD CONSTRAINT mfa_backup_codes_pkey PRIMARY KEY (id);


--
-- Name: notices notices_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.notices
    ADD CONSTRAINT notices_pkey PRIMARY KEY (id);


--
-- Name: notification_patterns notification_patterns_pattern_name_key; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.notification_patterns
    ADD CONSTRAINT notification_patterns_pattern_name_key UNIQUE (pattern_name);


--
-- Name: notification_patterns notification_patterns_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.notification_patterns
    ADD CONSTRAINT notification_patterns_pkey PRIMARY KEY (id);


--
-- Name: office_calendar_accounts office_calendar_accounts_google_calendar_id_key; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.office_calendar_accounts
    ADD CONSTRAINT office_calendar_accounts_google_calendar_id_key UNIQUE (google_calendar_id);


--
-- Name: office_calendar_accounts office_calendar_accounts_office_id_key; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.office_calendar_accounts
    ADD CONSTRAINT office_calendar_accounts_office_id_key UNIQUE (office_id);


--
-- Name: office_calendar_accounts office_calendar_accounts_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.office_calendar_accounts
    ADD CONSTRAINT office_calendar_accounts_pkey PRIMARY KEY (id);


--
-- Name: office_staffs office_staffs_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.office_staffs
    ADD CONSTRAINT office_staffs_pkey PRIMARY KEY (id);


--
-- Name: office_welfare_recipients office_welfare_recipients_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.office_welfare_recipients
    ADD CONSTRAINT office_welfare_recipients_pkey PRIMARY KEY (id);


--
-- Name: offices offices_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.offices
    ADD CONSTRAINT offices_pkey PRIMARY KEY (id);


--
-- Name: password_histories password_histories_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.password_histories
    ADD CONSTRAINT password_histories_pkey PRIMARY KEY (id);


--
-- Name: password_reset_audit_logs password_reset_audit_logs_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.password_reset_audit_logs
    ADD CONSTRAINT password_reset_audit_logs_pkey PRIMARY KEY (id);


--
-- Name: password_reset_tokens password_reset_tokens_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.password_reset_tokens
    ADD CONSTRAINT password_reset_tokens_pkey PRIMARY KEY (id);


--
-- Name: plan_deliverables plan_deliverables_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.plan_deliverables
    ADD CONSTRAINT plan_deliverables_pkey PRIMARY KEY (id);


--
-- Name: push_subscriptions push_subscriptions_endpoint_key; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.push_subscriptions
    ADD CONSTRAINT push_subscriptions_endpoint_key UNIQUE (endpoint);


--
-- Name: push_subscriptions push_subscriptions_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.push_subscriptions
    ADD CONSTRAINT push_subscriptions_pkey PRIMARY KEY (id);


--
-- Name: refresh_token_blacklist refresh_token_blacklist_jti_key; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.refresh_token_blacklist
    ADD CONSTRAINT refresh_token_blacklist_jti_key UNIQUE (jti);


--
-- Name: refresh_token_blacklist refresh_token_blacklist_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.refresh_token_blacklist
    ADD CONSTRAINT refresh_token_blacklist_pkey PRIMARY KEY (id);


--
-- Name: service_recipient_details service_recipient_details_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.service_recipient_details
    ADD CONSTRAINT service_recipient_details_pkey PRIMARY KEY (id);


--
-- Name: service_recipient_details service_recipient_details_welfare_recipient_id_key; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.service_recipient_details
    ADD CONSTRAINT service_recipient_details_welfare_recipient_id_key UNIQUE (welfare_recipient_id);


--
-- Name: staff_calendar_accounts staff_calendar_accounts_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.staff_calendar_accounts
    ADD CONSTRAINT staff_calendar_accounts_pkey PRIMARY KEY (id);


--
-- Name: staff_calendar_accounts staff_calendar_accounts_staff_id_key; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.staff_calendar_accounts
    ADD CONSTRAINT staff_calendar_accounts_staff_id_key UNIQUE (staff_id);


--
-- Name: staffs staffs_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.staffs
    ADD CONSTRAINT staffs_pkey PRIMARY KEY (id);


--
-- Name: support_plan_cycles support_plan_cycles_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.support_plan_cycles
    ADD CONSTRAINT support_plan_cycles_pkey PRIMARY KEY (id);


--
-- Name: support_plan_statuses support_plan_statuses_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.support_plan_statuses
    ADD CONSTRAINT support_plan_statuses_pkey PRIMARY KEY (id);


--
-- Name: terms_agreements terms_agreements_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.terms_agreements
    ADD CONSTRAINT terms_agreements_pkey PRIMARY KEY (id);


--
-- Name: terms_agreements terms_agreements_staff_id_key; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.terms_agreements
    ADD CONSTRAINT terms_agreements_staff_id_key UNIQUE (staff_id);


--
-- Name: billings uq_billings_office_id; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.billings
    ADD CONSTRAINT uq_billings_office_id UNIQUE (office_id);


--
-- Name: billings uq_billings_stripe_customer_id; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.billings
    ADD CONSTRAINT uq_billings_stripe_customer_id UNIQUE (stripe_customer_id);


--
-- Name: billings uq_billings_stripe_subscription_id; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.billings
    ADD CONSTRAINT uq_billings_stripe_subscription_id UNIQUE (stripe_subscription_id);


--
-- Name: message_recipients uq_message_recipient; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.message_recipients
    ADD CONSTRAINT uq_message_recipient UNIQUE (message_id, recipient_staff_id);


--
-- Name: CONSTRAINT uq_message_recipient ON message_recipients; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON CONSTRAINT uq_message_recipient ON public.message_recipients IS '重複送信防止';


--
-- Name: webhook_events webhook_events_event_id_key; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.webhook_events
    ADD CONSTRAINT webhook_events_event_id_key UNIQUE (event_id);


--
-- Name: webhook_events webhook_events_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.webhook_events
    ADD CONSTRAINT webhook_events_pkey PRIMARY KEY (id);


--
-- Name: welfare_recipients welfare_recipients_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.welfare_recipients
    ADD CONSTRAINT welfare_recipients_pkey PRIMARY KEY (id);


--
-- Name: welfare_services_used welfare_services_used_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.welfare_services_used
    ADD CONSTRAINT welfare_services_used_pkey PRIMARY KEY (id);


--
-- Name: users_sync_deleted_at_idx; Type: INDEX; Schema: neon_auth; Owner: -
--

CREATE INDEX users_sync_deleted_at_idx ON neon_auth.users_sync USING btree (deleted_at);


--
-- Name: idx_approval_requests_created_at; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_approval_requests_created_at ON public.approval_requests USING btree (created_at);


--
-- Name: idx_approval_requests_is_test_data; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_approval_requests_is_test_data ON public.approval_requests USING btree (is_test_data);


--
-- Name: idx_approval_requests_office; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_approval_requests_office ON public.approval_requests USING btree (office_id);


--
-- Name: idx_approval_requests_office_status; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_approval_requests_office_status ON public.approval_requests USING btree (office_id, status);


--
-- Name: idx_approval_requests_requester; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_approval_requests_requester ON public.approval_requests USING btree (requester_staff_id);


--
-- Name: idx_approval_requests_resource_type; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_approval_requests_resource_type ON public.approval_requests USING btree (resource_type);


--
-- Name: idx_approval_requests_status; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_approval_requests_status ON public.approval_requests USING btree (status);


--
-- Name: idx_approval_requests_status_type; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_approval_requests_status_type ON public.approval_requests USING btree (status, resource_type);


--
-- Name: idx_archived_staffs_archived_at; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_archived_staffs_archived_at ON public.archived_staffs USING btree (archived_at);


--
-- Name: idx_archived_staffs_is_test_data; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_archived_staffs_is_test_data ON public.archived_staffs USING btree (is_test_data);


--
-- Name: idx_archived_staffs_office_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_archived_staffs_office_id ON public.archived_staffs USING btree (office_id);


--
-- Name: idx_archived_staffs_original_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_archived_staffs_original_id ON public.archived_staffs USING btree (original_staff_id);


--
-- Name: idx_archived_staffs_retention_until; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_archived_staffs_retention_until ON public.archived_staffs USING btree (legal_retention_until);


--
-- Name: idx_archived_staffs_terminated_at; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_archived_staffs_terminated_at ON public.archived_staffs USING btree (terminated_at);


--
-- Name: idx_audit_action; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_audit_action ON public.password_reset_audit_logs USING btree (action);


--
-- Name: idx_audit_created_at; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_audit_created_at ON public.password_reset_audit_logs USING btree (created_at);


--
-- Name: idx_audit_logs_action_timestamp; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_audit_logs_action_timestamp ON public.audit_logs USING btree (action, "timestamp");


--
-- Name: idx_audit_logs_is_test_data; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_audit_logs_is_test_data ON public.audit_logs USING btree (is_test_data);


--
-- Name: idx_audit_logs_office_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_audit_logs_office_id ON public.audit_logs USING btree (office_id);


--
-- Name: idx_audit_logs_office_timestamp; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_audit_logs_office_timestamp ON public.audit_logs USING btree (office_id, "timestamp");


--
-- Name: idx_audit_logs_target_type; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_audit_logs_target_type ON public.audit_logs USING btree (target_type);


--
-- Name: idx_audit_logs_timestamp; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_audit_logs_timestamp ON public.audit_logs USING btree ("timestamp");


--
-- Name: idx_audit_staff_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_audit_staff_id ON public.password_reset_audit_logs USING btree (staff_id);


--
-- Name: idx_billings_billing_status; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_billings_billing_status ON public.billings USING btree (billing_status);


--
-- Name: idx_calendar_event_instances_datetime; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_calendar_event_instances_datetime ON public.calendar_event_instances USING btree (event_datetime);


--
-- Name: idx_calendar_event_instances_google_event_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_calendar_event_instances_google_event_id ON public.calendar_event_instances USING btree (google_event_id);


--
-- Name: idx_calendar_event_instances_is_test_data; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_calendar_event_instances_is_test_data ON public.calendar_event_instances USING btree (is_test_data);


--
-- Name: idx_calendar_event_instances_reminder_pending; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_calendar_event_instances_reminder_pending ON public.calendar_event_instances USING btree (reminder_sent) WHERE (reminder_sent = false);


--
-- Name: idx_calendar_event_instances_series_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_calendar_event_instances_series_id ON public.calendar_event_instances USING btree (event_series_id);


--
-- Name: idx_calendar_event_instances_status; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_calendar_event_instances_status ON public.calendar_event_instances USING btree (instance_status);


--
-- Name: idx_calendar_event_instances_sync_status; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_calendar_event_instances_sync_status ON public.calendar_event_instances USING btree (sync_status);


--
-- Name: idx_calendar_event_series_deadline_date; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_calendar_event_series_deadline_date ON public.calendar_event_series USING btree (base_deadline_date);


--
-- Name: idx_calendar_event_series_event_type; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_calendar_event_series_event_type ON public.calendar_event_series USING btree (event_type);


--
-- Name: idx_calendar_event_series_is_test_data; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_calendar_event_series_is_test_data ON public.calendar_event_series USING btree (is_test_data);


--
-- Name: idx_calendar_event_series_office_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_calendar_event_series_office_id ON public.calendar_event_series USING btree (office_id);


--
-- Name: idx_calendar_event_series_status; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_calendar_event_series_status ON public.calendar_event_series USING btree (series_status);


--
-- Name: idx_calendar_event_series_welfare_recipient_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_calendar_event_series_welfare_recipient_id ON public.calendar_event_series USING btree (welfare_recipient_id);


--
-- Name: idx_calendar_events_cycle_type_unique; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX idx_calendar_events_cycle_type_unique ON public.calendar_events USING btree (support_plan_cycle_id, event_type) WHERE ((support_plan_cycle_id IS NOT NULL) AND ((sync_status = 'pending'::public.calendar_sync_status) OR (sync_status = 'synced'::public.calendar_sync_status)));


--
-- Name: idx_calendar_events_event_datetime; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_calendar_events_event_datetime ON public.calendar_events USING btree (event_start_datetime);


--
-- Name: idx_calendar_events_event_type; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_calendar_events_event_type ON public.calendar_events USING btree (event_type);


--
-- Name: idx_calendar_events_google_event_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_calendar_events_google_event_id ON public.calendar_events USING btree (google_event_id);


--
-- Name: idx_calendar_events_is_test_data; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_calendar_events_is_test_data ON public.calendar_events USING btree (is_test_data);


--
-- Name: idx_calendar_events_office_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_calendar_events_office_id ON public.calendar_events USING btree (office_id);


--
-- Name: idx_calendar_events_status_type_unique; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX idx_calendar_events_status_type_unique ON public.calendar_events USING btree (support_plan_status_id, event_type) WHERE ((support_plan_status_id IS NOT NULL) AND ((sync_status = 'pending'::public.calendar_sync_status) OR (sync_status = 'synced'::public.calendar_sync_status)));


--
-- Name: idx_calendar_events_sync_status; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_calendar_events_sync_status ON public.calendar_events USING btree (sync_status);


--
-- Name: idx_calendar_events_welfare_recipient_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_calendar_events_welfare_recipient_id ON public.calendar_events USING btree (welfare_recipient_id);


--
-- Name: idx_disability_details_is_test_data; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_disability_details_is_test_data ON public.disability_details USING btree (is_test_data);


--
-- Name: idx_disability_statuses_is_test_data; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_disability_statuses_is_test_data ON public.disability_statuses USING btree (is_test_data);


--
-- Name: idx_emergency_contacts_is_test_data; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_emergency_contacts_is_test_data ON public.emergency_contacts USING btree (is_test_data);


--
-- Name: idx_employment_related_is_test_data; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_employment_related_is_test_data ON public.employment_related USING btree (is_test_data);


--
-- Name: idx_family_of_service_recipients_is_test_data; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_family_of_service_recipients_is_test_data ON public.family_of_service_recipients USING btree (is_test_data);


--
-- Name: idx_history_of_hospital_visits_is_test_data; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_history_of_hospital_visits_is_test_data ON public.history_of_hospital_visits USING btree (is_test_data);


--
-- Name: idx_issue_analyses_is_test_data; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_issue_analyses_is_test_data ON public.issue_analyses USING btree (is_test_data);


--
-- Name: idx_medical_matters_is_test_data; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_medical_matters_is_test_data ON public.medical_matters USING btree (is_test_data);


--
-- Name: idx_message_audit_action; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_message_audit_action ON public.message_audit_logs USING btree (action);


--
-- Name: idx_message_audit_created; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_message_audit_created ON public.message_audit_logs USING btree (created_at DESC);


--
-- Name: idx_message_audit_logs_is_test_data; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_message_audit_logs_is_test_data ON public.message_audit_logs USING btree (is_test_data);


--
-- Name: idx_message_audit_message; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_message_audit_message ON public.message_audit_logs USING btree (message_id);


--
-- Name: idx_message_audit_staff; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_message_audit_staff ON public.message_audit_logs USING btree (staff_id);


--
-- Name: idx_message_recipients_created; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_message_recipients_created ON public.message_recipients USING btree (created_at DESC);


--
-- Name: idx_message_recipients_is_test_data; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_message_recipients_is_test_data ON public.message_recipients USING btree (is_test_data);


--
-- Name: idx_message_recipients_message; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_message_recipients_message ON public.message_recipients USING btree (message_id);


--
-- Name: idx_message_recipients_recipient_read; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_message_recipients_recipient_read ON public.message_recipients USING btree (recipient_staff_id, is_read);


--
-- Name: idx_messages_is_test_data; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_messages_is_test_data ON public.messages USING btree (is_test_data);


--
-- Name: idx_messages_office_created; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_messages_office_created ON public.messages USING btree (office_id, created_at DESC);


--
-- Name: idx_messages_sender; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_messages_sender ON public.messages USING btree (sender_staff_id);


--
-- Name: idx_messages_type; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_messages_type ON public.messages USING btree (message_type);


--
-- Name: idx_notices_created_at; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_notices_created_at ON public.notices USING btree (created_at);


--
-- Name: idx_notices_is_read; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_notices_is_read ON public.notices USING btree (is_read);


--
-- Name: idx_notices_is_test_data; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_notices_is_test_data ON public.notices USING btree (is_test_data);


--
-- Name: idx_notices_office_created; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_notices_office_created ON public.notices USING btree (office_id, created_at DESC);


--
-- Name: idx_notices_office_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_notices_office_id ON public.notices USING btree (office_id);


--
-- Name: idx_notices_recipient_created; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_notices_recipient_created ON public.notices USING btree (recipient_staff_id, created_at DESC);


--
-- Name: idx_notices_recipient_read_created; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_notices_recipient_read_created ON public.notices USING btree (recipient_staff_id, is_read, created_at DESC);


--
-- Name: idx_notices_recipient_staff_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_notices_recipient_staff_id ON public.notices USING btree (recipient_staff_id);


--
-- Name: idx_notification_patterns_active; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_notification_patterns_active ON public.notification_patterns USING btree (is_active) WHERE (is_active = true);


--
-- Name: idx_notification_patterns_event_type; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_notification_patterns_event_type ON public.notification_patterns USING btree (event_type);


--
-- Name: idx_office_calendar_accounts_connection_status; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_office_calendar_accounts_connection_status ON public.office_calendar_accounts USING btree (connection_status);


--
-- Name: idx_office_calendar_accounts_office_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_office_calendar_accounts_office_id ON public.office_calendar_accounts USING btree (office_id);


--
-- Name: idx_office_staffs_is_test_data; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_office_staffs_is_test_data ON public.office_staffs USING btree (is_test_data);


--
-- Name: idx_office_welfare_recipients_is_test_data; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_office_welfare_recipients_is_test_data ON public.office_welfare_recipients USING btree (is_test_data);


--
-- Name: idx_office_welfare_recipients_office; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_office_welfare_recipients_office ON public.office_welfare_recipients USING btree (office_id, welfare_recipient_id);


--
-- Name: INDEX idx_office_welfare_recipients_office; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON INDEX public.idx_office_welfare_recipients_office IS '事業所別検索用のインデックス - ダッシュボードフィルター最適化';


--
-- Name: idx_office_welfare_recipients_office_welfare; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_office_welfare_recipients_office_welfare ON public.office_welfare_recipients USING btree (office_id, welfare_recipient_id);


--
-- Name: idx_offices_is_deleted; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_offices_is_deleted ON public.offices USING btree (is_deleted);


--
-- Name: idx_offices_is_test_data; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_offices_is_test_data ON public.offices USING btree (is_test_data);


--
-- Name: idx_password_reset_composite; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_password_reset_composite ON public.password_reset_tokens USING btree (staff_id, used, expires_at);


--
-- Name: idx_password_reset_token_hash; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX idx_password_reset_token_hash ON public.password_reset_tokens USING btree (token_hash);


--
-- Name: idx_plan_deliverables_cycle_type; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_plan_deliverables_cycle_type ON public.plan_deliverables USING btree (plan_cycle_id, deliverable_type);


--
-- Name: idx_plan_deliverables_is_test_data; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_plan_deliverables_is_test_data ON public.plan_deliverables USING btree (is_test_data);


--
-- Name: idx_push_subscriptions_endpoint_hash; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_push_subscriptions_endpoint_hash ON public.push_subscriptions USING hash (endpoint);


--
-- Name: idx_push_subscriptions_staff_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_push_subscriptions_staff_id ON public.push_subscriptions USING btree (staff_id);


--
-- Name: idx_service_recipient_details_is_test_data; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_service_recipient_details_is_test_data ON public.service_recipient_details USING btree (is_test_data);


--
-- Name: idx_staff_calendar_accounts_notification_timing; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_staff_calendar_accounts_notification_timing ON public.staff_calendar_accounts USING btree (notification_timing);


--
-- Name: idx_staff_calendar_accounts_staff_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_staff_calendar_accounts_staff_id ON public.staff_calendar_accounts USING btree (staff_id);


--
-- Name: idx_staff_is_deleted; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_staff_is_deleted ON public.staffs USING btree (is_deleted);


--
-- Name: idx_staffs_full_name_trgm; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_staffs_full_name_trgm ON public.staffs USING gin (full_name public.gin_trgm_ops);


--
-- Name: idx_staffs_is_test_data; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_staffs_is_test_data ON public.staffs USING btree (is_test_data);


--
-- Name: idx_support_plan_cycles_is_test_data; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_support_plan_cycles_is_test_data ON public.support_plan_cycles USING btree (is_test_data);


--
-- Name: idx_support_plan_cycles_office_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_support_plan_cycles_office_id ON public.support_plan_cycles USING btree (office_id);


--
-- Name: idx_support_plan_cycles_office_latest_renewal; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_support_plan_cycles_office_latest_renewal ON public.support_plan_cycles USING btree (office_id, is_latest_cycle, next_renewal_deadline);


--
-- Name: idx_support_plan_cycles_recipient_latest; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_support_plan_cycles_recipient_latest ON public.support_plan_cycles USING btree (welfare_recipient_id, is_latest_cycle) WHERE (is_latest_cycle = true);


--
-- Name: INDEX idx_support_plan_cycles_recipient_latest; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON INDEX public.idx_support_plan_cycles_recipient_latest IS '最新サイクル検索用の部分インデックス（is_latest_cycle=true のみ）- ダッシュボードフィルター最適化';


--
-- Name: idx_support_plan_cycles_recipient_office_latest; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_support_plan_cycles_recipient_office_latest ON public.support_plan_cycles USING btree (welfare_recipient_id, office_id, is_latest_cycle);


--
-- Name: idx_support_plan_statuses_cycle_latest; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_support_plan_statuses_cycle_latest ON public.support_plan_statuses USING btree (plan_cycle_id, is_latest_status, step_type) WHERE (is_latest_status = true);


--
-- Name: INDEX idx_support_plan_statuses_cycle_latest; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON INDEX public.idx_support_plan_statuses_cycle_latest IS '最新ステータス検索用の部分インデックス（is_latest_status=true のみ）- ダッシュボードフィルター最適化';


--
-- Name: idx_support_plan_statuses_is_test_data; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_support_plan_statuses_is_test_data ON public.support_plan_statuses USING btree (is_test_data);


--
-- Name: idx_support_plan_statuses_office_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_support_plan_statuses_office_id ON public.support_plan_statuses USING btree (office_id);


--
-- Name: idx_support_plan_statuses_office_latest_step; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_support_plan_statuses_office_latest_step ON public.support_plan_statuses USING btree (office_id, is_latest_status, step_type);


--
-- Name: idx_support_plan_statuses_welfare_recipient_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_support_plan_statuses_welfare_recipient_id ON public.support_plan_statuses USING btree (welfare_recipient_id);


--
-- Name: idx_terms_agreements_privacy_agreed; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_terms_agreements_privacy_agreed ON public.terms_agreements USING btree (privacy_policy_agreed_at);


--
-- Name: idx_terms_agreements_staff_id; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX idx_terms_agreements_staff_id ON public.terms_agreements USING btree (staff_id);


--
-- Name: idx_terms_agreements_tos_agreed; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_terms_agreements_tos_agreed ON public.terms_agreements USING btree (terms_of_service_agreed_at);


--
-- Name: idx_webhook_events_billing_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_webhook_events_billing_id ON public.webhook_events USING btree (billing_id);


--
-- Name: idx_webhook_events_event_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_webhook_events_event_id ON public.webhook_events USING btree (event_id);


--
-- Name: idx_webhook_events_event_type; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_webhook_events_event_type ON public.webhook_events USING btree (event_type);


--
-- Name: idx_webhook_events_office_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_webhook_events_office_id ON public.webhook_events USING btree (office_id);


--
-- Name: idx_webhook_events_processed_at; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_webhook_events_processed_at ON public.webhook_events USING btree (processed_at);


--
-- Name: idx_webhook_events_status; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_webhook_events_status ON public.webhook_events USING btree (status);


--
-- Name: idx_welfare_recipients_fname_furigana_trgm; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_welfare_recipients_fname_furigana_trgm ON public.welfare_recipients USING gin (first_name_furigana public.gin_trgm_ops);


--
-- Name: idx_welfare_recipients_furigana; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_welfare_recipients_furigana ON public.welfare_recipients USING btree (last_name_furigana, first_name_furigana);


--
-- Name: INDEX idx_welfare_recipients_furigana; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON INDEX public.idx_welfare_recipients_furigana IS 'ふりがなソート用のインデックス - ダッシュボードフィルター最適化';


--
-- Name: idx_welfare_recipients_furigana_trgm; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_welfare_recipients_furigana_trgm ON public.welfare_recipients USING gin (((((last_name_furigana)::text || ' '::text) || (first_name_furigana)::text)) public.gin_trgm_ops);


--
-- Name: idx_welfare_recipients_is_test_data; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_welfare_recipients_is_test_data ON public.welfare_recipients USING btree (is_test_data);


--
-- Name: idx_welfare_recipients_lname_furigana_trgm; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_welfare_recipients_lname_furigana_trgm ON public.welfare_recipients USING gin (last_name_furigana public.gin_trgm_ops);


--
-- Name: idx_welfare_services_used_is_test_data; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_welfare_services_used_is_test_data ON public.welfare_services_used USING btree (is_test_data);


--
-- Name: ix_audit_logs_action; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX ix_audit_logs_action ON public.audit_logs USING btree (action);


--
-- Name: ix_audit_logs_staff_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX ix_audit_logs_staff_id ON public.audit_logs USING btree (staff_id);


--
-- Name: ix_email_change_requests_verification_token; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX ix_email_change_requests_verification_token ON public.email_change_requests USING btree (verification_token);


--
-- Name: ix_inquiry_details_assigned_staff_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX ix_inquiry_details_assigned_staff_id ON public.inquiry_details USING btree (assigned_staff_id);


--
-- Name: ix_inquiry_details_assigned_status; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX ix_inquiry_details_assigned_status ON public.inquiry_details USING btree (assigned_staff_id, status);


--
-- Name: ix_inquiry_details_created_at; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX ix_inquiry_details_created_at ON public.inquiry_details USING btree (created_at);


--
-- Name: ix_inquiry_details_is_test_data; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX ix_inquiry_details_is_test_data ON public.inquiry_details USING btree (is_test_data);


--
-- Name: ix_inquiry_details_message_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX ix_inquiry_details_message_id ON public.inquiry_details USING btree (message_id);


--
-- Name: ix_inquiry_details_priority_status; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX ix_inquiry_details_priority_status ON public.inquiry_details USING btree (priority, status);


--
-- Name: ix_inquiry_details_sender_email; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX ix_inquiry_details_sender_email ON public.inquiry_details USING btree (sender_email);


--
-- Name: ix_inquiry_details_status; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX ix_inquiry_details_status ON public.inquiry_details USING btree (status);


--
-- Name: ix_inquiry_details_status_created; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX ix_inquiry_details_status_created ON public.inquiry_details USING btree (status, created_at DESC);


--
-- Name: ix_offices_name_is_deleted; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX ix_offices_name_is_deleted ON public.offices USING btree (name, is_deleted);


--
-- Name: ix_password_histories_staff_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX ix_password_histories_staff_id ON public.password_histories USING btree (staff_id);


--
-- Name: ix_refresh_token_blacklist_blacklisted_at; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX ix_refresh_token_blacklist_blacklisted_at ON public.refresh_token_blacklist USING btree (blacklisted_at);


--
-- Name: ix_refresh_token_blacklist_expires_at; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX ix_refresh_token_blacklist_expires_at ON public.refresh_token_blacklist USING btree (expires_at);


--
-- Name: ix_refresh_token_blacklist_jti; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX ix_refresh_token_blacklist_jti ON public.refresh_token_blacklist USING btree (jti);


--
-- Name: ix_refresh_token_blacklist_staff_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX ix_refresh_token_blacklist_staff_id ON public.refresh_token_blacklist USING btree (staff_id);


--
-- Name: ix_staffs_email; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX ix_staffs_email ON public.staffs USING btree (email);


--
-- Name: ix_staffs_full_name; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX ix_staffs_full_name ON public.staffs USING btree (full_name);


--
-- Name: ix_support_plan_statuses_cycle_latest; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX ix_support_plan_statuses_cycle_latest ON public.support_plan_statuses USING btree (plan_cycle_id, is_latest_status);


--
-- Name: ix_support_plan_statuses_is_latest; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX ix_support_plan_statuses_is_latest ON public.support_plan_statuses USING btree (is_latest_status);


--
-- Name: uq_webhook_events_event_id; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX uq_webhook_events_event_id ON public.webhook_events USING btree (event_id);


--
-- Name: calendar_event_instances trigger_update_calendar_event_instances_updated_at; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER trigger_update_calendar_event_instances_updated_at BEFORE UPDATE ON public.calendar_event_instances FOR EACH ROW EXECUTE FUNCTION public.update_calendar_event_instances_updated_at();


--
-- Name: calendar_event_series trigger_update_calendar_event_series_updated_at; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER trigger_update_calendar_event_series_updated_at BEFORE UPDATE ON public.calendar_event_series FOR EACH ROW EXECUTE FUNCTION public.update_calendar_event_series_updated_at();


--
-- Name: calendar_events trigger_update_calendar_events_updated_at; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER trigger_update_calendar_events_updated_at BEFORE UPDATE ON public.calendar_events FOR EACH ROW EXECUTE FUNCTION public.update_calendar_events_updated_at();


--
-- Name: inquiry_details trigger_update_inquiry_details_timestamp; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER trigger_update_inquiry_details_timestamp BEFORE UPDATE ON public.inquiry_details FOR EACH ROW EXECUTE FUNCTION public.update_inquiry_details_updated_at();


--
-- Name: TRIGGER trigger_update_inquiry_details_timestamp ON inquiry_details; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON TRIGGER trigger_update_inquiry_details_timestamp ON public.inquiry_details IS 'updated_at自動更新トリガー';


--
-- Name: notices trigger_update_notices_updated_at; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER trigger_update_notices_updated_at BEFORE UPDATE ON public.notices FOR EACH ROW EXECUTE FUNCTION public.update_notices_updated_at();


--
-- Name: notification_patterns trigger_update_notification_patterns_updated_at; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER trigger_update_notification_patterns_updated_at BEFORE UPDATE ON public.notification_patterns FOR EACH ROW EXECUTE FUNCTION public.update_notification_patterns_updated_at();


--
-- Name: office_calendar_accounts trigger_update_office_calendar_accounts_updated_at; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER trigger_update_office_calendar_accounts_updated_at BEFORE UPDATE ON public.office_calendar_accounts FOR EACH ROW EXECUTE FUNCTION public.update_calendar_accounts_updated_at();


--
-- Name: push_subscriptions trigger_update_push_subscriptions_updated_at; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER trigger_update_push_subscriptions_updated_at BEFORE UPDATE ON public.push_subscriptions FOR EACH ROW EXECUTE FUNCTION public.update_push_subscriptions_updated_at();


--
-- Name: staff_calendar_accounts trigger_update_staff_calendar_accounts_updated_at; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER trigger_update_staff_calendar_accounts_updated_at BEFORE UPDATE ON public.staff_calendar_accounts FOR EACH ROW EXECUTE FUNCTION public.update_calendar_accounts_updated_at();


--
-- Name: disability_details update_disability_details_updated_at; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER update_disability_details_updated_at BEFORE UPDATE ON public.disability_details FOR EACH ROW EXECUTE FUNCTION public.update_updated_at_column();


--
-- Name: disability_statuses update_disability_statuses_updated_at; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER update_disability_statuses_updated_at BEFORE UPDATE ON public.disability_statuses FOR EACH ROW EXECUTE FUNCTION public.update_updated_at_column();


--
-- Name: email_change_requests update_email_change_requests_updated_at; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER update_email_change_requests_updated_at BEFORE UPDATE ON public.email_change_requests FOR EACH ROW EXECUTE FUNCTION public.update_updated_at_column();


--
-- Name: emergency_contacts update_emergency_contacts_updated_at; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER update_emergency_contacts_updated_at BEFORE UPDATE ON public.emergency_contacts FOR EACH ROW EXECUTE FUNCTION public.update_updated_at_column();


--
-- Name: employment_related update_employment_related_updated_at; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER update_employment_related_updated_at BEFORE UPDATE ON public.employment_related FOR EACH ROW EXECUTE FUNCTION public.update_updated_at_column();


--
-- Name: family_of_service_recipients update_family_of_service_recipients_updated_at; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER update_family_of_service_recipients_updated_at BEFORE UPDATE ON public.family_of_service_recipients FOR EACH ROW EXECUTE FUNCTION public.update_updated_at_column();


--
-- Name: history_of_hospital_visits update_history_of_hospital_visits_updated_at; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER update_history_of_hospital_visits_updated_at BEFORE UPDATE ON public.history_of_hospital_visits FOR EACH ROW EXECUTE FUNCTION public.update_updated_at_column();


--
-- Name: issue_analyses update_issue_analyses_updated_at; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER update_issue_analyses_updated_at BEFORE UPDATE ON public.issue_analyses FOR EACH ROW EXECUTE FUNCTION public.update_updated_at_column();


--
-- Name: medical_matters update_medical_matters_updated_at; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER update_medical_matters_updated_at BEFORE UPDATE ON public.medical_matters FOR EACH ROW EXECUTE FUNCTION public.update_updated_at_column();


--
-- Name: service_recipient_details update_service_recipient_details_updated_at; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER update_service_recipient_details_updated_at BEFORE UPDATE ON public.service_recipient_details FOR EACH ROW EXECUTE FUNCTION public.update_updated_at_column();


--
-- Name: welfare_services_used update_welfare_services_used_updated_at; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER update_welfare_services_used_updated_at BEFORE UPDATE ON public.welfare_services_used FOR EACH ROW EXECUTE FUNCTION public.update_updated_at_column();


--
-- Name: audit_logs audit_logs_staff_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.audit_logs
    ADD CONSTRAINT audit_logs_staff_id_fkey FOREIGN KEY (staff_id) REFERENCES public.staffs(id) ON DELETE SET NULL;


--
-- Name: calendar_event_instances calendar_event_instances_event_series_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.calendar_event_instances
    ADD CONSTRAINT calendar_event_instances_event_series_id_fkey FOREIGN KEY (event_series_id) REFERENCES public.calendar_event_series(id) ON DELETE CASCADE;


--
-- Name: calendar_event_series calendar_event_series_notification_pattern_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.calendar_event_series
    ADD CONSTRAINT calendar_event_series_notification_pattern_id_fkey FOREIGN KEY (notification_pattern_id) REFERENCES public.notification_patterns(id);


--
-- Name: disability_details disability_details_disability_status_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.disability_details
    ADD CONSTRAINT disability_details_disability_status_id_fkey FOREIGN KEY (disability_status_id) REFERENCES public.disability_statuses(id) ON DELETE CASCADE;


--
-- Name: disability_statuses disability_statuses_welfare_recipient_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.disability_statuses
    ADD CONSTRAINT disability_statuses_welfare_recipient_id_fkey FOREIGN KEY (welfare_recipient_id) REFERENCES public.welfare_recipients(id) ON DELETE CASCADE;


--
-- Name: email_change_requests email_change_requests_staff_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.email_change_requests
    ADD CONSTRAINT email_change_requests_staff_id_fkey FOREIGN KEY (staff_id) REFERENCES public.staffs(id) ON DELETE CASCADE;


--
-- Name: emergency_contacts emergency_contacts_service_recipient_detail_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.emergency_contacts
    ADD CONSTRAINT emergency_contacts_service_recipient_detail_id_fkey FOREIGN KEY (service_recipient_detail_id) REFERENCES public.service_recipient_details(id) ON DELETE CASCADE;


--
-- Name: employment_related employment_related_created_by_staff_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.employment_related
    ADD CONSTRAINT employment_related_created_by_staff_id_fkey FOREIGN KEY (created_by_staff_id) REFERENCES public.staffs(id) ON DELETE CASCADE;


--
-- Name: employment_related employment_related_welfare_recipient_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.employment_related
    ADD CONSTRAINT employment_related_welfare_recipient_id_fkey FOREIGN KEY (welfare_recipient_id) REFERENCES public.welfare_recipients(id) ON DELETE CASCADE;


--
-- Name: family_of_service_recipients family_of_service_recipients_welfare_recipient_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.family_of_service_recipients
    ADD CONSTRAINT family_of_service_recipients_welfare_recipient_id_fkey FOREIGN KEY (welfare_recipient_id) REFERENCES public.welfare_recipients(id) ON DELETE CASCADE;


--
-- Name: approval_requests fk_approval_requests_office; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.approval_requests
    ADD CONSTRAINT fk_approval_requests_office FOREIGN KEY (office_id) REFERENCES public.offices(id) ON DELETE CASCADE;


--
-- Name: approval_requests fk_approval_requests_requester; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.approval_requests
    ADD CONSTRAINT fk_approval_requests_requester FOREIGN KEY (requester_staff_id) REFERENCES public.staffs(id) ON DELETE CASCADE;


--
-- Name: approval_requests fk_approval_requests_reviewer; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.approval_requests
    ADD CONSTRAINT fk_approval_requests_reviewer FOREIGN KEY (reviewed_by_staff_id) REFERENCES public.staffs(id) ON DELETE SET NULL;


--
-- Name: audit_logs fk_audit_logs_office; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.audit_logs
    ADD CONSTRAINT fk_audit_logs_office FOREIGN KEY (office_id) REFERENCES public.offices(id) ON DELETE SET NULL;


--
-- Name: billings fk_billings_office_id; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.billings
    ADD CONSTRAINT fk_billings_office_id FOREIGN KEY (office_id) REFERENCES public.offices(id) ON DELETE CASCADE;


--
-- Name: calendar_events fk_calendar_events_office_id; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.calendar_events
    ADD CONSTRAINT fk_calendar_events_office_id FOREIGN KEY (office_id) REFERENCES public.offices(id) ON DELETE CASCADE;


--
-- Name: calendar_events fk_calendar_events_support_plan_cycle_id; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.calendar_events
    ADD CONSTRAINT fk_calendar_events_support_plan_cycle_id FOREIGN KEY (support_plan_cycle_id) REFERENCES public.support_plan_cycles(id) ON DELETE CASCADE;


--
-- Name: calendar_events fk_calendar_events_support_plan_status_id; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.calendar_events
    ADD CONSTRAINT fk_calendar_events_support_plan_status_id FOREIGN KEY (support_plan_status_id) REFERENCES public.support_plan_statuses(id) ON DELETE CASCADE;


--
-- Name: calendar_events fk_calendar_events_welfare_recipient_id; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.calendar_events
    ADD CONSTRAINT fk_calendar_events_welfare_recipient_id FOREIGN KEY (welfare_recipient_id) REFERENCES public.welfare_recipients(id) ON DELETE CASCADE;


--
-- Name: mfa_audit_logs fk_mfa_audit_logs_staff_id; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.mfa_audit_logs
    ADD CONSTRAINT fk_mfa_audit_logs_staff_id FOREIGN KEY (staff_id) REFERENCES public.staffs(id) ON DELETE CASCADE;


--
-- Name: mfa_backup_codes fk_mfa_backup_codes_staff_id; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.mfa_backup_codes
    ADD CONSTRAINT fk_mfa_backup_codes_staff_id FOREIGN KEY (staff_id) REFERENCES public.staffs(id) ON DELETE CASCADE;


--
-- Name: office_calendar_accounts fk_office_calendar_accounts_office_id; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.office_calendar_accounts
    ADD CONSTRAINT fk_office_calendar_accounts_office_id FOREIGN KEY (office_id) REFERENCES public.offices(id) ON DELETE CASCADE;


--
-- Name: offices fk_offices_deleted_by_staffs; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.offices
    ADD CONSTRAINT fk_offices_deleted_by_staffs FOREIGN KEY (deleted_by) REFERENCES public.staffs(id) ON DELETE SET NULL;


--
-- Name: refresh_token_blacklist fk_refresh_token_blacklist_staff; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.refresh_token_blacklist
    ADD CONSTRAINT fk_refresh_token_blacklist_staff FOREIGN KEY (staff_id) REFERENCES public.staffs(id) ON DELETE CASCADE;


--
-- Name: staff_calendar_accounts fk_staff_calendar_accounts_staff_id; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.staff_calendar_accounts
    ADD CONSTRAINT fk_staff_calendar_accounts_staff_id FOREIGN KEY (staff_id) REFERENCES public.staffs(id) ON DELETE CASCADE;


--
-- Name: staffs fk_staffs_deleted_by_staffs; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.staffs
    ADD CONSTRAINT fk_staffs_deleted_by_staffs FOREIGN KEY (deleted_by) REFERENCES public.staffs(id);


--
-- Name: support_plan_cycles fk_support_plan_cycles_office_id; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.support_plan_cycles
    ADD CONSTRAINT fk_support_plan_cycles_office_id FOREIGN KEY (office_id) REFERENCES public.offices(id) ON DELETE CASCADE;


--
-- Name: support_plan_statuses fk_support_plan_statuses_office_id; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.support_plan_statuses
    ADD CONSTRAINT fk_support_plan_statuses_office_id FOREIGN KEY (office_id) REFERENCES public.offices(id) ON DELETE CASCADE;


--
-- Name: support_plan_statuses fk_support_plan_statuses_welfare_recipient_id; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.support_plan_statuses
    ADD CONSTRAINT fk_support_plan_statuses_welfare_recipient_id FOREIGN KEY (welfare_recipient_id) REFERENCES public.welfare_recipients(id) ON DELETE CASCADE;


--
-- Name: history_of_hospital_visits history_of_hospital_visits_medical_matters_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.history_of_hospital_visits
    ADD CONSTRAINT history_of_hospital_visits_medical_matters_id_fkey FOREIGN KEY (medical_matters_id) REFERENCES public.medical_matters(id) ON DELETE CASCADE;


--
-- Name: inquiry_details inquiry_details_assigned_staff_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.inquiry_details
    ADD CONSTRAINT inquiry_details_assigned_staff_id_fkey FOREIGN KEY (assigned_staff_id) REFERENCES public.staffs(id) ON DELETE SET NULL;


--
-- Name: inquiry_details inquiry_details_message_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.inquiry_details
    ADD CONSTRAINT inquiry_details_message_id_fkey FOREIGN KEY (message_id) REFERENCES public.messages(id) ON DELETE CASCADE;


--
-- Name: issue_analyses issue_analyses_created_by_staff_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.issue_analyses
    ADD CONSTRAINT issue_analyses_created_by_staff_id_fkey FOREIGN KEY (created_by_staff_id) REFERENCES public.staffs(id) ON DELETE CASCADE;


--
-- Name: issue_analyses issue_analyses_welfare_recipient_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.issue_analyses
    ADD CONSTRAINT issue_analyses_welfare_recipient_id_fkey FOREIGN KEY (welfare_recipient_id) REFERENCES public.welfare_recipients(id) ON DELETE CASCADE;


--
-- Name: medical_matters medical_matters_welfare_recipient_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.medical_matters
    ADD CONSTRAINT medical_matters_welfare_recipient_id_fkey FOREIGN KEY (welfare_recipient_id) REFERENCES public.welfare_recipients(id) ON DELETE CASCADE;


--
-- Name: message_audit_logs message_audit_logs_message_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.message_audit_logs
    ADD CONSTRAINT message_audit_logs_message_id_fkey FOREIGN KEY (message_id) REFERENCES public.messages(id) ON DELETE SET NULL;


--
-- Name: message_audit_logs message_audit_logs_staff_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.message_audit_logs
    ADD CONSTRAINT message_audit_logs_staff_id_fkey FOREIGN KEY (staff_id) REFERENCES public.staffs(id) ON DELETE SET NULL;


--
-- Name: message_recipients message_recipients_message_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.message_recipients
    ADD CONSTRAINT message_recipients_message_id_fkey FOREIGN KEY (message_id) REFERENCES public.messages(id) ON DELETE CASCADE;


--
-- Name: message_recipients message_recipients_recipient_staff_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.message_recipients
    ADD CONSTRAINT message_recipients_recipient_staff_id_fkey FOREIGN KEY (recipient_staff_id) REFERENCES public.staffs(id) ON DELETE CASCADE;


--
-- Name: messages messages_office_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.messages
    ADD CONSTRAINT messages_office_id_fkey FOREIGN KEY (office_id) REFERENCES public.offices(id) ON DELETE CASCADE;


--
-- Name: messages messages_sender_staff_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.messages
    ADD CONSTRAINT messages_sender_staff_id_fkey FOREIGN KEY (sender_staff_id) REFERENCES public.staffs(id) ON DELETE SET NULL;


--
-- Name: notices notices_office_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.notices
    ADD CONSTRAINT notices_office_id_fkey FOREIGN KEY (office_id) REFERENCES public.offices(id) ON DELETE CASCADE;


--
-- Name: notices notices_recipient_staff_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.notices
    ADD CONSTRAINT notices_recipient_staff_id_fkey FOREIGN KEY (recipient_staff_id) REFERENCES public.staffs(id) ON DELETE CASCADE;


--
-- Name: office_staffs office_staffs_office_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.office_staffs
    ADD CONSTRAINT office_staffs_office_id_fkey FOREIGN KEY (office_id) REFERENCES public.offices(id);


--
-- Name: office_staffs office_staffs_staff_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.office_staffs
    ADD CONSTRAINT office_staffs_staff_id_fkey FOREIGN KEY (staff_id) REFERENCES public.staffs(id);


--
-- Name: office_welfare_recipients office_welfare_recipients_office_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.office_welfare_recipients
    ADD CONSTRAINT office_welfare_recipients_office_id_fkey FOREIGN KEY (office_id) REFERENCES public.offices(id);


--
-- Name: office_welfare_recipients office_welfare_recipients_welfare_recipient_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.office_welfare_recipients
    ADD CONSTRAINT office_welfare_recipients_welfare_recipient_id_fkey FOREIGN KEY (welfare_recipient_id) REFERENCES public.welfare_recipients(id);


--
-- Name: offices offices_created_by_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.offices
    ADD CONSTRAINT offices_created_by_fkey FOREIGN KEY (created_by) REFERENCES public.staffs(id);


--
-- Name: offices offices_last_modified_by_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.offices
    ADD CONSTRAINT offices_last_modified_by_fkey FOREIGN KEY (last_modified_by) REFERENCES public.staffs(id);


--
-- Name: password_histories password_histories_staff_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.password_histories
    ADD CONSTRAINT password_histories_staff_id_fkey FOREIGN KEY (staff_id) REFERENCES public.staffs(id) ON DELETE CASCADE;


--
-- Name: password_reset_audit_logs password_reset_audit_logs_staff_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.password_reset_audit_logs
    ADD CONSTRAINT password_reset_audit_logs_staff_id_fkey FOREIGN KEY (staff_id) REFERENCES public.staffs(id) ON DELETE SET NULL;


--
-- Name: password_reset_tokens password_reset_tokens_staff_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.password_reset_tokens
    ADD CONSTRAINT password_reset_tokens_staff_id_fkey FOREIGN KEY (staff_id) REFERENCES public.staffs(id) ON DELETE CASCADE;


--
-- Name: plan_deliverables plan_deliverables_plan_cycle_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.plan_deliverables
    ADD CONSTRAINT plan_deliverables_plan_cycle_id_fkey FOREIGN KEY (plan_cycle_id) REFERENCES public.support_plan_cycles(id);


--
-- Name: plan_deliverables plan_deliverables_uploaded_by_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.plan_deliverables
    ADD CONSTRAINT plan_deliverables_uploaded_by_fkey FOREIGN KEY (uploaded_by) REFERENCES public.staffs(id);


--
-- Name: push_subscriptions push_subscriptions_staff_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.push_subscriptions
    ADD CONSTRAINT push_subscriptions_staff_id_fkey FOREIGN KEY (staff_id) REFERENCES public.staffs(id) ON DELETE CASCADE;


--
-- Name: service_recipient_details service_recipient_details_welfare_recipient_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.service_recipient_details
    ADD CONSTRAINT service_recipient_details_welfare_recipient_id_fkey FOREIGN KEY (welfare_recipient_id) REFERENCES public.welfare_recipients(id) ON DELETE CASCADE;


--
-- Name: support_plan_cycles support_plan_cycles_welfare_recipient_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.support_plan_cycles
    ADD CONSTRAINT support_plan_cycles_welfare_recipient_id_fkey FOREIGN KEY (welfare_recipient_id) REFERENCES public.welfare_recipients(id);


--
-- Name: support_plan_statuses support_plan_statuses_completed_by_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.support_plan_statuses
    ADD CONSTRAINT support_plan_statuses_completed_by_fkey FOREIGN KEY (completed_by) REFERENCES public.staffs(id);


--
-- Name: support_plan_statuses support_plan_statuses_plan_cycle_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.support_plan_statuses
    ADD CONSTRAINT support_plan_statuses_plan_cycle_id_fkey FOREIGN KEY (plan_cycle_id) REFERENCES public.support_plan_cycles(id);


--
-- Name: terms_agreements terms_agreements_staff_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.terms_agreements
    ADD CONSTRAINT terms_agreements_staff_id_fkey FOREIGN KEY (staff_id) REFERENCES public.staffs(id) ON DELETE CASCADE;


--
-- Name: webhook_events webhook_events_billing_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.webhook_events
    ADD CONSTRAINT webhook_events_billing_id_fkey FOREIGN KEY (billing_id) REFERENCES public.billings(id) ON DELETE SET NULL;


--
-- Name: webhook_events webhook_events_office_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.webhook_events
    ADD CONSTRAINT webhook_events_office_id_fkey FOREIGN KEY (office_id) REFERENCES public.offices(id) ON DELETE SET NULL;


--
-- Name: welfare_services_used welfare_services_used_welfare_recipient_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.welfare_services_used
    ADD CONSTRAINT welfare_services_used_welfare_recipient_id_fkey FOREIGN KEY (welfare_recipient_id) REFERENCES public.welfare_recipients(id) ON DELETE CASCADE;


--
-- PostgreSQL database dump complete
--

\unrestrict GmDt5F7ECiyOLwIZ1eFkvIvdgQWmxsaTrJWc1kyhkrMeDs4w87XNW41t7iIz0RU
