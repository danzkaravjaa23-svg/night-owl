-- ═══════════════════════════════════════════════════════════════════
-- NightOwl UB — Пост устгахад storage файл цэвэрлэх
-- Пост устахад media файлууд storage-д үлдэж orphan болж зардал нэмдэг.
-- Энэ trigger нь posts устахад posts bucket-аас холбогдох объектуудыг
-- устгана. media_url public URL дотор '/posts/' дараах хэсэг = объектын нэр.
-- SECURITY DEFINER — storage.objects дээр RLS алгасч устгана.
-- ═══════════════════════════════════════════════════════════════════

create or replace function public.cleanup_post_media()
returns trigger language plpgsql security definer as $$
declare
  u text;
  objname text;
begin
  for u in
    select unnest(coalesce(old.media_urls, array[old.media_url]))
  loop
    if u is null or u = '' then
      continue;
    end if;
    objname := split_part(u, '/posts/', 2);
    if objname <> '' then
      delete from storage.objects
        where bucket_id = 'posts' and name = objname;
    end if;
  end loop;
  return old;
end $$;

drop trigger if exists trg_cleanup_post_media on public.posts;
create trigger trg_cleanup_post_media
  after delete on public.posts
  for each row execute function public.cleanup_post_media();

notify pgrst, 'reload schema';
