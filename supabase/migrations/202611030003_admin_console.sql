-- Admin console: server authorization, atomic moderation, append-only audit.
-- Apply after social discovery / featured events / account deletion boundaries.
-- No users or content are changed by installing this migration. Staging first.
begin;

do $$ begin
  if not exists(select 1 from pg_catalog.pg_trigger t join pg_catalog.pg_proc p on p.oid=t.tgfoid
    where t.tgrelid='public.profiles'::regclass and not t.tgisinternal and t.tgenabled in ('O','A')
      and p.pronamespace='public'::regnamespace and p.proname='protect_profile_flags' and (t.tgtype::integer & 23)=23) then
    raise exception 'Install the active protect_profile_flags INSERT/UPDATE trigger first';
  end if;
  -- Moderation deletion must never revive the old arbitrary-URL Storage eraser.
  if not exists(select 1 from pg_catalog.pg_policy where polrelid='public.profiles'::regclass
      and polname='account_profile_delete_guard' and not polpermissive and polcmd='d'
      and pg_get_expr(polqual,polrelid)='false'
      and polroles @> array[(select oid from pg_roles where rolname='anon'),(select oid from pg_roles where rolname='authenticated')])
    or has_table_privilege('anon','public.profiles','DELETE,TRUNCATE')
    or has_table_privilege('authenticated','public.profiles','DELETE,TRUNCATE')
    or exists(select 1 from pg_catalog.pg_trigger where tgrelid='public.posts'::regclass and tgname='trg_cleanup_post_media')
    or not exists(select 1 from pg_catalog.pg_proc where oid=to_regprocedure('public.cleanup_post_media()') and not prosecdef
      and lower(regexp_replace(prosrc,'[[:space:]]','','g'))='beginreturnold;end;') then
    raise exception 'Apply and verify 202611030001_account_deletion_boundaries.sql before admin moderation';
  end if;
end $$;

create schema if not exists admin_private;
revoke all on schema admin_private from public, anon, authenticated;

create table if not exists admin_private.action_context (
  transaction_id bigint primary key,
  actor_id uuid not null,
  action text not null,
  target_id uuid not null,
  report_id uuid,
  reason text not null
);
revoke all on admin_private.action_context from public, anon, authenticated;

create table if not exists public.admin_audit_log (
  id uuid primary key default gen_random_uuid(),
  -- Deliberately no cascading FKs: deleting a target or actor cannot erase audit.
  actor_id uuid,
  actor_username text,
  action text not null,
  target_type text not null,
  target_id text not null,
  reason text not null check (char_length(btrim(reason)) between 3 and 1000),
  created_at timestamptz not null default clock_timestamp()
);
create index if not exists admin_audit_log_created on public.admin_audit_log(created_at desc,id desc);
alter table public.admin_audit_log enable row level security;
revoke all on public.admin_audit_log from public, anon, authenticated;

create or replace function public.admin_console_immutable_audit() returns trigger
language plpgsql set search_path=pg_catalog,public,pg_temp as $$
begin
  raise exception 'Admin audit records are append-only' using errcode='42501';
end $$;
drop trigger if exists admin_audit_immutable on public.admin_audit_log;
create trigger admin_audit_immutable before update or delete or truncate on public.admin_audit_log
  for each statement execute function public.admin_console_immutable_audit();

create or replace function public.admin_console_maintenance() returns boolean
language sql stable set search_path=pg_catalog,public,pg_temp as $$
  select current_setting('role',true)='service_role'
    or (auth.uid() is null and coalesce(current_setting('role',true),'none') not in ('anon','authenticated')
      and session_user not in ('anon','authenticated'));
$$;

-- Tighten legacy policies that still use this helper. Ownership rules remain.
create or replace function public.is_admin() returns boolean
language sql stable security definer set search_path=pg_catalog,public,pg_temp as $$
  select exists(select 1 from public.profiles where id=auth.uid() and is_admin is true and is_banned is not true);
$$;

