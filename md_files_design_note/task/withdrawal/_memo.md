
Table "public.audit_logs"
Column	Type	Collation	Nullable	Default
id	uuid		not null	gen_random_uuid()
staff_id	uuid		not null	
action	character varying(100)		not null	
old_value	text			
new_value	text			
ip_address	character varying(45)			
user_agent	text			
timestamp	timestamp with time zone		not null	now()
Indexes:
"audit_logs_pkey" PRIMARY KEY, btree (id)
"ix_audit_logs_action" btree (action)
"ix_audit_logs_staff_id" btree (staff_id)
Foreign-key constraints:
"audit_logs_staff_id_fkey" FOREIGN KEY (staff_id) REFERENCES staffs(id) ON DELETE CASCADE