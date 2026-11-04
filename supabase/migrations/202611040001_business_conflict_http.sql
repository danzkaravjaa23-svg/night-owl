-- Forward-only correction for deterministic application conflicts. SQLSTATE
-- 40001 denotes a retryable database serialization failure; PT409 tells
-- PostgREST to return HTTP 409 without retrying the unchanged business action.
-- Requires the reviewed final 003/004/009 function bodies. No data, roles,
-- privileges, triggers, policies or historical migrations are replayed.
begin;
set local lock_timeout='5s';
set local statement_timeout='30s';

do $business_conflicts$
declare
  expected record; function_id oid; body text; normalized text; definition text;
  before_attributes jsonb; after_attributes jsonb; old_count integer; new_count integer;
begin
  for expected in select * from (values
    ('public.admin_console_action(text,uuid,text,uuid)',7,'1917fb21a180ce3c761648b220f2308520db28ae997b172f5e705e093bf4d9a1','search_path=pg_catalog, public, pg_temp'),
    ('public.admin_console_report_guard()',1,'db8ec010c6ba778e80abee707f46961c1777688782f125008bf9dede396b308b','search_path=pg_catalog, public, pg_temp'),
    ('public.admin_console_review(text,uuid,uuid,text,text)',2,'99bde51bb4b9f750dfe763f27adcbadac13794140e571c4cceb981ff98995074','search_path=pg_catalog, public, pg_temp'),
    ('public.check_in_venue(uuid)',1,'3e71eebbbb168386c7d44b794b46947677eb89f4735cb16b574f61f1c73889ec','search_path=""')
  ) reviewed(signature,raises,body_sha256,configuration) loop
    function_id:=pg_catalog.to_regprocedure(expected.signature);
    if function_id is null then raise exception 'Business-conflict prerequisite missing: %',expected.signature; end if;
    select p.prosrc,to_jsonb(p)-'prosrc' into body,before_attributes from pg_catalog.pg_proc p where p.oid=function_id;
    if not exists(select 1 from pg_catalog.pg_proc p join pg_catalog.pg_language l on l.oid=p.prolang
      where p.oid=function_id and l.lanname='plpgsql' and p.prosecdef
        and p.proconfig=array[expected.configuration]) then
      raise exception 'Business-conflict function attributes changed: %',expected.signature;
    end if;
    -- Normalize only whitespace and the exact already-fixed error token. This
    -- accepts an idempotent rerun, while any other body drift requires review.
    normalized:=regexp_replace(body,'(errcode[[:space:]]*=[[:space:]]*)''PT409''','\1''40001''','g');
    normalized:=btrim(regexp_replace(normalized,'[[:space:]]+',' ','g'));
    if encode(sha256(convert_to(normalized,'UTF8')),'hex')<>expected.body_sha256 then
      raise exception 'Business-conflict function body changed: %',expected.signature;
    end if;
    select count(*) into old_count from regexp_matches(body,'errcode[[:space:]]*=[[:space:]]*''40001''','g');
    select count(*) into new_count from regexp_matches(body,'errcode[[:space:]]*=[[:space:]]*''PT409''','g');
    if old_count+new_count<>expected.raises then raise exception 'Business-conflict raise inventory changed: %',expected.signature; end if;
    if old_count>0 then
      definition:=pg_catalog.pg_get_functiondef(function_id);
      execute regexp_replace(definition,'(errcode[[:space:]]*=[[:space:]]*)''40001''','\1''PT409''','g');
    end if;
    select p.prosrc,to_jsonb(p)-'prosrc' into body,after_attributes from pg_catalog.pg_proc p where p.oid=function_id;
    if before_attributes is distinct from after_attributes then
      raise exception 'Business-conflict migration changed function metadata: %',expected.signature;
    end if;
    select count(*) into old_count from regexp_matches(body,'errcode[[:space:]]*=[[:space:]]*''40001''','g');
    select count(*) into new_count from regexp_matches(body,'errcode[[:space:]]*=[[:space:]]*''PT409''','g');
    if old_count<>0 or new_count<>expected.raises then raise exception 'Business-conflict replacement incomplete: %',expected.signature; end if;
  end loop;
end $business_conflicts$;
notify pgrst,'reload schema';
commit;
