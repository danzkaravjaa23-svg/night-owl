-- FICTIONAL fixtures only; never run against restored/source application data.
do $$
begin
  if current_database() !~ '_rpc_backend_test$' then
    raise exception 'RPC fixtures require an isolated *_rpc_backend_test database';
  end if;
  if to_regclass('public.profiles') is not null or to_regnamespace('auth') is not null then
    raise exception 'RPC fixtures require a new empty disposable database';
  end if;
  if not exists (select 1 from pg_roles where rolname = 'nightowl_rpc_fixture_owner') then
    create role nightowl_rpc_fixture_owner nologin noinherit nosuperuser nocreatedb nocreaterole noreplication nobypassrls;
  end if;
  if exists (select 1 from pg_roles where rolname = 'nightowl_rpc_fixture_owner' and
      (rolcanlogin or rolsuper or rolbypassrls or rolcreaterole or rolreplication)) then
    raise exception 'Fixture owner is unsafe';
  end if;
end;
$$;

\ir ../postgres/init/002-auth-compatibility.sql

grant usage, create on schema public to nightowl_rpc_fixture_owner;
grant usage on schema public to anon, authenticated, authenticator;
grant usage on schema auth to nightowl_rpc_fixture_owner;
grant execute on function auth.uid(), auth.role(), auth.jwt() to nightowl_rpc_fixture_owner;
create table auth.users(id uuid primary key);
alter table auth.users owner to nightowl_rpc_fixture_owner;
set role nightowl_rpc_fixture_owner;

create table public.profiles (
  id uuid primary key references auth.users(id) on delete cascade,
  username text not null unique, avatar_url text, last_seen_at timestamptz,
  is_banned boolean default false, is_admin boolean default false
);
create table public.venues (
  id uuid primary key default gen_random_uuid(), name text not null,
  checkin_count integer default 0
);
create table public.messages (
  id uuid primary key default gen_random_uuid(), sender_id uuid not null references public.profiles(id) on delete cascade,
  receiver_id uuid not null references public.profiles(id) on delete cascade,
  body text not null, is_read boolean default false, created_at timestamptz default now()
);
create table public.blocks (
  blocker_id uuid references public.profiles(id) on delete cascade,
  blocked_id uuid references public.profiles(id) on delete cascade,
  primary key (blocker_id,blocked_id)
);
create table public.group_chats (
  id uuid primary key default gen_random_uuid(), name text not null,
  created_by uuid references public.profiles(id) on delete set null,
  created_at timestamptz default now()
);
create table public.group_members (
  group_id uuid references public.group_chats(id) on delete cascade,
  user_id uuid references public.profiles(id) on delete cascade,
  joined_at timestamptz default now(), primary key (group_id,user_id)
);
create table public.checkins (
  id uuid primary key default gen_random_uuid(), user_id uuid not null references public.profiles(id) on delete cascade,
  venue_id uuid not null references public.venues(id) on delete cascade,
  created_at timestamptz default now(), expires_at timestamptz default (now()+interval '4 hours'),
  unique (user_id,venue_id)
);
alter table public.profiles enable row level security;
alter table public.venues enable row level security;
alter table public.messages enable row level security;
alter table public.blocks enable row level security;
alter table public.group_chats enable row level security;
alter table public.group_members enable row level security;
alter table public.checkins enable row level security;

-- Relevant source policy shapes, deliberately not claimed to be fully safe.
create policy "Public profiles viewable" on public.profiles for select using (true);
create policy "Venues viewable" on public.venues for select using (true);
create policy "Own messages viewable" on public.messages for select using (auth.uid()=sender_id or auth.uid()=receiver_id);
create policy "Own blocks viewable" on public.blocks for select using (auth.uid()=blocker_id);
create policy "Own blocks insert" on public.blocks for insert with check (auth.uid()=blocker_id);
create policy "gc_select" on public.group_chats for select using (
  exists(select 1 from public.group_members m where m.group_id=group_chats.id and m.user_id=auth.uid())
);
create policy "gc_insert" on public.group_chats for insert with check (auth.uid()=created_by);
create policy "gm_select" on public.group_members for select using (true);
create policy "gm_insert" on public.group_members for insert with check (
  auth.uid()=user_id or exists(select 1 from public.group_chats c where c.id=group_members.group_id and c.created_by=auth.uid())
);
create policy "Active checkins viewable" on public.checkins for select using (expires_at>now());
create policy "Own checkins insertable" on public.checkins for insert with check (auth.uid()=user_id);
create policy "Own checkins deletable" on public.checkins for delete using (auth.uid()=user_id);

-- Relevant source body and path behavior preserved exactly: public.venues is
-- qualified, but the source function has no explicit search_path setting.
create function public.update_checkin_count() returns trigger
language plpgsql security definer as $$
begin
  if (tg_op='INSERT') then update public.venues set checkin_count=checkin_count+1 where id=new.venue_id;
  elsif (tg_op='DELETE') then update public.venues set checkin_count=greatest(checkin_count-1,0) where id=old.venue_id; end if;
  return null; end;
$$;
revoke all on function public.update_checkin_count() from public;
create trigger on_checkin_change after insert or delete on public.checkins
  for each row execute function public.update_checkin_count();

