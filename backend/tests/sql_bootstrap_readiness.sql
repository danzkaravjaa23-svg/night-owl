-- Only execute in an isolated *_backend_test database AFTER the bootstrap.
-- Every probe/attribute change below is rolled back; no source data is used.
begin;
do $$
declare report jsonb;
begin
  if current_database() !~ '_backend_test$' then
    raise exception 'Integration tests require an isolated *_backend_test database';
  end if;
  report := nightowl_internal.readiness();
  if (report->>'ready')::boolean then
    raise exception 'Empty destination incorrectly passed readiness';
  end if;
  if jsonb_array_length(report->'missing_tables') <> 25 or
     jsonb_array_length(report->'missing_rpc_contracts') <> 7 then
    raise exception 'Authoritative missing table/RPC inventory is incomplete';
  end if;
  if (report->>'auth_users_present')::boolean then
    raise exception 'Bootstrap must not manufacture Auth users';
  end if;
  if report->'unsafe_roles' <> '[]'::jsonb or
     report->'unexpected_role_memberships' <> '[]'::jsonb then
    raise exception 'Bootstrap created unsafe API roles';
  end if;
  if has_function_privilege('anon', 'nightowl_internal.readiness()', 'EXECUTE') or
     has_function_privilege('authenticated', 'nightowl_internal.readiness()', 'EXECUTE') then
    raise exception 'Private inventory function leaked API execution rights';
  end if;
end;
$$;

create table public.bootstrap_acl_probe (id uuid primary key);
create function public.bootstrap_acl_probe_rpc() returns integer
language sql as $$ select 1; $$;
do $$
declare api_role text;
begin
  foreach api_role in array array['anon','authenticated','authenticator','nightowl_readiness']
  loop
    if has_table_privilege(api_role, 'public.bootstrap_acl_probe', 'SELECT,INSERT,UPDATE,DELETE') then
      raise exception 'Bootstrap gave % implicit application table privileges', api_role;
    end if;
    if has_function_privilege(api_role, 'public.bootstrap_acl_probe_rpc()', 'EXECUTE') then
      raise exception 'New RPC implicitly became executable by %', api_role;
    end if;
  end loop;
end;
$$;

set local role authenticated;
do $$
begin
  perform set_config('request.jwt.claims', '', true);
  if auth.uid() is not null or auth.jwt() <> '{}'::jsonb then
    raise exception 'Missing claims must not manufacture an identity';
  end if;
  perform set_config('request.jwt.claims', '{"sub":"00000000-0000-4000-8000-000000000001","role":"authenticated"}', true);
  if auth.uid() <> '00000000-0000-4000-8000-000000000001'::uuid or auth.role() <> 'authenticated' then
    raise exception 'Transaction claims were not read by the compatibility helpers';
  end if;
  -- These are SQL helper tests; they do not substitute for signed JWT tests.
  perform set_config('request.jwt.claims', '{"sub":"not-a-uuid"}', true);
  begin
    perform auth.uid();
    raise exception 'Malformed UUID claim accepted';
  exception when invalid_text_representation then
    null;
  end;
  perform set_config('request.jwt.claims', 'not-json', true);
  begin
    perform auth.jwt();
    raise exception 'Malformed JSON claims accepted';
  exception when invalid_text_representation then
    null;
  end;
  perform set_config('request.jwt.claims', '', true);
  begin
    perform id from public.bootstrap_acl_probe;
    raise exception 'Authenticated role accessed ungranted application rows';
  exception when insufficient_privilege then
    null;
  end;
end;
$$;
reset role;

set local role nightowl_readiness;
do $$
begin
  if (nightowl_internal.readiness()->>'ready')::boolean then
    raise exception 'Restricted metadata caller unexpectedly passed an empty destination';
  end if;
  begin
    perform id from public.bootstrap_acl_probe;
    raise exception 'Readiness role accessed application rows';
  exception when insufficient_privilege then
    null;
  end;
end;
$$;
reset role;

-- Detect an unsafe restored role instead of silently trusting it.
alter role authenticator bypassrls;
do $$
begin
  if not (nightowl_internal.readiness()->'unsafe_roles' ? 'authenticator') then
    raise exception 'Readiness missed API RLS bypass privilege';
  end if;
end;
$$;
rollback;

select 'PASS: missing schema/RPCs, private inventory, no implicit grants, malformed claims, restricted metadata, unsafe-role detection' as verification;
