-- Staging first. Close legacy bypasses before enabling the deletion endpoint.
-- No Auth user, profile, post or Storage object is deleted by this migration.
begin;

do $$
begin
  if not exists (select 1 from pg_catalog.pg_class
    where oid = 'public.profiles'::regclass and relrowsecurity) then
    raise exception 'Profile RLS must already be enabled';
  end if;
end;
$$;

-- A direct profile DELETE bypasses account confirmation, provider revocation,
-- Storage erasure, and Auth deletion. Browser admins also use the server flow.
drop policy if exists "Own profile deletable" on public.profiles;
drop policy if exists account_profile_delete_guard on public.profiles;
create policy account_profile_delete_guard on public.profiles as restrictive
  for delete to anon, authenticated using (false);
revoke delete, truncate on public.profiles from public, anon, authenticated;

-- The old definer trigger accepted arbitrary post media URLs and deleted their
-- storage.objects metadata, including other users' objects. Metadata deletion
-- also strands physical blobs. Neutralize every alias of the legacy function,
-- and detach the known trigger. Physical cleanup belongs to the Storage API.
create or replace function public.cleanup_post_media()
returns trigger language plpgsql security invoker set search_path = '' as $$
begin
  return old;
end;
$$;
revoke all on function public.cleanup_post_media() from public, anon, authenticated;
drop trigger if exists trg_cleanup_post_media on public.posts;

notify pgrst, 'reload schema';
commit;
