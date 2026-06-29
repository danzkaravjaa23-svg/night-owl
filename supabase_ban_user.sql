-- ═══════════════════════════════════════════════════════════════════
-- NightOwl UB — Хэрэглэгч хориглох (ban) — moderation-ийн үргэлжлэл
--   • profiles.is_banned багана
--   • is_banned() helper (security definer)
--   • banned хэрэглэгч пост/сэтгэгдэл бичиж чадахгүй (insert policy)
--   • banned хэрэглэгчийн пост feed-д харагдахгүй (get_feed_cursor)
-- Idempotent. Additive — одоо байгаа хэрэглэгчид is_banned=false.
-- ═══════════════════════════════════════════════════════════════════

alter table public.profiles add column if not exists is_banned boolean default false;

create or replace function public.is_banned()
returns boolean language sql stable security definer as $$
  select coalesce((select is_banned from public.profiles where id = auth.uid()), false);
$$;

-- Banned хэрэглэгч контент үүсгэхээс сэргийлэх
drop policy if exists "Own posts insertable" on public.posts;
create policy "Own posts insertable" on public.posts
  for insert with check (auth.uid() = user_id and not public.is_banned());

drop policy if exists "Own comments insertable" on public.comments;
create policy "Own comments insertable" on public.comments
  for insert with check (auth.uid() = user_id and not public.is_banned());

-- Feed-ээс banned зохиогчийн постыг хасах
drop function if exists public.get_feed_cursor(uuid, int, timestamptz);
create function public.get_feed_cursor(
  p_user_id uuid, p_limit int default 20, p_before timestamptz default null
)
returns table (
  id uuid, user_id uuid, venue_id uuid, caption text, media_url text,
  media_urls text[], media_type text, likes_count int, comments_count int,
  is_liked_by_me boolean, created_at timestamptz, author_id uuid,
  author_username text, author_avatar text, author_verified boolean, venue_name text
)
language sql stable as $$
  select
    p.id, p.user_id, p.venue_id, p.caption, p.media_url,
    p.media_urls,
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
  where p.created_at < coalesce(p_before, 'infinity'::timestamptz)
    and not coalesce(pr.is_banned, false)
    and p.user_id not in (
      select blocked_id from public.blocks where blocker_id = p_user_id
      union
      select blocker_id from public.blocks where blocked_id = p_user_id
    )
  order by p.created_at desc
  limit p_limit;
$$;

notify pgrst, 'reload schema';
