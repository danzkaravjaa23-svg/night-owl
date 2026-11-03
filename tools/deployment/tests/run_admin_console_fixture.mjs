// Synthetic in-memory PostgreSQL only. Never connects to an application DB.
import assert from 'node:assert/strict';
import {readFile} from 'node:fs/promises';
import {fileURLToPath,pathToFileURL} from 'node:url';
import path from 'node:path';

if (!process.argv[2] || !path.isAbsolute(process.argv[2])) throw new Error('Pass an absolute PGlite module path');
const {PGlite}=await import(pathToFileURL(process.argv[2]).href);
const root=path.resolve(path.dirname(fileURLToPath(import.meta.url)),'../../..');
const read=f=>readFile(path.join(root,f),'utf8');
const db=new PGlite();
const member='10000000-0000-0000-0000-000000000001';
const author='10000000-0000-0000-0000-000000000002';
const admin='10000000-0000-0000-0000-000000000003';
const other='10000000-0000-0000-0000-000000000004';
const banned='10000000-0000-0000-0000-000000000005';
const venue='20000000-0000-0000-0000-000000000001';
const post='30000000-0000-0000-0000-000000000001';
const post2='30000000-0000-0000-0000-000000000002';
const comment='40000000-0000-0000-0000-000000000001';
const reply='40000000-0000-0000-0000-000000000002';
const event='50000000-0000-0000-0000-000000000001';
const report='60000000-0000-0000-0000-000000000001';
const report2='60000000-0000-0000-0000-000000000002';
const missing='90000000-0000-0000-0000-000000000001';
let passed=0;
const query=async(sql,args=[])=> (await db.query(sql,args)).rows;
const scalar=async(sql,args=[])=>Object.values((await query(sql,args))[0])[0];
const login=async(id,role=id?'authenticated':'anon')=>db.exec(`reset role; select set_config('request.jwt.claim.sub','${id??''}',false); set role ${role};`);
const system=()=>db.exec("reset role;select set_config('request.jwt.claim.sub','',false)");
const denied=async(sql,code='42501')=>assert.rejects(db.exec(sql),e=>e.code===code);
const action=(name,id,reason='Fixture moderation reason',reportId=null)=>scalar(
  'select public.admin_console_action($1,$2::uuid,$3,$4::uuid)',[name,id,reason,reportId]);
const rejectedAction=async(name,id,reason,reportId,code)=>assert.rejects(action(name,id,reason,reportId),e=>e.code===code);
const auditCount=()=>scalar("select (public.admin_console_audit(0,100)->'items')::jsonb").then(x=>x.length);
const check=async(name,fn)=>{await fn();passed++;console.log(`PASS ${name}`);};