create or replace function public.admin_console_require_admin() returns uuid
language plpgsql stable security definer set search_path=pg_catalog,public,pg_temp as $$
begin
  if auth.uid() is null or not public.is_admin() then
    raise exception 'Active administrator required' using errcode='42501';
  end if;
  return auth.uid();
end $$;

create or replace function public.admin_console_validate_page(p_offset integer,p_limit integer,p_search text default '') returns void
language plpgsql immutable set search_path=pg_catalog,public,pg_temp as $$
begin
  if p_offset is null or p_offset not between 0 and 100000 or p_limit is null or p_limit not between 1 and 100
     or p_search is null or char_length(p_search)>100 then
    raise exception 'Invalid pagination or search' using errcode='22023';
  end if;
end $$;

create or replace function public.protect_profile_flags() returns trigger
language plpgsql security definer set search_path=pg_catalog,public,pg_temp as $$
declare c admin_private.action_context%rowtype;
begin
  if public.admin_console_maintenance() then return new; end if;
  if tg_op='UPDATE' and new.id is distinct from old.id then
    raise exception 'Profile identity cannot be reassigned' using errcode='42501';
  end if;
  if not public.is_admin() then
    if tg_op='INSERT' then new.is_admin:=false; new.is_banned:=false; new.is_verified:=false;
    else new.is_admin:=old.is_admin; new.is_banned:=old.is_banned; new.is_verified:=old.is_verified; end if;
    return new;
  end if;
  if tg_op='INSERT' then
    if coalesce(new.is_admin,false) or coalesce(new.is_banned,false) or coalesce(new.is_verified,false) then
      raise exception 'Profile flags require a server moderation action' using errcode='42501';
    end if;
    return new;
  end if;
  if new.is_admin is not distinct from old.is_admin and new.is_banned is not distinct from old.is_banned
     and new.is_verified is not distinct from old.is_verified then return new; end if;
  select * into c from admin_private.action_context where transaction_id=txid_current() and actor_id=auth.uid() and target_id=old.id;
  if not found or new.is_admin is distinct from old.is_admin
     or not ((c.action in ('ban_user','unban_user') and new.is_verified is not distinct from old.is_verified
               and new.is_banned=(c.action='ban_user'))
          or (c.action in ('verify_user','unverify_user') and new.is_banned is not distinct from old.is_banned
               and new.is_verified=(c.action='verify_user'))) then
    raise exception 'Profile flags require a server moderation action' using errcode='42501';
  end if;
  return new;
end $$;

create or replace function public.admin_console_report_guard() returns trigger
language plpgsql security definer set search_path=pg_catalog,public,pg_temp as $$
declare c admin_private.action_context%rowtype;
begin
  if public.admin_console_maintenance() then
    if tg_op='DELETE' then return old; else return new; end if;
  end if;
  if tg_op='INSERT' then
    if not public.social_active() or new.reporter_id is distinct from auth.uid() then
      raise exception 'Active reporter required' using errcode='42501';
    end if;
    if new.status is distinct from 'pending' or new.target_type is null
       or new.target_type not in ('post','comment','user','venue') or new.target_id is null
       or new.reason is null or new.reason not in ('spam','harassment','nudity','violence','hate','other')
       or char_length(coalesce(new.details,''))>2000 then
      raise exception 'Invalid report' using errcode='22023';
    end if;
    -- Serialize one reporter so concurrent submissions cannot evade the quota.
    perform 1 from public.profiles where id=auth.uid() for update;
    if (select count(*) from public.reports where reporter_id=auth.uid() and created_at>clock_timestamp()-interval '1 hour')>=20 then
      raise exception 'Too many reports; try again later' using errcode='54000';
    end if;
    if exists(select 1 from public.reports where reporter_id=auth.uid() and target_type=new.target_type and target_id=new.target_id and status='pending') then
      raise exception 'This target already has a pending report' using errcode='40001';
    end if;
    if not (case new.target_type
      when 'user' then exists(select 1 from public.profiles where id=new.target_id)
      when 'post' then exists(select 1 from public.posts where id=new.target_id)
      when 'comment' then exists(select 1 from public.comments where id=new.target_id)
      when 'venue' then exists(select 1 from public.venues where id=new.target_id)
      else false end) then raise exception 'Report target no longer exists' using errcode='P0002'; end if;
    new.created_at:=clock_timestamp();
    new.details:=nullif(btrim(new.details),'');
    return new;
  end if;
  if tg_op='DELETE' then raise exception 'Reports cannot be deleted by clients' using errcode='42501'; end if;
  select * into c from admin_private.action_context where transaction_id=txid_current() and actor_id=auth.uid() and report_id=old.id;
  if not found or not public.is_admin() or (to_jsonb(new)-'status') is distinct from (to_jsonb(old)-'status')
     or not ((old.status='pending' and new.status in ('resolved','reviewed') and c.action<>'reopen_report')
          or (old.status in ('resolved','reviewed') and new.status='pending' and c.action='reopen_report')) then
    raise exception 'Report transitions require a server moderation action' using errcode='42501';
  end if;
  return new;
