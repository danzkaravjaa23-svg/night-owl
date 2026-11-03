-- Manual prepublication review. Existing published records are grandfathered;
-- new public UGC and content edits wait for an active moderator's decision.
-- This is a staged migration: requires coordinated pending-status/media UI.
begin;
set local lock_timeout='5s';
set local statement_timeout='60s';

do $$ begin
 if to_regprocedure('public.admin_console_require_admin()') is null or to_regprocedure('public.venue_map_activity()') is null then
  raise exception 'Install and verify admin console and map activity prerequisites';
 end if;
end $$;

-- Erasure-frozen accounts also lose moderation reads and media exceptions.
-- Preserve the tighter social_active() installed by migration 008.
create or replace function public.is_admin() returns boolean
language sql stable security definer set search_path=pg_catalog,public,pg_temp as $$
 select public.social_active() and exists(select 1 from public.profiles where id=auth.uid() and is_admin is true and is_banned is not true);
$$;
create or replace function public.social_admin() returns boolean
language sql stable security definer set search_path=pg_catalog,public,pg_temp as $$select public.is_admin()$$;

create table if not exists admin_private.ugc_action_context(
 transaction_id bigint primary key,actor_id uuid not null,kind text not null,target_id uuid not null,decision text not null
);
create table if not exists admin_private.ugc_profile_drafts(
 profile_id uuid primary key references public.profiles(id) on delete cascade,
 candidate jsonb not null
);
revoke all on admin_private.ugc_action_context,admin_private.ugc_profile_drafts from public,anon,authenticated;

do $$ declare t text; begin
 foreach t in array array['posts','stories','comments','events','venue_reviews','profiles','notes','place_collections','venues'] loop
  if to_regclass('public.'||t) is null then raise exception 'Missing UGC prerequisite: %',t; end if;
  execute format('alter table public.%I add column if not exists moderation_status text not null default ''approved'' check(moderation_status in (''pending'',''approved'',''rejected''))',t);
  execute format('alter table public.%I alter column moderation_status set default ''pending''',t);
  execute format('alter table public.%I add column if not exists moderation_version uuid not null default gen_random_uuid()',t);
  execute format('alter table public.%I add column if not exists moderation_submitted_at timestamptz not null default clock_timestamp()',t);
  execute format('create index if not exists %I on public.%I(moderation_status,moderation_submitted_at desc,id desc)', 'ugc_review_'||t,t);
 end loop;
end $$;
alter table public.profiles add column if not exists moderation_public_ready boolean not null default true;
alter table public.profiles alter column moderation_public_ready set default false;
alter table public.venue_catalog add column if not exists moderation_status text not null default 'approved' check(moderation_status in ('pending','approved','rejected'));

-- Only these user-facing fields enter the review queue. Credentials, contact
-- settings, flags, messages, counters, and private account metadata never do.
create or replace function public.ugc_public_fields(p_table text,p_row jsonb) returns jsonb
language sql immutable set search_path=pg_catalog,public,pg_temp as $$
 select coalesce(jsonb_object_agg(key,value),'{}'::jsonb) from jsonb_each(p_row)
 where key=any(case p_table
 when 'posts' then array['caption','media_url','media_urls','media_type','venue_id','venue_ref','venue_name']
 when 'stories' then array['caption','media_url','media_type','duration','venue_id','venue_ref','mentions','music_url','music_title','music_artist']
 when 'comments' then array['body']
 when 'events' then array['title','description','cover_url','venue_id','starts_at','ends_at','price','capacity']
 when 'venue_reviews' then array['rating','comment']
 when 'profiles' then array['username','full_name','bio','avatar_url','cover_url','interests']
 when 'notes' then array['text','venue_id']
 when 'place_collections' then array['title','name','description','cover_url','is_public']
 when 'venues' then array['name','venue_type','description','district','address','lat','lng','cover_url','photos','phone','website_url','open_time','close_time','opening_hours']
 else array[]::text[] end);
$$;
revoke all on function public.ugc_public_fields(text,jsonb) from public,anon,authenticated;

