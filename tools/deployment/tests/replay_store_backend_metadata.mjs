// Replays captured application metadata inside a caller-owned isolated PGlite.
// No connection, credential, user data, remote SQL or filesystem import occurs.
// Platform-only Auth/Storage triggers and noncaptured service internals are
// explicitly excluded; this is application-schema compatibility, not a hosted clone.
const q=value=>'"'+String(value).replaceAll('"','""')+'"';
const name=value=>value.split('.').map(q).join('.');
const privilege={r:'SELECT',a:'INSERT',w:'UPDATE',d:'DELETE',D:'TRUNCATE',x:'REFERENCES',t:'TRIGGER',m:'MAINTAIN',X:'EXECUTE',U:'USAGE',C:'CREATE'};
export async function replayStoreBackendMetadata(db,metadata,boundaries){
 if(metadata.scope!=='metadata-only; no application/Auth/Storage object rows')throw new Error('Unexpected metadata export scope');
 if(!Array.isArray(boundaries.roles)||!Array.isArray(boundaries.functions)||!Array.isArray(boundaries.enums))throw new Error('Verified boundary role/function/type metadata required');
 const roleByOid=new Map([['0','public'],...boundaries.roles.map(r=>[String(r.oid),r.role])]);
 const roles=new Set(['anon','authenticated','service_role']);
 for(const relation of metadata.relations){roles.add(relation.owner);for(const acl of relation.acl??[])roles.add(acl.split('=')[0]||'public');}
 for(const s of metadata.schema_acls){roles.add(s.owner);for(const acl of s.acl??[])roles.add(acl.split('=')[0]||'public');}
 for(const role of roles){
   if(!/^[a-z_][a-z0-9_]*$/.test(role))throw new Error('Unsupported role identifier');
   if(!['public','postgres','pg_database_owner'].includes(role))await db.exec(`create role ${q(role)} nologin ${role==='service_role'?'bypassrls':''}`);
 }
 for(const schema of ['auth','storage','admin_private'])await db.exec(`create schema ${q(schema)}`);
 if(metadata.relations.some(r=>r.name.startsWith('account_private.')))throw new Error('Snapshot already has pending erasure schema');
 const labels=boundaries.enums.filter(e=>e.schema==='storage'&&e.name==='buckettype').sort((a,b)=>a.order-b.order).map(e=>"'"+e.label.replaceAll("'","''")+"'");
 if(labels.length===0)throw new Error('Missing Storage buckettype labels');
 await db.exec(`create type storage.buckettype as enum (${labels.join(',')});set check_function_bodies=off;`);
 async function acl(kind,target,list){
   if(list===null||list===undefined)return;
   await db.exec(`revoke all on ${kind} ${target} from public`);
   for(const item of list){
     const match=/^([^=]*)=([^/]+)\/([^/]+)$/.exec(item);if(!match)throw new Error('Unexpected ACL shape');
     const role=match[1]||'public';if(role!=='public'&&!roles.has(role))throw new Error('Unlisted ACL role');
     for(let i=0;i<match[2].length;i++){
       const p=privilege[match[2][i]];if(!p)throw new Error('Unsupported ACL privilege');
       const grant=match[2][i+1]==='*';if(grant)i++;
       await db.exec(`grant ${p} on ${kind} ${target} to ${role==='public'?'public':q(role)}${grant?' with grant option':''}`);
     }
   }
 }
 for(const relation of metadata.relations){
   if(relation.kind!=='r')throw new Error('Only ordinary tables are supported by this replay');
   const columns=relation.columns.map(c=>{
     if(c.identity)throw new Error('Identity column replay requires explicit sequence metadata');
     const def=c.generated?` generated always as (${c.default}) stored`:c.default?` default ${c.default}`:'';
     return `${q(c.name)} ${c.type}${def}${c.not_null?' not null':''}`;
   });
   await db.exec(`create table ${name(relation.name)}(${columns.join(',')})`);
 }
 for(const fkPass of [false,true])for(const relation of metadata.relations)for(const c of relation.constraints??[]){
   if(c.definition.startsWith('FOREIGN KEY')!==fkPass)continue;
   await db.exec(`alter table ${name(relation.name)} add constraint ${q(c.name)} ${c.definition}${!c.validated&&!c.definition.endsWith('NOT VALID')?' not valid':''}`);
 }
 for(const boundary of boundaries.functions){
   if(!['auth.uid()','auth.role()','auth.jwt()','storage.foldername(text)'].includes(boundary.signature))throw new Error('Unreviewed platform boundary function');
   await db.exec(boundary.definition);
 }
 for(const f of metadata.functions){
   if(f.owner!=='postgres')throw new Error('Non-postgres function owner requires additional definer-role metadata');
   await db.exec(f.definition);
 }
 for(const relation of metadata.relations){
   for(const index of relation.indexes??[])await db.exec(index.replace(/^CREATE (UNIQUE )?INDEX /,(_,u)=>`CREATE ${u??''}INDEX IF NOT EXISTS `));
   if(relation.rls)await db.exec(`alter table ${name(relation.name)} enable row level security`);
   if(relation.force_rls)await db.exec(`alter table ${name(relation.name)} force row level security`);
   for(const policy of relation.policies??[]){
     const commands={r:'select',a:'insert',w:'update',d:'delete','*':'all'};
     const policyRoles=policy.roles.map(oid=>{const role=roleByOid.get(String(oid));if(!role)throw new Error('Unresolved policy role OID '+oid);return role==='public'?'public':q(role);});
     await db.exec(`create policy ${q(policy.name)} on ${name(relation.name)} as ${policy.permissive?'permissive':'restrictive'} for ${commands[policy.command]} to ${policyRoles.join(',')}${policy.using?` using (${policy.using})`:''}${policy.check?` with check (${policy.check})`:''}`);
   }
   await acl('table',name(relation.name),relation.acl);
   for(const column of relation.columns)for(const item of column.acl??[]){
     const match=/^([^=]*)=([^/]+)\/([^/]+)$/.exec(item);if(!match)throw new Error('Unexpected column ACL');
     const role=match[1]||'public';
     for(let i=0;i<match[2].length;i++){
       const p=privilege[match[2][i]];if(!['SELECT','INSERT','UPDATE','REFERENCES'].includes(p))throw new Error('Unsupported column ACL');
       const grant=match[2][i+1]==='*';if(grant)i++;
       await db.exec(`grant ${p}(${q(column.name)}) on ${name(relation.name)} to ${role==='public'?'public':q(role)}${grant?' with grant option':''}`);
     }
   }
 }
 for(const f of metadata.functions)await acl('function',f.signature,f.acl);
 for(const schema of metadata.schema_acls)await acl('schema',q(schema.schema),schema.acl);
 const omitted=[];let installedTriggers=0;
 for(const relation of metadata.relations)for(const t of relation.triggers??[]){
   const platform=relation.name.startsWith('storage.')||relation.name.startsWith('auth.');
   if(platform&&!/EXECUTE FUNCTION (?:public\.)?(?:handle_new_user|account_erasure_write_guard)\(/.test(t.definition)){omitted.push(relation.name+'.'+t.name);continue;}
   await db.exec(t.definition);
   if(t.enabled==='D')await db.exec(`alter table ${name(relation.name)} disable trigger ${q(t.name)}`);
   else if(t.enabled==='A')await db.exec(`alter table ${name(relation.name)} enable always trigger ${q(t.name)}`);
   else if(t.enabled==='R')await db.exec(`alter table ${name(relation.name)} enable replica trigger ${q(t.name)}`);
   installedTriggers++;
 }
 for(const b of metadata.app_buckets)await db.query('insert into storage.buckets(id,name,public) values($1,$1,$2)',[b.id,b.public]);
 for(const d of metadata.default_acls){
   const types={r:'tables',S:'sequences',f:'functions',T:'types',n:'schemas'};
   if(!types[d.type])throw new Error('Unsupported default ACL type');
   const prefix=`alter default privileges for role ${q(d.owner)}${d.schema?' in schema '+q(d.schema):''}`;
   await db.exec(`${prefix} revoke all on ${types[d.type]} from public`);
   for(const item of d.acl??[]){
     const match=/^([^=]*)=([^/]+)\/([^/]+)$/.exec(item);if(!match)throw new Error('Unexpected default ACL');
     for(let i=0;i<match[2].length;i++){
       const p=privilege[match[2][i]];if(!p)throw new Error('Unsupported default ACL privilege');
       const grant=match[2][i+1]==='*';if(grant)i++;
       await db.exec(`${prefix} grant ${p} on ${types[d.type]} to ${match[1]?q(match[1]):'public'}${grant?' with grant option':''}`);
     }
   }
 }
 await db.exec('set check_function_bodies=on');
 return {relations:metadata.relations.length,functions:metadata.functions.length,
   policies:metadata.relations.reduce((n,r)=>n+(r.policies?.length??0),0),installed_triggers:installedTriggers,
   omitted_platform_triggers:omitted,limits:['No hosted services or production user data','Platform-only Auth/Storage triggers excluded','Extension implementations and physical storage are not replayed']};
}
