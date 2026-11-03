-- READ ONLY operator health summary. Run as database owner in a private console.
-- No user IDs, receipts, Apple subjects, tokens, content or object paths returned.
-- A prepared request does not freeze writes; failed/expired running jobs do.
begin read only;
select jsonb_build_object(
 'checked_at',now(),
 'prepared_count',count(*) filter(where state='prepared'),
 'running_with_valid_lease',count(*) filter(where state='running' and lease_until>now()),
 'running_without_valid_lease',count(*) filter(where state='running' and (lease_until is null or lease_until<=now())),
 'failed_count',count(*) filter(where state='failed'),
 'completed_count',count(*) filter(where state='completed'),
 'completed_over_retention',count(*) filter(where state='completed' and completed_at<now()-interval '30 days'),
 'invalid_completed_checkpoint',count(*) filter(where state='completed' and (completed_at is null or storage_cleared_at is null or database_cleared_at is null)),
 'attention_required',coalesce(bool_or(state='failed' or (state='running' and (lease_until is null or lease_until<=now()))
   or (state='completed' and (completed_at is null or storage_cleared_at is null or database_cleared_at is null))),false),
 'oldest_attention_age_seconds',max(extract(epoch from now()-updated_at)) filter(where state='failed' or (state='running' and (lease_until is null or lease_until<=now())))
) as erasure_operations_status
from account_private.erasure_jobs;
commit;
