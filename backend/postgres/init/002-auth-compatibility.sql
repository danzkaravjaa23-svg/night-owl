-- These helpers read transaction claims after PostgREST verifies a JWT.
-- They do not validate JWTs, issue tokens, create users or implement Auth.
begin;
create schema auth;
revoke all on schema auth from public;
grant usage on schema auth to anon, authenticated;

create function auth.jwt() returns jsonb
language sql stable security invoker set search_path = pg_catalog as $$
  select coalesce(nullif(current_setting('request.jwt.claims', true), ''), '{}')::jsonb;
$$;
create function auth.uid() returns uuid
language sql stable security invoker set search_path = pg_catalog as $$
  select nullif(auth.jwt()->>'sub', '')::uuid;
$$;
create function auth.role() returns text
language sql stable security invoker set search_path = pg_catalog as $$
  select auth.jwt()->>'role';
$$;
revoke all on function auth.jwt(), auth.uid(), auth.role() from public;
grant execute on function auth.jwt(), auth.uid(), auth.role() to anon, authenticated;
commit;
