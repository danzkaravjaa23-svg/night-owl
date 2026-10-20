-- Social discovery, privacy and a real pilot cohort. Apply to staging first.
begin;

alter table public.profiles add column if not exists is_private boolean not null default false;
alter table public.profiles add column if not exists dm_policy text not null default 'requests'
  check (dm_policy in ('requests','following','nobody','everyone'));
alter table public.checkins add column if not exists audience text not null default 'self'
  check (audience in ('self','followers','public'));

create or replace function public.social_admin() returns boolean
language sql stable security definer set search_path=public,pg_temp as $$
  select exists(select 1 from profiles where id=auth.uid() and is_admin and not coalesce(is_banned,false));
$$;
create or replace function public.social_active() returns boolean
language sql stable security definer set search_path=public,pg_temp as $$
  select exists(select 1 from profiles where id=auth.uid() and not coalesce(is_banned,false));
$$;
create or replace function public.social_pair_blocked(a uuid,b uuid) returns boolean
language sql stable security definer set search_path=public,pg_temp as $$
  select exists(select 1 from blocks where (blocker_id=a and blocked_id=b) or (blocker_id=b and blocked_id=a));
$$;
create or replace function public.can_view_author(p_author uuid) returns boolean
language sql stable security definer set search_path=public,pg_temp as $$
  select exists(select 1 from profiles p where p.id=p_author
    and (p.id=auth.uid() or (not coalesce(p.is_banned,false)
      and not social_pair_blocked(auth.uid(),p.id)
      and (not p.is_private or exists(select 1 from follows f where f.follower_id=auth.uid() and f.following_id=p.id)))));
$$;
create or replace function public.social_blocked(p_target uuid) returns boolean
language sql stable security definer set search_path=public,pg_temp as $$ select social_pair_blocked(auth.uid(),p_target); $$;
create or replace function public.protect_profile_flags() returns trigger
language plpgsql security definer set search_path=public,pg_temp as $$
begin
  if auth.uid() is null then return new; end if;
  if not social_admin() then
    if tg_op='INSERT' then new.is_admin:=false; new.is_banned:=false; new.is_verified:=false;
    else new.is_admin:=old.is_admin; new.is_banned:=old.is_banned; new.is_verified:=old.is_verified; end if;
  end if;
  return new;
end $$;
drop trigger if exists protect_profile_flags on public.profiles;
create trigger protect_profile_flags before insert or update on public.profiles
  for each row execute function public.protect_profile_flags();
drop policy if exists social_profile_update on public.profiles;
create policy social_profile_update on public.profiles as restrictive for update to authenticated
  using(social_active() and (id=auth.uid() or social_admin()))
  with check(social_active() and (id=auth.uid() or social_admin()));

create table if not exists public.follow_requests (
  requester_id uuid references profiles(id) on delete cascade,
  target_id uuid references profiles(id) on delete cascade,
  created_at timestamptz not null default now(),
  primary key(requester_id,target_id), check(requester_id<>target_id)
);
alter table public.follow_requests enable row level security;
create table if not exists public.dm_requests (
  requester_id uuid references profiles(id) on delete cascade,
  target_id uuid references profiles(id) on delete cascade,
  status text not null default 'pending' check(status in ('pending','accepted','declined')),
  created_at timestamptz not null default now(),
  primary key(requester_id,target_id), check(requester_id<>target_id)
);
alter table public.dm_requests enable row level security;
drop policy if exists social_follow_requests on public.follow_requests;
create policy social_follow_requests on public.follow_requests for select to authenticated
  using (auth.uid() in (requester_id,target_id));
drop policy if exists social_dm_requests on public.dm_requests;
create policy social_dm_requests on public.dm_requests for select to authenticated
  using (auth.uid() in (requester_id,target_id));
grant select on public.follow_requests,public.dm_requests to authenticated;
revoke insert,update,delete on public.follow_requests,public.dm_requests from anon,authenticated;

create or replace function public.set_follow(p_target uuid,p_follow boolean) returns text
language plpgsql security definer set search_path=public,pg_temp as $$
declare v_private boolean;
begin
  if not social_active() or p_target=auth.uid() or p_follow is null then
    raise exception 'Follow unavailable' using errcode='42501'; end if;
  perform 1 from profiles where id in (auth.uid(),p_target) order by id for update;
  if not p_follow then
    delete from follows where follower_id=auth.uid() and following_id=p_target;
    delete from follow_requests where requester_id=auth.uid() and target_id=p_target;
    return 'none';
  end if;
  select is_private into v_private from profiles where id=p_target and not coalesce(is_banned,false);
  if not found or social_pair_blocked(auth.uid(),p_target) then
    raise exception 'Follow unavailable' using errcode='42501'; end if;
  if exists(select 1 from follows where follower_id=auth.uid() and following_id=p_target) then return 'following'; end if;
  if v_private then
    insert into follow_requests(requester_id,target_id) values(auth.uid(),p_target) on conflict do nothing;
    return 'requested';
  end if;
  insert into follows(follower_id,following_id) values(auth.uid(),p_target) on conflict do nothing;
  return 'following';
