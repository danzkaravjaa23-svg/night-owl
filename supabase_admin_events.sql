-- ═══════════════════════════════════════════════════════════════════
-- NightOwl UB — Админ moderation: events
-- events хүснэгтэд зөвхөн select + own-insert policy байсан.
-- Веб админ панелаас эвент устгах/засахын тулд админд эрх нэмнэ.
-- Idempotent.
-- ═══════════════════════════════════════════════════════════════════

drop policy if exists "Admin events update" on public.events;
create policy "Admin events update" on public.events
  for update using (public.is_admin());

drop policy if exists "Admin events delete" on public.events;
create policy "Admin events delete" on public.events
  for delete using (auth.uid() = organizer_id or public.is_admin());

notify pgrst, 'reload schema';
