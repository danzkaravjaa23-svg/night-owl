-- Optional pilot analytics require the actor's explicit current consent.
-- No historical metrics or user metadata are changed by this migration.
begin;

do $$
begin
  if to_regprocedure('public.record_discovery_activity(text,text)') is null or
     to_regprocedure('public.social_action_metric()') is null or
     to_regclass('auth.users') is null then
    raise exception 'Apply and review social discovery and Auth prerequisites first';
  end if;
end;
$$;

create or replace function public.record_discovery_activity(p_event text,p_target text default '') returns void
language plpgsql security definer set search_path=public,pg_temp as $$
begin
  if not social_active() or not exists(select 1 from pilot_participants where user_id=auth.uid()) then return; end if;
  -- Read the current Auth row, not a stale JWT/client claim. Only JSON boolean
  -- true opts in; absence, null, string "true" and withdrawn false all opt out.
  if not exists(select 1 from auth.users u where u.id=auth.uid()
    and u.raw_user_meta_data->'discovery_analytics_consent'='true'::jsonb) then return; end if;
  if (select count(*) from discovery_activity where user_id=auth.uid() and created_at>now()-interval '1 minute')>=120 then return; end if;
  if p_event='session' then p_target:='';
  elsif p_event='directions' then
    if not exists(select 1 from venue_catalog where ref=p_target) then raise exception 'Invalid venue' using errcode='22023'; end if;
  elsif p_event='profile_view' then
    if not exists(select 1 from profiles where id::text=p_target and can_view_author(id)) then return; end if;
  else raise exception 'Invalid event' using errcode='22023'; end if;
  insert into discovery_activity(user_id,event,target) values(auth.uid(),p_event,p_target) on conflict do nothing;
end;
$$;

create or replace function public.social_action_metric() returns trigger
language plpgsql security definer set search_path=public,pg_temp as $$
declare v_actor uuid;v_event text;v_target text;
begin
  if tg_table_name='follows' then v_actor:=new.follower_id;v_event:='follow';v_target:=new.following_id::text;
  elsif tg_table_name='venue_saves' then
    if new.legacy_import then return new; end if;
    v_actor:=new.user_id;v_event:='venue_save';v_target:=new.venue_ref;
  else v_actor:=new.user_id;v_event:='content_publish';v_target:=new.id::text; end if;
  -- Imports and an administrator acting for someone else are not that person's
  -- activity. Preserve their core action without recording an analytics event.
  if v_actor is distinct from auth.uid() or not social_active() then return new; end if;
  if not exists(select 1 from pilot_participants where user_id=v_actor) then return new; end if;
  if not exists(select 1 from auth.users u where u.id=v_actor
    and u.raw_user_meta_data->'discovery_analytics_consent'='true'::jsonb) then return new; end if;
  insert into discovery_activity(user_id,event,target) values(v_actor,v_event,v_target) on conflict do nothing;
  return new;
end;
$$;

revoke all on function public.record_discovery_activity(text,text) from public,anon;
grant execute on function public.record_discovery_activity(text,text) to authenticated;
revoke all on function public.social_action_metric() from public,anon,authenticated;
notify pgrst, 'reload schema';
commit;
