-- TARGET ONLY: additive RPCs absent from the 2026-10-05 source inventory.
-- Run as the reviewed, nonsuperuser owner of the seven referenced public tables.
-- Do not execute on managed Supabase or substitute this for an authoritative dump.
begin;

do $$
declare
  v_role record;
  v_table text;
  v_column record;
begin
  if current_setting('nightowl.target_rpc_patch', true) is distinct from 'approved-independent-target' then
    raise exception 'Independent-target approval marker required' using errcode = '42501';
  end if;
  select * into strict v_role from pg_catalog.pg_roles where rolname = current_user;
  if v_role.rolsuper or v_role.rolbypassrls or v_role.rolcreaterole or v_role.rolreplication or
      current_user in ('anon', 'authenticated', 'authenticator', 'nightowl_readiness') then
    raise exception 'RPC owner must be a reviewed role without superuser, bypass-RLS, create-role or replication privileges' using errcode = '42501';
  end if;
  if pg_catalog.pg_has_role('authenticator', current_user, 'MEMBER') or
      pg_catalog.pg_has_role('authenticated', current_user, 'MEMBER') or
      pg_catalog.pg_has_role('anon', current_user, 'MEMBER') then
    raise exception 'API roles must not be members of the RPC table-owner role' using errcode = '42501';
  end if;
  foreach v_table in array array['profiles','messages','blocks','group_chats','group_members','venues','checkins']
  loop
    if not exists (
      select 1 from pg_catalog.pg_class c
      where c.oid = pg_catalog.to_regclass('public.' || v_table)
        and c.relkind = 'r' and c.relowner = v_role.oid and c.relrowsecurity and not c.relforcerowsecurity
    ) then
      raise exception 'Expected owned table with enabled, nonforced RLS: %', v_table using errcode = '42501';
    end if;
  end loop;
  for v_column in select * from (values
    ('profiles','id','uuid'), ('profiles','username','text'), ('profiles','avatar_url','text'),
    ('profiles','last_seen_at','timestamp with time zone'), ('profiles','is_banned','boolean'),
    ('messages','id','uuid'), ('messages','sender_id','uuid'), ('messages','receiver_id','uuid'),
    ('messages','body','text'), ('messages','is_read','boolean'), ('messages','created_at','timestamp with time zone'),
    ('blocks','blocker_id','uuid'), ('blocks','blocked_id','uuid'),
    ('group_chats','id','uuid'), ('group_chats','name','text'), ('group_chats','created_by','uuid'),
    ('group_chats','created_at','timestamp with time zone'), ('group_members','group_id','uuid'),
    ('group_members','user_id','uuid'), ('group_members','joined_at','timestamp with time zone'),
    ('venues','id','uuid'), ('venues','name','text'),
    ('checkins','user_id','uuid'), ('checkins','venue_id','uuid'),
    ('checkins','created_at','timestamp with time zone'), ('checkins','expires_at','timestamp with time zone')
  ) as expected(table_name, column_name, type_name)
  loop
    if not exists (
      select 1 from pg_catalog.pg_attribute a
      where a.attrelid = pg_catalog.to_regclass('public.' || v_column.table_name)
        and a.attname = v_column.column_name and not a.attisdropped
        and a.atttypid = pg_catalog.to_regtype(v_column.type_name)
    ) then
      raise exception 'Reviewed column contract missing: %.%', v_column.table_name, v_column.column_name;
    end if;
  end loop;
  if not pg_catalog.has_function_privilege(current_user, 'auth.uid()', 'EXECUTE') or
      not pg_catalog.has_function_privilege(current_user, 'auth.role()', 'EXECUTE') then
    raise exception 'Verified-claims helpers unavailable to RPC owner' using errcode = '42501';
  end if;
end;
$$;

-- Exact output fields consumed by dm_list_screen.dart. No caller-supplied ID.
create function public.dm_conversations()
returns table (
  partner_id uuid, partner_username text, partner_avatar_url text,
  partner_last_seen_at timestamptz, last_body text, last_at timestamptz,
  last_sender_id uuid, unread_count bigint
)
language plpgsql stable security definer set search_path = '' as $$
declare
  v_user uuid := auth.uid();
begin
  if v_user is null or auth.role() is distinct from 'authenticated' then
    raise exception 'Authentication required' using errcode = '42501';
  end if;
  if not exists (select 1 from public.profiles p where p.id = v_user and not coalesce(p.is_banned, false)) then
    raise exception 'Active profile required' using errcode = '42501';
  end if;
  return query
    with relevant as materialized (
      select case when m.sender_id = v_user then m.receiver_id else m.sender_id end as other_id,
        m.id, m.sender_id, m.receiver_id, m.body, m.created_at, m.is_read
      from public.messages m
      where m.sender_id = v_user or m.receiver_id = v_user
    ), latest as (
      select distinct on (r.other_id) r.other_id, r.body, r.created_at, r.sender_id
      from relevant r
      order by r.other_id, r.created_at desc nulls last, r.id desc
    ), unread as (
      select r.other_id, count(*) as amount from relevant r
      where r.receiver_id = v_user and r.sender_id <> v_user and r.is_read is false
      group by r.other_id
    )
    select l.other_id, p.username, p.avatar_url, p.last_seen_at, l.body,
      l.created_at, l.sender_id, coalesce(u.amount, 0::bigint)
    from latest l
    join public.profiles p on p.id = l.other_id and not coalesce(p.is_banned, false)
    left join unread u on u.other_id = l.other_id
    where not exists (
      select 1 from public.blocks b
      where (b.blocker_id = v_user and b.blocked_id = l.other_id) or
        (b.blocker_id = l.other_id and b.blocked_id = v_user)
    )
    order by l.created_at desc nulls last, l.other_id;
