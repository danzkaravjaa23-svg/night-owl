-- Night Owl: organization-curated Explore events.
-- Requires supabase_protect_profile_flags.sql, events, venues and profiles.
-- Atomic and repeatable. No existing event is automatically selected.
-- PostgreSQL migration targets must retain the existing auth.uid() contract.
begin;

do $$
begin
  if not exists (
    select 1 from pg_catalog.pg_trigger t
    join pg_catalog.pg_proc p on p.oid = t.tgfoid
    join pg_catalog.pg_namespace n on n.oid = p.pronamespace
    where t.tgrelid = 'public.profiles'::regclass
      and not t.tgisinternal and t.tgenabled in ('O', 'A')
      and n.nspname = 'public' and p.proname = 'protect_profile_flags'
      and (t.tgtype::integer & 23) = 23 -- row/before/insert/update
  ) then
    raise exception 'Apply supabase_protect_profile_flags.sql before featured events';
  end if;
end;
$$;

create or replace function public.can_manage_featured_events()
returns boolean
language sql stable security definer
set search_path = public, pg_temp
as $$
  select auth.uid() is not null and exists (
    select 1 from public.profiles p
    where p.id = auth.uid() and p.is_admin is true
      and p.is_banned is not true
  );
$$;
revoke all on function public.can_manage_featured_events() from public;
grant execute on function public.can_manage_featured_events() to anon, authenticated;

-- The legacy profile guard trusts is_admin even after a ban. A banned admin
-- must not reactivate themselves (or promote a second account) to regain the
-- feature RPC. This only tightens changes to these two authorization flags.
create or replace function public.protect_featured_event_admin_flags()
returns trigger
language plpgsql security definer
set search_path = public, pg_temp
as $$
begin
  if auth.uid() is null then return new; end if;
  if not public.can_manage_featured_events() then
    if tg_op = 'INSERT' then
      new.is_admin := false;
      new.is_banned := false;
    else
      new.is_admin := old.is_admin;
      new.is_banned := old.is_banned;
    end if;
  end if;
  return new;
end;
$$;
revoke all on function public.protect_featured_event_admin_flags() from public, anon, authenticated;
drop trigger if exists protect_featured_event_admin_flags on public.profiles;
create trigger protect_featured_event_admin_flags
before insert or update of is_admin, is_banned on public.profiles
for each row execute function public.protect_featured_event_admin_flags();

create table if not exists public.event_features (
  event_id uuid primary key references public.events(id) on delete cascade,
  rank integer not null default 0 check (rank between 0 and 9999),
  selected_by uuid references public.profiles(id) on delete set null,
  selected_at timestamptz not null default now()
);
alter table public.event_features enable row level security;

-- Only the narrow read columns are exposed directly. Mutations always pass
-- through the guarded RPC, even for administrators. Event creation is unchanged.
revoke all on table public.event_features from public, anon, authenticated;
grant select (event_id, rank) on table public.event_features to anon, authenticated;
drop policy if exists "Selected current events readable" on public.event_features;
create policy "Selected current events readable" on public.event_features
for select to anon, authenticated using (
  exists (
    select 1 from public.events e
    where e.id = event_id
      and coalesce(e.ends_at, e.starts_at + interval '8 hours') > now()
  )
);

create or replace function public.get_featured_events()
returns table (
  id uuid, title text, description text, cover_url text,
  starts_at timestamptz, price integer, attendee_count integer,
  venue_name text, organizer_name text
)
language sql stable security invoker
set search_path = public, pg_temp
as $$
  select e.id, e.title, e.description, e.cover_url, e.starts_at,
         e.price, e.attendee_count, v.name, p.username
  from public.event_features f
  join public.events e on e.id = f.event_id
  left join public.venues v on v.id = e.venue_id
  left join public.profiles p on p.id = e.organizer_id
  where coalesce(e.ends_at, e.starts_at + interval '8 hours') > now()
  order by f.rank, e.starts_at, e.id
  limit 60;
$$;
revoke all on function public.get_featured_events() from public;
grant execute on function public.get_featured_events() to anon, authenticated;

create or replace function public.get_admin_featured_events()
returns table (event_id uuid, rank integer)
language plpgsql stable security definer
set search_path = public, pg_temp
as $$
begin
  if not public.can_manage_featured_events() then
    raise exception 'Only active Night Owl administrators may manage featured events'
      using errcode = '42501';
  end if;
  return query select f.event_id, f.rank
    from public.event_features f order by f.rank, f.event_id;
end;
$$;
revoke all on function public.get_admin_featured_events() from public, anon;
grant execute on function public.get_admin_featured_events() to authenticated;

create or replace function public.set_featured_event(
  p_event_id uuid, p_featured boolean, p_rank integer default 0
)
returns void
language plpgsql security definer
set search_path = public, pg_temp
as $$
begin
  if not public.can_manage_featured_events() then
    raise exception 'Only active Night Owl administrators may manage featured events'
      using errcode = '42501';
  end if;
  if p_featured is null or p_rank is null or p_rank not between 0 and 9999 then
    raise exception 'Invalid featured event selection' using errcode = '22023';
  end if;
  if p_featured then
    if not exists (
      select 1 from public.events e where e.id = p_event_id
        and coalesce(e.ends_at, e.starts_at + interval '8 hours') > now()
    ) then
      raise exception 'Select an upcoming or active event' using errcode = '22023';
    end if;
    insert into public.event_features (event_id, rank, selected_by)
      values (p_event_id, p_rank, auth.uid())
      on conflict (event_id) do update
        set rank = excluded.rank, selected_by = excluded.selected_by,
            selected_at = now();
  else
    delete from public.event_features where event_id = p_event_id;
  end if;
end;
$$;
revoke all on function public.set_featured_event(uuid, boolean, integer) from public, anon;
grant execute on function public.set_featured_event(uuid, boolean, integer) to authenticated;

notify pgrst, 'reload schema';
commit;
