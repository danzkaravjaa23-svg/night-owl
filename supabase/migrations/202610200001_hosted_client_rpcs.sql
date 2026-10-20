-- Hosted Supabase follow-up to social discovery. Review/backup before applying.
-- Existing groups/messages remain intact. Never replace an unknown RPC.
begin;
set local lock_timeout = '5s';
set local statement_timeout = '60s';

do $$
begin
  if to_regprocedure('public.social_active()') is null or
      to_regprocedure('auth.role()') is null then
    raise exception 'Apply and verify social discovery first';
  end if;
  if to_regprocedure('public.create_group(text,uuid[])') is not null or
      to_regprocedure('public.check_in_venue(uuid)') is not null then
    raise exception 'Existing client RPC requires explicit implementation review';
  end if;
  if exists(select 1 from pg_class where oid in (
      'public.group_chats'::regclass, 'public.group_members'::regclass,
      'public.group_messages'::regclass) and (not relrowsecurity or relforcerowsecurity)) then
    raise exception 'Review group RLS before applying';
  end if;
end $$;

-- Hosted projects can grant ALL to API roles through default privileges.
-- Keep the social tables' intended narrow contract, including non-DML rights.
revoke all on public.follow_requests,public.dm_requests,public.venue_catalog,
  public.venue_saves,public.place_collections,public.collection_places,
  public.discovery_activity,public.pilot_creators,public.pilot_participants,
  public.pilot_venues,public.pilot_content from public,anon,authenticated;
grant select on public.follow_requests,public.dm_requests to authenticated;
grant select on public.venue_catalog to anon,authenticated;
grant select,insert,delete on public.venue_saves to authenticated;
grant select on public.place_collections,public.collection_places to anon,authenticated;
grant insert,update,delete on public.place_collections,public.collection_places to authenticated;

create function public.social_group_member(p_group uuid) returns boolean
language sql stable security definer set search_path = '' as $$
  select public.social_active() and exists (
    select 1 from public.group_members m
    where m.group_id=p_group and m.user_id=auth.uid()
  );
$$;
create function public.social_group_can_add(p_group uuid,p_user uuid) returns boolean
language sql stable security definer set search_path = '' as $$
  select public.social_group_member(p_group)
    and exists(select 1 from public.group_chats g where g.id=p_group and g.created_by=auth.uid())
    and exists(select 1 from public.profiles p where p.id=p_user and not coalesce(p.is_banned,false))
    and not exists(select 1 from public.group_members m
      where m.group_id=p_group and public.social_pair_blocked(m.user_id,p_user));
$$;
revoke all on function public.social_group_member(uuid),public.social_group_can_add(uuid,uuid) from public,anon;
grant execute on function public.social_group_member(uuid),public.social_group_can_add(uuid,uuid) to authenticated;

-- The definer helper checks only the caller's membership, avoiding recursive RLS.
create policy hosted_group_read on public.group_chats as restrictive
  for select to authenticated using(public.social_group_member(id));
create policy hosted_group_members_read on public.group_members as restrictive
  for select to authenticated using(public.social_group_member(group_id));
create policy hosted_group_messages_read on public.group_messages as restrictive
  for select to authenticated using(public.social_group_member(group_id));
create policy hosted_group_anon_read on public.group_chats as restrictive for select to anon using(false);
create policy hosted_group_members_anon_read on public.group_members as restrictive for select to anon using(false);
create policy hosted_group_messages_anon_read on public.group_messages as restrictive for select to anon using(false);
create policy hosted_group_create on public.group_chats as restrictive for insert to authenticated with check(false);
create policy hosted_group_members_add on public.group_members as restrictive for insert to authenticated
  with check(public.social_group_can_add(group_id,user_id));
create policy hosted_group_members_update on public.group_members as restrictive for update to authenticated
  using(false) with check(false);
create policy hosted_group_leave on public.group_members for delete to authenticated
  using(user_id=auth.uid() and public.social_active());
create policy hosted_group_leave_guard on public.group_members as restrictive for delete to authenticated
  using(user_id=auth.uid() and public.social_active());
