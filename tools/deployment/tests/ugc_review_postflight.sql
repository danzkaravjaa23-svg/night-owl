-- Read-only metadata assertions after installing 009 on staging.
-- Does not select application content, profiles, reports, or Storage objects.
begin read only;
do $$ declare t text; f text; r text; begin
 foreach t in array array['posts','stories','comments','events','venue_reviews','profiles','notes','place_collections','venues'] loop
  if not exists(select 1 from pg_class where oid=to_regclass('public.'||t) and relrowsecurity) then raise exception 'Missing UGC RLS: %',t; end if;
  if not exists(select 1 from pg_policy where polrelid=to_regclass('public.'||t) and polname='ugc_approved_read' and not polpermissive and polcmd='r') then raise exception 'Missing approved-content gate: %',t; end if;
  if not exists(select 1 from pg_trigger where tgrelid=to_regclass('public.'||t) and tgname='ugc_content_guard' and tgenabled in ('O','A')) then raise exception 'Missing review guard: %',t; end if;
  if not exists(select 1 from pg_attribute a join pg_attrdef d on d.adrelid=a.attrelid and d.adnum=a.attnum where a.attrelid=to_regclass('public.'||t) and a.attname='moderation_status' and a.attnotnull and pg_get_expr(d.adbin,d.adrelid)='''pending''::text') then raise exception 'New UGC is not pending by default: %',t; end if;
 end loop;
 foreach f in array array['admin_console_review_queue(text,text,integer,integer)','admin_console_review(text,uuid,uuid,text,text)'] loop
  if not exists(select 1 from pg_proc where oid=to_regprocedure('public.'||f) and prosecdef and proconfig @> array['search_path=pg_catalog, public, pg_temp'])
   or has_function_privilege('anon','public.'||f,'execute') or not has_function_privilege('authenticated','public.'||f,'execute') then raise exception 'Review RPC contract invalid: %',f; end if;
 end loop;
 foreach f in array array['report_ugc(text,uuid,text,text)','ugc_report_capture()'] loop
  if not exists(select 1 from pg_proc where oid=to_regprocedure('public.'||f) and not prosecdef and proconfig @> array['search_path=pg_catalog, public, pg_temp']) then raise exception 'Reporter RLS is not invoker-bound: %',f; end if;
 end loop;
 foreach r in array array['anon','authenticated'] loop
  if has_schema_privilege(r,'admin_private','usage') or has_table_privilege(r,'admin_private.ugc_profile_drafts','select,insert,update,delete,truncate') or has_table_privilege(r,'admin_private.ugc_action_context','select,insert,update,delete,truncate') then raise exception 'Private review state exposed: %',r; end if;
  foreach f in array array['ugc_content_guard()','ugc_public_fields(text,jsonb)','ugc_report_capture()','ugc_recount_approved()','ugc_erase_report_context()'] loop
   if has_function_privilege(r,'public.'||f,'execute') then raise exception 'Internal review helper exposed: %',f; end if;
  end loop;
 end loop;
 if exists(select 1 from storage.buckets where id in ('posts','stories','avatars','venues') and public) then raise exception 'UGC media bucket remains public'; end if;
 if not exists(select 1 from pg_trigger where tgrelid='public.profiles'::regclass and tgname='ugc_erase_report_context' and tgenabled in ('O','A')) then raise exception 'Report erasure hook missing'; end if;
 if not exists(select 1 from pg_proc where oid='public.is_admin()'::regprocedure and prosrc like '%public.social_active()%') then raise exception 'Erasure-frozen admin gate missing'; end if;
 if not exists(select 1 from pg_proc where oid='public.venue_map_activity()'::regprocedure and prosrc like '%s.moderation_status=''approved''%' and prosrc like '%p.moderation_status=''approved''%') then raise exception 'Map counts include unreviewed publications'; end if;
end $$;
commit;
