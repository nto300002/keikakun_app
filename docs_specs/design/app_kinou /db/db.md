List of relations
Schema	Name	Type	Owner
public	alembic_version	table	keikakun_dev
public	audit_logs	table	neondb_owner
public	calendar_event_instances	table	neondb_owner
public	calendar_event_series	table	neondb_owner
public	calendar_events	table	neondb_owner
public	disability_details	table	neondb_owner
public	disability_statuses	table	neondb_owner
public	email_change_requests	table	neondb_owner
public	emergency_contacts	table	neondb_owner
public	employment_related	table	neondb_owner
public	family_of_service_recipients	table	neondb_owner
public	history_of_hospital_visits	table	neondb_owner
public	issue_analyses	table	neondb_owner
public	medical_matters	table	neondb_owner
public	mfa_audit_logs	table	neondb_owner
public	mfa_backup_codes	table	neondb_owner
public	notices	table	neondb_owner
public	notification_patterns	table	neondb_owner
public	office_calendar_accounts	table	neondb_owner
public	office_staffs	table	neondb_owner
public	office_welfare_recipients	table	neondb_owner
public	offices	table	neondb_owner
public	password_histories	table	neondb_owner
public	plan_deliverables	table	neondb_owner
public	service_recipient_details	table	neondb_owner
public	staff_calendar_accounts	table	neondb_owner
public	staffs	table	neondb_owner
public	support_plan_cycles	table	neondb_owner
public	support_plan_statuses	table	neondb_owner
public	welfare_recipients	table	neondb_owner
public	welfare_recipients_part_0	table	neondb_owner
public	welfare_recipients_partitioned	partitioned table	neondb_owner
public	welfare_services_used	table	neondb_owner







Table "public.staffs"
Column	Type	Collation	Nullable	Default
id	uuid		not null	gen_random_uuid()
email	character varying(255)		not null	
hashed_password	character varying(255)		not null	
name	character varying(255)			
role	staffrole		not null	
created_at	timestamp with time zone		not null	now()
updated_at	timestamp with time zone		not null	now()
is_email_verified	boolean		not null	false
is_mfa_enabled	boolean		not null	false
mfa_secret	character varying(255)			
mfa_backup_codes_used	integer		not null	0
last_name	character varying(50)			
first_name	character varying(50)			
last_name_furigana	character varying(100)			
first_name_furigana	character varying(100)			
full_name	character varying(255)			
password_changed_at	timestamp with time zone			
failed_password_attempts	integer		not null	0
is_locked	boolean		not null	false
locked_at	timestamp with time zone			
Indexes:
"staffs_pkey" PRIMARY KEY, btree (id)
"ix_staffs_email" UNIQUE, btree (email)
Referenced by:
TABLE "audit_logs" CONSTRAINT "audit_logs_staff_id_fkey" FOREIGN KEY (staff_id) REFERENCES staffs(id) ON DELETE CASCADE
TABLE "email_change_requests" CONSTRAINT "email_change_requests_staff_id_fkey" FOREIGN KEY (staff_id) REFERENCES staffs(id) ON DELETE CASCADE
TABLE "employment_related" CONSTRAINT "employment_related_created_by_staff_id_fkey" FOREIGN KEY (created_by_staff_id) REFERENCES staffs(id) ON DELETE CASCADE
TABLE "mfa_audit_logs" CONSTRAINT "fk_mfa_audit_logs_staff_id" FOREIGN KEY (staff_id) REFERENCES staffs(id) ON DELETE CASCADE
TABLE "mfa_backup_codes" CONSTRAINT "fk_mfa_backup_codes_staff_id" FOREIGN KEY (staff_id) REFERENCES staffs(id) ON DELETE CASCADE
TABLE "staff_calendar_accounts" CONSTRAINT "fk_staff_calendar_accounts_staff_id" FOREIGN KEY (staff_id) REFERENCES staffs(id) ON DELETE CASCADE
TABLE "issue_analyses" CONSTRAINT "issue_analyses_created_by_staff_id_fkey" FOREIGN KEY (created_by_staff_id) REFERENCES staffs(id) ON DELETE CASCADE
TABLE "notices" CONSTRAINT "notices_recipient_staff_id_fkey" FOREIGN KEY (recipient_staff_id) REFERENCES staffs(id) ON DELETE CASCADE
TABLE "office_staffs" CONSTRAINT "office_staffs_staff_id_fkey" FOREIGN KEY (staff_id) REFERENCES staffs(id)
TABLE "offices" CONSTRAINT "offices_created_by_fkey" FOREIGN KEY (created_by) REFERENCES staffs(id)
TABLE "offices" CONSTRAINT "offices_last_modified_by_fkey" FOREIGN KEY (last_modified_by) REFERENCES staffs(id)
TABLE "password_histories" CONSTRAINT "password_histories_staff_id_fkey" FOREIGN KEY (staff_id) REFERENCES staffs(id) ON DELETE CASCADE
TABLE "plan_deliverables" CONSTRAINT "plan_deliverables_uploaded_by_fkey" FOREIGN KEY (uploaded_by) REFERENCES staffs(id)
TABLE "support_plan_statuses" CONSTRAINT "support_plan_statuses_completed_by_fkey" FOREIGN KEY (completed_by) REFERENCES staffs(id)


