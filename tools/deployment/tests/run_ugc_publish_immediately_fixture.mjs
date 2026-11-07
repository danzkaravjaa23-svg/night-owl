// In-memory PostgreSQL (PGlite) only. Real prior migration bodies, fictional
// identities and synthetic text. No network, hosted project, Auth or Storage bytes.
// Usage: deno run --no-lock --no-config --allow-read <this file> /abs/path/pglite/dist/index.js
import assert from 'node:assert/strict';
import {readFile} from 'node:fs/promises';
import {pathToFileURL} from 'node:url';
import {seedStoreRolloutFixture} from './store_rollout_fixture.mjs';
const {PGlite}=await import(pathToFileURL(process.argv[2]).href);
const db=new PGlite();
const read=p=>readFile(new URL('../../../'+p,import.meta.url),'utf8');
const q=async(sql,args=[])=>(await db.query(sql,args)).rows;
// Tolerates zero rows: a reporter cannot see what they reported.
const scalar=async(sql,args=[])=>{const rows=await q(sql,args);return rows.length?Object.values(rows[0])[0]:undefined;};
const login=async id=>db.exec(`reset role;select set_config('request.jwt.claim.sub','${id??''}',false);set role ${id?'authenticated':'anon'}`);
const system=async()=>db.exec("reset role;select set_config('request.jwt.claim.sub','',false)");
const denied=async(sql,args=[],code='42501')=>assert.rejects(db.query(sql,args),e=>e.code===code,`expected ${code}: ${sql}`);
let passed=0;const check=async(name,fn)=>{await fn();passed++;console.log('PASS: '+name);};
const uuidPattern=/^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/;
// r1..r7 and r9 are established members; r8 is a fresh Auth account; r10 never publishes a profile.
const r=[null,...Array.from({length:10},(_,i)=>'50000000-0000-0000-0000-'+String(i+1).padStart(12,'0'))];
const media=(bucket,owner,name)=>`https://fixture.test/storage/v1/object/public/${bucket}/${owner}/${name}`;
const replaced=['public.ugc_content_guard()','public.interaction_note_write_guard()','public.create_comment_notification()',
  'public.admin_console_review_queue(text,text,integer,integer)','public.admin_console_audit_change()'];
const created=['public.ugc_fold_case(text)','public.ugc_strip_marks(text)','public.ugc_normalize_text(text)','public.ugc_screen_text(text,jsonb,jsonb)',
  'public.ugc_viewer_reported_ids(text)','public.ugc_report_threshold()'];
const privateTables=['admin_private.ugc_publish_config','admin_private.ugc_blocked_terms','admin_private.ugc_report_holds','admin_private.ugc_hold_context'];
const reporterHidden=['posts','stories','comments','notes','venue_reviews','place_collections'];
const snapshot=async names=>{await system();return scalar(`select jsonb_object_agg(p.oid::regprocedure::text,jsonb_build_object('md5',md5(p.prosrc),
  'config',p.proconfig,'secdef',p.prosecdef,'acl',p.proacl::text[])) from pg_proc p where p.oid=any($1::regprocedure[])`,[names]);};
const status=async(table,id)=>{await system();return scalar(`select moderation_status from public.${table} where id=$1`,[id]);};
const sees=async(user,table,id)=>{await login(user);return scalar(`select count(*) from public.${table} where id=$1`,[id]);};
const inFeed=async(user,id)=>{await login(user);return scalar("select count(*) from get_discovery_feed(false,null,null,50) f where f->>'id'=$1",[id]);};
const post=async(user,caption,extra='')=>{await login(user);
  return (await q(`insert into posts(user_id,caption${extra?',media_url':''}) values(auth.uid(),$1${extra?',$2':''}) returning id,moderation_status,moderation_version`,extra?[caption,extra]:[caption]))[0];};
const comment=async(user,postId,body)=>{await login(user);return (await q('insert into comments(user_id,post_id,body) values(auth.uid(),$1,$2) returning id,moderation_status',[postId,body]))[0];};
const report=async(user,type,id,reason='hate')=>{await login(user);return scalar('select report_ugc($1,$2::uuid,$3,$4)',[type,id,reason,null]);};
const queue=async(kind,state='pending')=>{await login(r.admin);return scalar('select admin_console_review_queue($1,$2,0,100)',[kind,state]);};
const queueItem=async(kind,id,state='pending')=>(await queue(kind,state)).items.find(item=>item.id===id);
// Decides a pending item, or hides an approved one ('Харагдахыг зогсоох').
const review=async(kind,id,decision='approved')=>{
  const item=await queueItem(kind,id,'pending')??(decision==='rejected'?await queueItem(kind,id,'approved'):undefined);
  assert.ok(item,`review target missing from queue: ${kind} ${id}`);await login(r.admin);
  return scalar('select admin_console_review($1,$2::uuid,$3::uuid,$4,$5)',[kind,id,item.review_version,decision,'Synthetic decision']);};