end $$;
drop trigger if exists admin_console_report_guard on public.reports;
create trigger admin_console_report_guard before insert or update or delete on public.reports
  for each row execute function public.admin_console_report_guard();
create index if not exists admin_reports_reporter_time on public.reports(reporter_id,created_at desc);
create index if not exists admin_reports_reporter_pending on public.reports(reporter_id,target_type,target_id) where status='pending';
revoke update,delete,truncate on public.reports from public,anon,authenticated;
drop policy if exists admin_console_reports_read on public.reports;
create policy admin_console_reports_read on public.reports as restrictive for select to anon,authenticated
  using(public.social_active() and (reporter_id=auth.uid() or public.is_admin()));
drop policy if exists admin_console_reports_insert on public.reports;
create policy admin_console_reports_insert on public.reports as restrictive for insert to authenticated
  with check(public.social_active() and reporter_id=auth.uid() and status='pending');

-- Restrictive gates compose with existing owner/admin policies, including old
-- policies whose inline administrator checks did not consider bans.
do $$ declare t text; begin
  foreach t in array array['venues','events'] loop
    execute format('drop policy if exists admin_console_active_insert on public.%I',t);
    execute format('create policy admin_console_active_insert on public.%I as restrictive for insert to authenticated with check(public.social_active())',t);
    execute format('drop policy if exists admin_console_active_update on public.%I',t);
    execute format('create policy admin_console_active_update on public.%I as restrictive for update to authenticated using(public.social_active()) with check(public.social_active())',t);
    execute format('drop policy if exists admin_console_active_delete on public.%I',t);
    execute format('create policy admin_console_active_delete on public.%I as restrictive for delete to authenticated using(public.social_active())',t);
  end loop;
end $$;

-- Only an attached post can use the moderation-media exception. This does not
-- authorize guessed/unattached objects, private stories, or private messages.
create or replace function public.social_media_readable(p_bucket text,p_name text) returns boolean
language sql stable security definer set search_path=pg_catalog,public,pg_temp as $$
  select (split_part(p_name,'/',1)=auth.uid()::text and public.social_active()) or
    (p_bucket='posts' and exists(select 1 from public.posts p where p.user_id::text=split_part(p_name,'/',1)
      and (public.can_view_author(p.user_id) or public.social_admin())
      and (split_part(p.media_url,'/storage/v1/object/public/posts/',2)=p_name or exists(select 1 from unnest(p.media_urls) u where split_part(u,'/storage/v1/object/public/posts/',2)=p_name)))) or
    (p_bucket='posts' and exists(select 1 from public.events e where e.organizer_id::text=split_part(p_name,'/',1) and split_part(e.cover_url,'/storage/v1/object/public/posts/',2)=p_name)) or
    (p_bucket='stories' and exists(select 1 from public.stories s where s.user_id::text=split_part(p_name,'/',1) and s.expires_at>now() and public.can_view_author(s.user_id)
      and split_part(s.media_url,'/storage/v1/object/public/stories/',2)=p_name));
$$;
revoke all on function public.social_media_readable(text,text) from public;
grant execute on function public.social_media_readable(text,text) to anon,authenticated;

