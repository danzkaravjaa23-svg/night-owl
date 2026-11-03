// Synthetic in-memory PostgreSQL only. Never connects to a hosted database.
import assert from 'node:assert/strict';
import {readFile} from 'node:fs/promises';
import {pathToFileURL} from 'node:url';
const {PGlite}=await import(pathToFileURL(process.argv[2]).href);
const db=new PGlite();
const read=file=>readFile(new URL('../../../'+file,import.meta.url),'utf8');
const viewer='10000000-0000-0000-0000-000000000001';
const author='10000000-0000-0000-0000-000000000002';
const venue='20000000-0000-0000-0000-000000000001';
const source='osm:node:123';
let passed=0;
const check=(name,body)=>{body();passed++;console.log(`PASS: ${name}`);};
const login=async(id)=>db.exec(`reset role;select set_config('request.jwt.claim.sub','${id??''}',false);set role ${id?'authenticated':'anon'}`);
const maintenance=async()=>db.exec("reset role;select set_config('request.jwt.claim.sub','',false)");
const activity=async()=> (await db.query('select * from public.venue_story_activity_today()')).rows;
try {
  await db.exec(await read('tools/deployment/tests/social_discovery_fixture.sql'));
  await db.exec('alter table stories add column created_at timestamptz not null default now()');
  await db.exec(await read('supabase/migrations/202610160001_social_discovery.sql'));
  const policies=(await db.query("select polname,pg_get_expr(polqual,polrelid) as expression from pg_policy where polrelid='public.stories'::regclass order by polname")).rows;
  const migration=await read('supabase/migrations/202611030005_venue_story_activity.sql');
  const storyRowsBefore=(await db.query('select count(*)::integer as n from stories')).rows[0].n;
  await db.exec(migration);
  await db.exec(migration);
  assert.equal((await db.query('select count(*)::integer as n from stories')).rows[0].n,storyRowsBefore);
  assert.deepEqual((await db.query("select polname,pg_get_expr(polqual,polrelid) as expression from pg_policy where polrelid='public.stories'::regclass order by polname")).rows,policies);
  check('idempotent install has no story writes or policy changes',()=>assert.equal(storyRowsBefore,2));
  const fn=(await db.query("select prosecdef,provolatile,proconfig from pg_proc where oid='public.venue_story_activity_today()'::regprocedure")).rows[0];
  check('stable SECURITY INVOKER with pinned search path',()=>{
    assert.equal(fn.prosecdef,false);assert.equal(fn.provolatile,'s');
    assert.deepEqual(fn.proconfig,['search_path=public, pg_temp']);
  });
  const grants=(await db.query("select has_function_privilege('anon','public.venue_story_activity_today()','execute') as anon,has_function_privilege('authenticated','public.venue_story_activity_today()','execute') as authenticated,exists(select 1 from pg_proc p cross join lateral aclexplode(p.proacl) a where p.oid='public.venue_story_activity_today()'::regprocedure and a.grantee=0) as public_access")).rows[0];
  check('only explicit API roles receive execute',()=>assert.deepEqual(grants,{anon:true,authenticated:true,public_access:false}));
  await db.exec(`insert into venue_catalog(ref,name) values('${source}','Synthetic OSM place');
    insert into stories(user_id,venue_ref,created_at,expires_at) values
      ('${author}','${venue}',date_trunc('day',now() at time zone 'Asia/Ulaanbaatar') at time zone 'Asia/Ulaanbaatar',now()+interval '30 minutes'),
      ('${author}','${source}',now()-interval '1 millisecond',now()+interval '50 minutes');
    -- Legacy UUID-only rows still resolve, but dual references count once.
    insert into stories(user_id,venue_id,venue_ref,created_at,expires_at) values
      ('${author}','${venue}','${venue}',now()-interval '1 millisecond',now()+interval '40 minutes');
    alter table stories disable trigger normalize_venue_reference;
    insert into stories(user_id,venue_id,created_at,expires_at) values
      ('${author}','${venue}',now()-interval '1 millisecond',now()+interval '20 minutes');
    alter table stories enable trigger normalize_venue_reference;
    -- All of these are excluded: prior UB day, expired, future, no location.
    insert into stories(user_id,venue_ref,created_at,expires_at) values
      ('${author}','${venue}',(date_trunc('day',now() at time zone 'Asia/Ulaanbaatar') at time zone 'Asia/Ulaanbaatar')-interval '1 microsecond',now()+interval '1 day'),
      ('${author}','${venue}',now()-interval '1 millisecond',now()-interval '1 microsecond'),
      ('${author}','${venue}',now()+interval '1 hour',now()+interval '1 day'),
      ('${author}',null,now()-interval '1 millisecond',now()+interval '1 day');`);
  await login(null);
  let rows=await activity();
  check('anonymous public stories aggregate canonical UUID and source references',()=>{
    assert.equal(rows.length,2);
    assert.equal(Number(rows.find(r=>r.venue_ref===venue).story_count),3);
    assert.equal(Number(rows.find(r=>r.venue_ref===source).story_count),1);
  });
  const expectedDay=(await db.query("select (now() at time zone 'Asia/Ulaanbaatar')::date as day")).rows[0].day;
  check('UB midnight inclusive; yesterday, expired, future and unlocated excluded',()=>{
    assert.deepEqual(rows[0].activity_day,expectedDay);
    assert.equal(rows.reduce((n,r)=>n+Number(r.story_count),0),4);
  });
  const nextExpiry=(await db.query(`select min(expires_at) as expiry from stories where venue_id='${venue}' and venue_ref is null`)).rows[0].expiry;
  check('nearest counted expiry provided for timely map refresh',()=>assert.deepEqual(rows.find(r=>r.venue_ref===venue).next_expiry,nextExpiry));
  await db.exec("set time zone 'Pacific/Honolulu'");
  const otherTimezoneRows=await activity();
  check('activity is independent of connection timezone',()=>assert.deepEqual(otherTimezoneRows,rows));
  await maintenance();
  await db.exec(`update profiles set is_private=true where id='${author}'`);
  await login(null);
  rows=await activity();
  check('anonymous sees no private location count',()=>assert.deepEqual(rows,[]));
  await login(viewer);
  rows=await activity();
  check('nonfollower sees no private location count',()=>assert.deepEqual(rows,[]));
  await maintenance();
  await db.exec(`insert into follows values('${viewer}','${author}')`);
  await login(viewer);
  rows=await activity();
  check('approved follower sees private story count',()=>assert.equal(rows.length,2));
  await maintenance();
  await db.exec(`insert into blocks values('${viewer}','${author}')`);
  await login(viewer);
  rows=await activity();
  check('outgoing block hides story activity',()=>assert.deepEqual(rows,[]));
  await maintenance();
  await db.exec(`delete from blocks where blocker_id='${viewer}' and blocked_id='${author}';update profiles set is_private=false where id='${author}';insert into blocks values('${author}','${viewer}')`);
  await login(viewer);
  rows=await activity();
  check('incoming block hides story activity',()=>assert.deepEqual(rows,[]));
  await maintenance();
  await db.exec(`delete from blocks where blocker_id='${author}' and blocked_id='${viewer}';update profiles set is_banned=true where id='${author}'`);
  await login(viewer);
  rows=await activity();
  check('banned author hidden from viewer',()=>assert.deepEqual(rows,[]));
  await login(author);
  rows=await activity();
  check('banned author cannot count own stories despite self-read RLS',()=>assert.deepEqual(rows,[]));
  await maintenance();
  await db.exec(`update profiles set is_banned=false where id='${author}';update profiles set is_banned=true where id='${viewer}'`);
  await login(viewer);
  rows=await activity();
  check('banned requester receives no map activity',()=>assert.deepEqual(rows,[]));
  await login(null);
  await db.exec('begin read only');
  rows=await activity();
  await db.exec('commit');
  check('anonymous RPC runs in a read-only transaction',()=>assert.equal(rows.length,2));
  await maintenance();
  await db.exec(`insert into stories(user_id,venue_ref,created_at,expires_at)
    select '${author}','${venue}',now()-interval '7 days',now()-interval '6 days'
    from generate_series(1,5000);
    analyze stories;`);
  const queryBody=(await db.query("select prosrc from pg_proc where oid='public.venue_story_activity_today()'::regprocedure")).rows[0].prosrc;
  await login(null);
  const plan=await db.query(`explain (format json) ${queryBody}`);
  check('actual invoker query uses daily partial index with historical stories',()=>{
    assert.match(JSON.stringify(plan.rows),/stories_daily_venue_activity/);
  });
  console.log(`PASS: ${passed} venue story activity fixture groups`);
} finally {await db.close();}
