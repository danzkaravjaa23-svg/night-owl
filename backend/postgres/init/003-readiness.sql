-- Catalog-only inspection: this function reads NO application/auth rows.
-- It cannot establish that restored policies are semantically safe; perform
-- a separate two-user/owner/admin ACL test before CUTOVER_APPROVED=true.
begin;
create schema nightowl_internal;
revoke all on schema nightowl_internal from public;
grant usage on schema nightowl_internal to nightowl_readiness;

create function nightowl_internal.readiness() returns jsonb
language sql stable security definer set search_path = pg_catalog as $$
  with read_tables(name) as (values
    ('profiles'), ('venues'), ('posts'), ('likes'), ('follows'),
    ('comments'), ('comment_likes'), ('saved_posts'), ('stories'),
    ('story_views'), ('story_likes'), ('checkins'), ('events'),
    ('event_rsvps'), ('messages'), ('group_chats'), ('group_members'),
    ('group_messages'), ('notes'), ('notifications'), ('blocks'),
    ('reports'), ('venue_reviews'), ('live_streams'), ('live_comments'),
    ('follow_requests'), ('dm_requests'), ('venue_catalog'), ('venue_saves'),
    ('place_collections'), ('collection_places')
  ), rpc_only_tables(name) as (values
    ('discovery_activity'), ('pilot_creators'), ('pilot_participants'),
    ('pilot_venues'), ('pilot_content')
  ), expected_tables(name, access) as (
    select name, 'read' from read_tables
    union all select name, 'rpc' from rpc_only_tables
    union all select 'event_features', 'columns'
  ), table_checks as (
    select e.name, e.access, c.oid, c.relrowsecurity,
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
    ('public.decrement_viewer(uuid)', array['p_stream']),
    ('public.get_relationship(uuid)', array['p_target']),
    ('public.set_follow(uuid,boolean)', array['p_target','p_follow']),
    ('public.respond_follow_request(uuid,boolean)', array['p_requester','p_accept']),
    ('public.respond_message_request(uuid,boolean)', array['p_requester','p_accept']),
    ('public.send_direct_message(uuid,text,text,uuid,text)', array['p_receiver','p_body','p_note','p_story','p_venue']),
    ('public.get_discovery_feed(boolean,timestamp with time zone,uuid,integer)', array['p_following','p_before','p_before_id','p_limit']),
    ('public.get_following_reels(integer)', array['p_limit']),
    ('public.discover_creators(text,text,integer)', array['p_interest','p_query','p_limit']),
    ('public.import_venue_saves(uuid,text[])', array['p_owner','p_refs']),
    ('public.record_discovery_activity(text,text)', array['p_event','p_target']),
    ('public.set_pilot_entry(text,text,boolean)', array['p_kind','p_id','p_enabled']),
    ('public.review_venue(text,jsonb)', array['p_ref','p_details']),
    ('public.get_pilot_overview()', array[]::text[]),
    ('public.search_pilot_candidates(text,text)', array['p_kind','p_query']),
    ('public.get_featured_events()', array[]::text[]),
    ('public.get_admin_featured_events()', array[]::text[]),
    ('public.set_featured_event(uuid,boolean,integer)', array['p_event_id','p_featured','p_rank'])
  ), rpc_checks as (
    select e.signature,
      p.oid is not null and p.pronargs = cardinality(e.argument_names) and
      (cardinality(e.argument_names) = 0 or
        p.proargnames[1:cardinality(e.argument_names)] = e.argument_names) as present
    from expected_rpcs e
    left join pg_proc p on p.oid = to_regprocedure(e.signature) and p.prokind = 'f'
  ), expected_columns(table_name, column_name, type_name) as (values
    ('profiles','id','uuid'), ('profiles','is_admin','boolean'),
    ('profiles','is_verified','boolean'), ('profiles','is_banned','boolean'),
    ('profiles','interests','text[]'), ('profiles','last_seen_at','timestamptz'),
    ('profiles','is_private','boolean'), ('profiles','dm_policy','text'),
    ('posts','id','uuid'), ('posts','user_id','uuid'), ('posts','venue_id','uuid'),
    ('posts','venue_name','text'), ('posts','media_urls','text[]'), ('posts','created_at','timestamptz'),
    ('posts','venue_ref','text'), ('stories','user_id','uuid'), ('stories','venue_id','uuid'),
    ('stories','expires_at','timestamptz'), ('stories','venue_ref','text'),
    ('messages','sender_id','uuid'), ('messages','receiver_id','uuid'),
    ('messages','is_read','boolean'), ('messages','note_text','text'),
    ('messages','story_media_url','text'), ('messages','venue_ref','text'),
    ('venues','id','uuid'), ('venues','owner_id','uuid'), ('events','organizer_id','uuid'),
    ('checkins','audience','text'), ('venue_saves','legacy_import','boolean')
  ), column_checks as (
    select e.table_name || '.' || e.column_name as name,
      a.atttypid = to_regtype(e.type_name) as present
    from expected_columns e
    left join pg_attribute a on a.attrelid = to_regclass('public.' || e.table_name)
      and a.attname = e.column_name and a.attnum > 0 and not a.attisdropped
  ), select_checks as (
    select t.name,
      case when t.access = 'columns' then
        not exists(select 1 from (values ('event_id'), ('rank')) required(name)
          where not exists(select 1 from pg_attribute a where a.attrelid = t.oid
            and a.attname = required.name and a.attnum > 0 and not a.attisdropped
            and has_column_privilege('authenticated', t.oid, a.attnum, 'SELECT')))
      else has_table_privilege('authenticated', t.oid, 'SELECT') end as granted
    from table_checks t where t.oid is not null and t.access <> 'rpc'
  ), rpc_only_grants as (
    select distinct t.name from table_checks t
    cross join (values ('anon'), ('authenticated')) api(role_name)
    where t.oid is not null and t.access = 'rpc' and
      (has_table_privilege(api.role_name, t.oid, 'SELECT,INSERT,UPDATE,DELETE,TRUNCATE,REFERENCES,TRIGGER')
       or has_any_column_privilege(api.role_name, t.oid, 'SELECT,INSERT,UPDATE,REFERENCES'))
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
      'contract_version', '2026-10-20.social-discovery.1',
      'expected_tables', (select count(*) from expected_tables),
      'expected_rpcs', (select count(*) from expected_rpcs),
      'expected_columns', (select count(*) from expected_columns),
      'missing_tables', coalesce((select jsonb_agg(name order by name) from table_checks where oid is null), '[]'::jsonb),
      'tables_without_rls', coalesce((select jsonb_agg(name order by name) from table_checks where oid is not null and not relrowsecurity), '[]'::jsonb),
      'tables_without_policies', coalesce((select jsonb_agg(name order by name) from table_checks where oid is not null and access <> 'rpc' and not has_policy), '[]'::jsonb),
      'incompatible_columns', coalesce((select jsonb_agg(name order by name) from column_checks where not coalesce(present, false)), '[]'::jsonb),
      'rpc_only_tables_with_api_grants', coalesce((select jsonb_agg(name order by name) from rpc_only_grants), '[]'::jsonb),
      'roles_with_public_create', coalesce((select jsonb_agg(role_name order by role_name) from (values ('anon'), ('authenticated')) api(role_name) where has_schema_privilege(role_name, 'public', 'CREATE')), '[]'::jsonb),
      'missing_rpc_contracts', coalesce((select jsonb_agg(signature order by signature) from rpc_checks where not coalesce(present, false)), '[]'::jsonb),
      'unsafe_roles', coalesce((select jsonb_agg(rolname order by rolname) from role_checks), '[]'::jsonb),
      'unexpected_role_memberships', coalesce((select jsonb_agg(rolname order by rolname) from membership_checks), '[]'::jsonb),
      'tables_without_authenticated_select', coalesce((select jsonb_agg(name order by name) from select_checks where not granted), '[]'::jsonb),
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
    result->'incompatible_columns' = '[]'::jsonb and
    result->'rpc_only_tables_with_api_grants' = '[]'::jsonb and
    result->'roles_with_public_create' = '[]'::jsonb and
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