try {
  await db.exec(await read('tools/deployment/tests/social_discovery_fixture.sql'));
  await db.exec(await read('supabase/migrations/202610160001_social_discovery.sql'));
  await db.exec(`
    create role service_role nologin bypassrls;
    grant usage on schema public,auth to service_role;
    grant execute on all functions in schema auth to service_role;
    create function public.is_admin() returns boolean language sql stable security definer set search_path=public,pg_temp as
      'select exists(select 1 from profiles where id=auth.uid() and is_admin)';
    alter table public.comments add column created_at timestamptz default now();
    alter table public.comments add column parent_id uuid references public.comments(id) on delete cascade;
    alter table public.comments drop constraint comments_post_id_fkey;
    alter table public.comments add foreign key(post_id) references public.posts(id) on delete cascade;
    alter table public.events add column title text,add column description text,add column starts_at timestamptz default now()+interval '1 day',
      add column ends_at timestamptz,add column price integer default 0,add column attendee_count integer default 0,add column venue_id uuid references venues;
    create table public.reports(id uuid primary key default gen_random_uuid(),reporter_id uuid not null references profiles,
      target_type text not null,target_id uuid not null,reason text not null,details text,status text default 'pending',created_at timestamptz default now());
    alter table public.reports enable row level security;
    grant select,insert,update,delete on public.reports to authenticated;
    create policy own_report_insert on public.reports for insert with check(reporter_id=auth.uid());
    create policy old_report_select on public.reports for select using(reporter_id=auth.uid() or public.is_admin());
    create policy old_report_update on public.reports for update using(public.is_admin());
    create policy admin_profile on public.profiles for update using(public.is_admin());
    create policy own_or_admin_post_delete on public.posts for delete using(user_id=auth.uid() or public.is_admin());
    create policy own_comment_delete on public.comments for delete using(user_id=auth.uid());
    create policy venue_add on public.venues for insert with check(owner_id=auth.uid() or public.is_admin());
    create policy venue_delete on public.venues for delete using(owner_id=auth.uid() or public.is_admin());
    create policy event_add on public.events for insert with check(organizer_id=auth.uid());
    create policy event_edit on public.events for update using(public.is_admin());
    create policy event_delete on public.events for delete using(organizer_id=auth.uid() or public.is_admin());
    insert into public.profiles(id,username,is_admin,is_banned) values('${banned}','banned-admin',true,true);
    update public.profiles set username='literal_%_name' where id='${other}';
    insert into public.comments(id,user_id,post_id,body) values('${comment}','${member}','${post}','Comment for moderation');
    insert into public.events(id,organizer_id,title,venue_id) values('${event}','${author}','Fixture concert','${venue}');
    insert into public.reports(id,reporter_id,target_type,target_id,reason) values
      ('${report}','${member}','post','${post}','spam'),('${report2}','${member}','user','${other}','hate');
    grant select,insert,update,delete on all tables in schema public to service_role;
  `);
  await db.exec(await read('supabase_featured_events.sql'));
  const migration=await read('supabase/migrations/202611030003_admin_console.sql');
  await db.exec('alter table public.profiles disable trigger protect_profile_flags');
  await assert.rejects(db.exec(migration),/protect_profile_flags/);
  await db.exec('rollback;alter table public.profiles enable trigger protect_profile_flags');
  await assert.rejects(db.exec(migration),/account_deletion_boundaries/);
  await db.exec('rollback');
  const deletionBoundary=await read('supabase/migrations/202611030001_account_deletion_boundaries.sql');
  await db.exec(deletionBoundary);
  await db.exec(`create or replace function public.cleanup_post_media() returns trigger language plpgsql security definer as $$
    begin delete from storage.objects where name=old.media_url; return old; end $$;`);
  await assert.rejects(db.exec(migration),/account_deletion_boundaries/);
  await db.exec('rollback');
  assert.equal(await scalar("select to_regclass('public.admin_audit_log') is null"),true);
  await db.exec(deletionBoundary);
  await db.exec(await read('tools/deployment/tests/admin_console_preflight.sql'));
  await db.exec(migration);
  await db.exec(migration);
  await db.exec(await read('tools/deployment/tests/admin_console_postflight.sql'));
  await check('migration repeats and catalog privilege postflight passes',async()=>{});

  const readCalls=["admin_console_summary()","admin_console_users()","admin_console_reports()","admin_console_content('post')","admin_console_audit()"];
  for(const [id,label] of [[null,'anonymous'],[member,'member'],[banned,'banned administrator']]) {
    await check(`${label} cannot read console or moderate`,async()=>{
      await login(id);
      for(const call of readCalls) await denied(`select public.${call}`);
      await rejectedAction('ban_user',other,'Valid reason',null,'42501');
    });
  }
  await login(admin);
  await check('active administrator summary and exact public data shapes',async()=>{
    const result=await scalar('select public.admin_console_summary()');
    assert.equal(result.actor_id,admin);assert.equal(result.users,5);assert.equal(result.pending_reports,2);
    assert.deepEqual(Object.keys(result).sort(),['actor_id','banned_users','comments','events','pending_reports','posts','users','venues']);
    const users=await scalar('select public.admin_console_users()');
    assert.equal(users.items.length,5);
    assert.deepEqual(Object.keys(users.items[0]).sort(),['avatar_url','created_at','full_name','id','is_admin','is_banned','is_verified','username']);
    const reports=await scalar('select public.admin_console_reports()');
    const item=reports.items.find(x=>x.id===report);
    assert.equal(item.target_author_id,author);assert.equal(item.target_excerpt,'Synthetic private photo');
    const content=await scalar("select public.admin_console_content('comment')");
    assert.equal(content.items[0].body,'Comment for moderation');assert.equal(content.items[0].media_url,null);
    assert.deepEqual(Object.keys(content.items[0]).sort(),['author_id','body','created_at','id','media_url','username']);
  });
  await check('literal search and bounded deterministic pagination',async()=>{
    const literal=await scalar("select public.admin_console_users('%_')");
    assert.deepEqual(literal.items.map(x=>x.id),[other]);
    const a=await scalar("select public.admin_console_users('',0,2)");
    const b=await scalar("select public.admin_console_users('',2,2)");
    assert.equal(a.has_more,true);assert.equal(new Set([...a.items,...b.items].map(x=>x.id)).size,4);
    for(const sql of ["admin_console_users('',-1,30)","admin_console_users('',0,101)","admin_console_users(repeat('x',101))","admin_console_reports('unknown')","admin_console_content('message')","admin_console_audit(100001,30)","admin_console_audit(0,null)"]) await denied(`select public.${sql}`,'22023');
  });
  await check('private attached post media has a narrow active-admin exception',async()=>{
    await system();await db.exec(`update public.profiles set is_private=true where id='${author}'`);
    for(const id of [null,member,banned,admin]) {
      await login(id);
      assert.equal(await scalar(`select public.social_media_readable('posts','${author}/photo.jpg')`),id===admin);
      assert.equal(await scalar(`select public.social_media_readable('posts','${author}/unattached.jpg')`),false);
      assert.equal(await scalar(`select public.social_media_readable('posts','${member}/photo.jpg')`),id===member);
      assert.equal(await scalar(`select public.social_media_readable('stories','${author}/active.jpg')`),false);
    }
    await system();await db.exec(`update public.profiles set is_private=false where id='${author}'`);await login(admin);
  });
  await check('audit and private transaction authorization cannot be forged',async()=>{
    await denied('select * from admin_private.action_context');
    await denied("insert into admin_private.action_context values(txid_current(),auth.uid(),'ban_user',auth.uid(),null,'forged')");
    await denied('select * from public.admin_audit_log');
    await denied("insert into public.admin_audit_log(action,target_type,target_id,reason) values('fake','user','fake','fake')");
    await denied('update public.admin_audit_log set reason=\'fake\'');
    await denied('delete from public.admin_audit_log');
    await denied('truncate public.admin_audit_log');
    await db.exec("select set_config('app.admin_action','ban_user',false)");
    await denied(`update public.profiles set is_banned=true where id='${other}'`);
    await denied(`update public.profiles set is_admin=true where id='${other}'`);
    await denied(`update public.reports set status='resolved' where id='${report}'`);
  });
  await check('invalid reasons, missing targets, protected admins leave no audit',async()=>{
    const before=await auditCount();
    for(const reason of [null,'  ','\n\t\n','ab','x'.repeat(1001)]) await rejectedAction('ban_user',other,reason,null,'22023');
    await rejectedAction('delete_user',other,'Valid reason',null,'22023');
    await rejectedAction('ban_user',missing,'Valid reason',null,'P0002');
    await rejectedAction('delete_post',missing,'Valid reason',null,'P0002');
    await rejectedAction('ban_user',admin,'Valid reason',null,'42501');
    await rejectedAction('ban_user',banned,'Valid reason',null,'42501');
    assert.equal(await auditCount(),before);
  });
  await check('mismatched reports and no-op actions are atomic failures',async()=>{
    const before=await auditCount();
    await rejectedAction('ban_user',other,'Valid reason',report,'40001');
    await rejectedAction('delete_post',post2,'Valid reason',report,'40001');
    await rejectedAction('unban_user',other,'Valid reason',null,'40001');
    const row=(await scalar(`select public.admin_console_users('${other}')`)).items[0];
    assert.equal(row.is_banned,false);assert.equal(await auditCount(),before);
    assert.equal((await scalar('select public.admin_console_reports()')).items.length,2);
  });
  await check('ban and matching report close with one immutable audit receipt',async()=>{
    const before=await auditCount();
    const receipt=await action('ban_user',other,'  Reviewed report evidence  ',report2);
    assert.equal(receipt.report_id,report2);assert.equal(receipt.report_status,'resolved');assert.equal(receipt.target_type,'user');
    assert.equal((await scalar(`select public.admin_console_users('${other}')`)).items[0].is_banned,true);
    const audit=(await scalar('select public.admin_console_audit()')).items.find(x=>x.id===receipt.audit_id);
    assert.equal(audit.actor_id,admin);assert.equal(audit.reason,'Reviewed report evidence');assert.equal(await auditCount(),before+1);
    await rejectedAction('unban_user',other,'Valid reason',report2,'40001');
    assert.equal((await scalar(`select public.admin_console_users('${other}')`)).items[0].is_banned,true);
    await action('unban_user',other);
    await action('verify_user',other);await action('unverify_user',other);
  });
  await check('report reopen, dismiss and resolve reject stale states',async()=>{
    await action('reopen_report',report2);await action('dismiss_report',report2);
    await rejectedAction('dismiss_report',report2,'Valid reason',null,'40001');
    await action('reopen_report',report2);await action('resolve_report',report2);
    await rejectedAction('resolve_report',report2,'Valid reason',null,'40001');
    await rejectedAction('resolve_report',report,'Valid reason',report2,'22023');
  });
  await check('content deletion cascades atomically and a repeat cannot succeed',async()=>{
    const before=await auditCount();
    await denied(`delete from public.posts where id='${post}'`);
    const receipt=await action('delete_post',post,'Removed reported content',report);
    assert.equal(receipt.report_status,'resolved');assert.equal(await auditCount(),before+1);
    assert.equal((await scalar("select public.admin_console_content('comment')")).items.length,0);
    await rejectedAction('delete_post',post,'Valid reason',null,'P0002');
    assert.equal(await auditCount(),before+1);
  });
  await check('a failure after a write rolls the write, report and audit back',async()=>{
    await system();
    await db.exec(`insert into public.comments(id,user_id,post_id,body) values('${comment}','${member}','${post2}','Retained comment');
      insert into public.comments(id,user_id,post_id,parent_id,body) values('${reply}','${author}','${post2}','${comment}','Another author reply');
      insert into public.reports(id,reporter_id,target_type,target_id,reason) values('${missing}','${member}','comment','${comment}','other');
      create function public.fixture_fail_audit() returns trigger language plpgsql as $$ begin
        if new.reason='forced audit failure' then raise exception 'forced audit failure'; end if; return new; end $$;
      create trigger fixture_fail_audit before insert on public.admin_audit_log for each row execute function public.fixture_fail_audit();`);
    await db.exec(`create function public.fixture_skip_delete() returns trigger language plpgsql as $$ begin return null; end $$;
      create trigger fixture_skip_delete before delete on public.comments for each row execute function public.fixture_skip_delete()`);
    await login(admin);
    await rejectedAction('delete_comment',comment,'Skipped row must not succeed',missing,'40001');
    assert.equal((await scalar("select public.admin_console_content('comment')")).items.length,2);
    assert.equal((await scalar("select public.admin_console_reports('pending')")).items.find(x=>x.id===missing).status,'pending');
    await system();await db.exec('drop trigger fixture_skip_delete on public.comments;drop function public.fixture_skip_delete()');
    await login(admin);
    await assert.rejects(action('delete_comment',comment,'forced audit failure',missing),/forced audit failure/);
    assert.equal((await scalar("select public.admin_console_content('comment')")).items.length,2);
    assert.equal((await scalar("select public.admin_console_reports('pending')")).items.find(x=>x.id===missing).status,'pending');
    await system();assert.equal(await scalar('select count(*) from admin_private.action_context'),0);
    await db.exec('drop trigger fixture_fail_audit on public.admin_audit_log;drop function public.fixture_fail_audit()');
    await login(admin);await action('delete_comment',comment,'Confirmed removal',missing);
    assert.equal((await scalar("select public.admin_console_content('comment')")).items.length,0);
  });
  await check('ordinary profile editing remains possible and cannot escalate flags',async()=>{
    await login(member);
    await db.exec(`update public.profiles set full_name='Updated ordinary user',is_admin=true,is_banned=true,is_verified=true where id='${member}'`);
    const row=(await query(`select full_name,is_admin,is_banned,is_verified from public.profiles where id='${member}'`))[0];
    assert.deepEqual(row,{full_name:'Updated ordinary user',is_admin:false,is_banned:false,is_verified:false});
  });
  await check('report insertion validates actor, pending state, type, reason and detail length',async()=>{
    await login(member);
    const insert=(extra='')=>`insert into public.reports(reporter_id,target_type,target_id,reason${extra})`;
    await db.exec(`${insert()} values('${member}','user','${other}','hate')`);
    await denied(`${insert()} values('${member}','user','${other}','spam')`,'40001');
    await denied(`${insert()} values('${member}','post','${missing}','spam')`,'P0002');
    for(const sql of [
      `${insert(',status')} values('${member}','user','${other}','spam','resolved')`,
      `${insert()} values('${member}','message','${other}','spam')`,
      `${insert()} values('${member}','user','${other}','unknown')`,
      `${insert(',details')} values('${member}','user','${other}','other',repeat('x',2001))`,
    ]) await denied(sql,'22023');
    await denied(`${insert()} values('${author}','user','${other}','spam')`);
    await login(banned);await denied(`${insert()} values('${banned}','user','${other}','spam')`);
  });
  await check('report quota also counts previously handled reports',async()=>{
    await system();
    await db.exec(`insert into public.reports(reporter_id,target_type,target_id,reason,status)
      select '${author}','user','${other}','spam','resolved' from generate_series(1,20)`);
    await login(author);
    await denied(`insert into public.reports(reporter_id,target_type,target_id,reason) values('${author}','venue','${venue}','spam')`,'54000');
  });
  await check('ordinary comment deletion cascades another author reply',async()=>{
    await system();await db.exec(`insert into public.comments(id,user_id,post_id,body) values('${comment}','${member}','${post2}','Own comment');
      insert into public.comments(id,user_id,post_id,parent_id,body) values('${reply}','${author}','${post2}','${comment}','Reply by someone else')`);
    await login(member);await db.exec(`delete from public.comments where id='${comment}'`);
    await login(admin);assert.equal((await scalar("select public.admin_console_content('comment')")).items.length,0);
  });
  await check('venue owner changes and ordinary content deletion remain authorized',async()=>{
    await login(author);
    await db.exec(`update public.venues set name='Owner edited venue' where id='${venue}'`);
    await db.exec(`select public.review_venue('${venue}',jsonb_build_object('address','Owner address'))`);
    assert.equal(await scalar(`select address from public.venue_catalog where ref='${venue}'`),'Owner address');
    await db.exec(`delete from public.posts where id='${post2}'`);
    await login(admin);assert.equal((await scalar("select public.admin_console_content('post')")).items.length,0);
  });
  await check('place review requires active owner/admin and a confirmed catalog update',async()=>{
    for(const id of [null,member,banned]) {
      await login(id);
      await denied(`select public.review_venue('${venue}',jsonb_build_object('address','Unauthorized overwrite'))`);
    }
    await login(admin);
    const before=await auditCount();
    await denied(`select public.review_venue('${missing}',jsonb_build_object('address','Missing place'))`,'P0002');
    await denied(`select public.review_venue('${venue}',null)`,'22023');
    await denied(`select public.review_venue('${venue}',jsonb_build_object('cover_url','http://fixture.test/image.png'))`,'22023');
    assert.equal(await auditCount(),before);
    await system();
    await db.exec(`insert into public.pilot_venues(venue_ref) values('${venue}');
      create function public.fixture_skip_review() returns trigger language plpgsql as $$ begin return null; end $$;
      create trigger fixture_skip_review before update on public.venue_catalog for each row execute function public.fixture_skip_review()`);
    for(const id of [admin,author]) {
      await login(id);
      await denied(`select public.review_venue('${venue}',jsonb_build_object('address','Must not save'))`,'P0002');
    }
    await login(admin);
    assert.equal(await auditCount(),before);
    assert.equal(await scalar(`select address from public.venue_catalog where ref='${venue}'`),'Owner address');
    await system();
    assert.equal(await scalar(`select count(*) from public.pilot_venues where venue_ref='${venue}'`),1);
    await db.exec('drop trigger fixture_skip_review on public.venue_catalog;drop function public.fixture_skip_review()');
    await login(admin);
    await db.exec(`select public.review_venue('${venue}',jsonb_build_object('address','Confirmed reviewed address'))`);
    assert.equal(await scalar(`select address from public.venue_catalog where ref='${venue}'`),'Confirmed reviewed address');
    const latest=(await scalar('select public.admin_console_audit(0,100)')).items;
    assert(latest.some(x=>x.action==='update_venue_catalog' && x.target_id===venue));
    assert(latest.some(x=>x.action==='delete_pilot_venue' && x.target_id===venue));
    await system();assert.equal(await scalar(`select count(*) from public.pilot_venues where venue_ref='${venue}'`),0);
    await login(admin);
  });
  await check('legacy event, venue, featured and pilot edits append audit',async()=>{
    await login(admin);const before=await auditCount();
    await db.exec(`update public.venues set name='Admin edited venue' where id='${venue}'`);
    await db.exec(`update public.events set title='Admin edited event' where id='${event}'`);
    await db.exec(`select public.set_featured_event('${event}',true,4)`);
    await db.exec(`select public.set_featured_event('${event}',false,0)`);
    await db.exec(`select public.set_pilot_entry('creator','${author}',true)`);
    await db.exec(`select public.set_pilot_entry('creator','${author}',false)`);
    const items=(await scalar('select public.admin_console_audit(0,100)')).items;
    for(const expected of ['update_venue','update_event','insert_event_feature','delete_event_feature','insert_pilot_creator','delete_pilot_creator']) assert(items.some(x=>x.action===expected),expected);
    assert((await auditCount())>=before+6);
  });
  await check('banned administrator cannot use legacy owner/admin writes',async()=>{
    await login(banned);
    await denied(`insert into public.events(id,organizer_id,title) values('${missing}','${banned}','Blocked event')`);
    await db.exec(`update public.venues set name='Banned overwrite' where id='${venue}'`);
    await denied(`select public.set_featured_event('${event}',true,0)`);
    await denied(`select public.set_pilot_entry('creator','${author}',true)`);
    await login(admin);assert.equal(await scalar(`select name from public.venues where id='${venue}'`),'Admin edited venue');
  });
  await check('service maintenance remains available but audit cannot be edited',async()=>{
    await login(null,'service_role');
    await db.exec(`update public.profiles set is_verified=true where id='${other}'`);
    await system();assert.equal(await scalar(`select is_verified from public.profiles where id='${other}'`),true);
    await denied('delete from public.admin_audit_log');
    await denied('truncate public.admin_audit_log');
    await login(admin);
  });
  await check('demotion invalidates an existing administrator session immediately',async()=>{
    await system();await db.exec(`update public.profiles set is_admin=false where id='${admin}'`);
    await login(admin);await denied('select public.admin_console_summary()');
    await rejectedAction('ban_user',other,'Valid reason',null,'42501');
  });
  await system();await db.exec(await read('tools/deployment/tests/admin_console_postflight.sql'));
  console.log(JSON.stringify({scope:'synthetic in-memory PostgreSQL; no hosted data',passed,migrationRepeatable:true,
    anonymousMemberBannedAdminDenied:true,atomicModerationAndImmutableAudit:true,legacyOwnerPathsPreserved:true,
    limits:'Does not establish hosted migration compatibility, real concurrent transactions, or production grants.'},null,2));
} finally { await db.close(); }
