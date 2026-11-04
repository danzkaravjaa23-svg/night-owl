// In-memory PostgreSQL only. Real prior migration bodies, fictional identities.
import assert from 'node:assert/strict';
import {readFile} from 'node:fs/promises';
import {pathToFileURL} from 'node:url';
import {seedStoreRolloutFixture} from './store_rollout_fixture.mjs';
const {PGlite}=await import(pathToFileURL(process.argv[2]).href);
const db=new PGlite();
const read=p=>readFile(new URL('../../../'+p,import.meta.url),'utf8');
const signatures=['public.admin_console_action(text,uuid,text,uuid)','public.admin_console_report_guard()',
  'public.admin_console_review(text,uuid,uuid,text,text)','public.check_in_venue(uuid)'];
const scalar=async(sql,args=[])=>Object.values((await db.query(sql,args)).rows[0])[0];
const system=async()=>db.exec("reset role;select set_config('request.jwt.claim.sub','',false)");
const login=async id=>db.exec(`reset role;select set_config('request.jwt.claim.sub','${id??''}',false);set role ${id?'authenticated':'anon'}`);
const denied=async(sql,args=[],code='PT409')=>assert.rejects(db.query(sql,args),e=>e.code===code);
const action=async(name,id,report=null)=>scalar('select admin_console_action($1,$2::uuid,$3,$4::uuid)',[name,id,'Synthetic conflict verification',report]);
const actionDenied=async(name,id,report=null)=>denied('select admin_console_action($1,$2::uuid,$3,$4::uuid)',[name,id,'Synthetic conflict verification',report]);
const review=async(id,version)=>scalar("select admin_console_review('post',$1::uuid,$2::uuid,'approved','Synthetic review')",[id,version]);
const reviewDenied=async(id,version)=>denied("select admin_console_review('post',$1::uuid,$2::uuid,'approved','Synthetic review')",[id,version]);
let passed=0;const check=async(name,fn)=>{await fn();passed++;console.log('PASS: '+name);};
try{
  const {owner:admin,other:member,venue}=await seedStoreRolloutFixture(db);
  await db.exec("select set_config('app.ugc_storage_origin','https://fixture.test',false)");
  // Fixture bootstrap only; the live forward artifact never replays these.
  for(const file of ['202611030008_account_erasure.sql','202611030009_ugc_review.sql'])
    await db.exec(await read('supabase/migrations/'+file));
  // This shared metadata fixture supplies read policies only. Model the
  // existing own-report permissive policy beneath the actual restrictive guards.
  await db.exec("create policy fixture_report_insert on reports for insert to authenticated with check(reporter_id=auth.uid());create policy fixture_post_update on posts for update to authenticated using(user_id=auth.uid()) with check(user_id=auth.uid());update reports set status='pending' where status is null");
  const migration=await read('supabase/migrations/202611040001_business_conflict_http.sql');
  const postflight=await read('tools/deployment/tests/business_conflict_postflight.sql');
  const snapshot=async()=>JSON.parse(await scalar("select jsonb_agg(to_jsonb(p) order by p.oid)::text from pg_proc p where p.oid=any($1::regprocedure[])",[signatures]));
  const bodies=async()=>JSON.parse(await scalar("select jsonb_object_agg(p.oid::regprocedure::text,pg_get_functiondef(p.oid))::text from pg_proc p where p.oid=any($1::regprocedure[])",[signatures]));
  const before=await snapshot(),original=await bodies();
  await check('read-only postflight rejects unfixed business SQLSTATEs',async()=>{
    await assert.rejects(db.exec(postflight),/Business-conflict postflight body mismatch/);await db.exec('rollback');
  });
  await check('missing final function rolls back earlier replacements',async()=>{
    await db.exec('alter function public.check_in_venue(uuid) rename to fixture_missing_check_in');
    await assert.rejects(db.exec(migration),/Business-conflict prerequisite missing/);await db.exec('rollback');
    await db.exec('alter function public.fixture_missing_check_in(uuid) rename to check_in_venue');
    assert.deepEqual(await snapshot(),before);
  });
  await check('unreviewed body shape is rejected atomically',async()=>{
    const source=original['check_in_venue(uuid)'];
    await db.exec(source.replace('Check-in was not confirmed','Unreviewed changed message'));
    const changed=await snapshot();
    await assert.rejects(db.exec(migration),/Business-conflict function body changed/);await db.exec('rollback');
    assert.deepEqual(await snapshot(),changed);await db.exec(source);
  });
  await check('unexpected security attributes are rejected atomically',async()=>{
    await db.exec('alter function public.check_in_venue(uuid) security invoker');
    const changed=await snapshot();
    await assert.rejects(db.exec(migration),/Business-conflict function attributes changed/);await db.exec('rollback');
    assert.deepEqual(await snapshot(),changed);await db.exec('alter function public.check_in_venue(uuid) security definer');
  });
  await db.exec(`create role fixture_observer nologin;grant execute on function public.admin_console_review(text,uuid,uuid,text,text) to fixture_observer;
    comment on function public.admin_console_review(text,uuid,uuid,text,text) is 'Preserve fixture function comment';
    create function public.fixture_serialization_failure() returns void language plpgsql as $$begin raise exception 'Database serialization failure' using errcode='40001';end$$;`);
  const metadataBefore=(await snapshot()).map(({prosrc,...attributes})=>attributes);
  await check('forward install changes exactly eleven errors and preserves every pg_proc attribute',async()=>{
    await db.exec(migration);await db.exec(postflight);
    const after=await snapshot();assert.deepEqual(after.map(({prosrc,...attributes})=>attributes),metadataBefore);
    assert.equal(after.reduce((sum,p)=>sum+(p.prosrc.match(/errcode\s*=\s*'PT409'/g)??[]).length,0),11);
    for(const item of after)assert.ok(!/errcode\s*=\s*'40001'/.test(item.prosrc));
    assert.equal(await scalar("select obj_description('public.admin_console_review(text,uuid,uuid,text,text)'::regprocedure,'pg_proc')"),'Preserve fixture function comment');
    await denied('select fixture_serialization_failure()',[],'40001');
  });
  await check('second forward install is an exact no-op',async()=>{
    const fixed=await snapshot();await db.exec(migration);await db.exec(postflight);assert.deepEqual(await snapshot(),fixed);
  });
  const post=await scalar('insert into public.posts(user_id,caption) values($1,$2) returning id',[member,'Synthetic pending publication']);
  let version=await scalar('select moderation_version from posts where id=$1',[post]);
  await check('repeat approval returns PT409 and does not add another audit',async()=>{
    await login(admin);await review(post,version);
    const count=await scalar("select jsonb_array_length(admin_console_audit(0,100)->'items')");
    await reviewDenied(post,version);
    assert.equal(await scalar("select jsonb_array_length(admin_console_audit(0,100)->'items')"),count);
  });
  await check('stale review version returns PT409 after a real edit',async()=>{
    await login(member);await db.query("update posts set caption='Newer pending publication' where id=$1",[post]);
    const updatedVersion=await scalar('select moderation_version from posts where id=$1',[post]);
    assert.notEqual(updatedVersion,version);
    assert.equal(await scalar('select moderation_status from posts where id=$1',[post]),'pending');
    await login(admin);await reviewDenied(post,version);
    version=updatedVersion;
  });
  await check('duplicate participant-selected report returns PT409',async()=>{
    await login(member);
    const args=['message','34000000-0000-0000-0000-000000000001','spam',null];
    assert.ok(await scalar('select report_ugc($1,$2::uuid,$3,$4)',args));
    await denied('select report_ugc($1,$2::uuid,$3,$4)',args);
  });
  const firstReport='35000000-0000-0000-0000-000000000001',secondReport='35000000-0000-0000-0000-000000000002';
  await check('report/user state and target mismatches return PT409',async()=>{
    await login(admin);
    await actionDenied('unban_user',member);
    await actionDenied('ban_user',member,firstReport);
    await actionDenied('delete_post',post,secondReport);
    await action('resolve_report',firstReport);await actionDenied('resolve_report',firstReport);
  });
  const suppress=async(table,event,run)=>{
    await system();
    await db.exec(`create or replace function public.fixture_suppress_mutation() returns trigger language plpgsql as $$begin return null;end$$;
      create trigger zz_fixture_suppress before ${event} on public.${table} for each row execute function public.fixture_suppress_mutation()`);
    try{await login(admin);await run();}finally{await system();await db.exec(`drop trigger zz_fixture_suppress on public.${table}`);}
  };
  await check('unconfirmed moderation target, report and audit mutations return PT409',async()=>{
    await suppress('profiles','update',()=>actionDenied('ban_user',member));
    await suppress('reports','update',()=>actionDenied('resolve_report',secondReport));
    await suppress('admin_audit_log','insert',()=>actionDenied('ban_user',member));
    assert.equal(await scalar('select is_banned from profiles where id=$1',[member]),false);
  });
  await check('unconfirmed review mutation returns PT409 without publishing',async()=>{
    await suppress('posts','update',()=>reviewDenied(post,version));
    assert.equal(await scalar('select moderation_status from posts where id=$1',[post]),'pending');
  });
  await check('suppressed check-in returns PT409 and retains prior check-in',async()=>{
    await system();await db.exec('alter table checkins alter column id set default gen_random_uuid()');
    await login(admin);await scalar('select check_in_venue($1::uuid)',[venue]);
    await system();const before=await scalar('select jsonb_agg(to_jsonb(c)) from checkins c where user_id=$1',[admin]);
    await suppress('checkins','insert',()=>denied('select check_in_venue($1::uuid)',[venue]));
    assert.deepEqual(await scalar('select jsonb_agg(to_jsonb(c)) from checkins c where user_id=$1',[admin]),before);
  });
  await check('permission failures remain 42501',async()=>{
    await login(null);await denied("select admin_console_review('post',$1::uuid,$2::uuid,'approved','Forbidden')",[post,version],'42501');
  });
  console.log(JSON.stringify({passed,scope:'synthetic in-memory PostgreSQL',hosted:false}));
}catch(error){console.error('FAIL:',error.stack??error.message,error.where??'');process.exitCode=1;}
finally{await db.close();}
