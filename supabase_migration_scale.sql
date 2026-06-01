-- ═══════════════════════════════════════════════════════════════════
-- NightOwl UB — LIVE DB Reconciliation + Scale Migration (v3)
-- ───────────────────────────────────────────────────────────────────
-- Энэ файл нь ЖИНХЭНЭ live DB-ийн төлвийг шалгасны үндсэн дээр бичигдсэн.
-- (2026-06-01-нд Chrome-оор Supabase SQL Editor-оор шалгасан.)
--
-- Live DB-д ИЛЭРСЭН зөрүү:
--   • follows / stories / story_views / checkins / events table БАЙХГҮЙ
--   • get_feed_posts функц БАЙХГҮЙ (апп-ийн feed RPC алдаа өгдөг)
--   • Гүйцэтгэлийн index ГАНЦ Ч БАЙХГҮЙ (зөвхөн PK/unique)
--   • comments.text багана — апп нь 'body' хүлээдэг (сэтгэгдэл эвдэрсэн)
--   • comments-д likes_count алга (апп хүлээдэг)
--   • posts-д comments_count, media_type алга (апп create-post эвдэрдэг)
--   • profiles-д followers_count/following_count/posts_count алга
--   • likes_count тоолуурын trigger алга (like тоо DB-д шинэчлэгдэхгүй)
--
-- Idempotent — аюулгүйгээр дахин ажиллуулж болно.
-- ⚠️ PRODUCTION DB дээр ажиллана. Бүх өөрчлөлт additive (column rename-ээс
--    бусад нь). Дэстрактив устгал хийхгүй.
-- ═══════════════════════════════════════════════════════════════════


-- ───────────────────────────────────────────────────────────────────
-- SECTION 0 — Дутуу TABLE-уудыг үүсгэх (+ RLS)
-- ───────────────────────────────────────────────────────────────────

-- 0a. FOLLOWS
create table if not exists public.follows (
  id uuid default gen_random_uuid() primary key,
  follower_id  uuid references public.profiles on delete cascade not null,
  following_id uuid references public.profiles on delete cascade not null,
  created_at timestamptz default now(),
  unique(follower_id, following_id)
);
alter table public.follows enable row level security;
drop policy if exists "Follows viewable"        on public.follows;
drop policy if exists "Own follows insertable"  on public.follows;
drop policy if exists "Own follows deletable"   on public.follows;
create policy "Follows viewable"       on public.follows for select using (true);
create policy "Own follows insertable" on public.follows for insert with check (auth.uid() = follower_id);
create policy "Own follows deletable"  on public.follows for delete using (auth.uid() = follower_id);

-- 0b. STORIES
create table if not exists public.stories (
  id uuid default gen_random_uuid() primary key,
  user_id uuid references public.profiles on delete cascade not null,
  media_url text not null,
  media_type text default 'image',
  caption text,
  duration int default 5,
  view_count int default 0,
  expires_at timestamptz default (now() + interval '24 hours'),
  created_at timestamptz default now()
);
alter table public.stories enable row level security;
drop policy if exists "Active stories viewable" on public.stories;
drop policy if exists "Own stories insertable"  on public.stories;
drop policy if exists "Own stories deletable"   on public.stories;
create policy "Active stories viewable" on public.stories for select using (expires_at > now());
create policy "Own stories insertable"  on public.stories for insert with check (auth.uid() = user_id);
create policy "Own stories deletable"   on public.stories for delete using (auth.uid() = user_id);

-- 0c. STORY VIEWS
create table if not exists public.story_views (
  id uuid default gen_random_uuid() primary key,
  story_id  uuid references public.stories  on delete cascade not null,
  viewer_id uuid references public.profiles on delete cascade not null,
  viewed_at timestamptz default now(),
  unique(story_id, viewer_id)
);
alter table public.story_views enable row level security;
drop policy if exists "Story views insertable"   on public.story_views;
drop policy if exists "Own story views viewable" on public.story_views;
create policy "Story views insertable"   on public.story_views for insert with check (auth.uid() = viewer_id);
create policy "Own story views viewable"  on public.story_views for select using (true);