end $$;
create or replace function public.respond_follow_request(p_requester uuid,p_accept boolean) returns void
language plpgsql security definer set search_path=public,pg_temp as $$
begin
  if not social_active() or p_accept is null then raise exception 'Not allowed' using errcode='42501'; end if;
  perform 1 from profiles where id in (auth.uid(),p_requester) order by id for update;
  if not exists(select 1 from follow_requests where requester_id=p_requester and target_id=auth.uid()) then
    raise exception 'Request not found' using errcode='22023'; end if;
  if p_accept then
    if social_pair_blocked(auth.uid(),p_requester) or not exists(select 1 from profiles where id=p_requester and not coalesce(is_banned,false)) then
      raise exception 'Not allowed' using errcode='42501'; end if;
    insert into follows(follower_id,following_id) values(p_requester,auth.uid()) on conflict do nothing;
  end if;
  delete from follow_requests where requester_id=p_requester and target_id=auth.uid();
end $$;

-- Restrictive policies compose with existing owner/admin policies.
drop policy if exists social_follow_insert on public.follows;
create policy social_follow_insert on public.follows as restrictive for insert to authenticated
  with check(social_active() and follower_id=auth.uid() and following_id<>auth.uid() and not social_blocked(following_id)
    and exists(select 1 from profiles where id=following_id and not is_private and not coalesce(is_banned,false)));
drop policy if exists social_posts_read on public.posts;
create policy social_posts_read on public.posts as restrictive for select to anon,authenticated using(can_view_author(user_id));
drop policy if exists social_posts_write on public.posts;
create policy social_posts_write on public.posts as restrictive for insert to authenticated with check(social_active());
drop policy if exists social_posts_update on public.posts;
create policy social_posts_update on public.posts as restrictive for update to authenticated
  using(social_active() and (user_id=auth.uid() or social_admin()))
  with check(social_active() and (user_id=auth.uid() or social_admin()));
drop policy if exists social_stories_read on public.stories;
create policy social_stories_read on public.stories as restrictive for select to anon,authenticated
  using(can_view_author(user_id) and (user_id=auth.uid() or expires_at>now()));
drop policy if exists social_stories_write on public.stories;
create policy social_stories_write on public.stories as restrictive for insert to authenticated with check(social_active());
drop policy if exists social_checkins_read on public.checkins;
create policy social_checkins_read on public.checkins as restrictive for select to anon,authenticated
  using(user_id=auth.uid() or (expires_at>now() and can_view_author(user_id) and (audience='public' or (audience='followers' and exists(
    select 1 from follows where follower_id=auth.uid() and following_id=user_id)))));
drop policy if exists social_comments_read on public.comments;
create policy social_comments_read on public.comments as restrictive for select to anon,authenticated
  using(can_view_author(user_id) and exists(select 1 from posts where id=post_id));
drop policy if exists social_comments_write on public.comments;
create policy social_comments_write on public.comments as restrictive for insert to authenticated
  with check(social_active() and exists(select 1 from posts where id=post_id));
drop policy if exists social_likes_read on public.likes;
create policy social_likes_read on public.likes as restrictive for select to anon,authenticated
  using(exists(select 1 from posts where id=post_id));
drop policy if exists social_likes_write on public.likes;
create policy social_likes_write on public.likes as restrictive for insert to authenticated
  with check(social_active() and exists(select 1 from posts where id=post_id));
drop policy if exists social_messages_read on public.messages;
create policy social_messages_read on public.messages as restrictive for select to anon,authenticated
  using(social_active() and auth.uid() in (sender_id,receiver_id) and not social_blocked(case when sender_id=auth.uid() then receiver_id else sender_id end));
drop policy if exists social_messages_write on public.messages;
create policy social_messages_write on public.messages as restrictive for insert to authenticated with check(false);
drop policy if exists social_messages_update on public.messages;
create policy social_messages_update on public.messages as restrictive for update to authenticated
  using(receiver_id=auth.uid() and not social_blocked(sender_id))
  with check(receiver_id=auth.uid() and not social_blocked(sender_id));
revoke update on public.messages from authenticated;
grant update(is_read) on public.messages to authenticated;

create or replace function public.social_block_cleanup() returns trigger
language plpgsql security definer set search_path=public,pg_temp as $$
begin
  perform 1 from profiles where id in (new.blocker_id,new.blocked_id) order by id for update;
  delete from follows where (follower_id=new.blocker_id and following_id=new.blocked_id) or (follower_id=new.blocked_id and following_id=new.blocker_id);
  delete from follow_requests where (requester_id=new.blocker_id and target_id=new.blocked_id) or (requester_id=new.blocked_id and target_id=new.blocker_id);
  delete from dm_requests where (requester_id=new.blocker_id and target_id=new.blocked_id) or (requester_id=new.blocked_id and target_id=new.blocker_id);
  return new;
end $$;
drop trigger if exists social_block_cleanup on public.blocks;
create trigger social_block_cleanup after insert on public.blocks for each row execute function public.social_block_cleanup();
-- Apply the same cleanup to blocks created before this migration.
delete from public.follows f using public.blocks b where
  (f.follower_id=b.blocker_id and f.following_id=b.blocked_id) or
  (f.follower_id=b.blocked_id and f.following_id=b.blocker_id);
delete from public.follow_requests r using public.blocks b where
  (r.requester_id=b.blocker_id and r.target_id=b.blocked_id) or
  (r.requester_id=b.blocked_id and r.target_id=b.blocker_id);
