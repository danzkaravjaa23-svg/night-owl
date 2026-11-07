-- Exact rollback of supabase/migrations/202611070001_ugc_publish_immediately.sql.
-- NOT a migration: keep it outside supabase/migrations so it never auto-runs.
-- Run manually as one transaction, then run tests/ugc_review_postflight.sql and
-- tests/business_conflict_postflight.sql. Restores the reviewed 009/004 bodies.
--
-- Data semantics: rows already approved stay approved (history is not hidden);
-- report-held rows stay pending and remain in the 009 queue; profile drafts are
-- kept. Owner-added blocked terms, config and the stored rejection/hold records
-- are DROPPED (under 009 every edit waits for review anyway); export terms first:
--   select term,match_mode,category from admin_private.ugc_blocked_terms;
-- A later reinstall re-seeds the default term list.
-- The 004 note-guard defect returns, because this rollback is exact.
-- Faster fallback without DDL (keeps report hiding and the note fix):
--   update admin_private.ugc_publish_config set publish_immediately=false;
begin;
set local lock_timeout='5s';
set local statement_timeout='60s';
drop trigger if exists zz_ugc_report_threshold on public.reports;

-- Exact 009 admin_console_audit_change body (reverses the hold-context skip).
do $$ declare definition text; before_text text; after_text text; begin
 before_text:=$fragment$ or exists(select 1 from admin_private.ugc_action_context where transaction_id=txid_current() and actor_id=auth.uid()) then$fragment$;
 after_text:=$fragment$ or exists(select 1 from admin_private.ugc_action_context where transaction_id=txid_current() and actor_id=auth.uid()) or exists(select 1 from admin_private.ugc_hold_context where transaction_id=txid_current()) then$fragment$;
 definition:=pg_get_functiondef('public.admin_console_audit_change()'::regprocedure);
 if strpos(definition,after_text)>0 then execute replace(definition,after_text,before_text); end if;
end $$;

