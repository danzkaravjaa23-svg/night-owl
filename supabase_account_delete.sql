-- Retired: deleting a profiles row is NOT account deletion. It leaves the Auth
-- identity and may bypass Apple revocation and Storage API cleanup.
-- Only the authenticated server deletion workflow may erase the account.
-- This restrictive policy also intersects any permissive legacy admin policy.
begin;

alter table public.profiles enable row level security;
drop policy if exists "Own profile deletable" on public.profiles;
drop policy if exists account_profile_delete_guard on public.profiles;
create policy account_profile_delete_guard on public.profiles as restrictive
  for delete to anon, authenticated using (false);
revoke delete, truncate on public.profiles from public, anon, authenticated;

-- Auth's trusted FK cascade and service-role recovery are unaffected by client
-- privileges/RLS. Verify the real FK schema on disposable staging before enable.
notify pgrst, 'reload schema';
commit;
