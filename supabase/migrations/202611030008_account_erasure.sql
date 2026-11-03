-- Durable, service-only account erasure coordination. Installs no deletion job
-- and does not delete existing application/Auth/Storage rows.
begin;
set local lock_timeout='5s';
set local statement_timeout='60s';

do $$ begin
  if to_regprocedure('public.social_active()') is null or not exists(
    select 1 from pg_constraint c where c.contype='f'
      and c.conrelid='public.profiles'::regclass
      and c.confrelid='auth.users'::regclass and c.confdeltype='c'
      and pg_get_constraintdef(c.oid) like 'FOREIGN KEY (id) REFERENCES auth.users(id)%'
  ) then raise exception 'Account erasure requires the audited Auth-to-profile cascade'; end if;
  if not exists(select 1 from pg_roles where rolname='service_role') then
    raise exception 'Service role prerequisite missing';
  end if;
end $$;

-- Refuse a schema that could retain person-owned rows or cascade a shared
-- venue/group through a changed FK. These are the 69 relationships captured
-- read-only from the existing deployment on 2026-11-03; names are not assumed.
do $$ declare f record; begin
  for f in select * from (values
    ('blocks', 'blocked_id', 'public.profiles', 'id', 'c'),
    ('blocks', 'blocker_id', 'public.profiles', 'id', 'c'),
    ('checkins', 'user_id', 'public.profiles', 'id', 'c'),
    ('checkins', 'venue_id', 'public.venues', 'id', 'c'),
    ('collection_places', 'collection_id', 'public.place_collections', 'id', 'c'),
    ('collection_places', 'venue_ref', 'public.venue_catalog', 'ref', 'c'),
    ('comment_likes', 'comment_id', 'public.comments', 'id', 'c'),
    ('comment_likes', 'user_id', 'public.profiles', 'id', 'c'),
    ('comments', 'parent_id', 'public.comments', 'id', 'c'),
    ('comments', 'post_id', 'public.posts', 'id', 'c'),
    ('comments', 'user_id', 'public.profiles', 'id', 'c'),
    ('discovery_activity', 'user_id', 'public.profiles', 'id', 'c'),
    ('dm_requests', 'requester_id', 'public.profiles', 'id', 'c'),
    ('dm_requests', 'target_id', 'public.profiles', 'id', 'c'),
    ('event_features', 'event_id', 'public.events', 'id', 'c'),
    ('event_features', 'selected_by', 'public.profiles', 'id', 'n'),
    ('event_rsvps', 'event_id', 'public.events', 'id', 'c'),
    ('event_rsvps', 'user_id', 'public.profiles', 'id', 'c'),
    ('events', 'organizer_id', 'public.profiles', 'id', 'n'),
    ('events', 'venue_id', 'public.venues', 'id', 'c'),
    ('follow_requests', 'requester_id', 'public.profiles', 'id', 'c'),
    ('follow_requests', 'target_id', 'public.profiles', 'id', 'c'),
    ('follows', 'follower_id', 'public.profiles', 'id', 'c'),
    ('follows', 'following_id', 'public.profiles', 'id', 'c'),
    ('group_chats', 'created_by', 'public.profiles', 'id', 'n'),
    ('group_members', 'group_id', 'public.group_chats', 'id', 'c'),
    ('group_members', 'user_id', 'public.profiles', 'id', 'c'),
    ('group_messages', 'group_id', 'public.group_chats', 'id', 'c'),
    ('group_messages', 'sender_id', 'public.profiles', 'id', 'c'),
    ('likes', 'post_id', 'public.posts', 'id', 'c'),
    ('likes', 'user_id', 'public.profiles', 'id', 'c'),
    ('live_comments', 'stream_id', 'public.live_streams', 'id', 'c'),
    ('live_comments', 'user_id', 'public.profiles', 'id', 'c'),
    ('live_streams', 'user_id', 'public.profiles', 'id', 'c'),
    ('live_streams', 'venue_id', 'public.venues', 'id', 'n'),
    ('messages', 'receiver_id', 'public.profiles', 'id', 'c'),
    ('messages', 'sender_id', 'public.profiles', 'id', 'c'),
    ('messages', 'venue_ref', 'public.venue_catalog', 'ref', 'a'),
    ('notes', 'user_id', 'public.profiles', 'id', 'c'),
    ('notes', 'venue_id', 'public.venues', 'id', 'n'),
    ('notifications', 'actor_id', 'public.profiles', 'id', 'c'),
    ('notifications', 'post_id', 'public.posts', 'id', 'c'),
    ('notifications', 'user_id', 'public.profiles', 'id', 'c'),
    ('pilot_content', 'post_id', 'public.posts', 'id', 'c'),
    ('pilot_creators', 'user_id', 'public.profiles', 'id', 'c'),
    ('pilot_participants', 'user_id', 'public.profiles', 'id', 'c'),
    ('pilot_venues', 'venue_ref', 'public.venue_catalog', 'ref', 'c'),
    ('place_collections', 'user_id', 'public.profiles', 'id', 'c'),
    ('posts', 'user_id', 'public.profiles', 'id', 'c'),
    ('posts', 'venue_id', 'public.venues', 'id', 'n'),
    ('posts', 'venue_ref', 'public.venue_catalog', 'ref', 'a'),
    ('profiles', 'id', 'auth.users', 'id', 'c'),
    ('reports', 'reporter_id', 'public.profiles', 'id', 'c'),
    ('saved_posts', 'post_id', 'public.posts', 'id', 'c'),
    ('saved_posts', 'user_id', 'public.profiles', 'id', 'c'),
    ('stories', 'user_id', 'public.profiles', 'id', 'c'),
    ('stories', 'venue_id', 'public.venues', 'id', 'n'),
    ('stories', 'venue_ref', 'public.venue_catalog', 'ref', 'a'),
    ('story_likes', 'story_id', 'public.stories', 'id', 'c'),
    ('story_likes', 'user_id', 'auth.users', 'id', 'c'),
    ('story_views', 'story_id', 'public.stories', 'id', 'c'),
    ('story_views', 'viewer_id', 'public.profiles', 'id', 'c'),
    ('venue_catalog', 'reviewed_by', 'public.profiles', 'id', 'n'),
    ('venue_catalog', 'venue_id', 'public.venues', 'id', 'c'),
    ('venue_reviews', 'user_id', 'public.profiles', 'id', 'c'),
    ('venue_reviews', 'venue_id', 'public.venues', 'id', 'c'),
    ('venue_saves', 'user_id', 'public.profiles', 'id', 'c'),
    ('venue_saves', 'venue_ref', 'public.venue_catalog', 'ref', 'c'),
    ('venues', 'owner_id', 'public.profiles', 'id', 'n')
  ) expected(table_name,column_name,target_table,target_column,delete_action) loop
    if not exists(select 1 from pg_constraint c
      where c.contype='f' and c.conrelid=format('public.%I',f.table_name)::regclass
        and c.confrelid=f.target_table::regclass and c.confdeltype=f.delete_action::"char"
        and c.conkey=array[(select attnum from pg_attribute where attrelid=c.conrelid and attname=f.column_name and not attisdropped)]::smallint[]
        and c.confkey=array[(select attnum from pg_attribute where attrelid=c.confrelid and attname=f.target_column and not attisdropped)]::smallint[]
    ) then raise exception 'Account erasure schema drift: %.%',f.table_name,f.column_name; end if;
  end loop;
