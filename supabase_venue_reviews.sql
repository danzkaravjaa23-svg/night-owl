-- ═══════════════════════════════════════════════════════════════════
-- NightOwl UB — Venue reviews (1-5 од үнэлгээ + сэтгэгдэл)
-- ═══════════════════════════════════════════════════════════════════

create table if not exists public.venue_reviews (
  id uuid default gen_random_uuid() primary key,
  venue_id uuid references public.venues on delete cascade not null,
  user_id  uuid references public.profiles on delete cascade not null,
  rating int not null check (rating between 1 and 5),
  comment text,
  created_at timestamptz default now(),
  unique(venue_id, user_id)
);
create index if not exists idx_venue_reviews_venue on public.venue_reviews(venue_id, created_at desc);
alter table public.venue_reviews enable row level security;
drop policy if exists "Reviews viewable"   on public.venue_reviews;
drop policy if exists "Own review insert"   on public.venue_reviews;
drop policy if exists "Own review update"   on public.venue_reviews;
drop policy if exists "Own review delete"   on public.venue_reviews;
create policy "Reviews viewable" on public.venue_reviews for select using (true);
create policy "Own review insert" on public.venue_reviews for insert with check (auth.uid() = user_id);
create policy "Own review update" on public.venue_reviews for update using (auth.uid() = user_id);
create policy "Own review delete" on public.venue_reviews for delete using (auth.uid() = user_id);

-- venues-д дундаж үнэлгээ + тоо
alter table public.venues add column if not exists rating numeric(2,1) default 0;
alter table public.venues add column if not exists review_count int default 0;

-- Тоолуур автоматаар шинэчлэх (security definer)
create or replace function public.update_venue_rating()
returns trigger language plpgsql security definer as $$
declare v uuid;
begin
  v := coalesce(new.venue_id, old.venue_id);
  update public.venues set
    rating = coalesce((select round(avg(rating)::numeric, 1) from public.venue_reviews where venue_id = v), 0),
    review_count = (select count(*) from public.venue_reviews where venue_id = v)
  where id = v;
  return null;
end; $$;
drop trigger if exists on_venue_review_change on public.venue_reviews;
create trigger on_venue_review_change
  after insert or update or delete on public.venue_reviews
  for each row execute function public.update_venue_rating();

notify pgrst, 'reload schema';
