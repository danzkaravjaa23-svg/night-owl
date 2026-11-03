// Synthetic PostgreSQL only: prove the legacy bypasses, then close them without
// deleting a real account, object or service. Supply an installed PGlite module.
import assert from 'node:assert/strict';
import {readFile} from 'node:fs/promises';
import {pathToFileURL} from 'node:url';
const {PGlite}=await import(pathToFileURL(process.argv[2]).href);
const db=new PGlite();
const owner='10000000-0000-0000-0000-000000000001';
const other='10000000-0000-0000-0000-000000000002';
const admin='10000000-0000-0000-0000-000000000003';
const login=async(id,role='authenticated')=>db.exec(`reset role;select set_config('request.jwt.claim.sub','${id??''}',false);set role ${role}`);
const rows=async sql=>(await db.query(sql)).rows;
const denied=sql=>assert.rejects(db.exec(sql),error=>error.code==='42501');
try {
  await db.exec(`create role anon nologin;create role authenticated nologin;create role service_role nologin bypassrls;
    create schema auth;create schema storage;
    create function auth.uid() returns uuid language sql stable as $$
      select nullif(current_setting('request.jwt.claim.sub',true),'')::uuid;$$;
    grant usage on schema auth,storage to anon,authenticated,service_role;
    create table auth.users(id uuid primary key);
    create table profiles(id uuid primary key references auth.users(id) on delete cascade,is_admin boolean default false);
    create table posts(id integer primary key,user_id uuid references profiles(id) on delete cascade,media_url text,media_urls text[]);
    create table storage.objects(bucket_id text,name text,primary key(bucket_id,name));
    insert into auth.users values('${owner}'),('${other}'),('${admin}');
    insert into profiles values('${owner}',false),('${other}',false),('${admin}',true);
    insert into posts values(1,'${owner}','https://fixture.invalid/storage/v1/object/public/posts/${other}/victim.jpg',null),
      (2,'${owner}','https://fixture.invalid/storage/v1/object/public/posts/${owner}/own.jpg',null),
      (3,'${other}',null,null);
    insert into storage.objects values('posts','${owner}/own.jpg'),('posts','${other}/victim.jpg');
    create function is_admin() returns boolean language sql stable security definer set search_path=public,pg_temp as $$
      select coalesce((select is_admin from profiles where id=auth.uid()),false);$$;
    alter table profiles enable row level security;
    alter table posts enable row level security;
    alter table storage.objects enable row level security;
    grant select,delete,truncate on profiles to anon,authenticated;
    grant select,delete on posts to authenticated;
    grant select on storage.objects to authenticated;
    grant select,delete on auth.users,profiles,posts,storage.objects to service_role;
    create policy profile_read on profiles for select using(true);
    create policy "Own profile deletable" on profiles for delete using(auth.uid()=id or public.is_admin());
    create policy post_read on posts for select using(true);
    create policy post_delete on posts for delete using(auth.uid()=user_id);
    create policy storage_read on storage.objects for select using(true);
    create function cleanup_post_media() returns trigger language plpgsql security definer as $$
    begin delete from storage.objects where bucket_id='posts' and name=split_part(old.media_url,'/posts/',2);return old;end;$$;
    create trigger trg_cleanup_post_media after delete on posts for each row execute function cleanup_post_media();
    create trigger legacy_alias after delete on posts for each row execute function cleanup_post_media();`);

  await login(owner);
  await db.exec('begin;delete from posts where id=1');
  assert.equal((await rows(`select * from storage.objects where name='${other}/victim.jpg'`)).length,0,
    'Legacy post URL could erase another owner\'s metadata');
  await db.exec('rollback;begin;delete from profiles where id=auth.uid()');
  assert.equal((await rows(`select * from profiles where id='${owner}'`)).length,0,
    'Legacy profile policy bypassed the complete account workflow');
  await db.exec('rollback;reset role');

  const migration=await readFile(new URL('../../../supabase/migrations/202611030001_account_deletion_boundaries.sql',import.meta.url),'utf8');
  await db.exec(migration);
  await db.exec(migration);
  // The maintained compatibility scripts must not reopen either bypass.
  await db.exec(await readFile(new URL('../../../supabase_account_delete.sql',import.meta.url),'utf8'));
  await db.exec(await readFile(new URL('../../../supabase_storage_cleanup.sql',import.meta.url),'utf8'));
  for(const id of [owner,admin,null]) {
    await login(id,id?'authenticated':'anon');
    await denied(`delete from profiles where id='${owner}'`);
    await denied('truncate profiles cascade');
  }
  // Even restoring a broad permissive policy/grant cannot bypass restriction.
  await db.exec('reset role;grant delete on profiles to authenticated;create policy accidental_broad_delete on profiles for delete using(true)');
  await login(admin);
  assert.equal((await rows('delete from profiles returning id')).length,0);
  await login(owner);
  await db.exec('delete from posts where id=1');
  assert.equal((await rows(`select * from storage.objects where name='${other}/victim.jpg'`)).length,1,
    'Neither the known trigger nor a legacy alias may delete foreign metadata');

  // Simulate only the database side of the trusted Auth cascade. Real Storage
  // API erasure is a separate contract and is intentionally not faked as SQL.
  await login(owner,'service_role');
  await db.exec(`delete from auth.users where id='${owner}'`);
  assert.equal((await rows(`select * from profiles where id='${owner}'`)).length,0);
  assert.equal((await rows(`select * from posts where user_id='${owner}'`)).length,0);
  assert.equal((await rows(`select * from auth.users where id='${other}'`)).length,1);
  assert.equal((await rows(`select * from profiles where id='${other}'`)).length,1);
  assert.equal((await rows(`select * from posts where user_id='${other}'`)).length,1);
  assert.equal((await rows(`select * from storage.objects where name='${other}/victim.jpg'`)).length,1);
  console.log('PASS: legacy profile/metadata bypasses reproduced and closed; admin/anon/delete/truncate blocked; aliases neutralized; trusted Auth FK cascade retained; other account isolated');
} finally {
  await db.close();
}
