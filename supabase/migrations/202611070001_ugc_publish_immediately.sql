-- Publish-immediately (post-moderation) for ordinary UGC, with App Store Guideline 1.2
-- safeguards: server text filter hold, reporter-only hide and a distinct-reporter hold.
-- No content rows, column defaults or hash-pinned RPCs change. Venues/events stay pre-moderated.
-- Rollback (not a migration): tools/deployment/ugc_publish_immediately_rollback.sql
begin;
set local lock_timeout='5s';
set local statement_timeout='60s';

-- Requires the reviewed 004/009 objects, the 009 audit patch, Auth account
-- creation times and the 202611040001 PT409 forward fix.
do $$ begin
 if to_regprocedure('public.ugc_content_guard()') is null or to_regprocedure('public.admin_console_review(text,uuid,uuid,text,text)') is null
  or to_regprocedure('public.admin_console_review_queue(text,text,integer,integer)') is null or to_regprocedure('public.report_ugc(text,uuid,text,text)') is null
  or to_regprocedure('public.interaction_note_write_guard()') is null or to_regprocedure('public.create_comment_notification()') is null
  or to_regprocedure('public.admin_console_audit_change()') is null
  or to_regclass('admin_private.ugc_action_context') is null or to_regclass('admin_private.ugc_profile_drafts') is null then
  raise exception 'Install and verify 004 and 009 before publish-immediately';
 end if;
 if not exists(select 1 from pg_attribute where attrelid='auth.users'::regclass and attname='created_at' and not attisdropped) then
  raise exception 'auth.users.created_at is required for reporter eligibility';
 end if;
 if not exists(select 1 from pg_proc where oid=to_regprocedure('public.admin_console_review(text,uuid,uuid,text,text)') and prosrc like '%''PT409''%') then
  raise exception 'Apply 202611040001_business_conflict_http.sql first';
 end if;
end $$;

-- Private state only (admin_private): no public tables, FKs or client RPCs.
-- Settings and seed terms are written only when their table is first created, so
-- re-running this migration never restores a term or setting the owner removed.
do $$ begin
 -- Single-row settings. A missing row falls back to review-before-publish.
 if to_regclass('admin_private.ugc_publish_config') is null then
  create table admin_private.ugc_publish_config(
   singleton boolean primary key default true check(singleton),
   publish_immediately boolean not null default true,
   report_hide_threshold integer not null default 3 check(report_hide_threshold between 2 and 50),
   profile_report_hide_threshold integer not null default 5 check(profile_report_hide_threshold between 2 and 50),
   -- A report counts towards a hold only if its reporter's Auth account was at
   -- least this old when reporting and the reporter's profile is public.
   reporter_min_account_age interval not null default interval '24 hours' check(reporter_min_account_age between interval '0 seconds' and interval '30 days'),
   hold_links boolean not null default true,
   hold_phone_numbers boolean not null default true,
   updated_at timestamptz not null default now());
  insert into admin_private.ugc_publish_config(singleton) values(true);
 end if;
 -- Owner-extendable blocked terms. Seed only clearly severe, well-attested terms;
 -- ordinary profanity is deliberately excluded to limit false holds. 'героин' is
 -- a word plus explicit inflection stems so Russian 'героиня' (heroine) passes.
 if to_regclass('admin_private.ugc_blocked_terms') is null then
  create table admin_private.ugc_blocked_terms(
   term text primary key check(term=btrim(term) and char_length(term) between 2 and 100),
   match_mode text not null default 'prefix' check(match_mode in ('word','prefix','substring')),
   category text not null default 'custom' check(char_length(category) between 1 and 40),
   created_at timestamptz not null default now());
  insert into admin_private.ugc_blocked_terms(term,match_mode,category) values
   ('nigger','prefix','slur'),('faggot','prefix','slur'),('hujaa','prefix','slur'),('khujaa','prefix','slur'),
   ('хужаа','prefix','slur'),('пидар','prefix','slur'),('пидор','prefix','slur'),
   ('child porn','substring','csam'),('kiddie porn','substring','csam'),('pthc','word','csam'),
   ('kill yourself','prefix','self_harm'),
   ('cocaine','prefix','drugs'),('heroin','word','drugs'),('meth','word','drugs'),('methamphetamine','prefix','drugs'),
   ('кокаин','prefix','drugs'),('героин','word','drugs'),('героины','prefix','drugs'),('героинд','prefix','drugs'),('героино','prefix','drugs'),
   ('героинт','prefix','drugs'),('героина','prefix','drugs'),('героину','prefix','drugs'),('метамфетамин','prefix','drugs'),('хар тамхи','substring','drugs');
 end if;
