-- Readable posts influence a venue for 168 elapsed hours from publication.
-- Posts and their location remain stored after that window; stories retain
-- their existing Ulaanbaatar-day and expiry rules. No row policy is broadened.
begin;
set local lock_timeout = '5s';
set local statement_timeout = '60s';

-- The original publication clock belongs to the server. Existing timestamps
-- are left intact, including historical imports; caption/location/moderation
-- edits cannot restart the activity window. Duplicate-ID insert retries still
-- follow the normal unique-constraint and original-row recovery path.
create or replace function public.protect_post_publication_clock()
returns trigger
language plpgsql security invoker
set search_path = public, pg_temp
as $$
begin
  if tg_op = 'INSERT' then
    new.created_at := now();
  elsif new.created_at is distinct from old.created_at then
    raise exception 'Original post publication time cannot be changed'
      using errcode = '22023';
  end if;
  return new;
end;
$$;

revoke all on function public.protect_post_publication_clock() from public, anon, authenticated;
drop trigger if exists protect_post_publication_clock on public.posts;
create trigger protect_post_publication_clock
  before insert or update on public.posts
  for each row execute function public.protect_post_publication_clock();

create index if not exists posts_weekly_venue_activity
  on public.posts (created_at desc) include (venue_ref, venue_id, user_id)
  where venue_ref is not null or venue_id is not null;

create or replace function public.venue_map_activity()
returns table (
  venue_ref text,
  story_count bigint,
  post_count bigint,
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
  ), contributions as (
    select coalesce(s.venue_ref, s.venue_id::text) as ref,
      count(*) as stories, 0::bigint as posts,
      min(s.expires_at) as expires_at
    from public.stories s
    join public.profiles author on author.id = s.user_id
    cross join clock c
    where (s.venue_ref is not null or s.venue_id is not null)
      and s.created_at >= c.day_start
      and s.created_at <= c.observed_at
      and s.expires_at > c.observed_at
      and not coalesce(author.is_banned, false)
      and (auth.uid() is null or public.social_active())
    group by coalesce(s.venue_ref, s.venue_id::text)
    union all
    select coalesce(p.venue_ref, p.venue_id::text),
      0::bigint, count(*), min(p.created_at + interval '168 hours')
    from public.posts p
    join public.profiles author on author.id = p.user_id
    cross join clock c
    where (p.venue_ref is not null or p.venue_id is not null)
      and p.created_at > c.observed_at - interval '168 hours'
      and p.created_at <= c.observed_at
      and not coalesce(author.is_banned, false)
      and (auth.uid() is null or public.social_active())
    group by coalesce(p.venue_ref, p.venue_id::text)
  )
  select a.ref, sum(a.stories)::bigint, sum(a.posts)::bigint,
    c.local_day, min(a.expires_at)
  from contributions a cross join clock c
  group by a.ref, c.local_day
  order by a.ref;
$$;

revoke all on function public.venue_map_activity() from public;
grant execute on function public.venue_map_activity() to anon, authenticated;

comment on function public.venue_map_activity() is
  'Caller-readable venue activity: today''s unexpired stories in Asia/Ulaanbaatar plus posts published within 168 elapsed hours. Existing post/story RLS remains authoritative; content is never expired or deleted by this API.';
comment on function public.protect_post_publication_clock() is
  'Pins new post created_at to server transaction time and preserves original publication time on all later edits. Does not rewrite existing rows.';

-- A missing privacy prerequisite aborts every DDL change in this transaction.
do $$
declare t text;
begin
  foreach t in array array['posts', 'stories'] loop
    if not exists (
      select 1 from pg_attribute
      where attrelid = format('public.%I', t)::regclass
        and attname = 'created_at' and atttypid = 'timestamptz'::regtype
        and not attisdropped
    ) then
      raise exception 'Venue map activity requires timestamptz %.created_at', t;
    end if;
    if not exists (
      select 1 from pg_class c join pg_namespace n on n.oid = c.relnamespace
      where n.nspname = 'public' and c.relname = t and c.relrowsecurity
    ) or not exists (
      select 1 from pg_policy
      where polrelid = format('public.%I', t)::regclass
        and polname = format('social_%s_read', t)
        and not polpermissive and polcmd = 'r'
    ) then
      raise exception 'Venue map activity requires existing restrictive % RLS', t;
    end if;
  end loop;
  if not exists (
    select 1 from pg_proc
    where oid = 'public.venue_map_activity()'::regprocedure
      and not prosecdef and provolatile = 's'
      and proconfig @> array['search_path=public, pg_temp']
  ) or not has_function_privilege('anon', 'public.venue_map_activity()', 'execute')
    or not has_function_privilege('authenticated', 'public.venue_map_activity()', 'execute')
    or exists (
      select 1 from pg_proc p cross join lateral aclexplode(p.proacl) a
      where p.oid = 'public.venue_map_activity()'::regprocedure
        and a.grantee = 0 and a.privilege_type = 'EXECUTE'
    ) then
    raise exception 'Venue map activity API permissions are invalid';
  end if;
  if not exists (
    select 1 from pg_trigger
    where tgrelid = 'public.posts'::regclass
      and tgname = 'protect_post_publication_clock'
      and tgfoid = 'public.protect_post_publication_clock()'::regprocedure
      and tgenabled = 'O' and tgtype = 23
  ) then
    raise exception 'Post publication clock guard is missing';
  end if;
end;
$$;

commit;
