-- Retired unsafe metadata cleanup. Never DELETE storage.objects from a trigger:
-- it does not remove the backing blob, and a post's user-controlled media_url
-- must never authorize removal of another account's object.
-- https://supabase.com/docs/guides/storage/schema/design
-- Real erasure must use the Storage API and an independently verified owner.
begin;

-- Keep a harmless compatibility function for any legacy trigger aliases.
create or replace function public.cleanup_post_media()
returns trigger language plpgsql security invoker set search_path = '' as $$
begin
  return old;
end;
$$;
revoke all on function public.cleanup_post_media() from public, anon, authenticated;
drop trigger if exists trg_cleanup_post_media on public.posts;

-- Ordinary post deletion no longer pretends to clean up physical files. A
-- verified Storage API cleanup worker remains required for individual posts.
-- The account-deletion handler independently lists the caller's own prefixes.
notify pgrst, 'reload schema';
commit;
