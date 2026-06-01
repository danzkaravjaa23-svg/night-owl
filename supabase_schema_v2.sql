-- =============================================
-- NightOwl UB — Schema v2 (шинэ table-ууд)
-- Supabase SQL Editor-т бүгдийг хуулаад Run дар
-- =============================================

-- 1. FOLLOWS TABLE
create table if not exists public.follows (
  id uuid default gen_random_uuid() primary key,
  follower_id uuid references public.profiles on delete cascade not null,
  following_id uuid references public.profiles on delete cascade not null,
  created_at timestamptz default now(),
  unique(follower_id, following_id)
);
alter table public.follows enable row level security;
create policy "Follows viewable" on public.follows for select using (true);
create policy "Own follows insertable" on public.follows for insert with check (auth.uid() = follower_id);
create policy "Own follows deletable" on public.follows for delete using (auth.uid() = follower_id);

-- 2. COMMENTS TABLE
create table if not exists public.comments (
  id uuid default gen_random_uuid() primary key,
  post_id uuid references public.posts on delete cascade not null,
  user_id uuid references public.profiles on delete cascade not null,
  body text not null,
  likes_count int default 0,
  created_at timestamptz default now()
);
alter table public.comments enable row level security;
create policy "Comments viewable" on public.comments for select using (true);
create policy "Own comments insertable" on public.comments for insert with check (auth.uid() = user_id);
create policy "Own comments deletable" on public.comments for delete using (auth.uid() = user_id);

-- 3. STORIES TABLE
create table if not exists public.stories (
  id uuid default gen_random_uuid() primary key,
  user_id uuid references public.profiles on delete cascade not null,
  media_url text not null,
  media_type text default 'image',  -- 'image' | 'video'
  caption text,
  duration int default 5,           -- seconds
  view_count int default 0,
  expires_at timestamptz default (now() + interval '24 hours'),
  created_at timestamptz default now()
);
alter table public.stories enable row level security;
create policy "Active stories viewable" on public.stories for select using (expires_at > now());
create policy "Own stories insertable" on public.stories for insert with check (auth.uid() = user_id);
create policy "Own stories deletable" on public.stories for delete using (auth.uid() = user_id);

-- 4. STORY VIEWS TABLE
create table if not exists public.story_views (
  id uuid default gen_random_uuid() primary key,
  story_id uuid references public.stories on delete cascade not null,
  viewer_id uuid references public.profiles on delete cascade not null,
  viewed_at timestamptz default now(),
  unique(story_id, viewer_id)
);
alter table public.story_views enable row level security;
create policy "Story views insertable" on public.story_views for insert with check (auth.uid() = viewer_id);
create policy "Own story views viewable" on public.story_views for select using (auth.uid() = viewer_id);

-- 5. CHECKINS TABLE
create table if not exists public.checkins (
  id uuid default gen_random_uuid() primary key,
  user_id uuid references public.profiles on delete cascade not null,
  venue_id uuid references public.venues on delete cascade not null,
  expires_at timestamptz default (now() + interval '4 hours'),
  created_at timestamptz default now(),
  unique(user_id, venue_id)
);
alter table public.checkins enable row level security;
create policy "Active checkins viewable" on public.checkins for select using (expires_at > now());
create policy "Own checkins insertable" on public.checkins for insert with check (auth.uid() = user_id);
create policy "Own checkins deletable" on public.checkins for delete using (auth.uid() = user_id);

-- 6. EVENTS TABLE
create table if not exists public.events (
  id uuid default gen_random_uuid() primary key,
  venue_id uuid references public.venues on delete cascade,
  organizer_id uuid references public.profiles on delete set null,
  title text not null,
  description text,
  cover_url text,
  starts_at timestamptz not null,
  ends_at timestamptz,
  price int default 0,
  capacity int,
  attendee_count int default 0,
  created_at timestamptz default now()
);
alter table public.events enable row level security;
create policy "Events viewable" on public.events for select using (true);
create policy "Events insertable" on public.events for insert with check (auth.uid() = organizer_id);

-- ═══════════════════════════════════════════════════
-- FUNCTIONS & TRIGGERS
-- ═══════════════════════════════════════════════════

-- 7. is_liked_by_me — Feed-д current user liked эсэхийг шалгах
create or replace function public.get_feed_posts(
  p_user_id uuid,
  p_limit int default 20,
  p_offset int default 0
)
returns table (
  id uuid,
  user_id uuid,
  venue_id uuid,
  caption text,
  media_url text,
  media_type text,
  likes_count int,
  comments_count bigint,
  is_liked_by_me boolean,
  created_at timestamptz,
  author_id uuid,
  author_username text,
  author_avatar text,
  author_verified boolean,
  venue_name text
)
language sql stable
as $$
  select
    p.id,
    p.user_id,
    p.venue_id,
    p.caption,
    p.media_url,
    coalesce(p.media_type, 'image') as media_type,
    p.likes_count,
    (select count(*) from public.comments c where c.post_id = p.id) as comments_count,
    exists(
      select 1 from public.likes l
      where l.post_id = p.id and l.user_id = p_user_id
    ) as is_liked_by_me,
    p.created_at,
    pr.id as author_id,
    pr.username as author_username,
    pr.avatar_url as author_avatar,
    pr.is_verified as author_verified,
    v.name as venue_name
  from public.posts p
  left join public.profiles pr on pr.id = p.user_id
  left join public.venues v on v.id = p.venue_id
  order by p.created_at desc
  limit p_limit offset p_offset;
$$;