end $$;

create schema if not exists account_private;
revoke all on schema account_private from public,anon,authenticated;
create table if not exists account_private.erasure_jobs(
  user_id uuid primary key,
  state text not null check(state in ('prepared','running','failed','completed')),
  receipt_hash text not null unique check(receipt_hash ~ '^[a-f0-9]{64}$'),
  nonce_hash text check(nonce_hash ~ '^[a-f0-9]{64}$'),
  nonce_expires_at timestamptz,
  apple_subject text,
  apple_audience text,
  apple_revoked_at timestamptz,
  lease_id uuid,
  lease_until timestamptz,
  storage_cleared_at timestamptz,
  database_cleared_at timestamptz,
  completed_at timestamptz,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);
alter table account_private.erasure_jobs enable row level security;
revoke all on account_private.erasure_jobs from public,anon,authenticated,service_role;
comment on table account_private.erasure_jobs is
  'Service-only erasure recovery journal; no raw credentials/tokens/content. Completed entries pruned after 30 days by service-only prune action. Active/failed jobs freeze account writes until deliberate recovery.';

-- Changing this shared predicate only tightens existing account/write gates.
create or replace function public.social_active() returns boolean
language sql stable security definer set search_path=public,pg_temp as $$
  select exists(select 1 from public.profiles where id=auth.uid() and not coalesce(is_banned,false))
    and not exists(select 1 from account_private.erasure_jobs
      where user_id=auth.uid() and state in ('running','failed','completed'));
