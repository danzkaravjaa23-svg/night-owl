-- ═══════════════════════════════════════════════════════════════════
-- NightOwl UB — Сэтгэгдлийн хариу (reply) + like
-- comments-д parent_id, comment_likes table + likes_count trigger.
-- Idempotent.
-- ═══════════════════════════════════════════════════════════════════

-- Reply — нэг түвшний thread
alter table public.comments
  add column if not exists parent_id uuid references public.comments(id) on delete cascade;
create index if not exists idx_comments_parent on public.comments(parent_id);

-- Сэтгэгдлийн like
create table if not exists public.comment_likes (
  comment_id uuid references public.comments on delete cascade not null,
  user_id    uuid references public.profiles on delete cascade not null,
  created_at timestamptz default now(),
  primary key (comment_id, user_id)
);
alter table public.comment_likes enable row level security;
drop policy if exists "Comment likes viewable" on public.comment_likes;
drop policy if exists "Own comment likes insert" on public.comment_likes;
drop policy if exists "Own comment likes delete" on public.comment_likes;
create policy "Comment likes viewable"   on public.comment_likes for select using (true);
create policy "Own comment likes insert" on public.comment_likes for insert with check (auth.uid() = user_id);
create policy "Own comment likes delete" on public.comment_likes for delete using (auth.uid() = user_id);
create index if not exists idx_comment_likes_comment on public.comment_likes(comment_id);

-- likes_count тоолуурын trigger (SECURITY DEFINER — RLS-ийг алгасч cross-user count)
create or replace function public.bump_comment_likes()
returns trigger language plpgsql security definer as $$
begin
  if (tg_op = 'INSERT') then
    update public.comments set likes_count = coalesce(likes_count,0) + 1
      where id = new.comment_id;
    return new;
  elsif (tg_op = 'DELETE') then
    update public.comments set likes_count = greatest(coalesce(likes_count,0) - 1, 0)
      where id = old.comment_id;
    return old;
  end if;
  return null;
end $$;
drop trigger if exists trg_comment_likes on public.comment_likes;
create trigger trg_comment_likes
  after insert or delete on public.comment_likes
  for each row execute function public.bump_comment_likes();

-- Одоо байгаа тоог backfill
update public.comments c set
  likes_count = coalesce((select count(*) from public.comment_likes cl where cl.comment_id = c.id), 0);

notify pgrst, 'reload schema';