create or replace function public.admin_console_content_delete_guard() returns trigger
language plpgsql security definer set search_path=pg_catalog,public,pg_temp as $$
declare c admin_private.action_context%rowtype;
begin
  if public.admin_console_maintenance() then return old; end if;
  -- A post's FK cascade must remove all its comments, including other authors'.
  if tg_table_name='comments' then
    if pg_trigger_depth()>1 and not exists(select 1 from public.posts where id=old.post_id) then return old; end if;
    -- Reply cascades can remove another author's reply while the post remains.
    if pg_trigger_depth()>1 and nullif(to_jsonb(old)->>'parent_id','') is not null
       and not exists(select 1 from public.comments where id=(to_jsonb(old)->>'parent_id')::uuid) then return old; end if;
  end if;
  if old.user_id=auth.uid() and public.social_active() then return old; end if;
  select * into c from admin_private.action_context where transaction_id=txid_current() and actor_id=auth.uid();
  if public.is_admin() and ((c.action='delete_post' and tg_table_name='posts' and c.target_id=old.id)
      or (c.action='delete_comment' and tg_table_name='comments' and c.target_id=old.id)) then return old; end if;
  raise exception 'Content moderation requires a server action' using errcode='42501';
end $$;
drop trigger if exists admin_console_delete_guard on public.posts;
create trigger admin_console_delete_guard before delete on public.posts for each row execute function public.admin_console_content_delete_guard();
drop trigger if exists admin_console_delete_guard on public.comments;
create trigger admin_console_delete_guard before delete on public.comments for each row execute function public.admin_console_content_delete_guard();

-- Existing venue/event/featured/pilot controls continue to work. Audit is
-- attached to the actual row change, so a failed write cannot leave a receipt.
-- Context is a private transaction row, never an attacker-writable GUC token.
create or replace function public.admin_console_audit_change() returns trigger
language plpgsql security definer set search_path=pg_catalog,public,pg_temp as $$
declare v_old jsonb; v_new jsonb; v_row jsonb; v_reason text; v_name text;
begin
  if auth.uid() is null or public.admin_console_maintenance() or not public.is_admin() then
    if tg_op='DELETE' then return old; else return new; end if;
  end if;
  if tg_op<>'INSERT' then v_old:=to_jsonb(old); end if;
  if tg_op<>'DELETE' then v_new:=to_jsonb(new); end if;
  -- Counter maintenance is not an editorial/moderation change.
  if tg_op='UPDATE' and (v_old-array['likes_count','comments_count','checkin_count','attendee_count','updated_at'])
      is not distinct from (v_new-array['likes_count','comments_count','checkin_count','attendee_count','updated_at']) then return new; end if;
  -- The moderation RPC records one audit receipt, including its FK cascades.
  if exists(select 1 from admin_private.action_context where transaction_id=txid_current() and actor_id=auth.uid()) then
    if tg_op='DELETE' then return old; else return new; end if;
  end if;
  v_row:=coalesce(v_new,v_old);
  v_reason:=nullif(regexp_replace(current_setting('app.admin_reason',true),'^[[:space:]]+|[[:space:]]+$','','g'),'');
  if v_reason is null then v_reason:='Existing admin control: '||lower(tg_op)||' '||tg_argv[0]; end if;
  if char_length(v_reason) not between 3 and 1000 then raise exception 'Invalid audit reason' using errcode='22023'; end if;
  select username into v_name from public.profiles where id=auth.uid();
  insert into public.admin_audit_log(actor_id,actor_username,action,target_type,target_id,reason)
    values(auth.uid(),v_name,lower(tg_op)||'_'||tg_argv[0],tg_argv[0],v_row->>tg_argv[1],v_reason);
  if tg_op='DELETE' then return old; else return new; end if;