create or replace function public.ugc_content_guard() returns trigger
language plpgsql security definer set search_path=pg_catalog,public,pg_temp as $$
declare c admin_private.ugc_action_context%rowtype; candidate jsonb; old_public jsonb; changed boolean; media_value text; media_owner text;
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
  for media_value in select value #>> '{}' from jsonb_each(candidate) where key in ('media_url','avatar_url','cover_url','music_url')
   union all select v #>> '{}' from jsonb_each(candidate) e cross join lateral jsonb_array_elements(case when jsonb_typeof(e.value)='array' then e.value else '[]'::jsonb end) v where e.key in ('media_urls','photos') loop
   media_owner:=substring(media_value from '/storage/v1/object/public/(?:posts|stories|avatars|venues)/([^/]+)/');
   if media_owner is not null and media_owner is distinct from to_jsonb(new)->>tg_argv[0]
      and not (public.is_admin() and media_owner=auth.uid()::text) then
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

do $$ declare r record; owner_col text; begin
 for r in select * from (values('posts','user_id','post'),('stories','user_id','story'),('comments','user_id','comment'),('events','organizer_id','event'),
  ('venue_reviews','user_id','review'),('profiles','id','profile'),('notes','user_id','note'),('place_collections','user_id','collection'),('venues','owner_id','venue')) t(tbl,owner_col,kind) loop
  execute format('drop trigger if exists ugc_content_guard on public.%I',r.tbl);
  execute format('create trigger ugc_content_guard before insert or update on public.%I for each row execute function public.ugc_content_guard(%L,%L)',r.tbl,r.owner_col,r.kind);
  execute format('drop policy if exists ugc_approved_read on public.%I',r.tbl);
  execute format('create policy ugc_approved_read on public.%I as restrictive for select to anon,authenticated using(%s or %I=auth.uid())',r.tbl,
   case when r.tbl='profiles' then 'moderation_public_ready' else 'moderation_status=''approved''' end,r.owner_col);
 end loop;
end $$;
-- Catalog mirrors must not publish an owner-submitted venue ahead of approval.
create or replace function public.ugc_catalog_review_sync() returns trigger
language plpgsql security definer set search_path=pg_catalog,public,pg_temp as $$
begin
 update public.venue_catalog set moderation_status=new.moderation_status where ref=new.id::text;
 return new;
end $$;
revoke all on function public.ugc_catalog_review_sync() from public,anon,authenticated;
drop trigger if exists zz_ugc_catalog_review_sync on public.venues;
create trigger zz_ugc_catalog_review_sync after insert or update on public.venues for each row execute function public.ugc_catalog_review_sync();
drop policy if exists ugc_catalog_read on public.venue_catalog;
create policy ugc_catalog_read on public.venue_catalog as restrictive for select to anon,authenticated
 using(moderation_status='approved' or exists(select 1 from public.venues v where v.id::text=ref and v.owner_id=auth.uid()));

alter table public.reports add column if not exists target_author_id uuid;
alter table public.reports add column if not exists target_snapshot jsonb not null default '{}'::jsonb;

