// Synthetic in-memory PostgreSQL. FK/column names mirror the 2026-11-03
// read-only hosted metadata inventory; there is no user data or live connection.
import assert from 'node:assert/strict';
import {readFile} from 'node:fs/promises';
import {pathToFileURL} from 'node:url';
const {PGlite}=await import(pathToFileURL(process.argv[2]).href);
const db=new PGlite();
const schema=JSON.parse(await readFile(new URL('./account_erasure_schema_fixture.json',import.meta.url),'utf8'));
const migration=await readFile(new URL('../../../supabase/migrations/202611030008_account_erasure.sql',import.meta.url),'utf8');
const owner='10000000-0000-0000-0000-000000000001',other='10000000-0000-0000-0000-000000000002';
const venue='20000000-0000-0000-0000-000000000001',post='30000000-0000-0000-0000-000000000001';
const lease='50000000-0000-0000-0000-000000000001',lease2='50000000-0000-0000-0000-000000000002';
const receipt='a'.repeat(64),nonce='b'.repeat(64);
let passed=0;
const check=(name,run)=>{run();passed++;console.log('PASS: '+name);};
const q=name=>'"'+name.replaceAll('"','""')+'"';
const role=async(name,id=null)=>db.exec(`reset role;select set_config('request.jwt.claim.sub','${id??''}',false);set role ${name}`);
const control=async(action,extra={})=>(await db.query('select public.account_erasure_control($1,$2,$3,$4,$5,$6,$7) as job',[action,extra.user??owner,extra.receipt??receipt,extra.nonce??null,extra.audience??null,extra.subject??null,extra.lease??lease])).rows[0].job;
async function reject(sql,code){await assert.rejects(db.exec(sql),e=>e.code===code);}
try {
  await db.exec(`create role anon nologin;create role authenticated nologin;create role service_role nologin bypassrls;
    create schema auth;create table auth.users(id uuid primary key);
    create function auth.uid() returns uuid language sql stable as $$select nullif(current_setting('request.jwt.claim.sub',true),'')::uuid$$;
    grant usage on schema auth to anon,authenticated,service_role;grant execute on function auth.uid() to anon,authenticated,service_role;`);
  for(const table of [...new Set(schema.columns.map(c=>c.table))]){
    const cols=schema.columns.filter(c=>c.table===table).map(c=>{
      const type=({'_text':'text[]','_uuid':'uuid[]'})[c.type]??c.type;
      const primary=c.column==='id'||(table==='venue_catalog'&&c.column==='ref');
      const def=type==='bool'?' default false':type.endsWith('[]')?" default '{}'":'';
      return q(c.column)+' '+type+(primary?' primary key':'')+def;
    });
    await db.exec(`create table public.${q(table)}(${cols.join(',')})`);
  }
  for(const fk of schema.foreign_keys)await db.exec(`alter table public.${q(fk.table)} add constraint ${q(fk.name)} ${fk.definition}`);
  await db.exec(`create schema storage;create table storage.objects(id uuid primary key default gen_random_uuid(),bucket_id text,name text,owner_id text);
    create function public.social_active() returns boolean language sql stable security definer set search_path=public,pg_temp as $$select exists(select 1 from profiles where id=auth.uid() and not coalesce(is_banned,false))$$;
    grant usage on schema storage to anon,authenticated,service_role;
    grant select,insert,update,delete on all tables in schema public,storage to authenticated,service_role;
    grant select on all tables in schema public,storage to anon;
    alter table profiles enable row level security;create policy fixture_profile_read on profiles for select using(true);
    create policy fixture_profile_update on profiles for update using(id=auth.uid()) with check(id=auth.uid());
    create policy fixture_profile_insert on profiles for insert with check(id=auth.uid());
    alter table posts enable row level security;create policy fixture_post_read on posts for select using(true);
    create policy fixture_post_insert on posts for insert with check(user_id=auth.uid());
    alter table storage.objects enable row level security;
    create policy fixture_object_read on storage.objects for select using(true);
    create policy fixture_object_write on storage.objects for insert with check(true);
    insert into auth.users values('${owner}'),('${other}');
    insert into profiles(id,username) values('${owner}','erased-member'),('${other}','remaining-member');
    insert into venues(id,name,owner_id,cover_url) values('${venue}','Shared community place','${owner}','https://fixture.test/posts/${owner}/venue.jpg');
    insert into venue_catalog(ref,venue_id,name,cover_url) values('${venue}','${venue}','Shared community place','https://fixture.test/posts/${owner}/venue.jpg');
    insert into posts(id,user_id,venue_id,venue_ref,caption) values('${post}','${owner}','${venue}','${venue}','own post'),('30000000-0000-0000-0000-000000000002','${other}','${venue}','${venue}','other post stays');
    insert into comments(id,user_id,post_id,body) values('31000000-0000-0000-0000-000000000001','${owner}','30000000-0000-0000-0000-000000000002','own comment'),('31000000-0000-0000-0000-000000000002','${other}','30000000-0000-0000-0000-000000000002','other comment stays');
    insert into stories(id,user_id,mentions) values('32000000-0000-0000-0000-000000000001','${other}',array['${owner}','${other}']::uuid[]);
    insert into events(id,organizer_id,venue_id,title) values('33000000-0000-0000-0000-000000000001','${owner}','${venue}','own authored event'),('33000000-0000-0000-0000-000000000002','${other}','${venue}','other event stays');
    insert into messages(id,sender_id,receiver_id,body) values('34000000-0000-0000-0000-000000000001','${owner}','${other}','private own message');
    insert into reports(id,reporter_id,target_type,target_id,details) values('35000000-0000-0000-0000-000000000001','${other}','post','${post}','subject copy'),('35000000-0000-0000-0000-000000000002','${other}','user','${owner}','subject copy');
    insert into group_chats(id,name,created_by) values('36000000-0000-0000-0000-000000000001','Shared group','${owner}'),('36000000-0000-0000-0000-000000000002','Empty owner group','${owner}');
    insert into group_members(group_id,user_id) values('36000000-0000-0000-0000-000000000001','${owner}'),('36000000-0000-0000-0000-000000000001','${other}'),('36000000-0000-0000-0000-000000000002','${owner}');
    insert into group_messages(id,group_id,sender_id,body) values('37000000-0000-0000-0000-000000000001','36000000-0000-0000-0000-000000000001','${owner}','own group text'),('37000000-0000-0000-0000-000000000002','36000000-0000-0000-0000-000000000001','${other}','other group text stays');
    insert into venue_reviews(id,venue_id,user_id,rating,comment) values('38000000-0000-0000-0000-000000000001','${venue}','${other}',5,'other review stays');
    insert into admin_audit_log(id,actor_id,actor_username,action,target_type,target_id,reason) values('39000000-0000-0000-0000-000000000001','${other}','moderator','delete_post','post','${post}','security audit retained');`);
  const before=(await db.query('select count(*)::int as n from posts')).rows[0].n;
  const preflightSql=await readFile(new URL('./account_erasure_preflight.sql',import.meta.url),'utf8');
  const preflight=JSON.parse((await db.query(preflightSql)).rows[0].account_erasure_preflight);
  check('read-only hosted preflight matches every audited FK without inspecting member data',()=>{assert.equal(preflight.expected_fk_count,69);assert.equal(preflight.matching_fk_count,69);assert.deepEqual(preflight.schema_drift,[]);});
  await db.exec(migration);await db.exec(migration);
  check('idempotent install writes no existing application rows',()=>assert.equal(before,2));
  assert.equal((await db.query('select count(*)::int as n from posts')).rows[0].n,before);
  const postflightSql=await readFile(new URL('./account_erasure_postflight.sql',import.meta.url),'utf8');
  const postflight=JSON.parse((await db.query(postflightSql)).rows[0].account_erasure_postflight);
  check('read-only postflight verifies exact function bodies, private ACL and all write guards',()=>{
    for(const [key,value]of Object.entries(postflight))if(typeof value==='boolean')assert.equal(value,true,key);
    assert.deepEqual(postflight.unguarded_public_tables,[]);
  });
  await db.exec("insert into auth.users values('10000000-0000-0000-0000-000000000003')");
  await role('authenticated','10000000-0000-0000-0000-000000000003');
  await db.exec("insert into profiles(id,username) values('10000000-0000-0000-0000-000000000003','legitimate-bootstrap')");
  check('fresh existing Auth user can bootstrap its own missing profile',()=>{});
  await role('authenticated',owner);
  await reject('select * from account_private.erasure_jobs','42501');
  await reject(`select public.account_erasure_control('lookup','${owner}')`,'42501');
  await reject('select public.account_erasure_write_guard()','42501');
  check('journal schema, direct table and control/trigger functions are inaccessible to clients',()=>{});
  await db.exec(`insert into posts(id,user_id,caption) values('40000000-0000-0000-0000-000000000001','${owner}','before deletion allowed')`);
  await role('service_role');
  await db.exec(`insert into storage.objects(bucket_id,name,owner_id) values
    ('posts','${owner}/owned.jpg','${owner}'),('posts','legacy/owned.jpg','${owner}'),('posts','${other}/untouched.jpg','${other}')`);
  const inventory=await control('storage_inventory');
  check('Storage ownership inventory includes legacy owned paths and excludes other member files',()=>assert.deepEqual(inventory.objects.map(o=>o.name).sort(),[owner+'/owned.jpg','legacy/owned.jpg'].sort()));
  await db.exec(`insert into storage.objects(bucket_id,name,owner_id) values('posts','${owner}/conflict.jpg','${other}')`);
  await assert.rejects(control('storage_inventory'),/conflicting object ownership/);
  await db.exec(`delete from storage.objects where name='${owner}/conflict.jpg'`);
  check('conflicting prefix ownership fails closed instead of deleting another member file',()=>{});
  let job=await control('prepare',{nonce,audience:'com.fixture.app',subject:'fixture.apple.subject'});
  check('prepare persists hashes with short-lived owner-bound Apple challenge and no account freeze',()=>{
    assert.equal(job.user_id,owner);assert.equal(job.state,'prepared');assert.equal(job.nonce_hash,nonce);assert.equal(job.receipt_hash,undefined);assert.equal(job.lease_id,undefined);
    assert.ok(new Date(job.nonce_expires_at)-new Date(job.created_at)<=300001);
  });
  await role('authenticated',owner);
  assert.equal((await db.query('select public.social_active() as active')).rows[0].active,true);
  await db.exec(`insert into storage.objects(bucket_id,name) values('posts','${owner}/before.jpg')`);
  await role('service_role');await control('claim');
  await assert.rejects(control('claim',{lease:lease2}),e=>e.code==='55P03');
  check('atomic claim excludes concurrent erasure workers',()=>{});
  await role('authenticated',owner);
  assert.equal((await db.query('select public.social_active() as active')).rows[0].active,false);
  await reject(`insert into posts(id,user_id,caption) values(gen_random_uuid(),'${owner}','forbidden during erasure')`,'42501');
  await reject(`insert into storage.objects(bucket_id,name) values('posts','${owner}/late.jpg')`,'42501');
  await reject(`update profiles set username='changed' where id='${owner}'`,'42501');
  check('claimed/partial erasure freezes social and Storage DB writes despite a valid old JWT',()=>{});
  await role('authenticated',other);
  await db.exec(`insert into posts(id,user_id,caption) values('40000000-0000-0000-0000-000000000002','${other}','other user remains active')`);
  check('other users keep writing during one member erasure',()=>{});
  await role('service_role');
  await assert.rejects(control('cleanup'),e=>e.code==='22023');
  await control('apple_revoked');await control('failed');
  job=await control('prepare',{receipt:'c'.repeat(64),audience:'com.fixture.app',subject:'fixture.apple.subject'});
  check('deliberate retry keeps irreversible revocation checkpoint and failed-account freeze',()=>{assert.equal(job.state,'failed');assert.ok(job.apple_revoked_at);});
  job=await control('prepare',{receipt:'c'.repeat(64),nonce:'d'.repeat(64),audience:'com.fixture.app',subject:'fixture.apple.subject'});
  check('a new Apple reauthorization challenge invalidates an earlier revocation checkpoint',()=>assert.equal(job.apple_revoked_at,null));
  const resumed={receipt:'c'.repeat(64),lease:lease2};
  await control('claim',resumed);await control('renew',resumed);
  await assert.rejects(control('renew'),e=>e.code==='P0002');
  await assert.rejects(control('completed',resumed),e=>e.code==='22023');
  check('old receipts/leases cannot mutate replacement job; premature completion rejected',()=>{});
  await db.exec('reset role;update account_private.erasure_jobs set lease_until=now()-interval \'1 second\'');
  await role('service_role');
  const oldLease=resumed.lease;
  resumed.lease='50000000-0000-0000-0000-000000000003';
  await control('claim',resumed);
  await assert.rejects(control('renew',{...resumed,lease:oldLease}),e=>e.code==='55P03');
  check('expired worker lease can be reclaimed and the old worker loses write authority',()=>{});
  await control('apple_revoked',resumed);
  await db.exec(`delete from storage.objects where owner_id='${owner}' or starts_with(name,'${owner}/')`); // Synthetic Storage API equivalent.
  await control('storage_cleared',resumed);await control('cleanup',resumed);
  await control('cleanup',resumed); // Safe repeat after a lost RPC response.
  await role('service_role');
  const preserved=(await db.query(`select
    (select count(*)::int from venues where id='${venue}' and owner_id is null and cover_url is null) as venue,
    (select count(*)::int from posts where user_id='${other}') as others_posts,
    (select count(*)::int from events where organizer_id='${other}') as others_events,
    (select count(*)::int from venue_reviews where user_id='${other}') as others_reviews,
    (select count(*)::int from reports where target_id in('${owner}','${post}')) as subject_reports,
    (select '${owner}'::uuid=any(mentions) from stories where user_id='${other}') as mentioned,
    (select count(*)::int from admin_audit_log) as audit`)).rows[0];
  check('cleanup preserves shared venue, others posts/events/reviews and immutable audit; removes subject reports/mentions',()=>assert.deepEqual(preserved,{venue:1,others_posts:2,others_events:1,others_reviews:1,subject_reports:0,mentioned:false,audit:1}));
  await db.exec(`reset role;delete from auth.users where id='${owner}'`); // Synthetic trusted Auth API equivalent.
  await role('service_role');
  const cascaded=(await db.query(`select
    (select count(*)::int from profiles where id='${owner}') as profile,
    (select count(*)::int from posts where user_id='${owner}') as posts,
    (select count(*)::int from comments where user_id='${owner}') as comments,
    (select count(*)::int from messages where sender_id='${owner}' or receiver_id='${owner}') as messages,
    (select count(*)::int from group_messages where sender_id='${owner}') as own_group_messages,
    (select count(*)::int from group_messages where sender_id='${other}') as other_group_messages,
    (select count(*)::int from group_chats where created_by is null) as shared_groups`)).rows[0];
  check('actual audited FKs erase member content/DM while shared group and other messages remain',()=>assert.deepEqual(cascaded,{profile:0,posts:0,comments:0,messages:0,own_group_messages:0,other_group_messages:1,shared_groups:1}));
  job=await control('reconcile',{...resumed,user:null});
  check('receipt recovery confirms Auth deletion even if final completion response was lost',()=>{assert.equal(job.state,'completed');assert.equal(job.apple_subject,null);assert.equal(job.apple_audience,null);});
  assert.equal((await control('reconcile',{...resumed,user:null})).state,'completed');
  check('completed receipt reconciliation is idempotent and cannot start a deletion',()=>{});
  await role('authenticated',owner);
  await reject(`insert into storage.objects(bucket_id,name) values('posts','${owner}/after.jpg')`,'42501');
  check('deleted profile blocks outstanding JWT writes',()=>{});
  await role('service_role');
  await control('prune');
  await db.exec('reset role;update account_private.erasure_jobs set completed_at=now()-interval \'31 days\'');
  await role('service_role');await control('prune');
  await db.exec('reset role');
  check('service-only retention prune removes completed journals after 30 days',()=>{});
  assert.equal((await db.query('select count(*)::int n from account_private.erasure_jobs')).rows[0].n,0);
  const bodyBefore=(await db.query("select md5(prosrc) as hash from pg_proc where oid='public.account_erasure_control(text,uuid,text,text,text,text,uuid)'::regprocedure")).rows[0].hash;
  await db.exec('alter table profiles drop constraint profiles_id_fkey');
  await assert.rejects(db.exec(migration),/requires the audited Auth-to-profile cascade/);
  await db.exec('rollback');
  const bodyAfter=(await db.query("select md5(prosrc) as hash from pg_proc where oid='public.account_erasure_control(text,uuid,text,text,text,text,uuid)'::regprocedure")).rows[0].hash;
  check('missing Auth cascade aborts migration without replacing the installed control API',()=>assert.equal(bodyAfter,bodyBefore));
  console.log(`PASS: ${passed} account erasure SQL fixture groups across ${schema.foreign_keys.length} audited FKs`);
} finally {await db.close();}