-- 0d. CHECKINS
create table if not exists public.checkins (
  id uuid default gen_random_uuid() primary key,
  user_id  uuid references public.profiles on delete cascade not null,
  venue_id uuid references public.venues   on delete cascade not null,
  expires_at timestamptz default (now() + interval '4 hours'),
  created_at timestamptz default now(),
  unique(user_id, venue_id)
);
alter table public.checkins enable row level security;
drop policy if exists "Active checkins viewable" on public.checkins;
drop policy if exists "Own checkins insertable"  on public.checkins;
drop policy if exists "Own checkins deletable"   on public.checkins;
create policy "Active checkins viewable" on public.checkins for select using (expires_at > now());
create policy "Own checkins insertable"  on public.checkins for insert with check (auth.uid() = user_id);
create policy "Own checkins deletable"   on public.checkins for delete using (auth.uid() = user_id);

-- 0e. EVENTS
create table if not exists public.events (
  id uuid default gen_random_uuid() primary key,
  venue_id     uuid references public.venues   on delete cascade,
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
drop policy if exists "Events viewable"   on public.events;
drop policy if exists "Events insertable"  on public.events;
create policy "Events viewable"   on public.events for select using (true);
create policy "Events insertable"  on public.events for insert with check (auth.uid() = organizer_id);


-- ───────────────────────────────────────────────────────────────────
-- SECTION 1 — Одоо байгаа table-уудын дутуу багана + comments засвар
-- ───────────────────────────────────────────────────────────────────

-- 1a. comments: апп 'body' + 'likes_count' хүлээдэг ч DB-д 'text' байна.
--     'text' → 'body' болгож нэрлэнэ (өгөгдөл хадгалагдана), likes_count нэмнэ.
do $$
begin
  if exists (select 1 from information_schema.columns
             where table_schema='public' and table_name='comments' and column_name='text')
     and not exists (select 1 from information_schema.columns
             where table_schema='public' and table_name='comments' and column_name='body')
  then
    alter table public.comments rename column "text" to body;
  end if;
end $$;
alter table public.comments add column if not exists likes_count int default 0;

-- comments RLS (апп insert/select хийдэг)
alter table public.comments enable row level security;
drop policy if exists "Comments viewable"       on public.comments;
drop policy if exists "Own comments insertable" on public.comments;
drop policy if exists "Own comments deletable"  on public.comments;
create policy "Comments viewable"       on public.comments for select using (true);
create policy "Own comments insertable" on public.comments for insert with check (auth.uid() = user_id);
create policy "Own comments deletable"  on public.comments for delete using (auth.uid() = user_id);

-- 1b. posts: дутуу багана
alter table public.posts add column if not exists comments_count int default 0;
alter table public.posts add column if not exists media_type     text default 'image';

-- 1c. profiles: тоолуурын багана
alter table public.profiles add column if not exists followers_count int default 0;
alter table public.profiles add column if not exists following_count int default 0;
alter table public.profiles add column if not exists posts_count     int default 0;


-- ───────────────────────────────────────────────────────────────────
-- SECTION 2 — ГҮЙЦЭТГЭЛИЙН INDEX-УУД (хамгийн чухал)
-- ───────────────────────────────────────────────────────────────────
create index if not exists idx_posts_created       on public.posts (created_at desc);
create index if not exists idx_posts_user_created   on public.posts (user_id, created_at desc);
create index if not exists idx_posts_venue          on public.posts (venue_id) where venue_id is not null;

create index if not exists idx_likes_post           on public.likes (post_id);

create index if not exists idx_comments_post        on public.comments (post_id, created_at desc);
create index if not exists idx_comments_user        on public.comments (user_id);

create index if not exists idx_follows_following    on public.follows (following_id);

create index if not exists idx_msg_pair             on public.messages (sender_id, receiver_id, created_at desc);
create index if not exists idx_msg_receiver_unread  on public.messages (receiver_id) where is_read = false;

create index if not exists idx_notif_user           on public.notifications (user_id, created_at desc);
create index if not exists idx_notif_unread         on public.notifications (user_id) where is_read = false;

create index if not exists idx_stories_user         on public.stories (user_id, created_at desc);
create index if not exists idx_stories_active       on public.stories (expires_at);

create index if not exists idx_story_views_viewer   on public.story_views (viewer_id);

create index if not exists idx_checkins_venue       on public.checkins (venue_id);
create index if not exists idx_checkins_active      on public.checkins (expires_at);

create index if not exists idx_events_venue         on public.events (venue_id);
create index if not exists idx_events_starts        on public.events (starts_at);

create index if not exists idx_venues_geo           on public.venues (lat, lng);

-- Live feature (одоо байгаа table-ууд)
create index if not exists idx_live_streams_user    on public.live_streams (user_id);
create index if not exists idx_live_streams_active  on public.live_streams (is_live) where is_live = true;
create index if not exists idx_live_comments_stream on public.live_comments (stream_id, created_at desc);


-- ───────────────────────────────────────────────────────────────────
-- SECTION 3 — ТООЛУУРЫН TRIGGER-УУД
-- ───────────────────────────────────────────────────────────────────

-- 3a. likes_count (live DB-д БАЙХГҮЙ байсан — like тоо шинэчлэгдэхгүй байсан)
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
create trigger on_like_change after insert or delete on public.likes
  for each row execute function public.update_likes_count();

-- 3b. comments_count
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
create trigger on_comment_change after insert or delete on public.comments
  for each row execute function public.update_comments_count();

-- 3c. follow counts
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
create trigger on_follow_change after insert or delete on public.follows
  for each row execute function public.update_follow_counts();

-- 3d. posts_count
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
create trigger on_post_change after insert or delete on public.posts
  for each row execute function public.update_posts_count();

-- 3e. checkin count
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
create trigger on_checkin_change after insert or delete on public.checkins
  for each row execute function public.update_checkin_count();


-- ───────────────────────────────────────────────────────────────────
-- SECTION 4 — NOTIFICATION TRIGGER-УУД (хуучныг стандартчилж, follow нэмэх)
-- ───────────────────────────────────────────────────────────────────
-- Live DB-д аль хэдийн on_like_notify (notify_on_like), on_comment_notify
-- (notify_on_comment) байгаа. Тэдгээрийг нэг стандарт хувилбар болгож солино.

-- 4a. like notification
drop trigger if exists on_like_notify on public.likes;
drop function if exists public.notify_on_like();
create or replace function public.create_like_notification()
returns trigger language plpgsql security definer as $$
declare v_owner uuid; v_name text;
begin
  select user_id into v_owner from public.posts where id = new.post_id;
  if v_owner is null or v_owner = new.user_id then return new; end if;
  select username into v_name from public.profiles where id = new.user_id;
  insert into public.notifications (user_id, actor_id, actor_name, type, message, post_id)
  values (v_owner, new.user_id, v_name, 'like',
          coalesce(v_name,'Хэн нэгэн') || ' таны постыг лайкласан', new.post_id);
  return new;
end;
$$;
create trigger on_like_notify after insert on public.likes
  for each row execute function public.create_like_notification();

-- 4b. comment notification
drop trigger if exists on_comment_notify on public.comments;
drop function if exists public.notify_on_comment();
create or replace function public.create_comment_notification()
returns trigger language plpgsql security definer as $$
declare v_owner uuid; v_name text;
begin
  select user_id into v_owner from public.posts where id = new.post_id;
  if v_owner is null or v_owner = new.user_id then return new; end if;
  select username into v_name from public.profiles where id = new.user_id;
  insert into public.notifications (user_id, actor_id, actor_name, type, message, post_id)
  values (v_owner, new.user_id, v_name, 'comment',
          coalesce(v_name,'Хэн нэгэн') || ' таны постод сэтгэгдэл бичлээ', new.post_id);
  return new;
end;
$$;
create trigger on_comment_notify after insert on public.comments
  for each row execute function public.create_comment_notification();

-- 4c. follow notification (ШИНЭ — follows table шинээр үүссэн)
create or replace function public.create_follow_notification()
returns trigger language plpgsql security definer as $$
declare v_name text;
begin
  select username into v_name from public.profiles where id = new.follower_id;
  insert into public.notifications (user_id, actor_id, actor_name, type, message)
  values (new.following_id, new.follower_id, v_name, 'follow',
          coalesce(v_name,'Хэн нэгэн') || ' таныг дагаж эхэллээ');
  return new;
end;
$$;
drop trigger if exists on_follow_notify on public.follows;
create trigger on_follow_notify after insert on public.follows
  for each row execute function public.create_follow_notification();


-- ───────────────────────────────────────────────────────────────────
-- SECTION 5 — FEED ФУНКЦУУД (get_feed_posts live DB-д БАЙХГҮЙ байсан!)
-- ───────────────────────────────────────────────────────────────────

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
  order by p.created_at desc
  limit p_limit offset p_offset;
$$;

-- Following feed — Instagram шиг (дагасан хүмүүс + өөрийн пост)
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
  where p.user_id = p_user_id
     or p.user_id in (select following_id from public.follows where follower_id = p_user_id)
  order by p.created_at desc
  limit p_limit offset p_offset;
$$;


-- ───────────────────────────────────────────────────────────────────
-- SECTION 6 — Одоо байгаа өгөгдлийн тоолуурыг дахин тооцоолох (backfill)
-- ───────────────────────────────────────────────────────────────────
update public.posts p set
  likes_count    = coalesce((select count(*) from public.likes    l where l.post_id = p.id), 0),
  comments_count = coalesce((select count(*) from public.comments c where c.post_id = p.id), 0);

update public.profiles pr set
  followers_count = coalesce((select count(*) from public.follows f where f.following_id = pr.id), 0),
  following_count = coalesce((select count(*) from public.follows f where f.follower_id  = pr.id), 0),
  posts_count     = coalesce((select count(*) from public.posts   p where p.user_id      = pr.id), 0);

update public.venues v set
  checkin_count = coalesce((select count(*) from public.checkins c where c.venue_id = v.id), 0);


-- ───────────────────────────────────────────────────────────────────
-- SECTION 7 — Realtime publication
-- ───────────────────────────────────────────────────────────────────
do $$
begin
  begin alter publication supabase_realtime add table public.notifications; exception when others then null; end;
  begin alter publication supabase_realtime add table public.messages;      exception when others then null; end;
  begin alter publication supabase_realtime add table public.comments;      exception when others then null; end;
  begin alter publication supabase_realtime add table public.stories;       exception when others then null; end;
  begin alter publication supabase_realtime add table public.checkins;      exception when others then null; end;
  begin alter publication supabase_realtime add table public.live_comments; exception when others then null; end;
  begin alter publication supabase_realtime add table public.follows;       exception when others then null; end;
end $$;

-- ───────────────────────────────────────────────────────────────────
-- SECTION 8 — Stories view_count нэмэгдүүлэх RPC (апп markViewed дууддаг)
-- ───────────────────────────────────────────────────────────────────
create or replace function public.increment_story_views(story_id uuid)
returns void language sql as $$
  update public.stories set view_count = view_count + 1 where id = story_id;
$$;

-- ───────────────────────────────────────────────────────────────────
-- SECTION 9 — messages RLS (live DB-д policy огт байхгүй байсан → DM явдаггүй)
-- ───────────────────────────────────────────────────────────────────
alter table public.messages enable row level security;
drop policy if exists "Own messages viewable"   on public.messages;
drop policy if exists "Own messages insertable"  on public.messages;
drop policy if exists "Mark received read"       on public.messages;
create policy "Own messages viewable" on public.messages for select
  using (auth.uid() = sender_id or auth.uid() = receiver_id);
create policy "Own messages insertable" on public.messages for insert
  with check (auth.uid() = sender_id);
create policy "Mark received read" on public.messages for update
  using (auth.uid() = receiver_id);

-- ───────────────────────────────────────────────────────────────────
-- SECTION 10 — DM мессеж → notification (activity-д харагдана)
-- ───────────────────────────────────────────────────────────────────
create or replace function public.create_message_notification()
returns trigger language plpgsql security definer as $$
declare v_name text;
begin
  select username into v_name from public.profiles where id = new.sender_id;
  insert into public.notifications (user_id, actor_id, actor_name, type, message)
  values (new.receiver_id, new.sender_id, v_name, 'message',
          coalesce(v_name,'Хэн нэгэн') || ' танд мессеж илгээлээ');
  return new;
end; $$;
drop trigger if exists on_message_notify on public.messages;
create trigger on_message_notify after insert on public.messages
  for each row execute function public.create_message_notification();

-- ═══════════════════════════════════════════════════════════════════
-- ДУУСЛАА.
-- ═══════════════════════════════════════════════════════════════════