-- Buckets are private: pending media is readable only by its owner, or by a
-- moderator opening a specific submitted/reported piece of content.
update storage.buckets set public=false where id in ('posts','stories','avatars','venues');
create or replace function public.social_media_readable(p_bucket text,p_name text) returns boolean
language sql stable security definer set search_path=pg_catalog,public,pg_temp as $$
 select (split_part(p_name,'/',1)=auth.uid()::text and public.social_active()) or
 (p_bucket='posts' and exists(select 1 from public.posts p where p.user_id::text=split_part(p_name,'/',1)
  and ((p.moderation_status='approved' and public.can_view_author(p.user_id)) or public.social_admin())
  and (split_part(p.media_url,'/storage/v1/object/public/posts/',2)=p_name or exists(select 1 from unnest(p.media_urls) u where split_part(u,'/storage/v1/object/public/posts/',2)=p_name)))) or
 (p_bucket='posts' and exists(select 1 from public.events e where e.organizer_id::text=split_part(p_name,'/',1)
  and (e.moderation_status='approved' or public.social_admin()) and split_part(e.cover_url,'/storage/v1/object/public/posts/',2)=p_name)) or
 (p_bucket='stories' and exists(select 1 from public.stories s where s.user_id::text=split_part(p_name,'/',1)
  and ((s.moderation_status='approved' and s.expires_at>now() and public.can_view_author(s.user_id)) or (s.moderation_status='pending' and public.social_admin()))
  and split_part(s.media_url,'/storage/v1/object/public/stories/',2)=p_name)) or
 (p_bucket in ('posts','stories','avatars','venues') and exists(select 1 from public.stories s where s.user_id::text=split_part(p_name,'/',1)
  and ((s.moderation_status='approved' and s.expires_at>now() and public.can_view_author(s.user_id)) or (s.moderation_status='pending' and public.social_admin()))
  and split_part(to_jsonb(s)->>'music_url','/storage/v1/object/public/'||p_bucket||'/',2)=p_name)) or
 (p_bucket='avatars' and exists(select 1 from public.profiles p where p.id::text=split_part(p_name,'/',1)
  and p.moderation_public_ready and public.can_view_author(p.id)
  and (split_part(p.avatar_url,'/storage/v1/object/public/avatars/',2)=p_name or split_part(to_jsonb(p)->>'cover_url','/storage/v1/object/public/avatars/',2)=p_name))) or
 (p_bucket='avatars' and public.social_admin() and exists(select 1 from admin_private.ugc_profile_drafts d
  where d.profile_id::text=split_part(p_name,'/',1) and (split_part(d.candidate->>'avatar_url','/storage/v1/object/public/avatars/',2)=p_name or split_part(d.candidate->>'cover_url','/storage/v1/object/public/avatars/',2)=p_name))) or
 (p_bucket='avatars' and public.social_admin() and exists(select 1 from public.profiles p where p.id::text=split_part(p_name,'/',1) and p.moderation_status='pending'
  and (split_part(p.avatar_url,'/storage/v1/object/public/avatars/',2)=p_name or split_part(to_jsonb(p)->>'cover_url','/storage/v1/object/public/avatars/',2)=p_name))) or
 (p_bucket='venues' and exists(select 1 from public.venues v where (v.moderation_status='approved' or public.social_admin())
  and (split_part(v.cover_url,'/storage/v1/object/public/venues/',2)=p_name or exists(select 1 from jsonb_array_elements_text(case when jsonb_typeof(to_jsonb(v)->'photos')='array' then to_jsonb(v)->'photos' else '[]'::jsonb end) u where split_part(u,'/storage/v1/object/public/venues/',2)=p_name)))) or
 (p_bucket='venues' and exists(select 1 from public.venue_catalog v where v.moderation_status='approved' and split_part(v.cover_url,'/storage/v1/object/public/venues/',2)=p_name)) or
 (p_bucket in ('posts','stories','avatars','venues') and public.social_admin() and exists(select 1 from public.reports r where r.status='pending' and r.target_type in ('post','story','message','event','venue','user')
  and coalesce(r.target_snapshot->>'media_owner',r.target_author_id::text)=split_part(p_name,'/',1) and split_part(r.target_snapshot->>'media_url','/storage/v1/object/public/'||p_bucket||'/',2)=p_name));
$$;
revoke all on function public.social_media_readable(text,text) from public;
grant execute on function public.social_media_readable(text,text) to anon,authenticated;
-- Extend the existing restrictive Storage rule to all newly private buckets.
drop policy if exists social_media_read on storage.objects;
create policy social_media_read on storage.objects as restrictive for select to anon,authenticated
 using(bucket_id not in ('posts','stories','avatars','venues') or public.social_media_readable(bucket_id,name));


