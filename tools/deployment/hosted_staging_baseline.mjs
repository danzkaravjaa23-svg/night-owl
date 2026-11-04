// Offline, metadata-only preparation for the one reviewed EMPTY hosted project.
// Never connects, reads credentials/user rows, runs SQL, or replaces Auth/Storage.
import {createHash} from 'node:crypto';
import {readFile,writeFile,mkdir,lstat} from 'node:fs/promises';
import {fileURLToPath} from 'node:url';
import path from 'node:path';
import {buildStoreBackendRelease,transactionBody} from './store_backend_release.mjs';

export const stagingProject='sreojqqqhdzkfsrbvlpl';
export const stagingOrigin=`https://${stagingProject}.supabase.co`;
const root=fileURLToPath(new URL('../../',import.meta.url));
const sha=value=>createHash('sha256').update(value).digest('hex');
const md5=value=>createHash('md5').update(value).digest('hex');
const q=value=>'"'+String(value).replaceAll('"','""')+'"';
const literal=value=>"'"+String(value).replaceAll("'","''")+"'";
const json=value=>literal(JSON.stringify(value))+'::jsonb';
const identifier=value=>{if(!/^[a-z_][a-z0-9_]*$/.test(value))throw new Error('Unsupported metadata identifier');return value;};
const relationName=value=>value.includes('.')?value:'public.'+value;
const qualified=value=>relationName(value).split('.').map(x=>q(identifier(x))).join('.');
const publicTables=('admin_audit_log blocks checkins collection_places comment_likes comments discovery_activity dm_requests event_features event_rsvps events follow_requests follows group_chats group_members group_messages likes live_comments live_streams messages notes notifications pilot_content pilot_creators pilot_participants pilot_venues place_collections posts profiles reports saved_posts stories story_likes story_views venue_catalog venue_reviews venue_saves venues').split(' ');
const appNames=new Set([...publicTables.map(n=>'public.'+n),'admin_private.action_context']);
const clientRoles=new Set(['public','anon','authenticated']);
const allGrantees=['public','anon','authenticated','service_role','postgres'];
const privilege={r:'SELECT',a:'INSERT',w:'UPDATE',d:'DELETE',D:'TRUNCATE',x:'REFERENCES',t:'TRIGGER',m:'MAINTAIN',X:'EXECUTE',U:'USAGE',C:'CREATE'};
const roleSql=role=>role==='public'?'public':q(identifier(role));
// This is a one-project reviewed initializer, not a general SQL import tool.
// Both byte provenance and parsed content are pinned: a supplied MD5 beside a
// function body is not sufficient to trust arbitrary executable metadata.
const reviewedMetadata={
 schema:{bytes:'cbe81a74e1da4528742b0c45daca665ddc27d286a9f97d9aebbb22f67820f384',parsed:'653d072dd87d16121e424ae0afc256f0662d8da8d5edf7c8deebb5fc281c5c59'},
 platform:{bytes:'ac05b0ed1fcbc024084b5ca0bfb93ff592987469611e171029a0b7c7ac179160',parsed:'4d5d0e97e08fa7fb643e5ab8818a6b5617865d92afb1a9d7110266f6c0c7a063'},
 complement:{bytes:'13f09f01d0e0d26ffa6728ac55129af35ea021fece920e13881dd7423d4d78dc',parsed:'de8dadff80d0c7f6e3259a55b1c57b437311c2def565d00efeac9f72a442ed17'},
 target:{bytes:'32093be3f2179e03ddc11d323e0aa67ecc38a8034595daed276ba3c459405d05',parsed:'80ada72945c4b7a7ed93ae2c7f5b75dd2a7d74079a884903daf12d7e886ef191'},
};
function verifyReviewedMetadata(inputs,hashes){
 for(const [kind,pin] of Object.entries(reviewedMetadata)){
  if(hashes[kind]!==pin.bytes||inputs[kind]===undefined||sha(JSON.stringify(inputs[kind]))!==pin.parsed)throw new Error('Unreviewed metadata capture; refresh requires source review and new pins');
 }
 const source=inputs.complement.database,target=inputs.target.database;
 const localeFields=['encoding','locale_provider','lc_collate','lc_ctype','locale','icu_rules','recorded_collation_version'];
 if(localeFields.some(field=>source?.[field]!==target?.[field]))throw new Error('Source and hosted target database locale differ');
 if(inputs.target.format!=='night-owl-hosted-metadata-complement-v1'||inputs.target.app_replica_identity?.length!==0||inputs.target.app_buckets?.length!==0)throw new Error('Reviewed target is not empty');
 const targetFunctions=inputs.target.functions.filter(f=>!f.extension_name);
 if(targetFunctions.length!==1||targetFunctions[0].schema_name!=='public'||targetFunctions[0].name!=='rls_auto_enable')throw new Error('Unexpected target helper inventory');
}

