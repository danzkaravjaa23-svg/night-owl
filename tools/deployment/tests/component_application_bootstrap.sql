-- COMPONENT TEST FIXTURE ONLY. Never run against hosted/staging/production.
-- Application skeleton from account_erasure_schema_fixture.json (38 tables,
-- 250 columns, 69 foreign keys). This intentionally does NOT claim complete
-- production schema/policy/default/trigger parity. Source migrations provide
-- actual social/privacy, admin, erasure and UGC behavior on top of this fixture.
-- Official local Supabase must already own Auth and Storage; this file does not
-- create/replace roles, Auth users/functions, Storage objects/buckets or policies.
-- The HTTP harness creates users/buckets through their actual service APIs and
-- supplies owner-scoped Storage upload policies separately.
-- Run once on a fresh disposable local stack BEFORE these source migrations:
-- 202610160001, supabase_featured_events.sql, 202611030001, 003, 005, 007, 008, 009.
-- admin_audit_log and event_features are created by their actual migrations.
begin;
do $$ begin
 if to_regclass('public.profiles') is not null then
  raise exception 'Component fixture requires an empty application schema';
 end if;
 if to_regprocedure('auth.uid()') is null or to_regprocedure('auth.role()') is null
    or to_regclass('auth.users') is null or to_regclass('storage.objects') is null
    or to_regclass('storage.buckets') is null then
  raise exception 'Use the official disposable local Supabase Auth/Storage stack';
 end if;
end $$;