Table "public.staff_calendar_accounts"
Column	Type	Collation	Nullable	Default
id	uuid		not null	gen_random_uuid()
staff_id	uuid		not null	
calendar_notifications_enabled	boolean		not null	true
email_notifications_enabled	boolean		not null	true
in_app_notifications_enabled	boolean		not null	true
notification_email	character varying(255)			
notification_timing	notification_timing		not null	'standard'::notification_timing
custom_reminder_days	character varying(100)			
notifications_paused_until	date			
pause_reason	character varying(255)			
has_calendar_access	boolean		not null	false
calendar_access_granted_at	timestamp with time zone			
total_notifications_sent	integer		not null	0
last_notification_sent_at	timestamp with time zone			
created_at	timestamp with time zone			now()
updated_at	timestamp with time zone			now()
Indexes:
"staff_calendar_accounts_pkey" PRIMARY KEY, btree (id)
"idx_staff_calendar_accounts_notification_timing" btree (notification_timing)
"idx_staff_calendar_accounts_staff_id" btree (staff_id)
"staff_calendar_accounts_staff_id_key" UNIQUE CONSTRAINT, btree (staff_id)
Foreign-key constraints:
"fk_staff_calendar_accounts_staff_id" FOREIGN KEY (staff_id) REFERENCES staffs(id) ON DELETE CASCADE
Triggers:
trigger_update_staff_calendar_accounts_updated_at BEFORE UPDATE ON staff_calendar_accounts FOR EACH ROW EXECUTE FUNCTION update_calendar_accounts_updated_at()



Table "public.offices"
Column	Type	Collation	Nullable	Default
id	uuid		not null	gen_random_uuid()
name	character varying(255)		not null	
is_group	boolean		not null	
type	officetype		not null	
created_by	uuid		not null	
last_modified_by	uuid		not null	
billing_status	billingstatus		not null	
stripe_customer_id	character varying(255)			
stripe_subscription_id	character varying(255)			
deactivated_at	timestamp with time zone			
created_at	timestamp with time zone		not null	now()
updated_at	timestamp with time zone		not null	now()
Indexes:
"offices_pkey" PRIMARY KEY, btree (id)
"offices_stripe_customer_id_key" UNIQUE CONSTRAINT, btree (stripe_customer_id)
"offices_stripe_subscription_id_key" UNIQUE CONSTRAINT, btree (stripe_subscription_id)
Foreign-key constraints:
"offices_created_by_fkey" FOREIGN KEY (created_by) REFERENCES staffs(id)
"offices_last_modified_by_fkey" FOREIGN KEY (last_modified_by) REFERENCES staffs(id)
Referenced by:
TABLE "calendar_events" CONSTRAINT "fk_calendar_events_office_id" FOREIGN KEY (office_id) REFERENCES offices(id) ON DELETE CASCADE
TABLE "office_calendar_accounts" CONSTRAINT "fk_office_calendar_accounts_office_id" FOREIGN KEY (office_id) REFERENCES offices(id) ON DELETE CASCADE
TABLE "support_plan_cycles" CONSTRAINT "fk_support_plan_cycles_office_id" FOREIGN KEY (office_id) REFERENCES offices(id) ON DELETE CASCADE
TABLE "support_plan_statuses" CONSTRAINT "fk_support_plan_statuses_office_id" FOREIGN KEY (office_id) REFERENCES offices(id) ON DELETE CASCADE
TABLE "notices" CONSTRAINT "notices_office_id_fkey" FOREIGN KEY (office_id) REFERENCES offices(id) ON DELETE CASCADE
TABLE "office_staffs" CONSTRAINT "office_staffs_office_id_fkey" FOREIGN KEY (office_id) REFERENCES offices(id)
TABLE "office_welfare_recipients" CONSTRAINT "office_welfare_recipients_office_id_fkey" FOREIGN KEY (office_id) REFERENCES offices(id)



