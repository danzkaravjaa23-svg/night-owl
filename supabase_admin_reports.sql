-- ═══════════════════════════════════════════════════════════════════
-- NightOwl UB — Админ moderation
-- Reports-ийн status-ийг админ шинэчлэх (resolved) policy.
-- (Пост устгах нь posts-ийн "Own posts deletable" policy дотор
--  public.is_admin()-ээр аль хэдийн зөвшөөрөгдсөн.)
-- ═══════════════════════════════════════════════════════════════════

drop policy if exists "Admin reports update" on public.reports;
create policy "Admin reports update" on public.reports
  for update using (public.is_admin());

notify pgrst, 'reload schema';
