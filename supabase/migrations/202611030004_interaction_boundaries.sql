-- Forward security repair: private interactions/notes, bans, check-ins, identity.
-- Apply after the reviewed social / hosted RPC / account / admin migrations.
-- Existing rows remain intact. No Auth users, grants of admin status or Storage
-- objects are changed. Run interaction_boundaries_preflight.sql first.
begin;
set local lock_timeout='5s';
set local statement_timeout='60s';

do $$ declare t text; begin
  foreach t in array array['profiles','posts','stories','comments','story_views','story_likes','comment_likes','venue_reviews','checkins','notes'] loop
    if to_regclass('public.'||t) is null or not exists(select 1 from pg_class where oid=to_regclass('public.'||t) and relrowsecurity) then
      raise exception 'Missing RLS prerequisite: %',t;
    end if;
  end loop;
  if to_regprocedure('public.admin_console_maintenance()') is null
     or to_regprocedure('public.admin_console_action(text,uuid,text,uuid)') is null
     or to_regprocedure('public.social_active()') is null
     or to_regprocedure('auth.role()') is null then
    raise exception 'Install and verify social, hosted RPC and admin console prerequisites';
  end if;
end $$;

-- A flag-preserving primary-key change must not move authority to another Auth
-- identity. The independent trigger also protects installations of the original
-- 003 migration. Service-role maintenance retains its explicit existing bypass.
create or replace function public.interaction_identity_guard() returns trigger
language plpgsql security definer set search_path=pg_catalog,public,pg_temp as $$
declare k text;
begin
  if public.admin_console_maintenance() then return new; end if;
  foreach k in array tg_argv loop
    if to_jsonb(new)->k is distinct from to_jsonb(old)->k then
      raise exception 'Record identity cannot be reassigned' using errcode='42501';
    end if;
  end loop;
  return new;
end $$;
revoke all on function public.interaction_identity_guard() from public,anon,authenticated;
drop trigger if exists interaction_identity_guard on public.profiles;
create trigger interaction_identity_guard before update on public.profiles for each row execute function public.interaction_identity_guard('id');
drop trigger if exists interaction_identity_guard on public.story_views;
create trigger interaction_identity_guard before update on public.story_views for each row execute function public.interaction_identity_guard('id','story_id','viewer_id');
drop trigger if exists interaction_identity_guard on public.story_likes;
create trigger interaction_identity_guard before update on public.story_likes for each row execute function public.interaction_identity_guard('story_id','user_id');
drop trigger if exists interaction_identity_guard on public.comment_likes;
create trigger interaction_identity_guard before update on public.comment_likes for each row execute function public.interaction_identity_guard('comment_id','user_id');
drop trigger if exists interaction_identity_guard on public.venue_reviews;
create trigger interaction_identity_guard before update on public.venue_reviews for each row execute function public.interaction_identity_guard('id','venue_id','user_id');
drop trigger if exists interaction_identity_guard on public.notes;
create trigger interaction_identity_guard before update on public.notes for each row execute function public.interaction_identity_guard('id','user_id');

-- A browser role never needs TRUNCATE; RLS does not protect that operation.
-- Future schema changes must preserve this invariant (checked by postflight).
revoke truncate on all tables in schema public from public,anon,authenticated;

-- Remove inherited table AND explicit column grants before rebuilding the API
-- contract. Table-level REVOKE alone does not remove column-level privileges.
do $$ declare t text; c record; begin
  foreach t in array array['story_views','story_likes','comment_likes','venue_reviews','checkins','notes'] loop
    execute format('revoke all on public.%I from public,anon,authenticated',t);
    for c in select attname from pg_attribute where attrelid=to_regclass('public.'||t) and attnum>0 and not attisdropped loop
      execute format('revoke select(%1$I),insert(%1$I),update(%1$I),references(%1$I) on public.%2$I from public,anon,authenticated',c.attname,t);
    end loop;
  end loop;
end $$;
grant select on public.story_views to authenticated;
grant insert(story_id,viewer_id),update(story_id,viewer_id) on public.story_views to authenticated;
grant select on public.story_likes,public.comment_likes,public.venue_reviews,public.checkins to anon,authenticated;
grant insert(story_id,user_id),update(story_id,user_id),delete on public.story_likes to authenticated;
grant insert(comment_id,user_id),update(comment_id,user_id),delete on public.comment_likes to authenticated;
grant insert(venue_id,user_id,rating,comment),update(venue_id,user_id,rating,comment),delete on public.venue_reviews to authenticated;
grant delete on public.checkins to authenticated;
grant select,delete on public.notes to authenticated;
grant insert(user_id,text,venue_id,created_at,expires_at),update(user_id,text,venue_id,created_at,expires_at) on public.notes to authenticated;