$$;

create or replace function public.account_erasure_write_guard() returns trigger
language plpgsql security definer set search_path=pg_catalog,public,pg_temp as $$
declare actor uuid:=auth.uid();
begin
  -- Maintenance/Auth cascades use their existing trusted server role.
  if actor is null then
    if tg_op='DELETE' then return old; else return new; end if;
  end if;
  -- A claim takes FOR UPDATE on this same row. Existing DB writes finish
  -- before erasure starts; later writes wait, observe the job and are refused.
  perform 1 from public.profiles where id=actor for key share;
  if not found then
    -- Preserve legitimate self-bootstrap for an Auth user whose profile has
    -- not been created yet. An erased user's old JWT cannot recreate a row.
    if tg_table_schema='public' and tg_table_name='profiles' and tg_op='INSERT' then
      if new.id=actor and not exists(select 1 from account_private.erasure_jobs where user_id=actor and state in ('running','failed','completed')) then
        perform 1 from auth.users where id=actor for key share;
        if found then return new; end if;
      end if;
    end if;
    raise exception 'Account profile unavailable' using errcode='42501';
  end if;
  if exists(select 1 from account_private.erasure_jobs
    where user_id=actor and state in ('running','failed','completed')) then
    raise exception 'Account erasure in progress' using errcode='42501';
  end if;
  if tg_op='DELETE' then return old; else return new; end if;
end $$;
revoke all on function public.account_erasure_write_guard() from public,anon,authenticated;

do $$ declare r record; begin
  for r in select c.oid,n.nspname,c.relname from pg_class c join pg_namespace n on n.oid=c.relnamespace
    where c.relkind='r' and n.nspname='public'
    union all select c.oid,n.nspname,c.relname from pg_class c join pg_namespace n on n.oid=c.relnamespace
      where c.relkind='r' and n.nspname='storage' and c.relname='objects'
  loop
    execute format('drop trigger if exists account_erasure_write_guard on %I.%I',r.nspname,r.relname);
    execute format('create trigger account_erasure_write_guard before insert or update or delete on %I.%I for each row execute function public.account_erasure_write_guard()',r.nspname,r.relname);
  end loop;
end $$;