delete from public.dm_requests r using public.blocks b where
  (r.requester_id=b.blocker_id and r.target_id=b.blocked_id) or
  (r.requester_id=b.blocked_id and r.target_id=b.blocker_id);

create or replace function public.get_relationship(p_target uuid) returns jsonb
language plpgsql stable security definer set search_path=public,pg_temp as $$
declare v_policy text; v_state text; v_blocked boolean;
begin
  select dm_policy into v_policy from profiles where id=p_target and not coalesce(is_banned,false);
  v_blocked:=social_pair_blocked(auth.uid(),p_target);
  v_state:='new';
  if v_policy is null or v_blocked or not social_active() or p_target=auth.uid() then v_state:='blocked';
  elsif v_policy='nobody' then v_state:='closed';
  elsif v_policy='everyone' or exists(select 1 from follows where follower_id=p_target and following_id=auth.uid())
    or exists(select 1 from dm_requests where status='accepted' and ((requester_id=auth.uid() and target_id=p_target) or (target_id=auth.uid() and requester_id=p_target))) then v_state:='accepted';
  elsif exists(select 1 from dm_requests where requester_id=p_target and target_id=auth.uid() and status='pending') then v_state:='incoming';
  elsif exists(select 1 from dm_requests where requester_id=auth.uid() and target_id=p_target) then v_state:='requested';
  elsif v_policy='following' then v_state:='closed'; end if;
  return jsonb_build_object('following',exists(select 1 from follows where follower_id=auth.uid() and following_id=p_target),
    'requested',exists(select 1 from follow_requests where requester_id=auth.uid() and target_id=p_target),
    'private',coalesce((select is_private from profiles where id=p_target),true),
    'can_view',can_view_author(p_target),'blocked',v_blocked,'dm_state',v_state);
end $$;
create or replace function public.respond_message_request(p_requester uuid,p_accept boolean) returns void
language plpgsql security definer set search_path=public,pg_temp as $$
begin
  if not social_active() or p_accept is null then raise exception 'Not allowed' using errcode='42501'; end if;
  perform 1 from profiles where id in (auth.uid(),p_requester) order by id for update;
  if social_pair_blocked(auth.uid(),p_requester) then raise exception 'Not allowed' using errcode='42501'; end if;
  update dm_requests set status=case when p_accept then 'accepted' else 'declined' end
    where requester_id=p_requester and target_id=auth.uid() and status='pending';
  if not found then raise exception 'Request not found' using errcode='22023'; end if;
end $$;

-- A source ID remains a source ID; OSM IDs are never sent to UUID columns.
create table if not exists public.venue_catalog (
  ref text primary key check(length(ref) between 1 and 100),
  venue_id uuid unique references venues(id) on delete cascade,
  name text not null, venue_type text, address text, district text,
  lat double precision, lng double precision, cover_url text, phone text,
  website_url text, source_url text, source_label text, source_retrieved_at timestamptz,
  hours text, price_min integer check(price_min>=0),price_max integer check(price_max>=price_min),
  menu_url text, vibes text[] not null default '{}',
  reviewed_at timestamptz, reviewed_by uuid references profiles(id) on delete set null
);
alter table public.venue_catalog enable row level security;
drop policy if exists social_catalog_read on public.venue_catalog;
create policy social_catalog_read on public.venue_catalog for select using(true);
grant select on public.venue_catalog to anon,authenticated;
revoke insert,update,delete on public.venue_catalog from anon,authenticated;
create or replace function public.sync_venue_catalog() returns trigger
language plpgsql security definer set search_path=public,pg_temp as $$
begin
  insert into venue_catalog(ref,venue_id,name,venue_type,address,district,lat,lng,cover_url,phone)
    values(new.id::text,new.id,new.name,new.venue_type,new.address,new.district,new.lat,new.lng,new.cover_url,new.phone)
    on conflict(ref) do update set name=excluded.name,venue_type=excluded.venue_type,address=excluded.address,
      district=excluded.district,lat=excluded.lat,lng=excluded.lng,cover_url=excluded.cover_url,phone=excluded.phone;
  if tg_op='UPDATE' and (old.name,old.venue_type,old.address,old.district,old.lat,old.lng,old.cover_url,old.phone)
      is distinct from (new.name,new.venue_type,new.address,new.district,new.lat,new.lng,new.cover_url,new.phone) then
    update venue_catalog set reviewed_at=null,reviewed_by=null where ref=new.id::text;
    delete from pilot_venues where venue_ref=new.id::text;
  end if;
  return new;
end $$;
insert into public.venue_catalog(ref,venue_id,name,venue_type,address,district,lat,lng,cover_url,phone)
  select id::text,id,name,venue_type,address,district,lat,lng,cover_url,phone from public.venues on conflict(ref) do nothing;