-- The existing composer sends timestamps, but only the server controls the
-- actual 24-hour lifetime. Do not change existing notes during installation.
create or replace function public.interaction_note_write_guard() returns trigger
language plpgsql security definer set search_path=pg_catalog,public,pg_temp as $$
begin
  if public.admin_console_maintenance() then return new; end if;
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
drop trigger if exists interaction_note_write_guard on public.notes;
create trigger interaction_note_write_guard before insert or update on public.notes for each row execute function public.interaction_note_write_guard();
drop policy if exists interaction_notes_read on public.notes;
create policy interaction_notes_read on public.notes as restrictive for select to anon,authenticated
  using(public.social_active() and (user_id=auth.uid() or
    (created_at<=now() and created_at>now()-interval '24 hours' and expires_at>now()
      and public.can_view_author(user_id)
      and exists(select 1 from public.follows f where f.follower_id=auth.uid() and f.following_id=notes.user_id)
      and exists(select 1 from public.follows f where f.follower_id=notes.user_id and f.following_id=auth.uid()))));
drop policy if exists interaction_notes_insert on public.notes;
create policy interaction_notes_insert on public.notes as restrictive for insert to anon,authenticated
  with check(public.social_active() and user_id=auth.uid());
drop policy if exists interaction_notes_update on public.notes;
create policy interaction_notes_update on public.notes as restrictive for update to anon,authenticated
  using(public.social_active() and user_id=auth.uid()) with check(public.social_active() and user_id=auth.uid());
drop policy if exists interaction_notes_delete on public.notes;
create policy interaction_notes_delete on public.notes as restrictive for delete to anon,authenticated
  using(public.social_active() and user_id=auth.uid());

-- Parent subqueries run as the caller, so existing private-account, block,
-- expired-story and private-post policies remain authoritative. Administrators
-- do not get a blanket exception for other users' viewing history.
drop policy if exists interaction_views_read on public.story_views;
create policy interaction_views_read on public.story_views as restrictive for select to anon,authenticated
  using(public.social_active() and exists(select 1 from public.stories s where s.id=story_id and s.expires_at>now() and (viewer_id=auth.uid() or s.user_id=auth.uid())));
drop policy if exists interaction_views_insert on public.story_views;
create policy interaction_views_insert on public.story_views as restrictive for insert to anon,authenticated
  with check(public.social_active() and viewer_id=auth.uid() and exists(select 1 from public.stories s where s.id=story_id and s.expires_at>now()));
drop policy if exists interaction_views_update on public.story_views;
create policy interaction_views_update on public.story_views as restrictive for update to anon,authenticated
  using(public.social_active() and viewer_id=auth.uid() and exists(select 1 from public.stories s where s.id=story_id and s.expires_at>now()))
  with check(public.social_active() and viewer_id=auth.uid() and exists(select 1 from public.stories s where s.id=story_id and s.expires_at>now()));
drop policy if exists interaction_views_upsert on public.story_views;
create policy interaction_views_upsert on public.story_views for update to authenticated using(viewer_id=auth.uid()) with check(viewer_id=auth.uid());
drop policy if exists interaction_views_delete on public.story_views;
create policy interaction_views_delete on public.story_views as restrictive for delete to anon,authenticated using(false);

do $$ declare r record; v_parent text; begin
  for r in select * from (values ('story_likes','stories','story_id'),('comment_likes','comments','comment_id')) as x(t,parent_table,parent_key) loop
    v_parent:=format('exists(select 1 from public.%I p where p.id=%I%s)',r.parent_table,r.parent_key,case when r.t='story_likes' then ' and p.expires_at>now()' else '' end);
    execute format('drop policy if exists interaction_read on public.%I',r.t);
    execute format('create policy interaction_read on public.%I as restrictive for select to anon,authenticated using((auth.uid() is null or public.social_active()) and %s)',r.t,v_parent);
    execute format('drop policy if exists interaction_insert on public.%I',r.t);
    execute format('create policy interaction_insert on public.%I as restrictive for insert to anon,authenticated with check(public.social_active() and user_id=auth.uid() and %s)',r.t,v_parent);
    execute format('drop policy if exists interaction_update on public.%I',r.t);
    execute format('create policy interaction_update on public.%I as restrictive for update to anon,authenticated using(public.social_active() and user_id=auth.uid() and %s) with check(public.social_active() and user_id=auth.uid() and %s)',r.t,v_parent,v_parent);
    execute format('drop policy if exists interaction_upsert on public.%I',r.t);
    execute format('create policy interaction_upsert on public.%I for update to authenticated using(user_id=auth.uid()) with check(user_id=auth.uid())',r.t);
    execute format('drop policy if exists interaction_delete on public.%I',r.t);
    execute format('create policy interaction_delete on public.%I as restrictive for delete to anon,authenticated using(public.social_active() and user_id=auth.uid())',r.t);
  end loop;