end $$;
-- Report hold bookkeeping per target. reports_cleared_at is the last moderator
-- decision; only reports created after it count towards a new hold. rejected_at
-- is the last moderator rejection (cleared by an approval): author edits never
-- publish a rejected item again until a moderator approves it.
create table if not exists admin_private.ugc_report_holds(
 kind text not null check(kind in ('post','story','comment','event','review','profile','note','collection','venue')),
 target_id uuid not null, report_count integer not null default 0 check(report_count>=0),
 report_held_at timestamptz, reports_cleared_at timestamptz, previously_published boolean not null default false,
 rejected_at timestamptz,
 updated_at timestamptz not null default clock_timestamp(), primary key(kind,target_id));
-- Transaction-scoped authorization for the report-threshold hold write. Clients
-- cannot write admin_private, so a hold cannot be forged.
create table if not exists admin_private.ugc_hold_context(
 transaction_id bigint not null,kind text not null,target_id uuid not null,primary key(transaction_id,kind,target_id));
revoke all on admin_private.ugc_publish_config,admin_private.ugc_blocked_terms,admin_private.ugc_report_holds,admin_private.ugc_hold_context from public,anon,authenticated;
comment on table admin_private.ugc_blocked_terms is 'Owner-extendable: insert into admin_private.ugc_blocked_terms(term,match_mode,category) values (''term'',''prefix'',''custom'') on conflict do nothing; modes: word | prefix (default; allows suffixes) | substring (ignores spaces). Latin and Cyrillic look-alike letters match each other, so prefer word mode for short terms.';
comment on table admin_private.ugc_publish_config is 'Single row. publish_immediately=false restores review-before-publish for new writes.';

-- Locale-independent case folding and normalization. Explicit code-point lists
-- behave the same on hosted ICU and offline PGlite (no lower(), \m, [[:alpha:]] or ~*).
-- normalize() uses PostgreSQL's built-in Unicode tables, not the locale.
create or replace function public.ugc_fold_case(p_value text) returns text
language sql immutable parallel safe set search_path=pg_catalog,public,pg_temp as $$
 select translate(coalesce(p_value,''),'ABCDEFGHIJKLMNOPQRSTUVWXYZАБВГДЕЁЖЗИЙКЛМНОӨПРСТУҮФХЦЧШЩЪЫЬЭЮЯ','abcdefghijklmnopqrstuvwxyzабвгдеёжзийклмноөпрстуүфхцчшщъыьэюя')
$$;
-- Compatibility-decomposes (fullwidth and styled letters become ASCII, accents
-- split off), then deletes combining marks, invisible format characters
-- (zero-width, direction marks, invisible operators, variation selectors, tags)
-- and soft hyphens. Cyrillic й is protected via U+E000 so it stays distinct from и.
create or replace function public.ugc_strip_marks(p_value text) returns text
language sql immutable parallel safe set search_path=pg_catalog,public,pg_temp as $$
 select translate(regexp_replace(normalize(translate(normalize(coalesce(p_value,''),NFC),'йЙ',chr(57344)||chr(57344)),NFKD),
  '['||chr(173)||chr(768)||'-'||chr(879)||chr(1155)||'-'||chr(1161)||chr(6155)||'-'||chr(6159)||chr(6832)||'-'||chr(6911)
   ||chr(8203)||'-'||chr(8207)||chr(8234)||'-'||chr(8238)||chr(8288)||'-'||chr(8292)||chr(8294)||'-'||chr(8303)||chr(8400)||'-'||chr(8447)
   ||chr(65024)||'-'||chr(65039)||chr(65056)||'-'||chr(65071)||chr(65279)||chr(917504)||'-'||chr(917631)||chr(917760)||'-'||chr(917999)||']','','g'),
  chr(57344),'й')
$$;
-- After stripping marks: maps ё 0 1 3 4 5 7 @ $ to e o i e a s t a s and the
-- Cyrillic look-alikes а е о р с у х к м т в н to Latin a e o p c y x k m t b h
-- (applied to terms and text alike, so mixed-script spellings match), and turns
-- every other character into a single space with space padding. Mongolian ө/ү
-- are not mapped. chr(36) is '$' (avoids $-quoting).
create or replace function public.ugc_normalize_text(p_value text) returns text
language sql immutable parallel safe set search_path=pg_catalog,public,pg_temp as $$
 select ' '||btrim(regexp_replace(translate(public.ugc_fold_case(public.ugc_strip_marks(p_value)),'ё013457@'||chr(36)||'аеорсухкмтвн','eoieastas'||'aeopcyxkmtbh'),
  '[^abcdefghijklmnopqrstuvwxyz0123456789абвгдежзийклмноөпрстуүфхцчшщъыьэюя]+',' ','g'))||' '
$$;