-- Derived counts never include a pending/rejected review or comment.
create or replace function public.ugc_recount_approved() returns trigger
language plpgsql security definer set search_path=pg_catalog,public,pg_temp as $$
declare target uuid;
begin
 if tg_table_name='comments' then
  target:=case when tg_op='DELETE' then old.post_id else new.post_id end;
  update public.posts set comments_count=(select count(*) from public.comments where post_id=target and moderation_status='approved') where id=target;
 else
  target:=case when tg_op='DELETE' then old.venue_id else new.venue_id end;
  update public.venues set rating=coalesce((select round(avg(rating)::numeric,1) from public.venue_reviews where venue_id=target and moderation_status='approved'),0),
   review_count=(select count(*) from public.venue_reviews where venue_id=target and moderation_status='approved') where id=target;
 end if;
 if tg_op='DELETE' then return old; else return new; end if;
end $$;
revoke all on function public.ugc_recount_approved() from public,anon,authenticated;
drop trigger if exists zz_ugc_approved_counts on public.comments;
create trigger zz_ugc_approved_counts after insert or update or delete on public.comments for each row execute function public.ugc_recount_approved();
drop trigger if exists zz_ugc_approved_counts on public.venue_reviews;
create trigger zz_ugc_approved_counts after insert or update or delete on public.venue_reviews for each row execute function public.ugc_recount_approved();
-- Known inherited counter triggers run first; the last trigger is authoritative.

-- The reviewed decision is one audit action, not an extra legacy edit receipt.
do $$ declare definition text; before_text text; after_text text; begin
 before_text:=$fragment$if exists(select 1 from admin_private.action_context where transaction_id=txid_current() and actor_id=auth.uid()) then$fragment$;
 after_text:=$fragment$if exists(select 1 from admin_private.action_context where transaction_id=txid_current() and actor_id=auth.uid()) or exists(select 1 from admin_private.ugc_action_context where transaction_id=txid_current() and actor_id=auth.uid()) then$fragment$;
 definition:=pg_get_functiondef('public.admin_console_audit_change()'::regprocedure);
 if strpos(definition,after_text)=0 then
  if strpos(definition,before_text)=0 then raise exception 'Review installed audit implementation before applying'; end if;
  execute replace(definition,before_text,after_text);
 end if;
end $$;

-- Do not announce a comment before it passes review. Notify once on approval.
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
do $$ begin
 if to_regclass('public.notifications') is not null then
  drop trigger if exists on_comment_notify on public.comments;
  create trigger on_comment_notify after insert or update of moderation_status on public.comments for each row execute function public.create_comment_notification();
 end if;
end $$;

-- A capture trigger is SECURITY INVOKER, so target reads use the reporter's
-- ordinary RLS. It replaces any client-supplied context with the selected row.
alter table public.reports add column if not exists target_author_id uuid;
alter table public.reports add column if not exists target_snapshot jsonb not null default '{}'::jsonb;
do $$ declare c record; begin
 for c in select conname from pg_constraint where conrelid='public.reports'::regclass and contype='c' and pg_get_constraintdef(oid) like '%target_type%' loop
  execute format('alter table public.reports drop constraint %I',c.conname);
 end loop;
end $$;
alter table public.reports add constraint reports_ugc_target_type check(target_type in ('post','comment','user','venue','story','message','group_message','event','review','note','collection'));

