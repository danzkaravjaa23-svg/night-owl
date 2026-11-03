-- Read-only metadata only. Do not query job rows or private content for rollout proof.
select jsonb_pretty(jsonb_build_object(
  'checked_at',now(),
  'control_exists',to_regprocedure('public.account_erasure_control(text,uuid,text,text,text,text,uuid)') is not null,
  'control_security_definer',(select prosecdef from pg_proc where oid=to_regprocedure('public.account_erasure_control(text,uuid,text,text,text,text,uuid)')),
  'control_search_path',(select proconfig @> array['search_path=pg_catalog, public, pg_temp'] from pg_proc where oid=to_regprocedure('public.account_erasure_control(text,uuid,text,text,text,text,uuid)')),
  'control_body_md5',(select md5(prosrc) from pg_proc where oid=to_regprocedure('public.account_erasure_control(text,uuid,text,text,text,text,uuid)')),
  'control_body_matches',(select md5(prosrc)='ee3d8273579d7ee10ab33e6428afbd5f' from pg_proc where oid=to_regprocedure('public.account_erasure_control(text,uuid,text,text,text,text,uuid)')),
  'service_execute',has_function_privilege('service_role',to_regprocedure('public.account_erasure_control(text,uuid,text,text,text,text,uuid)'),'execute'),
  'anon_execute_denied',not has_function_privilege('anon',to_regprocedure('public.account_erasure_control(text,uuid,text,text,text,text,uuid)'),'execute'),
  'authenticated_execute_denied',not has_function_privilege('authenticated',to_regprocedure('public.account_erasure_control(text,uuid,text,text,text,text,uuid)'),'execute'),
  'public_execute_denied',not exists(select 1 from pg_proc p cross join lateral aclexplode(p.proacl) a where p.oid=to_regprocedure('public.account_erasure_control(text,uuid,text,text,text,text,uuid)') and a.grantee=0 and a.privilege_type='EXECUTE'),
  'private_schema_hidden',not has_schema_privilege('anon','account_private','usage') and not has_schema_privilege('authenticated','account_private','usage'),
  'journal_rls',(select relrowsecurity from pg_class where oid=to_regclass('account_private.erasure_jobs')),
  'journal_direct_access_denied',not has_table_privilege('anon',to_regclass('account_private.erasure_jobs'),'select') and not has_table_privilege('authenticated',to_regclass('account_private.erasure_jobs'),'select') and not has_table_privilege('service_role',to_regclass('account_private.erasure_jobs'),'select'),
  'social_active_body_matches',(select md5(prosrc)='2ddbc476a8e28a877468ba72b315a3be' from pg_proc where oid=to_regprocedure('public.social_active()')),
  'write_guard_body_matches',(select md5(prosrc)='7d3e952b76b2885159e7a43a040526b9' from pg_proc where oid=to_regprocedure('public.account_erasure_write_guard()')),
  'unguarded_public_tables',(select coalesce(jsonb_agg(c.relname),'[]'::jsonb) from pg_class c join pg_namespace n on n.oid=c.relnamespace where n.nspname='public' and c.relkind='r' and not exists(select 1 from pg_trigger t where t.tgrelid=c.oid and t.tgname='account_erasure_write_guard' and t.tgenabled='O' and t.tgtype=31)),
  'storage_write_guard',exists(select 1 from pg_trigger where tgrelid='storage.objects'::regclass and tgname='account_erasure_write_guard' and tgenabled='O' and tgtype=31)
)) as account_erasure_postflight;