create table public."blocks" (
  "blocker_id" uuid not null,
  "blocked_id" uuid not null,
  "created_at" timestamptz default now(),
  primary key("blocker_id","blocked_id")
);
create table public."checkins" (
  "id" uuid not null default gen_random_uuid(),
  "user_id" uuid not null,
  "venue_id" uuid not null,
  "expires_at" timestamptz default (now()+interval '24 hours'),
  "created_at" timestamptz default now(),
  "audience" text not null default 'self',
  primary key("id")
);
create table public."collection_places" (
  "collection_id" uuid not null,
  "venue_ref" text not null,
  "note" text not null,
  "created_at" timestamptz not null default now(),
  primary key("collection_id","venue_ref")
);
create table public."comment_likes" (
  "comment_id" uuid not null,
  "user_id" uuid not null,
  "created_at" timestamptz default now(),
  primary key("comment_id","user_id")
);
create table public."comments" (
  "id" uuid not null default gen_random_uuid(),
  "post_id" uuid not null,
  "user_id" uuid not null,
  "body" text not null,
  "created_at" timestamptz default now(),
  "likes_count" int4 default 0,
  "parent_id" uuid,
  primary key("id")
);
create table public."discovery_activity" (
  "id" uuid not null default gen_random_uuid(),
  "user_id" uuid not null,
  "event" text not null,
  "target" text not null,
  "day" date not null default current_date,
  "created_at" timestamptz not null default now(),
  primary key("id")
);
create table public."dm_requests" (
  "requester_id" uuid not null,
  "target_id" uuid not null,
  "status" text not null default 'pending',
  "created_at" timestamptz not null default now(),
  primary key("requester_id","target_id")
);
create table public."event_rsvps" (
  "event_id" uuid not null,
  "user_id" uuid not null,
  "status" text not null default 'pending',
  "created_at" timestamptz default now(),
  primary key("event_id","user_id")
);
create table public."events" (
  "id" uuid not null default gen_random_uuid(),
  "venue_id" uuid,
  "organizer_id" uuid,
  "title" text not null,
  "description" text,
  "cover_url" text,
  "starts_at" timestamptz not null,
  "ends_at" timestamptz,
  "price" int4 default 0,
  "capacity" int4,
  "attendee_count" int4 default 0,
  "created_at" timestamptz default now(),
  primary key("id")
);
create table public."follow_requests" (
  "requester_id" uuid not null,
  "target_id" uuid not null,
  "created_at" timestamptz not null default now(),
  primary key("requester_id","target_id")
);
create table public."follows" (
  "id" uuid not null default gen_random_uuid(),
  "follower_id" uuid not null,
  "following_id" uuid not null,
  "created_at" timestamptz default now(),
  primary key("id"),
  unique(follower_id,following_id)
);
create table public."group_chats" (
  "id" uuid not null default gen_random_uuid(),
  "name" text not null,
  "created_by" uuid,
  "created_at" timestamptz default now(),
  primary key("id")
);
create table public."group_members" (
  "group_id" uuid not null,
  "user_id" uuid not null,
  "joined_at" timestamptz default now(),
  primary key("group_id","user_id")
);
create table public."group_messages" (
  "id" uuid not null default gen_random_uuid(),
  "group_id" uuid not null,
  "sender_id" uuid not null,
  "body" text not null,
  "created_at" timestamptz default now(),
  primary key("id")
);
create table public."likes" (
  "id" uuid not null default gen_random_uuid(),
  "user_id" uuid not null,
  "post_id" uuid not null,
  "created_at" timestamptz default now(),
  primary key("id"),
  unique(user_id,post_id)
);
create table public."live_comments" (
  "id" uuid not null default gen_random_uuid(),
  "stream_id" uuid,
  "user_id" uuid,
  "text" text not null,
  "created_at" timestamptz default now(),
  primary key("id")
);
create table public."live_streams" (
  "id" uuid not null default gen_random_uuid(),
  "user_id" uuid,
  "title" text not null,
  "is_live" bool default false,
  "viewer_count" int4 default 0,
  "thumbnail_url" text,
  "started_at" timestamptz default now(),
  "ended_at" timestamptz,
  "venue_id" uuid,
  primary key("id")
);
create table public."messages" (
  "id" uuid not null default gen_random_uuid(),
  "sender_id" uuid not null,
  "receiver_id" uuid not null,
  "body" text not null,
  "is_read" bool default false,
  "created_at" timestamptz default now(),
  "conversation_id" text,
  "story_media_url" text,
  "note_text" text,
  "venue_ref" text,
  primary key("id")
);
create table public."notes" (
  "id" uuid not null default gen_random_uuid(),
  "user_id" uuid not null,
  "text" text not null,
  "venue_id" uuid,
  "expires_at" timestamptz default (now()+interval '24 hours'),
  "created_at" timestamptz default now(),
  primary key("id")
);
create table public."notifications" (
  "id" uuid not null default gen_random_uuid(),
  "user_id" uuid not null,
  "actor_id" uuid not null,
  "actor_name" text,
  "actor_avatar" text,
  "type" text not null,
  "message" text not null,
  "is_read" bool default false,
  "created_at" timestamptz default now(),
  "post_id" uuid,
  primary key("id")
);
create table public."pilot_content" (
  "post_id" uuid not null,
  "reviewed_at" timestamptz not null default now(),
  primary key("post_id")
);
create table public."pilot_creators" (
  "user_id" uuid not null,
  "enrolled_at" timestamptz not null default now(),
  primary key("user_id")
);
create table public."pilot_participants" (
  "user_id" uuid not null,
  "enrolled_at" timestamptz not null default now(),
  primary key("user_id")
);
create table public."pilot_venues" (
  "venue_ref" text not null,
  "reviewed_at" timestamptz not null default now(),
  primary key("venue_ref")
);
create table public."place_collections" (
  "id" uuid not null default gen_random_uuid(),
  "user_id" uuid not null,
  "title" text not null,
  "is_public" bool not null default false,
  "created_at" timestamptz not null default now(),
  primary key("id")
);
create table public."posts" (
  "id" uuid not null default gen_random_uuid(),
  "user_id" uuid not null,
  "venue_id" uuid,
  "caption" text,
  "media_url" text,
  "likes_count" int4 default 0,
  "created_at" timestamptz default now(),
  "venue_name" text,
  "comments_count" int4 default 0,
  "media_type" text default 'image',
  "media_urls" text[] default '{}',
  "venue_ref" text,
  primary key("id")
);
create table public."profiles" (
  "id" uuid not null,
  "username" text not null,
  "full_name" text,
  "avatar_url" text,
  "bio" text,
  "interests" text[] default '{}',
  "is_verified" bool default false,
  "is_business" bool default false,
  "fcm_token" text,
  "updated_at" timestamptz default now(),
  "created_at" timestamptz default now(),
  "followers_count" int4 default 0,
  "following_count" int4 default 0,
  "posts_count" int4 default 0,
  "is_admin" bool default false,
  "is_banned" bool default false,
  "cover_url" text,
  "last_seen_at" timestamptz,
  "is_private" bool not null default false,
  "dm_policy" text not null default 'requests',
  primary key("id")
);
create table public."reports" (
  "id" uuid not null default gen_random_uuid(),
  "reporter_id" uuid not null,
  "target_type" text not null,
  "target_id" uuid not null,
  "reason" text not null,
  "details" text,
  "status" text default 'pending',
  "created_at" timestamptz default now(),
  primary key("id")
);
create table public."saved_posts" (
  "user_id" uuid not null,
  "post_id" uuid not null,
  "created_at" timestamptz default now(),
  primary key("user_id","post_id")
);
create table public."stories" (
  "id" uuid not null default gen_random_uuid(),
  "user_id" uuid not null,
  "media_url" text not null,
  "media_type" text default 'image',
  "caption" text,
  "duration" int4,
  "view_count" int4 default 0,
  "expires_at" timestamptz default (now()+interval '24 hours'),
  "created_at" timestamptz default now(),
  "venue_id" uuid,
  "mentions" uuid[] default '{}',
  "music_url" text,
  "music_title" text,
  "music_artist" text,
  "venue_ref" text,
  primary key("id")
);
create table public."story_likes" (
  "story_id" uuid not null,
  "user_id" uuid not null,
  "created_at" timestamptz not null default now(),
  primary key("story_id","user_id")
);
create table public."story_views" (
  "id" uuid not null default gen_random_uuid(),
  "story_id" uuid not null,
  "viewer_id" uuid not null,
  "viewed_at" timestamptz default now(),
  primary key("id")
);
create table public."venue_catalog" (
  "ref" text not null,
  "venue_id" uuid,
  "name" text not null,
  "venue_type" text,
  "address" text,
  "district" text,
  "lat" float8,
  "lng" float8,
  "cover_url" text,
  "phone" text,
  "website_url" text,
  "source_url" text,
  "source_label" text,
  "source_retrieved_at" timestamptz,
  "hours" text,
  "price_min" int4,
  "price_max" int4,
  "menu_url" text,
  "vibes" text[] not null default '{}',
  "reviewed_at" timestamptz default now(),
  "reviewed_by" uuid,
  primary key("ref"),
  unique(venue_id)
);
create table public."venue_reviews" (
  "id" uuid not null default gen_random_uuid(),
  "venue_id" uuid not null,
  "user_id" uuid not null,
  "rating" int4 not null,
  "comment" text,
  "created_at" timestamptz default now(),
  primary key("id")
);
create table public."venue_saves" (
  "user_id" uuid not null,
  "venue_ref" text not null,
  "created_at" timestamptz not null default now(),
  "legacy_import" bool not null default false,
  primary key("user_id","venue_ref")
);
create table public."venues" (
  "id" uuid not null default gen_random_uuid(),
  "name" text not null,
  "venue_type" text,
  "lat" float8,
  "lng" float8,
  "district" text,
  "description" text,
  "cover_url" text,
  "checkin_count" int4 default 0,
  "created_at" timestamptz default now(),
  "owner_id" uuid,
  "rating" numeric,
  "review_count" int4 default 0,
  "phone" text,
  "open_time" text,
  "close_time" text,
  "address" text,
  primary key("id")
);
alter table public."blocks" add constraint "blocks_blocked_id_fkey" FOREIGN KEY (blocked_id) REFERENCES profiles(id) ON DELETE CASCADE;
alter table public."blocks" add constraint "blocks_blocker_id_fkey" FOREIGN KEY (blocker_id) REFERENCES profiles(id) ON DELETE CASCADE;
alter table public."checkins" add constraint "checkins_user_id_fkey" FOREIGN KEY (user_id) REFERENCES profiles(id) ON DELETE CASCADE;
alter table public."checkins" add constraint "checkins_venue_id_fkey" FOREIGN KEY (venue_id) REFERENCES venues(id) ON DELETE CASCADE;
alter table public."collection_places" add constraint "collection_places_collection_id_fkey" FOREIGN KEY (collection_id) REFERENCES place_collections(id) ON DELETE CASCADE;
alter table public."collection_places" add constraint "collection_places_venue_ref_fkey" FOREIGN KEY (venue_ref) REFERENCES venue_catalog(ref) ON DELETE CASCADE;
alter table public."comment_likes" add constraint "comment_likes_comment_id_fkey" FOREIGN KEY (comment_id) REFERENCES comments(id) ON DELETE CASCADE;
alter table public."comment_likes" add constraint "comment_likes_user_id_fkey" FOREIGN KEY (user_id) REFERENCES profiles(id) ON DELETE CASCADE;
alter table public."comments" add constraint "comments_parent_id_fkey" FOREIGN KEY (parent_id) REFERENCES comments(id) ON DELETE CASCADE;
alter table public."comments" add constraint "comments_post_id_fkey" FOREIGN KEY (post_id) REFERENCES posts(id) ON DELETE CASCADE;
alter table public."comments" add constraint "comments_user_id_fkey" FOREIGN KEY (user_id) REFERENCES profiles(id) ON DELETE CASCADE;
alter table public."discovery_activity" add constraint "discovery_activity_user_id_fkey" FOREIGN KEY (user_id) REFERENCES profiles(id) ON DELETE CASCADE;
alter table public."dm_requests" add constraint "dm_requests_requester_id_fkey" FOREIGN KEY (requester_id) REFERENCES profiles(id) ON DELETE CASCADE;
alter table public."dm_requests" add constraint "dm_requests_target_id_fkey" FOREIGN KEY (target_id) REFERENCES profiles(id) ON DELETE CASCADE;
alter table public."event_rsvps" add constraint "event_rsvps_event_id_fkey" FOREIGN KEY (event_id) REFERENCES events(id) ON DELETE CASCADE;
alter table public."event_rsvps" add constraint "event_rsvps_user_id_fkey" FOREIGN KEY (user_id) REFERENCES profiles(id) ON DELETE CASCADE;
alter table public."events" add constraint "events_organizer_id_fkey" FOREIGN KEY (organizer_id) REFERENCES profiles(id) ON DELETE SET NULL;
alter table public."events" add constraint "events_venue_id_fkey" FOREIGN KEY (venue_id) REFERENCES venues(id) ON DELETE CASCADE;
alter table public."follow_requests" add constraint "follow_requests_requester_id_fkey" FOREIGN KEY (requester_id) REFERENCES profiles(id) ON DELETE CASCADE;
alter table public."follow_requests" add constraint "follow_requests_target_id_fkey" FOREIGN KEY (target_id) REFERENCES profiles(id) ON DELETE CASCADE;
alter table public."follows" add constraint "follows_follower_id_fkey" FOREIGN KEY (follower_id) REFERENCES profiles(id) ON DELETE CASCADE;
alter table public."follows" add constraint "follows_following_id_fkey" FOREIGN KEY (following_id) REFERENCES profiles(id) ON DELETE CASCADE;
alter table public."group_chats" add constraint "group_chats_created_by_fkey" FOREIGN KEY (created_by) REFERENCES profiles(id) ON DELETE SET NULL;
alter table public."group_members" add constraint "group_members_group_id_fkey" FOREIGN KEY (group_id) REFERENCES group_chats(id) ON DELETE CASCADE;
alter table public."group_members" add constraint "group_members_user_id_fkey" FOREIGN KEY (user_id) REFERENCES profiles(id) ON DELETE CASCADE;
alter table public."group_messages" add constraint "group_messages_group_id_fkey" FOREIGN KEY (group_id) REFERENCES group_chats(id) ON DELETE CASCADE;
alter table public."group_messages" add constraint "group_messages_sender_id_fkey" FOREIGN KEY (sender_id) REFERENCES profiles(id) ON DELETE CASCADE;
alter table public."likes" add constraint "likes_post_id_fkey" FOREIGN KEY (post_id) REFERENCES posts(id) ON DELETE CASCADE;
alter table public."likes" add constraint "likes_user_id_fkey" FOREIGN KEY (user_id) REFERENCES profiles(id) ON DELETE CASCADE;
alter table public."live_comments" add constraint "live_comments_stream_id_fkey" FOREIGN KEY (stream_id) REFERENCES live_streams(id) ON DELETE CASCADE;
alter table public."live_comments" add constraint "live_comments_user_id_fkey" FOREIGN KEY (user_id) REFERENCES profiles(id) ON DELETE CASCADE;
alter table public."live_streams" add constraint "live_streams_user_id_fkey" FOREIGN KEY (user_id) REFERENCES profiles(id) ON DELETE CASCADE;
alter table public."live_streams" add constraint "live_streams_venue_id_fkey" FOREIGN KEY (venue_id) REFERENCES venues(id) ON DELETE SET NULL;
alter table public."messages" add constraint "messages_receiver_id_fkey" FOREIGN KEY (receiver_id) REFERENCES profiles(id) ON DELETE CASCADE;
alter table public."messages" add constraint "messages_sender_id_fkey" FOREIGN KEY (sender_id) REFERENCES profiles(id) ON DELETE CASCADE;
alter table public."messages" add constraint "messages_venue_ref_fkey" FOREIGN KEY (venue_ref) REFERENCES venue_catalog(ref);
alter table public."notes" add constraint "notes_user_id_fkey" FOREIGN KEY (user_id) REFERENCES profiles(id) ON DELETE CASCADE;
alter table public."notes" add constraint "notes_venue_id_fkey" FOREIGN KEY (venue_id) REFERENCES venues(id) ON DELETE SET NULL;
alter table public."notifications" add constraint "notifications_actor_id_fkey" FOREIGN KEY (actor_id) REFERENCES profiles(id) ON DELETE CASCADE;
alter table public."notifications" add constraint "notifications_post_id_fkey" FOREIGN KEY (post_id) REFERENCES posts(id) ON DELETE CASCADE;
alter table public."notifications" add constraint "notifications_user_id_fkey" FOREIGN KEY (user_id) REFERENCES profiles(id) ON DELETE CASCADE;
alter table public."pilot_content" add constraint "pilot_content_post_id_fkey" FOREIGN KEY (post_id) REFERENCES posts(id) ON DELETE CASCADE;
alter table public."pilot_creators" add constraint "pilot_creators_user_id_fkey" FOREIGN KEY (user_id) REFERENCES profiles(id) ON DELETE CASCADE;
alter table public."pilot_participants" add constraint "pilot_participants_user_id_fkey" FOREIGN KEY (user_id) REFERENCES profiles(id) ON DELETE CASCADE;
alter table public."pilot_venues" add constraint "pilot_venues_venue_ref_fkey" FOREIGN KEY (venue_ref) REFERENCES venue_catalog(ref) ON DELETE CASCADE;
alter table public."place_collections" add constraint "place_collections_user_id_fkey" FOREIGN KEY (user_id) REFERENCES profiles(id) ON DELETE CASCADE;
alter table public."posts" add constraint "posts_user_id_fkey" FOREIGN KEY (user_id) REFERENCES profiles(id) ON DELETE CASCADE;
alter table public."posts" add constraint "posts_venue_id_fkey" FOREIGN KEY (venue_id) REFERENCES venues(id) ON DELETE SET NULL;
alter table public."posts" add constraint "posts_venue_ref_fkey" FOREIGN KEY (venue_ref) REFERENCES venue_catalog(ref);
alter table public."profiles" add constraint "profiles_id_fkey" FOREIGN KEY (id) REFERENCES auth.users(id) ON DELETE CASCADE;
alter table public."reports" add constraint "reports_reporter_id_fkey" FOREIGN KEY (reporter_id) REFERENCES profiles(id) ON DELETE CASCADE;
alter table public."saved_posts" add constraint "saved_posts_post_id_fkey" FOREIGN KEY (post_id) REFERENCES posts(id) ON DELETE CASCADE;
alter table public."saved_posts" add constraint "saved_posts_user_id_fkey" FOREIGN KEY (user_id) REFERENCES profiles(id) ON DELETE CASCADE;
alter table public."stories" add constraint "stories_user_id_fkey" FOREIGN KEY (user_id) REFERENCES profiles(id) ON DELETE CASCADE;
alter table public."stories" add constraint "stories_venue_id_fkey" FOREIGN KEY (venue_id) REFERENCES venues(id) ON DELETE SET NULL;
alter table public."stories" add constraint "stories_venue_ref_fkey" FOREIGN KEY (venue_ref) REFERENCES venue_catalog(ref);
alter table public."story_likes" add constraint "story_likes_story_id_fkey" FOREIGN KEY (story_id) REFERENCES stories(id) ON DELETE CASCADE;
alter table public."story_likes" add constraint "story_likes_user_id_fkey" FOREIGN KEY (user_id) REFERENCES auth.users(id) ON DELETE CASCADE;
alter table public."story_views" add constraint "story_views_story_id_fkey" FOREIGN KEY (story_id) REFERENCES stories(id) ON DELETE CASCADE;
alter table public."story_views" add constraint "story_views_viewer_id_fkey" FOREIGN KEY (viewer_id) REFERENCES profiles(id) ON DELETE CASCADE;
alter table public."venue_catalog" add constraint "venue_catalog_reviewed_by_fkey" FOREIGN KEY (reviewed_by) REFERENCES profiles(id) ON DELETE SET NULL;
alter table public."venue_catalog" add constraint "venue_catalog_venue_id_fkey" FOREIGN KEY (venue_id) REFERENCES venues(id) ON DELETE CASCADE;
alter table public."venue_reviews" add constraint "venue_reviews_user_id_fkey" FOREIGN KEY (user_id) REFERENCES profiles(id) ON DELETE CASCADE;
alter table public."venue_reviews" add constraint "venue_reviews_venue_id_fkey" FOREIGN KEY (venue_id) REFERENCES venues(id) ON DELETE CASCADE;
alter table public."venue_saves" add constraint "venue_saves_user_id_fkey" FOREIGN KEY (user_id) REFERENCES profiles(id) ON DELETE CASCADE;
alter table public."venue_saves" add constraint "venue_saves_venue_ref_fkey" FOREIGN KEY (venue_ref) REFERENCES venue_catalog(ref) ON DELETE CASCADE;
alter table public."venues" add constraint "venues_owner_id_fkey" FOREIGN KEY (owner_id) REFERENCES profiles(id) ON DELETE SET NULL;

