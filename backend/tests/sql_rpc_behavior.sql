-- Requires fictional fixtures and the patch in an isolated *_rpc_backend_test DB.
begin;
do $$
declare signature text;
begin
  if current_database() !~ '_rpc_backend_test$' then raise exception 'Disposable RPC test database required'; end if;
  if exists (
    select b.* from nightowl_patch_test.table_acl_before b
    except select c.oid,c.relacl,c.relrowsecurity,c.relforcerowsecurity from pg_class c
  ) or exists (
    select b.* from nightowl_patch_test.policy_before b
    except select p.* from pg_policy p
  ) then raise exception 'Patch changed preexisting table ACLs or RLS'; end if;
  if (select proconfig from pg_proc where oid='public.update_checkin_count()'::regprocedure) is not null then
    raise exception 'Fixture must preserve source counter trigger path inheritance';
  end if;
  foreach signature in array array['public.dm_conversations()','public.create_group(text,uuid[])','public.check_in_venue(uuid)'] loop
    if not has_function_privilege('authenticated',signature,'EXECUTE') or
       has_function_privilege('anon',signature,'EXECUTE') or
       has_function_privilege('authenticator',signature,'EXECUTE') or
       has_function_privilege('nightowl_readiness',signature,'EXECUTE') then
      raise exception 'RPC execute boundary failed: %',signature;
    end if;
    if not exists(select 1 from pg_proc p where p.oid=to_regprocedure(signature)
      and p.prosecdef and p.proowner='nightowl_rpc_fixture_owner'::regrole
      and p.proconfig=array['search_path=""']) then
      raise exception 'RPC owner/search-path boundary failed: %',signature;
    end if;
  end loop;
end;
$$;

set local role anon;
do $$ begin
  begin perform public.dm_conversations(); raise exception 'Anonymous RPC execution allowed';
  exception when insufficient_privilege then null; end;
end; $$;
reset role;

set local role authenticated;
do $$
declare r record; v_group uuid; v_count integer;
begin
  perform set_config('request.jwt.claims','',true);
  begin perform public.dm_conversations(); raise exception 'No-claim read permitted'; exception when insufficient_privilege then null; end;
  begin perform public.create_group('fixture',array['00000000-0000-4000-8000-000000000002']::uuid[]); raise exception 'No-claim group permitted'; exception when insufficient_privilege then null; end;
  begin perform public.check_in_venue('10000000-0000-4000-8000-000000000001'); raise exception 'No-claim check-in permitted'; exception when insufficient_privilege then null; end;
  perform set_config('request.jwt.claims','{"sub":"00000000-0000-4000-8000-000000000001","role":"anon"}',true);
  begin perform public.dm_conversations(); raise exception 'Mismatched role claim permitted'; exception when insufficient_privilege then null; end;
  perform set_config('request.jwt.claims','{"sub":"not-a-uuid","role":"authenticated"}',true);
  begin perform public.dm_conversations(); raise exception 'Malformed identity permitted'; exception when invalid_text_representation then null; end;
  perform set_config('request.jwt.claims','{"sub":"00000000-0000-4000-8000-000000000005","role":"authenticated"}',true);
  begin perform public.dm_conversations(); raise exception 'Missing profile permitted'; exception when insufficient_privilege then null; end;
  perform set_config('request.jwt.claims','{"sub":"00000000-0000-4000-8000-000000000004","role":"authenticated"}',true);
  begin perform public.dm_conversations(); raise exception 'Banned caller read permitted'; exception when insufficient_privilege then null; end;
  begin perform public.create_group('fixture',array['00000000-0000-4000-8000-000000000002']::uuid[]); raise exception 'Banned caller group permitted'; exception when insufficient_privilege then null; end;
  begin perform public.check_in_venue('10000000-0000-4000-8000-000000000001'); raise exception 'Banned caller check-in permitted'; exception when insufficient_privilege then null; end;

  perform set_config('request.jwt.claims','{"sub":"00000000-0000-4000-8000-000000000001","role":"authenticated"}',true);
  select count(*) into v_count from public.dm_conversations();
  if v_count<>2 then raise exception 'Partner list leaked unrelated/banned pairs or lost partners'; end if;
  select * into strict r from public.dm_conversations() where partner_id='00000000-0000-4000-8000-000000000002';
  if r.partner_username<>'fixture_bob' or r.last_body<>'fixture latest own tie' or
    r.last_sender_id<>'00000000-0000-4000-8000-000000000001' or r.unread_count<>452 then
    raise exception 'Latest tie, sender direction or full-history unread calculation failed';
  end if;
  select * into strict r from public.dm_conversations() where partner_id='00000000-0000-4000-8000-000000000003';
  if r.unread_count<>0 then raise exception 'Read message counted as unread'; end if;
  if (select partner_id from public.dm_conversations() limit 1)<>'00000000-0000-4000-8000-000000000002'::uuid then
    raise exception 'Conversation ordering failed';
  end if;

  begin perform public.create_group('  ',array['00000000-0000-4000-8000-000000000002']::uuid[]); raise exception 'Blank group permitted'; exception when invalid_parameter_value then null; end;
  begin perform public.create_group('fixture',array[]::uuid[]); raise exception 'Self-only group permitted'; exception when invalid_parameter_value then null; end;
  begin perform public.create_group('fixture',array[null]::uuid[]); raise exception 'Null member permitted'; exception when invalid_parameter_value then null; end;
  begin perform public.create_group('fixture',null); raise exception 'Missing member list permitted'; exception when invalid_parameter_value then null; end;
  begin perform public.create_group('fixture',array[['00000000-0000-4000-8000-000000000002','00000000-0000-4000-8000-000000000003']]::uuid[]); raise exception 'Multidimensional member list permitted'; exception when invalid_parameter_value then null; end;
  begin perform public.create_group('fixture',array['00000000-0000-4000-8000-000000000005']::uuid[]); raise exception 'Missing member permitted'; exception when insufficient_privilege then null; end;
  begin perform public.create_group('fixture',array['00000000-0000-4000-8000-000000000004']::uuid[]); raise exception 'Banned member permitted'; exception when insufficient_privilege then null; end;
  begin perform public.create_group('fixture failing members',array['00000000-0000-4000-8000-000000000006']::uuid[]); raise exception 'Fictional member trigger did not reject'; exception when check_violation then null; end;
  v_group:=public.create_group('  Fixture group  ',array['00000000-0000-4000-8000-000000000002','00000000-0000-4000-8000-000000000002']::uuid[]);
  insert into nightowl_patch_test.results values(v_group);
  if (select count(*) from public.group_members where group_id=v_group)<>2 or
      (select name from public.group_chats where id=v_group)<>'Fixture group' then
    raise exception 'Group caller inclusion, de-duplication or name trimming failed';
  end if;
  if (select count(*) from public.group_chats)<>1 then raise exception 'Failed group creation left an orphan'; end if;

  begin perform public.check_in_venue('10000000-0000-4000-8000-000000000003'); raise exception 'Demo venue permitted'; exception when invalid_parameter_value then null; end;
  begin perform public.check_in_venue('10000000-0000-4000-8000-000000000009'); raise exception 'Missing venue permitted'; exception when invalid_parameter_value then null; end;
  select * into strict r from public.check_in_venue('10000000-0000-4000-8000-000000000002');
  if r.venue_id<>'10000000-0000-4000-8000-000000000002' or r.expires_at<>now()+interval '4 hours' then
    raise exception 'Check-in return or server expiry failed';
  end if;
