// Synthetic in-memory PostgreSQL only. Never connects to a hosted database.
import assert from 'node:assert/strict';
import {readFile} from 'node:fs/promises';
import {pathToFileURL} from 'node:url';
const {PGlite} = await import(pathToFileURL(process.argv[2]).href);
const db = new PGlite();
const read = file => readFile(new URL('../../../' + file, import.meta.url), 'utf8');
const viewer = '10000000-0000-0000-0000-000000000001';
const author = '10000000-0000-0000-0000-000000000002';
const venue = '20000000-0000-0000-0000-000000000001';
const source = 'osm:node:123';
let passed = 0;
const check = (name, body) => {body(); passed++; console.log(`PASS: ${name}`);};
const login = async id => db.exec(`reset role;select set_config('request.jwt.claim.sub','${id ?? ''}',false);set role ${id ? 'authenticated' : 'anon'}`);
const maintenance = async () => db.exec("reset role;select set_config('request.jwt.claim.sub','',false)");
const activity = async () => (await db.query('select * from public.venue_map_activity()')).rows;
const total = rows => rows.reduce((n, row) => n + Number(row.story_count) + Number(row.post_count), 0);
const state = async () => (await db.query(`select
  (select jsonb_agg(to_jsonb(p) order by id) from posts p) as posts,
  (select jsonb_agg(to_jsonb(s) order by id) from stories s) as stories,
  (select jsonb_agg(jsonb_build_object('relation',polrelid::regclass::text,'name',polname,'kind',polcmd,'permissive',polpermissive,'using',pg_get_expr(polqual,polrelid),'check',pg_get_expr(polwithcheck,polrelid)) order by polrelid,polname)
   from pg_policy where polrelid in ('public.posts'::regclass,'public.stories'::regclass)) as policies,
  (select jsonb_agg(jsonb_build_object('table',oid::regclass::text,'acl',relacl) order by oid)
   from pg_class where oid in ('public.posts'::regclass,'public.stories'::regclass)) as table_acl,
  (select md5(prosrc) from pg_proc where oid='public.venue_story_activity_today()'::regprocedure) as legacy_api
`)).rows[0];
const rejected = async (sql, code) => {
  await db.exec('savepoint expected_rejection');
  try {
    await assert.rejects(db.exec(sql), error => error.code === code);
  } finally {
    await db.exec('rollback to savepoint expected_rejection;release savepoint expected_rejection');
  }
};
try {
  await db.exec(await read('tools/deployment/tests/social_discovery_fixture.sql'));
  await db.exec('alter table stories add column created_at timestamptz not null default now()');
  await db.exec(await read('supabase/migrations/202610160001_social_discovery.sql'));
  // Production has owner update/delete policies. These synthetic permissive
  // policies exercise the existing restrictive social policies in composition.
  await db.exec(`create policy fixture_own_post_update on posts for update using(user_id=auth.uid()) with check(user_id=auth.uid());
    create policy fixture_own_post_delete on posts for delete using(user_id=auth.uid());`);
  await db.exec(await read('supabase/migrations/202611030005_venue_story_activity.sql'));
  const before = await state();
  const migration = await read('supabase/migrations/202611030007_venue_map_activity.sql');
  await db.exec(migration);
  await db.exec(migration);
  const after = await state();
  check('idempotent install does not mutate existing rows, row ACL, RLS, or legacy story API', () => assert.deepEqual(after, before));
  const fn = (await db.query("select prosecdef,provolatile,proconfig from pg_proc where oid='public.venue_map_activity()'::regprocedure")).rows[0];
  check('stable SECURITY INVOKER with pinned search path', () => assert.deepEqual(fn, {
    prosecdef: false, provolatile: 's', proconfig: ['search_path=public, pg_temp'],
  }));
  const grants = (await db.query(`select
    has_function_privilege('anon','public.venue_map_activity()','execute') as anon,
    has_function_privilege('authenticated','public.venue_map_activity()','execute') as authenticated,
    exists(select 1 from pg_proc p cross join lateral aclexplode(p.proacl) a where p.oid='public.venue_map_activity()'::regprocedure and a.grantee=0) as public_access,
    has_function_privilege('authenticated','public.protect_post_publication_clock()','execute') as direct_clock_access`)).rows[0];
  check('only explicit API roles receive execute; publication trigger has no direct client grant', () => assert.deepEqual(grants, {
    anon: true, authenticated: true, public_access: false, direct_clock_access: false,
  }));
  await db.exec('begin'); // Every edge compares against the same server now().
  await db.exec(`insert into venue_catalog(ref,name) values('${source}','Synthetic OSM place');
    insert into stories(user_id,venue_ref,created_at,expires_at) values
      ('${author}','${venue}',date_trunc('day',now() at time zone 'Asia/Ulaanbaatar') at time zone 'Asia/Ulaanbaatar',now()+interval '30 minutes'),
      ('${author}','${source}',now(),now()+interval '50 minutes');
    insert into stories(user_id,venue_id,venue_ref,created_at,expires_at) values
      ('${author}','${venue}','${venue}',now(),now()+interval '40 minutes');
    alter table stories disable trigger normalize_venue_reference;
    insert into stories(user_id,venue_id,created_at,expires_at) values
      ('${author}','${venue}',now(),now()+interval '20 minutes');
    alter table stories enable trigger normalize_venue_reference;
    insert into stories(user_id,venue_ref,created_at,expires_at) values
      ('${author}','${venue}',(date_trunc('day',now() at time zone 'Asia/Ulaanbaatar') at time zone 'Asia/Ulaanbaatar')-interval '1 microsecond',now()+interval '1 day'),
      ('${author}','${venue}',now(),now()),
      ('${author}','${venue}',now()+interval '1 microsecond',now()+interval '1 day'),
      ('${author}',null,now(),now()+interval '1 day');
    -- Only the fixture owner can bypass the new guard to model older imports.
    alter table posts disable trigger protect_post_publication_clock;
    insert into posts(id,user_id,venue_ref,created_at,caption) values
      ('40000000-0000-0000-0000-000000000001','${author}','${venue}',now()-interval '168 hours'+interval '1 microsecond','Last valid microsecond'),
      ('40000000-0000-0000-0000-000000000002','${author}','${venue}',now()-interval '168 hours','Exactly expired'),
      ('40000000-0000-0000-0000-000000000003','${author}','${venue}',now()-interval '168 hours'-interval '1 microsecond','Already expired'),
      ('40000000-0000-0000-0000-000000000004','${author}','${venue}',now()+interval '1 microsecond','Future import'),
      ('40000000-0000-0000-0000-000000000005','${author}',null,now(),'No location'),
      ('40000000-0000-0000-0000-000000000006','${author}','${source}',now()-interval '24 hours','OSM post'),
      ('40000000-0000-0000-0000-000000000007','${author}','${venue}',now(),'Now inclusive');
    insert into posts(user_id,venue_id,venue_ref,created_at) values('${author}','${venue}','${venue}',now()-interval '2 hours');
    alter table posts disable trigger normalize_venue_reference;
    insert into posts(user_id,venue_id,created_at) values('${author}','${venue}',now()-interval '4 hours');
    alter table posts enable trigger normalize_venue_reference;
    alter table posts enable trigger protect_post_publication_clock;`);
  await login(null);
  let rows = await activity();
  check('anonymous aggregates readable stories plus posts by canonical UUID and OSM reference', () => {
    assert.equal(rows.length, 2);
    assert.equal(Number(rows.find(r => r.venue_ref === venue).story_count), 3);
    assert.equal(Number(rows.find(r => r.venue_ref === venue).post_count), 4);
    assert.equal(Number(rows.find(r => r.venue_ref === source).story_count), 1);
    assert.equal(Number(rows.find(r => r.venue_ref === source).post_count), 1);
    assert.equal(total(rows), 9);
  });
  const expected = (await db.query("select (now() at time zone 'Asia/Ulaanbaatar')::date as day,now()+interval '1 microsecond' as expiry")).rows[0];
  check('168h lower boundary exclusive, now inclusive; future, expired, and unlocated excluded', () => {
    assert.deepEqual(rows[0].activity_day, expected.day);
    assert.deepEqual(rows.find(r => r.venue_ref === venue).next_expiry, expected.expiry);
  });
  for (const zone of ['Pacific/Honolulu', 'America/New_York', 'UTC']) {
    await db.exec(`set time zone '${zone}'`);
    assert.deepEqual(await activity(), rows);
  }
  await db.exec("set time zone 'America/New_York'");
  const dst = (await db.query(`select
    extract(epoch from (('2026-11-03T12:00:00Z'::timestamptz)-('2026-11-03T12:00:00Z'::timestamptz-interval '168 hours'))) as elapsed,
    ('2026-11-03T12:00:00Z'::timestamptz-interval '168 hours')='2026-10-27T12:00:00Z'::timestamptz as dst_safe`)).rows[0];
  check('168 elapsed hours and UB story calendar are independent of UTC, Honolulu, and DST session zones', () => {
    assert.equal(Number(dst.elapsed), 604800);
    assert.equal(dst.dst_safe, true);
  });
  await maintenance();
  await db.exec(`update profiles set is_private=true where id='${author}'`);
  await login(null);
  rows = await activity();
  check('anonymous sees no private location activity', () => assert.deepEqual(rows, []));
  await login(viewer);
  assert.deepEqual(await activity(), []);
  check('nonfollower sees no private location activity', () => {});
  await login(author);
  rows = await activity();
  check('active private author sees own story and post activity', () => assert.equal(total(rows), 9));
  await maintenance();
  await db.exec(`insert into follows values('${viewer}','${author}')`);
  await login(viewer);
  assert.equal(total(await activity()), 9);
  check('approved follower sees private activity', () => {});
  await maintenance();
  await db.exec(`insert into blocks values('${viewer}','${author}')`);
  await login(viewer);
  assert.deepEqual(await activity(), []);
  check('outgoing block removes both activity sources', () => {});
  await maintenance();
  await db.exec(`delete from blocks where blocker_id='${viewer}' and blocked_id='${author}';update profiles set is_private=false where id='${author}';insert into blocks values('${author}','${viewer}')`);
  await login(viewer);
  assert.deepEqual(await activity(), []);
  check('incoming block removes both activity sources', () => {});
  await maintenance();
  await db.exec(`delete from blocks where blocker_id='${author}' and blocked_id='${viewer}';update profiles set is_banned=true where id='${author}'`);
  await login(viewer);
  assert.deepEqual(await activity(), []);
  await login(author);
  assert.deepEqual(await activity(), []);
  check('banned author excluded even from self-read RLS', () => {});
  await maintenance();
  await db.exec(`update profiles set is_banned=false where id='${author}';update profiles set is_banned=true where id='${viewer}'`);
  await login(viewer);
  assert.deepEqual(await activity(), []);
  check('banned requester receives no public or private aggregate', () => {});
  await login(author);
  const inserted = (await db.query(`insert into posts(id,user_id,venue_ref,created_at,caption) values
      ('50000000-0000-0000-0000-000000000001','${author}','${source}',now()+interval '10 years','Future clock'),
      ('50000000-0000-0000-0000-000000000002','${author}','${source}',now()-interval '10 years','Backdated clock')
    returning id,created_at,created_at=now() as server_clock`)).rows;
  check('client future and backdated publication clocks normalize to server time', () => {
    assert.equal(inserted.length, 2);
    assert.ok(inserted.every(row => row.server_clock));
  });
  await rejected("update posts set created_at=now()+interval '1 hour' where id='50000000-0000-0000-0000-000000000001'", '22023');
  await rejected("update posts set created_at=now()-interval '1 hour' where id='50000000-0000-0000-0000-000000000001'", '22023');
  await rejected("update posts set created_at=null where id='50000000-0000-0000-0000-000000000001'", '22023');
  check('future, backdated, and null timestamp updates cannot reset original publication', () => {});
  await db.exec("update posts set caption='Legitimate caption edit' where id='50000000-0000-0000-0000-000000000001'");
  const edited = (await db.query("select caption,created_at from posts where id='50000000-0000-0000-0000-000000000001'")).rows[0];
  check('legitimate content edit preserves publication timestamp', () => {
    assert.equal(edited.caption, 'Legitimate caption edit');
    assert.deepEqual(edited.created_at, inserted[0].created_at);
  });
  await maintenance();
  await db.exec("update posts set caption='Legitimate moderation edit' where id='50000000-0000-0000-0000-000000000001'");
  const moderated = (await db.query("select created_at from posts where id='50000000-0000-0000-0000-000000000001'")).rows[0];
  check('authorized maintenance moderation preserves original publication time', () => assert.deepEqual(moderated.created_at, inserted[0].created_at));
  await login(author);
  await rejected(`insert into posts(id,user_id,venue_ref,created_at) values('50000000-0000-0000-0000-000000000001','${author}','${source}',now()+interval '1 year')`, '23505');
  const recovered = (await db.query("select id,user_id,created_at from posts where id='50000000-0000-0000-0000-000000000001'")).rows;
  check('duplicate publication retry recovers exactly the original row without extending lifetime', () => {
    assert.equal(recovered.length, 1);
    assert.equal(recovered[0].user_id, author);
    assert.deepEqual(recovered[0].created_at, inserted[0].created_at);
  });
  const priorLocation = await activity();
  await db.exec(`update posts set venue_ref='${source}' where id='40000000-0000-0000-0000-000000000007'`);
  const relocated = await activity();
  check('changing a recent post location moves one contribution without resetting its clock', () => {
    assert.equal(total(relocated), total(priorLocation));
    assert.equal(Number(relocated.find(r => r.venue_ref === source).post_count), Number(priorLocation.find(r => r.venue_ref === source).post_count) + 1);
  });
  await db.exec(`update posts set venue_ref='${source}' where id='40000000-0000-0000-0000-000000000002'`);
  check('adding or changing location on an expired post does not reactivate it', () => {});
  assert.deepEqual(await activity(), relocated);
  await db.exec("delete from posts where id='50000000-0000-0000-0000-000000000002'");
  const afterDelete = await activity();
  check('deleted post immediately stops contributing', () => assert.equal(total(afterDelete), total(relocated) - 1));
  await db.exec("update posts set venue_ref=null,venue_id=null where id='50000000-0000-0000-0000-000000000001'");
  const afterUntag = await activity();
  check('removing location immediately stops contribution without deleting content', () => assert.equal(total(afterUntag), total(afterDelete) - 1));
  const permanentlyStored = (await db.query("select caption,venue_ref,created_at=now()-interval '168 hours' as unchanged_time from posts where id='40000000-0000-0000-0000-000000000002'")).rows[0];
  check('expired post and its location remain stored indefinitely', () => {
    assert.equal(permanentlyStored.caption, 'Exactly expired');
    assert.equal(permanentlyStored.venue_ref, source);
    assert.equal(permanentlyStored.unchanged_time, true);
  });
  await db.exec("delete from posts where id='40000000-0000-0000-0000-000000000001'");
  const withoutFirstExpiry = await activity();
  const storyExpiry = (await db.query(`select min(expires_at) as expiry from stories where venue_id='${venue}' and venue_ref is null`)).rows[0].expiry;
  check('next expiry falls back from nearest post to counted story expiry after deletion', () => assert.deepEqual(withoutFirstExpiry.find(r => r.venue_ref === venue).next_expiry, storyExpiry));
  await maintenance();
  await db.exec(`alter table posts disable trigger protect_post_publication_clock;
    insert into posts(user_id,venue_ref,created_at) select '${author}','${venue}',now()-interval '30 days' from generate_series(1,5000);
    alter table posts enable trigger protect_post_publication_clock;
    insert into stories(user_id,venue_ref,created_at,expires_at) select '${author}','${venue}',now()-interval '30 days',now()-interval '29 days' from generate_series(1,5000);
    analyze posts;analyze stories;`);
  const body = (await db.query("select prosrc from pg_proc where oid='public.venue_map_activity()'::regprocedure")).rows[0].prosrc;
  await login(null);
  const plan = await db.query(`explain (format json) ${body}`);
  check('actual invoker query bounds both sources through partial activity indexes', () => {
    assert.match(JSON.stringify(plan.rows), /posts_weekly_venue_activity/);
    assert.match(JSON.stringify(plan.rows), /stories_daily_venue_activity/);
  });
  await db.exec('commit;begin read only');
  const readOnly = await activity();
  await db.exec('commit');
  check('aggregate is usable in a read-only transaction with no historical-content expiry writes', () => assert.ok(total(readOnly) > 0));
  await maintenance();
  console.log('METADATA: ' + JSON.stringify((await db.query(`select
    (select md5(prosrc) from pg_proc where oid='public.venue_map_activity()'::regprocedure) as api_body_md5,
    (select md5(prosrc) from pg_proc where oid='public.protect_post_publication_clock()'::regprocedure) as clock_body_md5,
    (select md5(prosrc) from pg_proc where oid='public.venue_story_activity_today()'::regprocedure) as unchanged_legacy_api_body_md5`)).rows[0]));
  // A failed privacy preflight must roll back the API, trigger, and index.
  const broken = new PGlite();
  try {
    await broken.exec(await read('tools/deployment/tests/social_discovery_fixture.sql'));
    await broken.exec('alter table stories add column created_at timestamptz not null default now()');
    await broken.exec(await read('supabase/migrations/202610160001_social_discovery.sql'));
    await broken.exec('drop policy social_posts_read on posts');
    await assert.rejects(broken.exec(migration), /requires existing restrictive posts RLS/);
    await broken.exec('rollback');
    const rolledBack = (await broken.query("select to_regprocedure('public.venue_map_activity()') as api,to_regprocedure('public.protect_post_publication_clock()') as guard,to_regclass('public.posts_weekly_venue_activity') as index")).rows[0];
    check('missing restrictive RLS atomically rolls back API, clock guard, and index', () => assert.deepEqual(rolledBack, {api: null, guard: null, index: null}));
  } finally {await broken.close();}
  console.log(`PASS: ${passed} venue map activity fixture groups`);
} finally {await db.close();}