drop trigger if exists sync_venue_catalog on public.venues;
create trigger sync_venue_catalog after insert or update on public.venues for each row execute function public.sync_venue_catalog();
alter table public.posts add column if not exists venue_ref text references public.venue_catalog(ref);
alter table public.stories add column if not exists venue_ref text references public.venue_catalog(ref);
alter table public.messages add column if not exists venue_ref text references public.venue_catalog(ref);
update public.posts set venue_ref=venue_id::text where venue_ref is null and venue_id is not null;
update public.stories set venue_ref=venue_id::text where venue_ref is null and venue_id is not null;
create index if not exists social_post_venue on public.posts(venue_ref,created_at desc,id desc);
create index if not exists social_feed_cursor on public.posts(created_at desc,id desc);
create or replace function public.normalize_venue_reference() returns trigger
language plpgsql security definer set search_path=public,pg_temp as $$
declare v venue_catalog;
begin
  if new.venue_ref is null and new.venue_id is not null then new.venue_ref:=new.venue_id::text; end if;
  if new.venue_ref is not null then
    select * into strict v from venue_catalog where ref=new.venue_ref;
    new.venue_id:=v.venue_id;
    if tg_table_name='posts' then new.venue_name:=v.name; end if;
  end if;
  return new;
end $$;
drop trigger if exists normalize_venue_reference on public.posts;
create trigger normalize_venue_reference before insert or update of venue_ref,venue_id on public.posts
  for each row execute function public.normalize_venue_reference();
drop trigger if exists normalize_venue_reference on public.stories;
create trigger normalize_venue_reference before insert or update of venue_ref,venue_id on public.stories
  for each row execute function public.normalize_venue_reference();

create or replace function public.send_direct_message(p_receiver uuid,p_body text,p_note text default null,p_story uuid default null,p_venue text default null)
returns uuid language plpgsql security definer set search_path=public,pg_temp as $$
declare v_state text; v_id uuid; v_media text;
begin
  perform 1 from profiles where id in (auth.uid(),p_receiver) order by id for update;
  v_state:=get_relationship(p_receiver)->>'dm_state';
  if v_state not in ('new','accepted') then raise exception 'Message unavailable' using errcode='42501'; end if;
  if length(trim(p_body)) not between 1 and 2000 or length(coalesce(p_note,''))>300 then
    raise exception 'Invalid message' using errcode='22023'; end if;
  if (select count(*) from messages where sender_id=auth.uid() and created_at>now()-interval '1 minute')>=30 then
    raise exception 'Slow down' using errcode='54000'; end if;
  if p_story is not null then
    select media_url into v_media from stories where id=p_story and expires_at>now() and can_view_author(user_id);
    if not found then raise exception 'Story unavailable' using errcode='42501'; end if;
  end if;
  if p_venue is not null and not exists(select 1 from venue_catalog where ref=p_venue) then
    raise exception 'Venue unavailable' using errcode='22023'; end if;
  if v_state='new' then insert into dm_requests(requester_id,target_id) values(auth.uid(),p_receiver); end if;
  insert into messages(sender_id,receiver_id,body,is_read,note_text,story_media_url,venue_ref)
    values(auth.uid(),p_receiver,trim(p_body),false,p_note,v_media,p_venue) returning id into v_id;
  return v_id;
end $$;

create or replace function public.get_discovery_feed(p_following boolean default false,p_before timestamptz default null,p_before_id uuid default null,p_limit integer default 20)
returns setof jsonb language sql stable security invoker set search_path=public,pg_temp as $$
  select to_jsonb(p)||jsonb_build_object('profiles',jsonb_build_object('id',pr.id,'username',pr.username,'avatar_url',pr.avatar_url,'is_verified',pr.is_verified),
    'venue_name',coalesce(v.name,p.venue_name),'is_liked_by_me',exists(select 1 from likes where post_id=p.id and user_id=auth.uid()))
  from posts p join profiles pr on pr.id=p.user_id left join venue_catalog v on v.ref=p.venue_ref
  where (not p_following or exists(select 1 from follows where follower_id=auth.uid() and following_id=p.user_id))
    and (p_before is null or (p.created_at,p.id)<(p_before,coalesce(p_before_id,'ffffffff-ffff-ffff-ffff-ffffffffffff'::uuid)))
  order by p.created_at desc,p.id desc limit greatest(1,least(coalesce(p_limit,20),50));
$$;
-- Both the accepted-follow and video predicates precede the page limit.
create or replace function public.get_following_reels(p_limit integer default 50)
returns setof jsonb language sql stable security invoker set search_path=public,pg_temp as $$
  select to_jsonb(p)||jsonb_build_object(
    'profiles',jsonb_build_object('username',pr.username,'avatar_url',pr.avatar_url),
    'venue_catalog',jsonb_build_object('name',v.name))
  from posts p join profiles pr on pr.id=p.user_id left join venue_catalog v on v.ref=p.venue_ref
  where exists(select 1 from follows where follower_id=auth.uid() and following_id=p.user_id)
    and exists(select 1 from unnest(array[p.media_url]||coalesce(p.media_urls,'{}'::text[])) media(url)
      where url ~* '^https?://[^/[:space:]]+/' and (
        url ~* '\.(mp4|webm|mov|m4v|avi|mkv)([?#]|$)'
        or (p.media_type='video' and url !~* '\.(avif|bmp|gif|heic|heif|ico|jpe?g|png|svg|webp)([?#]|$)')))
  order by p.created_at desc,p.id desc limit greatest(1,least(coalesce(p_limit,50),50));
$$;
revoke all on function public.get_following_reels(integer) from public,anon;
grant execute on function public.get_following_reels(integer) to authenticated;