// Explicitly normalize the legacy client grants; do not inherit target defaults.
// Null ACL means PostgreSQL's built-in owner (+ PUBLIC EXECUTE for functions).
export function normalizeAcl(list,kind,owner='postgres'){
 if(owner!=='postgres')throw new Error('Unexpected application owner');
 const source=list??[`${owner}=${kind==='function'?'X':kind==='schema'?'UC':'arwdDxtm'}/${owner}`,...(kind==='function'?['=X/postgres']:[])];
 const result=[];
 for(const item of source){
  const match=/^([^=]*)=([^/]*)\/([^/]+)$/.exec(item);
  if(!match||!allGrantees.includes(match[1]||'public')||match[3]!=='postgres')throw new Error('Unreviewed application ACL role or grantor');
  const role=match[1]||'public';
  for(let i=0;i<match[2].length;i++){
   const p=privilege[match[2][i]];if(!p)throw new Error('Unsupported ACL privilege');
   let grantable=match[2][i+1]==='*';if(grantable)i++;
   if(clientRoles.has(role)){
    if((kind==='table'||kind==='column')&&!['SELECT','INSERT','UPDATE','DELETE'].includes(p))continue;
    grantable=false;
   }
   if(kind==='column'&&!['SELECT','INSERT','UPDATE','REFERENCES'].includes(p))throw new Error('Unsupported column privilege');
   if(kind==='function'&&p!=='EXECUTE')throw new Error('Unsupported routine privilege');
   result.push({role,privilege:p,grantable});
  }
 }
 return result;
}
function grants(kind,target,acl,column){
 const revoke=column?`revoke all (${q(column)}) on table ${target} from ${allGrantees.map(roleSql).join(',')};`:
   `revoke all on ${kind} ${target} from ${allGrantees.map(roleSql).join(',')};`;
 return [revoke,...acl.map(a=>`grant ${a.privilege}${column?' ('+q(column)+')':''} on ${kind==='column'?'table':kind} ${target} to ${roleSql(a.role)}${a.grantable?' with grant option':''};`)].join('\n');
}
function functionSignature(value){
 if(!/^(?:public\.)?[a-z_][a-z0-9_]*\((?:[a-z0-9_\[\] ,]*)\)$/.test(value))throw new Error('Unsupported function signature');
 return value.startsWith('public.')?value:'public.'+value;
}
const equalSet=(a,b)=>a.length===b.length&&a.every(v=>b.includes(v));

function validateInput(metadata,boundaries,complement){
 if(metadata?.scope!=='metadata-only; no application/Auth/Storage object rows'||!Array.isArray(metadata.relations)||!Array.isArray(metadata.functions))throw new Error('Required bounded source schema metadata missing');
 if(!Array.isArray(boundaries?.roles)||!Array.isArray(boundaries?.functions))throw new Error('Required source platform boundary metadata missing');
 if(complement?.format!=='night-owl-hosted-metadata-complement-v1')throw new Error('Required source metadata complement missing');
 const apps=metadata.relations.filter(r=>appNames.has(relationName(r.name)));
 const unexpected=metadata.relations.filter(r=>!appNames.has(relationName(r.name))&&!['auth.users','auth.identities','storage.objects','storage.buckets'].includes(r.name));
 if(apps.length!==39||new Set(apps.map(r=>relationName(r.name))).size!==39||unexpected.length||metadata.functions.length!==78)throw new Error('Source inventory differs from reviewed 39-table / 78-function baseline');
 for(const r of apps){
  if(r.kind!=='r'||r.owner!=='postgres'||!Array.isArray(r.columns)||!r.columns.length)throw new Error('Unsupported application relation metadata');
  if(r.name!=='admin_private.action_context'&&!r.rls)throw new Error('Public application table is missing RLS');
  for(const c of r.columns){
   identifier(c.name);
   if(c.identity||c.generated||!['bigint','boolean','date','double precision','integer','numeric(2,1)','text','text[]','timestamp with time zone','uuid','uuid[]'].includes(c.type))throw new Error('Unreviewed application column type/generation');
  }
 }
 const signatures=new Set();
 for(const f of metadata.functions){
  const sig=functionSignature(f.signature);if(signatures.has(sig)||f.owner!=='postgres'||!f.definition.startsWith('CREATE OR REPLACE FUNCTION public.')||md5(f.definition)!==f.definition_md5)throw new Error('Invalid or changed captured function definition');
  signatures.add(sig);
  if((f.config??[]).some(v=>!v.startsWith('search_path=')))throw new Error('Unreviewed routine setting; do not embed configuration values');
 }
 if((complement.functions??[]).some(f=>['admin_private','account_private'].includes(f.schema_name)))throw new Error('Private routines need a separate dependency review');
 const appInventory=(complement.functions??[]).filter(f=>f.schema_name==='public'&&!f.extension_name);
 if(appInventory.length!==78||appInventory.some(f=>!metadata.functions.some(m=>functionSignature(m.signature).startsWith('public.'+f.name+'('))))throw new Error('Source complement routine inventory does not match main capture');
 if(!Array.isArray(complement.app_replica_identity)||complement.app_replica_identity.length!==39)throw new Error('Complete application replica-identity metadata required');
 for(const r of complement.app_replica_identity){
  if(!appNames.has(r.schema_name+'.'+r.relation_name)||r.kind!=='r'||r.persistence!=='p'||!['d','f','n','i'].includes(r.replica_identity))throw new Error('Unsupported relation persistence or replica identity');
  if(r.replica_identity==='i')identifier(r.identity_index);
 }
 for(const c of complement.column_collations??[]){
  if(!appNames.has(c.schema_name+'.'+c.relation_name)||c.collation_schema!=='pg_catalog'||c.collation_name!=='default')throw new Error('Non-default application collation requires explicit review');
 }
 const collatable=apps.flatMap(r=>r.columns.filter(c=>['text','text[]'].includes(c.type)).map(c=>relationName(r.name)+'.'+c.name));
 const captured=(complement.column_collations??[]).map(c=>c.schema_name+'.'+c.relation_name+'.'+c.column_name);
 if(!equalSet(collatable,captured))throw new Error('Application column-collation inventory incomplete');
 const buckets=complement.app_buckets;
 if(!Array.isArray(buckets)||!equalSet(buckets.map(b=>b.id),['avatars','posts','stories','venues']))throw new Error('All four source bucket configurations required');
 for(const b of buckets){
  if(b.name!==b.id||b.type!=='STANDARD'||!(b.file_size_limit===null||(Number.isSafeInteger(b.file_size_limit)&&b.file_size_limit>0))||!(b.allowed_mime_types===null||(Array.isArray(b.allowed_mime_types)&&b.allowed_mime_types.every(t=>typeof t==='string'&&t.length<100))))throw new Error('Unreviewed bucket configuration');
 }
 const trgm=(complement.extensions??[]).find(e=>e.name==='pg_trgm');
 if(!trgm||!['public','extensions'].includes(trgm.schema_name)||trgm.version!=='1.6'||!(complement.trigram_opclasses??[]).some(o=>o.name==='gin_trgm_ops'&&o.schema_name===trgm.schema_name&&o.extension_name==='pg_trgm'))throw new Error('Expected reviewed pg_trgm 1.6 schema');
 const publication=(complement.publications??[]).find(p=>p.name==='supabase_realtime');
 if(!publication||publication.all_tables||publication.publish_via_partition_root||(complement.publication_schemas??[]).some(p=>p.publication==='supabase_realtime'))throw new Error('Realtime requires explicit reviewed table membership');
 const realtime=(complement.publication_explicit_tables??[]).filter(p=>p.publication==='supabase_realtime');
 if(realtime.some(p=>p.schema_name!=='public'||!publicTables.includes(p.table_name)||p.column_positions!==null||p.row_filter!==null))throw new Error('Unreviewed Realtime table, column list or row filter');
 const effective=(complement.publication_effective_tables??[]).filter(p=>p.publication==='supabase_realtime');
 if(!equalSet(realtime.map(p=>p.table_name),effective.map(p=>p.table_name)))throw new Error('Realtime expanded membership differs from explicit tables');
 const storage=metadata.relations.find(r=>r.name==='storage.objects');
 if((storage?.policies??[]).length!==14)throw new Error('Expected 14 source application Storage policies');
 const auth=metadata.relations.find(r=>r.name==='auth.users');
 const authTriggers=(auth?.triggers??[]).filter(t=>t.name==='on_auth_user_created');
 if(authTriggers.length!==1||!/EXECUTE FUNCTION (?:public\.)?handle_new_user\(\)$/.test(authTriggers[0].definition))throw new Error('Expected captured profile-creation trigger');
 return {apps,storage,authTriggers,buckets,publication,realtime,trgm};
}

