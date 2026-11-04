// Isolated in-memory PostgreSQL ONLY. Managed boundaries are synthetic fixtures;
// this executable has no hosted connection or credential argument.
import assert from 'node:assert/strict';
import {readFile,writeFile,mkdir,lstat,realpath} from 'node:fs/promises';
import {fileURLToPath,pathToFileURL} from 'node:url';
import path from 'node:path';
import {createHash} from 'node:crypto';
import {buildHostedStagingBaseline,normalizeAcl,stagingOrigin} from '../hosted_staging_baseline.mjs';

process.on('uncaughtException',error=>{console.error(JSON.stringify({error:error.message,code:error.code,where:error.where}));process.exit(1);});
const usage='Usage: node tools/deployment/tests/run_hosted_staging_baseline.mjs <absolute-pglite-module-path> <schema.json> <platform.json> <complement.json> <target-complement.json> [new-build-receipt.json]';
if(process.argv.length<7||process.argv.length>8||!path.isAbsolute(process.argv[2]))throw new Error(usage);
const modulePath=await realpath(process.argv[2]);
if(!(await lstat(modulePath)).isFile())throw new Error(usage);
const {PGlite}=await import(pathToFileURL(modulePath).href);
const {pg_trgm}=await import(new URL('./contrib/pg_trgm.js',pathToFileURL(modulePath)).href);
const root=fileURLToPath(new URL('../../../',import.meta.url));
let output;
if(process.argv[7]){
 output=path.resolve(process.argv[7]);
 if(!output.startsWith(path.join(root,'build')+path.sep)||!output.endsWith('.json'))throw new Error('Receipt must be a new JSON file inside repository build');
 let component=root;for(const part of path.relative(root,output).split(path.sep)){component=path.join(component,part);try{if((await lstat(component)).isSymbolicLink())throw new Error('Receipt path contains symlink');}catch(e){if(e.code!=='ENOENT')throw e;}}
 try{await lstat(output);throw new Error('Receipt exists; use a new path');}catch(e){if(e.code!=='ENOENT')throw e;}
}
const [schemaText,platformText,complementText,targetText]=await Promise.all(process.argv.slice(3,7).map(p=>readFile(p,'utf8')));
const metadata=JSON.parse(schemaText),boundaries=JSON.parse(platformText),complement=JSON.parse(complementText),targetComplement=JSON.parse(targetText);
const sha=s=>createHash('sha256').update(s).digest('hex');
const sourceHashes={schema:sha(schemaText),platform:sha(platformText),complement:sha(complementText),target:sha(targetText)};
const input={metadata,boundaries,complement,targetComplement,sourceHashes};
const result=await buildHostedStagingBaseline(input);
// PGlite is compiled without the hosted ICU locale. Test the ORIGINAL guard's
// refusal separately, then substitute ONLY this guard in the in-memory fixture.
// Source pins, all DDL/grants and008/009 remain unchanged. Record both hashes.
const localeGuard=/do \$verify_database_locale\$[\s\S]*?end \$verify_database_locale\$;/g;
assert.equal([...result.sql.matchAll(localeGuard)].length,1);
const fixtureResult=Object.fromEntries(Object.entries(result).map(([key,value])=>[key,
 typeof value==='string'?value.replace(localeGuard,'-- TEST ONLY: hosted ICU locale guard independently checked; PGlite fixture substitution.'):value]));
const harden=await readFile(new URL('../harden_empty_staging_defaults.sql',import.meta.url),'utf8');
const q=s=>'"'+s.replaceAll('"','""')+'"';
const name=s=>s.split('.').map(q).join('.');
const scalar=async(db,sql)=>(await db.query(sql)).rows[0].v;
const passed=[];
const check=async(label,fn)=>{await fn();passed.push(label);console.log('PASS: '+label);};

