-- =============================================
-- NightOwl UB — Database Setup
-- Supabase SQL Editor-т бүгдийг хуулаад Run дар
-- =============================================

-- 1. PROFILES TABLE
create table if not exists public.profiles (
  id uuid references auth.users on delete cascade primary key,
  username text unique not null,
  full_name text,
  avatar_url text,
  bio text,
  interests text[] default '{}',
  is_verified boolean default false,
  is_business boolean default false,
  fcm_token text,
  updated_at timestamptz,
  created_at timestamptz default now()
);
alter table public.profiles enable row level security;
create policy "Public profiles viewable" on public.profiles for select using (true);
create policy "Own profile editable" on public.profiles for update using (auth.uid() = id);
create policy "Insert own profile" on public.profiles for insert with check (auth.uid() = id);

-- 2. BACKFILL EXISTING AUTH USERS
insert into public.profiles (id, username, created_at)
select id, email, now()
from auth.users
on conflict (id) do nothing;

-- 3. AUTO-CREATE PROFILE ON SIGNUP
create or replace function public.handle_new_user()
returns trigger language plpgsql security definer as $$
begin
  insert into public.profiles (id, username, full_name, avatar_url, created_at)
  values (
    new.id,
    coalesce(new.raw_user_meta_data->>'username', split_part(new.email, '@', 1)),
    coalesce(new.raw_user_meta_data->>'full_name', ''),
    coalesce(new.raw_user_meta_data->>'avatar_url', ''),
    now()
  ) on conflict (id) do nothing;
  return new;
end;
$$;

drop trigger if exists on_auth_user_created on auth.users;
create trigger on_auth_user_created
  after insert on auth.users
  for each row execute function public.handle_new_user();

-- 4. VENUES TABLE
create table if not exists public.venues (
  id uuid default gen_random_uuid() primary key,
  name text not null,
  venue_type text,
  lat double precision,
  lng double precision,
  district text,
  description text,
  cover_url text,
  checkin_count int default 0,
  created_at timestamptz default now()
);
alter table public.venues enable row level security;
create policy "Venues viewable" on public.venues for select using (true);

-- 4. POSTS TABLE
create table if not exists public.posts (
  id uuid default gen_random_uuid() primary key,
  user_id uuid references public.profiles on delete cascade not null,
  venue_id uuid references public.venues on delete set null,
  caption text,
  media_url text,
  likes_count int default 0,
  created_at timestamptz default now()
);
alter table public.posts enable row level security;
create policy "Posts viewable" on public.posts for select using (true);
create policy "Own posts insertable" on public.posts for insert with check (auth.uid() = user_id);
create policy "Own posts deletable" on public.posts for delete using (auth.uid() = user_id);

-- 5. LIKES TABLE
create table if not exists public.likes (
  id uuid default gen_random_uuid() primary key,
  user_id uuid references public.profiles on delete cascade not null,
  post_id uuid references public.posts on delete cascade not null,
  created_at timestamptz default now(),
  unique(user_id, post_id)
);
alter table public.likes enable row level security;
create policy "Likes viewable" on public.likes for select using (true);
create policy "Own likes insertable" on public.likes for insert with check (auth.uid() = user_id);
create policy "Own likes deletable" on public.likes for delete using (auth.uid() = user_id);

-- 6. NOTIFICATIONS TABLE
create table if not exists public.notifications (
  id uuid default gen_random_uuid() primary key,
  user_id uuid references public.profiles on delete cascade not null,
  actor_id uuid references public.profiles on delete cascade not null,
  actor_name text,
  actor_avatar text,
  type text not null,
  message text not null,r
  is_read boolean default false,
  created_at timestamptz default now()
);
alter table public.notifications enable row level security;
create policy "Own notifs viewable" on public.notifications for select using (auth.uid() = user_id);
create policy "Notifs insertable" on public.notifications for insert with check (true);
create policy "Own notifs updatable" on public.notifications for update using (auth.uid() = user_id);

-- 7. MESSAGES TABLE
create table if not exists public.messages (
  id uuid default gen_random_uuid() primary key,
  sender_id uuid references public.profiles on delete cascade not null,
  receiver_id uuid references public.profiles on delete cascade not null,
  body text not null,
  is_read boolean default false,
  created_at timestamptz default now()
);
alter table public.messages enable row level security;
create policy "Own messages viewable" on public.messages for select
  using (auth.uid() = sender_id or auth.uid() = receiver_id);
create policy "Own messages insertable" on public.messages for insert
  with check (auth.uid() = sender_id);