-- 8. likes_count auto-update trigger
create or replace function public.update_likes_count()
returns trigger language plpgsql as $$
begin
  if (tg_op = 'INSERT') then
    update public.posts set likes_count = likes_count + 1 where id = new.post_id;
  elsif (tg_op = 'DELETE') then
    update public.posts set likes_count = greatest(likes_count - 1, 0) where id = old.post_id;
  end if;
  return null;
end;
$$;

drop trigger if exists on_like_change on public.likes;
create trigger on_like_change
  after insert or delete on public.likes
  for each row execute function public.update_likes_count();

-- 9. comments_count — posts table-д нэмэх (optional cached column)
alter table public.posts add column if not exists comments_count int default 0;
alter table public.posts add column if not exists media_type text default 'image';

create or replace function public.update_comments_count()
returns trigger language plpgsql as $$
begin
  if (tg_op = 'INSERT') then
    update public.posts set comments_count = comments_count + 1 where id = new.post_id;
  elsif (tg_op = 'DELETE') then
    update public.posts set comments_count = greatest(comments_count - 1, 0) where id = old.post_id;
  end if;
  return null;
end;
$$;

drop trigger if exists on_comment_change on public.comments;
create trigger on_comment_change
  after insert or delete on public.comments
  for each row execute function public.update_comments_count();

-- 10. followers/following count triggers
alter table public.profiles add column if not exists followers_count int default 0;
alter table public.profiles add column if not exists following_count int default 0;
alter table public.profiles add column if not exists posts_count int default 0;

create or replace function public.update_follow_counts()
returns trigger language plpgsql as $$
begin
  if (tg_op = 'INSERT') then
    update public.profiles set followers_count = followers_count + 1 where id = new.following_id;
    update public.profiles set following_count = following_count + 1 where id = new.follower_id;
  elsif (tg_op = 'DELETE') then
    update public.profiles set followers_count = greatest(followers_count - 1, 0) where id = old.following_id;
    update public.profiles set following_count = greatest(following_count - 1, 0) where id = old.follower_id;
  end if;
  return null;
end;
$$;

drop trigger if exists on_follow_change on public.follows;
create trigger on_follow_change
  after insert or delete on public.follows
  for each row execute function public.update_follow_counts();

-- 11. posts_count trigger
create or replace function public.update_posts_count()
returns trigger language plpgsql as $$
begin
  if (tg_op = 'INSERT') then
    update public.profiles set posts_count = posts_count + 1 where id = new.user_id;
  elsif (tg_op = 'DELETE') then
    update public.profiles set posts_count = greatest(posts_count - 1, 0) where id = old.user_id;
  end if;
  return null;
end;
$$;

drop trigger if exists on_post_change on public.posts;
create trigger on_post_change
  after insert or delete on public.posts
  for each row execute function public.update_posts_count();

-- 12. Notifications автоматаар үүсгэх trigger
create or replace function public.create_like_notification()
returns trigger language plpgsql security definer as $$
declare
  v_post_owner uuid;
  v_actor_name text;
begin
  select user_id into v_post_owner from public.posts where id = new.post_id;
  if v_post_owner is null or v_post_owner = new.user_id then return new; end if;
  select username into v_actor_name from public.profiles where id = new.user_id;
  insert into public.notifications (user_id, actor_id, actor_name, type, message)
  values (v_post_owner, new.user_id, v_actor_name, 'like',
          coalesce(v_actor_name, 'Someone') || ' таны постыг liked хийлээ');
  return new;
end;
$$;

drop trigger if exists on_like_notify on public.likes;
create trigger on_like_notify
  after insert on public.likes
  for each row execute function public.create_like_notification();

create or replace function public.create_follow_notification()
returns trigger language plpgsql security definer as $$
declare
  v_actor_name text;
begin
  select username into v_actor_name from public.profiles where id = new.follower_id;
  insert into public.notifications (user_id, actor_id, actor_name, type, message)
  values (new.following_id, new.follower_id, v_actor_name, 'follow',
          coalesce(v_actor_name, 'Someone') || ' таныг дагаж эхэллээ');
  return new;
end;
$$;

drop trigger if exists on_follow_notify on public.follows;
create trigger on_follow_notify
  after insert on public.follows
  for each row execute function public.create_follow_notification();

create or replace function public.create_comment_notification()
returns trigger language plpgsql security definer as $$
declare
  v_post_owner uuid;
  v_actor_name text;
begin
  select user_id into v_post_owner from public.posts where id = new.post_id;
  if v_post_owner is null or v_post_owner = new.user_id then return new; end if;
  select username into v_actor_name from public.profiles where id = new.user_id;
  insert into public.notifications (user_id, actor_id, actor_name, type, message)
  values (v_post_owner, new.user_id, v_actor_name, 'comment',
          coalesce(v_actor_name, 'Someone') || ' таны постод сэтгэгдэл үлдээлээ');
  return new;
end;
$$;

drop trigger if exists on_comment_notify on public.comments;
create trigger on_comment_notify
  after insert on public.comments
  for each row execute function public.create_comment_notification();

-- 13. Venue checkin_count trigger
create or replace function public.update_checkin_count()
returns trigger language plpgsql as $$
begin
  if (tg_op = 'INSERT') then
    update public.venues set checkin_count = checkin_count + 1 where id = new.venue_id;
  elsif (tg_op = 'DELETE') then
    update public.venues set checkin_count = greatest(checkin_count - 1, 0) where id = old.venue_id;
  end if;
  return null;
end;
$$;

drop trigger if exists on_checkin_change on public.checkins;
create trigger on_checkin_change
  after insert or delete on public.checkins
  for each row execute function public.update_checkin_count();

-- 14. Realtime идэвхжүүлэх
alter publication supabase_realtime add table public.notifications;
alter publication supabase_realtime add table public.comments;
alter publication supabase_realtime add table public.messages;
alter publication supabase_realtime add table public.stories;
