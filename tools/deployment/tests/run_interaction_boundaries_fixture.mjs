// Synthetic in-memory PostgreSQL only. Never connects to an application DB.
import assert from 'node:assert/strict';
import {readFile} from 'node:fs/promises';
import {fileURLToPath,pathToFileURL} from 'node:url';
import path from 'node:path';
import {buildSecurityRepair} from '../security_backend_release.mjs';

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
  const boundary=await read('supabase/migrations/202611030004_interaction_boundaries.sql');
  const story='30000000-0000-0000-0000-000000000003';
  const expiredStory='30000000-0000-0000-0000-000000000004';
  await check('metadata-only hosted queries execute before repair',async()=>{
    for(const file of ['reaudit_hosted_preflight.sql','reaudit_rollback_snapshot.sql']) {
      const result=await db.query(await read(`tools/deployment/tests/${file}`));
      assert.equal(result.rows.length,1);
    }
  });
  await check('legacy private interaction leak is present before repair',async()=>{
    await db.exec(`update public.profiles set is_private=true where id='${author}';
      insert into public.story_views(story_id,viewer_id) values('${story}','${author}'),('${story}','${member}');
      insert into public.story_likes(story_id,user_id) values('${story}','${author}');
      insert into public.comment_likes(comment_id,user_id) values('${comment}','${author}');`);
    await login(null);
    assert.equal(await scalar(`select count(*) from stories where id='${story}'`),0);
    assert.equal(await scalar('select count(*) from story_views'),2);
    assert.equal(await scalar('select count(*) from story_likes'),1);
    assert.equal(await scalar('select count(*) from comment_likes'),1);
    await system();
  });
  await check('004 is atomic, repeatable and removes broad and column grants',async()=>{
    await db.exec('alter table public.story_likes disable row level security');
    await assert.rejects(db.exec(boundary),/Missing RLS prerequisite/);
    await db.exec('rollback;alter table public.story_likes enable row level security');
    await db.exec(await read('tools/deployment/tests/interaction_boundaries_preflight.sql'));
    await db.exec(boundary);await db.exec(boundary);
    await db.exec(await read('tools/deployment/tests/interaction_boundaries_postflight.sql'));
  });
  await check('combined pending migration bundle runs in one transaction',async()=>{
    const {sql,manifest}=await buildSecurityRepair();
    assert.equal(manifest.order.length,5);assert.equal(manifest.assertions.length,4);
    assert.equal((sql.match(/^begin;$/gm)??[]).length,1);
    assert.equal((sql.match(/^commit;$/gm)??[]).length,1);
    // A final assertion failure must roll back both earlier DDL and guard
    // replacement. This exercises the generated artifact, not a second builder.
    const broken=sql.replace(/^create trigger interaction_note_write_guard .*$/m,'')
      .replace(/^begin;$/m,'begin;\ncreate table public.release_atomicity_witness(id integer);');
    await assert.rejects(db.exec(broken),/Note write guard missing/);
    await db.exec('rollback');
    assert.equal(await scalar("select to_regclass('public.release_atomicity_witness') is null"),true);
    assert.equal(await scalar("select count(*) from pg_trigger where tgrelid='public.notes'::regclass and tgname='interaction_note_write_guard'"),1);
    await db.exec(sql);
    await db.exec(await read('tools/deployment/tests/admin_console_postflight.sql'));
    await db.exec(await read('tools/deployment/tests/interaction_boundaries_postflight.sql'));
  });
  await check('anonymous and unrelated actors cannot read private interactions or forge likes/views',async()=>{
    for(const id of [null,other,admin,banned]) {
      await login(id);
      if(id===null)await denied('select * from story_views');
      else assert.equal(await scalar('select count(*) from story_views'),0);
      assert.equal(await scalar('select count(*) from story_likes'),0);
      assert.equal(await scalar('select count(*) from comment_likes'),0);
      await denied(`insert into story_views(story_id,viewer_id) values('${story}',auth.uid())`);
      await denied(`insert into story_likes(story_id,user_id) values('${story}',auth.uid())`);
      await denied(`insert into comment_likes(comment_id,user_id) values('${comment}',auth.uid())`);
    }
  });
  await check('approved follower gets visible likes and only their own viewing history',async()=>{
    await login(member);assert.equal(await scalar(`select set_follow('${author}',true)`),'requested');
    await login(author);await db.exec(`select respond_follow_request('${member}',true)`);
    await login(member);
    assert.equal(await scalar('select count(*) from story_likes'),1);
    assert.equal(await scalar('select count(*) from comment_likes'),1);
    assert.deepEqual((await query('select viewer_id from story_views')).map(x=>x.viewer_id),[member]);
    await login(author);assert.equal(await scalar('select count(*) from story_views'),2);
  });
  await check('repeated client view and like upserts are idempotent and counters remain correct',async()=>{
    await login(member);
    for(let i=0;i<2;i++)await db.exec(`
      insert into story_views(story_id,viewer_id) values('${story}',auth.uid()) on conflict(story_id,viewer_id) do update set story_id=excluded.story_id,viewer_id=excluded.viewer_id;
      insert into story_likes(story_id,user_id) values('${story}',auth.uid()) on conflict(story_id,user_id) do update set story_id=excluded.story_id,user_id=excluded.user_id;
      insert into comment_likes(comment_id,user_id) values('${comment}',auth.uid()) on conflict(comment_id,user_id) do update set comment_id=excluded.comment_id,user_id=excluded.user_id;
    `);
    assert.equal(await scalar('select count(*) from story_views where viewer_id=auth.uid()'),1);
    assert.equal(await scalar('select count(*) from story_likes where user_id=auth.uid()'),1);
    assert.equal(await scalar(`select likes_count from comments where id='${comment}'`),2);
    await db.exec(`delete from comment_likes where comment_id='${comment}' and user_id=auth.uid()`);
    assert.equal(await scalar(`select likes_count from comments where id='${comment}'`),1);
    await denied(`update story_views set viewed_at=now() where viewer_id=auth.uid()`);
    await denied(`update story_likes set user_id='${other}' where user_id=auth.uid()`);
  });
  await check('public likes remain readable while viewing histories remain private',async()=>{
    await system();await db.exec(`update profiles set is_private=false where id='${author}'`);
    await login(null);assert.equal(await scalar('select count(*) from story_likes'),2);
    assert.equal(await scalar('select count(*) from comment_likes'),1);
    await denied('select * from story_views');
    await login(other);assert.equal(await scalar('select count(*) from story_views'),0);
    await system();await db.exec(`update profiles set is_private=true where id='${author}'`);
  });
  await check('blocks and expired stories remove interaction visibility and deny new writes',async()=>{
    await login(author);await db.exec(`insert into blocks(blocker_id,blocked_id) values(auth.uid(),'${member}')`);
    await login(member);assert.equal(await scalar('select count(*) from story_views'),0);
    assert.equal(await scalar('select count(*) from story_likes'),0);
    await denied(`insert into story_likes(story_id,user_id) values('${story}',auth.uid()) on conflict(story_id,user_id) do update set user_id=excluded.user_id`);
    await login(author);await denied(`insert into story_likes(story_id,user_id) values('${expiredStory}',auth.uid())`);
    await system();await db.exec(`delete from blocks where blocker_id='${author}' and blocked_id='${member}'`);
  });
  await check('active venue-review upsert and deletion preserve genuine rating trigger',async()=>{
    await login(other);
    for(const rating of [2,5])await db.exec(`insert into venue_reviews(venue_id,user_id,rating,comment) values('${venue}',auth.uid(),${rating},'Fixture review')
      on conflict(venue_id,user_id) do update set venue_id=excluded.venue_id,user_id=excluded.user_id,rating=excluded.rating,comment=excluded.comment`);
    assert.equal(await scalar(`select count(*) from venue_reviews where user_id=auth.uid()`),1);
    assert.equal(Number(await scalar(`select rating from venues where id='${venue}'`)),5);
    assert.equal(await scalar(`select review_count from venues where id='${venue}'`),1);
    await denied(`update venue_reviews set user_id='${member}' where user_id=auth.uid()`);
    await db.exec('delete from venue_reviews where user_id=auth.uid()');
    assert.equal(await scalar(`select review_count from venues where id='${venue}'`),0);
  });
  await check('banned member cannot insert, update or delete reviews even with stale login',async()=>{
    await login(other);await db.exec(`insert into venue_reviews(venue_id,user_id,rating,comment) values('${venue}',auth.uid(),3,'Existing review')`);
    await system();await db.exec(`update profiles set is_banned=true where id='${other}'`);
    await login(other);
    await denied(`insert into venue_reviews(venue_id,user_id,rating,comment) values('${venue}',auth.uid(),1,'Banned overwrite') on conflict(venue_id,user_id) do update set rating=excluded.rating,comment=excluded.comment`);
    await db.exec(`update venue_reviews set comment='Banned overwrite' where user_id=auth.uid();delete from venue_reviews where user_id=auth.uid()`);
    await login(null);assert.equal(await scalar(`select comment from venue_reviews where user_id='${other}'`),'Existing review');
    await login(banned);await denied(`insert into venue_reviews(venue_id,user_id,rating,comment) values('${venue}',auth.uid(),1,'Banned admin')`);
    await system();await db.exec(`update profiles set is_banned=false where id='${other}'`);
  });
  await check('direct check-in INSERT/UPDATE cannot bypass the RPC for any client',async()=>{
    for(const id of [null,member,admin,banned]) {
      await login(id);
      await denied(`insert into checkins(user_id,venue_id,expires_at) values(auth.uid(),'${venue}',now()+interval '100 years')`);
      await denied(`update checkins set expires_at=now()+interval '100 years' where user_id=auth.uid()`);
    }
    await login(banned);await denied(`select check_in_venue('${venue}')`);
  });
  await check('check-in RPC is caller-bound with four-hour expiry, replacement and own checkout',async()=>{
    await login(member);
    for(let i=0;i<2;i++) {
      const row=(await query(`select * from check_in_venue('${venue}')`))[0];
      assert.equal(row.venue_id,venue);
      assert.equal(await scalar(`select '${row.expires_at.toISOString()}'::timestamptz between now()+interval '3 hours 59 minutes' and now()+interval '4 hours 1 minute'`),true);
    }
    assert.equal(await scalar('select count(*) from checkins where user_id=auth.uid()'),1);
    await denied(`select check_in_venue('${missing}')`,'22023');
    assert.equal(await scalar('select count(*) from checkins where user_id=auth.uid()'),1);
    await db.exec('delete from checkins where user_id=auth.uid()');
    assert.equal(await scalar('select count(*) from checkins where user_id=auth.uid()'),0);
  });
  await check('suppressed check-in insert rolls back previous checkout and returns no success',async()=>{
    await login(member);await db.exec(`select check_in_venue('${venue}')`);
    const previous=await query('select id,expires_at from checkins where user_id=auth.uid()');
    await system();await db.exec(`create function fixture_skip_checkin() returns trigger language plpgsql as $$begin return null;end$$;
      create trigger fixture_skip_checkin before insert on checkins for each row execute function fixture_skip_checkin()`);
    await login(member);await denied(`select check_in_venue('${venue}')`,'40001');
    assert.deepEqual(await query('select id,expires_at from checkins where user_id=auth.uid()'),previous);
    await system();await db.exec('drop trigger fixture_skip_checkin on checkins');
  });
  await check('profile identity cannot transfer admin authority, including original003 installations',async()=>{
    const fresh='10000000-0000-0000-0000-000000000006',orphan='10000000-0000-0000-0000-000000000007';
    await system();await db.exec(`insert into auth.users(id) select id from profiles on conflict do nothing;
      alter table profiles add foreign key(id) references auth.users(id) on delete cascade;
      insert into auth.users(id) values('${fresh}'),('${orphan}');
      insert into profiles(id,username,is_admin) values('${fresh}','fresh-admin',true)`);
    await login(fresh);const before=await auditCount();
    await denied(`update profiles set id='${orphan}' where id=auth.uid()`);
    // 004 must protect installations whose old flag trigger lacked this guard.
    await system();await db.exec('alter table profiles disable trigger protect_profile_flags');
    await login(fresh);await denied(`update profiles set id='${orphan}' where id=auth.uid()`);
    assert.equal(await auditCount(),before);
    await system();await db.exec('alter table profiles enable trigger protect_profile_flags');
    await login(orphan);await denied('select admin_console_summary()');
    await login(fresh);assert.equal((await scalar('select admin_console_summary()')).actor_id,fresh);
    await db.exec("update profiles set full_name='Normal own edit' where id=auth.uid()");
  });
  await check('restrictive policies survive later broad grants and permissive legacy policies',async()=>{
    await system();await db.exec(`grant all on story_views,story_likes,comment_likes,venue_reviews,checkins to anon,authenticated;
      create policy fixture_all_views on story_views for all using(true) with check(true);
      create policy fixture_all_likes on story_likes for all using(true) with check(true);
      create policy fixture_all_checks on checkins for all using(true) with check(true)`);
    await login(null);assert.equal(await scalar('select count(*) from story_views'),0);
    assert.equal(await scalar('select count(*) from story_likes'),0);
    await login(other);await denied(`insert into story_likes(story_id,user_id) values('${story}',auth.uid())`);
    await denied(`insert into checkins(user_id,venue_id,expires_at) values(auth.uid(),'${venue}',now()+interval '100 years')`);
    await system();await db.exec(boundary);
    await db.exec(await read('tools/deployment/tests/interaction_boundaries_postflight.sql'));
  });
  await check('service-role maintenance and content cascades remain available',async()=>{
    await login(null,'service_role');
    await db.exec(`insert into venue_reviews(venue_id,user_id,rating,comment) values('${venue}','${banned}',4,'Maintenance import')`);
    await system();await db.exec(`delete from public.stories where id='${story}'`);
    assert.equal(await scalar(`select count(*) from story_likes where story_id='${story}'`),0);
    assert.equal(await scalar(`select count(*) from story_views where story_id='${story}'`),0);
    await db.exec(await read('tools/deployment/tests/admin_console_postflight.sql'));
  });
  await check('notes are own or mutual-friend only, never global or one-way follows',async()=>{
    await system();await db.exec(`update profiles set is_private=false where id='${author}';
      delete from follows where follower_id in ('${member}','${author}') and following_id in ('${member}','${author}')`);
    await login(author);await db.exec(`insert into notes(user_id,text,venue_id,created_at,expires_at) values(auth.uid(),'  Friend note  ','${venue}',now()+interval '100 years',now()+interval '100 years')`);
    assert.equal(await scalar('select text from notes'),'Friend note');
    assert.equal(await scalar("select created_at<=now() and expires_at-created_at=interval '24 hours' from notes"),true);
    await login(null);await denied('select * from notes');
    for(const id of [member,other,admin]){await login(id);assert.equal(await scalar('select count(*) from notes'),0);}
    await login(member);await db.exec(`select set_follow('${author}',true)`);
    assert.equal(await scalar('select count(*) from notes'),0);
    await login(author);await db.exec(`select set_follow('${member}',true)`);
    await login(member);assert.equal(await scalar('select text from notes'),'Friend note');
    await system();await db.exec(`update profiles set is_private=true where id='${author}'`);
    await login(member);assert.equal(await scalar('select text from notes'),'Friend note');
  });
  await check('notes expire for friends while owners can replace an expired unique row',async()=>{
    await system();await db.exec(`update notes set created_at=now()-interval '25 hours',expires_at=now()+interval '100 years' where user_id='${author}'`);
    await login(member);assert.equal(await scalar('select count(*) from notes'),0);
    await login(author);const oldId=await scalar('select id from notes');
    await db.exec(`insert into notes(user_id,text,venue_id,created_at,expires_at) values(auth.uid(),'Reposted note',null,now()-interval '99 years',now()+interval '99 years')
      on conflict(user_id) do update set user_id=excluded.user_id,text=excluded.text,venue_id=excluded.venue_id,created_at=excluded.created_at,expires_at=excluded.expires_at`);
    assert.equal(await scalar('select id from notes'),oldId);
    assert.equal(await scalar("select expires_at-created_at=interval '24 hours' and created_at<=now() from notes"),true);
    await login(member);assert.equal(await scalar('select text from notes'),'Reposted note');
    await system();await db.exec(`update notes set created_at=now()+interval '1 hour' where user_id='${author}'`);
    await login(member);assert.equal(await scalar('select count(*) from notes'),0);
    await login(author);await db.exec("update notes set text='Current note' where user_id=auth.uid()");
  });
  await check('notes enforce blocks, bans, owner identity and bounded nonempty text',async()=>{
    await system();await db.exec(`update profiles set is_banned=true where id='${member}'`);
    await login(member);assert.equal(await scalar('select count(*) from notes'),0);
    await system();await db.exec(`update profiles set is_banned=false where id='${member}'`);
    await login(member);
    await denied(`insert into notes(user_id,text) values('${author}','Forged owner')`);
    for(const text of ['   ','x'.repeat(1001)])await assert.rejects(db.query('insert into notes(user_id,text) values(auth.uid(),$1)',[text]),e=>e.code==='22023');
    const composedEmoji='👨‍👩‍👧‍👦'.repeat(100);
    await db.query('insert into notes(user_id,text) values(auth.uid(),$1)',[composedEmoji]);
    assert.equal(await scalar('select text from notes where user_id=auth.uid()'),composedEmoji);
    await db.exec('delete from notes where user_id=auth.uid()');
    await login(author);await denied(`update notes set user_id='${other}' where user_id=auth.uid()`);
    await db.exec(`insert into blocks(blocker_id,blocked_id) values(auth.uid(),'${member}')`);
    await login(member);assert.equal(await scalar('select count(*) from notes'),0);
    await system();await db.exec(`update profiles set is_banned=true where id='${author}'`);
    await login(author);assert.equal(await scalar('select count(*) from notes'),0);
    await denied("insert into notes(user_id,text) values(auth.uid(),'Banned note') on conflict(user_id) do update set text=excluded.text");
    await login(banned);await denied("insert into notes(user_id,text) values(auth.uid(),'Banned admin note')");
    await system();await db.exec(`update profiles set is_banned=false where id='${author}'`);
    await login(author);await db.exec('delete from notes where user_id=auth.uid()');
    assert.equal(await scalar('select count(*) from notes'),0);
  });
  await check('every public table denies API TRUNCATE, including unrelated legacy tables',async()=>{
    await system();await db.exec(await read('tools/deployment/tests/interaction_boundaries_postflight.sql'));
    for(const id of [null,member,admin]) {
      await login(id);await denied('truncate public.posts cascade');await denied('truncate public.messages cascade');await denied('truncate public.notes cascade');
    }
    await system();
  });
  await check('admin moderation remains atomic and audited after all004 guards',async()=>{
    await login(admin);
    const before=await auditCount();
    const receipt=await action('ban_user',other,'Confirmed fixture report',report2);
    assert.equal(receipt.report_status,'resolved');assert.equal(receipt.report_id,report2);
    assert.equal((await scalar(`select admin_console_users('${other}')`)).items[0].is_banned,true);
    await action('unban_user',other);await action('verify_user',author);await action('unverify_user',author);
    await action('delete_comment',comment);await action('delete_post',post2);
    assert.equal(await auditCount(),before+6);
    await system();assert.equal(await scalar('select count(*) from admin_private.action_context'),0);
    assert.equal(await scalar(`select count(*) from comment_likes where comment_id='${comment}'`),0);
    await db.exec(await read('tools/deployment/tests/admin_console_postflight.sql'));
    await db.exec(await read('tools/deployment/tests/interaction_boundaries_postflight.sql'));
  });
  console.log(JSON.stringify({scope:'synthetic in-memory PostgreSQL; legacy tables precede all migrations',passed,
    privateInteractionsProtected:true,bannedReviewsDenied:true,checkinsRpcOnly:true,profileIdentityImmutable:true,
    sameKeyClientUpserts:true,friendsOnlyNotes:true,publicTableTruncateDenied:true,repeatable:true,limits:'No hosted user data or real concurrent transactions used; Notes schema supplied from root read-only metadata.'},null,2));
} finally {await db.close();}