Table "public.office_calendar_accounts"
Column	Type	Collation	Nullable	Default
id	uuid		not null	gen_random_uuid()
office_id	uuid		not null	
google_calendar_id	character varying(255)			
calendar_name	character varying(255)			
calendar_url	text			
service_account_key	text			
service_account_email	character varying(255)			
connection_status	calendar_connection_status		not null	'not_connected'::calendar_connection_status
last_sync_at	timestamp with time zone			
last_error_message	text			
auto_invite_staff	boolean		not null	true
default_reminder_minutes	integer		not null	1440
created_at	timestamp with time zone			now()
updated_at	timestamp with time zone			now()
Indexes:
"office_calendar_accounts_pkey" PRIMARY KEY, btree (id)
"idx_office_calendar_accounts_connection_status" btree (connection_status)
"idx_office_calendar_accounts_office_id" btree (office_id)
"office_calendar_accounts_google_calendar_id_key" UNIQUE CONSTRAINT, btree (google_calendar_id)
"office_calendar_accounts_office_id_key" UNIQUE CONSTRAINT, btree (office_id)
Foreign-key constraints:
"fk_office_calendar_accounts_office_id" FOREIGN KEY (office_id) REFERENCES offices(id) ON DELETE CASCADE
Triggers:
trigger_update_office_calendar_accounts_updated_at BEFORE UPDATE ON office_calendar_accounts FOR EACH ROW EXECUTE FUNCTION update_calendar_accounts_updated_at()



Table "public.support_plan_cycles"
Column	Type	Collation	Nullable	Default
id	integer		not null	nextval('support_plan_cycles_id_seq'::regclass)
welfare_recipient_id	uuid		not null	
plan_cycle_start_date	date			
final_plan_signed_date	date			
next_renewal_deadline	date			
is_latest_cycle	boolean		not null	
google_calendar_id	text			
google_event_id	text			
google_event_url	text			
created_at	timestamp with time zone		not null	now()
updated_at	timestamp with time zone		not null	now()
cycle_number	integer			1
monitoring_deadline	integer			7
office_id	uuid		not null	
Indexes:
"support_plan_cycles_pkey" PRIMARY KEY, btree (id)
"idx_support_plan_cycles_latest_renewal" btree (welfare_recipient_id, next_renewal_deadline) WHERE is_latest_cycle = true
"idx_support_plan_cycles_office_id" btree (office_id)
Foreign-key constraints:
"fk_support_plan_cycles_office_id" FOREIGN KEY (office_id) REFERENCES offices(id) ON DELETE CASCADE
"support_plan_cycles_welfare_recipient_id_fkey" FOREIGN KEY (welfare_recipient_id) REFERENCES welfare_recipients(id)
Referenced by:
TABLE "calendar_events" CONSTRAINT "fk_calendar_events_support_plan_cycle_id" FOREIGN KEY (support_plan_cycle_id) REFERENCES support_plan_cycles(id) ON DELETE CASCADE
TABLE "plan_deliverables" CONSTRAINT "plan_deliverables_plan_cycle_id_fkey" FOREIGN KEY (plan_cycle_id) REFERENCES support_plan_cycles(id)
TABLE "support_plan_statuses" CONSTRAINT "support_plan_statuses_plan_cycle_id_fkey" FOREIGN KEY (plan_cycle_id) REFERENCES support_plan_cycles(id)



