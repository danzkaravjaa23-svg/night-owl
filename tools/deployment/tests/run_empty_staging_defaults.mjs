import {readFile,writeFile,mkdir,lstat,realpath} from 'node:fs/promises';
import path from 'node:path';
import {fileURLToPath,pathToFileURL} from 'node:url';
import {createHash} from 'node:crypto';
import assert from 'node:assert/strict';
// Synthetic in-memory PostgreSQL only. Never connects to a hosted project.
const usage='Usage: node tools/deployment/tests/run_empty_staging_defaults.mjs <absolute-pglite-module-path> [build/receipt.json]';
if(process.argv.length<3||process.argv.length>4||!path.isAbsolute(process.argv[2]))throw new Error(usage);
const modulePath=await realpath(process.argv[2]);
if(!(await lstat(modulePath)).isFile())throw new Error('PGlite module must be an existing file. '+usage);
const {PGlite}=await import(pathToFileURL(modulePath).href);
if(typeof PGlite!=='function')throw new Error('The supplied module does not export PGlite.');
const base=new URL('./',import.meta.url);
const root=fileURLToPath(new URL('../../../',import.meta.url));
let output;
if(process.argv[3]){
 const build=path.join(root,'build');
 output=path.resolve(root,process.argv[3]);
 if(!output.startsWith(build+path.sep)||path.extname(output)!=='.json')throw new Error('Receipt must be a new JSON file under this repository build directory.');
 // Reject symlink components before creating any directory or writing a receipt.
 let candidate=root;
 for(const part of path.relative(root,output).split(path.sep)){
  candidate=path.join(candidate,part);
  try{if((await lstat(candidate)).isSymbolicLink())throw new Error('Receipt path must not contain symlinks.');}
  catch(error){if(error.code!=='ENOENT')throw error;}
 }
 try{await lstat(output);throw new Error('Receipt already exists; choose a new build path.');}
 catch(error){if(error.code!=='ENOENT')throw error;}
}
const install=await readFile(new URL('../harden_empty_staging_defaults.sql',base),'utf8');
const postflight=await readFile(new URL('empty_staging_defaults_postflight.sql',base),'utf8');
const setup=`create role anon; create role authenticated; create role service_role bypassrls; create role supabase_admin;
create schema auth; create schema storage; create schema extensions;
grant usage on schema storage to anon;
create function public.rls_auto_enable() returns void language sql as $$ select null::void $$;
alter default privileges for role postgres in schema public grant truncate,references,trigger,maintain on tables to anon,authenticated,service_role;
alter default privileges for role postgres grant all on sequences to authenticated;
alter default privileges for role postgres grant execute on functions to authenticated;
alter default privileges for role supabase_admin in schema public grant all on tables to anon,authenticated,service_role;
alter default privileges for role supabase_admin in schema public grant execute on functions to anon,authenticated,service_role;`;
const scalar=async(db,sql)=>(await db.query(sql)).rows[0].v;
const defaults=async db=>scalar(db,`select jsonb_agg(jsonb_build_object('owner',defaclrole::regrole::text,'schema',defaclnamespace,'kind',defaclobjtype,'acl',defaclacl) order by defaclrole,defaclnamespace,defaclobjtype) v from pg_default_acl`);
const passed=[];
let db=new PGlite();
try{
 await db.exec(setup);
 await assert.rejects(db.exec(postflight),/Global postgres defaults/); await db.exec('rollback');
 passed.push('postflight rejects implicit global PUBLIC execute and client defaults');
 const managed=await scalar(db,`select jsonb_agg(defaclacl order by defaclobjtype) v from pg_default_acl where defaclrole='supabase_admin'::regrole`);
 const helper=await scalar(db,`select has_function_privilege('anon','public.rls_auto_enable()','execute') v`);
 await db.exec(install); await db.exec(postflight);
 assert.deepEqual(await scalar(db,`select jsonb_agg(defaclacl order by defaclobjtype) v from pg_default_acl where defaclrole='supabase_admin'::regrole`),managed);
 assert.equal(await scalar(db,`select has_function_privilege('anon','public.rls_auto_enable()','execute') v`),helper);
 passed.push('install preserves managed defaults and existing helper permissions');
 await db.exec(`create table public.synthetic(id int); create sequence public.synthetic_seq; create function public.synthetic_fn() returns int language sql as $$ select 1 $$;`);
 for(const role of ['anon','authenticated','service_role']){
  for(const privilege of ['select','insert','update','delete','truncate','references','trigger','maintain']) assert.equal(await scalar(db,`select has_table_privilege('${role}','public.synthetic','${privilege}') v`),false);
  assert.equal(await scalar(db,`select has_function_privilege('${role}','public.synthetic_fn()','execute') v`),false);
  assert.equal(await scalar(db,`select has_sequence_privilege('${role}','public.synthetic_seq','usage,select,update') v`),false);
 }
 await db.exec(`grant select on public.synthetic to authenticated`);
 assert.equal(await scalar(db,`select has_table_privilege('authenticated','public.synthetic','select') v`),true);
 passed.push('new objects deny inherited clients while explicit grants work');
 const before=await defaults(db);
 await assert.rejects(db.exec(install),/existing application refused/); await db.exec('rollback');
 assert.deepEqual(await defaults(db),before);
 passed.push('nonempty application guard refuses changes');
}finally{await db.close();}
db=new PGlite();
try{
 await db.exec(setup); const before=await defaults(db);
 const corrupted=install.replace('do $preservation$',`alter default privileges for role supabase_admin in schema public revoke all on tables from anon;\ndo $preservation$`);
 await assert.rejects(db.exec(corrupted),/managed default ACLs changed/);await db.exec('rollback');
 assert.deepEqual(await defaults(db),before);
 passed.push('managed-default drift aborts and rolls back all changes');
}finally{await db.close();}
const receipt={scope:'synthetic in-memory PostgreSQL only',passed,hosted_executed:false,production_modified:false,
 install_sha256:createHash('sha256').update(install).digest('hex'),postflight_sha256:createHash('sha256').update(postflight).digest('hex')};
if(output){
 await mkdir(path.dirname(output),{recursive:true});
 await writeFile(output,JSON.stringify(receipt,null,2)+'\n',{flag:'wx'});
}
console.log(JSON.stringify(receipt,null,2));