async function fixture(){
 const db=new PGlite({extensions:{pg_trgm}});
 await db.exec(`create role anon;create role authenticated;create role service_role bypassrls;
 create role supabase_admin;create role supabase_auth_admin;create role supabase_storage_admin;
 create schema auth authorization supabase_auth_admin;create schema storage authorization supabase_storage_admin;create schema extensions;
 revoke create on schema public from public;grant usage on schema public,auth,storage,extensions to anon,authenticated,service_role;
 create type storage.buckettype as enum('STANDARD','ANALYTICS','VECTOR');
 create function public.rls_auto_enable() returns event_trigger language plpgsql as $$ declare r record;begin
 for r in select * from pg_event_trigger_ddl_commands() where command_tag='CREATE TABLE' and schema_name in ('public','admin_private') loop
 execute format('alter table %s enable row level security',r.object_identity);end loop;end $$;
 create event trigger ensure_rls on ddl_command_end when tag in ('CREATE TABLE') execute function public.rls_auto_enable();
 create publication supabase_realtime;
 alter default privileges for role postgres in schema public grant truncate,references,trigger,maintain on tables to anon,authenticated,service_role;
 alter default privileges for role supabase_admin in schema public grant all on tables to anon,authenticated,service_role;
 alter default privileges for role supabase_admin in schema public grant execute on functions to anon,authenticated,service_role;`);
 const managed=metadata.relations.filter(r=>['auth.users','auth.identities','storage.buckets','storage.objects'].includes(r.name));
 for(const r of managed){
  const columns=r.columns.map(c=>`${q(c.name)} ${c.type}${c.generated?' generated always as ('+c.default+') stored':c.default?' default '+c.default:''}${c.not_null?' not null':''}`);
  await db.exec(`create table ${name(r.name)}(${columns.join(',')});alter table ${name(r.name)} enable row level security;`);
 }
 for(const foreign of [false,true])for(const r of managed)for(const c of r.constraints??[]){
  if(c.definition.startsWith('FOREIGN KEY')!==foreign)continue;
  await db.exec(`alter table ${name(r.name)} add constraint ${q(c.name)} ${c.definition}`);
 }
 for(const f of boundaries.functions)await db.exec(f.definition);
 // Existing native objects are deliberately left in place by the initializer.
 await db.exec(`create function storage.fixture_native_guard() returns trigger language plpgsql as $$begin if tg_op='DELETE' then return old;else return new;end if;end$$;
 create trigger fixture_native_bucket before insert or update on storage.buckets for each row execute function storage.fixture_native_guard();
 create trigger fixture_native_object before update on storage.objects for each row execute function storage.fixture_native_guard();
 grant all on storage.objects to anon,authenticated,service_role;
 grant all on storage.buckets to service_role;
 grant all on auth.users,auth.identities to service_role;`);
 await db.exec(harden);
 return db;
}
const owner='e1000000-0000-0000-0000-000000000001',other='e1000000-0000-0000-0000-000000000002',admin='e1000000-0000-0000-0000-000000000003';
const login=(db,id,role='authenticated')=>db.exec(`reset role;select set_config('request.jwt.claim.sub','${id??''}',false);select set_config('request.jwt.claim.role','${role}',false);set role ${role}`);
const logout=db=>db.exec("reset role;select set_config('request.jwt.claim.sub','',false);select set_config('request.jwt.claim.role','',false)");
const platformProof=db=>scalar(db,`select jsonb_build_object('roles',(select jsonb_agg(jsonb_build_array(oid,rolname,rolsuper,rolbypassrls) order by oid) from pg_roles),'defaults',(select jsonb_agg(to_jsonb(d) order by oid) from pg_default_acl d),'native',(select jsonb_agg(jsonb_build_array(t.oid,pg_get_triggerdef(t.oid),t.tgenabled) order by t.oid) from pg_trigger t join pg_proc p on p.oid=t.tgfoid join pg_namespace n on n.oid=p.pronamespace where n.nspname='storage'),'helper',(select md5(pg_get_functiondef('public.rls_auto_enable()'::regprocedure)))) v`);