Table "public.support_plan_statuses"
Column	Type	Collation	Nullable	Default
id	integer		not null	nextval('support_plan_statuses_id_seq'::regclass)
plan_cycle_id	integer		not null	
step_type	supportplanstep		not null	
completed	boolean		not null	
completed_at	timestamp with time zone			
completed_by	uuid			
notes	text			
created_at	timestamp with time zone		not null	now()
updated_at	timestamp with time zone		not null	now()
is_latest_status	boolean		not null	true
due_date	date			
welfare_recipient_id	uuid		not null	
office_id	uuid		not null	
Indexes:
"support_plan_statuses_pkey" PRIMARY KEY, btree (id)
"idx_support_plan_statuses_office_id" btree (office_id)
"idx_support_plan_statuses_welfare_recipient_id" btree (welfare_recipient_id)
"ix_support_plan_statuses_cycle_latest" btree (plan_cycle_id, is_latest_status)
"ix_support_plan_statuses_is_latest" btree (is_latest_status)
Foreign-key constraints:
"fk_support_plan_statuses_office_id" FOREIGN KEY (office_id) REFERENCES offices(id) ON DELETE CASCADE
"fk_support_plan_statuses_welfare_recipient_id" FOREIGN KEY (welfare_recipient_id) REFERENCES welfare_recipients(id) ON DELETE CASCADE
"support_plan_statuses_completed_by_fkey" FOREIGN KEY (completed_by) REFERENCES staffs(id)
"support_plan_statuses_plan_cycle_id_fkey" FOREIGN KEY (plan_cycle_id) REFERENCES support_plan_cycles(id)
Referenced by:
TABLE "calendar_events" CONSTRAINT "fk_calendar_events_support_plan_status_id" FOREIGN KEY (support_plan_status_id) REFERENCES support_plan_statuses(id) ON DELETE CASCADE



Table "public.calendar_events"
Column	Type	Collation	Nullable	Default
id	uuid		not null	gen_random_uuid()
office_id	uuid		not null	
welfare_recipient_id	uuid		not null	
event_type	calendar_event_type		not null	
google_calendar_id	character varying(255)		not null	
google_event_id	character varying(255)			
google_event_url	text			
event_title	character varying(500)		not null	
event_description	text			
event_start_datetime	timestamp with time zone		not null	
event_end_datetime	timestamp with time zone		not null	
created_by_system	boolean			true
sync_status	calendar_sync_status			'pending'::calendar_sync_status
last_sync_at	timestamp with time zone			
last_error_message	text			
created_at	timestamp with time zone			now()
updated_at	timestamp with time zone			now()
support_plan_cycle_id	integer			
support_plan_status_id	integer			
Indexes:
"calendar_events_pkey" PRIMARY KEY, btree (id)
"calendar_events_google_event_id_key" UNIQUE CONSTRAINT, btree (google_event_id)
"idx_calendar_events_cycle_type_unique" UNIQUE, btree (support_plan_cycle_id, event_type) WHERE support_plan_cycle_id IS NOT NULL AND (sync_status = 'pending'::calendar_sync_status OR sync_status = 'synced'::calendar_sync_status)
"idx_calendar_events_event_datetime" btree (event_start_datetime)
"idx_calendar_events_event_type" btree (event_type)
"idx_calendar_events_google_event_id" btree (google_event_id)
"idx_calendar_events_office_id" btree (office_id)
"idx_calendar_events_status_type_unique" UNIQUE, btree (support_plan_status_id, event_type) WHERE support_plan_status_id IS NOT NULL AND (sync_status = 'pending'::calendar_sync_status OR sync_status = 'synced'::calendar_sync_status)
"idx_calendar_events_sync_status" btree (sync_status)
"idx_calendar_events_welfare_recipient_id" btree (welfare_recipient_id)
Check constraints:
"chk_calendar_events_ref_exclusive" CHECK (support_plan_cycle_id IS NOT NULL AND support_plan_status_id IS NULL OR support_plan_cycle_id IS NULL AND support_plan_status_id IS NOT NULL)
Foreign-key constraints:
"fk_calendar_events_office_id" FOREIGN KEY (office_id) REFERENCES offices(id) ON DELETE CASCADE
"fk_calendar_events_support_plan_cycle_id" FOREIGN KEY (support_plan_cycle_id) REFERENCES support_plan_cycles(id) ON DELETE CASCADE
"fk_calendar_events_support_plan_status_id" FOREIGN KEY (support_plan_status_id) REFERENCES support_plan_statuses(id) ON DELETE CASCADE
"fk_calendar_events_welfare_recipient_id" FOREIGN KEY (welfare_recipient_id) REFERENCES welfare_recipients(id) ON DELETE CASCADE
Triggers:
trigger_update_calendar_events_updated_at BEFORE UPDATE ON calendar_events FOR EACH ROW EXECUTE FUNCTION update_calendar_events_updated_at()    