// Hash unchanged platform metadata by original OIDs. App trigger/policy additions
// cannot mask a mutation of an existing managed object. No record data is hashed.
const platformSnapshot=`select jsonb_build_object(
 'roles',(select jsonb_agg(jsonb_build_array(oid,rolname,rolsuper,rolinherit,rolcreaterole,rolcreatedb,rolcanlogin,rolreplication,rolbypassrls) order by oid) from pg_roles),
 'memberships',(select jsonb_agg(to_jsonb(m) order by roleid,member,grantor) from pg_auth_members m),
 'defaults',(select jsonb_agg(to_jsonb(d) order by oid) from pg_default_acl d),
 'schemas',(select jsonb_agg(jsonb_build_array(oid,nspowner,nspacl) order by oid) from pg_namespace where nspname in ('public','auth','storage','extensions')),
 'relations',(select jsonb_agg(jsonb_build_array(c.oid,c.relowner,c.relkind,c.relacl,c.relrowsecurity,c.relforcerowsecurity,c.relreplident) order by c.oid) from pg_class c join pg_namespace n on n.oid=c.relnamespace where n.nspname in ('auth','storage')),
 'columns',(select jsonb_agg(to_jsonb(a) order by a.attrelid,a.attnum) from pg_attribute a join pg_class c on c.oid=a.attrelid join pg_namespace n on n.oid=c.relnamespace where n.nspname in ('auth','storage') and a.attnum>0),
 'constraints',(select jsonb_agg(jsonb_build_array(x.oid,pg_get_constraintdef(x.oid),x.convalidated) order by x.oid) from pg_constraint x join pg_class c on c.oid=x.conrelid join pg_namespace n on n.oid=c.relnamespace where n.nspname in ('auth','storage')),
 'indexes',(select jsonb_agg(jsonb_build_array(i.indexrelid,pg_get_indexdef(i.indexrelid)) order by i.indexrelid) from pg_index i join pg_class c on c.oid=i.indrelid join pg_namespace n on n.oid=c.relnamespace where n.nspname in ('auth','storage')),
 'functions',(select jsonb_agg(jsonb_build_array(p.oid,md5(pg_get_functiondef(p.oid)),p.proowner,p.proacl) order by p.oid) from pg_proc p join pg_namespace n on n.oid=p.pronamespace where (n.nspname in ('auth','storage') or (n.nspname='public' and p.proname='rls_auto_enable')) and p.prokind in ('f','p')),
 'triggers',(select jsonb_agg(jsonb_build_array(t.oid,pg_get_triggerdef(t.oid),t.tgenabled) order by t.oid) from pg_trigger t join pg_class c on c.oid=t.tgrelid join pg_namespace n on n.oid=c.relnamespace where n.nspname in ('auth','storage') and not t.tgisinternal and t.oid=any(string_to_array(current_setting('nightowl.platform_trigger_oids'),',')::oid[])),
 'policies',(select jsonb_agg(to_jsonb(p) order by p.oid) from pg_policy p where p.oid=any(string_to_array(current_setting('nightowl.platform_policy_oids'),',')::oid[])),
 'events',(select jsonb_agg(to_jsonb(e) order by oid) from pg_event_trigger e),
 'publications',(select jsonb_agg(to_jsonb(p) order by oid) from pg_publication p),
 'publication_namespaces',(select jsonb_agg(to_jsonb(p) order by oid) from pg_publication_namespace p),
 'publication_existing_tables',(select jsonb_agg(to_jsonb(p) order by oid) from pg_publication_rel p where p.oid=any(string_to_array(current_setting('nightowl.platform_publication_oids'),',')::oid[]))
)`;
const preserveBefore=`do $capture_platform$ declare snapshot jsonb; begin
 perform set_config('nightowl.platform_trigger_oids',coalesce((select string_agg(t.oid::text,',') from pg_trigger t join pg_class c on c.oid=t.tgrelid join pg_namespace n on n.oid=c.relnamespace where n.nspname in ('auth','storage') and not t.tgisinternal),''),true);
 perform set_config('nightowl.platform_policy_oids',coalesce((select string_agg(p.oid::text,',') from pg_policy p join pg_class c on c.oid=p.polrelid join pg_namespace n on n.oid=c.relnamespace where n.nspname in ('auth','storage')),''),true);
 perform set_config('nightowl.platform_publication_oids',coalesce((select string_agg(oid::text,',') from pg_publication_rel),''),true);
 ${platformSnapshot} into snapshot;
 perform set_config('nightowl.platform_metadata_before',md5(snapshot::text),true);
end $capture_platform$;`;
const preserveAfter=`do $preserve_platform$ declare snapshot jsonb; begin
 ${platformSnapshot} into snapshot;
 if md5(snapshot::text) is distinct from current_setting('nightowl.platform_metadata_before') then raise exception 'Managed platform metadata changed; entire staging install must roll back'; end if;
end $preserve_platform$;`;

