-- Metadata-only checks after the complete hosted repair. No user rows read.
begin transaction read only;
do $$
declare signature text; table_name text; api_role text;
begin
  foreach signature in array array[
    'get_relationship(uuid)','set_follow(uuid,boolean)',
    'respond_follow_request(uuid,boolean)','respond_message_request(uuid,boolean)',
    'send_direct_message(uuid,text,text,uuid,text)',
    'get_discovery_feed(boolean,timestamptz,uuid,integer)',
    'get_following_reels(integer)','discover_creators(text,text,integer)',
    'dm_conversations()','import_venue_saves(uuid,text[])',
    'record_discovery_activity(text,text)','get_pilot_overview()',
    'set_pilot_entry(text,text,boolean)','review_venue(text,jsonb)',
    'search_pilot_candidates(text,text)','create_group(text,uuid[])','check_in_venue(uuid)'
  ] loop
    if to_regprocedure('public.'||signature) is null or
        not has_function_privilege('authenticated','public.'||signature,'EXECUTE') then
      raise exception 'Missing signed-in RPC contract: %',signature;
    end if;
  end loop;
  foreach signature in array array[
    'set_follow(uuid,boolean)','respond_follow_request(uuid,boolean)',
    'respond_message_request(uuid,boolean)','send_direct_message(uuid,text,text,uuid,text)',
    'get_following_reels(integer)','import_venue_saves(uuid,text[])',
    'record_discovery_activity(text,text)','get_pilot_overview()',
    'set_pilot_entry(text,text,boolean)','review_venue(text,jsonb)',
    'search_pilot_candidates(text,text)','create_group(text,uuid[])','check_in_venue(uuid)'
  ] loop
    if has_function_privilege('anon','public.'||signature,'EXECUTE') then
      raise exception 'Anonymous RPC access is too broad: %',signature;
    end if;
  end loop;
  foreach table_name in array array[
    'follow_requests','dm_requests','venue_catalog','venue_saves',
    'place_collections','collection_places','discovery_activity',
    'pilot_creators','pilot_participants','pilot_venues','pilot_content',
    'group_chats','group_members','group_messages'
  ] loop
    if not coalesce((select relrowsecurity from pg_class where oid=to_regclass('public.'||table_name)),false) then
      raise exception 'Required table/RLS missing: %',table_name;
    end if;
  end loop;
  foreach api_role in array array['anon','authenticated'] loop
    foreach table_name in array array['discovery_activity','pilot_creators','pilot_participants','pilot_venues','pilot_content'] loop
      if has_table_privilege(api_role,'public.'||table_name,'SELECT,INSERT,UPDATE,DELETE,TRUNCATE,REFERENCES,TRIGGER') then
        raise exception 'RPC-only table has a direct API grant: % / %',api_role,table_name;
      end if;
    end loop;
  end loop;
  if exists(select 1 from storage.buckets where id in ('posts','stories') and public) or
      (select count(*) from storage.buckets where id in ('posts','stories'))<>2 then
    raise exception 'Post/story bucket privacy missing';
  end if;
  if not exists(select 1 from pg_policies where schemaname='storage' and tablename='objects'
      and policyname='social_media_read' and permissive='RESTRICTIVE') then
    raise exception 'Restrictive media policy missing';
  end if;
  if exists(select 1 from pg_proc p join pg_namespace n on n.oid=p.pronamespace
      where n.nspname='public' and p.proname in ('get_feed_cursor','get_feed_posts','get_user_posts') and p.prosecdef) then
    raise exception 'Legacy feed must obey invoker RLS';
  end if;
end $$;
select 'PASS: hosted RPC, RLS, private media and pilot grants' as result;
rollback;
