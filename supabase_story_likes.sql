-- Story лайк table
create table if not exists public.story_likes (
  story_id   uuid not null references public.stories(id) on delete cascade,
  user_id    uuid not null references auth.users(id) on delete cascade,
  created_at timestamptz not null default now(),
  primary key (story_id, user_id)
);
alter table public.story_likes enable row level security;
drop policy if exists "story_likes_select" on public.story_likes;
drop policy if exists "story_likes_insert" on public.story_likes;
drop policy if exists "story_likes_delete" on public.story_likes;
create policy "story_likes_select" on public.story_likes for select using (true);
create policy "story_likes_insert" on public.story_likes for insert with check (auth.uid() = user_id);
create policy "story_likes_delete" on public.story_likes for delete using (auth.uid() = user_id);
