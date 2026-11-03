// Isolated synthetic PostgreSQL. No network, Auth accounts, or real messages.
import assert from 'node:assert/strict';
import {readFile} from 'node:fs/promises';
import {pathToFileURL} from 'node:url';
const {PGlite}=await import(pathToFileURL(process.argv[2]).href);
const db=new PGlite();
const read=p=>readFile(new URL('../../../'+p,import.meta.url),'utf8');
const a='10000000-0000-0000-0000-000000000002',b='10000000-0000-0000-0000-000000000001',admin='10000000-0000-0000-0000-000000000003',stranger='10000000-0000-0000-0000-000000000004';
const venue='20000000-0000-0000-0000-000000000001';
const q=async(s,args=[]) => (await db.query(s,args)).rows;
const scalar=async(s,args=[])=>Object.values((await q(s,args))[0])[0];
const login=async(id)=>db.exec(`reset role;select set_config('request.jwt.claim.sub','${id??''}',false);set role ${id?'authenticated':'anon'}`);
const system=async()=>db.exec("reset role;select set_config('request.jwt.claim.sub','',false)");
const denied=async(s,code='42501',args=[])=>assert.rejects(db.query(s,args),e=>e.code===code);
let passed=0;const check=async(name,fn)=>{await fn();passed++;console.log('PASS: '+name);};
const queue=async(kind='all',status='pending')=>scalar('select admin_console_review_queue($1,$2)',[kind,status]);
const review=async(kind,id,version,status='approved')=>scalar('select admin_console_review($1,$2::uuid,$3::uuid,$4,$5)',[kind,id,version,status,'Synthetic review decision']);
try{
 await db.exec(await read('tools/deployment/tests/social_discovery_fixture.sql'));
 await db.exec(`create role service_role nologin bypassrls;grant usage on schema public,auth to service_role;
 create function auth.role() returns text language sql stable as $$select current_setting('role',true)$$;
 grant execute on function auth.role() to anon,authenticated;
 alter table profiles add column cover_url text;
 alter table stories add column created_at timestamptz default now(),add column caption text,
  add column music_url text,add column music_title text,add column music_artist text,add column mentions uuid[] default '{}';
 alter table posts add column comments_count integer default 0;
 alter table comments add column created_at timestamptz default now(),add column parent_id uuid;
 alter table venues add column created_at timestamptz default now(),add column photos text[] default '{}',add column rating numeric default 0,add column review_count integer default 0;
 alter table events add column title text,add column description text,add column starts_at timestamptz default now()+interval '1 day',add column ends_at timestamptz,add column price integer default 0,add column attendee_count integer default 0,add column venue_id uuid,add column created_at timestamptz default now();
 create table reports(id uuid primary key default gen_random_uuid(),reporter_id uuid references profiles on delete cascade,target_type text not null,target_id uuid not null,reason text not null,details text,status text default 'pending',created_at timestamptz default now());
 alter table reports enable row level security;grant select,insert,update,delete on reports to authenticated;
 create policy report_read on reports for select using(reporter_id=auth.uid() or exists(select 1 from profiles where id=auth.uid() and is_admin));
 create policy report_insert on reports for insert with check(reporter_id=auth.uid());
 create table notes(id uuid primary key default gen_random_uuid(),user_id uuid references profiles on delete cascade,text text,venue_id uuid,created_at timestamptz default now(),expires_at timestamptz default now()+interval '24 hours');
 alter table notes enable row level security;grant select,insert,update,delete on notes to authenticated;grant select on notes to anon;
 create policy note_read on notes for select using(expires_at>now());create policy note_write on notes for insert with check(user_id=auth.uid());
 create table venue_reviews(id uuid primary key default gen_random_uuid(),user_id uuid references profiles on delete cascade,venue_id uuid references venues on delete cascade,rating integer,comment text,created_at timestamptz default now());
 alter table venue_reviews enable row level security;grant select,insert,update,delete on venue_reviews to authenticated;grant select on venue_reviews to anon;
 create policy review_read on venue_reviews for select using(true);create policy review_insert on venue_reviews for insert with check(user_id=auth.uid());
 create policy review_update on venue_reviews for update using(user_id=auth.uid());
 create table group_messages(id uuid primary key default gen_random_uuid(),group_id uuid,sender_id uuid references profiles,body text,created_at timestamptz default now());
 create table fixture_group_members(group_id uuid,user_id uuid);
 alter table group_messages enable row level security;grant select on group_messages,fixture_group_members to authenticated;
 create policy group_message_read on group_messages for select using(exists(select 1 from fixture_group_members where group_id=group_messages.group_id and user_id=auth.uid()));
 create policy post_update on posts for update using(user_id=auth.uid());create policy story_update on stories for update using(user_id=auth.uid());create policy comment_add on comments for insert with check(user_id=auth.uid());
 create policy comment_update on comments for update using(user_id=auth.uid());create policy event_add on events for insert with check(organizer_id=auth.uid());
 create policy venue_add on venues for insert with check(owner_id=auth.uid());
 `);
 await db.exec(await read('supabase/migrations/202610160001_social_discovery.sql'));
 await db.exec(await read('supabase_featured_events.sql'));
 await db.exec(await read('supabase/migrations/202611030001_account_deletion_boundaries.sql'));
 await db.exec(await read('supabase/migrations/202611030003_admin_console.sql'));
 await db.exec(await read('supabase/migrations/202611030005_venue_story_activity.sql'));
 await db.exec(await read('supabase/migrations/202611030007_venue_map_activity.sql'));
 const source=await read('supabase/migrations/202611030009_ugc_review.sql');
 await db.exec(source);await db.exec(source);
 await db.exec(await read('tools/deployment/tests/ugc_review_postflight.sql'));
 await check('repeat installation preserves grandfathered approved records',async()=>{
  assert.equal(await scalar("select count(*) from posts where moderation_status='approved'"),2);
  assert.equal(await scalar("select bool_and(not public) from storage.buckets where id in ('posts','stories','avatars','venues')"),true);
 });
 let post;
 await login(a);
 await check('direct write cannot self-approve; owner sees pending content',async()=>{
  post=(await q("insert into posts(user_id,caption,venue_ref,media_url,moderation_status) values(auth.uid(),'Pending safe photo',$1,$2,'approved') returning *",[venue,`https://fixture.test/storage/v1/object/public/posts/${a}/pending.jpg`]))[0];
  assert.equal(post.moderation_status,'pending');
  await denied("update posts set moderation_status='approved' where id=$1",'42501',[post.id]);
  assert.equal(await scalar('select count(*) from posts where id=$1',[post.id]),1);
 });
 await check('pending/rejected do not contribute to author or public map activity',async()=>{
  assert.equal((await q('select * from venue_map_activity()')).reduce((sum,r)=>sum+Number(r.post_count),0),0);
  await login(b);assert.equal(await scalar('select count(*) from posts where id=$1',[post.id]),0);
  assert.equal(await scalar("select social_media_readable('posts',$1)",[`${a}/pending.jpg`]),false);
  await login(null);assert.equal(await scalar('select count(*) from posts where id=$1',[post.id]),0);
 });
 await check('only active admins see review queue; private DM tables stay RLS-bound',async()=>{
  await login(b);await denied('select admin_console_review_queue()');
  await login(admin);const rows=await queue('post');assert.equal(rows.items[0].id,post.id);
  assert.equal(rows.items[0].content.caption,'Pending safe photo');
  assert.equal(await scalar("select social_media_readable('posts',$1)",[`${a}/pending.jpg`]),true);
  await denied('select * from admin_private.ugc_action_context');
 });
 await check('approval is version-bound, audited once and publishes safe content',async()=>{
  const before=await scalar("select jsonb_array_length(admin_console_audit(0,100)->'items')");
  const receipt=await review('post',post.id,post.moderation_version);assert.equal(receipt.status,'approved');assert.ok(receipt.audit_id);
  assert.equal(await scalar("select jsonb_array_length(admin_console_audit(0,100)->'items')"),before+1);
  await denied('select admin_console_review($1,$2::uuid,$3::uuid,$4,$5)','40001',['post',post.id,post.moderation_version,'approved','Repeat decision']);
  await login(b);assert.equal(await scalar('select count(*) from posts where id=$1',[post.id]),1);
  assert.equal(await scalar("select social_media_readable('posts',$1)",[`${a}/pending.jpg`]),true);
  assert.equal((await q('select * from venue_map_activity()')).reduce((sum,r)=>sum+Number(r.post_count),0),1);
 });
 await check('editing requeues content; stale review version cannot approve newer edits',async()=>{
  await login(a);const edit=(await q("update posts set caption='Edited draft' where id=$1 returning *",[post.id]))[0];
  assert.equal(edit.moderation_status,'pending');assert.notEqual(edit.moderation_version,post.moderation_version);
  await login(admin);await denied('select admin_console_review($1,$2::uuid,$3::uuid,$4,$5)','40001',['post',post.id,post.moderation_version,'approved','Stale decision']);
  await review('post',post.id,edit.moderation_version,'rejected');
  await login(b);assert.equal(await scalar('select count(*) from posts where id=$1',[post.id]),0);
  await login(a);assert.equal(await scalar('select moderation_status from posts where id=$1',[post.id]),'rejected');
 });
 await check('profile edits retain approved identity and stage candidate privately',async()=>{
  await login(a);await db.exec("update profiles set bio='Pending bio',avatar_url='https://fixture.test/new-avatar.jpg' where id=auth.uid()");
  assert.equal(await scalar('select moderation_status from profiles where id=auth.uid()'),'pending');
  await login(b);assert.notEqual(await scalar('select bio from profiles where id=$1',[a]),'Pending bio');
  await login(admin);const candidate=(await queue('profile')).items.find(r=>r.id===a);assert.equal(candidate.content.bio,'Pending bio');
  await review('profile',a,candidate.review_version);
  await login(b);assert.equal(await scalar('select bio from profiles where id=$1',[a]),'Pending bio');
 });
 await check('all public text/media entry points are pending by default',async()=>{
  await login(a);
  for(const sql of ["insert into comments(user_id,post_id,body) values(auth.uid(),'30000000-0000-0000-0000-000000000001','Review comment') returning moderation_status",
   "insert into stories(user_id,caption,media_url) values(auth.uid(),'Review story','https://fixture.test/s.jpg') returning moderation_status",
   "insert into events(organizer_id,title) values(auth.uid(),'Review event') returning moderation_status",
   `insert into venue_reviews(user_id,venue_id,rating,comment) values(auth.uid(),'${venue}',5,'Review text') returning moderation_status`,
   "insert into notes(user_id,text) values(auth.uid(),'Review note') returning moderation_status",
   "insert into place_collections(user_id,title,is_public) values(auth.uid(),'Review collection',true) returning moderation_status",
   "insert into venues(id,owner_id,name) values(gen_random_uuid(),auth.uid(),'Review venue') returning moderation_status"]){assert.equal(await scalar(sql),'pending');}
 assert.equal(await scalar('select comments_count from posts where id=$1',['30000000-0000-0000-0000-000000000001']),0);
 });
 await check('story audio credits and mentions are reviewed; every approved audio edit requeues',async()=>{
  await login(a);
  let story=(await q(`insert into stories(user_id,caption,media_url,music_url,music_title,music_artist,mentions)
   values(auth.uid(),'Audio review story',$1,$2,'Submitted title','Submitted artist',$3::uuid[]) returning *`,
   [`https://fixture.test/storage/v1/object/public/stories/${a}/audio-frame.jpg`,`https://fixture.test/storage/v1/object/public/stories/${a}/audio.mp3`,[b]]))[0];
  await login(admin);
  let submitted=(await queue('story')).items.find(r=>r.id===story.id);
  assert.equal(submitted.content.music_url,story.music_url);assert.equal(submitted.content.music_title,'Submitted title');
  assert.equal(submitted.content.music_artist,'Submitted artist');assert.deepEqual(submitted.content.mentions,[b]);
  assert.equal(await scalar("select social_media_readable('stories',$1)",[`${a}/audio.mp3`]),true);
  for(const edit of ["music_title='Changed title'","music_artist='Changed artist'",`music_url='https://fixture.test/storage/v1/object/public/stories/${a}/replacement.mp3'`,`mentions=array['${stranger}']::uuid[]`]){
   await review('story',story.id,submitted.review_version);
   await login(a);story=(await q(`update stories set ${edit} where id=$1 returning *`,[story.id]))[0];
   assert.equal(story.moderation_status,'pending');assert.notEqual(story.moderation_version,submitted.review_version);
   await login(admin);await denied('select admin_console_review($1,$2,$3,$4,$5)','40001',['story',story.id,submitted.review_version,'approved','Old audio review']);
   submitted=(await queue('story')).items.find(r=>r.id===story.id);assert.equal(submitted.review_version,story.moderation_version);
  }
  await login(a);await denied('update stories set music_url=$1 where id=$2','42501',[`https://fixture.test/storage/v1/object/public/stories/${stranger}/private.mp3`,story.id]);
 });
 let msg,gm;
 await system();
 msg=await scalar('insert into messages(sender_id,receiver_id,body) values($1,$2,$3) returning id',[a,b,'Only selected DM']);
 gm=await scalar("insert into group_messages(group_id,sender_id,body) values('90000000-0000-0000-0000-000000000001',$1,'Only selected group message') returning id",[a]);
 await db.exec(`insert into fixture_group_members values('90000000-0000-0000-0000-000000000001','${b}')`);
 await check('unrelated user cannot report guessed private DM or group message',async()=>{
  await login(stranger);
  for(const [type,id] of [['message',msg],['group_message',gm]]) await denied('select report_ugc($1,$2::uuid,$3,$4)','42501',[type,id,'harassment','Selected context only']);
 });
 let report;
 await check('participant reporting captures only exact selected context and rejects forgery',async()=>{
  await login(b);report=await scalar('select report_ugc($1,$2::uuid,$3,$4)',['message',msg,'harassment','Selected context only']);
  assert.ok(report);
  await scalar('select report_ugc($1,$2::uuid,$3,$4)',['group_message',gm,'spam',null]);
  await denied('select report_ugc($1,$2::uuid,$3,$4)','40001',['message',msg,'spam',null]);
  await login(admin);const reports=await scalar('select admin_console_reports()');
  assert.equal(reports.items.find(r=>r.id===report).target_excerpt,'Only selected DM');
  assert.equal(await scalar('select count(*) from messages where id=$1',[msg]),0);
  assert.equal(await scalar('select count(*) from group_messages where id=$1',[gm]),0);
 });
 await check('ban revocation denies pending review actions without granting new admins',async()=>{
  await system();await db.exec('update profiles set is_banned=true where id=$1'.replace('$1',`'${admin}'`));
  await login(admin);await denied('select admin_console_review_queue()');
  await system();await db.exec(`update profiles set is_banned=false where id='${admin}'`);
 });

 await check('rejecting an approved profile hides it, while rejecting a replacement preserves baseline',async()=>{
  await login(a);await db.exec("update profiles set bio='Replacement awaiting review' where id=auth.uid()");
  await login(admin);let item=(await queue('profile')).items.find(r=>r.id===a);
  await review('profile',a,item.review_version,'rejected');
  await login(b);assert.equal(await scalar('select bio from profiles where id=$1',[a]),'Pending bio');
  await login(a);await db.exec("update profiles set bio='Safe replacement' where id=auth.uid()");
  await login(admin);item=(await queue('profile')).items.find(r=>r.id===a);
  await review('profile',a,item.review_version);
  item=(await queue('profile','approved')).items.find(r=>r.id===a);
  await review('profile',a,item.review_version,'rejected');
  await login(b);assert.equal(await scalar('select count(*) from profiles where id=$1',[a]),0);
  await login(a);assert.equal(await scalar('select moderation_status from profiles where id=auth.uid()'),'rejected');
  await db.exec("update profiles set bio='Safe restored profile' where id=auth.uid()");
  await login(admin);item=(await queue('profile')).items.find(r=>r.id===a);await review('profile',a,item.review_version);
 });
 await check('nonowner pending comment counter maintenance cannot publish or requeue parent post',async()=>{
  await system();await db.exec(`create function fixture_comment_counter() returns trigger language plpgsql security definer as $$begin
   update posts set comments_count=comments_count+1 where id=new.post_id;return new;end$$;
   create trigger fixture_comment_count after insert on comments for each row execute function fixture_comment_counter();`);
  await login(b);const id=await scalar("insert into comments(user_id,post_id,body) values(auth.uid(),'30000000-0000-0000-0000-000000000001','Nonowner comment awaiting review') returning id");
  assert.equal(await scalar("select comments_count from posts where id='30000000-0000-0000-0000-000000000001'"),0);
  assert.equal(await scalar("select moderation_status from posts where id='30000000-0000-0000-0000-000000000001'"),'approved');
  await login(admin);const item=(await queue('comment')).items.find(r=>r.id===id);await review('comment',id,item.review_version);
  assert.equal(await scalar("select comments_count from posts where id='30000000-0000-0000-0000-000000000001'"),1);
 });
 await check('ratings count only approved reviews and private collections never enter review queue',async()=>{
  await login(admin);const item=(await queue('review')).items[0];
  assert.equal(await scalar('select review_count from venues where id=$1',[venue]),0);
  await review('review',item.id,item.review_version);
  assert.equal(await scalar('select review_count from venues where id=$1',[venue]),1);
  await login(b);const id=await scalar("insert into place_collections(user_id,title,is_public) values(auth.uid(),'Private collection name',false) returning id");
  await login(admin);assert.equal((await queue('collection','approved')).items.some(r=>r.id===id),false);
 });
 await check('forged report context is overwritten with exactly caller-visible selected content',async()=>{
  await login(b);const id=await scalar("insert into reports(reporter_id,target_type,target_id,reason,target_snapshot,target_author_id) values(auth.uid(),'post','30000000-0000-0000-0000-000000000001','spam','{\"body\":\"forged context\"}'::jsonb,$1) returning id",[stranger]);
  const snapshot=await scalar('select target_snapshot from reports where id=$1',[id]);
  assert.equal(snapshot.body,'Synthetic private photo');
  assert.equal(await scalar('select target_author_id from reports where id=$1',[id]),a);
 });
 await check('cross-owner media cannot use submitted content as a signing oracle',async()=>{
  await login(b);await denied("insert into posts(user_id,caption,media_url) values(auth.uid(),'Forged object',$1)",'42501',[`https://fixture.test/storage/v1/object/public/posts/${a}/unattached.jpg`]);
  await denied("update profiles set avatar_url=$1 where id=auth.uid()",'42501',[`https://fixture.test/storage/v1/object/public/avatars/${a}/private.jpg`]);
  await denied("insert into venues(id,owner_id,name,cover_url) values(gen_random_uuid(),auth.uid(),'Forged venue',$1)",'42501',[`https://fixture.test/storage/v1/object/public/venues/${a}/private.jpg`]);
 });
 await check('reports support exact visible story, event, review, note and collection UUIDs',async()=>{
  await login(admin);
  const selected=[];
  for(const kind of ['story','event','note','collection']){
   const item=(await queue(kind)).items[0];await review(kind,item.id,item.review_version);selected.push([kind,item.id]);
  }
  const item=(await queue('review','approved')).items[0];selected.push(['review',item.id]);
  await login(a);for(const [kind,id] of selected)assert.ok(await scalar('select report_ugc($1,$2::uuid,$3,$4)',[kind,id,'other','Synthetic selected report']));
 });
 await check('private selected story media is report-scoped, never a blanket private-story grant',async()=>{
  await system();const id=await scalar("insert into stories(user_id,media_url,moderation_status) values($1,$2,'approved') returning id",[a,`https://fixture.test/storage/v1/object/public/stories/${a}/reported.jpg`]);
  await login(b);const reportId=await scalar('select report_ugc($1,$2::uuid,$3,$4)',['story',id,'other','Selected media report']);
  await system();await db.exec(`update profiles set is_private=true where id='${a}'`);
  await login(admin);assert.equal(await scalar("select social_media_readable('stories',$1)",[`${a}/reported.jpg`]),true);
  assert.equal(await scalar("select social_media_readable('stories',$1)",[`${a}/active.jpg`]),false);
  await scalar("select admin_console_action('resolve_report',$1,'Reviewed selected report',null)",[reportId]);
  assert.equal(await scalar("select social_media_readable('stories',$1)",[`${a}/reported.jpg`]),false);
  await system();await db.exec(`update profiles set is_private=false where id='${a}'`);
 });
 await check('forged review GUCs and direct version changes cannot authorize publication',async()=>{
  await login(a);await db.exec("select set_config('app.ugc_decision','approved',false)");
  await denied('update posts set moderation_version=gen_random_uuid() where id=$1','42501',[post.id]);
  await denied("update posts set moderation_status='approved' where id=$1",'42501',[post.id]);
  await denied("insert into admin_private.ugc_action_context values(txid_current(),auth.uid(),'post',$1,'approved')",'42501',[post.id]);
 });
 await check('reported selected context is scrubbed when its subject is erased',async()=>{
  await system();await db.exec(`delete from fixture_group_members;delete from group_messages;delete from messages;delete from stories;delete from checkins;delete from follows;delete from blocks;delete from comments;delete from posts;delete from events;delete from venue_reviews;delete from notes;delete from place_collections;delete from venues;delete from profiles where id='${a}'`);
  assert.deepEqual(await scalar('select target_snapshot from reports where id=$1',[report]),{});
  assert.equal(await scalar('select target_author_id from reports where id=$1',[report]),null);
 });
 console.log(`${passed} UGC review fixture groups passed`);
}catch(error){console.error('FAIL:',error.message,'\n',error.where??'',error.internalQuery??'',error.query??'');process.exitCode=1;}finally{await db.close();}