end $$;
do $$ declare r record; begin
  for r in select * from (values
    ('venues','venue','id'),('events','event','id'),('event_features','event_feature','event_id'),
    ('pilot_creators','pilot_creator','user_id'),('pilot_participants','pilot_participant','user_id'),
    ('pilot_content','pilot_content','post_id'),('pilot_venues','pilot_venue','venue_ref'),
    ('venue_catalog','venue_catalog','ref'),('posts','post','id'),('comments','comment','id')
  ) as t(table_name,target_type,id_column) loop
    if to_regclass('public.'||r.table_name) is not null then
      execute format('drop trigger if exists admin_console_audit_change on public.%I',r.table_name);
      execute format('create trigger admin_console_audit_change after insert or update or delete on public.%I for each row execute function public.admin_console_audit_change(%L,%L)',r.table_name,r.target_type,r.id_column);
    end if;
  end loop;
end $$;

-- The existing place-review form still returns void, but only after one real
-- catalog update. A removed place or a suppressing trigger must not report a
-- saved review or remove its pilot selection.
create or replace function public.review_venue(p_ref text,p_details jsonb) returns void
language plpgsql security definer set search_path=pg_catalog,public,pg_temp as $$
declare v_admin boolean; v_catalog public.venue_catalog%rowtype; v_updated text;
begin
  select coalesce(is_admin,false) into v_admin from public.profiles
    where id=auth.uid() and is_banned is not true for share;
  if not found then raise exception 'Owner or admin only' using errcode='42501'; end if;
  select * into v_catalog from public.venue_catalog where ref=p_ref for update;
  if not found then raise exception 'Place no longer exists' using errcode='P0002'; end if;
  if not v_admin then
    perform 1 from public.venues where id=v_catalog.venue_id and owner_id=auth.uid() for share;
    if not found then raise exception 'Owner or admin only' using errcode='42501'; end if;
  end if;
  if jsonb_typeof(p_details) is distinct from 'object' or length(p_details::text)>10000 then
    raise exception 'Invalid details' using errcode='22023'; end if;
  if exists(select 1 from jsonb_each_text(p_details) where key in ('cover_url','menu_url') and value<>'' and value !~ '^https://') then
    raise exception 'HTTPS links required' using errcode='22023'; end if;
  update public.venue_catalog set address=nullif(trim(p_details->>'address'),''),hours=nullif(trim(p_details->>'hours'),''),
    cover_url=nullif(trim(p_details->>'cover_url'),''),menu_url=nullif(trim(p_details->>'menu_url'),''),
    price_min=nullif(p_details->>'price_min','')::integer,price_max=nullif(p_details->>'price_max','')::integer,
    vibes=array(select jsonb_array_elements_text(coalesce(p_details->'vibes','[]'::jsonb))),reviewed_at=null,reviewed_by=null
    where ref=p_ref returning ref into v_updated;
  if v_updated is distinct from p_ref then raise exception 'Place update was not confirmed' using errcode='P0002'; end if;
  delete from public.pilot_venues where venue_ref=p_ref;
end $$;
revoke all on function public.review_venue(text,jsonb) from public,anon;
grant execute on function public.review_venue(text,jsonb) to authenticated;

create or replace function public.admin_console_summary() returns jsonb
language plpgsql stable security definer set search_path=pg_catalog,public,pg_temp as $$
declare v_actor uuid:=public.admin_console_require_admin();
begin
  return jsonb_build_object('actor_id',v_actor,'users',(select count(*) from public.profiles),
    'posts',(select count(*) from public.posts),'comments',(select count(*) from public.comments),
    'venues',(select count(*) from public.venues),'events',(select count(*) from public.events),
    'pending_reports',(select count(*) from public.reports where status='pending'),
    'banned_users',(select count(*) from public.profiles where is_banned is true));
end $$;

