-- READ ONLY. Future app-object ACLs for creator postgres; no user rows.
-- Scope intentionally excludes managed supabase_admin defaults/existing objects.
begin read only;
do $postflight$
declare creator oid := to_regrole('postgres');
begin
 if creator is null then raise exception 'Expected postgres role is absent'; end if;
 if exists (
   select 1 from (values ('r'::"char"),('S'::"char"),('f'::"char")) kinds(kind)
   cross join lateral aclexplode(coalesce(
     (select d.defaclacl from pg_default_acl d where d.defaclrole=creator and d.defaclnamespace=0 and d.defaclobjtype=kinds.kind),
     acldefault(kinds.kind,creator))) a
   where a.grantee=0 or a.grantee in (to_regrole('anon'),to_regrole('authenticated'),to_regrole('service_role'))
 ) then raise exception 'Global postgres defaults still grant client/PUBLIC privileges'; end if;
 if exists (
   select 1 from pg_default_acl d cross join lateral aclexplode(d.defaclacl) a
   where d.defaclrole=creator and d.defaclnamespace='public'::regnamespace and d.defaclobjtype in ('r','S','f')
   and (a.grantee=0 or a.grantee in (to_regrole('anon'),to_regrole('authenticated'),to_regrole('service_role')))
 ) then raise exception 'Public-schema postgres defaults still grant client/PUBLIC privileges'; end if;
end $postflight$;
select jsonb_build_object(
 'status','postgres_app_default_acls_hardened',
 'creator','postgres','scopes',jsonb_build_array('global','public'),
 'object_kinds',jsonb_build_array('tables','sequences','functions'),
 'client_privileges_require_explicit_grants',true,
 'existing_object_acl_verification_included',false,
 'hosted_baseline_installed',false
) as default_acl_postflight;
commit;
