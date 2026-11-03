-- READ ONLY. Run after 003 and before 004; no user rows are read.
begin read only;
do $$ declare t text; r record; begin
  foreach t in array array['profiles','posts','stories','comments','story_views','story_likes','comment_likes','venue_reviews','checkins','notes'] loop
    if to_regclass('public.'||t) is null or not exists(select 1 from pg_class where oid=to_regclass('public.'||t) and relrowsecurity) then raise exception 'Missing RLS prerequisite: %',t; end if;
  end loop;
  for r in select * from (values
    ('story_views','id'),('story_views','story_id'),('story_views','viewer_id'),('story_views','viewed_at'),
    ('story_likes','story_id'),('story_likes','user_id'),('comment_likes','comment_id'),('comment_likes','user_id'),
    ('venue_reviews','id'),('venue_reviews','venue_id'),('venue_reviews','user_id'),('venue_reviews','rating'),('venue_reviews','comment'),
    ('checkins','user_id'),('checkins','venue_id'),('checkins','created_at'),('checkins','expires_at'),('checkins','audience'),
    ('notes','id'),('notes','user_id'),('notes','text'),('notes','venue_id'),('notes','created_at'),('notes','expires_at')) as x(t,c) loop
    if not exists(select 1 from information_schema.columns where table_schema='public' and table_name=r.t and column_name=r.c) then raise exception 'Missing column %.%',r.t,r.c; end if;
  end loop;
  for r in select * from (values
    ('story_views',array['story_id','viewer_id']),('story_likes',array['story_id','user_id']),
    ('comment_likes',array['comment_id','user_id']),('venue_reviews',array['user_id','venue_id']),('notes',array['user_id'])) as x(t,keys) loop
    if not exists(select 1 from pg_index i where i.indrelid=to_regclass('public.'||r.t) and i.indisunique and i.indisvalid and i.indpred is null and i.indexprs is null
      and array(select a.attname::text from unnest(i.indkey::smallint[]) k join pg_attribute a on a.attrelid=i.indrelid and a.attnum=k order by a.attname)=r.keys) then
      raise exception 'Missing unique client-upsert key on %',r.t;
    end if;
  end loop;
  if to_regprocedure('public.admin_console_maintenance()') is null or to_regprocedure('public.admin_console_action(text,uuid,text,uuid)') is null
     or to_regprocedure('public.social_active()') is null or to_regprocedure('auth.role()') is null then raise exception 'Social, hosted and admin prerequisites are required'; end if;
  if exists(select 1 from pg_roles where rolname in ('anon','authenticated') and (rolsuper or rolbypassrls)) then raise exception 'Client roles must not bypass RLS'; end if;
  if has_schema_privilege('anon','public','CREATE') or has_schema_privilege('authenticated','public','CREATE') then raise exception 'Client roles must not create public objects'; end if;
  if not exists(select 1 from pg_trigger where tgrelid='public.profiles'::regclass and tgname='protect_profile_flags' and tgenabled in ('O','A')) then raise exception 'Profile flag guard is required'; end if;
end $$;
commit;
