-- ═══════════════════════════════════════════════════════════════════
-- NightOwl UB — Олон зурагтай пост (carousel)
-- posts-д media_urls text[] нэмж, feed RPC-уудыг буцаахаар шинэчлэх.
-- Block filter-ийг хадгална. Idempotent.
-- ═══════════════════════════════════════════════════════════════════

alter table public.posts add column if not exists media_urls text[];

drop function if exists public.get_feed_posts(uuid, int, int);
create function public.get_feed_posts(
  p_user_id uuid, p_limit int default 20, p_offset int default 0
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