const aclQuery=(kind,oid)=>kind==='column'?`select coalesce(jsonb_agg(jsonb_build_object('role',case when a.grantee=0 then 'public' else pg_get_userbyid(a.grantee) end,'privilege',a.privilege_type,'grantable',a.is_grantable)),'[]'::jsonb) from aclexplode(${oid}) a`:
 `select coalesce(jsonb_agg(jsonb_build_object('role',case when a.grantee=0 then 'public' else pg_get_userbyid(a.grantee) end,'privilege',a.privilege_type,'grantable',a.is_grantable)),'[]'::jsonb) from ${kind==='function'?'pg_proc':'pg_class'} o cross join lateral aclexplode(coalesce(o.${kind==='function'?'proacl':'relacl'},acldefault('${kind==='function'?'f':'r'}',o.${kind==='function'?'proowner':'relowner'}))) a where o.oid=${oid}`;

function baselineAssertions(expected,functions,policies,triggers,buckets,realtime){
 return `do $verify_baseline$
declare r jsonb; c jsonb; f jsonb; p jsonb; t jsonb; actual jsonb; object_id oid; column_acl aclitem[]; wanted jsonb;
begin
 if (select count(*) from pg_class c join pg_namespace n on n.oid=c.relnamespace where n.nspname in ('public','admin_private') and c.relkind in ('r','p','v','m','S','f') and not exists(select 1 from pg_depend d where d.classid='pg_class'::regclass and d.objid=c.oid and d.deptype='e'))<>39 then raise exception 'Baseline application relation count mismatch'; end if;
 for r in select value from jsonb_array_elements(${json(expected)}) loop
  object_id:=to_regclass(r->>'name');
  if object_id is null or not exists(select 1 from pg_class where oid=object_id and relkind='r' and relowner='postgres'::regrole and relrowsecurity=(r->>'rls')::boolean and relforcerowsecurity=(r->>'force_rls')::boolean and relreplident=(r->>'replica_identity')::"char") then raise exception 'Baseline relation contract mismatch'; end if;
  if (select count(*) from pg_attribute where attrelid=object_id and attnum>0 and not attisdropped)<>jsonb_array_length(r->'columns') then raise exception 'Baseline column count mismatch'; end if;
  for c in select value from jsonb_array_elements(r->'columns') loop
   select jsonb_build_object('type',format_type(a.atttypid,a.atttypmod),'not_null',a.attnotnull,'default',pg_get_expr(d.adbin,d.adrelid),'identity',a.attidentity,'generated',a.attgenerated) into actual from pg_attribute a left join pg_attrdef d on d.adrelid=a.attrelid and d.adnum=a.attnum where a.attrelid=object_id and a.attname=c->>'name' and not a.attisdropped;
   if actual is distinct from c->'shape' then raise exception 'Baseline column contract mismatch'; end if;
   select attacl into column_acl from pg_attribute where attrelid=object_id and attname=c->>'name';
   ${aclQuery('column','column_acl')} into actual;
   wanted:=c->'acl'; if not(actual @> wanted and wanted @> actual) then raise exception 'Baseline column ACL mismatch'; end if;
  end loop;
  ${aclQuery('table','object_id')} into actual;
  wanted:=r->'acl'; if not(actual @> wanted and wanted @> actual) then raise exception 'Baseline table ACL mismatch'; end if;
  select coalesce(jsonb_agg(jsonb_build_object('name',conname,'definition',pg_get_constraintdef(oid),'validated',convalidated)),'[]'::jsonb) into actual from pg_constraint where conrelid=object_id and contype<>'n';
  wanted:=r->'constraints'; if not(actual @> wanted and wanted @> actual) then raise exception 'Baseline constraint mismatch'; end if;
  select coalesce(jsonb_agg(pg_get_indexdef(indexrelid)),'[]'::jsonb) into actual from pg_index where indrelid=object_id;
  wanted:=r->'indexes'; if not(actual @> wanted and wanted @> actual) then raise exception 'Baseline index mismatch'; end if;
 end loop;
 for f in select value from jsonb_array_elements(${json(functions)}) loop
  object_id:=to_regprocedure(f->>'signature');
  if object_id is null or not exists(select 1 from pg_proc where oid=object_id and proowner='postgres'::regrole and prosecdef=(f->>'security_definer')::boolean and md5(pg_get_functiondef(oid))=f->>'definition_md5') then raise exception 'Baseline function contract mismatch'; end if;
  ${aclQuery('function','object_id')} into actual;
  wanted:=f->'acl'; if not(actual @> wanted and wanted @> actual) then raise exception 'Baseline function ACL mismatch'; end if;
 end loop;
 for p in select value from jsonb_array_elements(${json(policies)}) loop
  select jsonb_build_object('permissive',polpermissive,'command',polcmd,'using',pg_get_expr(polqual,polrelid),'check',pg_get_expr(polwithcheck,polrelid),'roles',(select jsonb_agg(case when x=0 then 'public' else pg_get_userbyid(x) end order by x) from unnest(polroles) x)) into actual from pg_policy where polrelid=to_regclass(p->>'table') and polname=p->>'name';
  wanted:=p->'shape'; if actual is null or (actual-'roles') is distinct from (wanted-'roles') or not((actual->'roles') @> (wanted->'roles') and (wanted->'roles') @> (actual->'roles')) then raise exception 'Baseline policy contract mismatch'; end if;
 end loop;
 if (select count(*) from pg_policy p join pg_class c on c.oid=p.polrelid join pg_namespace n on n.oid=c.relnamespace where n.nspname in ('public','admin_private'))<>155 then raise exception 'Baseline application policy count mismatch'; end if;
 for t in select value from jsonb_array_elements(${json(triggers)}) loop
  if not exists(select 1 from pg_trigger where tgrelid=to_regclass(t->>'table') and tgname=t->>'name' and tgenabled=(t->>'enabled')::"char" and pg_get_triggerdef(oid)=t->>'definition') then raise exception 'Baseline trigger contract mismatch'; end if;
 end loop;
 select coalesce(jsonb_agg(jsonb_build_object('id',id,'name',name,'public',public,'file_size_limit',file_size_limit,'allowed_mime_types',allowed_mime_types,'type',type::text)),'[]'::jsonb) into actual from storage.buckets where id in ('avatars','posts','stories','venues');
 wanted:=${json(buckets.map(b=>({...b,public:false})))}; if not(actual @> wanted and wanted @> actual) then raise exception 'Private bucket configuration mismatch'; end if;
 select coalesce(jsonb_agg(c.relname),'[]'::jsonb) into actual from pg_publication_rel pr join pg_publication p on p.oid=pr.prpubid join pg_class c on c.oid=pr.prrelid join pg_namespace n on n.oid=c.relnamespace where p.pubname='supabase_realtime' and n.nspname='public';
 wanted:=${json(realtime.map(p=>p.table_name))}; if not(actual @> wanted and wanted @> actual) then raise exception 'Realtime application membership mismatch'; end if;
 if has_schema_privilege('anon','admin_private','USAGE') or has_schema_privilege('authenticated','admin_private','USAGE') then raise exception 'Private application schema exposed'; end if;
end $verify_baseline$;`;
}

