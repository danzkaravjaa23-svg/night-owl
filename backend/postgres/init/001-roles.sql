-- Fresh, standalone database bootstrap only; no source data or table grants.
-- Restore reviewed ACLs from the authoritative migration separately.
begin;
create role anon nologin nosuperuser nocreatedb nocreaterole nobypassrls;
create role authenticated nologin nosuperuser nocreatedb nocreaterole nobypassrls;
create role authenticator login noinherit nosuperuser nocreatedb nocreaterole nobypassrls;
create role nightowl_readiness login noinherit nosuperuser nocreatedb nocreaterole nobypassrls;
grant anon, authenticated to authenticator;
revoke all on schema public from public;
grant usage on schema public to anon, authenticated, authenticator;
alter role anon set statement_timeout = '10s';
alter role authenticated set statement_timeout = '10s';
alter role nightowl_readiness set statement_timeout = '5s';
-- PostgreSQL's implicit function EXECUTE grant is global. A per-schema
-- REVOKE cannot cancel it, so revoke the creator's global default instead.
alter default privileges revoke execute on functions from public;
commit;
