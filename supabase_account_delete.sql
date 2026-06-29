-- ═══════════════════════════════════════════════════════════════════
-- NightOwl UB — Данс устгах (self-service, App Store 5.1.1(v) / GDPR)
-- Хэрэглэгч өөрийн profiles мөрийг устгаж болно. Бусад бүх контент
-- (posts/comments/likes/follows/stories/messages/notifications...) FK
-- on delete cascade-ээр устана. posts устахад storage trigger файлыг
-- цэвэрлэнэ. events.organizer_id / venues.owner_id нь set null.
-- ТЭМДЭГЛЭЛ: auth.users мөрийг client устгаж чадахгүй (service role
--   шаардана) — бүрэн устгалд edit function хэрэгтэй. Энэ нь profiles +
--   бүх контентыг устгана.
-- ═══════════════════════════════════════════════════════════════════

drop policy if exists "Own profile deletable" on public.profiles;
create policy "Own profile deletable" on public.profiles
  for delete using (auth.uid() = id or public.is_admin());

notify pgrst, 'reload schema';