end;
$$;
reset role;

do $$
begin
  if (select count(*) from public.checkins where user_id='00000000-0000-4000-8000-000000000001')<>1 or
    (select count(*) from public.checkins where user_id='00000000-0000-4000-8000-000000000002' and venue_id='10000000-0000-4000-8000-000000000001')<>1 then
    raise exception 'Check-in expired-row replacement or caller-only mutation failed';
  end if;
  if exists(select 1 from public.venues v where v.checkin_count<>(select count(*) from public.checkins c where c.venue_id=v.id)) then
    raise exception 'Check-in delete/insert counter trigger diverged';
  end if;
  if (select count(*) from public.group_chats)<>1 or (select count(*) from public.group_members)<>2 then
    raise exception 'Failed group invocation left orphan rows outside API visibility';
  end if;
end;
$$;

-- Reverse blocks are hidden by the ordinary API policy but must guard RPCs.
insert into public.blocks values('00000000-0000-4000-8000-000000000002','00000000-0000-4000-8000-000000000001');
set local role authenticated;
do $$ begin
  perform set_config('request.jwt.claims','{"sub":"00000000-0000-4000-8000-000000000001","role":"authenticated"}',true);
  if exists(select 1 from public.blocks) then raise exception 'Reverse block fixture not hidden from caller'; end if;
  if exists(select 1 from public.dm_conversations() where partner_id='00000000-0000-4000-8000-000000000002') then raise exception 'Reverse-blocked DM partner exposed'; end if;
  begin perform public.create_group('fixture blocked',array['00000000-0000-4000-8000-000000000002']::uuid[]); raise exception 'Reverse-blocked group permitted'; exception when insufficient_privilege then null; end;
end; $$;
reset role;
delete from public.blocks;
insert into public.blocks values('00000000-0000-4000-8000-000000000001','00000000-0000-4000-8000-000000000003');
set local role authenticated;
do $$ begin
  if exists(select 1 from public.dm_conversations() where partner_id='00000000-0000-4000-8000-000000000003') then raise exception 'Forward-blocked DM partner exposed'; end if;
  begin perform public.create_group('fixture blocked',array['00000000-0000-4000-8000-000000000003']::uuid[]); raise exception 'Forward-blocked group permitted'; exception when insufficient_privilege then null; end;
end; $$;
reset role;
delete from public.blocks;
insert into public.blocks values('00000000-0000-4000-8000-000000000002','00000000-0000-4000-8000-000000000003');
set local role authenticated;
do $$ begin
  perform set_config('request.jwt.claims','{"sub":"00000000-0000-4000-8000-000000000001","role":"authenticated"}',true);
  begin perform public.create_group('fixture third-party block',array['00000000-0000-4000-8000-000000000002','00000000-0000-4000-8000-000000000003']::uuid[]); raise exception 'Blocked selected participants grouped together'; exception when insufficient_privilege then null; end;
end; $$;
reset role;
delete from public.blocks;
set local role authenticated;
do $$ begin
  perform set_config('request.jwt.claims','{"sub":"00000000-0000-4000-8000-000000000006","role":"authenticated"}',true);
  if exists(select 1 from public.dm_conversations()) then raise exception 'Unrelated user learned other conversations'; end if;
  if exists(select 1 from public.group_chats) then raise exception 'Group readable by nonmember'; end if;
  if pg_has_role('authenticated','nightowl_rpc_fixture_owner','MEMBER') or
    pg_has_role('authenticator','nightowl_rpc_fixture_owner','MEMBER') then
    raise exception 'API membership reaches RPC owner';
  end if;
end; $$;
reset role;
delete from public.blocks;
commit;
select 'PASS: scoped conversations, complete unread count, atomic groups, blocks/bans, check-ins/counters, unchanged table ACL/RLS, restricted RPC owner' as verification;