create policy hosted_group_send on public.group_messages as restrictive for insert to authenticated
  with check(public.social_group_member(group_id) and sender_id=auth.uid());

create function public.create_group(p_name text,p_member_ids uuid[]) returns uuid
language plpgsql security definer set search_path = '' as $$
declare
  v_user uuid := auth.uid();
  v_group uuid := pg_catalog.gen_random_uuid();
  v_members uuid[];
  v_count integer;
begin
  if v_user is null or auth.role() is distinct from 'authenticated' then
    raise exception 'Authentication required' using errcode='42501';
  end if;
  if pg_catalog.current_setting('transaction_isolation') is distinct from 'read committed' then
    raise exception 'create_group requires READ COMMITTED isolation' using errcode='25000';
  end if;
  if p_name is null or pg_catalog.btrim(p_name)='' or p_member_ids is null or
      pg_catalog.array_ndims(p_member_ids)>1 or pg_catalog.array_position(p_member_ids,null::uuid) is not null then
    raise exception 'A name and valid member IDs are required' using errcode='22023';
  end if;
  select pg_catalog.array_agg(m.member_id order by m.member_id) into v_members
    from (select distinct unnest(p_member_ids||array[v_user]) as member_id) m;
  if pg_catalog.cardinality(v_members)<2 then
    raise exception 'Select at least one other member' using errcode='22023';
  end if;
  -- Match ordinary block writes' lock ordering before locking profile rows.
  lock table public.blocks in share mode;
  perform p.id from public.profiles p where p.id=any(v_members) and not coalesce(p.is_banned,false)
    order by p.id for share;
  get diagnostics v_count = row_count;
  if v_count<>pg_catalog.cardinality(v_members) or exists (
      select 1 from public.blocks b where b.blocker_id=any(v_members) and b.blocked_id=any(v_members)) then
    raise exception 'One or more members unavailable' using errcode='42501';
  end if;
  insert into public.group_chats(id,name,created_by,created_at)
    values(v_group,pg_catalog.btrim(p_name),v_user,pg_catalog.now());
  insert into public.group_members(group_id,user_id,joined_at)
    select v_group,m.member_id,pg_catalog.now() from unnest(v_members) m(member_id);
  return v_group;
end $$;

create function public.check_in_venue(p_venue_id uuid)
returns table(venue_id uuid,expires_at timestamptz)
language plpgsql security definer set search_path = '' as $$
declare
  v_user uuid := auth.uid();
  v_expiry timestamptz := pg_catalog.now()+interval '4 hours';
begin
  if v_user is null or auth.role() is distinct from 'authenticated' then
    raise exception 'Authentication required' using errcode='42501';
  end if;
  if pg_catalog.current_setting('transaction_isolation') is distinct from 'read committed' then
    raise exception 'check_in_venue requires READ COMMITTED isolation' using errcode='25000';
  end if;
  perform p.id from public.profiles p where p.id=v_user and not coalesce(p.is_banned,false) for update;
  if not found then raise exception 'Active profile required' using errcode='42501'; end if;
  perform v.id from public.venues v where v.id=p_venue_id and v.name !~ ' #[0-9]+$';
  if not found then raise exception 'Venue not found' using errcode='22023'; end if;
  -- Existing counter triggers touch both old and new venues; lock in one order.
  perform v.id from public.venues v where v.id in (
    select c.venue_id from public.checkins c where c.user_id=v_user union select p_venue_id
  ) order by v.id for update;
  if not exists(select 1 from public.venues v where v.id=p_venue_id and v.name !~ ' #[0-9]+$') then
    raise exception 'Venue not found' using errcode='22023';
  end if;
  delete from public.checkins c where c.user_id=v_user;
  insert into public.checkins(user_id,venue_id,created_at,expires_at)
    values(v_user,p_venue_id,pg_catalog.now(),v_expiry);
  return query select p_venue_id,v_expiry;
end $$;
revoke all on function public.create_group(text,uuid[]),public.check_in_venue(uuid) from public,anon;
grant execute on function public.create_group(text,uuid[]),public.check_in_venue(uuid) to authenticated;
notify pgrst,'reload schema';
commit;
