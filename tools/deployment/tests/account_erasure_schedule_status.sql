-- READ ONLY, selected retention job metadata and latest run status only.
-- Does not read other job commands or return_message/error payloads.
begin read only;
select jsonb_build_object(
 'checked_at',now(),'configured_timezone',current_setting('cron.timezone',true),
 'job_count',(select count(*) from cron.job where jobname='nightowl-erasure-prune-30d'),
 'jobs',(select coalesce(jsonb_agg(jsonb_build_object('jobid',j.jobid,'schedule',j.schedule,'active',j.active,
   'current_database',j.database=current_database(),'current_operator',j.username=current_user,
   'command_matches',j.command=$command$set lock_timeout='5s'; set statement_timeout='30s'; select public.account_erasure_control('prune');$command$,
   'last_run',(select jsonb_build_object('status',d.status,'started_at',d.start_time,'ended_at',d.end_time)
     from cron.job_run_details d where d.jobid=j.jobid order by d.start_time desc nulls last,d.runid desc limit 1))), '[]'::jsonb)
   from cron.job j where j.jobname='nightowl-erasure-prune-30d')
) as erasure_retention_schedule;
commit;