create or replace function public.discover_creators(p_interest text default null,p_query text default '',p_limit integer default 20)
returns setof jsonb language sql stable security invoker set search_path=public,pg_temp as $$
  select jsonb_build_object('id',p.id,'username',p.username,'full_name',p.full_name,'avatar_url',p.avatar_url,'bio',p.bio,'is_verified',p.is_verified,'interests',p.interests,
    'posts_count',(select count(*) from posts where user_id=p.id),'followers_count',p.followers_count)
  from profiles p where not coalesce(p.is_banned,false) and not p.is_private and p.id is distinct from auth.uid()
    and not social_pair_blocked(auth.uid(),p.id)
    and (p_interest is null or p_interest=any(p.interests))
    and (coalesce(p_query,'')='' or concat_ws(' ',p.username,p.full_name) ilike '%'||left(p_query,80)||'%')
    and exists(select 1 from posts where user_id=p.id)
  order by (select max(created_at) from posts where user_id=p.id) desc nulls last,p.id
  limit greatest(1,least(coalesce(p_limit,20),50));
$$;

create table if not exists public.venue_saves (
  user_id uuid references profiles(id) on delete cascade,
  venue_ref text references venue_catalog(ref) on delete cascade,
  created_at timestamptz not null default now(),primary key(user_id,venue_ref)
);
alter table public.venue_saves add column if not exists legacy_import boolean not null default false;
alter table public.venue_saves enable row level security;
drop policy if exists social_saves on public.venue_saves;
create policy social_saves on public.venue_saves for all to authenticated using(user_id=auth.uid()) with check(user_id=auth.uid() and social_active() and not legacy_import);
grant select,insert,delete on public.venue_saves to authenticated;
create or replace function public.import_venue_saves(p_owner uuid,p_refs text[]) returns integer
language plpgsql security definer set search_path=public,pg_temp as $$
declare v_count integer;
begin
  if not social_active() or auth.uid() is distinct from p_owner then
    raise exception 'Account changed' using errcode='42501'; end if;
  if cardinality(p_refs)>1000 then raise exception 'Too many places' using errcode='22023'; end if;
  insert into venue_saves(user_id,venue_ref,legacy_import)
    select auth.uid(),ref,true from venue_catalog where ref=any(p_refs) on conflict do nothing;
  get diagnostics v_count=row_count;
  return v_count;
end $$;
revoke all on function public.import_venue_saves(uuid,text[]) from public,anon;
grant execute on function public.import_venue_saves(uuid,text[]) to authenticated;
create table if not exists public.place_collections (
  id uuid primary key default gen_random_uuid(), user_id uuid not null references profiles(id) on delete cascade,
  title text not null check(length(trim(title)) between 1 and 80),
  is_public boolean not null default true,created_at timestamptz not null default now()
);
create table if not exists public.collection_places (
  collection_id uuid references place_collections(id) on delete cascade,
  venue_ref text references venue_catalog(ref) on delete cascade,
  note text not null default '' check(length(note)<=280),created_at timestamptz not null default now(),
  primary key(collection_id,venue_ref)
);
alter table public.place_collections enable row level security;
alter table public.collection_places enable row level security;
drop policy if exists social_collections_read on public.place_collections;
create policy social_collections_read on public.place_collections for select using(user_id=auth.uid() or (is_public and can_view_author(user_id)));
drop policy if exists social_collections_write on public.place_collections;
create policy social_collections_write on public.place_collections for all to authenticated using(user_id=auth.uid()) with check(user_id=auth.uid() and social_active());
drop policy if exists social_collection_places_read on public.collection_places;
create policy social_collection_places_read on public.collection_places for select using(exists(select 1 from place_collections where id=collection_id));
drop policy if exists social_collection_places_write on public.collection_places;
create policy social_collection_places_write on public.collection_places for all to authenticated
  using(exists(select 1 from place_collections where id=collection_id and user_id=auth.uid()))
  with check(social_active() and exists(select 1 from place_collections where id=collection_id and user_id=auth.uid()));
grant select on public.place_collections,public.collection_places to anon,authenticated;
grant insert,update,delete on public.place_collections,public.collection_places to authenticated;

-- Only short-lived, authorized signed URLs may deliver post/story media.
create or replace function public.social_media_readable(p_bucket text,p_name text) returns boolean
language sql stable security definer set search_path=public,pg_temp as $$
  select (split_part(p_name,'/',1)=auth.uid()::text and social_active()) or
    (p_bucket='posts' and exists(select 1 from posts p where p.user_id::text=split_part(p_name,'/',1) and can_view_author(p.user_id)
      and (split_part(p.media_url,'/storage/v1/object/public/posts/',2)=p_name or exists(select 1 from unnest(p.media_urls) u where split_part(u,'/storage/v1/object/public/posts/',2)=p_name)))) or
    (p_bucket='posts' and exists(select 1 from events e where e.organizer_id::text=split_part(p_name,'/',1) and split_part(e.cover_url,'/storage/v1/object/public/posts/',2)=p_name)) or
    (p_bucket='stories' and exists(select 1 from stories s where s.user_id::text=split_part(p_name,'/',1) and s.expires_at>now() and can_view_author(s.user_id)
      and split_part(s.media_url,'/storage/v1/object/public/stories/',2)=p_name));
$$;
update storage.buckets set public=false where id in ('posts','stories');
drop policy if exists social_media_read on storage.objects;
create policy social_media_read on storage.objects as restrictive for select to anon,authenticated
  using(bucket_id not in ('posts','stories') or public.social_media_readable(bucket_id,name));