-- Coarse, owner-scoped permissive component policies. Actual source migrations
-- add their restrictive guards; none of these stand in for production policies.
grant usage on schema public to anon,authenticated,service_role;
grant select,insert,update,delete on all tables in schema public to service_role;
alter default privileges in schema public grant select,insert,update,delete on tables to service_role;

alter table public."blocks" enable row level security;
alter table public."checkins" enable row level security;
grant insert,update,delete on public."checkins" to authenticated;
create policy component_owner_insert on public."checkins" for insert to authenticated with check("user_id"=auth.uid());
create policy component_owner_update on public."checkins" for update to authenticated using("user_id"=auth.uid()) with check("user_id"=auth.uid());
create policy component_owner_delete on public."checkins" for delete to authenticated using("user_id"=auth.uid());
alter table public."collection_places" enable row level security;
alter table public."comment_likes" enable row level security;
grant select on public."comment_likes" to anon,authenticated;
create policy component_read on public."comment_likes" for select to anon,authenticated using(true);
grant insert,update,delete on public."comment_likes" to authenticated;
create policy component_owner_insert on public."comment_likes" for insert to authenticated with check("user_id"=auth.uid());
create policy component_owner_update on public."comment_likes" for update to authenticated using("user_id"=auth.uid()) with check("user_id"=auth.uid());
create policy component_owner_delete on public."comment_likes" for delete to authenticated using("user_id"=auth.uid());
alter table public."comments" enable row level security;
grant select on public."comments" to anon,authenticated;
create policy component_read on public."comments" for select to anon,authenticated using(true);
grant insert,update,delete on public."comments" to authenticated;
create policy component_owner_insert on public."comments" for insert to authenticated with check("user_id"=auth.uid());
create policy component_owner_update on public."comments" for update to authenticated using("user_id"=auth.uid()) with check("user_id"=auth.uid());
create policy component_owner_delete on public."comments" for delete to authenticated using("user_id"=auth.uid());
alter table public."discovery_activity" enable row level security;
alter table public."dm_requests" enable row level security;
alter table public."event_rsvps" enable row level security;
alter table public."events" enable row level security;
grant select on public."events" to anon,authenticated;
create policy component_read on public."events" for select to anon,authenticated using(true);
grant insert,update,delete on public."events" to authenticated;
create policy component_owner_insert on public."events" for insert to authenticated with check("organizer_id"=auth.uid());
create policy component_owner_update on public."events" for update to authenticated using("organizer_id"=auth.uid()) with check("organizer_id"=auth.uid());
create policy component_owner_delete on public."events" for delete to authenticated using("organizer_id"=auth.uid());
alter table public."follow_requests" enable row level security;
alter table public."follows" enable row level security;
grant select on public."follows" to anon,authenticated;
create policy component_read on public."follows" for select to anon,authenticated using(true);
grant insert,update,delete on public."follows" to authenticated;
create policy component_owner_insert on public."follows" for insert to authenticated with check("follower_id"=auth.uid());
create policy component_owner_update on public."follows" for update to authenticated using("follower_id"=auth.uid()) with check("follower_id"=auth.uid());
create policy component_owner_delete on public."follows" for delete to authenticated using("follower_id"=auth.uid());
alter table public."group_chats" enable row level security;
grant select on public."group_chats" to authenticated;
create policy component_group_read on public."group_chats" for select to authenticated using(exists(select 1 from public.group_members m where m.group_id="group_chats".id and m.user_id=auth.uid()));
grant insert,update,delete on public."group_chats" to authenticated;
create policy component_owner_insert on public."group_chats" for insert to authenticated with check("created_by"=auth.uid());
create policy component_owner_update on public."group_chats" for update to authenticated using("created_by"=auth.uid()) with check("created_by"=auth.uid());
create policy component_owner_delete on public."group_chats" for delete to authenticated using("created_by"=auth.uid());
alter table public."group_members" enable row level security;
grant select on public.group_members to authenticated;
create policy component_member_read on public.group_members for select to authenticated using(user_id=auth.uid());
alter table public."group_messages" enable row level security;
grant select on public."group_messages" to authenticated;
create policy component_group_read on public."group_messages" for select to authenticated using(exists(select 1 from public.group_members m where m.group_id="group_messages".group_id and m.user_id=auth.uid()));
grant insert,update,delete on public."group_messages" to authenticated;
create policy component_owner_insert on public."group_messages" for insert to authenticated with check("sender_id"=auth.uid());
create policy component_owner_update on public."group_messages" for update to authenticated using("sender_id"=auth.uid()) with check("sender_id"=auth.uid());
create policy component_owner_delete on public."group_messages" for delete to authenticated using("sender_id"=auth.uid());
alter table public."likes" enable row level security;
grant select on public."likes" to anon,authenticated;
create policy component_read on public."likes" for select to anon,authenticated using(true);
grant insert,update,delete on public."likes" to authenticated;
create policy component_owner_insert on public."likes" for insert to authenticated with check("user_id"=auth.uid());
create policy component_owner_update on public."likes" for update to authenticated using("user_id"=auth.uid()) with check("user_id"=auth.uid());
create policy component_owner_delete on public."likes" for delete to authenticated using("user_id"=auth.uid());
alter table public."live_comments" enable row level security;
grant select on public."live_comments" to anon,authenticated;
create policy component_read on public."live_comments" for select to anon,authenticated using(true);
alter table public."live_streams" enable row level security;
grant select on public."live_streams" to anon,authenticated;
create policy component_read on public."live_streams" for select to anon,authenticated using(true);
alter table public."messages" enable row level security;
grant select on public.messages to authenticated;
create policy component_message_read on public.messages for select to authenticated using(auth.uid() in (sender_id,receiver_id));
grant insert,update,delete on public."messages" to authenticated;
create policy component_owner_insert on public."messages" for insert to authenticated with check("sender_id"=auth.uid());
create policy component_owner_update on public."messages" for update to authenticated using("sender_id"=auth.uid()) with check("sender_id"=auth.uid());
create policy component_owner_delete on public."messages" for delete to authenticated using("sender_id"=auth.uid());
alter table public."notes" enable row level security;
grant select on public.notes to authenticated;
create policy component_note_read on public.notes for select to authenticated using(user_id=auth.uid());
grant insert,update,delete on public."notes" to authenticated;
create policy component_owner_insert on public."notes" for insert to authenticated with check("user_id"=auth.uid());
create policy component_owner_update on public."notes" for update to authenticated using("user_id"=auth.uid()) with check("user_id"=auth.uid());
create policy component_owner_delete on public."notes" for delete to authenticated using("user_id"=auth.uid());
alter table public."notifications" enable row level security;
grant insert,update,delete on public."notifications" to authenticated;
create policy component_owner_insert on public."notifications" for insert to authenticated with check("user_id"=auth.uid());
create policy component_owner_update on public."notifications" for update to authenticated using("user_id"=auth.uid()) with check("user_id"=auth.uid());
create policy component_owner_delete on public."notifications" for delete to authenticated using("user_id"=auth.uid());
alter table public."pilot_content" enable row level security;
alter table public."pilot_creators" enable row level security;
alter table public."pilot_participants" enable row level security;
alter table public."pilot_venues" enable row level security;
alter table public."place_collections" enable row level security;
alter table public."posts" enable row level security;
grant select on public."posts" to anon,authenticated;
create policy component_read on public."posts" for select to anon,authenticated using(true);
grant insert,update,delete on public."posts" to authenticated;
create policy component_owner_insert on public."posts" for insert to authenticated with check("user_id"=auth.uid());
create policy component_owner_update on public."posts" for update to authenticated using("user_id"=auth.uid()) with check("user_id"=auth.uid());
create policy component_owner_delete on public."posts" for delete to authenticated using("user_id"=auth.uid());
alter table public."profiles" enable row level security;
grant select on public."profiles" to anon,authenticated;
create policy component_read on public."profiles" for select to anon,authenticated using(true);
grant insert,update,delete on public."profiles" to authenticated;
create policy component_owner_insert on public."profiles" for insert to authenticated with check("id"=auth.uid());
create policy component_owner_update on public."profiles" for update to authenticated using("id"=auth.uid()) with check("id"=auth.uid());
create policy component_owner_delete on public."profiles" for delete to authenticated using("id"=auth.uid());
alter table public."reports" enable row level security;
grant select on public.reports to authenticated;
create policy component_report_read on public.reports for select to authenticated using(reporter_id=auth.uid());
grant insert,update,delete on public."reports" to authenticated;
create policy component_owner_insert on public."reports" for insert to authenticated with check("reporter_id"=auth.uid());
create policy component_owner_update on public."reports" for update to authenticated using("reporter_id"=auth.uid()) with check("reporter_id"=auth.uid());
create policy component_owner_delete on public."reports" for delete to authenticated using("reporter_id"=auth.uid());
alter table public."saved_posts" enable row level security;
grant insert,update,delete on public."saved_posts" to authenticated;
create policy component_owner_insert on public."saved_posts" for insert to authenticated with check("user_id"=auth.uid());
create policy component_owner_update on public."saved_posts" for update to authenticated using("user_id"=auth.uid()) with check("user_id"=auth.uid());
create policy component_owner_delete on public."saved_posts" for delete to authenticated using("user_id"=auth.uid());
alter table public."stories" enable row level security;
grant select on public."stories" to anon,authenticated;
create policy component_read on public."stories" for select to anon,authenticated using(true);
grant insert,update,delete on public."stories" to authenticated;
create policy component_owner_insert on public."stories" for insert to authenticated with check("user_id"=auth.uid());
create policy component_owner_update on public."stories" for update to authenticated using("user_id"=auth.uid()) with check("user_id"=auth.uid());
create policy component_owner_delete on public."stories" for delete to authenticated using("user_id"=auth.uid());
alter table public."story_likes" enable row level security;
grant select on public."story_likes" to anon,authenticated;
create policy component_read on public."story_likes" for select to anon,authenticated using(true);
grant insert,update,delete on public."story_likes" to authenticated;
create policy component_owner_insert on public."story_likes" for insert to authenticated with check("user_id"=auth.uid());
create policy component_owner_update on public."story_likes" for update to authenticated using("user_id"=auth.uid()) with check("user_id"=auth.uid());
create policy component_owner_delete on public."story_likes" for delete to authenticated using("user_id"=auth.uid());
alter table public."story_views" enable row level security;
grant insert,update,delete on public."story_views" to authenticated;
create policy component_owner_insert on public."story_views" for insert to authenticated with check("viewer_id"=auth.uid());
create policy component_owner_update on public."story_views" for update to authenticated using("viewer_id"=auth.uid()) with check("viewer_id"=auth.uid());
create policy component_owner_delete on public."story_views" for delete to authenticated using("viewer_id"=auth.uid());
alter table public."venue_catalog" enable row level security;
grant select on public."venue_catalog" to anon,authenticated;
create policy component_read on public."venue_catalog" for select to anon,authenticated using(true);
alter table public."venue_reviews" enable row level security;
grant select on public."venue_reviews" to anon,authenticated;
create policy component_read on public."venue_reviews" for select to anon,authenticated using(true);
grant insert,update,delete on public."venue_reviews" to authenticated;
create policy component_owner_insert on public."venue_reviews" for insert to authenticated with check("user_id"=auth.uid());
create policy component_owner_update on public."venue_reviews" for update to authenticated using("user_id"=auth.uid()) with check("user_id"=auth.uid());
create policy component_owner_delete on public."venue_reviews" for delete to authenticated using("user_id"=auth.uid());
alter table public."venue_saves" enable row level security;
alter table public."venues" enable row level security;
grant select on public."venues" to anon,authenticated;
create policy component_read on public."venues" for select to anon,authenticated using(true);
grant insert,update,delete on public."venues" to authenticated;
create policy component_owner_insert on public."venues" for insert to authenticated with check("owner_id"=auth.uid());
create policy component_owner_update on public."venues" for update to authenticated using("owner_id"=auth.uid()) with check("owner_id"=auth.uid());
create policy component_owner_delete on public."venues" for delete to authenticated using("owner_id"=auth.uid());
commit;
