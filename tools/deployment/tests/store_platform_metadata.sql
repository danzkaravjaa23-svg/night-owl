-- READ ONLY complement to store_backend_metadata.sql for isolated replay.
-- Only role identifiers, one enum and four standard helper definitions.
-- No user rows, Auth secrets, access tokens, Storage objects or credentials.
begin read only;
select jsonb_build_object(
 'roles',(select jsonb_agg(jsonb_build_object('role',rolname,'oid',oid::text) order by rolname)
   from pg_roles where rolname in ('anon','authenticated','service_role','postgres','supabase_admin')),
 'enums',(select jsonb_agg(jsonb_build_object('schema',n.nspname,'name',t.typname,'label',e.enumlabel,'order',e.enumsortorder) order by e.enumsortorder)
   from pg_enum e join pg_type t on t.oid=e.enumtypid join pg_namespace n on n.oid=t.typnamespace
   where n.nspname='storage' and t.typname='buckettype'),
 'functions',(select jsonb_agg(jsonb_build_object('signature',p.oid::regprocedure::text,'definition',pg_get_functiondef(p.oid)) order by p.oid::regprocedure::text)
   from pg_proc p where p.oid in (to_regprocedure('auth.uid()'),to_regprocedure('auth.role()'),to_regprocedure('auth.jwt()'),to_regprocedure('storage.foldername(text)')))
) as store_platform_metadata;
commit;
