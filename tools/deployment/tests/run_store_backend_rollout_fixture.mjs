// Exact generated artifact on fictional data; no hosted connection.
import assert from 'node:assert/strict';
import {readFile} from 'node:fs/promises';
import {pathToFileURL} from 'node:url';
import {createHash} from 'node:crypto';
import {buildStoreBackendRelease,transactionBody,validateStorageOrigin} from '../store_backend_release.mjs';
import {seedStoreRolloutFixture} from './store_rollout_fixture.mjs';
const {PGlite}=await import(pathToFileURL(process.argv[2]).href);
const db=new PGlite();let passed=0;
const scalar=async sql=>Object.values((await db.query(sql)).rows[0])[0];
const check=async(name,run)=>{await run();passed++;console.log('PASS: '+name);};
try{
 await seedStoreRolloutFixture(db);
 const {sql,postflight,manifest}=await buildStoreBackendRelease({storageOrigin:'https://fixture.test'});
 const forwardMigration='supabase/migrations/202611040001_business_conflict_http.sql';
 const forwardBody=transactionBody(await readFile(new URL('../../../'+forwardMigration,import.meta.url),'utf8'),forwardMigration);
 const snapshot=async()=>{
   const result={};
   const tables=(await db.query("select c.oid::regclass::text name from pg_class c join pg_namespace n on n.oid=c.relnamespace where (n.nspname='public' and c.relkind='r') or (n.nspname='auth' and c.relname='users') or (n.nspname='storage' and c.relname='objects') order by 1")).rows;
   for(const {name} of tables)result[name]=await scalar(`select count(*)::int from ${name}`);
   result.admins=await scalar('select array_agg(id order by id) from profiles where is_admin');
   result.buckets=await scalar('select jsonb_object_agg(id,public) from storage.buckets');
   return result;
 };
 const before=await snapshot();
 await check('transaction parser rejects missing, duplicate and nonfinal commit',async()=>{
   for(const source of ['begin;\nselect 1;','begin;\nbegin;\ncommit;','begin;\ncommit;\nselect 2;'])assert.throws(()=>transactionBody(source,'fixture'));
   assert.equal(manifest.bundle_sha256,createHash('sha256').update(sql).digest('hex'));
   assert.deepEqual(manifest.migration_order,[
     'supabase/migrations/202611030008_account_erasure.sql',
     'supabase/migrations/202611030009_ugc_review.sql',forwardMigration]);
   assert.ok(manifest.sources.some(source=>source.file===forwardMigration));
   assert.ok(manifest.sources.some(source=>source.file==='tools/deployment/tests/business_conflict_postflight.sql'));
   for(const origin of [undefined,'http://real.example','http://[::1]:54321','https://[::1]','https://user:pass@example.com','https://fixture.test/path',"https://fixture.test/'",'https://fixture.test?x=1','https://fixture.test#fragment'])assert.throws(()=>validateStorageOrigin(origin));
   assert.equal(validateStorageOrigin('http://127.0.0.1:54321'),'http://127.0.0.1:54321');
 });
 await check('preflight refuses missing prior protection without changing rows',async()=>{
   await db.exec('alter table posts disable trigger protect_post_publication_clock');
   await assert.rejects(db.exec(sql),/007 post publication clock guard missing/);await db.exec('rollback');
   assert.equal(await scalar("select to_regnamespace('account_private') is null"),true);
   assert.deepEqual(await snapshot(),before);
   await db.exec('alter table posts enable trigger protect_post_publication_clock');
 });
 await check('final assertion failure rolls back all migrations and bucket flags',async()=>{
   const broken=sql.replace('do $verify_erasure$',()=>"drop trigger account_erasure_write_guard on storage.objects;\ndo $verify_erasure$");
   await assert.rejects(db.exec(broken),/Erasure postflight failed: storage_write_guard/);await db.exec('rollback');
   assert.equal(await scalar("select to_regnamespace('account_private') is null"),true);
   assert.equal(await scalar("select count(*)::int from pg_attribute where attrelid='public.posts'::regclass and attname='moderation_status' and not attisdropped"),0);
   assert.deepEqual(await snapshot(),before);
 });
 await check('missing business-conflict forward fix aborts the entire install before commit',async()=>{
   const broken=sql.replace(forwardBody,'-- Deliberately omit the reviewed forward fix.');
   assert.notEqual(broken,sql);
   const priorAction=await scalar("select prosrc from pg_proc where oid='public.admin_console_action(text,uuid,text,uuid)'::regprocedure");
   await assert.rejects(db.exec(broken),/Business-conflict postflight body mismatch/);await db.exec('rollback');
   assert.equal(await scalar("select to_regnamespace('account_private') is null"),true);
   assert.equal(await scalar("select prosrc from pg_proc where oid='public.admin_console_action(text,uuid,text,uuid)'::regprocedure"),priorAction);
   assert.deepEqual(await snapshot(),before);
 });
 await check('new unreviewed profile reference aborts before erasure DDL',async()=>{
   await db.exec('create table public.unreviewed_profile_copy(owner_id uuid references public.profiles(id))');
   await assert.rejects(db.exec(sql),/foreign-key inventory changed/);await db.exec('rollback');
   assert.equal(await scalar("select to_regnamespace('account_private') is null"),true);
   await db.exec('drop table public.unreviewed_profile_copy');assert.deepEqual(await snapshot(),before);
 });
 await check('exact bundle installs with all postconditions before commit and preserves counts/admins',async()=>{
   await db.exec(sql);await db.exec(postflight);
   const after=await snapshot();assert.deepEqual({...after,buckets:before.buckets},before);
   assert.deepEqual(after.buckets,{posts:false,stories:false,avatars:false,venues:false});
   assert.equal(await scalar('select count(*)::int from account_private.erasure_jobs'),0);
   assert.equal(await scalar("select count(*)::int from posts where moderation_status<>'approved'"),0);
 });
 await check('standalone postflight detects a reintroduced retryable business conflict',async()=>{
   const definition=await scalar("select pg_get_functiondef('public.admin_console_report_guard()'::regprocedure)");
   const regressed=definition.replace("'PT409'","'40001'");assert.notEqual(regressed,definition);
   await db.exec(regressed);
   await assert.rejects(db.exec(postflight),/Business-conflict postflight body mismatch/);await db.exec('rollback');
   await db.exec(definition);await db.exec(postflight);
 });
 await check('unknown outcome rerun is rejected rather than erasing new state',async()=>{
   const after=await snapshot();await assert.rejects(db.exec(sql),/already present or partially installed/);await db.exec('rollback');
   assert.deepEqual(await snapshot(),after);await db.exec(postflight);
 });
 await check('metadata export includes contracts but no application content',async()=>{
   const query=await readFile(new URL('./store_backend_metadata.sql',import.meta.url),'utf8');
   const results=await db.exec(query);const output=results.find(r=>r.rows?.[0]?.store_backend_metadata)?.rows[0].store_backend_metadata;
   assert.ok(output);assert.equal(output.app_buckets.length,4);assert.ok(output.functions.length>10);
   const serialized=JSON.stringify(output);for(const marker of ['erased-member','remaining-member','private own message','other group text stays'])assert.ok(!serialized.includes(marker));
 });
 await check('operations summary identifies failed/expired work without exposing identity',async()=>{
   for(const [index,state,age,lease] of [[1,'prepared',45,null],[2,'failed',45,null],[3,'running',45,-1],[4,'running',0,1],[5,'completed',31,null],[6,'completed',29,null]]){
     await db.query(`insert into account_private.erasure_jobs(user_id,state,receipt_hash,updated_at,lease_until,completed_at,storage_cleared_at,database_cleared_at)
       values($1,$2,$3,now()-($4||' days')::interval,case when $5::int is null then null else now()+($5||' minutes')::interval end,
       case when $2='completed' then now()-($4||' days')::interval end,case when $2='completed' then now()-($4||' days')::interval end,
       case when $2='completed' then now()-($4||' days')::interval end)`,
       ['81000000-0000-0000-0000-00000000000'+index,state,String(index).repeat(64),age,lease]);
   }
   const query=await readFile(new URL('./account_erasure_operations_status.sql',import.meta.url),'utf8');
   const output=(await db.exec(query)).find(r=>r.rows?.[0]?.erasure_operations_status).rows[0].erasure_operations_status;
   assert.equal(output.failed_count,1);assert.equal(output.running_without_valid_lease,1);assert.equal(output.running_with_valid_lease,1);
   assert.equal(output.completed_over_retention,1);assert.equal(output.attention_required,true);
   assert.ok(!JSON.stringify(output).includes('81000000-'));assert.ok(!JSON.stringify(output).includes('receipt'));
 });
 await check('pruning removes only completed journals older than30days; unfinished work persists',async()=>{
   await db.exec(await readFile(new URL('./account_erasure_prune.sql',import.meta.url),'utf8'));
   assert.equal(await scalar('select count(*)::int from account_private.erasure_jobs'),5);
   assert.equal(await scalar("select count(*)::int from account_private.erasure_jobs where state in ('prepared','running','failed')"),4);
   assert.equal(await scalar("select count(*)::int from account_private.erasure_jobs where state='completed'"),1);
   await db.exec('set role authenticated');
   await assert.rejects(db.query('select * from account_private.erasure_jobs'),e=>e.code==='42501');
   await assert.rejects(db.query("select public.account_erasure_control('prune')"),e=>e.code==='42501');
   await db.exec('reset role');
 });
 await check('retention scheduling refuses an uninstalled scheduler and status reads only its named job',async()=>{
   await assert.rejects(db.exec(await readFile(new URL('../account_erasure_schedule.sql',import.meta.url),'utf8')),/existing approved pg_cron installation/);await db.exec('rollback');
   // Schema-only stand-in validates the read query; it is not a running pg_cron.
   await db.exec(`create schema cron;create table cron.job(jobid bigint,jobname text,schedule text,active boolean,database text,username text,command text);
     create table cron.job_run_details(jobid bigint,runid bigint,status text,start_time timestamptz,end_time timestamptz);
     insert into cron.job values(1,'unrelated-private-job','* * * * *',true,current_database(),current_user,'Private unrelated command');
     insert into cron.job values(2,'nightowl-erasure-prune-30d','17 2 * * *',true,current_database(),current_user,$command$set lock_timeout='5s'; set statement_timeout='30s'; select public.account_erasure_control('prune');$command$);
     insert into cron.job_run_details values(2,1,'succeeded',now(),now());`);
   const query=await readFile(new URL('./account_erasure_schedule_status.sql',import.meta.url),'utf8');
   const output=(await db.exec(query)).find(r=>r.rows?.[0]?.erasure_retention_schedule).rows[0].erasure_retention_schedule;
   assert.equal(output.job_count,1);assert.equal(output.jobs[0].command_matches,true);assert.equal(output.jobs[0].last_run.status,'succeeded');
   assert.ok(!JSON.stringify(output).includes('Private unrelated command'));
 });
 console.log(JSON.stringify({passed,bundle_sha256:manifest.bundle_sha256,hosted:false}));
}catch(error){console.error('FAIL:',error.message,error.where??'',error.internalQuery??'');process.exitCode=1;}
finally{await db.close();}
