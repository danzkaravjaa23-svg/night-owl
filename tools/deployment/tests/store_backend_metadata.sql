-- READ ONLY. Schema/ACL/code metadata and four bucket public flags only.
-- No Auth users, profiles, reports, objects, job rows or credentials are queried.
-- Save this result privately; function/policy definitions describe security boundaries.
-- Dashboard-run SQL may not be registered in supabase_migrations: fingerprints and
-- actual invariants, not a migration-name list, determine whether a change is installed.
begin read only;
do $$ begin
 if (select count(*) from pg_class c join pg_namespace n on n.oid=c.relnamespace
     where n.nspname='public' and c.relkind in ('r','p','v','m'))>100
 or (select count(*) from pg_proc p join pg_namespace n on n.oid=p.pronamespace
     where n.nspname='public' and p.prokind in ('f','p') and not exists
       (select 1 from pg_depend d where d.classid='pg_proc'::regclass and d.objid=p.oid and d.deptype='e'))>300
 then raise exception 'Metadata export exceeds reviewed scope; inspect schema inventory first'; end if;
end $$;
with relations as (
 select c.* from pg_class c join pg_namespace n on n.oid=c.relnamespace
 where (n.nspname='public' and c.relkind in ('r','p','v','m'))
    or (n.nspname='auth' and c.relname in ('users','identities'))
    or (n.nspname='storage' and c.relname in ('objects','buckets'))
    or (n.nspname in ('account_private','admin_private') and c.relkind in ('r','p'))
), functions as (
 select p.* from pg_proc p join pg_namespace n on n.oid=p.pronamespace
 where n.nspname='public' and p.prokind in ('f','p') and not exists
   (select 1 from pg_depend d where d.classid='pg_proc'::regclass and d.objid=p.oid and d.deptype='e')
)
select jsonb_build_object(
 'captured_at',clock_timestamp(),'scope','metadata-only; no application/Auth/Storage object rows',
 'postgres_version',current_setting('server_version'),
 'roles',(select jsonb_agg(jsonb_build_object('role',rolname,'superuser',rolsuper,'bypass_rls',rolbypassrls))
   from pg_roles where rolname in ('anon','authenticated','service_role')),
 'schema_acls',(select jsonb_agg(jsonb_build_object('schema',nspname,'owner',pg_get_userbyid(nspowner),'acl',nspacl))
   from pg_namespace where nspname in ('public','auth','storage','account_private','admin_private')),
 'relations',(select jsonb_agg(jsonb_build_object('name',c.oid::regclass::text,'kind',c.relkind,'owner',pg_get_userbyid(c.relowner),
   'acl',c.relacl,'rls',c.relrowsecurity,'force_rls',c.relforcerowsecurity,
   'columns',(select jsonb_agg(jsonb_build_object('name',a.attname,'type',format_type(a.atttypid,a.atttypmod),
     'not_null',a.attnotnull,'identity',a.attidentity,'generated',a.attgenerated,'acl',a.attacl,
     'default',pg_get_expr(d.adbin,d.adrelid)) order by a.attnum)
     from pg_attribute a left join pg_attrdef d on d.adrelid=a.attrelid and d.adnum=a.attnum
     where a.attrelid=c.oid and a.attnum>0 and not a.attisdropped),
   'constraints',(select jsonb_agg(jsonb_build_object('name',x.conname,'definition',pg_get_constraintdef(x.oid),
     'validated',x.convalidated) order by x.conname) from pg_constraint x where x.conrelid=c.oid),
   'indexes',(select jsonb_agg(pg_get_indexdef(i.indexrelid) order by i.indexrelid::regclass::text) from pg_index i where i.indrelid=c.oid),
   'triggers',(select jsonb_agg(jsonb_build_object('name',t.tgname,'enabled',t.tgenabled,'definition',pg_get_triggerdef(t.oid)) order by t.tgname)
     from pg_trigger t where t.tgrelid=c.oid and not t.tgisinternal),
   'policies',(select jsonb_agg(jsonb_build_object('name',p.polname,'permissive',p.polpermissive,'roles',p.polroles,
     'command',p.polcmd,'using',pg_get_expr(p.polqual,p.polrelid),'check',pg_get_expr(p.polwithcheck,p.polrelid)) order by p.polname)
     from pg_policy p where p.polrelid=c.oid)) order by c.oid::regclass::text) from relations c),
 'functions',(select jsonb_agg(jsonb_build_object('signature',p.oid::regprocedure::text,'owner',pg_get_userbyid(p.proowner),
   'acl',p.proacl,'security_definer',p.prosecdef,'config',p.proconfig,'definition',pg_get_functiondef(p.oid),
   'definition_md5',md5(pg_get_functiondef(p.oid))) order by p.oid::regprocedure::text) from functions p),
 'default_acls',(select jsonb_agg(jsonb_build_object('owner',pg_get_userbyid(d.defaclrole),'schema',n.nspname,'type',d.defaclobjtype,'acl',d.defaclacl))
   from pg_default_acl d left join pg_namespace n on n.oid=d.defaclnamespace where n.nspname='public' or d.defaclnamespace=0),
 'app_buckets',(select jsonb_agg(jsonb_build_object('id',id,'public',public) order by id) from storage.buckets where id in ('posts','stories','avatars','venues')),
 'cron_extension_installed',exists(select 1 from pg_extension where extname='pg_cron'),
 'migration_registry_exists',to_regclass('supabase_migrations.schema_migrations') is not null
) as store_backend_metadata;
commit;