export async function buildHostedStagingBaseline({metadata,boundaries,complement,targetComplement,sourceHashes={}}={}){
 verifyReviewedMetadata({schema:metadata,platform:boundaries,complement,target:targetComplement},sourceHashes);
 const {apps,storage,authTriggers,buckets,publication,realtime,trgm}=validateInput(metadata,boundaries,complement);
 const roles=new Map([['0','public'],...boundaries.roles.map(r=>[String(r.oid),r.role])]);
 const policies=[];const triggers=[];const definitions=[];
 const expected=[];
 const defaultsSource=transactionBody(await readFile(new URL('./tests/empty_staging_defaults_postflight.sql',import.meta.url),'utf8'),'empty_staging_defaults_postflight.sql',true);
 // Reuse the assertions, not the earlier standalone "baseline not installed"
 // status row: that row would be misleading in the combined postflight.
 if(!defaultsSource.endsWith('as default_acl_postflight;'))throw new Error('Unexpected default-ACL postflight shape');
 const defaultsBody=defaultsSource.slice(0,defaultsSource.lastIndexOf('\nselect jsonb_build_object(')).trim();
 const localeFields=['encoding','locale_provider','lc_collate','lc_ctype','locale','icu_rules','recorded_collation_version'];
 const expectedLocale=Object.fromEntries(localeFields.map(key=>[key,complement.database[key]]));
 const localeGuard=`do $verify_database_locale$ declare actual jsonb; begin
 select jsonb_build_object('encoding',pg_encoding_to_char(encoding),'locale_provider',datlocprovider,'lc_collate',datcollate,'lc_ctype',datctype,'locale',datlocale,'icu_rules',daticurules,'recorded_collation_version',datcollversion) into actual from pg_database where datname=current_database();
 if actual is distinct from ${json(expectedLocale)} then raise exception 'Live target database locale differs from reviewed source/target metadata'; end if;
end $verify_database_locale$;`;
 const pubChecks=['insert','update','delete','truncate'].map(p=>`pub${p}=${publication['publish_'+p]?'true':'false'}`).join(' and ');
 const managedRequirements=[['auth.users','id','uuid'],['auth.users','raw_user_meta_data','jsonb'],['auth.identities','user_id','uuid'],['auth.identities','provider','text'],['auth.identities','identity_data','jsonb'],['storage.objects','bucket_id','text'],['storage.objects','name','text'],['storage.objects','owner_id','text'],['storage.objects','metadata','jsonb'],['storage.buckets','id','text'],['storage.buckets','public','boolean'],['storage.buckets','allowed_mime_types','text[]'],['storage.buckets','file_size_limit','bigint'],['storage.buckets','type','storage.buckettype']];
 const preflight=`${defaultsBody}
${localeGuard}
do $staging_preflight$ declare boundary jsonb; begin
 if current_user<>'postgres' then raise exception 'Expected staging postgres operator'; end if;
 if to_regnamespace('admin_private') is not null or to_regnamespace('account_private') is not null or exists(select 1 from pg_class c join pg_namespace n on n.oid=c.relnamespace where n.nspname='public' and c.relkind in ('r','p','v','m','S','f') and not exists(select 1 from pg_depend d where d.classid='pg_class'::regclass and d.objid=c.oid and d.deptype='e')) then raise exception 'Expected empty app schema; existing application refused'; end if;
 if exists(select 1 from pg_proc p join pg_namespace n on n.oid=p.pronamespace where n.nspname='public' and p.proname<>'rls_auto_enable' and not exists(select 1 from pg_depend d where d.classid='pg_proc'::regclass and d.objid=p.oid and d.deptype='e')) then raise exception 'Unexpected existing public routine'; end if;
 if exists(select 1 from pg_roles where rolname in ('anon','authenticated') and (rolsuper or rolbypassrls)) or pg_has_role('anon','postgres','USAGE') or pg_has_role('authenticated','postgres','USAGE') or pg_has_role('anon','service_role','USAGE') or pg_has_role('authenticated','service_role','USAGE') then raise exception 'Unsafe client role inheritance'; end if;
 if has_schema_privilege('anon','public','CREATE') or has_schema_privilege('authenticated','public','CREATE') then raise exception 'Client schema CREATE must be disabled'; end if;
 if exists(select 1 from auth.users) or exists(select 1 from storage.objects) or exists(select 1 from storage.buckets) then raise exception 'Expected empty staging Auth/Storage; existing records refused'; end if;
 if exists(select 1 from pg_policy where polrelid in ('storage.objects'::regclass,'storage.buckets'::regclass)) or exists(select 1 from pg_trigger where tgrelid='auth.users'::regclass and tgname='on_auth_user_created') then raise exception 'Unexpected existing application boundary policy/trigger'; end if;
 if exists(select 1 from pg_publication_rel pr join pg_publication p on p.oid=pr.prpubid join pg_class c on c.oid=pr.prrelid join pg_namespace n on n.oid=c.relnamespace where p.pubname='supabase_realtime' and n.nspname='public') or exists(select 1 from pg_publication_namespace pn join pg_publication p on p.oid=pn.pnpubid where p.pubname='supabase_realtime') then raise exception 'Expected empty explicit Realtime app membership'; end if;
 if not exists(select 1 from pg_publication where pubname='supabase_realtime' and not puballtables and not pubviaroot and ${pubChecks}) then raise exception 'Managed Realtime publication settings differ'; end if;
 for boundary in select value from jsonb_array_elements(${json(managedRequirements)}) loop
  if not exists(select 1 from pg_attribute a where a.attrelid=to_regclass(boundary->>0) and a.attname=boundary->>1 and format_type(a.atttypid,a.atttypmod)=boundary->>2 and not a.attisdropped) then raise exception 'Managed Auth/Storage column contract missing'; end if;
 end loop;
 if exists(select 1 from (values ('auth.uid()'),('auth.role()'),('auth.jwt()'),('storage.foldername(text)')) f(signature) where to_regprocedure(f.signature) is null) then raise exception 'Managed Auth/Storage helpers missing'; end if;
 if not exists(select 1 from pg_class where oid='storage.objects'::regclass and relrowsecurity) then raise exception 'Storage object RLS missing'; end if;
 if to_regnamespace('extensions') is null or exists(select 1 from pg_extension e join pg_namespace n on n.oid=e.extnamespace where e.extname='pg_trgm' and (n.nspname<>${literal(trgm.schema_name)} or e.extversion<>${literal(trgm.version)})) then raise exception 'Required extension placement/version differs'; end if;
end $staging_preflight$;`;
 definitions.push(`create extension if not exists pg_trgm with schema ${q(trgm.schema_name)} version ${literal(trgm.version)};\ncreate schema admin_private authorization postgres;\nrevoke all on schema admin_private from public,anon,authenticated,service_role;\nset local check_function_bodies=off;`);
 for(const r of apps){
  const rn=relationName(r.name),target=qualified(rn);
  const columns=r.columns.map(c=>`${q(c.name)} ${c.type}${c.default!==null?' default '+c.default:''}${c.not_null?' not null':''}`);
  definitions.push(`create table ${target} (${columns.join(',\n ')});`);
 }
 // PK/UNIQUE keys exist before any cross-table FK, regardless of capture order.
 for(const r of apps)for(const c of r.constraints??[]){
  identifier(c.name);
  if(!c.definition.startsWith('FOREIGN KEY'))definitions.push(`alter table ${qualified(r.name)} add constraint ${q(c.name)} ${c.definition}${!c.validated&&!c.definition.endsWith('NOT VALID')?' not valid':''};`);
 }
 for(const f of metadata.functions)definitions.push(f.definition.replace(/^CREATE OR REPLACE FUNCTION /,'CREATE FUNCTION ')+';');
 for(const r of apps)for(const c of r.constraints??[])if(c.definition.startsWith('FOREIGN KEY'))definitions.push(`alter table ${qualified(r.name)} add constraint ${q(c.name)} ${c.definition}${!c.validated&&!c.definition.endsWith('NOT VALID')?' not valid':''};`);
 for(const r of apps){
  const target=qualified(r.name),rn=relationName(r.name);
  const constraintIndexes=new Set((r.constraints??[]).filter(c=>/^(PRIMARY KEY|UNIQUE) /.test(c.definition)).map(c=>c.name));
  for(const index of r.indexes??[]){
   const match=/^CREATE (?:UNIQUE )?INDEX ([a-z_][a-z0-9_]*) ON ([a-z_][a-z0-9_]*\.[a-z_][a-z0-9_]*) USING /.exec(index);
   if(!match||match[2]!==rn)throw new Error('Unexpected captured index target');
   if(!constraintIndexes.has(match[1]))definitions.push(index+';');
  }
  const replica=complement.app_replica_identity.find(x=>x.schema_name+'.'+x.relation_name===rn);
  definitions.push(`alter table ${target} replica identity ${{d:'default',f:'full',n:'nothing',i:'using index '+q(replica.identity_index??'')}[replica.replica_identity]};`);
  definitions.push(`alter table ${target} ${r.rls?'enable':'disable'} row level security;\nalter table ${target} ${r.force_rls?'force':'no force'} row level security;`);
  const tableAcl=normalizeAcl(r.acl,'table');definitions.push(grants('table',target,tableAcl));
  const columns=r.columns.map(c=>{const acl=c.acl?normalizeAcl(c.acl,'column'):[];definitions.push(grants('column',target,acl,c.name));return {name:c.name,shape:{type:c.type,not_null:c.not_null,default:c.default,identity:c.identity,generated:c.generated},acl};});
  expected.push({name:rn,rls:r.rls,force_rls:r.force_rls,replica_identity:replica.replica_identity,columns,acl:tableAcl,constraints:r.constraints??[],indexes:r.indexes??[]});
 }
 for(const r of [...apps,storage])for(const p of r.policies??[]){
  const roleNames=p.roles.map(oid=>{const role=roles.get(String(oid));if(!allGrantees.includes(role))throw new Error('Unresolved policy role');return role;});
  const command={r:'select',a:'insert',w:'update',d:'delete','*':'all'}[p.command];if(!command)throw new Error('Unknown policy command');
  definitions.push(`create policy ${q(p.name)} on ${qualified(r.name)} as ${p.permissive?'permissive':'restrictive'} for ${command} to ${roleNames.map(roleSql).join(',')}${p.using?' using ('+p.using+')':''}${p.check?' with check ('+p.check+')':''};`);
  policies.push({table:relationName(r.name),name:p.name,shape:{permissive:p.permissive,command:p.command,using:p.using,check:p.check,roles:roleNames}});
 }
 for(const r of [...apps,{name:'auth.users',triggers:authTriggers}])for(const t of r.triggers??[]){
  if(!['O','D','A','R'].includes(t.enabled)||!t.definition.startsWith('CREATE TRIGGER '))throw new Error('Unsupported trigger definition');
  definitions.push(t.definition+';');
  if(t.enabled!=='O')definitions.push(`alter table ${qualified(r.name)} ${t.enabled==='D'?'disable':t.enabled==='A'?'enable always':'enable replica'} trigger ${q(t.name)};`);
  triggers.push({table:relationName(r.name),...t});
 }
 const functions=metadata.functions.map(f=>{const signature=functionSignature(f.signature),acl=normalizeAcl(f.acl,'function');definitions.push(grants('function',signature,acl));return {signature,definition_md5:f.definition_md5,security_definer:f.security_definer,acl};});
 definitions.push('set local check_function_bodies=on;');
 for(const b of buckets)definitions.push(`insert into storage.buckets(id,name,public,file_size_limit,allowed_mime_types) values(${literal(b.id)},${literal(b.name)},false,${b.file_size_limit===null?'null':b.file_size_limit},${b.allowed_mime_types===null?'null':'array['+b.allowed_mime_types.map(literal).join(',')+']::text[]'});`);
 for(const p of realtime)definitions.push(`alter publication supabase_realtime add table ${qualified('public.'+p.table_name)};`);
 const assertions=baselineAssertions(expected,functions,policies,triggers,buckets,realtime);
 const release=await buildStoreBackendRelease({storageOrigin:stagingOrigin});
 const heading=`-- EMPTY HOSTED STAGING ONLY: night-owl-staging / ${stagingProject}\n-- Verify the dashboard/connection project identity before execution. SQL database\n-- name postgres does not prove project identity; production is refused by empty guards.\n-- Metadata-only baseline plus exact reviewed008/009, one atomic transaction.\n-- No source rows, credentials, roles, jobs, admin identities or Edge activation.\n-- Four buckets are private from creation. Existing platform objects are preserved.\n-- Any error: ROLLBACK. Unknown commit result: inspect postflight, never blind replay.\n`;
 const settings=`set local lock_timeout='5s';\nset local statement_timeout='120s';\nset local search_path=pg_catalog,public,extensions,pg_temp;\nset local standard_conforming_strings=on;`;
 const baseline=`${preflight}\n${preserveBefore}\n${definitions.join('\n')}\n${assertions}`;
 const baselineSql=`${heading}begin;\n${settings}\n${baseline}\n${preserveAfter}\ncommit;\n`;
 const sql=`${heading}begin;\n${settings}\n${baseline}\n-- Exact existing008/009 bundle body follows; baseline assertions already passed.\n${transactionBody(release.sql,'generated008009')}\n${preserveAfter}\nnotify pgrst, 'reload schema';\ncommit;\n`;
 const postflight=`-- After the COMBINED installation; does not require an empty Auth database.\n-- Read-only security assertions. Hosted HTTP/Auth/Storage acceptance remains separate.\nbegin read only;\n${settings}\n${localeGuard}\n${transactionBody(release.postflight,'generated008009postflight',true)}\n${defaultsBody}\ndo $staging_configuration$ begin\n if (select count(*) from storage.buckets where id in ('avatars','posts','stories','venues') and not public)<>4 then raise exception 'Four private app buckets required'; end if;\n if (select storage_origin from admin_private.ugc_media_config where singleton) is distinct from ${literal(stagingOrigin)} then raise exception 'Wrong staging media origin'; end if;\n if exists(select 1 from pg_class c join pg_namespace n on n.oid=c.relnamespace cross join lateral aclexplode(coalesce(c.relacl,acldefault('r',c.relowner))) a where n.nspname in ('public','admin_private','account_private') and c.relkind='r' and (a.grantee=0 or a.grantee in ('anon'::regrole,'authenticated'::regrole)) and (a.is_grantable or a.privilege_type in ('TRUNCATE','REFERENCES','TRIGGER','MAINTAIN'))) then raise exception 'Dangerous client table privileges returned'; end if;\nend $staging_configuration$;\ncommit;\n`;
 return {sql,baselineSql,preflight:`begin read only;\n${settings}\n${preflight}\ncommit;\n`,baselinePostflight:`begin read only;\n${settings}\n${assertions}\ncommit;\n`,postflight,
  manifest:{format:'night-owl-hosted-staging-baseline-v1',prepared:true,executed:false,target_project:stagingProject,storage_origin:stagingOrigin,
   source_captured_at:metadata.captured_at,source_sha256:sourceHashes,reviewed_input_content_pinned:true,
   locale:{source_and_verified_target_equal:true,database:complement.database,target_captured_at:targetComplement.captured_at,runtime_preflight_and_postflight_enforced:true,local_fixture_tests_hosted_collation:false},
   target_managed_storage_trigger_count:targetComplement.triggers.filter(t=>t.schema_name==='storage').length,
   bundle_sha256:sha(sql),baseline_sha256:sha(baselineSql),postflight_sha256:sha(postflight),backend_bundle_sha256:release.manifest.bundle_sha256,backend_sources:release.manifest.sources,
   counts:{app_tables:apps.length,public_functions:functions.length,app_constraints:expected.reduce((n,r)=>n+r.constraints.length,0),app_indexes:expected.reduce((n,r)=>n+r.indexes.length,0),application_policies:155,storage_policies:storage.policies.length,application_triggers:triggers.length,private_buckets:buckets.length,realtime_tables:realtime.length},
   deviations:['PUBLIC/anon/authenticated table rights restricted to captured SELECT/INSERT/UPDATE/DELETE; column REFERENCES and client grant options removed','Four app buckets private from creation, including formerly public avatars/venues','No source default ACLs replayed; hardened target postgres defaults and managed supabase_admin defaults preserved'],
   preserved:['Managed Auth/Storage tables, columns, constraints, indexes, functions, native triggers and existing ACLs','Managed roles, memberships, event triggers, schema ACLs, default ACLs and publication settings','Existing public.rls_auto_enable helper'],
   excluded:['Source application/Auth/Storage object rows and private messages','Passwords, API keys, auth tokens, custom setting values','Cron jobs, administrator identities and Edge feature activation','Legacy public bucket access and production changes'],
   required_before_execution:['Confirm selected target project ref matches this manifest','Review exact SQL and hash, passing local fixture evidence and existing recovery receipts','Target Auth/Storage and application baseline must still be empty','Fresh pinned target metadata proves UTF8/ICU/en-US locale equality; re-capture/review if target is rebuilt'],
   remaining_after_execution:['Read-only postflight and platform preservation receipt','Synthetic hosted Auth signup/login, Storage photo/video, moderation and isolation acceptance','Compatible staging client configuration; Edge function tested separately'],
   limits:['Schema compatibility tests are not hosted service parity','SQL empty guards do not independently prove the project identity','No existing-user backfill; this initializer intentionally refuses nonempty targets','Baseline-only postflight applies before008/009; use combined postflight after the complete installer'],
   rollback:'Any failed assertion or DDL before COMMIT aborts the entire installation. Run ROLLBACK. After successful commit use postflight and forward fixes; never drop Auth/Storage or restore permissive defaults.'}};
}

