-- ═══════════════════════════════════════════════
-- NightOwl UB — Supabase Triggers & Functions
-- SQL Editor дотор ажиллуулна уу
-- ═══════════════════════════════════════════════

-- 1. Like → notification автоматаар үүсгэх
create or replace function notify_like()
returns trigger language plpgsql as $$
declare
  post_owner uuid;
begin
  select user_id into post_owner from posts where id = NEW.post_id;
  if post_owner != NEW.user_id then
    insert into notifications (id, user_id, actor_id, type, message, created_at)
    values (
      gen_random_uuid(),
      post_owner,
      NEW.user_id,
      'like',
      'liked your photo',
      now()
    );
  end if;
  return NEW;
end;
$$;
create trigger on_like after insert on likes
  for each row execute function notify_like();

-- 2. Follow → notification
create or replace function notify_follow()
returns trigger language plpgsql as $$
begin
  insert into notifications (id, user_id, actor_id, type, message, created_at)
  values (
    gen_random_uuid(),
    NEW.following_id,
    NEW.follower_id,
    'follow',
    'started following you',
    now()
  );
  return NEW;
end;
$$;
create trigger on_follow after insert on follows
  for each row execute function notify_follow();

-- 3. Post likes_count тоолуур
create or replace function update_likes_count()
returns trigger language plpgsql as $$
begin
  if TG_OP = 'INSERT' then
    update posts set likes_count = likes_count + 1 where id = NEW.post_id;
  elsif TG_OP = 'DELETE' then
    update posts set likes_count = greatest(likes_count - 1, 0) where id = OLD.post_id;
  end if;
  return coalesce(NEW, OLD);
end;
$$;
create trigger on_like_count after insert or delete on likes
  for each row execute function update_likes_count();

-- 4. Expired check-in автоматаар устгах (pg_cron extension шаардана)
-- Supabase Dashboard → Extensions → pg_cron идэвхжүүлнэ
-- select cron.schedule('clean-checkins', '*/30 * * * *',
--   'delete from checkins where expires_at < now()');

-- 5. Expired stories устгах
-- select cron.schedule('clean-stories', '0 * * * *',
--   'delete from stories where expires_at < now()');

-- 6. Notifications table (хэрэв үүсгэгдээгүй бол)
create table if not exists notifications (
  id         uuid primary key default gen_random_uuid(),
  user_id    uuid references profiles(id) on delete cascade,
  actor_id   uuid references profiles(id) on delete cascade,
  type       text not null,
  message    text not null,
  is_read    boolean default false,
  created_at timestamptz default now()
);
create index if not exists idx_notif_user on notifications(user_id, created_at desc);

-- 7. RLS
alter table notifications enable row level security;
create policy "Own notifications" on notifications
  for all using (auth.uid() = user_id);

-- 8. Realtime идэвхжүүлэх
alter publication supabase_realtime add table messages;
alter publication supabase_realtime add table notifications;
alter publication supabase_realtime add table checkins;
