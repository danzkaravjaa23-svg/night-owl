-- Synthetic database only. Run using run_featured_events_fixture.py.
create role anon nologin;
create role authenticated nologin;
create schema auth;
create function auth.uid() returns uuid language sql stable as $$
  select nullif(current_setting('request.jwt.claim.sub', true), '')::uuid;
$$;
create function auth.jwt() returns jsonb language sql stable as $$
  select jsonb_build_object('role', current_setting('role', true));
$$;
grant usage on schema auth to anon, authenticated;
grant execute on all functions in schema auth to anon, authenticated;

create table public.profiles (
  id uuid primary key, username text,
  is_admin boolean default false, is_banned boolean default false,
  is_verified boolean default false
);
create table public.venues (id uuid primary key, name text);
create table public.events (
  id uuid primary key, title text, description text, cover_url text,
  starts_at timestamptz not null, ends_at timestamptz, price integer default 0,
  attendee_count integer default 0, venue_id uuid references public.venues(id),
  organizer_id uuid references public.profiles(id)
);
create function public.is_admin() returns boolean
language sql stable security definer set search_path=public,pg_temp as $$
  select coalesce((select is_admin from public.profiles where id=auth.uid()),false);
$$;
alter table public.profiles enable row level security;
create policy profile_read on public.profiles for select using (true);
create policy profile_edit on public.profiles for update
using (id=auth.uid() or public.is_admin());
create policy profile_add on public.profiles for insert with check (id=auth.uid());
alter table public.events enable row level security;
create policy events_read on public.events for select using (true);
create policy events_add on public.events for insert
with check (organizer_id=auth.uid());
grant select, insert, update on public.profiles to authenticated;
grant select on public.profiles, public.events, public.venues to anon, authenticated;
grant insert on public.events to authenticated;

insert into public.profiles(id, username, is_admin, is_banned) values
('10000000-0000-0000-0000-000000000001','ordinary-organizer',false,false),
('10000000-0000-0000-0000-000000000002','night-owl-admin',true,false),
('10000000-0000-0000-0000-000000000003','banned-admin',true,true);
insert into public.events(id,title,starts_at,ends_at,organizer_id) values
('20000000-0000-0000-0000-000000000001','future-one',now()+interval '1 day',null,'10000000-0000-0000-0000-000000000001'),
('20000000-0000-0000-0000-000000000002','future-two',now()+interval '2 days',null,'10000000-0000-0000-0000-000000000001'),
('20000000-0000-0000-0000-000000000003','ongoing',now()-interval '1 hour',now()+interval '1 hour','10000000-0000-0000-0000-000000000001'),
('20000000-0000-0000-0000-000000000004','expired',now()-interval '2 days',null,'10000000-0000-0000-0000-000000000001');

create function public.fixture_assert(condition boolean, message text)
returns void language plpgsql as $$
begin
  if condition is not true then raise exception 'ASSERTION FAILED: %', message; end if;
end;
$$;