Table "public.welfare_recipients"
Column	Type	Collation	Nullable	Default
id	uuid		not null	gen_random_uuid()
first_name	character varying(255)		not null	
last_name	character varying(255)		not null	
birth_day	date		not null	
gender	gendertype		not null	
created_at	timestamp with time zone		not null	now()
updated_at	timestamp with time zone		not null	now()
first_name_furigana	character varying(255)			
last_name_furigana	character varying(255)			
Indexes:
"welfare_recipients_pkey" PRIMARY KEY, btree (id)
"idx_welfare_recipients_fname_furigana_trgm" gin (first_name_furigana gin_trgm_ops)
"idx_welfare_recipients_furigana_trgm" gin (((last_name_furigana::text || ' '::text) || first_name_furigana::text) gin_trgm_ops)
"idx_welfare_recipients_lname_furigana_trgm" gin (last_name_furigana gin_trgm_ops)
Referenced by:
TABLE "disability_statuses" CONSTRAINT "disability_statuses_welfare_recipient_id_fkey" FOREIGN KEY (welfare_recipient_id) REFERENCES welfare_recipients(id) ON DELETE CASCADE
TABLE "employment_related" CONSTRAINT "employment_related_welfare_recipient_id_fkey" FOREIGN KEY (welfare_recipient_id) REFERENCES welfare_recipients(id) ON DELETE CASCADE
TABLE "family_of_service_recipients" CONSTRAINT "family_of_service_recipients_welfare_recipient_id_fkey" FOREIGN KEY (welfare_recipient_id) REFERENCES welfare_recipients(id) ON DELETE CASCADE
TABLE "calendar_events" CONSTRAINT "fk_calendar_events_welfare_recipient_id" FOREIGN KEY (welfare_recipient_id) REFERENCES welfare_recipients(id) ON DELETE CASCADE
TABLE "support_plan_statuses" CONSTRAINT "fk_support_plan_statuses_welfare_recipient_id" FOREIGN KEY (welfare_recipient_id) REFERENCES welfare_recipients(id) ON DELETE CASCADE
TABLE "issue_analyses" CONSTRAINT "issue_analyses_welfare_recipient_id_fkey" FOREIGN KEY (welfare_recipient_id) REFERENCES welfare_recipients(id) ON DELETE CASCADE
TABLE "medical_matters" CONSTRAINT "medical_matters_welfare_recipient_id_fkey" FOREIGN KEY (welfare_recipient_id) REFERENCES welfare_recipients(id) ON DELETE CASCADE
TABLE "office_welfare_recipients" CONSTRAINT "office_welfare_recipients_welfare_recipient_id_fkey" FOREIGN KEY (welfare_recipient_id) REFERENCES welfare_recipients(id)
TABLE "service_recipient_details" CONSTRAINT "service_recipient_details_welfare_recipient_id_fkey" FOREIGN KEY (welfare_recipient_id) REFERENCES welfare_recipients(id) ON DELETE CASCADE
TABLE "support_plan_cycles" CONSTRAINT "support_plan_cycles_welfare_recipient_id_fkey" FOREIGN KEY (welfare_recipient_id) REFERENCES welfare_recipients(id)
TABLE "welfare_services_used" CONSTRAINT "welfare_services_used_welfare_recipient_id_fkey" FOREIGN KEY (welfare_recipient_id) REFERENCES welfare_recipients(id) ON DELETE CASCADE


