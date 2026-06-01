-- ═══════════════════════════════════════════════════════════════════
-- NightOwl UB — RLS Security Hardening (admin-aware)
-- ───────────────────────────────────────────────────────────────────
-- Анхдагч (эвдэрсэн) setup-аар үүссэн posts/profiles/likes/notifications/
-- venues table-ууд RLS-гүй байсан → public anon key-ээр хэн ч бусдын
-- пост/профайл устгаж/засаж чаддаг ноцтой цоорхой байсан.
--
-- Энэ файл: RLS асааж, "эзэн ӨӨРӨӨ ЭСВЭЛ admin" policy нэмнэ.
-- Admin extension нь anon key + admin нэвтрэлтээр (authenticated role)
-- ажилладаг тул admin-д cross-user эрх (ban/verify/delete/broadcast) хэрэгтэй.
--
-- ⚠️ Тоолуурын триггерүүдийг SECURITY DEFINER болгосон — эс тэгвээс RLS
--    асаахад like/comment/follow/checkin (cross-user count update) эвдэрнэ.
--
-- ⚠️ ОДОО бүх 4 хэрэглэгч admin (хөгжүүлэлтийн үе). Олон нийтэд гаргахаасаа
--    өмнө зөвхөн жинхэнэ admin-д хязгаарлана:
--    update public.profiles set is_admin=false where id <> '<admin-uuid>';
-- ═══════════════════════════════════════════════════════════════════

-- 0) Тоолуурын триггерүүд SECURITY DEFINER
create or replace function public.update_likes_count()
returns trigger language plpgsql security definer as $$
begin
  if (tg_op='INSERT') then update public.posts set likes_count=likes_count+1 where id=new.post_id;
  elsif (tg_op='DELETE') then update public.posts set likes_count=greatest(likes_count-1,0) where id=old.post_id; end if;
  return null; end; $$;
create or replace function public.update_comments_count()
returns trigger language plpgsql security definer as $$
begin
  if (tg_op='INSERT') then update public.posts set comments_count=comments_count+1 where id=new.post_id;
  elsif (tg_op='DELETE') then update public.posts set comments_count=greatest(comments_count-1,0) where id=old.post_id; end if;
  return null; end; $$;
create or replace function public.update_follow_counts()
returns trigger language plpgsql security definer as $$
begin
  if (tg_op='INSERT') then
    update public.profiles set followers_count=followers_count+1 where id=new.following_id;
    update public.profiles set following_count=following_count+1 where id=new.follower_id;
  elsif (tg_op='DELETE') then
    update public.profiles set followers_count=greatest(followers_count-1,0) where id=old.following_id;
    update public.profiles set following_count=greatest(following_count-1,0) where id=old.follower_id; end if;
  return null; end; $$;
create or replace function public.update_posts_count()
returns trigger language plpgsql security definer as $$
begin
  if (tg_op='INSERT') then update public.profiles set posts_count=posts_count+1 where id=new.user_id;
  elsif (tg_op='DELETE') then update public.profiles set posts_count=greatest(posts_count-1,0) where id=old.user_id; end if;
  return null; end; $$;
create or replace function public.update_checkin_count()
returns trigger language plpgsql security definer as $$
begin
  if (tg_op='INSERT') then update public.venues set checkin_count=checkin_count+1 where id=new.venue_id;
  elsif (tg_op='DELETE') then update public.venues set checkin_count=greatest(checkin_count-1,0) where id=old.venue_id; end if;
  return null; end; $$;

-- 1) is_admin багана + helper (security definer тул profiles RLS recursion-гүй)
alter table public.profiles add column if not exists is_admin boolean default false;
update public.profiles set is_admin=true
where id in (select id from auth.users where email in
  ('osokhe@gmail.com','altannavch.e@gmail.com','danzkaravjaa23@gmail.com','danzan1234@gmail.com'));

create or replace function public.is_admin()
returns boolean language sql stable security definer as $$
  select coalesce((select is_admin from public.profiles where id = auth.uid()), false);
$$;

-- 2) POSTS
alter table public.posts enable row level security;
drop policy if exists "Posts viewable" on public.posts;
drop policy if exists "Own posts insertable" on public.posts;
drop policy if exists "Own posts updatable" on public.posts;
drop policy if exists "Own posts deletable" on public.posts;
create policy "Posts viewable"        on public.posts for select using (true);
create policy "Own posts insertable"  on public.posts for insert with check (auth.uid()=user_id);
create policy "Own posts updatable"   on public.posts for update using (auth.uid()=user_id or public.is_admin());
create policy "Own posts deletable"   on public.posts for delete using (auth.uid()=user_id or public.is_admin());

-- 3) PROFILES
alter table public.profiles enable row level security;
drop policy if exists "Public profiles viewable" on public.profiles;
drop policy if exists "Insert own profile" on public.profiles;
drop policy if exists "Own profile editable" on public.profiles;
create policy "Public profiles viewable" on public.profiles for select using (true);
create policy "Insert own profile"       on public.profiles for insert with check (auth.uid()=id);
create policy "Own profile editable"     on public.profiles for update using (auth.uid()=id or public.is_admin());

-- 4) LIKES
alter table public.likes enable row level security;
drop policy if exists "Likes viewable" on public.likes;
drop policy if exists "Own likes insertable" on public.likes;
drop policy if exists "Own likes deletable" on public.likes;
create policy "Likes viewable"       on public.likes for select using (true);
create policy "Own likes insertable" on public.likes for insert with check (auth.uid()=user_id);
create policy "Own likes deletable"  on public.likes for delete using (auth.uid()=user_id or public.is_admin());

-- 5) NOTIFICATIONS
alter table public.notifications enable row level security;
drop policy if exists "Own notifs viewable" on public.notifications;
drop policy if exists "Notifs insertable" on public.notifications;
drop policy if exists "Own notifs updatable" on public.notifications;
drop policy if exists "Own notifs deletable" on public.notifications;
create policy "Own notifs viewable"  on public.notifications for select using (auth.uid()=user_id or public.is_admin());
create policy "Notifs insertable"    on public.notifications for insert with check (public.is_admin());
create policy "Own notifs updatable" on public.notifications for update using (auth.uid()=user_id);
create policy "Own notifs deletable" on public.notifications for delete using (auth.uid()=user_id or public.is_admin());

-- 6) VENUES (зөвхөн admin бичнэ; checkin_count триггер definer тул тойрно)
alter table public.venues enable row level security;
drop policy if exists "Venues viewable" on public.venues;
drop policy if exists "Admin venues insert" on public.venues;
drop policy if exists "Admin venues update" on public.venues;
drop policy if exists "Admin venues delete" on public.venues;
create policy "Venues viewable"     on public.venues for select using (true);
create policy "Admin venues insert" on public.venues for insert with check (public.is_admin());
create policy "Admin venues update" on public.venues for update using (public.is_admin());
create policy "Admin venues delete" on public.venues for delete using (public.is_admin());

-- ═══════════════════════════════════════════════════════════════════
-- ШАЛГАХ: select relname, relrowsecurity from pg_class
--         where relnamespace='public'::regnamespace and relkind='r';
-- ═══════════════════════════════════════════════════════════════════
