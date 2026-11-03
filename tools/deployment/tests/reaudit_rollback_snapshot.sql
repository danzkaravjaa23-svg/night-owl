-- READ ONLY metadata snapshot. Save the complete JSON outside the public app.
-- This is a review/recovery reference, NOT an automatically executable rollback:
-- restoring old permissive policies would reintroduce the audited defects.
select jsonb_build_object(
 'captured_at',clock_timestamp(),
 'functions',(select jsonb_agg(jsonb_build_object('signature',p.oid::regprocedure::text,'owner',pg_get_userbyid(p.proowner),'acl',p.proacl,'ddl',pg_get_functiondef(p.oid)))
   from pg_proc p join pg_namespace n on n.oid=p.pronamespace where n.nspname='public' and (p.proname like 'admin_console_%' or p.proname in
   ('is_admin','protect_profile_flags','cleanup_post_media','social_media_readable','social_media_writable','record_discovery_activity','social_action_metric','review_venue','check_in_venue','interaction_identity_guard','interaction_note_write_guard'))),
 'policies',(select jsonb_agg(jsonb_build_object('schema',p.schemaname,'table',p.tablename,'name',p.policyname,'mode',p.permissive,'roles',p.roles,'command',p.cmd,'using',p.qual,'check',p.with_check))
   from pg_policies p where (p.schemaname='public' and p.tablename in ('profiles','posts','comments','reports','venues','events','story_views','story_likes','comment_likes','venue_reviews','checkins','notes')) or (p.schemaname='storage' and p.tablename='objects')),
 'tables',(select jsonb_agg(jsonb_build_object('table',c.oid::regclass::text,'owner',pg_get_userbyid(c.relowner),'acl',c.relacl,'rls',c.relrowsecurity,'force_rls',c.relforcerowsecurity,
   'column_acls',(select jsonb_agg(jsonb_build_object('column',a.attname,'acl',a.attacl)) from pg_attribute a where a.attrelid=c.oid and a.attnum>0 and not a.attisdropped and a.attacl is not null)))
   from pg_class c join pg_namespace n on n.oid=c.relnamespace where c.relkind in ('r','p') and (n.nspname='public' or (n.nspname='storage' and c.relname='objects'))),
 'triggers',(select jsonb_agg(jsonb_build_object('table',t.tgrelid::regclass::text,'enabled',t.tgenabled,'ddl',pg_get_triggerdef(t.oid))) from pg_trigger t
   join pg_class c on c.oid=t.tgrelid join pg_namespace n on n.oid=c.relnamespace where not t.tgisinternal and n.nspname='public'
   and c.relname in ('profiles','posts','comments','reports','venues','events','event_features','pilot_creators','pilot_participants','pilot_content','pilot_venues','venue_catalog','story_views','story_likes','comment_likes','venue_reviews','checkins','notes','admin_audit_log'))
) as rollback_metadata;