-- Exact 009 ugc_content_guard and its privileges (triggers are untouched).
create or replace function public.ugc_content_guard() returns trigger
language plpgsql security definer set search_path=pg_catalog,public,pg_temp as $$
declare c admin_private.ugc_action_context%rowtype; candidate jsonb; old_public jsonb; changed boolean; media_value text; media_owner text; media_key text; origin text;
begin
 if public.admin_console_maintenance() then return new; end if;
 if tg_op='UPDATE' then
  if new.id is distinct from old.id or (to_jsonb(new)->tg_argv[0]) is distinct from (to_jsonb(old)->tg_argv[0]) then
   raise exception 'Content identity cannot be reassigned' using errcode='42501';
  end if;
  select * into c from admin_private.ugc_action_context where transaction_id=txid_current() and actor_id=auth.uid() and target_id=old.id and kind=tg_argv[1];
  if found and public.is_admin() then
   if c.decision not in ('approved','rejected') or new.moderation_status is distinct from c.decision then
    raise exception 'Invalid review transition' using errcode='42501'; end if;
   return new;
  end if;
  if new.moderation_status is distinct from old.moderation_status or new.moderation_version is distinct from old.moderation_version or new.moderation_submitted_at is distinct from old.moderation_submitted_at
     or (tg_table_name='profiles' and (to_jsonb(new)->'moderation_public_ready') is distinct from (to_jsonb(old)->'moderation_public_ready')) then
   raise exception 'Review state requires a moderator decision' using errcode='42501';
  end if;
 end if;
 candidate:=public.ugc_public_fields(tg_table_name,to_jsonb(new));
 if pg_column_size(candidate)>65536 then raise exception 'Public content is too large' using errcode='22023'; end if;
 old_public:=case when tg_op='UPDATE' then public.ugc_public_fields(tg_table_name,to_jsonb(old)) else null end;
 changed:=tg_op='INSERT' or candidate is distinct from old_public;
 if changed then
  select storage_origin into strict origin from admin_private.ugc_media_config where singleton;
  for media_key,media_value in select key,value #>> '{}' from jsonb_each(candidate) where key in ('media_url','avatar_url','cover_url','music_url')
   union all select e.key,v #>> '{}' from jsonb_each(candidate) e cross join lateral jsonb_array_elements(case when jsonb_typeof(e.value)='array' then e.value else '[]'::jsonb end) v where e.key in ('media_urls','photos') loop
   if media_value is null or media_value='' then continue; end if;
   -- Editing text never forces replacement of an unchanged historical asset.
   if tg_op='UPDATE' and ((media_key in ('media_urls','photos') and coalesce(old_public->media_key,'[]'::jsonb) @> jsonb_build_array(media_value))
     or (media_key not in ('media_urls','photos') and old_public->>media_key=media_value)) then continue; end if;
   if tg_table_name='profiles' and media_key='avatar_url' and media_value in ('nightowl://avatar/young-man','nightowl://avatar/young-woman','nightowl://avatar/older-man','nightowl://avatar/older-woman') then continue; end if;
   -- New media must use our immutable owned Storage namespace. No expiring
   -- signed URL, attacker-origin lookalike, redirect or external URL is saved.
   if not starts_with(media_value,origin||'/storage/v1/object/public/') or
     substring(media_value from char_length(origin)+1) !~ '^/storage/v1/object/public/(posts|stories|avatars|venues)/[0-9a-fA-F-]{36}/[A-Za-z0-9_./-]+$' or
     substring(media_value from char_length(origin)+1) ~ '(^|/)[.]{1,2}(/|$)|//' then
    raise exception 'New media must use the configured owned Storage origin' using errcode='42501';
   end if;
   media_owner:=split_part(substring(media_value from char_length(origin)+char_length('/storage/v1/object/public/')+1),'/',2);
   if media_owner is distinct from to_jsonb(new)->>tg_argv[0] then
    raise exception 'Media must belong to its submitting author' using errcode='42501';
   end if;
  end loop;
 end if;
 if tg_table_name='place_collections' and not coalesce((to_jsonb(new)->>'is_public')::boolean,false) then
  new.moderation_status:='approved';
  if changed then new.moderation_version:=gen_random_uuid(); end if;
  return new;
 end if;
 if changed then
  new.moderation_status:='pending';new.moderation_version:=gen_random_uuid();new.moderation_submitted_at:=clock_timestamp();
  if tg_table_name='profiles' then
   if tg_op='INSERT' then new:=jsonb_populate_record(new,jsonb_build_object('moderation_public_ready',false));
   elsif old.moderation_public_ready then
    insert into admin_private.ugc_profile_drafts(profile_id,candidate) values(old.id,candidate)
     on conflict(profile_id) do update set candidate=ugc_profile_drafts.candidate ||
      (select coalesce(jsonb_object_agg(key,value),'{}'::jsonb) from jsonb_each(excluded.candidate) where value is distinct from old_public->key);
    -- Keep the approved public identity visible until its replacement passes.
    new:=jsonb_populate_record(new,old_public);
   end if;
  end if;
 end if;
 return new;
end $$;
revoke all on function public.ugc_content_guard() from public,anon,authenticated;

-- Exact 004 interaction_note_write_guard and its privileges (trigger untouched).
create or replace function public.interaction_note_write_guard() returns trigger
language plpgsql security definer set search_path=pg_catalog,public,pg_temp as $$
begin
  if public.admin_console_maintenance() then return new; end if;
  if not public.social_active() or new.user_id is distinct from auth.uid() then
    raise exception 'Active note owner required' using errcode='42501';
  end if;
  new.text:=regexp_replace(new.text,'^[[:space:]]+|[[:space:]]+$','','g');
  -- Flutter's 100-character composer counts graphemes; PostgreSQL counts code
  -- points. Keep a bounded storage limit without rejecting combined emoji.
  if new.text is null or char_length(new.text) not between 1 and 1000 then
    raise exception 'Note text is empty or too long' using errcode='22023';
  end if;
  new.created_at:=now();
  new.expires_at:=now()+interval '24 hours';
  return new;
end $$;
revoke all on function public.interaction_note_write_guard() from public,anon,authenticated;

