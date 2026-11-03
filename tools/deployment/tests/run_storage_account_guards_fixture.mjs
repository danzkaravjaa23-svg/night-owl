// Isolated PostgreSQL semantics only. Never loads live rows, JWTs or credentials.
import assert from 'node:assert/strict';
import {readFile} from 'node:fs/promises';
import {pathToFileURL} from 'node:url';
const {PGlite}=await import(pathToFileURL(process.argv[2]).href);
const db=new PGlite();
const owner='10000000-0000-0000-0000-000000000001';
const other='10000000-0000-0000-0000-000000000002';
const stale='10000000-0000-0000-0000-000000000003';
const buckets=['avatars','posts','stories','venues'];
const login=async(id,role=id?'authenticated':'anon')=>db.exec(`reset role;select set_config('request.jwt.claim.sub','${id??''}',false);set role ${role}`);
const rows=async sql=>(await db.query(sql)).rows;
const denied=sql=>assert.rejects(db.exec(sql),error=>error.code==='42501');
try {
  await db.exec(`create role anon nologin;create role authenticated nologin;create role service_role nologin bypassrls;
    create schema auth;create schema storage;
    create table storage.buckets(id text primary key,name text,public boolean,file_size_limit bigint,allowed_mime_types text[]);
    insert into storage.buckets(id,name,public) values('posts','posts',false),('stories','stories',false);
    create function storage.foldername(p_name text) returns text[] language sql immutable as $$select string_to_array(p_name,'/');$$;
    create function auth.uid() returns uuid language sql stable as $$
      select nullif(current_setting('request.jwt.claim.sub',true),'')::uuid;$$;
    grant usage on schema auth,storage to anon,authenticated,service_role;
    create table profiles(id uuid primary key,is_banned boolean default false);
    insert into profiles values('${owner}',false),('${other}',false);
    create function social_active() returns boolean language sql stable security definer set search_path=public,pg_temp as $$
      select exists(select 1 from profiles where id=auth.uid() and not coalesce(is_banned,false));$$;
    create table storage.objects(bucket_id text,name text,primary key(bucket_id,name));
    alter table storage.objects enable row level security;
    grant select,insert,update,delete on storage.objects to anon,authenticated,service_role;
    create policy legacy_read on storage.objects for select using(true);
    create policy deliberately_broad_legacy_write on storage.objects for all to anon,authenticated using(true) with check(true);`);
  // Reproduce both legacy risks before installing the restrictive intersection.
  await login(owner);
  await db.exec(`insert into storage.objects values('posts','${other}/legacy.jpg')`);
  await login(stale);
  await db.exec(`insert into storage.objects values('avatars','${stale}/old-jwt.jpg')`);
  await db.exec('reset role;delete from storage.objects');
  const migration=await readFile(new URL('../../../supabase/migrations/202610220001_storage_account_guards.sql',import.meta.url),'utf8');
  await db.exec(migration);
  await db.exec(migration);
  const bootstrap=await readFile(new URL('../../../supabase_storage_setup.sql',import.meta.url),'utf8');
  await db.exec(bootstrap);
  await db.exec(bootstrap);
  assert.deepEqual((await rows("select public from storage.buckets where id in ('posts','stories') order by id")).map(r=>r.public),[false,false],
    'Storage bootstrap must not reopen private social media buckets');

  await login(owner);
  for(const bucket of buckets) {
    await db.exec(`insert into storage.objects values('${bucket}','${owner}/own.jpg')`);
    await denied(`insert into storage.objects values('${bucket}','${other}/spoofed.jpg')`);
    await denied(`insert into storage.objects values('${bucket}','${owner}/../escape.jpg')`);
    await denied(`insert into storage.objects values('${bucket}','${owner}/./escape.jpg')`);
    await denied(`insert into storage.objects values('${bucket}','${owner}/nested/../escape.jpg')`);
    await denied(`insert into storage.objects values('${bucket}','${owner}/nested${String.fromCharCode(92)}escape.jpg')`);
    await denied(`insert into storage.objects values('${bucket}','${owner}')`);
    for(const suffix of ['/', '//photo.jpg', '/nested//photo.jpg', '/nested/']) {
      await denied(`insert into storage.objects values('${bucket}','${owner}${suffix}')`);
    }
  }
  await db.exec(`update storage.objects set name='${owner}/renamed.jpg' where bucket_id='posts'`);
  await denied(`update storage.objects set name='${other}/overwrite.jpg' where bucket_id='posts'`);
  await db.exec(`reset role;insert into storage.objects values('avatars','${other}/other.jpg')`);
  await login(owner);
  assert.equal((await rows(`update storage.objects set name='${owner}/stolen.jpg' where name='${other}/other.jpg' returning *`)).length,0);
  assert.equal((await rows(`delete from storage.objects where name='${other}/other.jpg' returning *`)).length,0);

  for(const id of [stale,null]) {
    await login(id);
    for(const bucket of buckets)await denied(`insert into storage.objects values('${bucket}','${id??'anon'}/new.jpg')`);
  }
  await db.exec(`reset role;update profiles set is_banned=true where id='${owner}'`);
  await login(owner);
  await denied(`insert into storage.objects values('posts','${owner}/banned.jpg')`);
  assert.equal((await rows(`update storage.objects set name='${owner}/blocked.jpg' where bucket_id='posts' returning *`)).length,0);

  // Deleting a profile does not erase an already issued JWT's subject claim.
  await db.exec(`reset role;delete from profiles where id='${owner}'`);
  await login(owner);
  for(const bucket of buckets)await denied(`insert into storage.objects values('${bucket}','${owner}/after-delete.jpg')`);
  assert.equal((await rows(`delete from storage.objects where name like '${owner}/%' returning *`)).length,0);

  // Unrelated buckets and legacy public reads are not changed by this migration.
  await db.exec(`insert into storage.objects values('outside-app','legacy-scope.txt')`);
  await login(null);
  assert.ok((await rows("select * from storage.objects where bucket_id='avatars'")).length>0);
  await login(stale,'service_role');
  assert.ok((await rows(`delete from storage.objects where name like '${owner}/%' returning *`)).length>0);
  console.log('PASS: storage write guards (active owner, stale/deleted JWT, banned/anon, legacy intersection, service cleanup)');
} finally {
  await db.close();
}
