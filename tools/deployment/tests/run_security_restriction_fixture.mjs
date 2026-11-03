// Restrictions-only release trial on fictional legacy rows. No hosted access.
import assert from 'node:assert/strict';
import {readFile} from 'node:fs/promises';
import {fileURLToPath,pathToFileURL} from 'node:url';
import path from 'node:path';
import {buildSecurityRepair} from '../security_backend_release.mjs';
import {buildSecurityRestriction} from '../security_restriction_release.mjs';
import {createHash} from 'node:crypto';

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
  // Legacy auxiliary schema is installed BEFORE any pending migration.
  await db.exec(`
    create table auth.users(id uuid primary key,raw_user_meta_data jsonb default '{}'::jsonb);
    insert into auth.users(id) select id from profiles;
    alter table public.comments add column likes_count integer default 0;
  `);
  await db.exec(await read('supabase_story_likes.sql'));
  await db.exec(await read('supabase_comment_replies.sql'));
  await db.exec(await read('supabase_venue_reviews.sql'));
  const scale=await read('supabase_migration_scale.sql');
  // Exact legacy story-view/check-in tables and policy definitions, not rewrites.
  await db.exec(scale.slice(scale.indexOf('-- 0c. STORY VIEWS'),scale.indexOf('-- 0e. EVENTS')));
  // Notes schema/policies confirmed by the root's read-only hosted metadata.
  await db.exec(`create table public.notes(id uuid primary key default gen_random_uuid(),user_id uuid unique references profiles(id) on delete cascade,
    text text,venue_id uuid references venues(id),expires_at timestamptz default now()+interval '24 hours',created_at timestamptz default now());
    alter table public.notes enable row level security;
    create policy "Notes viewable" on notes for select using(true);
    create policy "Own notes insert" on notes for insert with check(user_id=auth.uid());
    create policy "Own notes update" on notes for update using(user_id=auth.uid());
    create policy "Own notes delete" on notes for delete using(user_id=auth.uid());
    grant all on public.notes to public,anon,authenticated;
    grant truncate on public.posts,public.messages,public.profiles to public,anon,authenticated;
  `);
  // Model broad hosted API defaults before hardening. Also seed explicit
  // column grants, which a table-level REVOKE alone does not remove.
  await db.exec(`
    grant all on public.story_views,public.story_likes,public.comment_likes,public.venue_reviews,public.checkins to public,anon,authenticated;
    grant insert(user_id,venue_id,expires_at),update(expires_at) on public.checkins to public,anon,authenticated;
    grant update(created_at) on public.venue_reviews to public,anon,authenticated;
    grant select on public.story_views,public.story_likes,public.comment_likes,public.venue_reviews to anon;
    create function auth.role() returns text language sql stable as $$select current_setting('role',true)$$;
    create table group_chats(id uuid primary key default gen_random_uuid(),name text not null,created_by uuid references profiles,created_at timestamptz default now());
    create table group_members(group_id uuid references group_chats on delete cascade,user_id uuid references profiles,joined_at timestamptz default now(),primary key(group_id,user_id));
    create table group_messages(id uuid primary key default gen_random_uuid(),group_id uuid references group_chats on delete cascade,sender_id uuid references profiles,body text not null,created_at timestamptz default now());
    alter table group_chats enable row level security;
    alter table group_members enable row level security;
    alter table group_messages enable row level security;
    alter table checkins add column created_at timestamptz default now();
  `);

  await db.exec(await read('supabase/migrations/202610160001_social_discovery.sql'));
  await db.exec(`
    create role service_role nologin bypassrls;
    grant usage on schema public,auth to service_role;
    grant execute on all functions in schema auth to service_role;
    create function public.is_admin() returns boolean language sql stable security definer set search_path=public,pg_temp as
      'select exists(select 1 from profiles where id=auth.uid() and is_admin)';
    alter table public.comments add column created_at timestamptz default now();
    alter table public.comments add column if not exists parent_id uuid references public.comments(id) on delete cascade;
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
  await db.exec(await read('supabase/migrations/202610200001_hosted_client_rpcs.sql'));
  await db.exec(await read('supabase/migrations/202610220001_storage_account_guards.sql'));
  await db.exec(await read('supabase/migrations/202611030002_discovery_analytics_consent.sql'));
  await db.exec(await read('supabase_featured_events.sql'));
  const {sql:restriction,manifest}=await buildSecurityRestriction();
  const {sql:generatedFull}=await buildSecurityRepair();
  const full=process.argv[3]?await readFile(process.argv[3],'utf8'):generatedFull;
  assert.equal(full,generatedFull,'The previously prepared full artifact must remain byte-for-byte unchanged');
  const fullHash=createHash('sha256').update(full).digest('hex');
  const story='30000000-0000-0000-0000-000000000003';
  const counts=async()=>{
    const tables=await query("select tablename from pg_tables where schemaname='public' order by tablename");
    const result={};for(const {tablename} of tables)result[tablename]=await scalar(`select count(*) from public."${tablename}"`);
    return result;
  };
  const unchangedReads=await scalar("select md5(pg_get_functiondef('public.social_media_readable(text,text)'::regprocedure)||pg_get_functiondef('public.protect_profile_flags()'::regprocedure))");
  await db.exec(`update public.profiles set is_private=true where id='${author}'`);
  const before=await counts();
  await check('pre-admin legacy baseline has no moderation RPC or private-admin media access',async()=>{
    assert.equal(await scalar("select to_regprocedure('public.admin_console_action(text,uuid,text,uuid)') is null"),true);
    await login(admin);assert.equal(await scalar(`select count(*) from posts where id='${post}'`),0);
    assert.equal(await scalar(`select public.social_media_readable('posts','${author}/photo.jpg')`),false);
    await system();
  });
  await check('final assertion failure rolls all earlier restriction changes back',async()=>{
    const broken=restriction.replace(/^create trigger interaction_note_write_guard .*$/m,'');
    await assert.rejects(db.exec(broken),/Note write guard missing/);await db.exec('rollback');
    assert.equal(await scalar("select to_regprocedure('public.admin_console_maintenance()') is null"),true);
    assert.equal(await scalar("select has_table_privilege('anon','public.notes','SELECT')"),true);
    assert.equal(await scalar("select has_table_privilege('authenticated','public.checkins','INSERT')"),true);
    assert.deepEqual(await counts(),before);
  });
  await check('exact restriction-only artifact applies idempotently without changing existing rows',async()=>{
    await db.exec(restriction);await db.exec(restriction);
    assert.deepEqual(await counts(),before);
    assert.equal(await scalar("select md5(pg_get_functiondef('public.social_media_readable(text,text)'::regprocedure)||pg_get_functiondef('public.protect_profile_flags()'::regprocedure))"),unchangedReads);
    assert.equal(await scalar("select count(*) from pg_proc p join pg_namespace n on n.oid=p.pronamespace where n.nspname='public' and p.proname like 'admin_console_%' and p.proname<>'admin_console_maintenance'"),0);
    assert.equal(await scalar("select to_regclass('public.admin_audit_log') is null and to_regnamespace('admin_private') is null"),true);
    await db.exec(await read('tools/deployment/tests/interaction_boundaries_postflight.sql'));
  });
  await check('private interactions and attached media remain hidden from unrelated users and admins',async()=>{
    await system();await db.exec(`insert into story_likes(story_id,user_id) values('${story}','${author}');
      insert into story_views(story_id,viewer_id) values('${story}','${author}');
      insert into comment_likes(comment_id,user_id) values('${comment}','${author}')`);
    for(const id of [null,other,admin]){
      await login(id);assert.equal(await scalar('select count(*) from story_likes'),0);
      assert.equal(await scalar('select count(*) from comment_likes'),0);
      if(id)assert.equal(await scalar('select count(*) from story_views'),0);else await denied('select * from story_views');
      assert.equal(await scalar(`select public.social_media_readable('posts','${author}/photo.jpg')`),false);
    }
  });
  await check('visible-parent view and like upserts remain idempotent',async()=>{
    await system();await db.exec(`update profiles set is_private=false where id='${author}'`);
    await login(member);
    for(let i=0;i<2;i++)await db.exec(`insert into story_views(story_id,viewer_id) values('${story}',auth.uid()) on conflict(story_id,viewer_id) do update set story_id=excluded.story_id,viewer_id=excluded.viewer_id;
      insert into story_likes(story_id,user_id) values('${story}',auth.uid()) on conflict(story_id,user_id) do update set story_id=excluded.story_id,user_id=excluded.user_id;
      insert into comment_likes(comment_id,user_id) values('${comment}',auth.uid()) on conflict(comment_id,user_id) do update set comment_id=excluded.comment_id,user_id=excluded.user_id`);
    assert.equal(await scalar('select count(*) from story_views where viewer_id=auth.uid()'),1);
    assert.equal(await scalar('select count(*) from story_likes where user_id=auth.uid()'),1);
    assert.equal(await scalar('select count(*) from comment_likes where user_id=auth.uid()'),1);
    await db.exec('delete from story_likes where user_id=auth.uid();delete from comment_likes where user_id=auth.uid()');
  });
  await check('Notes support own upsert, mutual-friend reads, server expiry and block privacy',async()=>{
    await login(author);await db.exec(`insert into notes(user_id,text,created_at,expires_at) values(auth.uid(),' Friend note ',now()+interval '100 years',now()+interval '100 years')
      on conflict(user_id) do update set user_id=excluded.user_id,text=excluded.text,created_at=excluded.created_at,expires_at=excluded.expires_at`);
    assert.equal(await scalar("select text='Friend note' and expires_at-created_at=interval '24 hours' and created_at<=now() from notes where user_id=auth.uid()"),true);
    await login(admin);assert.equal(await scalar('select count(*) from notes'),0);
    await login(member);assert.equal(await scalar('select count(*) from notes'),0);await db.exec(`select set_follow('${author}',true)`);
    await login(author);await db.exec(`select set_follow('${member}',true)`);
    await login(member);assert.equal(await scalar('select text from notes'),'Friend note');
    await login(author);await db.exec(`insert into blocks(blocker_id,blocked_id) values(auth.uid(),'${member}')`);
    await login(member);assert.equal(await scalar('select count(*) from notes'),0);
    await login(null);await denied('select * from notes');
    await login(author);await db.exec('delete from notes where user_id=auth.uid()');
  });
  await check('venue review upsert is retained while stale banned sessions cannot write',async()=>{
    await login(member);await db.exec(`insert into venue_reviews(venue_id,user_id,rating,comment) values('${venue}',auth.uid(),4,'Genuine review')
      on conflict(venue_id,user_id) do update set venue_id=excluded.venue_id,user_id=excluded.user_id,rating=excluded.rating,comment=excluded.comment`);
    assert.equal(await scalar('select rating from venue_reviews where user_id=auth.uid()'),4);
    await system();await db.exec(`update profiles set is_banned=true where id='${member}'`);
    await login(member);await denied(`insert into venue_reviews(venue_id,user_id,rating) values('${venue}',auth.uid(),5) on conflict(venue_id,user_id) do update set rating=excluded.rating`);
    await system();await db.exec(`update profiles set is_banned=false where id='${member}'`);
    await login(member);await db.exec('delete from venue_reviews where user_id=auth.uid()');
  });
  await check('check-in remains RPC-only with four-hour replacement and own checkout',async()=>{
    await login(member);await denied(`insert into checkins(user_id,venue_id,expires_at) values(auth.uid(),'${venue}',now()+interval '100 years')`);
    for(let i=0;i<2;i++){const receipt=await query(`select * from check_in_venue('${venue}')`);assert.equal(receipt.length,1);assert.equal(receipt[0].venue_id,venue);}
    assert.equal(await scalar("select count(*)=1 and bool_and(expires_at-created_at=interval '4 hours') from checkins where user_id=auth.uid()"),true);
    await db.exec('delete from checkins where user_id=auth.uid()');
    assert.equal(await scalar('select count(*) from checkins where user_id=auth.uid()'),0);
  });
  await check('profile identity and all public-table TRUNCATE are denied to browser roles',async()=>{
    await system();await db.exec(`insert into auth.users(id) values('${missing}')`);
    await login(admin);await denied(`update profiles set id='${missing}' where id=auth.uid()`);
    for(const id of [null,member,admin]){await login(id);await denied('truncate public.posts cascade');await denied('truncate public.messages cascade');}
    await system();
  });
  await check('the original unchanged full release safely applies after restrictions',async()=>{
    await db.exec(full);
    await db.exec(await read('tools/deployment/tests/admin_console_postflight.sql'));
    await db.exec(await read('tools/deployment/tests/interaction_boundaries_postflight.sql'));
    await login(admin);assert.equal((await scalar('select admin_console_summary()')).actor_id,admin);
    await system();await db.exec(`update profiles set is_private=true where id='${author}'`);
    await login(admin);assert.equal(await scalar(`select social_media_readable('posts','${author}/photo.jpg')`),true);
    await system();await assert.rejects(db.exec(restriction),/pre-admin baseline/);await db.exec('rollback');
  });
  console.log(JSON.stringify({scope:'Synthetic legacy hosted shape, without003 until final forward-compatibility test',passed,
    restrictionsOnly:true,existingRowsPreserved:true,privateAdminAccessWithheld:true,idempotent:true,
    originalFullReleaseCompatible:true,originalFullReleaseSha256:fullHash,restrictionSha256:manifest.bundle_sha256,
    limits:'No hosted user rows, live SQL or real concurrent sessions used.'},null,2));
}finally{await db.close();}
