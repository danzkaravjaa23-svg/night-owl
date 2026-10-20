// Catalog-only fixtures in an isolated in-memory database. No live service or
// account is contacted; the RPC stubs are NOT application implementations.
import assert from 'node:assert/strict';
import { readFile } from 'node:fs/promises';
import { fileURLToPath, pathToFileURL } from 'node:url';
import path from 'node:path';

const modulePath = process.argv[2];
if (!modulePath || !path.isAbsolute(modulePath)) {
  throw new Error('Pass an absolute path to the official PGlite dist/index.js');
}
const { PGlite } = await import(pathToFileURL(modulePath).href);
const { pg_trgm } = await import(pathToFileURL(path.join(path.dirname(modulePath), 'contrib/pg_trgm.js')).href);
const root = path.resolve(path.dirname(fileURLToPath(import.meta.url)), '..');
const db = new PGlite({ extensions: { pg_trgm } });
const read = file => readFile(path.join(root, file), 'utf8');
const report = async () => (await db.query('select nightowl_internal.readiness() as report')).rows[0].report;
const contract = '2026-10-20.social-discovery.1';

const readTables = [
  'profiles', 'venues', 'posts', 'likes', 'follows', 'comments',
  'comment_likes', 'saved_posts', 'stories', 'story_views', 'story_likes',
  'checkins', 'events', 'event_rsvps', 'messages', 'group_chats',
  'group_members', 'group_messages', 'notes', 'notifications', 'blocks',
  'reports', 'venue_reviews', 'live_streams', 'live_comments',
  'follow_requests', 'dm_requests', 'venue_catalog', 'venue_saves',
  'place_collections', 'collection_places',
];
const rpcOnlyTables = ['discovery_activity', 'pilot_creators', 'pilot_participants', 'pilot_venues', 'pilot_content'];
const columns = {
  profiles: 'id uuid, is_admin boolean, is_verified boolean, is_banned boolean, interests text[], last_seen_at timestamptz, is_private boolean, dm_policy text',
  posts: 'id uuid, user_id uuid, venue_id uuid, venue_name text, media_urls text[], created_at timestamptz, venue_ref text',
  stories: 'user_id uuid, venue_id uuid, expires_at timestamptz, venue_ref text',
  messages: 'sender_id uuid, receiver_id uuid, is_read boolean, note_text text, story_media_url text, venue_ref text',
  checkins: 'audience text',
  venues: 'id uuid, owner_id uuid',
  events: 'organizer_id uuid',
  venue_saves: 'legacy_import boolean',
};
const rpcs = [
  ['get_feed_cursor', 'p_user_id uuid,p_limit integer,p_before timestamptz'],
  ['dm_conversations', ''], ['create_group', 'p_name text,p_member_ids uuid[]'],
  ['check_in_venue', 'p_venue_id uuid'], ['increment_story_views', 'story_id uuid'],
  ['increment_viewer', 'p_stream uuid'], ['decrement_viewer', 'p_stream uuid'],
  ['get_relationship', 'p_target uuid'], ['set_follow', 'p_target uuid,p_follow boolean'],
  ['respond_follow_request', 'p_requester uuid,p_accept boolean'],
  ['respond_message_request', 'p_requester uuid,p_accept boolean'],
  ['send_direct_message', 'p_receiver uuid,p_body text,p_note text,p_story uuid,p_venue text'],
  ['get_discovery_feed', 'p_following boolean,p_before timestamptz,p_before_id uuid,p_limit integer'],
  ['get_following_reels', 'p_limit integer'],
  ['discover_creators', 'p_interest text,p_query text,p_limit integer'],
  ['import_venue_saves', 'p_owner uuid,p_refs text[]'],
  ['record_discovery_activity', 'p_event text,p_target text'],
  ['set_pilot_entry', 'p_kind text,p_id text,p_enabled boolean'],
  ['review_venue', 'p_ref text,p_details jsonb'], ['get_pilot_overview', ''],
  ['search_pilot_candidates', 'p_kind text,p_query text'],
  ['get_featured_events', ''], ['get_admin_featured_events', ''],
  ['set_featured_event', 'p_event_id uuid,p_featured boolean,p_rank integer'],
];