create table if not exists public.discovery_activity (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references profiles(id) on delete cascade,event text not null,
  target text not null default '',day date not null default (now() at time zone 'UTC')::date,
  created_at timestamptz not null default now()
);
create index if not exists social_activity_cohort on public.discovery_activity(user_id,event,created_at);
alter table public.discovery_activity enable row level security;
revoke all on public.discovery_activity from anon,authenticated;
create or replace function public.record_discovery_activity(p_event text,p_target text default '') returns void
language plpgsql security definer set search_path=public,pg_temp as $$
begin
  if not social_active() or not exists(select 1 from pilot_participants where user_id=auth.uid()) then return; end if;
  if (select count(*) from discovery_activity where user_id=auth.uid() and created_at>now()-interval '1 minute')>=120 then return; end if;
  if p_event='session' then p_target:='';
  elsif p_event='directions' then
    if not exists(select 1 from venue_catalog where ref=p_target) then raise exception 'Invalid venue' using errcode='22023'; end if;
  elsif p_event='profile_view' then
    if not exists(select 1 from profiles where id::text=p_target and can_view_author(id)) then return; end if;
  else raise exception 'Invalid event' using errcode='22023'; end if;
  insert into discovery_activity(user_id,event,target) values(auth.uid(),p_event,p_target) on conflict do nothing;
end $$;
create or replace function public.social_action_metric() returns trigger
language plpgsql security definer set search_path=public,pg_temp as $$
declare v_actor uuid;v_event text;v_target text;
begin
  if tg_table_name='follows' then v_actor:=new.follower_id;v_event:='follow';v_target:=new.following_id::text;
  elsif tg_table_name='venue_saves' then
    if new.legacy_import then return new; end if;
    v_actor:=new.user_id;v_event:='venue_save';v_target:=new.venue_ref;
  else v_actor:=new.user_id;v_event:='content_publish';v_target:=new.id::text; end if;
  if not exists(select 1 from pilot_participants where user_id=v_actor) then return new; end if;
  insert into discovery_activity(user_id,event,target) values(v_actor,v_event,v_target) on conflict do nothing;
  return new;
end $$;
drop trigger if exists social_action_metric on public.follows;
create trigger social_action_metric after insert on public.follows for each row execute function public.social_action_metric();
drop trigger if exists social_action_metric on public.venue_saves;
create trigger social_action_metric after insert on public.venue_saves for each row execute function public.social_action_metric();
drop trigger if exists social_action_metric on public.posts;
create trigger social_action_metric after insert on public.posts for each row execute function public.social_action_metric();

create table if not exists public.pilot_creators(user_id uuid primary key references profiles(id) on delete cascade,enrolled_at timestamptz not null default now());
create table if not exists public.pilot_participants(user_id uuid primary key references profiles(id) on delete cascade,enrolled_at timestamptz not null default now());
create table if not exists public.pilot_venues(venue_ref text primary key references venue_catalog(ref) on delete cascade,reviewed_at timestamptz not null default now());
create table if not exists public.pilot_content(post_id uuid primary key references posts(id) on delete cascade,reviewed_at timestamptz not null default now());
alter table public.pilot_creators enable row level security;
alter table public.pilot_participants enable row level security;
alter table public.pilot_venues enable row level security;
alter table public.pilot_content enable row level security;
revoke all on public.pilot_creators,public.pilot_participants,public.pilot_venues,public.pilot_content from anon,authenticated;
create or replace function public.set_pilot_entry(p_kind text,p_id text,p_enabled boolean) returns void
language plpgsql security definer set search_path=public,pg_temp as $$
begin
  if not social_admin() or p_enabled is null then raise exception 'Admin only' using errcode='42501'; end if;
  if p_kind='creator' then
    if p_enabled then
      insert into pilot_creators(user_id) values(p_id::uuid) on conflict do nothing;
      insert into pilot_participants(user_id) values(p_id::uuid) on conflict do nothing;
    else delete from pilot_creators where user_id=p_id::uuid; end if;
  elsif p_kind='participant' then
    if p_enabled then insert into pilot_participants(user_id) values(p_id::uuid) on conflict do nothing;
    else delete from pilot_participants where user_id=p_id::uuid; end if;
  elsif p_kind='venue' then
    if p_enabled then
      if not exists(select 1 from venue_catalog where ref=p_id and cover_url is not null and address is not null and hours is not null and price_min is not null) then
        raise exception 'Complete venue photo, address, hours and budget first' using errcode='22023'; end if;
      insert into pilot_venues(venue_ref) values(p_id) on conflict do nothing;
      update venue_catalog set reviewed_at=now(),reviewed_by=auth.uid() where ref=p_id;
    else delete from pilot_venues where venue_ref=p_id; update venue_catalog set reviewed_at=null,reviewed_by=null where ref=p_id; end if;
  elsif p_kind='content' then
    if p_enabled then
      if not exists(select 1 from posts where id=p_id::uuid and venue_ref is not null and media_url is not null and can_view_author(user_id)) then
        raise exception 'Select visible content with a venue and media' using errcode='22023'; end if;
      insert into pilot_content(post_id) values(p_id::uuid) on conflict do nothing;
    else delete from pilot_content where post_id=p_id::uuid; end if;
  else raise exception 'Invalid kind' using errcode='22023'; end if;