await check('source ACL normalization preserves EXECUTE and column distinctions while removing client Dxtm and grant options',async()=>{
 const acl=normalizeAcl(['postgres=arwdDxtm/postgres','anon=arwdDxtm/postgres','authenticated=a*w*x*/postgres','service_role=arwdDxtm/postgres'],'table');
 assert.deepEqual(acl.filter(a=>a.role==='anon').map(a=>a.privilege),['INSERT','SELECT','UPDATE','DELETE']);
 assert.ok(acl.filter(a=>a.role==='authenticated').every(a=>!a.grantable&&['INSERT','UPDATE'].includes(a.privilege)));
 assert.equal(acl.filter(a=>a.role==='service_role').length,8);
 assert.ok(normalizeAcl(null,'function').some(a=>a.role==='public'&&a.privilege==='EXECUTE'));
 assert.deepEqual(normalizeAcl(['authenticated=wx/postgres'],'column'),[{role:'authenticated',privilege:'UPDATE',grantable:false}]);
});
await check('incomplete metadata and unreviewed boundaries fail before SQL generation',async()=>{
 for(const bad of [undefined,{...complement,app_buckets:[]},{...complement,column_collations:[]},{...complement,app_replica_identity:[]},{...complement,functions:[...complement.functions,{schema_name:'admin_private'}]}])await assert.rejects(buildHostedStagingBaseline({...input,complement:bad}),/Unreviewed metadata capture/);
 await assert.rejects(buildHostedStagingBaseline({...input,metadata:{...metadata,functions:metadata.functions.slice(1)}}),/Unreviewed metadata capture/);
});
await check('changed executable metadata and altered target locale cannot bypass reviewed input pins',async()=>{
 const changed=structuredClone(metadata);
 changed.functions[0].definition+='; COMMIT; CREATE TABLE public.unreviewed(id integer);';
 changed.functions[0].definition_md5=createHash('md5').update(changed.functions[0].definition).digest('hex');
 await assert.rejects(buildHostedStagingBaseline({...input,metadata:changed}),/Unreviewed metadata capture/);
 await assert.rejects(buildHostedStagingBaseline({...input,sourceHashes:{...sourceHashes,schema:'0'.repeat(64)}}),/Unreviewed metadata capture/);
 await assert.rejects(buildHostedStagingBaseline({...input,targetComplement:{...targetComplement,database:{...targetComplement.database,locale:'C'}}}),/Unreviewed metadata capture/);
 assert.equal(result.manifest.locale.source_and_verified_target_equal,true);
 assert.equal(result.manifest.target_managed_storage_trigger_count,11);
});
let db=await fixture();
try{
 await check('unmodified live locale guard refuses incompatible database before any app DDL',async()=>{
  await assert.rejects(db.exec(result.sql),/Live target database locale differs/);await db.exec('rollback');
  assert.equal(await scalar(db,"select to_regclass('public.profiles') is null v"),true);
  assert.equal(await scalar(db,'select count(*)::int v from storage.buckets'),0);
 });
 await check('complete baseline installs under hardened defaults with dependency order and exact normalized postflight',async()=>{
  const before=await platformProof(db);
  await db.exec(fixtureResult.preflight);await db.exec(fixtureResult.baselineSql);await db.exec(fixtureResult.baselinePostflight);
  assert.deepEqual(await platformProof(db),before);
  assert.equal(await scalar(db,"select count(*)::int v from pg_constraint c join pg_class t on t.oid=c.conrelid join pg_namespace n on n.oid=t.relnamespace where n.nspname='public' and c.contype='f'"),69);
  assert.equal(await scalar(db,"select count(*)::int v from storage.buckets where public"),0);
 });
 await check('least-privilege grants retain real client read/write/column behavior',async()=>{
  for(const role of ['anon','authenticated'])for(const p of ['truncate','references','trigger','maintain'])assert.equal(await scalar(db,`select has_table_privilege('${role}','public.posts','${p}') v`),false);
  assert.equal(await scalar(db,"select has_table_privilege('authenticated','public.posts','insert') v"),true);
  assert.equal(await scalar(db,"select has_table_privilege('authenticated','public.messages','update') v"),false);
  assert.equal(await scalar(db,"select has_column_privilege('authenticated','public.messages','is_read','update') v"),true);
  assert.equal(await scalar(db,"select has_column_privilege('authenticated','public.messages','body','update') v"),false);
  assert.equal(await scalar(db,"select has_function_privilege('anon','public.admin_console_action(text,uuid,text,uuid)','execute') v"),false);
 });
 await check('repeat/occupied-target installation refuses changes',async()=>{
  const before=await platformProof(db);
  await assert.rejects(db.exec(fixtureResult.sql),/existing application refused/);await db.exec('rollback');
  assert.deepEqual(await platformProof(db),before);
 });
}finally{await db.close();}
db=await fixture();
try{
 await check('combined baseline plus008009 installs atomically with only the documented ICU fixture substitution',async()=>{
  const before=await platformProof(db);
  await db.exec(fixtureResult.sql);await db.exec(fixtureResult.postflight);
  assert.deepEqual(await platformProof(db),before);
  assert.equal(await scalar(db,"select storage_origin v from admin_private.ugc_media_config where singleton"),stagingOrigin);
 });
 await check('synthetic Auth profile trigger and pending photo/video isolation work under exact grants',async()=>{
  for(const [id,username] of [[owner,'staging_owner'],[other,'staging_other'],[admin,'staging_admin']])await db.query('insert into auth.users(id,email,raw_user_meta_data) values($1,$2,$3::jsonb)',[id,username+'@example.invalid',JSON.stringify({username})]);
  assert.equal(await scalar(db,'select count(*)::int v from profiles'),3);
  await db.query('update public.profiles set is_admin=true where id=$1',[admin]);
  await login(db,owner);
  await db.query('insert into storage.objects(bucket_id,name,owner_id) values($1,$2,$3)',['posts',owner+'/photo.jpg',owner]);
  await db.query('insert into storage.objects(bucket_id,name,owner_id) values($1,$2,$3)',['stories',owner+'/video.mp4',owner]);
  const post=(await db.query('insert into public.posts(user_id,caption,media_url) values($1,$2,$3) returning id,moderation_status,moderation_version',[owner,'Synthetic photo',stagingOrigin+'/storage/v1/object/public/posts/'+owner+'/photo.jpg'])).rows[0];
  const story=(await db.query('insert into public.stories(user_id,media_url,media_type) values($1,$2,$3) returning id,moderation_status,moderation_version',[owner,stagingOrigin+'/storage/v1/object/public/stories/'+owner+'/video.mp4','video'])).rows[0];
  assert.equal(post.moderation_status,'pending');assert.equal(story.moderation_status,'pending');
  await login(db,other);
  assert.equal(await scalar(db,'select count(*)::int v from posts'),0);assert.equal(await scalar(db,'select count(*)::int v from stories'),0);
  assert.equal(await scalar(db,'select count(*)::int v from storage.objects'),0);
  await login(db,admin);
  await db.query("select public.admin_console_review('post',$1,$2,'approved','Synthetic staging fixture')",[post.id,post.moderation_version]);
  await db.query("select public.admin_console_review('story',$1,$2,'approved','Synthetic staging fixture')",[story.id,story.moderation_version]);
  await login(db,other);
  assert.equal(await scalar(db,'select count(*)::int v from posts'),1);assert.equal(await scalar(db,'select count(*)::int v from stories'),1);
  assert.equal(await scalar(db,'select count(*)::int v from storage.objects'),2);
  await login(db,owner);
  await assert.rejects(db.query('update storage.objects set metadata=$1 where bucket_id=$2 and name=$3',[{},'posts',owner+'/photo.jpg']),e=>e.code==='42501');
  await assert.rejects(db.query('delete from storage.objects where bucket_id=$1 and name=$2',['stories',owner+'/video.mp4']),e=>e.code==='42501');
  await logout(db);await db.exec(fixtureResult.postflight);
 });
}finally{await db.close();}
db=await fixture();
try{
 await check('unexpected managed metadata change aborts and rolls back all app DDL',async()=>{
  const before=await platformProof(db);
  const corrupted=fixtureResult.sql.replace('do $preserve_platform$',`alter default privileges for role supabase_admin in schema public revoke all on tables from anon;\ndo $preserve_platform$`);
  await assert.rejects(db.exec(corrupted),/Managed platform metadata changed/);await db.exec('rollback');
  assert.deepEqual(await platformProof(db),before);assert.equal(await scalar(db,"select to_regclass('public.profiles') is null v"),true);
  assert.equal(await scalar(db,'select count(*)::int v from storage.buckets'),0);
 });
 await check('existing Auth account fails empty-target preflight without creating app objects',async()=>{
  await db.query('insert into auth.users(id,email) values($1,$2)',[owner,'existing@example.invalid']);
  await assert.rejects(db.exec(fixtureResult.sql),/existing records refused/);await db.exec('rollback');
  assert.equal(await scalar(db,"select to_regclass('public.profiles') is null v"),true);
 });
}finally{await db.close();}
const receipt={format:'night-owl-hosted-staging-baseline-test-v1',passed,source_sha256:sourceHashes,bundle_sha256:result.manifest.bundle_sha256,backend_bundle_sha256:result.manifest.backend_bundle_sha256,
 fixture_sql_sha256:sha(fixtureResult.sql),fixture_substitution:{only:'verify_database_locale assertion block',reason:'PGlite does not provide the hosted ICU en-US locale',original_guard_rejection_tested:true,ddl_and_acl_substitutions:false},
 hosted_executed:false,production_modified:false,source_user_rows:false,counts:result.manifest.counts,
 limits:['In-memory PGlite only; no hosted Auth, Storage HTTP bytes or Realtime delivery tested','Managed native service trigger behavior is a synthetic boundary fixture','Default collation parity is proved by pinned source/target metadata, not PGlite locale tests','Hosted postgres ownership/service permissions and provider versions require actual staging acceptance']};
if(output){await mkdir(path.dirname(output),{recursive:true});await writeFile(output,JSON.stringify(receipt,null,2)+'\n',{flag:'wx'});}
console.log(JSON.stringify(receipt,null,2));
