-- Catalog-only inspection: this function reads NO application/auth rows.
-- It cannot establish that restored policies are semantically safe; perform
-- a separate two-user/owner/admin ACL test before CUTOVER_APPROVED=true.
begin;
create schema nightowl_internal;
revoke all on schema nightowl_internal from public;
grant usage on schema nightowl_internal to nightowl_readiness;

create function nightowl_internal.readiness() returns jsonb
language sql stable security definer set search_path = pg_catalog as $$
  with expected_tables(name) as (values
    ('profiles'), ('venues'), ('posts'), ('likes'), ('follows'),
    ('comments'), ('comment_likes'), ('saved_posts'), ('stories'),
    ('story_views'), ('story_likes'), ('checkins'), ('events'),
    ('event_rsvps'), ('messages'), ('group_chats'), ('group_members'),
    ('group_messages'), ('notes'), ('notifications'), ('blocks'),
    ('reports'), ('venue_reviews'), ('live_streams'), ('live_comments')
  ), table_checks as (
    select e.name, c.oid, c.relrowsecurity,
      exists(select 1 from pg_policy p where p.polrelid = c.oid) as has_policy
    from expected_tables e
    left join pg_class c on c.oid = to_regclass('public.' || e.name)
      and c.relkind in ('r', 'p')
  ), expected_rpcs(signature, argument_names) as (values
    ('public.get_feed_cursor(uuid,integer,timestamp with time zone)', array['p_user_id','p_limit','p_before']),
    ('public.dm_conversations()', array[]::text[]),
    ('public.create_group(text,uuid[])', array['p_name','p_member_ids']),
    ('public.check_in_venue(uuid)', array['p_venue_id']),
    ('public.increment_story_views(uuid)', array['story_id']),
    ('public.increment_viewer(uuid)', array['p_stream']),
    ('public.decrement_viewer(uuid)', array['p_stream'])
  ), rpc_checks as (
    select e.signature,
      p.oid is not null and
      (cardinality(e.argument_names) = 0 or
        p.proargnames[1:cardinality(e.argument_names)] = e.argument_names) as present
    from expected_rpcs e
    left join pg_proc p on p.oid = to_regprocedure(e.signature)
  ), role_checks as (
    select r.rolname from pg_roles r
    where r.rolname in ('anon','authenticated','authenticator','nightowl_readiness')
      and (r.rolsuper or r.rolbypassrls or r.rolcreatedb or r.rolcreaterole
        or (r.rolname in ('anon','authenticated') and r.rolcanlogin)
        or (r.rolname in ('authenticator','nightowl_readiness') and r.rolinherit))
  ), membership_checks as (
    select granted.rolname
    from pg_auth_members m
    join pg_roles member_role on member_role.oid = m.member
    join pg_roles granted on granted.oid = m.roleid
    where member_role.rolname in ('authenticator','nightowl_readiness')
      and (member_role.rolname = 'nightowl_readiness'
        or granted.rolname not in ('anon','authenticated'))
  ), report as (
    select jsonb_build_object(
      'expected_tables', 25,
      'expected_rpcs', 7,
      'missing_tables', coalesce((select jsonb_agg(name order by name) from table_checks where oid is null), '[]'::jsonb),
      'tables_without_rls', coalesce((select jsonb_agg(name order by name) from table_checks where oid is not null and not relrowsecurity), '[]'::jsonb),
      'tables_without_policies', coalesce((select jsonb_agg(name order by name) from table_checks where oid is not null and not has_policy), '[]'::jsonb),
      'missing_rpc_contracts', coalesce((select jsonb_agg(signature order by signature) from rpc_checks where not coalesce(present, false)), '[]'::jsonb),
      'unsafe_roles', coalesce((select jsonb_agg(rolname order by rolname) from role_checks), '[]'::jsonb),
      'unexpected_role_memberships', coalesce((select jsonb_agg(rolname order by rolname) from membership_checks), '[]'::jsonb),
      'tables_without_authenticated_select', coalesce((select jsonb_agg(name order by name) from table_checks where oid is not null and not has_table_privilege('authenticated', oid, 'SELECT')), '[]'::jsonb),
      'rpcs_without_authenticated_execute', coalesce((select jsonb_agg(signature order by signature) from rpc_checks where present and not has_function_privilege('authenticated', to_regprocedure(signature), 'EXECUTE')), '[]'::jsonb),
      'auth_users_present', to_regclass('auth.users') is not null,
      'claim_helpers_present', to_regprocedure('auth.uid()') is not null and to_regprocedure('auth.jwt()') is not null,
      'pg_trgm_present', exists(select 1 from pg_extension where extname = 'pg_trgm')
    ) as result
  )
  select result || jsonb_build_object('ready',
    result->'missing_tables' = '[]'::jsonb and
    result->'tables_without_rls' = '[]'::jsonb and
    result->'tables_without_policies' = '[]'::jsonb and
    result->'missing_rpc_contracts' = '[]'::jsonb and
    result->'unsafe_roles' = '[]'::jsonb and
    result->'unexpected_role_memberships' = '[]'::jsonb and
    result->'tables_without_authenticated_select' = '[]'::jsonb and
    result->'rpcs_without_authenticated_execute' = '[]'::jsonb and
    (result->>'auth_users_present')::boolean and
    (result->>'claim_helpers_present')::boolean and
    (result->>'pg_trgm_present')::boolean)
  from report;
$$;
revoke all on function nightowl_internal.readiness() from public;
grant execute on function nightowl_internal.readiness() to nightowl_readiness;
commit;
