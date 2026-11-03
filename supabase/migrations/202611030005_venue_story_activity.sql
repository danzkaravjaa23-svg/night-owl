-- A viewer's map activity is derived only from stories that viewer can read.
-- This adds no table policies, grants on story rows, or application-data writes.
begin;
set local lock_timeout = '5s';
set local statement_timeout = '60s';

create index if not exists stories_daily_venue_activity
  on public.stories (created_at desc, expires_at)
  where venue_ref is not null or venue_id is not null;

create or replace function public.venue_story_activity_today()
returns table (
  venue_ref text,
  story_count bigint,
  activity_day date,
  next_expiry timestamptz
)
language sql stable security invoker
set search_path = public, pg_temp
as $$
  with clock as (
    select now() as observed_at,
      (now() at time zone 'Asia/Ulaanbaatar')::date as local_day,
      date_trunc('day', now() at time zone 'Asia/Ulaanbaatar')
        at time zone 'Asia/Ulaanbaatar' as day_start
  )
  select coalesce(s.venue_ref, s.venue_id::text), count(*), c.local_day,
    min(s.expires_at)
  from public.stories s
  join public.profiles author on author.id = s.user_id
  cross join clock c
  where (s.venue_ref is not null or s.venue_id is not null)
    and s.created_at >= c.day_start
    and s.created_at <= c.observed_at
    and s.expires_at > c.observed_at
    and not coalesce(author.is_banned, false)
    and (auth.uid() is null or public.social_active())
  group by coalesce(s.venue_ref, s.venue_id::text), c.local_day
  order by coalesce(s.venue_ref, s.venue_id::text);
$$;

revoke all on function public.venue_story_activity_today() from public;
grant execute on function public.venue_story_activity_today() to anon, authenticated;

comment on function public.venue_story_activity_today() is
  'Today in Asia/Ulaanbaatar: unexpired, nonfuture, readable location-tagged stories; caller RLS remains authoritative.';

-- Fail the transaction if a hosted prerequisite or API boundary is missing.
do $$
begin
  if not exists (
    select 1 from pg_class c join pg_namespace n on n.oid = c.relnamespace
    where n.nspname = 'public' and c.relname = 'stories' and c.relrowsecurity
  ) or not exists (
    select 1 from pg_policy
    where polrelid = 'public.stories'::regclass
      and polname = 'social_stories_read' and not polpermissive
      and polcmd = 'r'
  ) then
    raise exception 'Venue activity requires the existing restrictive story RLS';
  end if;
  if not exists (
    select 1 from pg_proc
    where oid = 'public.venue_story_activity_today()'::regprocedure
      and not prosecdef and provolatile = 's'
      and proconfig @> array['search_path=public, pg_temp']
  ) or not has_function_privilege('anon', 'public.venue_story_activity_today()', 'execute')
    or not has_function_privilege('authenticated', 'public.venue_story_activity_today()', 'execute')
    or exists (
      select 1 from pg_proc p cross join lateral aclexplode(p.proacl) a
      where p.oid = 'public.venue_story_activity_today()'::regprocedure
        and a.grantee = 0 and a.privilege_type = 'EXECUTE'
    ) then
    raise exception 'Venue story activity API permissions are invalid';
  end if;
end $$;

commit;