create or replace function public.ugc_report_capture() returns trigger
language plpgsql security invoker set search_path=pg_catalog,public,pg_temp as $$
declare tbl text; owner_col text; r jsonb; body text; media text; media_parts text[];
begin
 if current_setting('role',true)='service_role' or (auth.uid() is null and coalesce(current_setting('role',true),'none') not in ('anon','authenticated') and session_user not in ('anon','authenticated')) then return new; end if;
 tbl:=case new.target_type when 'post' then 'posts' when 'comment' then 'comments' when 'user' then 'profiles' when 'venue' then 'venues'
  when 'story' then 'stories' when 'message' then 'messages' when 'group_message' then 'group_messages' when 'event' then 'events' when 'review' then 'venue_reviews' when 'note' then 'notes' when 'collection' then 'place_collections' end;
 owner_col:=case new.target_type when 'user' then 'id' when 'venue' then 'owner_id' when 'event' then 'organizer_id' when 'message' then 'sender_id' when 'group_message' then 'sender_id' else 'user_id' end;
 if tbl is null then raise exception 'Invalid report type' using errcode='22023'; end if;
 execute format('select to_jsonb(t) from public.%I t where id=$1',tbl) into r using new.target_id;
 if r is null then raise exception 'Report target unavailable' using errcode='42501'; end if;
 new.target_author_id:=(r->>owner_col)::uuid;
 body:=left(coalesce(r->>'text',r->>'body',r->>'caption',r->>'comment',r->>'description',r->>'bio',r->>'title',r->>'name',r->>'username',''),2000);
 media:=case when new.target_type in ('post','story') then r->>'media_url' when new.target_type='message' then r->>'story_media_url'
  when new.target_type in ('event','venue','user') then coalesce(r->>'cover_url',r->>'avatar_url') else null end;
 media_parts:=regexp_match(coalesce(media,''),'/storage/v1/object/public/(posts|stories|avatars|venues)/([^/?#]+)/([^?#]+)$');
 if media_parts is not null and not public.social_media_readable(media_parts[1],media_parts[2]||'/'||media_parts[3]) then media:=null;media_parts:=null; end if;
 new.target_snapshot:=jsonb_build_object('body',body,'media_url',media,'media_owner',case when media_parts is not null then media_parts[2] else null end,
  'note_text',case when new.target_type='message' then left(r->>'note_text',300) else null end);
 return new;
end $$;
revoke all on function public.ugc_report_capture() from public,anon,authenticated;
drop trigger if exists ugc_report_capture on public.reports;
create trigger ugc_report_capture before insert on public.reports for each row execute function public.ugc_report_capture();

create or replace function public.admin_console_report_guard() returns trigger
language plpgsql security definer set search_path=pg_catalog,public,pg_temp as $$
declare c admin_private.action_context%rowtype;
begin
 if public.admin_console_maintenance() then if tg_op='DELETE' then return old; else return new; end if; end if;
 if tg_op='INSERT' then
  if not public.social_active() or new.reporter_id is distinct from auth.uid() then raise exception 'Active reporter required' using errcode='42501'; end if;
  if new.status is distinct from 'pending' or new.target_type not in ('post','comment','user','venue','story','message','group_message','event','review','note','collection') or new.target_id is null
   or new.reason is null or new.reason not in ('spam','harassment','nudity','violence','hate','other') or char_length(coalesce(new.details,''))>2000 then
   raise exception 'Invalid report' using errcode='22023'; end if;
  perform 1 from public.profiles where id=auth.uid() for update;
  if (select count(*) from public.reports where reporter_id=auth.uid() and created_at>clock_timestamp()-interval '1 hour')>=20 then raise exception 'Too many reports; try again later' using errcode='54000'; end if;
  if exists(select 1 from public.reports where reporter_id=auth.uid() and target_type=new.target_type and target_id=new.target_id and status='pending') then raise exception 'This target already has a pending report' using errcode='40001'; end if;
  new.created_at:=clock_timestamp();new.details:=nullif(btrim(new.details),'');return new;
 end if;
 if tg_op='DELETE' then raise exception 'Reports cannot be deleted by clients' using errcode='42501'; end if;
 select * into c from admin_private.action_context where transaction_id=txid_current() and actor_id=auth.uid() and report_id=old.id;
 if not found or not public.is_admin() or (to_jsonb(new)-'status') is distinct from (to_jsonb(old)-'status')
  or not ((old.status='pending' and new.status in ('resolved','reviewed') and c.action<>'reopen_report') or (old.status in ('resolved','reviewed') and new.status='pending' and c.action='reopen_report')) then
  raise exception 'Report transitions require a server moderation action' using errcode='42501'; end if;
 return new;
end $$;
create or replace function public.report_ugc(p_target_type text,p_target_id uuid,p_reason text,p_details text default null) returns uuid
language plpgsql security invoker set search_path=pg_catalog,public,pg_temp as $$
declare v_id uuid;
begin
 if not public.social_active() then raise exception 'Active reporter required' using errcode='42501'; end if;
 insert into public.reports(reporter_id,target_type,target_id,reason,details,status) values(auth.uid(),p_target_type,p_target_id,p_reason,p_details,'pending') returning id into v_id;
 return v_id;
