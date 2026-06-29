-- ═══════════════════════════════════════════════════════════════════
-- NightOwl UB — Feed cursor (keyset) pagination
-- OFFSET pagination-ийн оронд created_at cursor — 500к scale-д:
--   • гүн offset дээр ч O(limit) (offset scan байхгүй)
--   • шинэ пост ороход давхардал/алгасалт байхгүй
-- media_urls + block filter хадгална. Idempotent.
-- ═══════════════════════════════════════════════════════════════════

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
    and p.user_id not in (
      select blocked_id from public.blocks where blocker_id = p_user_id
      union
      select blocker_id from public.blocks where blocked_id = p_user_id
    )
  order by p.created_at desc
  limit p_limit;
$$;

notify pgrst, 'reload schema';