create or replace function public.admin_console_users(p_search text default '',p_offset integer default 0,p_limit integer default 30) returns jsonb
language plpgsql stable security definer set search_path=pg_catalog,public,pg_temp as $$
declare v_result jsonb;
begin
  perform public.admin_console_require_admin();
  perform public.admin_console_validate_page(p_offset,p_limit,p_search);
  with page as (
    select p.id,p.username,p.full_name,p.avatar_url,coalesce(p.is_admin,false) as is_admin,
      coalesce(p.is_banned,false) as is_banned,coalesce(p.is_verified,false) as is_verified,p.created_at
    from public.profiles p
    where strpos(lower(concat_ws(' ',p.username,p.full_name,p.id::text)),lower(btrim(p_search)))>0
    order by p.created_at desc nulls last,p.id desc offset p_offset limit p_limit+1
  ), numbered as (select *,row_number() over(order by created_at desc nulls last,id desc) n from page)
  select jsonb_build_object('items',coalesce(jsonb_agg(to_jsonb(numbered)-'n' order by n) filter(where n<=p_limit),'[]'::jsonb),
    'has_more',count(*)>p_limit) into v_result from numbered;
  return v_result;
end $$;

create or replace function public.admin_console_content(p_kind text,p_search text default '',p_offset integer default 0,p_limit integer default 30) returns jsonb
language plpgsql stable security definer set search_path=pg_catalog,public,pg_temp as $$
declare v_result jsonb;
begin
  perform public.admin_console_require_admin();
  perform public.admin_console_validate_page(p_offset,p_limit,p_search);
  if p_kind is null or p_kind not in ('post','comment') then raise exception 'Invalid content kind' using errcode='22023'; end if;
  with content as (
    select p.id,p.user_id author_id,u.username,p.caption body,p.media_url,p.created_at from public.posts p left join public.profiles u on u.id=p.user_id where p_kind='post'
    union all
    select c.id,c.user_id,u.username,c.body,null::text,c.created_at from public.comments c left join public.profiles u on u.id=c.user_id where p_kind='comment'
  ), page as (
    select * from content where strpos(lower(concat_ws(' ',body,username,id::text)),lower(btrim(p_search)))>0
    order by created_at desc nulls last,id desc offset p_offset limit p_limit+1
  ), numbered as (select *,row_number() over(order by created_at desc nulls last,id desc) n from page)
  select jsonb_build_object('items',coalesce(jsonb_agg(to_jsonb(numbered)-'n' order by n) filter(where n<=p_limit),'[]'::jsonb),
    'has_more',count(*)>p_limit) into v_result from numbered;
  return v_result;
end $$;

create or replace function public.admin_console_reports(p_status text default 'pending',p_offset integer default 0,p_limit integer default 30) returns jsonb
language plpgsql stable security definer set search_path=pg_catalog,public,pg_temp as $$
declare v_result jsonb;
begin
  perform public.admin_console_require_admin();
  perform public.admin_console_validate_page(p_offset,p_limit);
  if p_status is null or p_status not in ('pending','reviewed','resolved','all') then raise exception 'Invalid report status' using errcode='22023'; end if;
  with page as (
    select r.* from public.reports r where p_status='all' or r.status=p_status
    order by r.created_at desc nulls last,r.id desc offset p_offset limit p_limit+1
  ), enriched as (
    select r.id,r.reporter_id,rp.username reporter_username,r.target_type,r.target_id,
      case r.target_type when 'user' then u.id when 'post' then p.user_id when 'comment' then c.user_id when 'venue' then v.owner_id end target_author_id,
      left(case r.target_type when 'user' then concat_ws(' · ',u.username,u.full_name) when 'post' then p.caption when 'comment' then c.body when 'venue' then v.name end,500) target_excerpt,
      r.reason,r.details,r.status,r.created_at,row_number() over(order by r.created_at desc nulls last,r.id desc) n
    from page r left join public.profiles rp on rp.id=r.reporter_id
    left join public.profiles u on r.target_type='user' and u.id=r.target_id
    left join public.posts p on r.target_type='post' and p.id=r.target_id
    left join public.comments c on r.target_type='comment' and c.id=r.target_id
    left join public.venues v on r.target_type='venue' and v.id=r.target_id
  ) select jsonb_build_object('items',coalesce(jsonb_agg(to_jsonb(enriched)-'n' order by n) filter(where n<=p_limit),'[]'::jsonb),
    'has_more',count(*)>p_limit) into v_result from enriched;
  return v_result;
end $$;

