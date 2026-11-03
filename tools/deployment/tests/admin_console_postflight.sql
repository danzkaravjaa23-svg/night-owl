-- Read-only catalog checks after installing the admin console migration.
begin read only;
do $$ declare f text; r text; begin
  foreach f in array array['admin_console_summary()','admin_console_users(text,integer,integer)',
    'admin_console_reports(text,integer,integer)','admin_console_content(text,text,integer,integer)',
    'admin_console_audit(integer,integer)','admin_console_action(text,uuid,text,uuid)','review_venue(text,jsonb)'] loop
    if to_regprocedure('public.'||f) is null then raise exception 'Missing RPC %',f; end if;
    if has_function_privilege('anon','public.'||f,'EXECUTE') or not has_function_privilege('authenticated','public.'||f,'EXECUTE') then raise exception 'Invalid RPC grants %',f; end if;
    if not exists(select 1 from pg_proc where oid=to_regprocedure('public.'||f) and prosecdef and proconfig @> array['search_path=pg_catalog, public, pg_temp']) then raise exception 'RPC security/search_path mismatch %',f; end if;
  end loop;
  foreach r in array array['anon','authenticated'] loop
    if has_schema_privilege(r,'admin_private','USAGE') or has_table_privilege(r,'admin_private.action_context','SELECT,INSERT,UPDATE,DELETE,TRUNCATE')
       or has_table_privilege(r,'public.admin_audit_log','SELECT,INSERT,UPDATE,DELETE,TRUNCATE') then raise exception 'Private context or audit table exposed to %',r; end if;
    foreach f in array array['admin_console_maintenance()','admin_console_require_admin()','admin_console_validate_page(integer,integer,text)',
      'admin_console_report_guard()','admin_console_content_delete_guard()','admin_console_audit_change()','protect_profile_flags()'] loop
      if has_function_privilege(r,'public.'||f,'EXECUTE') then raise exception 'Internal helper exposed to %: %',r,f; end if;
    end loop;
  end loop;
  if has_table_privilege('authenticated','public.reports','UPDATE,DELETE,TRUNCATE') then raise exception 'Direct report mutation remains granted'; end if;
  if not exists(select 1 from pg_trigger where tgrelid='public.admin_audit_log'::regclass and tgname='admin_audit_immutable' and tgenabled in ('O','A')) then raise exception 'Append-only audit guard missing'; end if;
end $$;
commit;
