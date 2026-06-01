-- ═══════════════════════════════════════════════════════════════════
-- NightOwl UB — Venue ownership (бизнес эзэн өөрийн venue-г засна)
-- Supabase SQL Editor-т хуулаад Run дар.
-- ═══════════════════════════════════════════════════════════════════

-- venues-д эзэн (business profile)
alter table public.venues
  add column if not exists owner_id uuid references public.profiles(id) on delete set null;
create index if not exists idx_venues_owner on public.venues(owner_id) where owner_id is not null;

-- RLS: эзэн ӨӨРӨӨ эсвэл admin л venue-г insert/update/delete хийнэ
drop policy if exists "Admin venues insert" on public.venues;
drop policy if exists "Admin venues update" on public.venues;
drop policy if exists "Admin venues delete" on public.venues;
drop policy if exists "Venue owner insert" on public.venues;
drop policy if exists "Venue owner update" on public.venues;
drop policy if exists "Venue owner delete" on public.venues;

create policy "Venue owner insert" on public.venues for insert
  with check (auth.uid() = owner_id or public.is_admin());
create policy "Venue owner update" on public.venues for update
  using (auth.uid() = owner_id or public.is_admin());
create policy "Venue owner delete" on public.venues for delete
  using (auth.uid() = owner_id or public.is_admin());

-- (select бол "Venues viewable" policy-аар бүгдэд нээлттэй хэвээр)