-- Returns null when clean, else {"reason":"blocked_term","term":t} | {"reason":"link"} | {"reason":"phone"}.
-- With p_old, only text fields that changed are screened. Every public text field
-- is checked for blocked terms; links/phones in every field except usernames. A
-- post's venue_name equal to its approved catalog place name is not user text.
create or replace function public.ugc_screen_text(p_kind text,p_candidate jsonb,p_old jsonb default null) returns jsonb
language plpgsql stable security definer set search_path=pg_catalog,public,pg_temp as $$
declare cfg admin_private.ugc_publish_config%rowtype; fields text[]; k text; v text; all_text text:=''; contact_text text:=''; norm text; joined text; plain text; folded text; hit text;
begin
 fields:=case p_kind when 'post' then array['caption','venue_name'] when 'story' then array['caption','music_title','music_artist'] when 'comment' then array['body']
  when 'note' then array['text'] when 'review' then array['comment'] when 'collection' then array['title','name','description']
  when 'profile' then array['username','full_name','bio','interests'] else array[]::text[] end;
 foreach k in array fields loop
  v:=p_candidate->>k;
  if v is null or btrim(v)='' or (p_old is not null and (p_old->>k) is not distinct from v) then continue; end if;
  if k='venue_name' and exists(select 1 from public.venue_catalog vc where vc.ref=p_candidate->>'venue_ref' and vc.name=v and vc.moderation_status='approved') then continue; end if;
  all_text:=all_text||' '||v;
  if k<>'username' then contact_text:=contact_text||' '||v; end if;
 end loop;
 if all_text='' then return null; end if;
 norm:=public.ugc_normalize_text(all_text);
 -- Letter-spaced spellings ("c o c a i n e", "c.o.c.a.i.n.e") are also tested joined.
 joined:=regexp_replace(norm,'(?<= [^ ]) (?=[^ ] )','','g');
 select t.term into hit from admin_private.ugc_blocked_terms t cross join lateral (select btrim(public.ugc_normalize_text(t.term)) tn) n
  where n.tn<>'' and case t.match_mode when 'word' then strpos(norm,' '||n.tn||' ')>0 or strpos(joined,' '||n.tn||' ')>0
   when 'prefix' then strpos(norm,' '||n.tn)>0 or strpos(joined,' '||n.tn)>0
   else strpos(replace(norm,' ',''),replace(n.tn,' ',''))>0 end order by t.term limit 1;
 if hit is not null then return jsonb_build_object('reason','blocked_term','term',hit); end if;
 if contact_text='' then return null; end if;
 select * into cfg from admin_private.ugc_publish_config where singleton;
 plain:=public.ugc_strip_marks(contact_text);
 folded:=public.ugc_fold_case(plain);
 -- Scheme/www, or a domain ending. Endings that are also ordinary words (Live,
 -- Club, App, Me...) count only in lower case or before '/', so "Tonight.Live"
 -- and "Mega.Club" (missing space after a full stop) are not held.
 if coalesce(cfg.hold_links,true) and (folded ~ '(https?://|www[.])' or folded ~ '[a-z0-9-][.](com|net|org|biz|io|ly|gg|xyz|ru|mn)([^a-z0-9]|$)'
    or plain ~ '[A-Za-z0-9-][.](info|me|link|top|shop|site|online|club|app|cc|to|vip|bet|live|tv|co)([^A-Za-z0-9]|$)'
    or folded ~ '[a-z0-9-][.](info|me|link|top|shop|site|online|club|app|cc|to|vip|bet|live|tv|co)/') then
  return jsonb_build_object('reason','link'); end if;
 -- Mongolian 8-digit numbers (optional +976) unless followed by a price unit or
 -- shaped like a price range ("7000-9000", "6000 9000": both halves end in 00);
 -- any + and 8+ digits.
 if coalesce(cfg.hold_phone_numbers,true) and (folded ~ '(^|[^0-9])([+]?976[ .-]?)?(?![5-9][0-9]00[ .-][0-9]{2}00([^0-9]|$))[5-9][0-9]{3}[ .-]?[0-9]{4}(?![0-9]| ?(₮|төг|tug|tg|mnt))'
    or folded ~ '[+][0-9][0-9 .-]{7,16}[0-9]') then
  return jsonb_build_object('reason','phone'); end if;
 return null;
end $$;
revoke all on function public.ugc_fold_case(text),public.ugc_strip_marks(text),public.ugc_normalize_text(text),public.ugc_screen_text(text,jsonb,jsonb) from public,anon,authenticated;

-- The viewer's own reported ids of one type (any report status). Used by the
-- reporter-hide policies below; evaluated once per query as an InitPlan.
create or replace function public.ugc_viewer_reported_ids(p_target_type text) returns uuid[]
language sql stable security definer set search_path=pg_catalog,public,pg_temp as $$
 select coalesce(array_agg(distinct r.target_id),'{}'::uuid[]) from public.reports r where r.reporter_id=auth.uid() and r.target_type=p_target_type
