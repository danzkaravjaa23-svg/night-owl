-- ═══════════════════════════════════════════════════════════════════
-- NightOwl UB — Сэтгэгдлийн reply + like notification (engagement)
--   • reply бол эх сэтгэгдлийн эзэнд "хариулсан" notification
--   • сэтгэгдэл лайклавал сэтгэгдлийн эзэнд "лайкласан" notification
-- Idempotent. notifications(user_id,actor_id,actor_name,type,message,post_id).
-- ═══════════════════════════════════════════════════════════════════

-- Reply-aware comment notification (одоогийн trigger функцийг сольно)
create or replace function public.create_comment_notification()
returns trigger language plpgsql security definer as $$
declare v_target uuid; v_name text; v_msg text;
begin
  select username into v_name from public.profiles where id = new.user_id;
  if new.parent_id is not null then
    -- Reply → эх сэтгэгдлийн эзэн
    select user_id into v_target from public.comments where id = new.parent_id;
    v_msg := coalesce(v_name,'Хэн нэгэн') || ' таны сэтгэгдэлд хариулсан';
  else
    -- Энгийн сэтгэгдэл → постын эзэн
    select user_id into v_target from public.posts where id = new.post_id;
    v_msg := coalesce(v_name,'Хэн нэгэн') || ' таны постод сэтгэгдэл бичлээ';
  end if;
  if v_target is null or v_target = new.user_id then return new; end if;
  insert into public.notifications (user_id, actor_id, actor_name, type, message, post_id)
  values (v_target, new.user_id, v_name, 'comment', v_msg, new.post_id);
  return new;
end;
$$;

-- Сэтгэгдэл лайклах notification
create or replace function public.create_comment_like_notification()
returns trigger language plpgsql security definer as $$
declare v_owner uuid; v_post uuid; v_name text;
begin
  select user_id, post_id into v_owner, v_post
    from public.comments where id = new.comment_id;
  if v_owner is null or v_owner = new.user_id then return new; end if;
  select username into v_name from public.profiles where id = new.user_id;
  insert into public.notifications (user_id, actor_id, actor_name, type, message, post_id)
  values (v_owner, new.user_id, v_name, 'like',
          coalesce(v_name,'Хэн нэгэн') || ' таны сэтгэгдлийг лайкласан', v_post);
  return new;
end;
$$;
drop trigger if exists on_comment_like_notify on public.comment_likes;
create trigger on_comment_like_notify after insert on public.comment_likes
  for each row execute function public.create_comment_like_notification();

notify pgrst, 'reload schema';