end $$;
revoke all on function public.report_ugc(text,uuid,text,text) from public,anon;
grant execute on function public.report_ugc(text,uuid,text,text) to authenticated;

-- Reviewers receive reported snapshots only, never a private-message browser.
create or replace function public.admin_console_reports(p_status text default 'pending',p_offset integer default 0,p_limit integer default 30) returns jsonb
language plpgsql stable security definer set search_path=pg_catalog,public,pg_temp as $$
declare result jsonb;
begin
 perform public.admin_console_require_admin();perform public.admin_console_validate_page(p_offset,p_limit);
 if p_status is null or p_status not in ('pending','resolved','reviewed','all') then raise exception 'Invalid status' using errcode='22023'; end if;
 with page as(select r.*,p.username reporter_username,row_number() over(order by r.created_at desc,r.id desc) n from public.reports r left join public.profiles p on p.id=r.reporter_id
 where p_status='all' or r.status=p_status order by r.created_at desc,r.id desc offset p_offset limit p_limit+1)
 select jsonb_build_object('items',coalesce(jsonb_agg((to_jsonb(page)-array['n','target_snapshot'])||jsonb_build_object('target_excerpt',target_snapshot->>'body','target_media_url',target_snapshot->>'media_url') order by n) filter(where n<=p_offset+p_limit),'[]'::jsonb),'has_more',count(*)>p_limit) into result from page;
 return result;
end $$;


-- Preserve report-linked ban matching for newly supported selected targets.
do $$ declare definition text; before_text text; after_text text; begin
 before_text:=$fragment$elsif v_report.target_type='venue' then select owner_id into v_report_author from public.venues where id=v_report.target_id for share;
      end if;$fragment$;
 after_text:=$fragment$elsif v_report.target_type='venue' then select owner_id into v_report_author from public.venues where id=v_report.target_id for share;
      else v_report_author:=v_report.target_author_id;
      end if;$fragment$;
 definition:=pg_get_functiondef('public.admin_console_action(text,uuid,text,uuid)'::regprocedure);
 if strpos(definition,before_text)>0 then execute replace(definition,before_text,after_text);
 elsif strpos(definition,'else v_report_author:=v_report.target_author_id;')=0 then raise exception 'Review installed admin action implementation before applying'; end if;
end $$;