$$;
revoke all on function public.ugc_viewer_reported_ids(text) from public;
grant execute on function public.ugc_viewer_reported_ids(text) to anon,authenticated;

-- Fixes the existing 004 defect: a moderator decision or a report hold may change
-- only the review columns of a note and keeps its created_at/expires_at lifetime.
-- The author path is unchanged. The trigger itself is not recreated.
create or replace function public.interaction_note_write_guard() returns trigger
language plpgsql security definer set search_path=pg_catalog,public,pg_temp as $$
begin
  if public.admin_console_maintenance() then return new; end if;
  if tg_op='UPDATE' then
    if (public.is_admin() and exists(select 1 from admin_private.ugc_action_context c where c.transaction_id=txid_current() and c.actor_id=auth.uid() and c.kind='note' and c.target_id=old.id))
        or exists(select 1 from admin_private.ugc_hold_context h where h.transaction_id=txid_current() and h.kind='note' and h.target_id=old.id) then
      if (to_jsonb(new)-array['moderation_status','moderation_version','moderation_submitted_at']) is distinct from (to_jsonb(old)-array['moderation_status','moderation_version','moderation_submitted_at']) then
        raise exception 'Review decisions cannot edit notes' using errcode='42501';
      end if;
      return new;
    end if;
  end if;
  if not public.social_active() or new.user_id is distinct from auth.uid() then
    raise exception 'Active note owner required' using errcode='42501';
  end if;
  new.text:=regexp_replace(new.text,'^[[:space:]]+|[[:space:]]+$','','g');
  -- Flutter's 100-character composer counts graphemes; PostgreSQL counts code
  -- points. Keep a bounded storage limit without rejecting combined emoji.
  if new.text is null or char_length(new.text) not between 1 and 1000 then
    raise exception 'Note text is empty or too long' using errcode='22023';
  end if;
  new.created_at:=now();
  new.expires_at:=now()+interval '24 hours';
  return new;
end $$;
revoke all on function public.interaction_note_write_guard() from public,anon,authenticated;

-- Publish on save unless held. Lines from 009 are kept verbatim; the 009
-- triggers (ugc_content_guard on nine tables) stay as installed. OLD is only
-- referenced inside tg_op='UPDATE' branches; the INSERT path adds no side-table rows.
create or replace function public.ugc_content_guard() returns trigger
language plpgsql security definer set search_path=pg_catalog,public,pg_temp as $$
declare c admin_private.ugc_action_context%rowtype; candidate jsonb; old_public jsonb; changed boolean; media_value text; media_owner text; media_key text; origin text;
 cfg admin_private.ugc_publish_config%rowtype; screen jsonb; screen_base jsonb; report_held boolean; prior_rejected boolean; new_media boolean:=false;
 review_columns text[]:=array['moderation_status','moderation_version','moderation_submitted_at','moderation_public_ready'];
