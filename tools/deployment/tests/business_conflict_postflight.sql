-- Read-only exact function-shape proof. No application rows or credentials.
begin read only;
do $verify_business_conflicts$
declare expected record; body text; normalized text; actual_count integer;
begin
  for expected in select * from (values
    ('public.admin_console_action(text,uuid,text,uuid)',7,'1917fb21a180ce3c761648b220f2308520db28ae997b172f5e705e093bf4d9a1','search_path=pg_catalog, public, pg_temp'),
    ('public.admin_console_report_guard()',1,'db8ec010c6ba778e80abee707f46961c1777688782f125008bf9dede396b308b','search_path=pg_catalog, public, pg_temp'),
    ('public.admin_console_review(text,uuid,uuid,text,text)',2,'99bde51bb4b9f750dfe763f27adcbadac13794140e571c4cceb981ff98995074','search_path=pg_catalog, public, pg_temp'),
    ('public.check_in_venue(uuid)',1,'3e71eebbbb168386c7d44b794b46947677eb89f4735cb16b574f61f1c73889ec','search_path=""')
  ) reviewed(signature,raises,body_sha256,configuration) loop
    select p.prosrc into body from pg_catalog.pg_proc p join pg_catalog.pg_language l on l.oid=p.prolang
      where p.oid=pg_catalog.to_regprocedure(expected.signature) and l.lanname='plpgsql' and p.prosecdef
        and p.proconfig=array[expected.configuration];
    if body is null then raise exception 'Business-conflict postflight attributes missing: %',expected.signature; end if;
    normalized:=regexp_replace(body,'(errcode[[:space:]]*=[[:space:]]*)''PT409''','\1''40001''','g');
    normalized:=btrim(regexp_replace(normalized,'[[:space:]]+',' ','g'));
    select count(*) into actual_count from regexp_matches(body,'errcode[[:space:]]*=[[:space:]]*''PT409''','g');
    if encode(sha256(convert_to(normalized,'UTF8')),'hex')<>expected.body_sha256
      or actual_count<>expected.raises or body~'errcode[[:space:]]*=[[:space:]]*''40001''' then
      raise exception 'Business-conflict postflight body mismatch: %',expected.signature;
    end if;
  end loop;
end $verify_business_conflicts$;
commit;
