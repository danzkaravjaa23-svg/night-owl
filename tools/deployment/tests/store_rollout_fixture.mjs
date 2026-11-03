// Isolated synthetic baseline for atomic rollout tests. No hosted access.
// Includes captured column/FK shapes and actual prior guard migrations; it is
// intentionally not represented as a complete production schema dump.
import {readFile} from 'node:fs/promises';
export async function seedStoreRolloutFixture(db){
 const schema=JSON.parse(await readFile(new URL('./account_erasure_schema_fixture.json',import.meta.url),'utf8'));
 const owner='10000000-0000-0000-0000-000000000001',other='10000000-0000-0000-0000-000000000002';
 const venue='20000000-0000-0000-0000-000000000001',post='30000000-0000-0000-0000-000000000001';
 const q=name=>'"'+name.replaceAll('"','""')+'"';
  await db.exec(`create role anon nologin;create role authenticated nologin;create role service_role nologin bypassrls;
    create schema auth;create table auth.users(id uuid primary key);
    create function auth.uid() returns uuid language sql stable as $$select nullif(current_setting('request.jwt.claim.sub',true),'')::uuid$$;
    grant usage on schema auth to anon,authenticated,service_role;grant execute on function auth.uid() to anon,authenticated,service_role;`);
  for(const table of [...new Set(schema.columns.map(c=>c.table))]){
    const cols=schema.columns.filter(c=>c.table===table).map(c=>{
      const type=({'_text':'text[]','_uuid':'uuid[]'})[c.type]??c.type;
      const primary=c.column==='id'||(table==='venue_catalog'&&c.column==='ref');
      const def=type==='bool'?' default false':type.endsWith('[]')?" default '{}'":'';
      return q(c.column)+' '+type+(primary?' primary key':'')+def;
    });
    await db.exec(`create table public.${q(table)}(${cols.join(',')})`);
  }
  for(const fk of schema.foreign_keys)await db.exec(`alter table public.${q(fk.table)} add constraint ${q(fk.name)} ${fk.definition}`);
  await db.exec(`create schema storage;create table storage.objects(id uuid primary key default gen_random_uuid(),bucket_id text,name text,owner_id text);
    create function public.social_active() returns boolean language sql stable security definer set search_path=public,pg_temp as $$select exists(select 1 from profiles where id=auth.uid() and not coalesce(is_banned,false))$$;
    grant usage on schema storage to anon,authenticated,service_role;
    grant select,insert,update,delete on all tables in schema public,storage to authenticated,service_role;
    grant select on all tables in schema public,storage to anon;
    alter table profiles enable row level security;create policy fixture_profile_read on profiles for select using(true);
    create policy fixture_profile_update on profiles for update using(id=auth.uid()) with check(id=auth.uid());
    alter table posts enable row level security;create policy fixture_post_read on posts for select using(true);
    create policy fixture_post_insert on posts for insert with check(user_id=auth.uid());
    alter table storage.objects enable row level security;
    create policy fixture_object_read on storage.objects for select using(true);
    create policy fixture_object_write on storage.objects for insert with check(true);
    insert into auth.users values('${owner}'),('${other}');
    insert into profiles(id,username) values('${owner}','erased-member'),('${other}','remaining-member');
    insert into venues(id,name,owner_id,cover_url) values('${venue}','Shared community place','${owner}','https://fixture.test/posts/${owner}/venue.jpg');
    insert into venue_catalog(ref,venue_id,name,cover_url) values('${venue}','${venue}','Shared community place','https://fixture.test/posts/${owner}/venue.jpg');
    insert into posts(id,user_id,venue_id,venue_ref,caption) values('${post}','${owner}','${venue}','${venue}','own post'),('30000000-0000-0000-0000-000000000002','${other}','${venue}','${venue}','other post stays');
    insert into comments(id,user_id,post_id,body) values('31000000-0000-0000-0000-000000000001','${owner}','30000000-0000-0000-0000-000000000002','own comment'),('31000000-0000-0000-0000-000000000002','${other}','30000000-0000-0000-0000-000000000002','other comment stays');
    insert into stories(id,user_id,mentions) values('32000000-0000-0000-0000-000000000001','${other}',array['${owner}','${other}']::uuid[]);
    insert into events(id,organizer_id,venue_id,title) values('33000000-0000-0000-0000-000000000001','${owner}','${venue}','own authored event'),('33000000-0000-0000-0000-000000000002','${other}','${venue}','other event stays');
    insert into messages(id,sender_id,receiver_id,body) values('34000000-0000-0000-0000-000000000001','${owner}','${other}','private own message');
    insert into reports(id,reporter_id,target_type,target_id,details) values('35000000-0000-0000-0000-000000000001','${other}','post','${post}','subject copy'),('35000000-0000-0000-0000-000000000002','${other}','user','${owner}','subject copy');
    insert into group_chats(id,name,created_by) values('36000000-0000-0000-0000-000000000001','Shared group','${owner}'),('36000000-0000-0000-0000-000000000002','Empty owner group','${owner}');
    insert into group_members(group_id,user_id) values('36000000-0000-0000-0000-000000000001','${owner}'),('36000000-0000-0000-0000-000000000001','${other}'),('36000000-0000-0000-0000-000000000002','${owner}');
    insert into group_messages(id,group_id,sender_id,body) values('37000000-0000-0000-0000-000000000001','36000000-0000-0000-0000-000000000001','${owner}','own group text'),('37000000-0000-0000-0000-000000000002','36000000-0000-0000-0000-000000000001','${other}','other group text stays');
    insert into venue_reviews(id,venue_id,user_id,rating,comment) values('38000000-0000-0000-0000-000000000001','${venue}','${other}',5,'other review stays');
    insert into admin_audit_log(id,actor_id,actor_username,action,target_type,target_id,reason) values('39000000-0000-0000-0000-000000000001','${other}','moderator','delete_post','post','${post}','security audit retained');`);

  const read=p=>readFile(new URL('../../../'+p,import.meta.url),'utf8');
  await db.exec(`create table storage.buckets(id text primary key,public boolean);insert into storage.buckets values('posts',true),('stories',true),('avatars',true),('venues',true);
    create function auth.role() returns text language sql stable as $$select current_setting('role',true)$$;
    create function auth.jwt() returns jsonb language sql stable as $$select jsonb_build_object('role',current_setting('role',true))$$;
    grant execute on all functions in schema auth to anon,authenticated,service_role;
    alter table reports alter column id set default gen_random_uuid(),alter column status set default 'pending';
    alter table admin_audit_log alter column id set default gen_random_uuid(),alter column created_at set default clock_timestamp();
    alter table posts alter column id set default gen_random_uuid();
    alter table profiles add column if not exists cover_url text;
    update profiles set is_admin=true where id='${owner}';
    do $$declare t record;begin for t in select tablename from pg_tables where schemaname='public' loop
      execute format('alter table public.%I enable row level security',t.tablename);
      if t.tablename not in ('profiles','posts') then execute format('create policy combined_fixture_read on public.%I for select using(true)',t.tablename);end if;
    end loop;end$$;`);
  await db.exec(await read('supabase/migrations/202610160001_social_discovery.sql'));
  await db.exec(await read('supabase_featured_events.sql'));
  await db.exec(await read('supabase/migrations/202610220001_storage_account_guards.sql'));
  await db.exec(await read('supabase/migrations/202611030001_account_deletion_boundaries.sql'));
  await db.exec(await read('supabase/migrations/202611030002_discovery_analytics_consent.sql'));
  await db.exec(await read('supabase/migrations/202611030003_admin_console.sql'));
  await db.exec(await read('supabase/migrations/202611030004_interaction_boundaries.sql'));
  await db.exec(await read('supabase/migrations/202611030005_venue_story_activity.sql'));
  await db.exec(await read('supabase/migrations/202611030007_venue_map_activity.sql'));

 return {owner,other,venue,post};
}