begin
 if public.admin_console_maintenance() then return new; end if;
 if tg_op='UPDATE' then
  if new.id is distinct from old.id or (to_jsonb(new)->tg_argv[0]) is distinct from (to_jsonb(old)->tg_argv[0]) then
   raise exception 'Content identity cannot be reassigned' using errcode='42501';
  end if;
  select * into c from admin_private.ugc_action_context where transaction_id=txid_current() and actor_id=auth.uid() and target_id=old.id and kind=tg_argv[1];
  if found and public.is_admin() then
   if c.decision not in ('approved','rejected') or new.moderation_status is distinct from c.decision then
    raise exception 'Invalid review transition' using errcode='42501'; end if;
   -- A moderator decision clears any report hold (only later reports count) and
   -- records a rejection outside the row, so author edits cannot shed it.
   insert into admin_private.ugc_report_holds(kind,target_id,reports_cleared_at,rejected_at,updated_at)
    values(tg_argv[1],old.id,clock_timestamp(),case when c.decision='rejected' then clock_timestamp() end,clock_timestamp())
    on conflict(kind,target_id) do update set report_held_at=null,report_count=0,reports_cleared_at=excluded.reports_cleared_at,rejected_at=excluded.rejected_at,updated_at=excluded.updated_at;
   return new;
  end if;
  -- A report-threshold hold may only move the row to pending, nothing else.
  if exists(select 1 from admin_private.ugc_hold_context h where h.transaction_id=txid_current() and h.kind=tg_argv[1] and h.target_id=old.id) then
   if new.moderation_status is distinct from 'pending' or new.moderation_version is distinct from old.moderation_version
      or (to_jsonb(new)-review_columns) is distinct from (to_jsonb(old)-review_columns) then
    raise exception 'Invalid report hold transition' using errcode='42501'; end if;
   return new;
  end if;
  if new.moderation_status is distinct from old.moderation_status or new.moderation_version is distinct from old.moderation_version or new.moderation_submitted_at is distinct from old.moderation_submitted_at
     or (tg_table_name='profiles' and (to_jsonb(new)->'moderation_public_ready') is distinct from (to_jsonb(old)->'moderation_public_ready')) then
   raise exception 'Review state requires a moderator decision' using errcode='42501';
  end if;
 end if;
 candidate:=public.ugc_public_fields(tg_table_name,to_jsonb(new));
 if pg_column_size(candidate)>65536 then raise exception 'Public content is too large' using errcode='22023'; end if;
 old_public:=case when tg_op='UPDATE' then public.ugc_public_fields(tg_table_name,to_jsonb(old)) else null end;
 changed:=tg_op='INSERT' or candidate is distinct from old_public;
 if changed then
  select storage_origin into strict origin from admin_private.ugc_media_config where singleton;
  for media_key,media_value in select key,value #>> '{}' from jsonb_each(candidate) where key in ('media_url','avatar_url','cover_url','music_url')
   union all select e.key,v #>> '{}' from jsonb_each(candidate) e cross join lateral jsonb_array_elements(case when jsonb_typeof(e.value)='array' then e.value else '[]'::jsonb end) v where e.key in ('media_urls','photos') loop
   if media_value is null or media_value='' then continue; end if;
   -- Editing text never forces replacement of an unchanged historical asset.
   if tg_op='UPDATE' and ((media_key in ('media_urls','photos') and coalesce(old_public->media_key,'[]'::jsonb) @> jsonb_build_array(media_value))
     or (media_key not in ('media_urls','photos') and old_public->>media_key=media_value)) then continue; end if;
   if tg_table_name='profiles' and media_key='avatar_url' and media_value in ('nightowl://avatar/young-man','nightowl://avatar/young-woman','nightowl://avatar/older-man','nightowl://avatar/older-woman') then continue; end if;
   -- New media must use our immutable owned Storage namespace. No expiring
   -- signed URL, attacker-origin lookalike, redirect or external URL is saved.
   if not starts_with(media_value,origin||'/storage/v1/object/public/') or
     substring(media_value from char_length(origin)+1) !~ '^/storage/v1/object/public/(posts|stories|avatars|venues)/[0-9a-fA-F-]{36}/[A-Za-z0-9_./-]+$' or
     substring(media_value from char_length(origin)+1) ~ '(^|/)[.]{1,2}(/|$)|//' then
    raise exception 'New media must use the configured owned Storage origin' using errcode='42501';
   end if;
   media_owner:=split_part(substring(media_value from char_length(origin)+char_length('/storage/v1/object/public/')+1),'/',2);
   if media_owner is distinct from to_jsonb(new)->>tg_argv[0] then
    raise exception 'Media must belong to its submitting author' using errcode='42501';
   end if;
   -- An edit that adds media not in the previous version (no image filter exists).
   if tg_op='UPDATE' then new_media:=true; end if;
  end loop;
 end if;
 select * into cfg from admin_private.ugc_publish_config where singleton;
 -- Report hold and moderator rejection live outside the row. A row rejected by a
 -- path that left no record (e.g. before this migration) is recorded on its first edit.
 select h.report_held_at is not null,h.rejected_at is not null into report_held,prior_rejected
  from admin_private.ugc_report_holds h where h.kind=tg_argv[1] and h.target_id=new.id;
 report_held:=coalesce(report_held,false);prior_rejected:=coalesce(prior_rejected,false);
 if tg_op='UPDATE' then
  if old.moderation_status='rejected' and not prior_rejected then
   prior_rejected:=true;
   insert into admin_private.ugc_report_holds(kind,target_id,rejected_at,updated_at) values(tg_argv[1],old.id,clock_timestamp(),clock_timestamp())
    on conflict(kind,target_id) do update set rejected_at=excluded.rejected_at,updated_at=excluded.updated_at;
  end if;
 end if;
 -- Private collections stay approved, but a moderator rejection sticks.
 if tg_table_name='place_collections' and not coalesce((to_jsonb(new)->>'is_public')::boolean,false) then
  new.moderation_status:=case when prior_rejected then 'rejected' else 'approved' end;
  if changed then new.moderation_version:=gen_random_uuid(); end if;
  return new;
 end if;
 if not changed then return new; end if;
 new.moderation_status:='pending';new.moderation_version:=gen_random_uuid();new.moderation_submitted_at:=clock_timestamp();
 -- Venues and events keep exact 009 pre-moderation.
 if coalesce(cfg.publish_immediately,false) and tg_argv[1] not in ('event','venue') then
  if tg_op='UPDATE' then
   -- Screen only changed text of an approved, publicly visible version; otherwise screen everything.
   if old.moderation_status='approved' and (tg_table_name<>'profiles' or coalesce((to_jsonb(old)->>'moderation_public_ready')::boolean,false))
      and (tg_table_name<>'place_collections' or coalesce((old_public->>'is_public')::boolean,false)) then screen_base:=old_public; end if;
  end if;
  screen:=public.ugc_screen_text(tg_argv[1],candidate,screen_base);
  -- New media on an edited post, story or collection waits for a moderator;
  -- profile photo changes publish like other profile fields.
  if screen is null and not report_held and not prior_rejected and not (new_media and tg_table_name in ('posts','stories','place_collections')) then
   new.moderation_status:='approved';
   if tg_table_name='profiles' then
    new:=jsonb_populate_record(new,jsonb_build_object('moderation_public_ready',true));
    -- Only a real UPDATE replaces a held draft. The INSERT half of an upsert
    -- (build 3 saves profiles with ON CONFLICT DO UPDATE) must not touch it.
    if tg_op='UPDATE' then delete from admin_private.ugc_profile_drafts where profile_id=new.id; end if;
   end if;
   return new;
  end if;
 end if;
 -- Held (or pre-moderated): 009 profile handling keeps the approved identity public.
  if tg_table_name='profiles' then
   if tg_op='INSERT' then new:=jsonb_populate_record(new,jsonb_build_object('moderation_public_ready',false));
   elsif old.moderation_public_ready then
    insert into admin_private.ugc_profile_drafts(profile_id,candidate) values(old.id,candidate)
     on conflict(profile_id) do update set candidate=ugc_profile_drafts.candidate ||
      (select coalesce(jsonb_object_agg(key,value),'{}'::jsonb) from jsonb_each(excluded.candidate) where value is distinct from old_public->key);
    -- Keep the approved public identity visible until its replacement passes.
    new:=jsonb_populate_record(new,old_public);
   end if;
  end if;
 return new;
