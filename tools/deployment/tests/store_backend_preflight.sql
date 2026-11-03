-- Fail closed before the first coordinated 008+009 installation. No user rows.
-- Repeated/unknown-outcome installs must run postflight, not blindly replay DDL.
begin read only;
do $$ declare f text; t text; begin
 if (select count(*) from pg_constraint c join pg_class r on r.oid=c.conrelid join pg_namespace n on n.oid=r.relnamespace
     where n.nspname='public' and c.contype='f')<>69 then
   raise exception 'Public foreign-key inventory changed; refresh and review erasure scope before rollout'; end if;
 if to_regnamespace('account_private') is not null
 or to_regclass('admin_private.ugc_action_context') is not null
 or to_regclass('admin_private.ugc_profile_drafts') is not null
 or to_regprocedure('public.account_erasure_control(text,uuid,text,text,text,text,uuid)') is not null
 or exists(select 1 from pg_attribute a join pg_class c on c.oid=a.attrelid join pg_namespace n on n.oid=c.relnamespace
   where n.nspname='public' and a.attname in ('moderation_status','moderation_public_ready','target_snapshot','target_author_id') and not a.attisdropped)
 then raise exception '008/009 is already present or partially installed; inspect postflight and reconcile before retry'; end if;
 foreach f in array array['social_active()','social_media_readable(text,text)','social_media_writable(text,text)',
   'admin_console_require_admin()','venue_story_activity_today()','venue_map_activity()'] loop
   if to_regprocedure('public.'||f) is null then raise exception 'Missing prior rollout function: %',f; end if;
 end loop;
 if not exists(select 1 from pg_trigger where tgrelid='public.posts'::regclass and tgname='protect_post_publication_clock' and tgenabled in ('O','A')) then
   raise exception '007 post publication clock guard missing'; end if;
 if (select count(*) from storage.buckets where id in ('posts','stories','avatars','venues'))<>4 then
   raise exception 'All four reviewed app Storage buckets must exist'; end if;
 if not exists(select 1 from pg_class where oid='storage.objects'::regclass and relrowsecurity) then
   raise exception 'Storage object RLS is required'; end if;
 foreach t in array array['posts','stories','comments','events','venue_reviews','profiles','notes','place_collections','venues','venue_catalog'] loop
   if not exists(select 1 from pg_class where oid=to_regclass('public.'||t) and relrowsecurity) then
     raise exception 'UGC prerequisite RLS missing: %',t; end if;
 end loop;
end $$;
commit;