create or replace function public.account_erasure_control(
  p_action text,p_user uuid default null,p_receipt_hash text default null,
  p_nonce_hash text default null,p_audience text default null,
  p_subject text default null,p_lease uuid default null
) returns jsonb
language plpgsql security definer set search_path=pg_catalog,public,pg_temp as $$
declare j account_private.erasure_jobs%rowtype; owner_expression text; inventory jsonb; conflicts boolean;
begin
  if p_action='prune' then
    delete from account_private.erasure_jobs where state='completed' and completed_at<now()-interval '30 days';
    return jsonb_build_object('ok',true);
  end if;
  if p_action='lookup' then
    select * into j from account_private.erasure_jobs where user_id=p_user;
    if not found then return jsonb_build_object('state',null); end if;
    return to_jsonb(j)-'receipt_hash'-'lease_id';
  end if;
  if p_action='storage_inventory' then
    if p_user is null then raise exception 'Account missing' using errcode='22023'; end if;
    if exists(select 1 from pg_attribute where attrelid='storage.objects'::regclass and attname='owner_id' and not attisdropped) then
      owner_expression:='nullif(owner_id::text,'''')';
      if exists(select 1 from pg_attribute where attrelid='storage.objects'::regclass and attname='owner' and not attisdropped) then
        owner_expression:='coalesce(nullif(owner_id::text,''''),owner::text)';
      end if;
    elsif exists(select 1 from pg_attribute where attrelid='storage.objects'::regclass and attname='owner' and not attisdropped) then
      owner_expression:='owner::text';
    else raise exception 'Storage ownership metadata is unavailable'; end if;
    execute format('select exists(select 1 from storage.objects where bucket_id in (''avatars'',''posts'',''stories'',''venues'') and starts_with(name,$1||''/'') and %s is not null and %s<>$1)',owner_expression,owner_expression)
      into conflicts using p_user::text;
    if conflicts then raise exception 'Legacy prefix has conflicting object ownership'; end if;
    execute format('select coalesce(jsonb_agg(jsonb_build_object(''bucket_id'',bucket_id,''name'',name)),''[]''::jsonb) from (select bucket_id,name from storage.objects where %s=$1 order by bucket_id,name limit 80001) o',owner_expression)
      into inventory using p_user::text;
    if jsonb_array_length(inventory)>80000 then raise exception 'Storage ownership inventory limit exceeded'; end if;
    return jsonb_build_object('objects',inventory);
  end if;
  if p_action='prepare' then
    if p_user is null or p_receipt_hash is null or p_receipt_hash !~ '^[a-f0-9]{64}$'
      or (p_nonce_hash is not null and (p_nonce_hash !~ '^[a-f0-9]{64}$'
        or p_audience is null or length(p_audience) not between 1 and 200
        or p_subject is null or length(p_subject) not between 1 and 255)) then
      raise exception 'Invalid erasure preparation' using errcode='22023';
    end if;
    perform 1 from public.profiles where id=p_user for update;
    if not found then raise exception 'Account missing' using errcode='P0002'; end if;
    select * into j from account_private.erasure_jobs where user_id=p_user for update;
    if found and (j.state='completed' or (j.state='running' and j.lease_until>now())) then
      raise exception 'Erasure already running' using errcode='55P03';
    end if;
    insert into account_private.erasure_jobs(user_id,state,receipt_hash,nonce_hash,nonce_expires_at,apple_subject,apple_audience)
      values(p_user,'prepared',p_receipt_hash,p_nonce_hash,case when p_nonce_hash is not null then now()+interval '5 minutes' end,p_subject,p_audience)
      on conflict(user_id) do update set receipt_hash=excluded.receipt_hash,
        nonce_hash=excluded.nonce_hash,nonce_expires_at=excluded.nonce_expires_at,
        apple_revoked_at=case when excluded.nonce_hash is null and erasure_jobs.apple_subject is not distinct from excluded.apple_subject
          then erasure_jobs.apple_revoked_at else null end,
        apple_subject=excluded.apple_subject,apple_audience=excluded.apple_audience,
        updated_at=now()
      returning * into j;
    -- Failed/running expired state is deliberately not reset to prepared:
    -- partial erasure stays frozen until a retry completes.
  else
    if p_action='claim' then
      -- Match prepare's lock order: profile first, journal second. The first
      -- receipt lookup is deliberately nonlocking; re-check it under the job
      -- lock after waiting, so a concurrent preparation can rotate safely.
      select user_id into j.user_id from account_private.erasure_jobs
        where receipt_hash=p_receipt_hash and (p_user is null or user_id=p_user);
      if not found then raise exception 'Erasure receipt not found' using errcode='P0002'; end if;
      perform 1 from public.profiles where id=j.user_id for update;
      if not found then raise exception 'Account missing' using errcode='P0002'; end if;
    end if;
    select * into j from account_private.erasure_jobs
      where receipt_hash=p_receipt_hash and (p_user is null or user_id=p_user) for update;
    if not found then raise exception 'Erasure receipt not found' using errcode='P0002'; end if;
    if p_action='reconcile' then
      if j.storage_cleared_at is not null and j.database_cleared_at is not null
        and not exists(select 1 from auth.users where id=j.user_id)
        and (j.apple_subject is null or j.apple_revoked_at is not null) then
        update account_private.erasure_jobs set state='completed',completed_at=coalesce(completed_at,now()),
          lease_id=null,lease_until=null,nonce_hash=null,nonce_expires_at=null,
          apple_subject=null,apple_audience=null,updated_at=now() where user_id=j.user_id returning * into j;
      end if;
    elsif p_action='claim' then
      if p_lease is null or j.state='completed' or (j.state='running' and j.lease_until>now() and j.lease_id is distinct from p_lease) then
        raise exception 'Erasure already running' using errcode='55P03'; end if;
      update account_private.erasure_jobs set state='running',lease_id=p_lease,
        lease_until=now()+interval '2 minutes',updated_at=now() where user_id=j.user_id returning * into j;
    elsif p_action<>'status' then
      if p_lease is null or j.lease_id is distinct from p_lease or j.lease_until<=now() or j.state<>'running' then
        raise exception 'Erasure lease expired' using errcode='55P03'; end if;
      if p_action='renew' then
        update account_private.erasure_jobs set lease_until=now()+interval '2 minutes',updated_at=now() where user_id=j.user_id returning * into j;
      elsif p_action='apple_revoked' then
        update account_private.erasure_jobs set apple_revoked_at=now(),nonce_hash=null,nonce_expires_at=null,updated_at=now() where user_id=j.user_id returning * into j;
      elsif p_action='storage_cleared' then
        update account_private.erasure_jobs set storage_cleared_at=now(),updated_at=now() where user_id=j.user_id returning * into j;
      elsif p_action='cleanup' then
        if j.storage_cleared_at is null or (j.apple_subject is not null and j.apple_revoked_at is null) then
          raise exception 'Erasure prerequisites not completed' using errcode='22023'; end if;
        -- events are the member's authored content; shared venue records and
        -- other members' posts/reviews/events must never cascade away here.
        delete from public.events where organizer_id=j.user_id;
        update public.venues set owner_id=null,
          cover_url=case when position('/'||j.user_id::text||'/' in coalesce(cover_url,''))>0 then null else cover_url end
          where owner_id=j.user_id;
        update public.venue_catalog set cover_url=null
          where position('/'||j.user_id::text||'/' in coalesce(cover_url,''))>0;
        update public.stories set mentions=array_remove(mentions,j.user_id) where j.user_id=any(mentions);
        update public.messages set story_media_url=null,note_text=null
          where position('/'||j.user_id::text||'/' in coalesce(story_media_url,''))>0;
        delete from public.reports where reporter_id=j.user_id
          or (target_type='user' and target_id=j.user_id)
          or (target_type='post' and target_id in(select id from public.posts where user_id=j.user_id))
          or (target_type='comment' and target_id in(select id from public.comments where user_id=j.user_id))
          or (target_type='story' and target_id in(select id from public.stories where user_id=j.user_id))
          or (target_type='message' and target_id in(select id from public.messages where sender_id=j.user_id or receiver_id=j.user_id));
        -- Keep shared groups and other members' messages; empty groups have no
        -- remaining community content. Auth/profile FK cascade removes the
        -- erased member's group membership and authored messages.
        delete from public.group_chats g where g.created_by=j.user_id
          and not exists(select 1 from public.group_members m where m.group_id=g.id and m.user_id<>j.user_id);
        update public.group_chats set created_by=null where created_by=j.user_id;
        update account_private.erasure_jobs set database_cleared_at=now(),updated_at=now() where user_id=j.user_id returning * into j;
      elsif p_action='completed' then
        if j.storage_cleared_at is null or j.database_cleared_at is null or exists(select 1 from auth.users where id=j.user_id) then
          raise exception 'Auth erasure not completed' using errcode='22023'; end if;
        update account_private.erasure_jobs set state='completed',completed_at=now(),
          lease_id=null,lease_until=null,nonce_hash=null,nonce_expires_at=null,
          apple_subject=null,apple_audience=null,updated_at=now() where user_id=j.user_id returning * into j;
      elsif p_action='failed' then
        update account_private.erasure_jobs set state='failed',lease_id=null,lease_until=null,updated_at=now() where user_id=j.user_id returning * into j;
      else raise exception 'Unknown erasure action' using errcode='22023'; end if;
    end if;
  end if;
  return to_jsonb(j)-'receipt_hash'-'lease_id';
end $$;
revoke all on function public.account_erasure_control(text,uuid,text,text,text,text,uuid) from public,anon,authenticated;
grant execute on function public.account_erasure_control(text,uuid,text,text,text,text,uuid) to service_role;

notify pgrst,'reload schema';
commit;
