-- Read-only prerequisite check. Run on staging before admin console migration.
begin read only;
do $$ declare r record; begin
  for r in select * from (values
    ('profiles','id'),('profiles','username'),('profiles','full_name'),('profiles','avatar_url'),('profiles','is_admin'),('profiles','is_banned'),('profiles','is_verified'),('profiles','created_at'),
    ('posts','id'),('posts','user_id'),('posts','caption'),('posts','media_url'),('posts','created_at'),
    ('comments','id'),('comments','user_id'),('comments','post_id'),('comments','body'),('comments','created_at'),
    ('venues','id'),('venues','owner_id'),('venues','name'),('events','id'),
    ('reports','id'),('reports','reporter_id'),('reports','target_type'),('reports','target_id'),('reports','reason'),('reports','details'),('reports','status'),('reports','created_at')
  ) as t(table_name,column_name) loop
    if not exists(select 1 from information_schema.columns c where c.table_schema='public' and c.table_name=r.table_name and c.column_name=r.column_name) then
      raise exception 'Missing admin prerequisite: %.%',r.table_name,r.column_name;
    end if;
  end loop;
  if exists(select 1 from pg_catalog.pg_class where oid in ('public.profiles'::regclass,'public.reports'::regclass,'public.posts'::regclass,'public.comments'::regclass,'public.venues'::regclass,'public.events'::regclass) and not relrowsecurity) then
    raise exception 'All admin target tables must have RLS enabled';
  end if;
  if to_regprocedure('public.social_active()') is null or to_regprocedure('public.social_admin()') is null then
    raise exception 'Install social discovery before the admin console';
  end if;
  if not exists(select 1 from pg_catalog.pg_trigger t join pg_catalog.pg_proc p on p.oid=t.tgfoid
    where t.tgrelid='public.profiles'::regclass and not t.tgisinternal and t.tgenabled in ('O','A')
      and p.pronamespace='public'::regnamespace and p.proname='protect_profile_flags' and (t.tgtype::integer & 23)=23) then
    raise exception 'Active profile flag guard trigger is required';
  end if;
  if exists(select 1 from pg_roles where rolname in ('anon','authenticated') and (rolsuper or rolbypassrls)) then raise exception 'Client roles must not bypass RLS'; end if;
  if has_schema_privilege('anon','public','CREATE') or has_schema_privilege('authenticated','public','CREATE') then raise exception 'Client roles must not create public objects'; end if;
  if not exists(select 1 from pg_catalog.pg_policy where polrelid='public.profiles'::regclass
      and polname='account_profile_delete_guard' and not polpermissive and polcmd='d'
      and pg_get_expr(polqual,polrelid)='false'
      and polroles @> array[(select oid from pg_roles where rolname='anon'),(select oid from pg_roles where rolname='authenticated')])
    or has_table_privilege('anon','public.profiles','DELETE,TRUNCATE')
    or has_table_privilege('authenticated','public.profiles','DELETE,TRUNCATE')
    or exists(select 1 from pg_catalog.pg_trigger where tgrelid='public.posts'::regclass and tgname='trg_cleanup_post_media')
    or not exists(select 1 from pg_catalog.pg_proc where oid=to_regprocedure('public.cleanup_post_media()') and not prosecdef
      and lower(regexp_replace(prosrc,'[[:space:]]','','g'))='beginreturnold;end;') then
    raise exception 'Apply and verify 202611030001_account_deletion_boundaries.sql before admin moderation';
  end if;
end $$;
commit;
