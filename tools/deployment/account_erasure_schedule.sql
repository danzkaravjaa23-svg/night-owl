-- Optional, separate operator action AFTER 008/009 postflight passes.
-- Existing pg_cron only; never installs an extension, grants a role or enables deletion.
-- Daily02:17 in pg_cron's configured timezone (not the browser/device timezone).
-- Deletes completed journal rows older than30days through the existing RPC only.
-- Source contract: https://github.com/citusdata/pg_cron#creating-a-cron-job
begin;
set local lock_timeout='5s';
set local statement_timeout='30s';
do $schedule$
declare job_count integer; command_text constant text := $command$set lock_timeout='5s'; set statement_timeout='30s'; select public.account_erasure_control('prune');$command$;
begin
 if not exists(select 1 from pg_extension where extname='pg_cron') or to_regprocedure('cron.schedule(text,text,text)') is null then
   raise exception 'An existing approved pg_cron installation is required'; end if;
 if not exists(select 1 from pg_proc where oid=to_regprocedure('public.account_erasure_control(text,uuid,text,text,text,text,uuid)')
   and prosecdef and md5(prosrc)='ee3d8273579d7ee10ab33e6428afbd5f') then raise exception 'Verified008 erasure control is required'; end if;
 if has_function_privilege('anon','public.account_erasure_control(text,uuid,text,text,text,text,uuid)','execute')
   or has_function_privilege('authenticated','public.account_erasure_control(text,uuid,text,text,text,text,uuid)','execute') then
   raise exception 'Client execution of erasure maintenance must remain denied'; end if;
 select count(*) into job_count from cron.job where jobname='nightowl-erasure-prune-30d';
 if job_count>1 then raise exception 'Duplicate retention schedules require operator review'; end if;
 if job_count=1 and not exists(select 1 from cron.job where jobname='nightowl-erasure-prune-30d' and command=command_text
     and schedule='17 2 * * *' and database=current_database() and username=current_user and active) then
   raise exception 'Existing retention schedule differs; do not silently replace it'; end if;
 if job_count=0 then perform cron.schedule('nightowl-erasure-prune-30d','17 2 * * *',command_text); end if;
 if not exists(select 1 from cron.job where jobname='nightowl-erasure-prune-30d' and command=command_text
     and schedule='17 2 * * *' and database=current_database() and username=current_user and active) then
   raise exception 'Retention schedule verification failed'; end if;
end $schedule$;
commit;
