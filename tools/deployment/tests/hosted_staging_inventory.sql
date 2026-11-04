-- READ ONLY, bounded schema/config metadata; no credentials, user/content rows,
-- function bodies or database custom-setting values. Run only in the intended
-- project SQL editor. Project name/ref are verified by the operator outside SQL;
-- current_database() is commonly postgres and is not a unique project identity.
begin read only;
set local statement_timeout='15s';
with app_relations as (
 select c.*, n.nspname from pg_class c join pg_namespace n on n.oid=c.relnamespace
 where n.nspname in ('public','admin_private','account_private')
   and c.relkind in ('r','p','v','m','S','f')
   and not exists(select 1 from pg_depend d where d.classid='pg_class'::regclass
                  and d.objid=c.oid and d.deptype='e')
), app_functions as (
 select p.*, n.nspname from pg_proc p join pg_namespace n on n.oid=p.pronamespace
 where n.nspname in ('public','admin_private','account_private') and p.prokind in ('f','p')
   and not exists(select 1 from pg_depend d where d.classid='pg_proc'::regclass
                  and d.objid=p.oid and d.deptype='e')
)
select jsonb_build_object(
 'scope','read-only schema/config metadata; no user rows, secrets or function bodies',
 'captured_at',clock_timestamp(),
 'database',current_database(),
 'database_is_not_project_identity',true,
 'session_role',current_user,
 'postgres_version',current_setting('server_version'),
 'app_owned_relation_count',(select count(*) from app_relations),
 'app_owned_function_count',(select count(*) from app_functions),
 'app_schemas_empty',(not exists(select 1 from app_relations) and not exists(select 1 from app_functions)),
 'app_relations',(select coalesce(jsonb_agg(jsonb_build_object(
   'schema',nspname,'name',relname,'kind',relkind,'owner',pg_get_userbyid(relowner),
   'rls',relrowsecurity,'force_rls',relforcerowsecurity,'replica_identity',relreplident)
   order by nspname,relname),'[]'::jsonb) from (select * from app_relations order by nspname,relname limit 101) a),
 'extensions',(select coalesce(jsonb_agg(jsonb_build_object('name',e.extname,
   'version',e.extversion,'schema',n.nspname) order by e.extname),'[]'::jsonb)
   from pg_extension e join pg_namespace n on n.oid=e.extnamespace),
 'schemas',(select coalesce(jsonb_agg(jsonb_build_object('name',nspname,
   'owner',pg_get_userbyid(nspowner),'acl',nspacl) order by nspname),'[]'::jsonb)
   from pg_namespace where nspname in ('public','auth','storage','extensions','admin_private','account_private')),
 'default_acls',(select coalesce(jsonb_agg(jsonb_build_object('owner',pg_get_userbyid(d.defaclrole),
   'schema',n.nspname,'kind',d.defaclobjtype,'acl',d.defaclacl) order by d.defaclrole,n.nspname,d.defaclobjtype),'[]'::jsonb)
   from pg_default_acl d left join pg_namespace n on n.oid=d.defaclnamespace
   where n.nspname in ('public','admin_private','account_private') or d.defaclnamespace=0),
 'roles',(select coalesce(jsonb_agg(jsonb_build_object('name',rolname,'oid',oid::text,
   'superuser',rolsuper,'bypass_rls',rolbypassrls) order by rolname),'[]'::jsonb)
   from pg_roles where rolname in ('postgres','anon','authenticated','service_role','supabase_admin','supabase_auth_admin','supabase_storage_admin')),
 'managed_relations',(select coalesce(jsonb_agg(jsonb_build_object('schema',n.nspname,
   'name',c.relname,'owner',pg_get_userbyid(c.relowner),'rls',c.relrowsecurity,
   'columns',(select jsonb_agg(jsonb_build_object('name',a.attname,'type',format_type(a.atttypid,a.atttypmod),
     'not_null',a.attnotnull) order by a.attnum) from pg_attribute a
     where a.attrelid=c.oid and a.attnum>0 and not a.attisdropped)) order by n.nspname,c.relname),'[]'::jsonb)
   from pg_class c join pg_namespace n on n.oid=c.relnamespace
   where (n.nspname='auth' and c.relname in ('users','identities'))
      or (n.nspname='storage' and c.relname in ('buckets','objects'))),
 'managed_helpers',(select jsonb_agg(jsonb_build_object('signature',signature,'present',to_regprocedure(signature) is not null))
   from (values ('auth.uid()'),('auth.role()'),('auth.jwt()'),('storage.foldername(text)')) f(signature)),
 'managed_triggers',(select coalesce(jsonb_agg(jsonb_build_object('schema',n.nspname,'table',c.relname,
   'name',t.tgname,'enabled',t.tgenabled,'function_schema',pn.nspname,'function_name',p.proname)
   order by n.nspname,c.relname,t.tgname),'[]'::jsonb)
   from pg_trigger t join pg_class c on c.oid=t.tgrelid join pg_namespace n on n.oid=c.relnamespace
   join pg_proc p on p.oid=t.tgfoid join pg_namespace pn on pn.oid=p.pronamespace
   where not t.tgisinternal and ((n.nspname='auth' and c.relname in ('users','identities'))
   or(n.nspname='storage' and c.relname in ('objects','buckets')))),
 'bucket_settings',(select coalesce(jsonb_agg(jsonb_build_object('id',b.id,'name',b.name,
   'public',b.public,'file_size_limit',to_jsonb(b)->'file_size_limit',
   'allowed_mime_types',to_jsonb(b)->'allowed_mime_types','type',to_jsonb(b)->'type') order by b.id),'[]'::jsonb)
   from storage.buckets b where b.id in ('avatars','posts','stories','venues')),
 'realtime_publications',(select coalesce(jsonb_agg(jsonb_build_object('name',pubname,
   'all_tables',puballtables,'insert',pubinsert,'update',pubupdate,'delete',pubdelete,
   'truncate',pubtruncate,'via_partition_root',pubviaroot) order by pubname),'[]'::jsonb)
   from pg_publication where pubname='supabase_realtime'),
 'realtime_app_membership',(select coalesce(jsonb_agg(jsonb_build_object('schema',schemaname,
   'table',tablename,'columns',attnames,'row_filter',rowfilter) order by schemaname,tablename),'[]'::jsonb)
   from pg_publication_tables where pubname='supabase_realtime' and schemaname='public'),
 'api_configuration_included',false,
 'api_configuration_note','Verify Data API exposed schemas and automatic exposure/RLS in dashboard; do not export custom setting values'
) as hosted_staging_inventory;
commit;
