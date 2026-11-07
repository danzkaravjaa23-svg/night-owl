-- Read-only metadata assertions after 202611070001_ugc_publish_immediately.sql.
-- Selects no content, report, blocked-term or configuration values; only counts
-- and catalog metadata. Run after the migration (or inside its transaction).
begin read only;
do $$ declare t text; r text; f text; begin
 -- 1. Private state exists and is closed to client roles.
 foreach t in array array['admin_private.ugc_publish_config','admin_private.ugc_blocked_terms','admin_private.ugc_report_holds','admin_private.ugc_hold_context'] loop
  if to_regclass(t) is null then raise exception 'Missing publish-immediately state: %',t; end if;
  foreach r in array array['anon','authenticated'] loop
   if has_table_privilege(r,t,'select,insert,update,delete,truncate') then raise exception 'Publish-immediately state exposed to %: %',r,t; end if;
  end loop;
 end loop;
 -- 2. Exactly one settings row and a non-empty blocked-term list.
 if (select count(*) from admin_private.ugc_publish_config)<>1 then raise exception 'Publish-immediately settings must have exactly one row'; end if;
 if not exists(select 1 from admin_private.ugc_blocked_terms) then raise exception 'Blocked-term list is empty'; end if;
 -- 3. Guard is definer-bound and uses the configuration, hold context, filter and
 --    the stored moderator rejection; drafts are only deleted on UPDATE.
 if not exists(select 1 from pg_proc where oid=to_regprocedure('public.ugc_content_guard()') and prosecdef
   and proconfig @> array['search_path=pg_catalog, public, pg_temp']
   and prosrc like '%admin_private.ugc_publish_config%' and prosrc like '%admin_private.ugc_hold_context%' and prosrc like '%public.ugc_screen_text(%'
   and prosrc like '%h.rejected_at is not null%' and prosrc like '%if tg_op=''UPDATE'' then delete from admin_private.ugc_profile_drafts%') then
  raise exception 'Publish-immediately content guard missing'; end if;
 if not exists(select 1 from pg_attribute where attrelid='admin_private.ugc_report_holds'::regclass and attname='rejected_at' and not attisdropped)
   or not exists(select 1 from pg_attribute where attrelid='admin_private.ugc_publish_config'::regclass and attname='reporter_min_account_age' and not attisdropped) then
  raise exception 'Publish-immediately state columns missing'; end if;
 -- 3b. Reporter eligibility reads Auth account age; an automatic hold is not audited as an admin edit.
 if not exists(select 1 from pg_attribute where attrelid='auth.users'::regclass and attname='created_at' and not attisdropped)
   or not exists(select 1 from pg_proc where oid=to_regprocedure('public.ugc_report_threshold()') and prosrc like '%p.moderation_public_ready%' and prosrc like '%reporter_min_account_age%') then
  raise exception 'Reporter eligibility check missing'; end if;
 if not exists(select 1 from pg_proc where oid=to_regprocedure('public.admin_console_audit_change()') and prosecdef
   and prosrc like '%admin_private.ugc_action_context%' and prosrc like '%admin_private.ugc_hold_context%') then
  raise exception 'Audit skip for report holds missing'; end if;
 -- 4. Note guard accepts moderator decisions and report holds.
 if not exists(select 1 from pg_proc where oid=to_regprocedure('public.interaction_note_write_guard()')
   and prosrc like '%admin_private.ugc_action_context%' and prosrc like '%admin_private.ugc_hold_context%') then
  raise exception 'Note moderation guard fix missing'; end if;
 -- 5. Restored comments do not notify twice.
 if not exists(select 1 from pg_proc where oid=to_regprocedure('public.create_comment_notification()') and prosrc like '%previously_published%') then
  raise exception 'Comment notification dedupe missing'; end if;
 -- 6. Report threshold trigger: AFTER INSERT FOR EACH ROW (tgtype 5), enabled.
 if to_regprocedure('public.ugc_report_threshold()') is null or not exists(select 1 from pg_trigger where tgrelid='public.reports'::regclass
   and tgname='zz_ugc_report_threshold' and tgenabled='O' and tgtype=5 and tgfoid=to_regprocedure('public.ugc_report_threshold()')) then
  raise exception 'Report threshold trigger missing'; end if;
 -- 7. Restrictive reporter-hide SELECT policies.
 foreach t in array array['posts','stories','comments','notes','venue_reviews','place_collections'] loop
  if not exists(select 1 from pg_policy where polrelid=to_regclass('public.'||t) and polname='ugc_reporter_hidden_read' and not polpermissive and polcmd='r') then
   raise exception 'Missing reporter-hide policy: %',t; end if;
 end loop;
 -- 8. Only the reporter-hide helper is callable by client roles.
 foreach r in array array['anon','authenticated'] loop
  if not has_function_privilege(r,'public.ugc_viewer_reported_ids(text)','execute') then raise exception 'Reporter-hide helper not executable by %',r; end if;
  foreach f in array array['ugc_fold_case(text)','ugc_strip_marks(text)','ugc_normalize_text(text)','ugc_screen_text(text,jsonb,jsonb)','ugc_report_threshold()','admin_console_audit_change()'] loop
   if has_function_privilege(r,'public.'||f,'execute') then raise exception 'Internal publish-immediately helper exposed: %',f; end if;
  end loop;
 end loop;
 -- 9. Definer helpers pin their search_path.
 foreach f in array array['ugc_screen_text(text,jsonb,jsonb)','ugc_viewer_reported_ids(text)','ugc_report_threshold()'] loop
  if not exists(select 1 from pg_proc where oid=to_regprocedure('public.'||f) and prosecdef and proconfig @> array['search_path=pg_catalog, public, pg_temp']) then
   raise exception 'Helper is not definer-bound with pinned search_path: %',f; end if;
 end loop;
 -- 10. Supporting indexes.
 if to_regclass('public.ugc_reports_reporter_target') is null or to_regclass('public.ugc_reports_target_pending') is null then
  raise exception 'Report lookup indexes missing'; end if;
 -- 11. Review queue stays authenticated-only.
 if has_function_privilege('anon','public.admin_console_review_queue(text,text,integer,integer)','execute')
   or not has_function_privilege('authenticated','public.admin_console_review_queue(text,text,integer,integer)','execute') then
  raise exception 'Review queue privileges changed'; end if;
 -- 12. Column defaults stay pending (publication is decided by the guard).
 foreach t in array array['posts','stories','comments','events','venue_reviews','profiles','notes','place_collections','venues'] loop
  if not exists(select 1 from pg_attribute a join pg_attrdef d on d.adrelid=a.attrelid and d.adnum=a.attnum where a.attrelid=to_regclass('public.'||t) and a.attname='moderation_status' and a.attnotnull and pg_get_expr(d.adbin,d.adrelid)='''pending''::text') then
   raise exception 'New UGC default is no longer pending: %',t; end if;
 end loop;
end $$;
commit;