async function refused(sql, field, expected) {
  await db.exec('begin');
  try {
    await db.exec(sql);
    const result = await report();
    assert.equal(result.ready, false, `${field} incorrectly passed`);
    assert.ok(result[field].includes(expected), `${field} missed ${expected}`);
  } finally {
    await db.exec('rollback');
  }
}

try {
  for (const file of ['001-roles.sql', '002-auth-compatibility.sql', '003-readiness.sql']) {
    await db.exec(await read(`postgres/init/${file}`));
  }
  const empty = await report();
  assert.equal(empty.contract_version, contract);
  assert.equal(empty.expected_tables, 37);
  assert.equal(empty.expected_rpcs, 24);
  assert.equal(empty.expected_columns, 30);
  assert.equal(empty.missing_tables.length, 37);
  assert.equal(empty.missing_rpc_contracts.length, 24);
  assert.equal(empty.ready, false);
  await db.exec('create extension pg_trgm; create table auth.users(id uuid primary key)');
  for (const table of [...readTables, ...rpcOnlyTables]) {
    await db.exec(`create table public.${table} (${columns[table] ?? 'id uuid'}); alter table public.${table} enable row level security`);
    if (readTables.includes(table)) {
      await db.exec(`create policy fixture_read on public.${table} for select using(true); grant select on public.${table} to authenticated`);
    }
  }
  await db.exec(`create table public.event_features(event_id uuid, rank integer);
    alter table public.event_features enable row level security;
    create policy fixture_read on public.event_features for select using(true);
    grant select(event_id,rank) on public.event_features to authenticated`);
  for (const [name, args] of rpcs) {
    await db.exec(`create function public.${name}(${args}) returns jsonb language sql as $$ select '{}'::jsonb $$`);
  }
  await db.exec('grant execute on all functions in schema public to authenticated');
  assert.equal((await report()).ready, true);

  await refused('drop function public.get_following_reels(integer)', 'missing_rpc_contracts', 'public.get_following_reels(integer)');
  await refused("drop function public.set_follow(uuid,boolean); create function public.set_follow(target uuid,p_follow boolean) returns jsonb language sql as $$ select '{}'::jsonb $$", 'missing_rpc_contracts', 'public.set_follow(uuid,boolean)');
  await refused('revoke execute on function public.review_venue(text,jsonb) from authenticated', 'rpcs_without_authenticated_execute', 'public.review_venue(text,jsonb)');
  await refused('alter table public.profiles alter column is_private type text using is_private::text', 'incompatible_columns', 'profiles.is_private');
  await refused('alter table public.messages drop column venue_ref', 'incompatible_columns', 'messages.venue_ref');
  await refused('alter table public.place_collections disable row level security', 'tables_without_rls', 'place_collections');
  await refused('drop policy fixture_read on public.venue_saves', 'tables_without_policies', 'venue_saves');
  await refused('revoke select on public.collection_places from authenticated', 'tables_without_authenticated_select', 'collection_places');
  await refused('revoke select(rank) on public.event_features from authenticated', 'tables_without_authenticated_select', 'event_features');
  await refused('grant select on public.pilot_participants to authenticated', 'rpc_only_tables_with_api_grants', 'pilot_participants');
  await refused('grant select(id) on public.discovery_activity to anon', 'rpc_only_tables_with_api_grants', 'discovery_activity');
  await refused('grant create on schema public to anon', 'roles_with_public_create', 'anon');
  await refused('alter role authenticator bypassrls', 'unsafe_roles', 'authenticator');
  await db.exec('set role nightowl_readiness');
  assert.equal((await report()).ready, true);
  await assert.rejects(db.query('select * from public.profiles'), error => error.code === '42501');
  console.log('PASS: current migration contract, 37 tables/24 RPCs/30 columns, private catalog role, narrow column grants, RPC-only tables and fail-closed schema/ACL regressions. Synthetic metadata only; not service integration.');
} finally {
  await db.close();
}
