-- The fixture runner already applied the migration twice to prove repeatability.
set role authenticated;
select set_config('request.jwt.claim.sub','10000000-0000-0000-0000-000000000001',false);
update public.profiles set is_admin=true where id=auth.uid();
select public.fixture_assert(not public.is_admin(),'organizer cannot self-promote');
do $$
begin
  begin
    perform public.set_featured_event('20000000-0000-0000-0000-000000000001',true,0);
    raise exception 'organizer unexpectedly selected an event';
  exception when insufficient_privilege then null; end;
  begin
    perform public.get_admin_featured_events();
    raise exception 'organizer unexpectedly read admin selections';
  exception when insufficient_privilege then null; end;
  begin
    insert into public.event_features(event_id,rank)
    values('20000000-0000-0000-0000-000000000001',0);
    raise exception 'organizer unexpectedly inserted a selection directly';
  exception when insufficient_privilege then null; end;
end;
$$;

select set_config('request.jwt.claim.sub','10000000-0000-0000-0000-000000000003',false);
update public.profiles set is_banned=false where id=auth.uid();
select public.fixture_assert((select is_banned from public.profiles where id=auth.uid()),'banned admin cannot unban themselves');
update public.profiles set is_admin=true where id='10000000-0000-0000-0000-000000000001';
select public.fixture_assert((select not is_admin from public.profiles where id='10000000-0000-0000-0000-000000000001'),'banned admin cannot promote a proxy account');
do $$
begin
  begin
    perform public.set_featured_event('20000000-0000-0000-0000-000000000001',true,0);
    raise exception 'banned admin unexpectedly selected an event';
  exception when insufficient_privilege then null; end;
end;
$$;

select set_config('request.jwt.claim.sub','10000000-0000-0000-0000-000000000002',false);
update public.profiles set is_banned=false where id='10000000-0000-0000-0000-000000000003';
select public.fixture_assert((select not is_banned from public.profiles where id='10000000-0000-0000-0000-000000000003'),'active admin can still unban another account');
update public.profiles set is_banned=true where id='10000000-0000-0000-0000-000000000003';
select public.set_featured_event('20000000-0000-0000-0000-000000000001',true,20);
select public.set_featured_event('20000000-0000-0000-0000-000000000002',true,10);
select public.set_featured_event('20000000-0000-0000-0000-000000000003',true,5);
select public.fixture_assert((select count(*)=3 from public.get_admin_featured_events()),'admin selects three events');
do $$
begin
  begin
    perform public.set_featured_event('20000000-0000-0000-0000-000000000004',true,0);
    raise exception 'expired event unexpectedly featured';
  exception when invalid_parameter_value then null; end;
  begin
    perform public.set_featured_event('20000000-0000-0000-0000-000000000001',true,-1);
    raise exception 'invalid rank unexpectedly accepted';
  exception when invalid_parameter_value then null; end;
  begin
    update public.event_features set rank=4 where event_id='20000000-0000-0000-0000-000000000001';
    raise exception 'admin bypassed guarded RPC through direct update';
  exception when insufficient_privilege then null; end;
end;
$$;

set role anon;
select set_config('request.jwt.claim.sub','',false);
select public.fixture_assert(
  (select array_agg(title)=array['ongoing','future-two','future-one'] from public.get_featured_events()),
  'public reads selected active events in editorial order');
do $$
begin
  begin
    perform public.set_featured_event('20000000-0000-0000-0000-000000000001',false,0);
    raise exception 'anonymous client unexpectedly removed a selection';
  exception when insufficient_privilege then null; end;
  begin
    perform selected_by from public.event_features;
    raise exception 'anonymous client unexpectedly read admin audit fields';
  exception when insufficient_privilege then null; end;
end;
$$;

reset role;
update public.events set ends_at=now()-interval '1 second'
where id='20000000-0000-0000-0000-000000000003';
set role anon;
select public.fixture_assert((select count(*)=2 from public.get_featured_events()),'expired event automatically leaves public section');
select public.fixture_assert((select count(*)=2 from public.event_features),'RLS also hides expired selections on direct reads');

set role authenticated;
select set_config('request.jwt.claim.sub','10000000-0000-0000-0000-000000000002',false);
select public.fixture_assert((select count(*)=3 from public.get_admin_featured_events()),'admin can still remove expired selection');
select public.set_featured_event('20000000-0000-0000-0000-000000000003',false,0);
select public.set_featured_event('20000000-0000-0000-0000-000000000001',true,1);
select public.fixture_assert(
  (select array_agg(title)=array['future-one','future-two'] from public.get_featured_events()),
  'admin can change editorial rank');
select public.set_featured_event('20000000-0000-0000-0000-000000000001',false,0);
select public.fixture_assert((select count(*)=1 from public.get_featured_events()),'unselect removes public visibility');

reset role;
update public.profiles set is_banned=true where id='10000000-0000-0000-0000-000000000002';
set role authenticated;
do $$
begin
  begin
    perform public.set_featured_event('20000000-0000-0000-0000-000000000002',false,0);
    raise exception 'newly banned admin retained selection permissions';
  exception when insufficient_privilege then null; end;
end;
$$;
reset role;
select 'featured-event security fixture passed' as result;