-- Map popularity counts only approved publications, even for their author.
do $$ declare name text; definition text; begin
 foreach name in array array['venue_story_activity_today','venue_map_activity'] loop
  definition:=pg_get_functiondef(to_regprocedure('public.'||name||'()'));
  if strpos(definition,$where$where (s.venue_ref$where$)>0 then
   definition:=replace(definition,$where$where (s.venue_ref$where$,$where$where s.moderation_status='approved' and (s.venue_ref$where$);
  end if;
  if strpos(definition,$where$where (p.venue_ref$where$)>0 then
   definition:=replace(definition,$where$where (p.venue_ref$where$,$where$where p.moderation_status='approved' and (p.venue_ref$where$);
  end if;
  execute definition;
 end loop;
end $$;

-- Remove reported private context when its reporter or subject is erased.
create or replace function public.ugc_erase_report_context() returns trigger
language plpgsql security definer set search_path=pg_catalog,public,pg_temp as $$
begin
 update public.reports set target_snapshot='{}'::jsonb,target_author_id=null,details=null where reporter_id=old.id or target_author_id=old.id or target_snapshot->>'media_owner'=old.id::text;
 return old;
end $$;
revoke all on function public.ugc_erase_report_context() from public,anon,authenticated;
drop trigger if exists ugc_erase_report_context on public.profiles;
create trigger ugc_erase_report_context before delete on public.profiles for each row execute function public.ugc_erase_report_context();


do $$ declare definition text; before_text text; after_text text; begin
 before_text:='select media_url into v_media from stories where id=p_story';
 after_text:='select media_url into v_media from stories where moderation_status=''approved'' and id=p_story';
 definition:=pg_get_functiondef('public.send_direct_message(uuid,text,text,uuid,text)'::regprocedure);
 if strpos(definition,before_text)>0 then execute replace(definition,before_text,after_text);
 elsif strpos(definition,after_text)=0 then raise exception 'Review installed direct-message attachment lookup before applying'; end if;
end $$;

-- Pending review queue contains only public content fields, not private DMs.
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

create or replace function public.admin_console_review(p_kind text,p_target_id uuid,p_version uuid,p_decision text,p_reason text) returns jsonb
language plpgsql security definer set search_path=pg_catalog,public,pg_temp as $$
declare actor uuid; username text; tbl text; rowdata jsonb; candidate jsonb; changed uuid; audit_id uuid; at_time timestamptz;
begin
 select p.id,p.username into actor,username from public.profiles p where p.id=auth.uid() and p.is_admin and not coalesce(p.is_banned,false) and public.social_active() for share;
 if actor is null then raise exception 'Active administrator required' using errcode='42501'; end if;
 tbl:=case p_kind when 'post' then 'posts' when 'story' then 'stories' when 'comment' then 'comments' when 'event' then 'events' when 'review' then 'venue_reviews' when 'profile' then 'profiles' when 'note' then 'notes' when 'collection' then 'place_collections' when 'venue' then 'venues' end;
 if tbl is null or p_target_id is null or p_version is null or p_decision not in ('approved','rejected') or p_reason is null or char_length(btrim(p_reason)) not between 3 and 1000 then raise exception 'Invalid review decision' using errcode='22023'; end if;
 execute format('select to_jsonb(t) from public.%I t where id=$1 for update',tbl) into rowdata using p_target_id;
 if rowdata is null then raise exception 'Content no longer exists' using errcode='P0002'; end if;
 if not (rowdata->>'moderation_status'='pending' or (p_decision='rejected' and rowdata->>'moderation_status'='approved')) or (rowdata->>'moderation_version')::uuid<>p_version then raise exception 'Content changed; refresh before reviewing' using errcode='40001'; end if;
 insert into admin_private.ugc_action_context values(txid_current(),actor,p_kind,p_target_id,p_decision);
 if p_kind='profile' then
  select d.candidate into candidate from admin_private.ugc_profile_drafts d where profile_id=p_target_id;
  if p_decision='approved' and candidate is not null then
   -- Only reviewed public fields are applied; identity/flags remain untouched.
   update public.profiles p set username=coalesce(candidate->>'username',p.username),full_name=candidate->>'full_name',bio=candidate->>'bio',avatar_url=candidate->>'avatar_url',
    cover_url=candidate->>'cover_url',interests=array(select jsonb_array_elements_text(case when jsonb_typeof(candidate->'interests')='array' then candidate->'interests' else '[]'::jsonb end)),moderation_status='approved',moderation_public_ready=true where id=p_target_id returning id into changed;
  else
   update public.profiles set moderation_status=p_decision,moderation_public_ready=case when p_decision='approved' then true when rowdata->>'moderation_status'='approved' then false else moderation_public_ready end where id=p_target_id returning id into changed;
  end if;
  delete from admin_private.ugc_profile_drafts where profile_id=p_target_id;
 else execute format('update public.%I set moderation_status=$1 where id=$2 returning id',tbl) into changed using p_decision,p_target_id; end if;
 if changed is distinct from p_target_id then raise exception 'Review mutation was not confirmed' using errcode='40001'; end if;
 insert into public.admin_audit_log(actor_id,actor_username,action,target_type,target_id,reason) values(actor,username,p_decision||'_content',p_kind,p_target_id::text,btrim(p_reason)) returning id,created_at into audit_id,at_time;
 delete from admin_private.ugc_action_context where transaction_id=txid_current();
 return jsonb_build_object('target_id',p_target_id,'target_type',p_kind,'status',p_decision,'review_version',p_version,'audit_id',audit_id,'created_at',at_time);
end $$;
revoke all on function public.admin_console_review_queue(text,text,integer,integer),public.admin_console_review(text,uuid,uuid,text,text) from public,anon;
grant execute on function public.admin_console_review_queue(text,text,integer,integer),public.admin_console_review(text,uuid,uuid,text,text) to authenticated;
notify pgrst,'reload schema';
commit;