end;
$$;

-- Atomic equivalent of the client's group + member inserts, with server guards.
create function public.create_group(p_name text, p_member_ids uuid[])
returns uuid
language plpgsql security definer set search_path = '' as $$
declare
  v_user uuid := auth.uid();
  v_group uuid := pg_catalog.gen_random_uuid();
  v_members uuid[];
  v_count integer;
begin
  if v_user is null or auth.role() is distinct from 'authenticated' then
    raise exception 'Authentication required' using errcode = '42501';
  end if;
  if pg_catalog.current_setting('transaction_isolation') is distinct from 'read committed' then
    raise exception 'create_group requires READ COMMITTED isolation' using errcode = '25000';
  end if;
  if p_name is null or pg_catalog.btrim(p_name) = '' or p_member_ids is null or
      pg_catalog.array_ndims(p_member_ids) > 1 or pg_catalog.array_position(p_member_ids, null::uuid) is not null then
    raise exception 'A name and valid member IDs are required' using errcode = '22023';
  end if;
  select pg_catalog.array_agg(m.member_id order by m.member_id) into v_members
    from (select distinct unnest(p_member_ids || array[v_user]) as member_id) m;
  if pg_catalog.cardinality(v_members) < 2 then
    raise exception 'Select at least one other member' using errcode = '22023';
  end if;
  -- Normal block writes take ROW EXCLUSIVE before their FK profile locks.
  -- Acquire this barrier first, then inspect the newly committed block view.
  -- SHARE permits other group creations while excluding block mutations until
  -- this transaction ends; no table grant or RLS policy is broadened.
  lock table public.blocks in share mode;
  -- Stable ordering prevents opposite selections from taking profile locks in
  -- opposite order. Locks also protect against concurrent profile deletion/ban.
  perform p.id from public.profiles p
    where p.id = any(v_members) and not coalesce(p.is_banned, false)
    order by p.id for share;
  get diagnostics v_count = row_count;
  if v_count <> pg_catalog.cardinality(v_members) then
    raise exception 'One or more members unavailable' using errcode = '42501';
  end if;
  if exists (select 1 from public.blocks b where b.blocker_id = any(v_members) and b.blocked_id = any(v_members)) then
    raise exception 'One or more members unavailable' using errcode = '42501';
  end if;
  insert into public.group_chats(id, name, created_by, created_at)
    values (v_group, pg_catalog.btrim(p_name), v_user, pg_catalog.now());
  insert into public.group_members(group_id, user_id, joined_at)
    select v_group, m.member_id, pg_catalog.now() from unnest(v_members) m(member_id);
  return v_group;
end;
$$;

-- One current venue per caller, matching the existing four-hour client contract.
create function public.check_in_venue(p_venue_id uuid)
returns table(venue_id uuid, expires_at timestamptz)
language plpgsql security definer set search_path = '' as $$
declare
  v_user uuid := auth.uid();
  v_expiry timestamptz := pg_catalog.now() + interval '4 hours';
begin
  if v_user is null or auth.role() is distinct from 'authenticated' then
    raise exception 'Authentication required' using errcode = '42501';
  end if;
  if pg_catalog.current_setting('transaction_isolation') is distinct from 'read committed' then
    raise exception 'check_in_venue requires READ COMMITTED isolation' using errcode = '25000';
  end if;
  -- The existing client migration locks this same profile row. Hold it through
  -- delete + insert so simultaneous calls/devices cannot leave two active rows.
  perform p.id from public.profiles p
    where p.id = v_user and not coalesce(p.is_banned, false) for update;
  if not found then
    raise exception 'Active profile required' using errcode = '42501';
  end if;
  perform v.id from public.venues v where v.id = p_venue_id and v.name !~ ' #[0-9]+$';
  if not found then
    raise exception 'Venue not found' using errcode = '22023';
  end if;
  -- Counter triggers update both old and new venue rows. Lock that union in one
  -- global order before firing either trigger, including expired caller rows.
  -- Locking only the destination first can deadlock opposite-user venue swaps.
  perform v.id from public.venues v
    where v.id in (select c.venue_id from public.checkins c where c.user_id = v_user union select p_venue_id)
    order by v.id for update;
  -- Destination deletion/rename may have committed between validation and locks.
  if not exists (select 1 from public.venues v where v.id = p_venue_id and v.name !~ ' #[0-9]+$') then
    raise exception 'Venue not found' using errcode = '22023';
  end if;
  -- Includes expired rows hidden from API SELECT, preserving existing count
  -- triggers by deleting/inserting rather than silently overwriting the venue.
  delete from public.checkins c where c.user_id = v_user;
  insert into public.checkins(user_id, venue_id, created_at, expires_at)
    values (v_user, p_venue_id, pg_catalog.now(), v_expiry);
  return query select p_venue_id, v_expiry;
end;
$$;

revoke all on function public.dm_conversations(), public.create_group(text,uuid[]), public.check_in_venue(uuid)
  from public, anon, authenticator, nightowl_readiness;
grant execute on function public.dm_conversations(), public.create_group(text,uuid[]), public.check_in_venue(uuid)
  to authenticated;

-- Transactional PostgREST cache reload is delivered only after successful commit.
notify pgrst, 'reload schema';
commit;