if(process.argv[1]&&path.resolve(process.argv[1])===fileURLToPath(import.meta.url)){
 if(process.argv.length!==7)throw new Error('Usage: node tools/deployment/hosted_staging_baseline.mjs <source-schema.json> <source-platform.json> <source-complement.json> <target-complement.json> <new-build-output-directory>');
 const output=path.resolve(process.argv[6]);
 if(!output.startsWith(path.join(root,'build')+path.sep))throw new Error('Generated artifacts must be inside the repository build directory');
 let component=root;for(const p of path.relative(root,output).split(path.sep)){component=path.join(component,p);try{if((await lstat(component)).isSymbolicLink())throw new Error('Output path contains a symlink');}catch(e){if(e.code!=='ENOENT')throw e;}}
 try{await lstat(output);throw new Error('Output directory already exists; choose a new path');}catch(e){if(e.code!=='ENOENT')throw e;}
 const [schema,platform,complement,target]=await Promise.all(process.argv.slice(2,6).map(p=>readFile(p,'utf8')));
 const result=await buildHostedStagingBaseline({metadata:JSON.parse(schema),boundaries:JSON.parse(platform),complement:JSON.parse(complement),targetComplement:JSON.parse(target),sourceHashes:{schema:sha(schema),platform:sha(platform),complement:sha(complement),target:sha(target)}});
 await mkdir(output,{recursive:true,mode:0o700});
 for(const [filename,data] of Object.entries({'install-staging-baseline-008-009.sql':result.sql,'baseline-review.sql':result.baselineSql,'preflight.sql':result.preflight,'baseline-postflight.sql':result.baselinePostflight,'postflight.sql':result.postflight,'manifest.json':JSON.stringify(result.manifest,null,2)+'\n'}))await writeFile(path.join(output,filename),data,{flag:'wx',mode:0o600});
 console.log(JSON.stringify({prepared:true,executed:false,target_project:stagingProject,bundle_sha256:result.manifest.bundle_sha256,counts:result.manifest.counts,output}));
}