-- Exact 009 create_comment_notification and its privileges (trigger untouched).
create or replace function public.create_comment_notification() returns trigger
language plpgsql security definer set search_path=pg_catalog,public,pg_temp as $$
declare target uuid; name text; parent uuid;
begin
 if new.moderation_status<>'approved' or (tg_op='UPDATE' and old.moderation_status='approved') then return new; end if;
 parent:=nullif(to_jsonb(new)->>'parent_id','')::uuid;
 select username into name from public.profiles where id=new.user_id;
 if parent is not null then select user_id into target from public.comments where id=parent;
 else select user_id into target from public.posts where id=new.post_id; end if;
 if target is null or target=new.user_id then return new; end if;
 insert into public.notifications(user_id,actor_id,actor_name,type,message,post_id)
 values(target,new.user_id,name,'comment',coalesce(name,'Хэн нэгэн')||' таны постод сэтгэгдэл бичлээ',new.post_id);
 return new;
end $$;
revoke all on function public.create_comment_notification() from public,anon,authenticated;

-- Exact 009 admin_console_review_queue and its privileges.
create or replace function public.admin_console_review_queue(p_kind text default 'all',p_status text default 'pending',p_offset integer default 0,p_limit integer default 30) returns jsonb
language plpgsql stable security definer set search_path=pg_catalog,public,pg_temp as $$
declare r record; rows jsonb:='[]'::jsonb; result jsonb;
begin
 perform public.admin_console_require_admin();perform public.admin_console_validate_page(p_offset,p_limit);
 if p_kind is null or p_kind not in ('all','post','story','comment','event','review','profile','note','collection','venue') or p_status is null or p_status not in ('pending','approved','rejected') then raise exception 'Invalid review filter' using errcode='22023'; end if;
 for r in select * from (values('posts','user_id','post'),('stories','user_id','story'),('comments','user_id','comment'),('events','organizer_id','event'),('venue_reviews','user_id','review'),('profiles','id','profile'),('notes','user_id','note'),('place_collections','user_id','collection'),('venues','owner_id','venue')) t(tbl,owner_col,kind) loop
  if p_kind<>'all' and p_kind<>r.kind then continue; end if;
  execute format('select coalesce(jsonb_agg(jsonb_build_object(''id'',t.id,''kind'',%L,''author_id'',t.%I,''content'',coalesce(d.candidate,public.ugc_public_fields(%L,to_jsonb(t))),''review_version'',t.moderation_version,''status'',t.moderation_status,''created_at'',to_jsonb(t)->>''created_at'',''submitted_at'',t.moderation_submitted_at)),''[]''::jsonb) from (select * from public.%I where moderation_status=$1 and (%L<>''collection'' or coalesce((to_jsonb(%I)->>''is_public'')::boolean,false)) order by moderation_submitted_at desc,id desc limit $2) t left join admin_private.ugc_profile_drafts d on %L=''profile'' and d.profile_id=t.id',r.kind,r.owner_col,r.tbl,r.tbl,r.kind,r.tbl,r.kind)
   into result using p_status,p_offset+p_limit+1;
  rows:=rows||result;
 end loop;
 with page as(select value item from jsonb_array_elements(rows) order by value->>'submitted_at' desc nulls last,value->>'kind',value->>'id' desc offset p_offset limit p_limit+1),numbered as(select item,row_number() over(order by item->>'submitted_at' desc nulls last,item->>'kind',item->>'id' desc) n from page)
 select jsonb_build_object('items',coalesce(jsonb_agg(item order by n) filter(where n<=p_limit),'[]'::jsonb),'has_more',count(*)>p_limit) into result from numbered;
 return result;
end $$;
revoke all on function public.admin_console_review_queue(text,text,integer,integer) from public,anon;
grant execute on function public.admin_console_review_queue(text,text,integer,integer) to authenticated;

-- Policies before the helper they call; restored bodies no longer use the new state.
do $$ declare t text; begin foreach t in array array['posts','stories','comments','notes','venue_reviews','place_collections'] loop execute format('drop policy if exists ugc_reporter_hidden_read on public.%I',t); end loop; end $$;
drop function if exists public.ugc_report_threshold();
drop function if exists public.ugc_viewer_reported_ids(text);
drop function if exists public.ugc_screen_text(text,jsonb,jsonb);
drop function if exists public.ugc_normalize_text(text);
drop function if exists public.ugc_strip_marks(text);
drop function if exists public.ugc_fold_case(text);
drop index if exists public.ugc_reports_reporter_target;
drop index if exists public.ugc_reports_target_pending;
drop table if exists admin_private.ugc_hold_context,admin_private.ugc_report_holds,admin_private.ugc_blocked_terms,admin_private.ugc_publish_config;
notify pgrst,'reload schema';
commit;
