-- REVIEWED TARGET ONLY: night-owl-staging / sreojqqqhdzkfsrbvlpl.
-- Verify the SQL Editor project identity before running this entire transaction.
-- Database name postgres is not a project identity. This guard also rejects an
-- existing application baseline; production has application tables and fails.
-- Changes FUTURE postgres-created objects only. No existing object grants,
-- managed roles/defaults, users, Storage objects or production are changed.
-- Any assertion failure aborts the whole transaction; issue ROLLBACK afterward.
begin;
set local lock_timeout='5s';
set local statement_timeout='15s';
do $preflight$
begin
 if current_user<>'postgres' then raise exception 'Run only as the staging postgres operator'; end if;
 if to_regnamespace('admin_private') is not null or to_regnamespace('account_private') is not null
 or exists(select 1 from pg_class c join pg_namespace n on n.oid=c.relnamespace
   where n.nspname='public' and c.relkind in ('r','p','v','m','S','f')
   and not exists(select 1 from pg_depend d where d.classid='pg_class'::regclass and d.objid=c.oid and d.deptype='e'))
 then raise exception 'Expected an empty staging app schema; existing application refused'; end if;
 if exists(select 1 from (values ('anon'),('authenticated'),('service_role'),('supabase_admin')) r(name)
   where to_regrole(r.name) is null)
 then raise exception 'Required managed roles are absent'; end if;
 if exists(select 1 from pg_roles where rolname in ('anon','authenticated') and (rolsuper or rolbypassrls))
 then raise exception 'Client roles bypass RLS; stop for operator review'; end if;
 perform set_config('nightowl.other_default_acls_before',coalesce((select md5(string_agg(
   d.defaclrole::text||':'||d.defaclnamespace::text||':'||d.defaclobjtype::text||':'||d.defaclacl::text,
   '|' order by d.defaclrole,d.defaclnamespace,d.defaclobjtype)) from pg_default_acl d
   where not(d.defaclrole='postgres'::regrole and d.defaclnamespace in (0,'public'::regnamespace::oid)
     and d.defaclobjtype in ('r','S','f'))),'empty'),true);
 perform set_config('nightowl.schema_acls_before',(select md5(string_agg(
   n.oid::text||':'||n.nspowner::text||':'||coalesce(n.nspacl::text,''),'|' order by n.oid))
   from pg_namespace n where n.nspname in ('public','auth','storage','extensions')),true);
 perform set_config('nightowl.roles_before',(select md5(string_agg(
   r.oid::text||':'||r.rolname||':'||r.rolsuper::text||':'||r.rolbypassrls::text||':'||r.rolcanlogin::text,
   '|' order by r.oid)) from pg_roles r),true);
end $preflight$;
-- Global defaults apply in every schema; per-schema REVOKE cannot cancel a
-- global grant. Remove implicit PUBLIC EXECUTE and any explicit client defaults.
alter default privileges for role postgres revoke all privileges on tables from public, anon, authenticated, service_role;
alter default privileges for role postgres revoke all privileges on sequences from public, anon, authenticated, service_role;
alter default privileges for role postgres revoke all privileges on functions from public, anon, authenticated, service_role;
-- New Supabase project currently retains Dxtm on tables despite exposure OFF.
-- Eliminate these per-schema additions too; exact app grants are installed later.
alter default privileges for role postgres in schema public revoke all privileges on tables from public, anon, authenticated, service_role;
alter default privileges for role postgres in schema public revoke all privileges on sequences from public, anon, authenticated, service_role;
alter default privileges for role postgres in schema public revoke all privileges on functions from public, anon, authenticated, service_role;
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
do $preservation$
begin
 if current_setting('nightowl.other_default_acls_before') is distinct from coalesce((select md5(string_agg(
   d.defaclrole::text||':'||d.defaclnamespace::text||':'||d.defaclobjtype::text||':'||d.defaclacl::text,
   '|' order by d.defaclrole,d.defaclnamespace,d.defaclobjtype)) from pg_default_acl d
   where not(d.defaclrole='postgres'::regrole and d.defaclnamespace in (0,'public'::regnamespace::oid)
     and d.defaclobjtype in ('r','S','f'))),'empty')
 then raise exception 'Unrelated or managed default ACLs changed; rollback required'; end if;
 if current_setting('nightowl.schema_acls_before') is distinct from (select md5(string_agg(
   n.oid::text||':'||n.nspowner::text||':'||coalesce(n.nspacl::text,''),'|' order by n.oid))
   from pg_namespace n where n.nspname in ('public','auth','storage','extensions'))
 then raise exception 'Existing schema ACLs changed; rollback required'; end if;
 if current_setting('nightowl.roles_before') is distinct from (select md5(string_agg(
   r.oid::text||':'||r.rolname||':'||r.rolsuper::text||':'||r.rolbypassrls::text||':'||r.rolcanlogin::text,
   '|' order by r.oid)) from pg_roles r)
 then raise exception 'Existing roles changed; rollback required'; end if;
end $preservation$;
commit;
