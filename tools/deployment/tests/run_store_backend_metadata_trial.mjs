// Actual captured application contracts; synthetic local records only.
// Usage: node ... PGLITE_MODULE metadata.json boundary-metadata.json [result.json] [storage-origin]
import assert from 'node:assert/strict';
import {readFile,writeFile} from 'node:fs/promises';
import {createHash} from 'node:crypto';
import {pathToFileURL} from 'node:url';
import {buildStoreBackendRelease} from '../store_backend_release.mjs';
import {replayStoreBackendMetadata} from './replay_store_backend_metadata.mjs';
const {PGlite}=await import(pathToFileURL(process.argv[2]).href);
const {pg_trgm}=await import(new URL('./contrib/pg_trgm.js',pathToFileURL(process.argv[2])).href);
const metadataSource=await readFile(process.argv[3],'utf8'),boundarySource=await readFile(process.argv[4],'utf8');
const metadata=JSON.parse(metadataSource),boundaries=JSON.parse(boundarySource);
const storageOrigin=process.argv[6]??'https://fixture.test';
const db=new PGlite({extensions:{pg_trgm}});let passed=0;
const scalar=async sql=>Object.values((await db.query(sql)).rows[0])[0];
const check=async(name,run)=>{await run();passed++;console.log('PASS: '+name);};
const hash=s=>createHash('sha256').update(s).digest('hex');
const owner='a1000000-0000-0000-0000-000000000001',other='a1000000-0000-0000-0000-000000000002';
const admin='a1000000-0000-0000-0000-000000000003',post='a2000000-0000-0000-0000-000000000001';
const venue='a4000000-0000-0000-0000-000000000001';
try{
 await db.exec('create extension pg_trgm');
 const replay=await replayStoreBackendMetadata(db,metadata,boundaries);
 await check('current captured tables/functions/policies/application triggers replay in isolation',async()=>{
   assert.equal(replay.functions,metadata.functions.length);assert.equal(replay.relations,metadata.relations.length);
   assert.ok(replay.policies>=100);
   const query=await readFile(new URL('./store_platform_metadata.sql',import.meta.url),'utf8');
   const platform=(await db.exec(query)).find(r=>r.rows?.[0]?.store_platform_metadata).rows[0].store_platform_metadata;
   assert.equal(platform.functions.length,4);assert.equal(platform.enums.length,3);
 });
 // Actual Auth->profile application trigger is replayed; these are fictional IDs.
 for(const [id,username] of [[owner,'trial_owner'],[other,'trial_other'],[admin,'trial_admin']])await db.query(
   'insert into auth.users(id,email,raw_user_meta_data) values($1,$2,$3::jsonb)',[id,username+'@example.invalid',JSON.stringify({username})]);
 await db.query('update profiles set is_admin=true where id=$1',[admin]);
 await db.query('insert into posts(id,user_id,caption,media_url) values($1,$2,$3,$4)',[post,owner,'Legacy approved publication',storageOrigin+'/storage/v1/object/public/posts/'+owner+'/photo.jpg']);
 await db.query('insert into storage.objects(bucket_id,name,owner_id) values($1,$2,$3)',['posts',owner+'/photo.jpg',owner]);
 await db.query('insert into venues(id,name,owner_id,cover_url) values($1,$2,$3,$4)',[venue,'Synthetic curated place',owner,'https://legacy.example.invalid/photo.jpg']);
 await db.query('insert into storage.objects(bucket_id,name,owner_id) values($1,$2,$3)',['venues',admin+'/curated.jpg',admin]);
 const before=await scalar('select jsonb_build_object(\'auth\',(select count(*) from auth.users),\'profiles\',(select count(*) from profiles),\'posts\',(select count(*) from posts),\'objects\',(select count(*) from storage.objects))');
 const {sql,postflight,manifest}=await buildStoreBackendRelease({storageOrigin});
 await check('exact008+009 bundle passes captured production prerequisites and postflight',async()=>{
   await db.exec(sql);await db.exec(postflight);
   const after=await scalar('select jsonb_build_object(\'auth\',(select count(*) from auth.users),\'profiles\',(select count(*) from profiles),\'posts\',(select count(*) from posts),\'objects\',(select count(*) from storage.objects))');
   assert.deepEqual(after,before);assert.equal(await scalar("select count(*)::int from storage.buckets where public"),0);
 });
 const login=async(id,role='authenticated')=>db.exec(`reset role;select set_config('request.jwt.claim.sub','${id??''}',false);select set_config('request.jwt.claim.role','${role}',false);set role ${role}`);
 await check('legacy approved publication remains visible while new content awaits admin',async()=>{
   await login(owner);
   const pending=(await db.query("insert into posts(user_id,caption) values($1,'Pending trial publication') returning id,moderation_status,moderation_version",[owner])).rows[0];
   assert.equal(pending.moderation_status,'pending');
   await login(other);assert.equal(await scalar(`select count(*)::int from posts where id='${post}'`),1);
   assert.equal(await scalar(`select count(*)::int from posts where id='${pending.id}'`),0);
   await login(admin);await db.query("select admin_console_review('post',$1,$2,'approved','Isolated captured-schema trial')",[pending.id,pending.moderation_version]);
   await login(other);assert.equal(await scalar(`select count(*)::int from posts where id='${pending.id}'`),1);
 });
 await check('actual catalog curation RPC is admin-only and accepts only owned canonical replacement media',async()=>{
   await login(owner);await assert.rejects(db.query('select review_venue($1,$2::jsonb)',[venue,JSON.stringify({address:'Unreviewed owner change'})]),e=>e.code==='42501');
   await login(admin);await db.query('select review_venue($1,$2::jsonb)',[venue,JSON.stringify({address:'Updated curated details',cover_url:'https://legacy.example.invalid/photo.jpg'})]);
   await assert.rejects(db.query('select review_venue($1,$2::jsonb)',[venue,JSON.stringify({cover_url:'https://foreign.invalid/storage/v1/object/public/venues/'+admin+'/curated.jpg'})]),e=>e.code==='42501'||e.code==='22023');
   await assert.rejects(db.query('select review_venue($1,$2::jsonb)',[venue,JSON.stringify({cover_url:storageOrigin+'/storage/v1/object/public/venues/'+other+'/curated.jpg'})]),e=>e.code==='42501'||e.code==='22023');
   const cover=storageOrigin+'/storage/v1/object/public/venues/'+admin+'/curated.jpg';
   await db.query('select review_venue($1,$2::jsonb)',[venue,JSON.stringify({address:'Updated curated details',cover_url:cover})]);
   await login(other);assert.equal(await scalar(`select cover_url from venue_catalog where ref='${venue}'`),cover);
 });
 await check('captured Storage policies plus new guard deny approved byte replacement and foreign media',async()=>{
   await login(owner);
   await assert.rejects(db.query('update storage.objects set metadata=$1 where bucket_id=$2 and name=$3',[{},'posts',owner+'/photo.jpg']),e=>e.code==='42501');
   await assert.rejects(db.query('delete from storage.objects where bucket_id=$1 and name=$2',['posts',owner+'/photo.jpg']),e=>e.code==='42501');
   await assert.rejects(db.query('insert into posts(user_id,caption,media_url) values($1,$2,$3)',[owner,'Invalid foreign bytes','https://foreign.invalid/storage/v1/object/public/posts/'+owner+'/photo.jpg']),e=>e.code==='42501'||e.code==='22023');
 });
 await check('pending profile editor restores only its owner candidate under actual profile triggers',async()=>{
   await login(owner);await db.query('update profiles set bio=$1 where id=$2',['Pending private editor text',owner]);
   assert.equal((await scalar('select get_own_profile_draft()')).candidate.bio,'Pending private editor text');
   await login(other);assert.equal((await scalar('select get_own_profile_draft()')).candidate,null);
   assert.notEqual(await scalar(`select bio from profiles where id='${owner}'`),'Pending private editor text');
 });
 await check('reported-message context exposes selected message only with captured DM boundaries',async()=>{
   await db.exec("reset role;select set_config('request.jwt.claim.sub','',false);select set_config('request.jwt.claim.role','',false)");
   const selected='a3000000-0000-0000-0000-000000000001';
   await db.query('insert into messages(id,sender_id,receiver_id,body) values($1,$2,$3,$4)',[selected,owner,other,'Selected reported message']);
   await db.query('insert into messages(sender_id,receiver_id,body) values($1,$2,$3)',[owner,other,'Unreported private sibling']);
   await login(other);await db.query("select report_ugc('message',$1,'harassment','Selected-message test')",[selected]);
   await login(admin);
   const reports=JSON.stringify(await scalar("select admin_console_reports('pending')"));
   assert.ok(reports.includes('Selected reported message'));assert.ok(!reports.includes('Unreported private sibling'));
   assert.equal(await scalar('select count(*)::int from messages'),0);
 });
 await check('member cannot read private journal or invoke prune through captured ACLs',async()=>{
   await login(owner);await assert.rejects(db.query('select * from account_private.erasure_jobs'),e=>e.code==='42501');
   await assert.rejects(db.query("select account_erasure_control('prune')"),e=>e.code==='42501');
   await db.exec("reset role;select set_config('request.jwt.claim.sub','',false);select set_config('request.jwt.claim.role','',false)");
 });
 const result={passed,captured_at:metadata.captured_at,metadata_sha256:hash(metadataSource),boundary_metadata_sha256:hash(boundarySource),
   bundle_sha256:manifest.bundle_sha256,storage_origin:storageOrigin,sources:manifest.sources,replay,hosted:false,production_user_data:false,
   claim:'Captured application-schema compatibility only; not hosted Auth/Storage/Edge or Apple acceptance'};
 if(process.argv[5])await writeFile(process.argv[5],JSON.stringify(result,null,2)+'\n');
 console.log(JSON.stringify(result));
}catch(error){console.error('FAIL:',error.message,error.where??'',error.internalQuery??'');process.exitCode=1;}
finally{await db.close();}