end $$;
create or replace function public.review_venue(p_ref text,p_details jsonb) returns void
language plpgsql security definer set search_path=public,pg_temp as $$
begin
  if not social_admin() and not exists(select 1 from venues v join venue_catalog c on c.venue_id=v.id where c.ref=p_ref and v.owner_id=auth.uid() and social_active()) then
    raise exception 'Owner or admin only' using errcode='42501'; end if;
  if jsonb_typeof(p_details)<>'object' or length(p_details::text)>10000 then raise exception 'Invalid details' using errcode='22023'; end if;
  if exists(select 1 from jsonb_each_text(p_details) where key in ('cover_url','menu_url') and value<>'' and value !~ '^https://') then
    raise exception 'HTTPS links required' using errcode='22023'; end if;
  update venue_catalog set address=nullif(trim(p_details->>'address'),''),hours=nullif(trim(p_details->>'hours'),''),
    cover_url=nullif(trim(p_details->>'cover_url'),''),menu_url=nullif(trim(p_details->>'menu_url'),''),
    price_min=nullif(p_details->>'price_min','')::integer,price_max=nullif(p_details->>'price_max','')::integer,
    vibes=array(select jsonb_array_elements_text(coalesce(p_details->'vibes','[]'::jsonb))),reviewed_at=null,reviewed_by=null where ref=p_ref;
  delete from pilot_venues where venue_ref=p_ref;
end $$;
create or replace function public.get_pilot_overview() returns jsonb
language plpgsql stable security definer set search_path=public,pg_temp as $$
declare v_result jsonb;
begin
  if not social_admin() then raise exception 'Admin only' using errcode='42501'; end if;
  with cohort as (select p.id,c.enrolled_at as created_at from profiles p join pilot_participants c on c.user_id=p.id),
  metrics as (select count(*) as users,
    count(*) filter(where now()>=c.created_at+interval '1 day') as activation_eligible,
    count(*) filter(where now()>=c.created_at+interval '1 day' and exists(select 1 from discovery_activity a where a.user_id=c.id and a.event in ('follow','venue_save') and a.created_at>=c.created_at and a.created_at<c.created_at+interval '1 day')) as activated,
    count(*) filter(where now()>=c.created_at+interval '1 day' and exists(select 1 from discovery_activity a where a.user_id=c.id and a.event='follow' and a.created_at>=c.created_at and a.created_at<c.created_at+interval '1 day')) as first_day_followed,
    count(*) filter(where now()>=c.created_at+interval '1 day' and exists(select 1 from discovery_activity a where a.user_id=c.id and a.event='venue_save' and a.created_at>=c.created_at and a.created_at<c.created_at+interval '1 day')) as first_day_saved,
    count(*) filter(where now()>=c.created_at+interval '8 days') as d7_eligible,
    count(*) filter(where now()>=c.created_at+interval '8 days' and exists(select 1 from discovery_activity a where a.user_id=c.id and a.event='session' and a.created_at>=c.created_at+interval '7 days' and a.created_at<c.created_at+interval '8 days')) as d7_returned,
    count(*) filter(where exists(select 1 from pilot_creators pc where pc.user_id=c.id) and (select count(distinct a.day) from discovery_activity a where a.user_id=c.id and a.event='content_publish' and a.created_at>=c.created_at)>=2) as repeat_creators from cohort c)
  select to_jsonb(m)||jsonb_build_object('creator_count',(select count(*) from pilot_creators),'venues',(select count(*) from pilot_venues),'content',(select count(*) from pilot_content),
    'directions',(select count(distinct (a.user_id,a.target,a.day)) from discovery_activity a join cohort c on c.id=a.user_id where a.event='directions' and a.created_at>=c.created_at),
    'creators',coalesce((select jsonb_agg(jsonb_build_object('id',p.id,'label',p.username)) from pilot_creators c join profiles p on p.id=c.user_id),'[]'::jsonb),
    'participants',coalesce((select jsonb_agg(jsonb_build_object('id',p.id,'label',p.username)) from pilot_participants c join profiles p on p.id=c.user_id),'[]'::jsonb),
    'places',coalesce((select jsonb_agg(jsonb_build_object('id',v.ref,'label',v.name)) from pilot_venues c join venue_catalog v on v.ref=c.venue_ref),'[]'::jsonb),
    'posts',coalesce((select jsonb_agg(jsonb_build_object('id',p.id,'label',left(coalesce(p.caption,'Нийтлэл'),80))) from pilot_content c join posts p on p.id=c.post_id),'[]'::jsonb)) into v_result from metrics m;
  return v_result;
end $$;