create or replace function public.admin_console_audit(p_offset integer default 0,p_limit integer default 30) returns jsonb
language plpgsql stable security definer set search_path=pg_catalog,public,pg_temp as $$
declare v_result jsonb;
begin
  perform public.admin_console_require_admin();
  perform public.admin_console_validate_page(p_offset,p_limit);
  with page as (select id,actor_id,actor_username,action,target_type,target_id,reason,created_at
    from public.admin_audit_log order by created_at desc,id desc offset p_offset limit p_limit+1),
  numbered as (select *,row_number() over(order by created_at desc,id desc) n from page)
  select jsonb_build_object('items',coalesce(jsonb_agg(to_jsonb(numbered)-'n' order by n) filter(where n<=p_limit),'[]'::jsonb),
    'has_more',count(*)>p_limit) into v_result from numbered;
  return v_result;
end $$;

create or replace function public.admin_console_action(p_action text,p_target_id uuid,p_reason text,p_report_id uuid default null) returns jsonb
language plpgsql security definer set search_path=pg_catalog,public,pg_temp as $$
declare
  v_actor uuid:=auth.uid(); v_name text; v_reason text:=regexp_replace(p_reason,'^[[:space:]]+|[[:space:]]+$','','g'); v_kind text;
  v_report public.reports%rowtype; v_profile public.profiles%rowtype;
  v_report_id uuid:=p_report_id; v_author uuid; v_report_author uuid; v_status text;
  v_audit uuid; v_created timestamptz; v_changed uuid; v_confirmed boolean; v_expected_status text;