end $$;
revoke all on function public.ugc_content_guard() from public,anon,authenticated;

-- Same as 009, plus no second notification when a comment that was already
-- published is restored after a report hold. The on_comment_notify trigger is unchanged.
create or replace function public.create_comment_notification() returns trigger
language plpgsql security definer set search_path=pg_catalog,public,pg_temp as $$
declare target uuid; name text; parent uuid;
begin
 if new.moderation_status<>'approved' or (tg_op='UPDATE' and old.moderation_status='approved') then return new; end if;
 if tg_op='UPDATE' and exists(select 1 from admin_private.ugc_report_holds h where h.kind='comment' and h.target_id=new.id and h.previously_published) then return new; end if;
 parent:=nullif(to_jsonb(new)->>'parent_id','')::uuid;
 select username into name from public.profiles where id=new.user_id;
 if parent is not null then select user_id into target from public.comments where id=parent;
 else select user_id into target from public.posts where id=new.post_id; end if;
 if target is null or target=new.user_id then return new; end if;
 insert into public.notifications(user_id,actor_id,actor_name,type,message,post_id)
 values(target,new.user_id,name,'comment',coalesce(name,'Хэн нэгэн')||' таны постод сэтгэгдэл бичлээ',new.post_id);
 return new;
end $$;
revoke all on function public.create_comment_notification() from public,anon,authenticated;