-- No helper gets PostgreSQL's default PUBLIC execute grant.
revoke all on function public.social_pair_blocked(uuid,uuid),public.protect_profile_flags(),public.social_block_cleanup(),public.sync_venue_catalog(),public.normalize_venue_reference(),public.social_action_metric() from public,anon,authenticated;
revoke all on function public.social_admin(),public.social_active(),public.can_view_author(uuid),public.social_media_readable(text,text),public.get_relationship(uuid),public.get_discovery_feed(boolean,timestamptz,uuid,integer),public.discover_creators(text,text,integer) from public;
grant execute on function public.social_admin(),public.social_active(),public.can_view_author(uuid),public.social_media_readable(text,text),public.get_relationship(uuid),public.get_discovery_feed(boolean,timestamptz,uuid,integer),public.discover_creators(text,text,integer) to anon,authenticated;
-- discover_creators invokes this helper as invoker; it can only test the caller's pair.
create or replace function public.social_blocked(p_target uuid) returns boolean
language sql stable security definer set search_path=public,pg_temp as $$ select social_pair_blocked(auth.uid(),p_target); $$;
revoke all on function public.social_blocked(uuid) from public;
grant execute on function public.social_blocked(uuid) to anon,authenticated;
-- Recreate the invoker query without exposing the two-user helper.
create or replace function public.discover_creators(p_interest text default null,p_query text default '',p_limit integer default 20)
returns setof jsonb language sql stable security invoker set search_path=public,pg_temp as $$
  select jsonb_build_object('id',p.id,'username',p.username,'full_name',p.full_name,'avatar_url',p.avatar_url,'bio',p.bio,'is_verified',p.is_verified,'interests',p.interests,
    'posts_count',(select count(*) from posts where user_id=p.id),'followers_count',p.followers_count)
  from profiles p where not coalesce(p.is_banned,false) and not p.is_private and p.id is distinct from auth.uid()
    and not social_blocked(p.id) and (p_interest is null or p_interest=any(p.interests))
    and (coalesce(p_query,'')='' or concat_ws(' ',p.username,p.full_name) ilike '%'||left(p_query,80)||'%')
    and exists(select 1 from posts where user_id=p.id)
  order by (select max(created_at) from posts where user_id=p.id) desc nulls last,p.id
  limit greatest(1,least(coalesce(p_limit,20),50));
$$;
revoke all on function public.set_follow(uuid,boolean),public.respond_follow_request(uuid,boolean),public.respond_message_request(uuid,boolean),public.send_direct_message(uuid,text,text,uuid,text),public.record_discovery_activity(text,text),public.set_pilot_entry(text,text,boolean),public.review_venue(text,jsonb),public.get_pilot_overview() from public,anon;
grant execute on function public.set_follow(uuid,boolean),public.respond_follow_request(uuid,boolean),public.respond_message_request(uuid,boolean),public.send_direct_message(uuid,text,text,uuid,text),public.record_discovery_activity(text,text),public.set_pilot_entry(text,text,boolean),public.review_venue(text,jsonb),public.get_pilot_overview() to authenticated;
-- Legacy feed RPCs must also obey the new restrictive content policies.
do $$ declare f regprocedure; begin
  for f in select p.oid::regprocedure from pg_proc p join pg_namespace n on n.oid=p.pronamespace
    where n.nspname='public' and p.proname in ('get_feed_cursor','get_feed_posts','get_user_posts') loop
    execute format('alter function %s security invoker',f);
  end loop;
end $$;
create or replace function public.dm_conversations()
returns table(partner_id uuid,partner_username text,partner_avatar_url text,partner_last_seen_at timestamptz,last_body text,last_at timestamptz,last_sender_id uuid,unread_count bigint)
language sql stable security invoker set search_path=public,pg_temp as $$
  with relevant as (
    select case when m.sender_id=auth.uid() then m.receiver_id else m.sender_id end as other,m.*
      from messages m where auth.uid() in(m.sender_id,m.receiver_id)
  ), latest as (select distinct on(other) * from relevant order by other,created_at desc,id desc)
  select l.other,p.username,p.avatar_url,p.last_seen_at,l.body,l.created_at,l.sender_id,
    (select count(*) from relevant r where r.other=l.other and r.receiver_id=auth.uid() and not r.is_read)
    from latest l join profiles p on p.id=l.other where not coalesce(p.is_banned,false) order by l.created_at desc;
$$;
revoke all on function public.dm_conversations() from public,anon;
grant execute on function public.dm_conversations() to authenticated;
create or replace function public.search_pilot_candidates(p_kind text,p_query text default '') returns setof jsonb
language plpgsql stable security definer set search_path=public,pg_temp as $$
begin
  if not social_admin() then raise exception 'Admin only' using errcode='42501'; end if;
  if p_kind in ('creator','participant') then
    return query select jsonb_build_object('id',p.id,'label',concat_ws(' · ',p.username,p.full_name)) from profiles p
      where not coalesce(p.is_banned,false) and concat_ws(' ',p.username,p.full_name,p.id::text) ilike '%'||left(coalesce(p_query,''),80)||'%' order by p.username limit 20;
  elsif p_kind='venue' then
    return query select jsonb_build_object('id',v.ref,'label',v.name) from venue_catalog v
      where v.name ilike '%'||left(coalesce(p_query,''),80)||'%' order by v.name limit 20;
  elsif p_kind='content' then
    return query select jsonb_build_object('id',p.id,'label',left(coalesce(p.caption,'Нийтлэл'),80)) from posts p
      where can_view_author(p.user_id) and p.venue_ref is not null and coalesce(p.caption,'') ilike '%'||left(coalesce(p_query,''),80)||'%'
      order by p.created_at desc limit 20;
  else raise exception 'Invalid kind' using errcode='22023'; end if;
end $$;
revoke all on function public.search_pilot_candidates(text,text) from public,anon;
grant execute on function public.search_pilot_candidates(text,text) to authenticated;
notify pgrst,'reload schema';
commit;