const notifications=async(postId,actor)=>{await system();return scalar("select count(*) from notifications where type='comment' and post_id=$1 and actor_id=$2",[postId,actor]);};
const config=async sql=>{await system();await db.exec(`update admin_private.ugc_publish_config set ${sql}`);};
try{
  const seeded=await seedStoreRolloutFixture(db);
  r.admin=seeded.owner;r.member=seeded.other;const venue=seeded.venue;
  await db.exec("select set_config('app.ugc_storage_origin','https://fixture.test',false)");
  // Fixture bootstrap only; a live forward rollout never replays 008/009.
  for(const file of ['202611030008_account_erasure.sql','202611030009_ugc_review.sql'])
    await db.exec(await read('supabase/migrations/'+file));
  // The shared metadata fixture supplies read policies only. Model existing
  // owner write policies beneath the actual restrictive guards.
  await db.exec(`create policy fixture_report_insert on reports for insert to authenticated with check(reporter_id=auth.uid());
    create policy fixture_post_update on posts for update to authenticated using(user_id=auth.uid()) with check(user_id=auth.uid());
    create policy fixture_comment_write on comments for all to authenticated using(user_id=auth.uid()) with check(user_id=auth.uid());
    create policy fixture_note_write on notes for all to authenticated using(user_id=auth.uid()) with check(user_id=auth.uid());
    create policy fixture_review_write on venue_reviews for all to authenticated using(user_id=auth.uid()) with check(user_id=auth.uid());
    create policy fixture_story_write on stories for all to authenticated using(user_id=auth.uid()) with check(user_id=auth.uid());
    create policy fixture_event_write on events for all to authenticated using(organizer_id=auth.uid()) with check(organizer_id=auth.uid());
    create policy fixture_venue_write on venues for all to authenticated using(owner_id=auth.uid()) with check(owner_id=auth.uid());
    alter table comments alter column id set default gen_random_uuid();alter table notes alter column id set default gen_random_uuid();
    alter table venue_reviews alter column id set default gen_random_uuid();alter table events alter column id set default gen_random_uuid();
    alter table venues alter column id set default gen_random_uuid();alter table place_collections alter column id set default gen_random_uuid();
    alter table stories alter column id set default gen_random_uuid();alter table follows alter column id set default gen_random_uuid();
    alter table notifications alter column id set default gen_random_uuid(),alter column created_at set default now();
    create policy fixture_profile_insert on profiles for insert to authenticated with check(id=auth.uid());
    alter table auth.users add column created_at timestamptz not null default now();
    update reports set status='pending' where status is null;`);
  await db.exec(await read('supabase/migrations/202611040001_business_conflict_http.sql'));
  const migration=await read('supabase/migrations/202611070001_ugc_publish_immediately.sql');
  const rollback=await read('tools/deployment/ugc_publish_immediately_rollback.sql');
  const postflight=await read('tools/deployment/tests/ugc_publish_immediately_postflight.sql');
  const ugcPostflight=await read('tools/deployment/tests/ugc_review_postflight.sql');
  const conflictPostflight=await read('tools/deployment/tests/business_conflict_postflight.sql');
  const erasurePostflight=await read('tools/deployment/tests/account_erasure_postflight.sql');
  const unguarded=async()=>{await system();return JSON.parse((await q(erasurePostflight))[0].account_erasure_postflight).unguarded_public_tables;};
  const before=await snapshot(replaced);
  // Synthetic members r1..r10 are created by the maintenance path (like Auth's trigger).
  // Every Auth account except r8 is backdated past the 24-hour reporter age.
  await system();
  for(let i=1;i<=10;i++)await db.exec(`insert into auth.users(id) values('${r[i]}');insert into profiles(id,username,full_name) values('${r[i]}','fixture_r${i}','Fixture R${i}')`);
  await db.query("update auth.users set created_at=now()-interval '30 days' where id<>$1",[r[8]]);
  // A post rejected under 009, before this migration exists (no stored rejection record).
  await login(r.member);const legacyRejected=await scalar("insert into posts(user_id,caption) values(auth.uid(),'Legacy rejected') returning id");
  await system();const legacyVersion=await scalar('select moderation_version from posts where id=$1',[legacyRejected]);
  await login(r.admin);await scalar('select admin_console_review($1,$2::uuid,$3::uuid,$4,$5)',['post',legacyRejected,legacyVersion,'rejected','Synthetic legacy decision']);
  assert.equal(await status('posts',legacyRejected),'rejected');
  // Catalog places: an approved name with link/phone-like text, and a pending member place.
  await db.exec(`insert into venue_catalog(ref,name) values('fixture:approved-dot','Blue.mn Lounge 9911 2233');
    insert into venue_catalog(ref,name,moderation_status) values('fixture:pending','Залга 9911 2233','pending')`);
  for(let i=1;i<=3;i++)await db.exec(`insert into follows(follower_id,following_id) values('${r[i]}','${r.member}'),('${r.member}','${r[i]}')`);

  await check('T03 prerequisite guard: refuses without the PT409 forward fix and creates nothing',async()=>{
    await system();
    const original=await scalar("select pg_get_functiondef('public.admin_console_review(text,uuid,uuid,text,text)'::regprocedure)");
    const md5=await scalar("select md5(prosrc) from pg_proc where oid='public.admin_console_review(text,uuid,uuid,text,text)'::regprocedure");
    await db.exec(original.replaceAll("'PT409'","'40001'"));
    await assert.rejects(db.exec(migration),/Apply 202611040001_business_conflict_http\.sql first/);await db.exec('rollback');
    for(const t of privateTables)assert.equal(await scalar('select to_regclass($1)::text',[t]),null);
    for(const f of created)assert.equal(await scalar('select to_regprocedure($1)::text',[f]),null);
    assert.deepEqual(await snapshot(replaced),before);
    await db.exec(original);
    assert.equal(await scalar("select md5(prosrc) from pg_proc where oid='public.admin_console_review(text,uuid,uuid,text,text)'::regprocedure"),md5);
    await db.exec(conflictPostflight);
  });
  await check('T01 install: postflight refuses before, all postflights pass after, erasure guard coverage intact',async()=>{
    await system();
    await assert.rejects(db.exec(postflight),/Missing publish-immediately state/);await db.exec('rollback');
    await db.exec(migration);
    await db.exec(postflight);await db.exec(ugcPostflight);await db.exec(conflictPostflight);
    assert.deepEqual(await unguarded(),[]);
  });
  const installed=async()=>snapshot([...replaced,...created]);
  await check('T02 rerun is a no-op and preserves owner configuration and removed seed terms',async()=>{
    await config('report_hide_threshold=4');
    await system();assert.equal(await scalar('select count(*) from admin_private.ugc_blocked_terms'),25);
    await db.exec("delete from admin_private.ugc_blocked_terms where term='meth'");
    const first=await installed();
    await db.exec(migration);await db.exec(postflight);
    assert.deepEqual(await installed(),first);
    await system();
    assert.equal(await scalar('select count(*) from admin_private.ugc_blocked_terms'),24);
    assert.equal(await scalar("select count(*) from admin_private.ugc_blocked_terms where term='meth'"),0);
    assert.equal(await scalar('select report_hide_threshold from admin_private.ugc_publish_config'),4);
    assert.equal(await scalar("select count(*) from pg_policy where polname='ugc_reporter_hidden_read'"),6);
    assert.equal(await scalar("select count(*) from pg_proc where oid='public.admin_console_audit_change()'::regprocedure and prosrc like '%ugc_hold_context%'"),1);
    await db.exec("insert into admin_private.ugc_blocked_terms(term,match_mode,category) values ('meth','word','drugs')");
    await config('report_hide_threshold=3');
  });
  await check('T04 private state, internal helpers and hold context are closed to clients',async()=>{
    await login(r.member);
    for(const t of privateTables)await denied(`select * from ${t}`);
    await denied("select public.ugc_screen_text('post','{}'::jsonb,null)");
    await denied("select public.ugc_normalize_text('x')");
    await denied("select public.ugc_strip_marks('x')");
    await denied("select public.ugc_fold_case('x')");
    for(const role of ['anon','authenticated'])
      assert.equal(await scalar("select has_function_privilege($1,'public.ugc_report_threshold()','execute')",[role]),false);
    await login(null);assert.deepEqual(await scalar("select ugc_viewer_reported_ids('post')"),[]);
    const held=await post(r.member,'hujaa security probe');assert.equal(held.moderation_status,'pending');
    await denied("update posts set moderation_status='approved' where id=$1",[held.id]);
    await denied("insert into admin_private.ugc_hold_context values(txid_current(),'post',$1)",[held.id]);
    assert.equal(await status('posts',held.id),'pending');
  });
  let base;
  await check('T05 ordinary content is approved on insert and visible to others',async()=>{
    // Members (not r7, r10) save their profile once, as onboarding does; a clean save publishes it.
    for(const i of [1,2,3,4,5,6,8,9]){
      await login(r[i]);await db.exec(`update profiles set full_name='Member ${i}' where id=auth.uid()`);
      await system();assert.deepEqual((await q('select moderation_status,moderation_public_ready from profiles where id=$1',[r[i]]))[0],{moderation_status:'approved',moderation_public_ready:true});
    }
    base=await post(r.member,'Сайн уу Night Owl');assert.equal(base.moderation_status,'approved');
    assert.equal(await sees(r[4],'posts',base.id),1);assert.equal(await sees(null,'posts',base.id),1);
    assert.equal(await inFeed(r[4],base.id),1);
    const c=await comment(r[4],base.id,'Гоё зураг');assert.equal(c.moderation_status,'approved');
    assert.equal(await sees(r[5],'comments',c.id),1);
    await system();assert.equal(await scalar('select comments_count from posts where id=$1',[base.id]),1);
    assert.equal(await notifications(base.id,r[4]),1);
    await login(r.member);
    assert.equal(await scalar("insert into stories(user_id,caption,expires_at) values(auth.uid(),'Өнөө орой',now()+interval '1 day') returning moderation_status"),'approved');
    const note=(await q("insert into notes(user_id,text) values(auth.uid(),'Энд байна') returning id,moderation_status"))[0];
    assert.equal(note.moderation_status,'approved');assert.equal(await sees(r[1],'notes',note.id),1);
    await login(r.member);
    assert.equal(await scalar("insert into venue_reviews(venue_id,user_id,rating,comment) values($1,auth.uid(),5,'Сайхан газар') returning moderation_status",[venue]),'approved');
    const pub=(await q("insert into place_collections(user_id,title,is_public) values(auth.uid(),'Дуртай газрууд',true) returning id,moderation_status"))[0];
    assert.equal(pub.moderation_status,'approved');assert.equal(await sees(r[4],'place_collections',pub.id),1);
    await login(r.member);
    assert.equal(await scalar("insert into place_collections(user_id,title,is_public) values(auth.uid(),'Private list',false) returning moderation_status"),'approved');
  });
  await check('T06 blocked terms are held for the moderator, including obfuscation',async()=>{
    const ids=[];
    // Obfuscations: zero-width/direction/invisible-operator/grapheme-joiner marks, letter spacing,
    // accents, fullwidth letters and Latin/Cyrillic look-alikes.
    const obfuscated=['c.o.c.a.i.n.e','c o c a i n e','\u0441ocaine','co\u2063caine','co\u200ecaine','co\u034fcaine','coca\u00edne',
      '\uff43\uff4f\uff43\uff41\uff49\uff4e\uff45','x\u0443\u0436\u0430\u0430','ni\u200egger','героиныг зарна','героинтой'];
    for(const caption of ['HUJAA test','Хужаанууд гэж','c0caine tonight','ХАР-ТАМХИ зарна','хартамхи','meth.','kill yourself!!','child-porn','ni​gger',...obfuscated]){
      const p=await post(r.member,caption);assert.equal(p.moderation_status,'pending',caption);
      assert.equal(await sees(r[4],'posts',p.id),0,caption);assert.equal(await sees(r.member,'posts',p.id),1,caption);ids.push(p.id);
    }
    const item=await queueItem('post',ids[2]);
    assert.equal(item.status,'pending');assert.equal(item.hold_reason,'blocked_term');assert.equal(item.report_count,0);
    assert.ok(item.content.moderation_hold.startsWith('Автомат шүүлтүүр: хориотой үг'),item.content.moderation_hold);
  });
  await check('T07 no false positives on look-alike words, tobacco, times and prices',async()=>{
    for(const caption of ['methodology class','heroine movie','snigger laugh','шар тамхи татдаг','Сайн уу Night Owl 22:00','Ресторан 11:30-02:00','12.5% off','ӨЛГИЙ test',
      'Коктейль 7000-9000','Пиво 6000 9000','Tonight.Live DJ set','Mega.Club нээлттэй','Героиня фильма','Героини кино','A B testing','Самбар дээр кофе'])
      assert.equal((await post(r.member,caption)).moderation_status,'approved',caption);
  });
  await check('T08 owner-added term with Mongolian case folding; word mode allows other words',async()=>{
    await system();await db.exec("insert into admin_private.ugc_blocked_terms(term,match_mode,category) values ('Өгүүлбэр Тест','word','custom') on conflict do nothing");
    assert.equal((await comment(r.member,base.id,'өгүүлбэр ТЕСТ!')).moderation_status,'pending');
    assert.equal((await comment(r.member,base.id,'өгүүлбэр тестүүд')).moderation_status,'approved');
  });
  await check('T09 links and phone numbers in any text but usernames are held; prices and dates are not',async()=>{
    let linkId,phoneId;
    for(const caption of ['see https://x.test','www.example','see mega.mn now']){
      const p=await post(r.member,caption);assert.equal(p.moderation_status,'pending',caption);linkId=p.id;}
    for(const caption of ['9911 2233','9911-2233 залга','+976 99112233','+1 415 555 0100']){
      const p=await post(r.member,caption);assert.equal(p.moderation_status,'pending',caption);phoneId=p.id;}
    for(const caption of ['5000-8000₮','5000-8000 төг','15000 төг','2026.11.07'])
      assert.equal((await post(r.member,caption)).moderation_status,'approved',caption);
    assert.equal((await queueItem('post',linkId)).hold_reason,'link');
    const phone=await queueItem('post',phoneId);assert.equal(phone.hold_reason,'phone');
    assert.equal(phone.content.moderation_hold,'Автомат шүүлтүүр: утасны дугаар агуулсан');
    // Display names and collection titles are checked for links and phone numbers too.
    await login(r[5]);await db.exec("update profiles set full_name='Bat 99112233' where id=auth.uid()");
    await system();assert.deepEqual((await q('select full_name,moderation_status,moderation_public_ready from profiles where id=$1',[r[5]]))[0],
      {full_name:'Member 5',moderation_status:'pending',moderation_public_ready:true});
    assert.equal((await queueItem('profile',r[5])).hold_reason,'phone');
    await login(r[5]);await db.exec("update profiles set full_name='Bat Erdene' where id=auth.uid()");
    await system();assert.equal(await scalar('select moderation_status from profiles where id=$1',[r[5]]),'approved');
    for(const title of ['Залга 99112233','see mega.mn','t.me/xxx']){
      await login(r.member);assert.equal(await scalar('insert into place_collections(user_id,title,is_public) values(auth.uid(),$1,true) returning moderation_status',[title]),'pending',title);}
    await login(r.member);assert.equal(await scalar("insert into place_collections(user_id,title,is_public) values(auth.uid(),'Mega.Club шилдэг',true) returning moderation_status"),'approved');
    await login(r[6]);await db.exec("update profiles set username='bat99112233' where id=auth.uid()");
    await system();assert.deepEqual((await q('select moderation_status,moderation_public_ready from profiles where id=$1',[r[6]]))[0],{moderation_status:'approved',moderation_public_ready:true});
    await login(r[6]);await db.exec("update profiles set username='hujaa_99' where id=auth.uid()");
    await system();assert.deepEqual((await q('select username,moderation_status from profiles where id=$1',[r[6]]))[0],{username:'bat99112233',moderation_status:'pending'});
    await config('hold_phone_numbers=false');
    assert.equal((await post(r.member,'9911 2233')).moderation_status,'approved');
    await config('hold_phone_numbers=true');
  });
  await check('T10 editing held text clean releases it; adding a term holds it again',async()=>{
    const p=await post(r.member,'HUJAA edit test');assert.equal(p.moderation_status,'pending');
    await login(r.member);assert.equal(await scalar("update posts set caption='Цэвэр текст' where id=$1 returning moderation_status",[p.id]),'approved');
    assert.equal(await sees(r[4],'posts',p.id),1);
    await login(r.member);assert.equal(await scalar("update posts set caption='Цэвэр текст hujaa' where id=$1 returning moderation_status",[p.id]),'pending');
    await login(r.member);assert.equal(await scalar("update posts set caption='Цэвэр текст дахин' where id=$1 returning moderation_status",[p.id]),'approved');
  });
  let target;
  await check('T11 a reporter stops seeing the item at once; others still see it',async()=>{
    target=await post(r.member,'Report target');assert.equal(target.moderation_status,'approved');
    const id=await report(r[1],'post',target.id);assert.equal(typeof id,'string');assert.match(id,uuidPattern);
    assert.equal(await status('posts',target.id),'approved');
    assert.equal(await sees(r[1],'posts',target.id),0);assert.equal(await inFeed(r[1],target.id),0);
    assert.equal(await sees(r[2],'posts',target.id),1);assert.equal(await sees(r[4],'posts',target.id),1);
    await login(r[1]);await denied('select report_ugc($1,$2::uuid,$3,$4)',['post',target.id,'hate',null],'PT409');
  });
  await check('T12 three distinct reporters hide it from everyone; self and banned reports do not count',async()=>{
    await report(r[2],'post',target.id);assert.equal(await status('posts',target.id),'approved');
    await report(r[3],'post',target.id);assert.equal(await status('posts',target.id),'pending');
    assert.equal(await sees(r[4],'posts',target.id),0);assert.equal(await sees(null,'posts',target.id),0);
    assert.equal(await sees(r.member,'posts',target.id),1);
    const item=await queueItem('post',target.id);
    assert.equal(item.hold_reason,'reports');assert.equal(item.report_count,3);
    assert.ok(item.content.moderation_hold.startsWith('Хэрэглэгчид мэдээлсэн (3 хүн)'),item.content.moderation_hold);
    const p2=await post(r.member,'Second report target');
    await report(r.member,'post',p2.id);await report(r[1],'post',p2.id);await report(r[2],'post',p2.id);
    await system();await db.query('update profiles set is_banned=true where id=$1',[r[2]]);
    await report(r[3],'post',p2.id);
    assert.equal(await status('posts',p2.id),'approved');
    await system();assert.equal(await scalar("select report_count from admin_private.ugc_report_holds where kind='post' and target_id=$1",[p2.id]),2);
    await db.query('update profiles set is_banned=false where id=$1',[r[2]]);
  });
  await check('T13 author edits of a report-held item stay pending',async()=>{
    await login(r.member);assert.equal(await scalar("update posts set caption='Report target edited' where id=$1 returning moderation_status",[target.id]),'pending');
    assert.equal(await sees(r[4],'posts',target.id),0);
  });
  await check('T14 moderator restore; only reports after the decision count towards a new hold',async()=>{
    const receipt=await review('post',target.id,'approved');assert.equal(receipt.status,'approved');
    assert.equal(await sees(r[4],'posts',target.id),1);
    for(const i of [1,2,3])assert.equal(await sees(r[i],'posts',target.id),0);
    await report(r[4],'post',target.id);assert.equal(await status('posts',target.id),'approved');
    await report(r[5],'post',target.id);assert.equal(await status('posts',target.id),'approved');
    await report(r[6],'post',target.id);assert.equal(await status('posts',target.id),'pending');
  });
  const upsertProfile=async(user,f)=>{await login(user);
    await q(`insert into profiles(id,username,full_name,bio,interests) values(auth.uid(),$1,$2,$3,$4::text[])
      on conflict(id) do update set username=excluded.username,full_name=excluded.full_name,bio=excluded.bio,interests=excluded.interests`,[f.username,f.full_name,f.bio,f.interests]);};
  const profileState=async id=>{await system();return (await q('select moderation_status s,moderation_public_ready p,bio from profiles where id=$1',[id]))[0];};
  await check('T15 a moderator rejection sticks through repeated edits, profile upserts and the collection toggle',async()=>{
    const p=await post(r.member,'Will be rejected');assert.equal(p.moderation_status,'approved');
    assert.equal((await review('post',p.id,'rejected')).status,'rejected');
    await login(r.member);assert.equal(await scalar("update posts set caption='Trivial edit' where id=$1 returning moderation_status",[p.id]),'pending');
    await login(r.member);assert.equal(await scalar("update posts set caption='Second trivial edit' where id=$1 returning moderation_status",[p.id]),'pending');
    await login(r.member);assert.equal(await scalar("update posts set caption='Third trivial edit' where id=$1 returning moderation_status",[p.id]),'pending');
    assert.equal(await sees(r[4],'posts',p.id),0);
    const again=await queueItem('post',p.id);assert.equal(again.hold_reason,'rejected_before');
    assert.ok(again.content.moderation_hold.startsWith('Өмнө татгалзсан'),again.content.moderation_hold);
    // A report hold followed by a rejection also survives two edits.
    const held=await post(r.member,'Held then rejected');
    for(const i of [1,2,3])await report(r[i],'post',held.id);
    assert.equal(await status('posts',held.id),'pending');
    assert.equal((await review('post',held.id,'rejected')).status,'rejected');
    await login(r.member);await db.query("update posts set caption='Held edit one' where id=$1",[held.id]);
    await login(r.member);await db.query("update posts set caption='Held edit two' where id=$1",[held.id]);
    assert.equal(await status('posts',held.id),'pending');assert.equal(await sees(r[4],'posts',held.id),0);
    // Approving afterwards publishes normally, and later clean edits stay published.
    assert.equal((await review('post',p.id,'approved')).status,'approved');assert.equal(await sees(r[4],'posts',p.id),1);
    await login(r.member);assert.equal(await scalar("update posts set caption='Clean after approval' where id=$1 returning moderation_status",[p.id]),'approved');
    // A rejected public profile saved twice through a build-3 style upsert stays hidden.
    const fields={username:'fixture_r9',full_name:'Member 9',bio:'Nine',interests:['Bar']};
    await upsertProfile(r[9],fields);assert.deepEqual(await profileState(r[9]),{s:'approved',p:true,bio:'Nine'});
    assert.equal((await review('profile',r[9],'rejected')).status,'rejected');
    assert.deepEqual(await profileState(r[9]),{s:'rejected',p:false,bio:'Nine'});
    await upsertProfile(r[9],{...fields,bio:'Nine edited'});assert.deepEqual(await profileState(r[9]),{s:'pending',p:false,bio:'Nine edited'});
    await upsertProfile(r[9],{...fields,bio:'Nine edited twice'});assert.deepEqual(await profileState(r[9]),{s:'pending',p:false,bio:'Nine edited twice'});
    assert.equal(await sees(r[4],'profiles',r[9]),0);
    assert.equal((await review('profile',r[9],'approved')).status,'approved');
    assert.deepEqual(await profileState(r[9]),{s:'approved',p:true,bio:'Nine edited twice'});
    await upsertProfile(r[9],{...fields,bio:'Nine again'});assert.deepEqual(await profileState(r[9]),{s:'approved',p:true,bio:'Nine again'});
    await login(r.member);
    const col=await scalar("insert into place_collections(user_id,title,is_public) values(auth.uid(),'hujaa list',true) returning id");
    assert.equal(await status('place_collections',col),'pending');
    await login(r.member);await db.query('update place_collections set is_public=false where id=$1',[col]);
    assert.equal(await status('place_collections',col),'approved');
    await login(r.member);await db.query('update place_collections set is_public=true where id=$1',[col]);
    assert.equal(await status('place_collections',col),'pending');
    await login(r.member);
    const clean=await scalar("insert into place_collections(user_id,title,is_public) values(auth.uid(),'Clean list',true) returning id");
    assert.equal(await status('place_collections',clean),'approved');
    assert.equal((await review('collection',clean,'rejected')).status,'rejected');
    await login(r.member);await db.query('update place_collections set is_public=false where id=$1',[clean]);
    assert.equal(await status('place_collections',clean),'rejected');
    await login(r.member);await db.query('update place_collections set is_public=true where id=$1',[clean]);
    assert.equal(await status('place_collections',clean),'pending');
    await login(r.member);await db.query("update place_collections set title='Clean list 2' where id=$1",[clean]);
    assert.equal(await status('place_collections',clean),'pending');assert.equal(await sees(r[4],'place_collections',clean),0);
    assert.equal((await review('collection',clean,'approved')).status,'approved');assert.equal(await sees(r[4],'place_collections',clean),1);
    await login(r.member);await db.query("update place_collections set title='Clean list 3' where id=$1",[clean]);
    assert.equal(await status('place_collections',clean),'approved');
  });
  await check('T16 notes: report hold keeps the 24-hour lifetime; moderators can now decide notes',async()=>{
    await login(r.member);const note=(await q("insert into notes(user_id,text) values(auth.uid(),'Note to report') returning id,moderation_status"))[0];
    assert.equal(note.moderation_status,'approved');assert.equal(await sees(r[1],'notes',note.id),1);
    await system();const life=(await q('select created_at,expires_at from notes where id=$1',[note.id]))[0];
    for(const i of [1,2,3])assert.match(await report(r[i],'note',note.id),uuidPattern);
    await system();assert.equal(await scalar("select count(*) from reports where target_type='note' and target_id=$1",[note.id]),3);
    assert.equal(await status('notes',note.id),'pending');
    assert.deepEqual((await q('select created_at,expires_at from notes where id=$1',[note.id]))[0],life);
    assert.equal((await review('note',note.id,'rejected')).status,'rejected');
    assert.equal(await status('notes',note.id),'rejected');
    assert.deepEqual((await q('select created_at,expires_at from notes where id=$1',[note.id]))[0],life);
    await login(r.member);const held=(await q("insert into notes(user_id,text) values(auth.uid(),'call 9911 2233') returning id,moderation_status"))[0];
    assert.equal(held.moderation_status,'pending');
    assert.equal((await review('note',held.id,'approved')).status,'approved');
    assert.equal(await status('notes',held.id),'approved');
  });
  await check('T17 a restored comment does not notify twice; a first approval notifies once',async()=>{
    const p=await post(r.member,'Comment notification post');
    const c=await comment(r[4],p.id,'Nice place');assert.equal(c.moderation_status,'approved');
    assert.equal(await notifications(p.id,r[4]),1);
    await system();assert.equal(await scalar('select comments_count from posts where id=$1',[p.id]),1);
    for(const i of [1,2,3])await report(r[i],'comment',c.id);
    assert.equal(await status('comments',c.id),'pending');
    await system();assert.equal(await scalar('select comments_count from posts where id=$1',[p.id]),0);
    assert.equal((await review('comment',c.id,'approved')).status,'approved');
    assert.equal(await notifications(p.id,r[4]),1);
    await system();assert.equal(await scalar('select comments_count from posts where id=$1',[p.id]),1);
    const held=await comment(r[4],p.id,'call 9911 2233');assert.equal(held.moderation_status,'pending');
    assert.equal(await notifications(p.id,r[4]),1);
    await review('comment',held.id,'approved');
    assert.equal(await notifications(p.id,r[4]),2);
  });
  let r7Post;
  await check('T18 an auto-created profile stays hidden until its owner saves; a clean save publishes it',async()=>{
    await system();assert.deepEqual((await q('select moderation_status,moderation_public_ready from profiles where id=$1',[r[7]]))[0],{moderation_status:'pending',moderation_public_ready:false});
    assert.equal(await sees(r[6],'profiles',r[7]),0);
    await login(r[7]);await db.exec("update profiles set full_name='R Seven' where id=auth.uid()");
    await system();assert.deepEqual((await q('select moderation_status,moderation_public_ready from profiles where id=$1',[r[7]]))[0],{moderation_status:'approved',moderation_public_ready:true});
    assert.equal(await sees(r[6],'profiles',r[7]),1);
    await system();assert.equal(await scalar('select count(*) from admin_private.ugc_profile_drafts where profile_id=$1',[r[7]]),0);
    r7Post=await post(r[7],'R7 first post');assert.equal(r7Post.moderation_status,'approved');
    assert.equal(await inFeed(r[6],r7Post.id),1);
  });
  await check('T19 a held edit of a public profile keeps the public identity and stages a draft',async()=>{
    await login(r[7]);await db.exec("update profiles set bio='hujaa haha' where id=auth.uid()");
    await system();const row=(await q('select moderation_status,moderation_public_ready,bio from profiles where id=$1',[r[7]]))[0];
    assert.deepEqual(row,{moderation_status:'pending',moderation_public_ready:true,bio:null});
    assert.equal(await scalar("select candidate->>'bio' from admin_private.ugc_profile_drafts where profile_id=$1",[r[7]]),'hujaa haha');
    await login(r[7]);assert.equal((await scalar('select get_own_profile_draft()')).candidate.bio,'hujaa haha');
    const item=await queueItem('profile',r[7]);
    assert.equal(item.content.bio,'hujaa haha');assert.equal(item.content.moderation_hold,'Автомат шүүлтүүр: хориотой үг — hujaa');
    assert.equal(await sees(r[6],'profiles',r[7]),1);
    await login(r[7]);await db.exec("update profiles set bio='Шөнийн хүн' where id=auth.uid()");
    await system();assert.deepEqual((await q('select moderation_status,moderation_public_ready,bio from profiles where id=$1',[r[7]]))[0],
      {moderation_status:'approved',moderation_public_ready:true,bio:'Шөнийн хүн'});
    assert.equal(await scalar('select count(*) from admin_private.ugc_profile_drafts where profile_id=$1',[r[7]]),0);
  });
  await check('T20 five distinct reporters hide a profile and its posts from discovery until restored',async()=>{
    for(const i of [1,2,3,4])await report(r[i],'user',r[7],'harassment');
    await system();assert.deepEqual((await q('select moderation_status,moderation_public_ready from profiles where id=$1',[r[7]]))[0],{moderation_status:'approved',moderation_public_ready:true});
    await report(r[5],'user',r[7],'harassment');
    await system();assert.deepEqual((await q('select moderation_status,moderation_public_ready from profiles where id=$1',[r[7]]))[0],{moderation_status:'pending',moderation_public_ready:false});
    assert.equal(await sees(r[6],'profiles',r[7]),0);assert.equal(await inFeed(r[6],r7Post.id),0);
    const item=await queueItem('profile',r[7]);assert.equal(item.hold_reason,'reports');assert.equal(item.report_count,5);
    assert.equal((await review('profile',r[7],'approved')).status,'approved');
    await system();assert.deepEqual((await q('select moderation_status,moderation_public_ready from profiles where id=$1',[r[7]]))[0],{moderation_status:'approved',moderation_public_ready:true});
    assert.equal(await inFeed(r[6],r7Post.id),1);
  });
  await check('T21 venue and event listings stay pre-moderated',async()=>{
    await login(r.member);const event=await scalar("insert into events(organizer_id,title,venue_id) values(auth.uid(),'Fixture night',$1) returning id",[venue]);
    assert.equal(await status('events',event),'pending');assert.equal(await sees(r[4],'events',event),0);
    await login(r.member);const place=await scalar("insert into venues(owner_id,name) values(auth.uid(),'Fixture member venue') returning id");
    assert.equal(await status('venues',place),'pending');
    await system();assert.notEqual(await scalar('select moderation_status from venue_catalog where ref=$1',[place]),'approved');
    const item=await queueItem('event',event);assert.equal(item.status,'pending');
    assert.equal(Object.hasOwn(item.content,'moderation_hold'),false);assert.equal(item.hold_reason,null);
  });
  await check('T22 blocking still removes the blocked author from feed and post reads',async()=>{
    assert.equal(await inFeed(r[5],base.id),1);
    await system();await db.query('insert into blocks(blocker_id,blocked_id) values($1,$2)',[r[5],r.member]);
    assert.equal(await inFeed(r[5],base.id),0);
    await login(r[5]);assert.equal(await scalar('select count(*) from posts where user_id=$1',[r.member]),0);
  });
  await check('T23 build-3 client contracts are unchanged',async()=>{
    const p=await post(r.member,'Contract target');
    const id=await report(r[4],'post',p.id,'spam');assert.equal(typeof id,'string');assert.match(id,uuidPattern);
    await login(r[4]);await denied('select report_ugc($1,$2::uuid,$3,$4)',['post',p.id,'spam',null],'PT409');
    for(const state of ['pending','approved','rejected']){
      const page=await queue('all',state);assert.equal(typeof page.has_more,'boolean');assert.ok(page.items.length>0,state);
      for(const item of page.items){
        assert.equal(item.status,state);for(const k of ['id','kind','review_version'])assert.equal(typeof item[k],'string');
        assert.equal(typeof item.content,'object');assert.ok(item.content&&!Array.isArray(item.content));
      }
    }
    const held=await post(r.member,'hujaa contract');const item=await queueItem('post',held.id);
    await login(r.admin);const receipt=await scalar('select admin_console_review($1,$2::uuid,$3::uuid,$4,$5)',['post',held.id,item.review_version,'rejected','Synthetic contract decision']);
    assert.equal(receipt.status,'rejected');assert.equal(receipt.review_version,item.review_version);assert.match(receipt.audit_id,uuidPattern);
    await login(r[7]);assert.deepEqual(Object.keys(await scalar('select get_own_profile_draft()')).sort(),
      ['candidate','moderation_public_ready','moderation_status','moderation_submitted_at','moderation_version']);
    await login(r.admin);const reports=await scalar("select admin_console_reports('pending',0,100)");
    assert.ok(reports.items.some(row=>row.id===id));
  });
  await check('T24 kill switch returns new writes to review-before-publish',async()=>{
    await config('publish_immediately=false');
    assert.equal((await post(r.member,'Kill switch post')).moderation_status,'pending');
    await login(r[7]);await db.exec("update profiles set bio='Kill switch bio' where id=auth.uid()");
    await system();assert.deepEqual((await q('select moderation_status,moderation_public_ready,bio from profiles where id=$1',[r[7]]))[0],
      {moderation_status:'pending',moderation_public_ready:true,bio:'Шөнийн хүн'});
    assert.equal(await scalar("select candidate->>'bio' from admin_private.ugc_profile_drafts where profile_id=$1",[r[7]]),'Kill switch bio');
    await config('publish_immediately=true');
    assert.equal((await post(r.member,'Back on')).moderation_status,'approved');
  });
  await check('T25 maintenance writes keep defaults; held media is private again',async()=>{
    await system();
    assert.equal(await scalar("insert into posts(user_id,caption) values($1,'System row') returning moderation_status",[r.member]),'pending');
    await db.query("insert into reports(reporter_id,target_type,target_id,reason) values($1,'post',$2,'spam')",[r[6],base.id]);
    assert.equal(await scalar("select count(*) from admin_private.ugc_report_holds where kind='post' and target_id=$1",[base.id]),0);
    const p=await post(r.member,'Media post',media('posts',r.member,'a.jpg'));assert.equal(p.moderation_status,'approved');
    const readable=async user=>{await login(user);return scalar("select social_media_readable('posts',$1)",[`${r.member}/a.jpg`]);};
    assert.equal(await readable(r[4]),true);
    for(const i of [1,2,3])await report(r[i],'post',p.id,'nudity');
    assert.equal(await status('posts',p.id),'pending');
    assert.equal(await readable(r[4]),false);assert.equal(await readable(r.admin),true);assert.equal(await readable(r.member),true);
  });
  await check('T27 every public text field is screened: venue names, music, interests, display names',async()=>{
    await login(r.member);
    assert.equal(await scalar("insert into posts(user_id,caption,venue_name) values(auth.uid(),'nice night','hujaa call 9911 2233 www.x.com') returning moderation_status"),'pending');
    await login(r.member);
    assert.equal(await scalar("insert into posts(user_id,caption,venue_name) values(auth.uid(),'nice night','Залга 9911 2233') returning moderation_status"),'pending');
    const p=await post(r.member,'Venue edit target');assert.equal(p.moderation_status,'approved');
    await login(r.member);assert.equal(await scalar("update posts set venue_name='Утас 9911 2233' where id=$1 returning moderation_status",[p.id]),'pending');
    assert.equal(await sees(r[4],'posts',p.id),0);
    // The approved catalog name of a tagged place is not user text.
    await login(r.member);
    const tagged=(await q("insert into posts(user_id,caption,venue_ref,venue_name) values(auth.uid(),'At the place',$1,'Shared community place') returning id,moderation_status",[venue]))[0];
    assert.equal(tagged.moderation_status,'approved');
    await login(r.member);assert.equal(await scalar("update posts set venue_name='hujaa bar' where id=$1 returning moderation_status",[tagged.id]),'pending');
    await login(r.member);assert.equal(await scalar("insert into posts(user_id,caption,venue_ref,venue_name) values(auth.uid(),'Lounge night','fixture:approved-dot','Blue.mn Lounge 9911 2233') returning moderation_status"),'approved');
    await login(r.member);assert.equal(await scalar("insert into posts(user_id,caption,venue_ref,venue_name) values(auth.uid(),'Pending place','fixture:pending','Залга 9911 2233') returning moderation_status"),'pending');
    const story=async(title,artist)=>{await login(r.member);
      return scalar("insert into stories(user_id,caption,music_title,music_artist,expires_at) values(auth.uid(),'',$1,$2,now()+interval '1 day') returning moderation_status",[title,artist]);};
    assert.equal(await story('call 99112233','DJ'),'pending');
    assert.equal(await story('Night Drive','www.x.com'),'pending');
    assert.equal(await story('hujaa song','DJ'),'pending');
    assert.equal(await story('Night Drive','Tonight.Live'),'approved');
    await login(r[5]);await db.exec("update profiles set interests=array['hujaa'] where id=auth.uid()");
    await system();assert.deepEqual((await q('select interests,moderation_status,moderation_public_ready from profiles where id=$1',[r[5]]))[0],
      {interests:[],moderation_status:'pending',moderation_public_ready:true});
    await login(r[5]);await db.exec("update profiles set interests=array['Bar'] where id=auth.uid()");
    await system();assert.equal(await scalar('select moderation_status from profiles where id=$1',[r[5]]),'approved');
    await login(r[5]);await db.exec("update profiles set full_name='Escort 9911 2233' where id=auth.uid()");
    await system();assert.deepEqual((await q('select full_name,moderation_status from profiles where id=$1',[r[5]]))[0],{full_name:'Bat Erdene',moderation_status:'pending'});
    await login(r[5]);await db.exec("update profiles set full_name='Bat Erdene B' where id=auth.uid()");
    await system();assert.equal(await scalar('select moderation_status from profiles where id=$1',[r[5]]),'approved');
  });
  await check('T28 only established accounts count towards a report hold',async()=>{
    const p=await post(r.member,'Eligibility target');
    await report(r[8],'post',p.id);await report(r[10],'post',p.id);await report(r[1],'post',p.id);await report(r[2],'post',p.id);
    assert.equal(await status('posts',p.id),'approved');
    await system();assert.equal(await scalar("select report_count from admin_private.ugc_report_holds where kind='post' and target_id=$1",[p.id]),2);
    await report(r[3],'post',p.id);assert.equal(await status('posts',p.id),'pending');
    // The owner can lower the account age; a fresh public account then counts.
    await config("reporter_min_account_age=interval '0 seconds'");
    const p2=await post(r.member,'Eligibility target two');
    await report(r[8],'post',p2.id);await report(r[1],'post',p2.id);await report(r[2],'post',p2.id);
    assert.equal(await status('posts',p2.id),'pending');
    await config("reporter_min_account_age=interval '24 hours'");
  });
  await check('T29 an admin crossing the report threshold leaves no admin edit receipt',async()=>{
    const p=await post(r.member,'Admin report target');
    // r5 blocked the author in T22 and can no longer see or report this post.
    await report(r[4],'post',p.id);await report(r[6],'post',p.id);
    await system();const before=await scalar('select count(*) from admin_audit_log');
    await report(r.admin,'post',p.id);assert.equal(await status('posts',p.id),'pending');
    await system();assert.equal(await scalar('select count(*) from admin_audit_log'),before);
    assert.equal(await scalar('select count(*) from admin_audit_log where target_id=$1::text',[p.id]),0);
    // A moderator decision is still audited once.
    await review('post',p.id,'approved');
    await system();assert.equal(await scalar("select count(*) from admin_audit_log where target_id=$1::text and action='approved_content'",[p.id]),1);
    assert.equal(await scalar('select count(*) from admin_audit_log where target_id=$1::text',[p.id]),1);
  });
  await check('T30 new media on an edited post waits for a moderator; caption edits do not',async()=>{
    const p=await post(r.member,'Media swap',media('posts',r.member,'b.jpg'));assert.equal(p.moderation_status,'approved');
    await login(r.member);assert.equal(await scalar('update posts set media_url=$2 where id=$1 returning moderation_status',[p.id,media('posts',r.member,'c.jpg')]),'pending');
    assert.equal(await sees(r[4],'posts',p.id),0);
    const kept=await post(r.member,'Media keep',media('posts',r.member,'d.jpg'));
    await login(r.member);assert.equal(await scalar("update posts set caption='Media keep edited' where id=$1 returning moderation_status",[kept.id]),'approved');
  });
  await check('T31 a build-3 profile upsert never loses a held draft',async()=>{
    const fields={username:'fixture_r9',full_name:'Member 9',bio:'Night bio',interests:['Bar']};
    await upsertProfile(r[9],fields);assert.deepEqual(await profileState(r[9]),{s:'approved',p:true,bio:'Night bio'});
    await upsertProfile(r[9],{...fields,bio:'hujaa night'});assert.deepEqual(await profileState(r[9]),{s:'pending',p:true,bio:'Night bio'});
    const draft=async()=>{await system();return scalar('select count(*) from admin_private.ugc_profile_drafts where profile_id=$1',[r[9]]);};
    assert.equal(await draft(),1);
    // Re-saving the published values (the INSERT half is clean) keeps the draft, as 009 did.
    await upsertProfile(r[9],fields);assert.deepEqual(await profileState(r[9]),{s:'pending',p:true,bio:'Night bio'});
    assert.equal(await draft(),1);
    await login(r[9]);assert.notEqual((await scalar('select get_own_profile_draft()')).candidate,null);
    await upsertProfile(r[9],{...fields,bio:'Night bio two'});assert.deepEqual(await profileState(r[9]),{s:'approved',p:true,bio:'Night bio two'});
    assert.equal(await draft(),0);
    // Invariant: a pending profile whose identity is public always has a draft candidate.
    await system();assert.equal(await scalar(`select count(*) from profiles p where p.moderation_status='pending' and p.moderation_public_ready
      and not exists(select 1 from admin_private.ugc_profile_drafts d where d.profile_id=p.id)`),0);
  });
  await check('T32 a post rejected before this migration also stays held through repeated edits',async()=>{
    await login(r.member);assert.equal(await scalar("update posts set caption='Legacy edit one' where id=$1 returning moderation_status",[legacyRejected]),'pending');
    await login(r.member);assert.equal(await scalar("update posts set caption='Legacy edit two' where id=$1 returning moderation_status",[legacyRejected]),'pending');
    assert.equal(await sees(r[4],'posts',legacyRejected),0);
    assert.equal((await queueItem('post',legacyRejected)).hold_reason,'rejected_before');
  });
  await check('T26 exact rollback, then reinstall',async()=>{
    await system();await db.exec(rollback);
    assert.deepEqual(await snapshot(replaced),before);
    await system();
    assert.equal(await scalar("select count(*) from pg_policy where polname='ugc_reporter_hidden_read'"),0);
    assert.equal(await scalar("select count(*) from pg_trigger where tgname='zz_ugc_report_threshold'"),0);
    for(const t of privateTables)assert.equal(await scalar('select to_regclass($1)::text',[t]),null);
    for(const f of created)assert.equal(await scalar('select to_regprocedure($1)::text',[f]),null);
    await db.exec(ugcPostflight);await db.exec(conflictPostflight);assert.deepEqual(await unguarded(),[]);
    assert.equal((await post(r.member,'After rollback')).moderation_status,'pending');
    await system();await db.exec(migration);await db.exec(postflight);
    assert.equal((await post(r.member,'After reinstall')).moderation_status,'approved');
  });
  console.log(JSON.stringify({passed,scope:'synthetic in-memory PostgreSQL',hosted:false}));
}catch(error){console.error('FAIL:',error.stack??error.message,error.where??'',error.query??'');process.exitCode=1;}
finally{await db.close();}