-- Distinct-reporter hold. Counts pending reports created after the last moderator
-- decision by established reporters only: not the author, not banned, a public
-- profile, and an Auth account at least reporter_min_account_age old when the
-- report was made (throwaway accounts cannot hide others' content). Event, venue
-- and message reports only queue. Any failure is a WARNING: the report always saves.
create or replace function public.ugc_report_threshold() returns trigger
language plpgsql security definer set search_path=pg_catalog,public,pg_temp as $$
declare k text; tbl text; owner_col text; cfg admin_private.ugc_publish_config%rowtype; h admin_private.ugc_report_holds%rowtype;
 row_status text; row_public boolean; visible boolean; author uuid; n integer; threshold integer;
begin
 if public.admin_console_maintenance() or new.status is distinct from 'pending' then return null; end if;
 k:=case new.target_type when 'post' then 'post' when 'story' then 'story' when 'comment' then 'comment' when 'review' then 'review'
  when 'note' then 'note' when 'collection' then 'collection' when 'user' then 'profile' end;
 if k is null then return null; end if;
 select * into cfg from admin_private.ugc_publish_config where singleton;
 if not found then return null; end if;
 tbl:=case k when 'post' then 'posts' when 'story' then 'stories' when 'comment' then 'comments' when 'review' then 'venue_reviews'
  when 'note' then 'notes' when 'collection' then 'place_collections' else 'profiles' end;
 owner_col:=case k when 'profile' then 'id' else 'user_id' end;
 threshold:=case k when 'profile' then cfg.profile_report_hide_threshold else cfg.report_hide_threshold end;
 perform pg_advisory_xact_lock(hashtextextended('ugc_report_hold'||chr(10)||k||chr(10)||new.target_id::text,0));
 execute format('select t.moderation_status,(to_jsonb(t)->>%L)::uuid,coalesce((to_jsonb(t)->>''moderation_public_ready'')::boolean,false) from public.%I t where t.id=$1',owner_col,tbl)
  into row_status,author,row_public using new.target_id;
 if row_status is null then return null; end if;
 visible:=case when k='profile' then row_public else row_status='approved' end;
 begin
  select * into h from admin_private.ugc_report_holds where kind=k and target_id=new.target_id;
  select count(distinct r.reporter_id) into n from public.reports r join public.profiles p on p.id=r.reporter_id join auth.users u on u.id=r.reporter_id
   where r.target_type=new.target_type and r.target_id=new.target_id and r.status='pending'
    and r.created_at>coalesce(h.reports_cleared_at,'-infinity'::timestamptz)
    and r.reporter_id is distinct from author and not coalesce(p.is_banned,false)
    and p.moderation_public_ready and u.created_at<=r.created_at-cfg.reporter_min_account_age;
  insert into admin_private.ugc_report_holds(kind,target_id,report_count,updated_at) values(k,new.target_id,n,clock_timestamp())
   on conflict(kind,target_id) do update set report_count=excluded.report_count,updated_at=excluded.updated_at;
  if n>=threshold and h.report_held_at is null and (visible or row_status='pending') then
   update admin_private.ugc_report_holds set report_held_at=clock_timestamp(),previously_published=previously_published or visible
    where kind=k and target_id=new.target_id;
   if visible then
    insert into admin_private.ugc_hold_context(transaction_id,kind,target_id) values(txid_current(),k,new.target_id) on conflict do nothing;
    if k='profile' then
     update public.profiles set moderation_status='pending',moderation_public_ready=false,moderation_submitted_at=clock_timestamp() where id=new.target_id;
    else
     execute format('update public.%I set moderation_status=''pending'',moderation_submitted_at=clock_timestamp() where id=$1',tbl) using new.target_id;
    end if;
    delete from admin_private.ugc_hold_context where transaction_id=txid_current() and kind=k and target_id=new.target_id;
   end if;
  end if;
 exception when others then
  raise warning 'UGC report hold skipped for % (%)',k,sqlstate;
 end;
 return null;
end $$;
revoke all on function public.ugc_report_threshold() from public,anon,authenticated;
drop trigger if exists zz_ugc_report_threshold on public.reports;
create trigger zz_ugc_report_threshold after insert on public.reports for each row execute function public.ugc_report_threshold();

-- An automatic report hold is not an admin edit, even when the reporter who
-- crosses the threshold is an admin: skip the legacy audit receipt (same patch
-- technique as 009; the rollback reverses it exactly).
do $$ declare definition text; before_text text; after_text text; begin
 before_text:=$fragment$ or exists(select 1 from admin_private.ugc_action_context where transaction_id=txid_current() and actor_id=auth.uid()) then$fragment$;
 after_text:=$fragment$ or exists(select 1 from admin_private.ugc_action_context where transaction_id=txid_current() and actor_id=auth.uid()) or exists(select 1 from admin_private.ugc_hold_context where transaction_id=txid_current()) then$fragment$;
 definition:=pg_get_functiondef('public.admin_console_audit_change()'::regprocedure);
 if strpos(definition,after_text)=0 then
  if strpos(definition,before_text)=0 then raise exception 'Review installed audit implementation (009 patch) before applying'; end if;
  execute replace(definition,before_text,after_text);
 end if;
end $$;

-- Reporter lookups (reporter-hide) and per-target pending counts (threshold).
create index if not exists ugc_reports_reporter_target on public.reports(reporter_id,target_type,target_id);
create index if not exists ugc_reports_target_pending on public.reports(target_type,target_id,created_at) where status='pending';

-- A reporter no longer sees what they reported (authors still see their own rows).
-- The ::uuid[] cast is required: without it =any((select ...)) parses as ANY(subquery).
do $$ declare r record; begin
 for r in select * from (values('posts','user_id','post'),('stories','user_id','story'),('comments','user_id','comment'),('notes','user_id','note'),('venue_reviews','user_id','review'),('place_collections','user_id','collection')) t(tbl,owner_col,target_type) loop
  execute format('drop policy if exists ugc_reporter_hidden_read on public.%I',r.tbl);
  execute format('create policy ugc_reporter_hidden_read on public.%I as restrictive for select to anon,authenticated using(%I=(select auth.uid()) or not (id=any((select public.ugc_viewer_reported_ids(%L))::uuid[])))',r.tbl,r.owner_col,r.target_type);
 end loop;
end $$;

-- Same signature, attributes, rows and order as 009. Adds content.moderation_hold
-- (Mongolian reason, only when there is one) and top-level hold_reason
-- (reports | blocked_term | link | phone | rejected_before | null) and report_count.
-- Filter state is not stored: pending items are re-screened when listed.
create or replace function public.admin_console_review_queue(p_kind text default 'all',p_status text default 'pending',p_offset integer default 0,p_limit integer default 30) returns jsonb
language plpgsql stable security definer set search_path=pg_catalog,public,pg_temp as $$
declare r record; rows jsonb:='[]'::jsonb; result jsonb;
begin
 perform public.admin_console_require_admin();perform public.admin_console_validate_page(p_offset,p_limit);
 if p_kind is null or p_kind not in ('all','post','story','comment','event','review','profile','note','collection','venue') or p_status is null or p_status not in ('pending','approved','rejected') then raise exception 'Invalid review filter' using errcode='22023'; end if;
 for r in select * from (values('posts','user_id','post'),('stories','user_id','story'),('comments','user_id','comment'),('events','organizer_id','event'),('venue_reviews','user_id','review'),('profiles','id','profile'),('notes','user_id','note'),('place_collections','user_id','collection'),('venues','owner_id','venue')) t(tbl,owner_col,kind) loop
  if p_kind<>'all' and p_kind<>r.kind then continue; end if;
  execute format($q$select coalesce(jsonb_agg(jsonb_build_object('id',t.id,'kind',%1$L,'author_id',t.%2$I,
    'content',c.content||case when x.label is null then '{}'::jsonb else jsonb_build_object('moderation_hold',x.label) end,
    'review_version',t.moderation_version,'status',t.moderation_status,'created_at',to_jsonb(t)->>'created_at',
    'submitted_at',t.moderation_submitted_at,'hold_reason',x.reason,'report_count',coalesce(h.report_count,0))),'[]'::jsonb)
   from (select * from public.%3$I where moderation_status=$1 and (%1$L<>'collection' or coalesce((to_jsonb(%3$I)->>'is_public')::boolean,false)) order by moderation_submitted_at desc,id desc limit $2) t
   left join admin_private.ugc_profile_drafts d on %1$L='profile' and d.profile_id=t.id
   left join admin_private.ugc_report_holds h on h.kind=%1$L and h.target_id=t.id
   cross join lateral (select coalesce(d.candidate,public.ugc_public_fields(%3$L,to_jsonb(t))) content) c
   cross join lateral (select case when t.moderation_status='pending' and h.report_held_at is null then public.ugc_screen_text(%1$L,c.content,null) end s) f
   cross join lateral (select case when h.report_held_at is not null then 'reports' when f.s is not null then f.s->>'reason'
      when t.moderation_status='pending' and h.rejected_at is not null then 'rejected_before' end reason,
     case when h.report_held_at is not null then 'Хэрэглэгчид мэдээлсэн ('||h.report_count||' хүн) — бусдаас түр нуусан'
      when f.s->>'reason'='blocked_term' then 'Автомат шүүлтүүр: хориотой үг — '||(f.s->>'term')
      when f.s->>'reason'='link' then 'Автомат шүүлтүүр: холбоос (link) агуулсан'
      when f.s->>'reason'='phone' then 'Автомат шүүлтүүр: утасны дугаар агуулсан'
      when t.moderation_status='pending' and h.rejected_at is not null then 'Өмнө татгалзсан агуулгыг зохиогч зассан — таны шийдвэр хэрэгтэй'
      when coalesce(h.report_count,0)>0 then 'Мэдээлэл ирсэн: '||h.report_count||' хүн' end label) x$q$,r.kind,r.owner_col,r.tbl)
   into result using p_status,p_offset+p_limit+1;
  rows:=rows||result;
 end loop;
 with page as(select value item from jsonb_array_elements(rows) order by value->>'submitted_at' desc nulls last,value->>'kind',value->>'id' desc offset p_offset limit p_limit+1),numbered as(select item,row_number() over(order by item->>'submitted_at' desc nulls last,item->>'kind',item->>'id' desc) n from page)
 select jsonb_build_object('items',coalesce(jsonb_agg(item order by n) filter(where n<=p_limit),'[]'::jsonb),'has_more',count(*)>p_limit) into result from numbered;
 return result;
end $$;
revoke all on function public.admin_console_review_queue(text,text,integer,integer) from public,anon;
grant execute on function public.admin_console_review_queue(text,text,integer,integer) to authenticated;

notify pgrst,'reload schema';
commit;
