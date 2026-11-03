-- Operator maintenance: completed journal entries older than 30 days only.
-- Never removes prepared/running/failed jobs; never calls Auth/Storage deletion.
-- This file does not create a schedule. Run after the metadata postflight passes.
begin;
set local lock_timeout='5s';
set local statement_timeout='30s';
select public.account_erasure_control('prune');
do $$ begin
 if exists(select 1 from account_private.erasure_jobs where state='completed' and completed_at<now()-interval '30 days') then
   raise exception 'Completed journal retention check failed'; end if;
end $$;
commit;
