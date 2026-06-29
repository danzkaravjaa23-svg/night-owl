-- ═══════════════════════════════════════════════════════════════════
-- NightOwl UB — Хайлтын trigram индекс (pg_trgm)
-- `ilike '%q%'` нь leading-wildcard тул энгийн B-tree индекс ажиллахгүй,
-- 500к профайл дээр бүтэн scan хийдэг. GIN trigram индекс substring
-- ilike-ийг индексээр хурдасгана.
-- ═══════════════════════════════════════════════════════════════════

create extension if not exists pg_trgm;

create index if not exists idx_profiles_username_trgm
  on public.profiles using gin (username gin_trgm_ops);

create index if not exists idx_venues_name_trgm
  on public.venues using gin (name gin_trgm_ops);

notify pgrst, 'reload schema';