end $$;

drop policy if exists interaction_reviews_insert on public.venue_reviews;
create policy interaction_reviews_insert on public.venue_reviews as restrictive for insert to anon,authenticated
  with check(public.social_active() and user_id=auth.uid());
drop policy if exists interaction_reviews_update on public.venue_reviews;
create policy interaction_reviews_update on public.venue_reviews as restrictive for update to anon,authenticated
  using(public.social_active() and user_id=auth.uid()) with check(public.social_active() and user_id=auth.uid());
drop policy if exists interaction_reviews_delete on public.venue_reviews;
create policy interaction_reviews_delete on public.venue_reviews as restrictive for delete to anon,authenticated
  using(public.social_active() and user_id=auth.uid());

-- Only the definer RPC can create or replace a check-in. Keep own checkout.
drop policy if exists interaction_checkins_insert on public.checkins;
create policy interaction_checkins_insert on public.checkins as restrictive for insert to anon,authenticated with check(false);
drop policy if exists interaction_checkins_update on public.checkins;
create policy interaction_checkins_update on public.checkins as restrictive for update to anon,authenticated using(false) with check(false);
drop policy if exists interaction_checkins_delete on public.checkins;
create policy interaction_checkins_delete on public.checkins as restrictive for delete to anon,authenticated using(public.social_active() and user_id=auth.uid());

-- Replace older check-in signatures with the reviewed active-account contract.
-- RETURNING verification also prevents a suppressing trigger from reporting a
-- successful check-in after deleting the previous one.
create or replace function public.check_in_venue(p_venue_id uuid)
returns table(venue_id uuid,expires_at timestamptz)
language plpgsql security definer set search_path='' as $$
declare
  v_user uuid:=auth.uid(); v_expiry timestamptz:=pg_catalog.now()+interval '4 hours';
  v_saved_user uuid; v_saved_venue uuid; v_saved_expiry timestamptz;
begin
  if v_user is null or auth.role() is distinct from 'authenticated' then raise exception 'Authentication required' using errcode='42501'; end if;
  if pg_catalog.current_setting('transaction_isolation') is distinct from 'read committed' then raise exception 'check_in_venue requires READ COMMITTED isolation' using errcode='25000'; end if;
  perform p.id from public.profiles p where p.id=v_user and not coalesce(p.is_banned,false) for update;
  if not found then raise exception 'Active profile required' using errcode='42501'; end if;
  perform v.id from public.venues v where v.id=p_venue_id and v.name !~ ' #[0-9]+$';
  if not found then raise exception 'Venue not found' using errcode='22023'; end if;
  perform v.id from public.venues v where v.id in (select c.venue_id from public.checkins c where c.user_id=v_user union select p_venue_id) order by v.id for update;
  if not exists(select 1 from public.venues v where v.id=p_venue_id and v.name !~ ' #[0-9]+$') then raise exception 'Venue not found' using errcode='22023'; end if;
  delete from public.checkins c where c.user_id=v_user;
  insert into public.checkins as c(user_id,venue_id,created_at,expires_at) values(v_user,p_venue_id,pg_catalog.now(),v_expiry)
    returning c.user_id,c.venue_id,c.expires_at into v_saved_user,v_saved_venue,v_saved_expiry;
  if v_saved_user is distinct from v_user or v_saved_venue is distinct from p_venue_id or v_saved_expiry is distinct from v_expiry then
    raise exception 'Check-in was not confirmed' using errcode='40001';
  end if;
  return query select v_saved_venue,v_saved_expiry;
end $$;
revoke all on function public.check_in_venue(uuid) from public,anon;
grant execute on function public.check_in_venue(uuid) to authenticated;
notify pgrst,'reload schema';
commit;