-- Force the old-venue counter update/new-venue insert overlap for swap tests.
-- This separate fixture trigger leaves the relevant source counter body intact.
create function public.fixture_pause_after_count() returns trigger
language plpgsql set search_path='' as $$
begin
  if current_setting('nightowl.fixture_swap_pause',true)='enabled' then
    perform pg_catalog.pg_sleep(0.6);
  end if;
  return null;
end;
$$;
revoke all on function public.fixture_pause_after_count() from public;
create trigger zz_fixture_pause_after_count after delete on public.checkins
  for each row execute function public.fixture_pause_after_count();

-- Simulate a later failing member trigger to verify rollback after group INSERT,
-- rather than only validating inputs before a write begins.
create function public.fixture_reject_dave_member() returns trigger
language plpgsql set search_path='' as $$
begin
  if new.user_id='00000000-0000-4000-8000-000000000006'::uuid then
    raise exception 'Fictional member insert failure' using errcode='23514';
  end if;
  return new;
end;
$$;
revoke all on function public.fixture_reject_dave_member() from public;
create trigger fixture_member_failure before insert on public.group_members
  for each row execute function public.fixture_reject_dave_member();

grant select on public.profiles, public.venues, public.messages, public.blocks,
  public.group_chats, public.group_members, public.checkins to authenticated;
grant insert on public.group_chats, public.group_members, public.checkins to authenticated;
grant insert on public.blocks to authenticated;
grant delete on public.checkins to authenticated;

insert into auth.users(id) select ('00000000-0000-4000-8000-00000000000'||n)::uuid from generate_series(1,6) n;
insert into public.profiles(id,username,is_banned) values
 ('00000000-0000-4000-8000-000000000001','fixture_alice',false),
 ('00000000-0000-4000-8000-000000000002','fixture_bob',false),
 ('00000000-0000-4000-8000-000000000003','fixture_charlie',false),
 ('00000000-0000-4000-8000-000000000004','fixture_banned',true),
 ('00000000-0000-4000-8000-000000000006','fixture_dave',false);
insert into public.venues(id,name) values
 ('10000000-0000-4000-8000-000000000001','Fixture venue one'),
 ('10000000-0000-4000-8000-000000000002','Fixture venue two'),
 ('10000000-0000-4000-8000-000000000003','Fixture demo #123');
insert into public.messages(id,sender_id,receiver_id,body,is_read,created_at) values
 ('20000000-0000-4000-8000-000000000001','00000000-0000-4000-8000-000000000002','00000000-0000-4000-8000-000000000001','fixture unread one',false,'2026-01-01 10:00Z'),
 ('20000000-0000-4000-8000-000000000002','00000000-0000-4000-8000-000000000002','00000000-0000-4000-8000-000000000001','fixture unread two',false,'2026-01-01 11:00Z'),
 ('20000000-0000-4000-8000-000000000003','00000000-0000-4000-8000-000000000001','00000000-0000-4000-8000-000000000002','fixture latest own one',false,'2026-01-01 12:00Z'),
 ('20000000-0000-4000-8000-000000000004','00000000-0000-4000-8000-000000000001','00000000-0000-4000-8000-000000000002','fixture latest own tie',false,'2026-01-01 12:00Z'),
 ('20000000-0000-4000-8000-000000000005','00000000-0000-4000-8000-000000000003','00000000-0000-4000-8000-000000000001','fixture read',true,'2026-01-01 09:00Z'),
 ('20000000-0000-4000-8000-000000000006','00000000-0000-4000-8000-000000000002','00000000-0000-4000-8000-000000000003','private other pair',false,'2026-01-02 12:00Z'),
 ('20000000-0000-4000-8000-000000000007','00000000-0000-4000-8000-000000000004','00000000-0000-4000-8000-000000000001','banned partner',false,'2026-01-03 12:00Z'),
 ('20000000-0000-4000-8000-000000000008','00000000-0000-4000-8000-000000000002','00000000-0000-4000-8000-000000000001','null timestamp',true,null);
insert into public.messages(sender_id,receiver_id,body,is_read,created_at)
 select '00000000-0000-4000-8000-000000000002','00000000-0000-4000-8000-000000000001','old fixture',false,'2010-01-01Z'::timestamptz
 from generate_series(1,450);
insert into public.checkins(user_id,venue_id,expires_at) values
 ('00000000-0000-4000-8000-000000000001','10000000-0000-4000-8000-000000000001',now()-interval '1 hour'),
 ('00000000-0000-4000-8000-000000000001','10000000-0000-4000-8000-000000000002',now()+interval '2 hours'),
 ('00000000-0000-4000-8000-000000000002','10000000-0000-4000-8000-000000000001',now()+interval '2 hours');
reset role;

create schema nightowl_patch_test;
create table nightowl_patch_test.table_acl_before as
 select c.oid,c.relacl,c.relrowsecurity,c.relforcerowsecurity from pg_class c join pg_namespace n on n.oid=c.relnamespace
 where n.nspname='public' and c.relkind='r';
create table nightowl_patch_test.policy_before as
 select p.* from pg_policy p join pg_class c on c.oid=p.polrelid join pg_namespace n on n.oid=c.relnamespace where n.nspname='public';
create table nightowl_patch_test.results(group_id uuid);
grant usage on schema nightowl_patch_test to authenticated;
grant insert,select on nightowl_patch_test.results to authenticated;

set role nightowl_rpc_fixture_owner;
set nightowl.target_rpc_patch='approved-independent-target';
\ir ../patches/20261005_missing_client_rpcs.sql
reset role;
