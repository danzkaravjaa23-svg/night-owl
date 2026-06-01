-- ═══════════════════════════════════════════════════════════════════
-- NightOwl UB — Storage Bucket Setup + RLS (мэргэжлийн, дата хэмнэлттэй)
-- ───────────────────────────────────────────────────────────────────
-- Зорилго: Улаанбаатарын хэрэглэгчид (мобайл дата үнэтэй, 4G/3G холимог)
-- зориулж дата хэмнэлттэй, аюулгүй Storage тохиргоо.
--
-- Дата хэмнэх 4 зарчим:
--   1) Bucket бүрт ФАЙЛЫН ХЭМЖЭЭНИЙ ХЯЗГААР — том файл upload-ыг таслана
--   2) Зөвшөөрөгдсөн MIME төрөл — зөвхөн зураг/видео, бусдыг блоклоно
--   3) CDN кэш (cache-control) — нэг файлыг дахин дахин татахгүй
--   4) Аппын талд compress (imageQuality 85, maxWidth 1080 — одоо хийгдсэн)
--
-- Хэрэглэх: Supabase SQL Editor-т хуулаад Run. Idempotent.
-- ═══════════════════════════════════════════════════════════════════

-- ───────────────────────────────────────────────────────────────────
-- SECTION 1 — Bucket-ууд (хэмжээний хязгаар + MIME + public)
-- ───────────────────────────────────────────────────────────────────
-- file_size_limit нэгж = byte.
--   avatars  2 MB   (профайл зураг — жижиг)
--   posts   50 MB   (feed зураг + видео)
--   stories 50 MB   (24ц story, видео)
--   venues   5 MB   (газрын зураг — admin/business)
-- ⚠️ Видео 50MB-ийн дотор багтах ёстой. UB дата хэмнэхийн тулд апп талд
--    видеог compress хийх / 15-30сек хязгаарлахыг зөвлөнө (video_compress).
-- MIME: Apple .mov (video/quicktime), iPhone .heic зэргийг оруулсан
insert into storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
values
  ('avatars', 'avatars', true,  2097152,  array['image/jpeg','image/png','image/webp','image/heic','image/heif']),
  ('posts',   'posts',   true, 52428800,  array['image/jpeg','image/png','image/webp','image/heic','image/heif','image/gif','video/mp4','video/webm','video/quicktime','video/x-m4v']),
  ('stories', 'stories', true, 52428800,  array['image/jpeg','image/png','image/webp','image/heic','image/heif','image/gif','video/mp4','video/webm','video/quicktime','video/x-m4v']),
  ('venues',  'venues',  true,  5242880,  array['image/jpeg','image/png','image/webp','image/heic','image/heif'])
on conflict (id) do update set
  public             = excluded.public,
  file_size_limit    = excluded.file_size_limit,
  allowed_mime_types = excluded.allowed_mime_types;


-- ───────────────────────────────────────────────────────────────────
-- SECTION 2 — RLS policy (storage.objects дээр)
-- ───────────────────────────────────────────────────────────────────
-- Аппын upload зам үргэлж '<user_id>/файл.jpg' бүтэцтэй (image_uploader.dart),
-- тиймээс хэрэглэгч ЗӨВХӨН өөрийн id-тэй фолдерт бичиж/устгаж чадна.
-- Унших нь public (feed/profile/story бүгдэд харагдана).

-- 2a. Бүх 4 bucket-аас унших — public
drop policy if exists "NightOwl public read" on storage.objects;
create policy "NightOwl public read"
  on storage.objects for select
  using (bucket_id in ('avatars','posts','stories','venues'));

-- 2b. Өөрийн фолдерт upload (insert) — зөвхөн нэвтэрсэн хэрэглэгч
drop policy if exists "NightOwl own folder insert" on storage.objects;
create policy "NightOwl own folder insert"
  on storage.objects for insert to authenticated
  with check (
    bucket_id in ('avatars','posts','stories','venues')
    and (storage.foldername(name))[1] = auth.uid()::text
  );

-- 2c. Өөрийн файлыг шинэчлэх (upsert/update)
drop policy if exists "NightOwl own folder update" on storage.objects;
create policy "NightOwl own folder update"
  on storage.objects for update to authenticated
  using (
    bucket_id in ('avatars','posts','stories','venues')
    and (storage.foldername(name))[1] = auth.uid()::text
  );

-- 2d. Өөрийн файлыг устгах
drop policy if exists "NightOwl own folder delete" on storage.objects;
create policy "NightOwl own folder delete"
  on storage.objects for delete to authenticated
  using (
    bucket_id in ('avatars','posts','stories','venues')
    and (storage.foldername(name))[1] = auth.uid()::text
  );

-- ═══════════════════════════════════════════════════════════════════
-- ШАЛГАХ:  select id, public, file_size_limit, allowed_mime_types
--          from storage.buckets;
-- ═══════════════════════════════════════════════════════════════════

-- ───────────────────────────────────────────────────────────────────
-- ЗӨВЛӨМЖ (дата хэмнэх — кодын талд, энэ файлд биш):
--   • Post зураг upload-д cache-control урт болгох (immutable, timestamp-тэй
--     зам тул): FileOptions(cacheControl: '31536000'). avatars-д '3600'
--     (upsert хийдэг тул) — image_uploader.dart-д тохируулна.
--   • Зургийг WebP болгож хадгалбал JPEG-ээс ~30% бага (дата хэмнэнэ).
--   • Feed-д thumbnail хэмжээ (resize) ашиглах — Supabase image transform
--     (Pro feature) эсвэл upload үед жижиг хувилбар үүсгэх.
-- ───────────────────────────────────────────────────────────────────
