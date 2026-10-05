-- Apply in staging, then production, BEFORE releasing this client.
-- A check-in is one current venue per user, with a server-controlled expiry.
begin;
create or replace function public.check_in_venue(p_venue_id uuid)
returns table(venue_id uuid, expires_at timestamptz)
language plpgsql security definer set search_path = '' as $$
declare
  v_user uuid := auth.uid();
  v_expiry timestamptz := now() + interval '4 hours';
begin
  if v_user is null then raise exception 'Authentication required' using errcode = '42501'; end if;
  -- Serialize simultaneous taps/devices without trusting a client-supplied user ID.
  perform 1 from public.profiles where id = v_user for update;
  if not found then raise exception 'Profile required'; end if;
  perform 1 from public.venues where id = p_venue_id and name !~ ' #[0-9]+$';
  if not found then raise exception 'Venue not found'; end if;
  -- Definer access also removes expired rows hidden by the public SELECT policy.
  delete from public.checkins where user_id = v_user;
  insert into public.checkins(user_id, venue_id, created_at, expires_at)
    values (v_user, p_venue_id, now(), v_expiry);
  return query select p_venue_id, v_expiry;
end;
$$;
revoke all on function public.check_in_venue(uuid) from public, anon;
grant execute on function public.check_in_venue(uuid) to authenticated;
commit;
