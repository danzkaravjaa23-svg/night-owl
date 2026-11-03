// In-memory PostgreSQL with synthetic accounts only; no Auth API or live data.
import assert from 'node:assert/strict';
import {readFile} from 'node:fs/promises';
import {pathToFileURL} from 'node:url';
const {PGlite}=await import(pathToFileURL(process.argv[2]).href);
const db=new PGlite();
const owner='10000000-0000-0000-0000-000000000001';
const other='10000000-0000-0000-0000-000000000002';
const admin='10000000-0000-0000-0000-000000000003';
const outsider='10000000-0000-0000-0000-000000000004';
const venue='20000000-0000-0000-0000-000000000001';
const read=file=>readFile(new URL('../../../'+file,import.meta.url),'utf8');
const login=async(id)=>db.exec(`reset role;select set_config('request.jwt.claim.sub','${id??''}',false);set role ${id?'authenticated':'anon'}`);
const count=async()=>{
  await db.exec('reset role');
  return (await db.query('select count(*)::integer as n from discovery_activity')).rows[0].n;
};
const consent=async(value,id=owner)=>{
  await db.exec('reset role');
  await db.query('update auth.users set raw_user_meta_data=$1::jsonb where id=$2',
    [JSON.stringify(value),id]);
};
const activity=async()=>{
  await db.exec(`reset role;delete from follows where follower_id='${owner}' and following_id='${other}';
    delete from venue_saves where user_id='${owner}' and venue_ref='${venue}'`);
  await login(owner);
  await db.exec(`select record_discovery_activity('session');
    select record_discovery_activity('directions','${venue}');
    select record_discovery_activity('profile_view','${other}');
    insert into posts(user_id,caption) values(auth.uid(),'Synthetic publication');
    insert into follows values(auth.uid(),'${other}');
    insert into venue_saves(user_id,venue_ref) values(auth.uid(),'${venue}');`);
};
try {
  await db.exec(await read('tools/deployment/tests/social_discovery_fixture.sql'));
  await db.exec(`create table auth.users(id uuid primary key,raw_user_meta_data jsonb);
    insert into auth.users select id,'{}'::jsonb from profiles`);
  await db.exec(await read('supabase/migrations/202610160001_social_discovery.sql'));
  const migration=await read('supabase/migrations/202611030002_discovery_analytics_consent.sql');
  await db.exec(migration);
  await db.exec(migration);
  await login(admin);
  await db.exec(`select set_pilot_entry('participant','${owner}',true);select set_pilot_entry('participant','${other}',true)`);

  for(const value of [{},{discovery_analytics_consent:false},{discovery_analytics_consent:'true'},
    {discovery_analytics_consent:1},{discovery_analytics_consent:null}]) {
    await consent(value);
    await activity();
    assert.equal(await count(),0,'Only explicit boolean consent may collect events');
  }
  await consent({discovery_analytics_consent:true});
  await activity();
  assert.equal(await count(),6,'Opt-in records RPC and follow/save/publish trigger events');
  await consent({discovery_analytics_consent:false});
  await activity();
  assert.equal(await count(),6,'Withdrawal takes effect without issuing a new JWT');

  await consent({discovery_analytics_consent:true},outsider);
  await login(outsider);
  await db.exec("select record_discovery_activity('session');insert into posts(user_id,caption) values(auth.uid(),'Non-cohort publication')");
  assert.equal(await count(),6,'Consent alone cannot enroll someone in the admin pilot');
  await login(owner);
  await assert.rejects(db.exec(`select set_pilot_entry('participant','${outsider}',true)`),e=>e.code==='42501');
  await assert.rejects(db.exec(`insert into discovery_activity(user_id,event) values('${other}','session')`),e=>e.code==='42501');

  // A privileged business operation cannot forge analytics on another actor's
  // behalf, even if that actor has opted in. The fixture helper is test-only.
  await consent({discovery_analytics_consent:true},other);
  await db.exec(`create function fixture_publish_for_other() returns void language sql security definer set search_path=public,pg_temp as $$
    insert into posts(user_id,caption) values('${other}','Privileged import');$$;
    grant execute on function fixture_publish_for_other() to authenticated;`);
  await login(owner);
  await db.exec('select fixture_publish_for_other()');
  assert.equal(await count(),6,'Acting for another owner must not synthesize their activity');

  await consent({discovery_analytics_consent:true});
  await login(owner);
  await assert.rejects(db.exec("select record_discovery_activity('follow','spoofed')"),e=>e.code==='22023');
  await assert.rejects(db.exec("select record_discovery_activity('directions','unknown-place')"),e=>e.code==='22023');
  await db.exec(`reset role;select set_config('request.jwt.claim.sub','',false);update profiles set is_banned=true where id='${owner}'`);
  await login(owner);
  await db.exec("select record_discovery_activity('session')");
  assert.equal(await count(),6,'Banned accounts stay excluded even with consent');
  await login(null);
  await assert.rejects(db.exec("select record_discovery_activity('session')"),e=>e.code==='42501');
  console.log('PASS: analytics consent missing/false/string/null denies; true collects RPC+follow/save/publish; withdrawal immediate; pilot/admin/actor/ban/event validation retained; no cross-owner metrics');
} finally {
  await db.close();
}
