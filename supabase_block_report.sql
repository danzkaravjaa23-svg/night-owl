-- ═══════════════════════════════════════════════════════════════════
-- NightOwl UB — Block & Report (хэрэглэгч хориглох + мэдээлэх)
-- Idempotent — аюулгүйгээр дахин ажиллуулж болно.
-- ═══════════════════════════════════════════════════════════════════

-- ── BLOCKS ──────────────────────────────────────────────────────────
create table if not exists public.blocks (
  blocker_id uuid references public.profiles on delete cascade not null,
  blocked_id uuid references public.profiles on delete cascade not null,
  created_at timestamptz default now(),
  primary key (blocker_id, blocked_id)
);
alter table public.blocks enable row level security;
drop policy if exists "Own blocks viewable" on public.blocks;
drop policy if exists "Own blocks insert"   on public.blocks;
drop policy if exists "Own blocks delete"   on public.blocks;
create policy "Own blocks viewable" on public.blocks for select using (auth.uid() = blocker_id);
create policy "Own blocks insert"   on public.blocks for insert with check (auth.uid() = blocker_id);
create policy "Own blocks delete"   on public.blocks for delete using (auth.uid() = blocker_id);
create index if not exists idx_blocks_blocker on public.blocks(blocker_id);
create index if not exists idx_blocks_blocked on public.blocks(blocked_id);

-- ── REPORTS ─────────────────────────────────────────────────────────
create table if not exists public.reports (
  id uuid default gen_random_uuid() primary key,
  reporter_id uuid references public.profiles on delete cascade not null,
  target_type text not null,             -- 'post' | 'user' | 'comment' | 'venue'
  target_id   uuid not null,
  reason      text not null,             -- spam, harassment, nudity, violence, other
  details     text,
  status      text default 'pending',    -- pending | reviewed | resolved
  created_at  timestamptz default now()
);
alter table public.reports enable row level security;
drop policy if exists "Own reports insert"   on public.reports;
drop policy if exists "Own reports viewable" on public.reports;
drop policy if exists "Admin reports view"   on public.reports;
create policy "Own reports insert"   on public.reports for insert with check (auth.uid() = reporter_id);
create policy "Own reports viewable" on public.reports for select using (auth.uid() = reporter_id);
-- Админ бүх report-ыг харна
create policy "Admin reports view" on public.reports for select using (
  exists(select 1 from public.profiles p where p.id = auth.uid() and p.is_admin = true)
);
create index if not exists idx_reports_status on public.reports(status, created_at desc);

-- ── FEED RPC-уудыг блоклосон хүмүүсийг хасахаар шинэчлэх ─────────────
-- (хоёр чиглэлд: миний блоклосон + намайг блоклосон хүмүүс)
drop function if exists public.get_feed_posts(uuid, int, int);
create function public.get_feed_posts(
  p_user_id uuid, p_limit int default 20, p_offset int default 0
)
returns table (
  id uuid, user_id uuid, venue_id uuid, caption text, media_url text,
  media_type text, likes_count int, comments_count int, is_liked_by_me boolean,
  created_at timestamptz, author_id uuid, author_username text,
  author_avatar text, author_verified boolean, venue_name text
)
language sql stable as $$
  select
    p.id, p.user_id, p.venue_id, p.caption, p.media_url,
    coalesce(p.media_type,'image'),
    coalesce(p.likes_count,0),
    coalesce(p.comments_count,0),
    exists(select 1 from public.likes l where l.post_id = p.id and l.user_id = p_user_id),
    p.created_at,
    pr.id, pr.username, pr.avatar_url, pr.is_verified,
    coalesce(v.name, p.venue_name)
  from public.posts p
  left join public.profiles pr on pr.id = p.user_id
  left join public.venues   v  on v.id  = p.venue_id
  where p.user_id not in (
      select blocked_id from public.blocks where blocker_id = p_user_id
      union
      select blocker_id from public.blocks where blocked_id = p_user_id
    )
  order by p.created_at desc
  limit p_limit offset p_offset;
$$;

drop function if exists public.get_following_feed(uuid, int, int);
create function public.get_following_feed(
  p_user_id uuid, p_limit int default 20, p_offset int default 0
)
returns table (
  id uuid, user_id uuid, venue_id uuid, caption text, media_url text,
  media_type text, likes_count int, comments_count int, is_liked_by_me boolean,
  created_at timestamptz, author_id uuid, author_username text,
  author_avatar text, author_verified boolean, venue_name text
)
language sql stable as $$
  select
    p.id, p.user_id, p.venue_id, p.caption, p.media_url,
    coalesce(p.media_type,'image'),
    coalesce(p.likes_count,0),
    coalesce(p.comments_count,0),
    exists(select 1 from public.likes l where l.post_id = p.id and l.user_id = p_user_id),
    p.created_at,
    pr.id, pr.username, pr.avatar_url, pr.is_verified,
    coalesce(v.name, p.venue_name)
  from public.posts p
  left join public.profiles pr on pr.id = p.user_id
  left join public.venues   v  on v.id  = p.venue_id
  where (p.user_id = p_user_id
     or p.user_id in (select following_id from public.follows where follower_id = p_user_id))
    and p.user_id not in (
      select blocked_id from public.blocks where blocker_id = p_user_id
      union
      select blocker_id from public.blocks where blocked_id = p_user_id
    )
  order by p.created_at desc
  limit p_limit offset p_offset;
$$;

notify pgrst, 'reload schema';
