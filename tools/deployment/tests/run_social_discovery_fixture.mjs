import assert from 'node:assert/strict';
import {readFile} from 'node:fs/promises';
import {fileURLToPath,pathToFileURL} from 'node:url';
import path from 'node:path';
const {PGlite}=await import(pathToFileURL(process.argv[2]).href);
const root=path.resolve(path.dirname(fileURLToPath(import.meta.url)),'../../..');
const db=new PGlite();
const viewer='10000000-0000-0000-0000-000000000001';
const creator='10000000-0000-0000-0000-000000000002';
const admin='10000000-0000-0000-0000-000000000003';
const stranger='10000000-0000-0000-0000-000000000004';
const venue='20000000-0000-0000-0000-000000000001';
const photo='30000000-0000-0000-0000-000000000001';
const read=f=>readFile(path.join(root,f),'utf8');
const rows=async sql=>(await db.query(sql)).rows;
const login=async id=>db.exec(`reset role; select set_config('request.jwt.claim.sub','${id??''}',false); set role ${id?'authenticated':'anon'};`);
const scalar=async sql=>Object.values((await rows(sql))[0])[0];
try {
  await db.exec(await read('tools/deployment/tests/social_discovery_fixture.sql'));
  const preflight=await read('tools/deployment/tests/social_discovery_preflight.sql');
  await db.exec(preflight);
  await db.exec('alter role authenticated bypassrls');
  await assert.rejects(db.exec(preflight),/must not bypass RLS/);
  await db.exec('rollback;alter role authenticated nobypassrls');
  await db.exec('grant create on schema public to anon');
  await assert.rejects(db.exec(preflight),/can create objects/);
  await db.exec('rollback;revoke create on schema public from anon');
  const migration=await read('supabase/migrations/202610160001_social_discovery.sql');
  await db.exec(migration);
  await db.exec(migration);
  await db.exec(preflight);
  await db.exec(await read('supabase/migrations/202610160002_osm_catalog.sql'));
  await db.exec(await read('supabase/migrations/202610160002_osm_catalog.sql'));
  assert.equal(await scalar('select count(*)::int from venue_catalog'),271);
  assert.equal(await scalar('select count(*)::int from pilot_creators'),0);
  await db.exec("update checkins set audience='public'");
  await login(creator);
  await db.exec('update profiles set is_private=true where id=auth.uid()');
  await db.exec('update profiles set is_admin=true,is_verified=true where id=auth.uid()');
  assert.equal(await scalar('select is_admin from profiles where id=auth.uid()'),false);
  await login(viewer);
  const oldBlock=await scalar(`select get_relationship('${admin}')`);
  assert.equal(oldBlock.following,false);
  assert.equal(oldBlock.blocked,true);
  assert.equal((await rows('select * from posts')).length,0);
  assert.equal((await rows('select * from stories')).length,0);
  assert.equal((await rows('select * from checkins')).length,0);
  assert.equal((await rows('select * from storage.objects')).length,0);
  assert.equal((await rows('select * from get_following_reels()')).length,0);
  assert.equal(await scalar(`select set_follow('${creator}',true)`),'requested');
  await assert.rejects(db.exec(`insert into follows values('${viewer}','${creator}')`));
  await login(creator);
  await db.exec(`select respond_follow_request('${viewer}',true)`);
  await login(viewer);
  assert.equal((await rows('select * from posts')).length,2);
  assert.equal((await rows('select * from stories')).length,1);
  assert.equal((await rows('select * from checkins')).length,1);
  assert.equal(await scalar(`select social_media_readable('stories','${creator}/expired.jpg')`),false);
  assert.equal((await rows('select * from storage.objects')).length,1);
  assert.equal((await rows('select * from get_discovery_feed(true,null,null,1)')).length,1);
  const first=await scalar('select * from get_discovery_feed(true,null,null,1)');
  const second=await scalar(`select * from get_discovery_feed(true,'${first.created_at}','${first.id}',1)`);
  assert.notEqual(first.id,second.id);
  // More than a page of newer non-followed clips and followed photos must not
  // hide an older followed video. Roll back this synthetic load after checking.
  await db.exec(`reset role;begin;
    insert into posts(user_id,media_url,created_at)
      select '${stranger}','https://fixture.test/new.mp4',now() from generate_series(1,60);
    insert into posts(user_id,media_url,created_at)
      select '${creator}','https://fixture.test/new.jpg',now() from generate_series(1,60);
    insert into posts(id,user_id,media_type,media_url,media_urls,created_at) values
      ('40000000-0000-0000-0000-000000000001','${creator}','image','https://fixture.test/cover.jpg',array['https://fixture.test/array.MP4?token=ok'],'2026-10-02'),
      ('40000000-0000-0000-0000-000000000002','${creator}','video','https://fixture.test/stream','{}','2026-10-02'),
      ('40000000-0000-0000-0000-000000000003','${creator}','image','https://fixture.test/image.mp4.jpg','{}',now()),
      ('40000000-0000-0000-0000-000000000004','${creator}','video','javascript:alert(1)','{}',now());`);
  await login(viewer);
  const followedClips=await rows('select * from get_following_reels(50)');
  assert.deepEqual(followedClips.map(r=>r.get_following_reels.id),[
    '40000000-0000-0000-0000-000000000002',
    '40000000-0000-0000-0000-000000000001',
    '30000000-0000-0000-0000-000000000002',
  ]);
  assert.equal((await rows('select * from get_following_reels(1)')).length,1);
  await login(stranger);
  assert.equal((await rows('select * from get_following_reels()')).length,0);
  await db.exec('reset role;rollback');
  await login(viewer);
  await db.exec(`insert into venue_saves(user_id,venue_ref) values(auth.uid(),'${venue}')`);
  const collection=await scalar("insert into place_collections(user_id,title) values(auth.uid(),'Synthetic list') returning id");
  await db.exec(`insert into collection_places values('${collection}','${venue}','Synthetic note',now())`);
  await login(stranger);
  assert.equal((await rows('select * from place_collections')).length,1);
  assert.equal((await rows('select * from venue_saves')).length,0);
  await assert.rejects(db.exec(`insert into collection_places values('${collection}','osm:node:6380522595','',now())`));
  await assert.rejects(db.exec(`insert into follows values('${viewer}','${admin}')`));
  await login(viewer);
  await db.exec(`update place_collections set is_public=false where id='${collection}'`);
  await login(stranger);
  assert.equal((await rows('select * from place_collections')).length,0);
  assert.equal((await rows('select * from collection_places')).length,0);
  // A stranger gets one request, not an unrestricted conversation.
  await db.exec(`select send_direct_message('${creator}','Synthetic hello')`);
  await assert.rejects(db.exec(`select send_direct_message('${creator}','Second unsolicited message')`));
  await assert.rejects(db.exec(`insert into messages(sender_id,receiver_id,body) values(auth.uid(),'${creator}','Bypass')`));
  await login(creator);
  await assert.rejects(db.exec("update messages set body='Tampered'"));
  await db.exec('update messages set is_read=true where receiver_id=auth.uid()');
  await db.exec(`select respond_message_request('${stranger}',true)`);
  await login(stranger);
  await db.exec(`select send_direct_message('${creator}','Approved message')`);
  await login(creator);
  await db.exec(`insert into blocks values(auth.uid(),'${stranger}')`);
  await login(stranger);
  await assert.rejects(db.exec(`select send_direct_message('${creator}','Blocked message')`));
  assert.equal((await rows('select * from messages')).length,0);
  await assert.rejects(db.exec('select get_pilot_overview()'));
  await login(creator);
  await db.exec('update profiles set is_private=false where id=auth.uid()');
  await login(admin);
  await assert.rejects(db.exec(`select set_pilot_entry('venue','${venue}',true)`));
  await db.exec(`select review_venue('${venue}','{"address":"Synthetic address","hours":"18:00-23:00","cover_url":"https://fixture.test/cover.jpg","price_min":10000,"price_max":30000,"vibes":["Тайван"]}'::jsonb)`);
  await db.exec(`select set_pilot_entry('venue','${venue}',true);select set_pilot_entry('creator','${creator}',true);select set_pilot_entry('participant','${viewer}',true);select set_pilot_entry('content','${photo}',true);`);
  await login(viewer);
  await assert.rejects(db.exec("select record_discovery_activity('follow','spoofed')"));
  await assert.rejects(db.exec(`select import_venue_saves('${creator}',array['osm:node:6380522595'])`));
  assert.equal(await scalar(`select import_venue_saves('${viewer}',array['osm:node:6380522595','obsolete-place'])`),1);
  await assert.rejects(db.exec(`insert into venue_saves(user_id,venue_ref,legacy_import)
    select auth.uid(),ref,true from venue_catalog where ref not in(select venue_ref from venue_saves) limit 1`),error=>error.code==='42501');
  await db.exec('reset role');
  assert.equal(await scalar("select count(*)::int from discovery_activity where event='venue_save'"),0);
  await login(viewer);
  await db.exec(`insert into venue_saves(user_id,venue_ref)
    select auth.uid(),ref from venue_catalog where ref not in(select venue_ref from venue_saves) limit 1`);
  await db.exec('reset role');
  assert.equal(await scalar("select count(*)::int from discovery_activity where event='venue_save'"),1);
  await login(viewer);
  await db.exec(`select record_discovery_activity('session');select record_discovery_activity('session');select record_discovery_activity('directions','${venue}');`);
  await login(creator);
  await db.exec('update profiles set is_private=true where id=auth.uid()');
  await login(null);
  assert.equal((await rows('select * from posts')).length,0);
  assert.equal((await rows('select * from storage.objects')).length,0);
  await assert.rejects(db.exec('select * from get_following_reels()'),error=>error.code==='42501');
  await db.exec('reset role');
  assert.equal(await scalar("select count(*)::int from discovery_activity where event='session'"),2);
  // Mature one synthetic cohort member and exercise exact D7 windows.
  await db.exec(`update pilot_participants set enrolled_at=now()-interval '9 days' where user_id='${viewer}';
    insert into discovery_activity(user_id,event,target,day,created_at) values
    ('${viewer}','follow','synthetic-old',(now()-interval '9 days')::date,now()-interval '8 days 23 hours'),
    ('${viewer}','session','',(now()-interval '2 days')::date,now()-interval '1 day 23 hours');`);
  await login(admin);
  const overview=await scalar('select get_pilot_overview()');
  assert.equal(overview.users,2);
  assert.equal(overview.activation_eligible,1);
  assert.equal(overview.activated,1);
  assert.equal(overview.first_day_followed,1);
  assert.equal(overview.first_day_saved,0);
  assert.equal(overview.d7_eligible,1);
  assert.equal(overview.d7_returned,1);
  assert.equal(overview.creator_count,1);
  assert.equal(overview.venues,1);
  assert.equal(overview.content,1);
  await db.exec(`update venues set address='Updated synthetic address' where id='${venue}'`);
  assert.equal(await scalar(`select reviewed_at is null from venue_catalog where ref='${venue}'`),true);
  assert.equal((await scalar('select get_pilot_overview()')).venues,0);
  await db.exec(`select set_pilot_entry('participant','${stranger}',true);reset role;
    update pilot_participants set enrolled_at=now()-interval '9 days' where user_id='${stranger}';
    insert into discovery_activity(user_id,event,created_at)
      select user_id,'session',enrolled_at+interval '6 days' from pilot_participants where user_id='${stranger}'
      union all select user_id,'session',enrolled_at+interval '8 days' from pilot_participants where user_id='${stranger}';`);
  await login(admin);
  const boundaries=await scalar('select get_pilot_overview()');
  assert.equal(boundaries.d7_eligible,2);
  assert.equal(boundaries.d7_returned,1);
  console.log('PASS: read-only preflight/role guards, repeatable migrations, 270 real source records, private/expired content and media, existing/new blocks, follow/DM approvals, server-filtered Following reels, account-bound legacy imports, authoritative saves, collections, admin-only pilot and exact activation/D7 boundaries.');
} catch(error) {
  console.error(`${error.code ?? error.name}: ${error.message}`);
  if(error.name==='AssertionError')console.error(error.stack.split('\n').slice(1,4).join('\n'));
  process.exitCode=1;
} finally { await db.close(); }
