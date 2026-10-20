-- In-memory database only. Broad legacy policies intentionally remain installed.
create role anon nologin;
create role authenticated nologin;
create schema auth;
create function auth.uid() returns uuid language sql stable as $$ select nullif(current_setting('request.jwt.claim.sub',true),'')::uuid; $$;
create function auth.jwt() returns jsonb language sql stable as $$ select jsonb_build_object('role',current_setting('role',true)); $$;
grant usage on schema auth to anon,authenticated;
grant execute on all functions in schema auth to anon,authenticated;
create table profiles(id uuid primary key,username text,full_name text,bio text,avatar_url text,last_seen_at timestamptz,interests text[] default '{}',followers_count int default 0,
  is_admin boolean default false,is_banned boolean default false,is_verified boolean default false,created_at timestamptz default now());
create table venues(id uuid primary key,name text,venue_type text,address text,district text,lat float8,lng float8,cover_url text,phone text,owner_id uuid references profiles);
create table posts(id uuid primary key default gen_random_uuid(),user_id uuid references profiles,venue_id uuid references venues,venue_name text,caption text,media_url text,media_urls text[] default '{}',media_type text default 'image',created_at timestamptz default now());
create table follows(follower_id uuid references profiles,following_id uuid references profiles,primary key(follower_id,following_id));
create table blocks(blocker_id uuid references profiles,blocked_id uuid references profiles,primary key(blocker_id,blocked_id));
create table checkins(id uuid primary key default gen_random_uuid(),user_id uuid references profiles,venue_id uuid references venues,expires_at timestamptz default now()+interval '4 hours');
create table stories(id uuid primary key default gen_random_uuid(),user_id uuid references profiles,venue_id uuid references venues,media_url text,expires_at timestamptz default now()+interval '1 day');
create table comments(id uuid primary key default gen_random_uuid(),user_id uuid references profiles,post_id uuid references posts,body text);
create table likes(user_id uuid references profiles,post_id uuid references posts,primary key(user_id,post_id));
create table events(id uuid primary key default gen_random_uuid(),organizer_id uuid references profiles,cover_url text);
create table messages(id uuid primary key default gen_random_uuid(),sender_id uuid references profiles,receiver_id uuid references profiles,body text,is_read boolean default false,note_text text,story_media_url text,created_at timestamptz default now());
create schema storage;
create table storage.buckets(id text primary key,public boolean);
create table storage.objects(id uuid primary key default gen_random_uuid(),bucket_id text,name text);
insert into storage.buckets values('posts',true),('stories',true),('avatars',true),('venues',true);
grant usage on schema storage to anon,authenticated;
grant select on storage.objects,storage.buckets to anon,authenticated;
alter table storage.objects enable row level security;
create policy legacy_read on storage.objects for select using(true);
do $$ declare t text; begin
  foreach t in array array['profiles','venues','posts','follows','blocks','checkins','stories','comments','likes','messages','events'] loop
    execute format('alter table %I enable row level security',t);
    execute format('create policy legacy_read on %I for select using(true)',t);
    execute format('grant select,insert,update,delete on %I to authenticated',t);
    execute format('grant select on %I to anon',t);
  end loop;
end $$;
create policy own_profile on profiles for update using(id=auth.uid());
create policy own_venue on venues for update using(owner_id=auth.uid() or exists(select 1 from profiles where id=auth.uid() and is_admin));
create policy own_post on posts for insert with check(user_id=auth.uid());
create policy own_story on stories for insert with check(user_id=auth.uid());
create policy own_follow on follows for insert with check(follower_id=auth.uid());
create policy own_block on blocks for insert with check(blocker_id=auth.uid());
create policy own_message on messages for insert with check(sender_id=auth.uid());
create policy own_read_receipt on messages for update using(receiver_id=auth.uid());
insert into profiles(id,username,is_admin) values
('10000000-0000-0000-0000-000000000001','viewer',false),
('10000000-0000-0000-0000-000000000002','creator',false),
('10000000-0000-0000-0000-000000000003','admin',true),
('10000000-0000-0000-0000-000000000004','stranger',false);
insert into venues(id,name,address,owner_id) values('20000000-0000-0000-0000-000000000001','Synthetic cafe','Synthetic address','10000000-0000-0000-0000-000000000002');
insert into posts(id,user_id,venue_id,caption,media_url,created_at) values
('30000000-0000-0000-0000-000000000001','10000000-0000-0000-0000-000000000002','20000000-0000-0000-0000-000000000001','Synthetic private photo','https://fixture.test/storage/v1/object/public/posts/10000000-0000-0000-0000-000000000002/photo.jpg','2026-10-01T12:00:00Z'),
('30000000-0000-0000-0000-000000000002','10000000-0000-0000-0000-000000000002',null,'Same timestamp','https://fixture.test/storage/v1/object/public/posts/10000000-0000-0000-0000-000000000002/video.mp4','2026-10-01T12:00:00Z');
insert into storage.objects(bucket_id,name) values('posts','10000000-0000-0000-0000-000000000002/photo.jpg');
insert into follows values('10000000-0000-0000-0000-000000000001','10000000-0000-0000-0000-000000000003');
insert into blocks values('10000000-0000-0000-0000-000000000001','10000000-0000-0000-0000-000000000003');
insert into stories(id,user_id,media_url,expires_at) values
('30000000-0000-0000-0000-000000000003','10000000-0000-0000-0000-000000000002','https://fixture.test/storage/v1/object/public/stories/10000000-0000-0000-0000-000000000002/active.jpg',now()+interval '1 day'),
('30000000-0000-0000-0000-000000000004','10000000-0000-0000-0000-000000000002','https://fixture.test/storage/v1/object/public/stories/10000000-0000-0000-0000-000000000002/expired.jpg',now()-interval '1 day');
insert into checkins(user_id,venue_id,expires_at) values
('10000000-0000-0000-0000-000000000002','20000000-0000-0000-0000-000000000001',now()+interval '4 hours'),
('10000000-0000-0000-0000-000000000002','20000000-0000-0000-0000-000000000001',now()-interval '1 hour');
