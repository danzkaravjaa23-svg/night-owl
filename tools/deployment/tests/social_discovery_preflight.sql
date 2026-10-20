-- Run as the database owner on staging before applying the social migrations.
-- This transaction reads schema/permissions only and never changes user data.
begin transaction read only;

do $$
declare v_table text; v_role text; v_column record; v_actual regtype;
begin
  if to_regprocedure('auth.uid()') is null then
    raise exception 'auth.uid() is required; this migration targets the hosted Supabase contract';
  end if;
  foreach v_role in array array['anon','authenticated'] loop
    if not exists(select 1 from pg_roles where rolname=v_role) then
      raise exception 'Required API role is missing: %',v_role;
    end if;
    if exists(select 1 from pg_roles where rolname=v_role and (rolsuper or rolbypassrls)) then
      raise exception 'API role must not bypass RLS: %',v_role;
    end if;
    if has_schema_privilege(v_role,'public','CREATE') then
      raise exception 'Untrusted API role can create objects in public: %',v_role;
    end if;
  end loop;

  foreach v_table in array array['profiles','posts','stories','checkins','follows','blocks','messages','comments','likes','venues','events'] loop
    if to_regclass('public.'||v_table) is null then
      raise exception 'Required table is missing: public.%',v_table;
    end if;
    if not (select relrowsecurity from pg_class where oid=to_regclass('public.'||v_table)) then
      raise exception 'Enable and review RLS before migration: public.%',v_table;
    end if;
    if not has_table_privilege('authenticated','public.'||v_table,'SELECT') then
      raise exception 'Signed-in client lacks SELECT: public.%',v_table;
    end if;
    if exists(select 1 from pg_class c where c.oid=to_regclass('public.'||v_table)
      and (pg_has_role('anon',c.relowner,'USAGE') or pg_has_role('authenticated',c.relowner,'USAGE'))) then
      raise exception 'API role inherits table ownership and can bypass RLS: public.%',v_table;
    end if;
  end loop;
  foreach v_table in array array['profiles','posts','comments','likes','venues'] loop
    if not has_table_privilege('anon','public.'||v_table,'SELECT') then
      raise exception 'Public sharing requires reviewed anonymous SELECT: public.%',v_table;
    end if;
  end loop;

  for v_column in select * from (values
    ('profiles','id','uuid'),('profiles','is_admin','boolean'),
    ('profiles','is_verified','boolean'),('profiles','is_banned','boolean'),
    ('profiles','interests','text[]'),('profiles','last_seen_at','timestamptz'),
    ('posts','id','uuid'),('posts','user_id','uuid'),('posts','venue_id','uuid'),
    ('posts','venue_name','text'),('posts','media_urls','text[]'),('posts','created_at','timestamptz'),
    ('stories','user_id','uuid'),('stories','venue_id','uuid'),('stories','expires_at','timestamptz'),
    ('messages','sender_id','uuid'),('messages','receiver_id','uuid'),
    ('messages','is_read','boolean'),('messages','note_text','text'),('messages','story_media_url','text'),
    ('venues','id','uuid'),('venues','owner_id','uuid'),('events','organizer_id','uuid')
  ) as required(table_name,column_name,type_name) loop
    select atttypid::regtype into v_actual from pg_attribute
      where attrelid=to_regclass('public.'||v_column.table_name)
        and attname=v_column.column_name and attnum>0 and not attisdropped;
    if v_actual is distinct from v_column.type_name::regtype then
      raise exception 'Schema mismatch: %.% must be %, found %',
        v_column.table_name,v_column.column_name,v_column.type_name,coalesce(v_actual::text,'missing');
    end if;
  end loop;
  if to_regclass('storage.objects') is null or to_regclass('storage.buckets') is null then
    raise exception 'Supabase Storage schema is required';
  end if;
  if (select count(*) from storage.buckets where id in ('posts','stories','avatars','venues'))<>4 then
    raise exception 'Required Storage buckets: posts, stories, avatars, venues';
  end if;
  if not (select relrowsecurity from pg_class where oid='storage.objects'::regclass) then
    raise exception 'Storage object RLS is disabled';
  end if;
end $$;

-- Manually review existing callable definer RPCs: restrictive table policies do
-- not constrain a definer that bypasses RLS. No function bodies are exported.
select p.oid::regprocedure::text as existing_definer_rpc,
       has_function_privilege('anon',p.oid,'EXECUTE') as anonymous_access,
       has_function_privilege('authenticated',p.oid,'EXECUTE') as signed_in_access
  from pg_proc p join pg_namespace n on n.oid=p.pronamespace
  where n.nspname='public' and p.prokind='f' and p.prosecdef and p.prorettype<>'trigger'::regtype
    and (has_function_privilege('anon',p.oid,'EXECUTE') or has_function_privilege('authenticated',p.oid,'EXECUTE'))
    and pg_get_functiondef(p.oid) ~* '\m(posts|stories|messages|checkins|venue_saves|place_collections)\M'
  order by 1;

rollback;
