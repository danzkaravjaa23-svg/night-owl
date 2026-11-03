-- READ ONLY. One metadata JSON result; no application/Auth rows are selected.
select jsonb_build_object(
 'roles',(select jsonb_agg(jsonb_build_object('name',rolname,'super',rolsuper,'bypass_rls',rolbypassrls)) from pg_roles where rolname in ('anon','authenticated','service_role')),
 'tables',(select jsonb_agg(jsonb_build_object('name',c.relname,'rls',c.relrowsecurity,'force_rls',c.relforcerowsecurity,'owner',pg_get_userbyid(c.relowner),
   'columns',(select jsonb_agg(a.attname order by a.attnum) from pg_attribute a where a.attrelid=c.oid and a.attnum>0 and not a.attisdropped),
   'constraints',(select jsonb_agg(pg_get_constraintdef(x.oid)) from pg_constraint x where x.conrelid=c.oid),
   'anon_select',has_table_privilege('anon',c.oid,'SELECT'),'auth_insert',has_table_privilege('authenticated',c.oid,'INSERT'),
   'auth_update',has_table_privilege('authenticated',c.oid,'UPDATE'),'auth_truncate',has_table_privilege('authenticated',c.oid,'TRUNCATE')) order by c.relname)
   from pg_class c join pg_namespace n on n.oid=c.relnamespace where n.nspname='public' and c.relkind='r' and c.relname in
   ('profiles','posts','comments','stories','story_views','story_likes','comment_likes','venue_reviews','checkins','notes','venues','events','event_features','reports','venue_catalog','pilot_venues','admin_audit_log')),
 'functions',(select jsonb_agg(jsonb_build_object('signature',p.oid::regprocedure::text,'definer',p.prosecdef,'config',p.proconfig,'definition_md5',md5(pg_get_functiondef(p.oid)),
   'anon_execute',has_function_privilege('anon',p.oid,'EXECUTE'),'auth_execute',has_function_privilege('authenticated',p.oid,'EXECUTE')) order by p.proname)
   from pg_proc p join pg_namespace n on n.oid=p.pronamespace where n.nspname='public' and (p.proname like 'admin_console_%' or p.proname in
   ('social_active','social_admin','can_view_author','social_media_readable','social_media_writable','protect_profile_flags','cleanup_post_media','check_in_venue','review_venue','record_discovery_activity','social_action_metric','interaction_identity_guard','interaction_note_write_guard'))),
 'column_grants',(select jsonb_agg(to_jsonb(g)) from information_schema.column_privileges g where table_schema='public' and grantee in ('PUBLIC','anon','authenticated') and table_name in ('profiles','checkins','notes','story_views','story_likes','comment_likes','venue_reviews')),
 'policies',(select jsonb_agg(to_jsonb(p)) from pg_policies p where (schemaname='public' and tablename in ('profiles','checkins','notes','story_views','story_likes','comment_likes','venue_reviews','reports')) or (schemaname='storage' and tablename='objects')),
 'public_truncate_grants',(select jsonb_agg(jsonb_build_object('table',c.relname,'anon',has_table_privilege('anon',c.oid,'TRUNCATE'),'authenticated',has_table_privilege('authenticated',c.oid,'TRUNCATE'))) from pg_class c join pg_namespace n on n.oid=c.relnamespace where n.nspname='public' and c.relkind in ('r','p')),
 'guards',(select jsonb_agg(jsonb_build_object('table',t.tgrelid::regclass::text,'enabled',t.tgenabled,'definition',pg_get_triggerdef(t.oid))) from pg_trigger t where not t.tgisinternal and t.tgname in ('protect_profile_flags','protect_featured_event_admin_flags','trg_cleanup_post_media','interaction_identity_guard','interaction_note_write_guard'))
) as metadata;