begin
  -- The share lock keeps a demotion/ban from committing midway through a write.
  select username into v_name from public.profiles where id=v_actor and is_admin is true and is_banned is not true for share;
  if not found then raise exception 'Active administrator required' using errcode='42501'; end if;
  if p_target_id is null or v_reason is null or char_length(v_reason) not between 3 and 1000
     or p_action is null or p_action not in ('ban_user','unban_user','verify_user','unverify_user','delete_post','delete_comment','resolve_report','dismiss_report','reopen_report') then
    raise exception 'Invalid moderation action or reason' using errcode='22023';
  end if;
  v_kind:=case when p_action in ('ban_user','unban_user','verify_user','unverify_user') then 'user'
    when p_action='delete_post' then 'post' when p_action='delete_comment' then 'comment' else 'report' end;
  if v_kind='report' then
    if p_report_id is not null and p_report_id<>p_target_id then raise exception 'Report does not match action' using errcode='22023'; end if;
    v_report_id:=p_target_id;
  end if;
  if v_report_id is not null then
    select * into v_report from public.reports where id=v_report_id for update;
    if not found then raise exception 'Report no longer exists' using errcode='P0002'; end if;
    if (p_action='reopen_report' and coalesce(v_report.status not in ('resolved','reviewed'),true))
       or (p_action<>'reopen_report' and v_report.status is distinct from 'pending') then
      raise exception 'Report state changed; refresh before acting' using errcode='40001';
    end if;
  end if;
  if v_kind='user' then
    select * into v_profile from public.profiles where id=p_target_id for update;
    if not found then raise exception 'User no longer exists' using errcode='P0002'; end if;
    if p_action='ban_user' and (p_target_id=v_actor or v_profile.is_admin is true) then
      raise exception 'Administrators and yourself cannot be banned' using errcode='42501';
    end if;
    if (p_action='ban_user' and coalesce(v_profile.is_banned,false)) or (p_action='unban_user' and not coalesce(v_profile.is_banned,false))
       or (p_action='verify_user' and coalesce(v_profile.is_verified,false)) or (p_action='unverify_user' and not coalesce(v_profile.is_verified,false)) then
      raise exception 'User state changed; refresh before acting' using errcode='40001';
    end if;
  elsif v_kind='post' then
    select user_id into v_author from public.posts where id=p_target_id for update;
    if not found then raise exception 'Post no longer exists' using errcode='P0002'; end if;
  elsif v_kind='comment' then
    select user_id into v_author from public.comments where id=p_target_id for update;
    if not found then raise exception 'Comment no longer exists' using errcode='P0002'; end if;
  end if;
  if v_report_id is not null and v_kind<>'report' then
    if v_kind='user' then
      if v_report.target_type='user' then select id into v_report_author from public.profiles where id=v_report.target_id;
      elsif v_report.target_type='post' then select user_id into v_report_author from public.posts where id=v_report.target_id for share;
      elsif v_report.target_type='comment' then select user_id into v_report_author from public.comments where id=v_report.target_id for share;
      elsif v_report.target_type='venue' then select owner_id into v_report_author from public.venues where id=v_report.target_id for share;
      end if;
      if v_report_author is distinct from p_target_id then raise exception 'Report target does not match user' using errcode='40001'; end if;
    elsif v_report.target_type is distinct from v_kind or v_report.target_id is distinct from p_target_id then
      raise exception 'Report target does not match content' using errcode='40001';
    end if;
  end if;
  insert into admin_private.action_context(transaction_id,actor_id,action,target_id,report_id,reason)
    values(txid_current(),v_actor,p_action,p_target_id,v_report_id,v_reason);
  if p_action in ('ban_user','unban_user') then
    update public.profiles set is_banned=(p_action='ban_user') where id=p_target_id returning id,is_banned=(p_action='ban_user') into v_changed,v_confirmed;
  elsif p_action in ('verify_user','unverify_user') then
    update public.profiles set is_verified=(p_action='verify_user') where id=p_target_id returning id,is_verified=(p_action='verify_user') into v_changed,v_confirmed;
  elsif p_action='delete_post' then delete from public.posts where id=p_target_id returning id,true into v_changed,v_confirmed;
  elsif p_action='delete_comment' then delete from public.comments where id=p_target_id returning id,true into v_changed,v_confirmed;
  end if;
  if v_kind<>'report' and (v_changed is distinct from p_target_id or v_confirmed is not true) then
    raise exception 'Target mutation was not confirmed' using errcode='40001';
  end if;
  if v_report_id is not null then
    v_expected_status:=case p_action when 'reopen_report' then 'pending' when 'dismiss_report' then 'reviewed' else 'resolved' end;
    update public.reports set status=v_expected_status where id=v_report_id returning status into v_status;
    if v_status is distinct from v_expected_status then raise exception 'Report mutation was not confirmed' using errcode='40001'; end if;
  end if;
  insert into public.admin_audit_log(actor_id,actor_username,action,target_type,target_id,reason)
    values(v_actor,v_name,p_action,v_kind,p_target_id::text,v_reason) returning id,created_at into v_audit,v_created;
  if v_audit is null then raise exception 'Audit receipt was not recorded' using errcode='40001'; end if;
  delete from admin_private.action_context where transaction_id=txid_current();
  return jsonb_build_object('audit_id',v_audit,'action',p_action,'target_type',v_kind,'target_id',p_target_id,
    'report_id',v_report_id,'report_status',v_status,'created_at',v_created);
end $$;

revoke all on function public.admin_console_immutable_audit(),public.admin_console_maintenance(),public.admin_console_require_admin(),
  public.admin_console_validate_page(integer,integer,text),public.protect_profile_flags(),public.admin_console_report_guard(),
  public.admin_console_content_delete_guard(),public.admin_console_audit_change() from public,anon,authenticated;
revoke all on function public.admin_console_summary(),public.admin_console_users(text,integer,integer),
  public.admin_console_reports(text,integer,integer),public.admin_console_content(text,text,integer,integer),
  public.admin_console_audit(integer,integer),public.admin_console_action(text,uuid,text,uuid) from public,anon;
grant execute on function public.admin_console_summary(),public.admin_console_users(text,integer,integer),
  public.admin_console_reports(text,integer,integer),public.admin_console_content(text,text,integer,integer),
  public.admin_console_audit(integer,integer),public.admin_console_action(text,uuid,text,uuid) to authenticated;
revoke all on function public.is_admin() from public;
grant execute on function public.is_admin() to anon,authenticated;
notify pgrst,'reload schema';
commit;
