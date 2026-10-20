// Schema-only compatibility trial using an explicitly supplied private catalog.
// Does not read the scoped data backup, use user rows, or connect to a server.
import assert from 'node:assert/strict';
import {readFile} from 'node:fs/promises';
import {pathToFileURL} from 'node:url';
import {buildHostedRepair} from '../hosted_backend_release.mjs';

const {PGlite}=await import(pathToFileURL(process.argv[2]).href);
const catalog=JSON.parse(await readFile(process.argv[3],'utf8'));
const quote=value=>'"'+value.replaceAll('"','""')+'"';
const literal=value=>"'"+value.replaceAll("'","''")+"'";
const role=value=>value==='PUBLIC'?'public':quote(value);
const db=new PGlite();
try {
  await db.exec(`create role anon nologin;create role authenticated nologin;create role service_role nologin;
    revoke create on schema public from public;
    create schema auth;create table auth.users(id uuid primary key,raw_user_meta_data jsonb,email text);
    create function auth.uid() returns uuid language sql stable as $$select nullif(current_setting('request.jwt.claim.sub',true),'')::uuid$$;
    create function auth.role() returns text language sql stable as $$select current_setting('role',true)$$;
    create function auth.jwt() returns jsonb language sql stable as $$select jsonb_build_object('role',auth.role())$$;
    grant usage on schema auth to anon,authenticated;
    grant execute on all functions in schema auth to anon,authenticated;
    create schema storage;
    create table storage.buckets(id text primary key,public boolean,file_size_limit bigint,allowed_mime_types text[]);
    create table storage.objects(id uuid primary key default gen_random_uuid(),bucket_id text,name text,owner uuid,owner_id text,metadata jsonb);
    create function storage.foldername(text) returns text[] language sql immutable as $$select (string_to_array($1,'/'))[1:array_length(string_to_array($1,'/'),1)-1]$$;
    alter table storage.objects enable row level security;
    grant usage on schema storage to anon,authenticated;
    grant select on storage.objects,storage.buckets to anon,authenticated;
    set check_function_bodies=off;`);
  assert.equal(catalog.enums,null,'Review custom types explicitly');
  for(const table of catalog.tables) {
    assert.equal(table.kind,'r','Partitioned tables require explicit review');
    assert.equal(table.owner,'postgres','Unexpected managed table owner');
    const columns=table.columns.map(c=>{
      assert.equal(c.identity,'','Identity columns require explicit review');
      return `${quote(c.name)} ${c.type}`+
        (c.generated?` generated always as (${c.default}) stored`:
          c.default?` default ${c.default}`:'')+(c.not_null?' not null':'');
    });
    await db.exec(`create table public.${quote(table.name)}(${columns.join(',')})`);
    if(table.rls)await db.exec(`alter table public.${quote(table.name)} enable row level security`);
    if(table.force_rls)await db.exec(`alter table public.${quote(table.name)} force row level security`);
  }
  for(const constraint of catalog.constraints) {
    await db.exec(`alter table public.${quote(constraint.table.replace(/^public\./,''))} add constraint ${quote(constraint.name)} ${constraint.definition}`);
  }
  let applicationFunctions=0;
  for(const fn of catalog.functions) {
    // Extension C functions are not an application-schema restore. PGlite's
    // built-ins supply UUID/SQL primitives; no extension binary is transplanted.
    if(!/LANGUAGE (sql|plpgsql)\b/i.test(fn.definition))continue;
    await db.exec(fn.definition);
    applicationFunctions++;
  }
  for(const trigger of catalog.triggers)await db.exec(trigger);
  for(const policy of catalog.policies) {
    await db.exec(`create policy ${quote(policy.policyname)} on ${quote(policy.schemaname)}.${quote(policy.tablename)} as ${policy.permissive} for ${policy.cmd} to ${policy.roles.map(role).join(',')}`+
      (policy.qual?` using(${policy.qual})`:'')+(policy.with_check?` with check(${policy.with_check})`:''));
  }
  for(const grant of catalog.grants) {
    await db.exec(`grant ${grant.privilege_type} on public.${quote(grant.table_name)} to ${role(grant.grantee)}`);
  }
  // Column privileges derived from a table grant are not separate column ACLs.
  // Preserve the narrow event_features contract rather than inventing ALL.
  for(const grant of catalog.column_grants.filter(g=>g.table_name==='event_features')) {
    await db.exec(`grant ${grant.privilege_type}(${quote(grant.column_name)}) on public.${quote(grant.table_name)} to ${role(grant.grantee)}`);
  }
  for(const bucket of catalog.buckets) {
    await db.query('insert into storage.buckets values($1,$2,$3,$4)',[bucket.id,bucket.public,bucket.file_size_limit,bucket.allowed_mime_types]);
  }
  // Reproduce managed Supabase's broad defaults for newly created tables.
  await db.exec(`alter default privileges in schema public grant all on tables to anon,authenticated;
    alter default privileges in schema public grant all on functions to anon,authenticated;
    set check_function_bodies=on;`);
  const {sql,manifest}=await buildHostedRepair();
  await db.exec(sql);
  await db.exec(await readFile(new URL('./hosted_backend_postflight.sql',import.meta.url),'utf8'));
  await assert.rejects(db.exec(sql),/Existing client RPC requires explicit implementation review/);
  await db.exec('rollback');
  await db.exec(await readFile(new URL('./hosted_backend_postflight.sql',import.meta.url),'utf8'));
  const result=await db.query(`select to_regprocedure('public.get_discovery_feed(boolean,timestamptz,uuid,integer)') is not null as feed,
    to_regprocedure('public.create_group(text,uuid[])') is not null as groups,
    to_regprocedure('public.check_in_venue(uuid)') is not null as checkin,
    not has_table_privilege('authenticated','public.discovery_activity','SELECT') as private_metrics,
    not has_table_privilege('anon','public.venue_catalog','TRUNCATE') as narrow_catalog,
    not public as private_posts from storage.buckets where id='posts'`);
  assert.deepEqual(Object.values(result.rows[0]),[true,true,true,true,true,true]);
  await db.exec('set role anon');
  await db.query('select * from public.get_discovery_feed()');
  await db.query('select * from public.get_featured_events()');
  await assert.rejects(db.query('select * from public.get_pilot_overview()'),e=>e.code==='42501');
  console.log(JSON.stringify({passed:true,scope:'empty captured public table shapes/policies/application functions; Auth and Storage mocks; no user data',tables:catalog.tables.length,applicationFunctions,policies:catalog.policies.length,repairSha256:manifest.sha256,fullRestore:false},null,2));
} catch(error) {
  console.error(`${error.code??error.name}: ${error.message}`);
  process.exitCode=1;
} finally {await db.close();}
