-- NightOwl UB — Save / Bookmark posts
create table if not exists public.saved_posts (
  user_id uuid references public.profiles on delete cascade not null,
  post_id uuid references public.posts on delete cascade not null,
  created_at timestamptz default now(),
  primary key (user_id, post_id)
);
alter table public.saved_posts enable row level security;
drop policy if exists "Own saves viewable" on public.saved_posts;
drop policy if exists "Own saves insert" on public.saved_posts;
drop policy if exists "Own saves delete" on public.saved_posts;
create policy "Own saves viewable" on public.saved_posts for select using (auth.uid() = user_id);
create policy "Own saves insert" on public.saved_posts for insert with check (auth.uid() = user_id);
create policy "Own saves delete" on public.saved_posts for delete using (auth.uid() = user_id);
create index if not exists idx_saved_posts_user on public.saved_posts(user_id, created_at desc);
notify pgrst, 'reload schema';
