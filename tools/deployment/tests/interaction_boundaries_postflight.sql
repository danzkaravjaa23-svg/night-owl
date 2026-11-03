-- READ ONLY. Verifies restrictive gates, immutable identity and narrow grants.
begin read only;
do $$ declare t text; r text; c record; p record; allowed_insert text[]; allowed_update text[]; begin
  foreach t in array array['story_views','story_likes','comment_likes','venue_reviews','checkins','notes'] loop
    if not exists(select 1 from pg_class where oid=to_regclass('public.'||t) and relrowsecurity) then raise exception 'RLS missing on %',t; end if;
    foreach r in array array['anon','authenticated'] loop
      if has_table_privilege(r,'public.'||t,'INSERT,UPDATE,TRUNCATE,REFERENCES,TRIGGER') then raise exception 'Broad write privilege remains on % for %',t,r; end if;
      allowed_insert:=case when r='anon' or t='checkins' then array[]::text[] when t='story_views' then array['story_id','viewer_id'] when t='story_likes' then array['story_id','user_id'] when t='comment_likes' then array['comment_id','user_id'] when t='notes' then array['user_id','text','venue_id','created_at','expires_at'] else array['venue_id','user_id','rating','comment'] end;
      allowed_update:=allowed_insert;
      for c in select attname from pg_attribute where attrelid=to_regclass('public.'||t) and attnum>0 and not attisdropped loop
        if has_column_privilege(r,'public.'||t,c.attname,'INSERT') is distinct from (c.attname=any(allowed_insert))
          or has_column_privilege(r,'public.'||t,c.attname,'UPDATE') is distinct from (c.attname=any(allowed_update)) then raise exception 'Column grant mismatch %.% for %',t,c.attname,r; end if;
      end loop;
    end loop;
  end loop;
  if has_table_privilege('anon','public.story_views','SELECT') or not has_table_privilege('authenticated','public.story_views','SELECT') then raise exception 'Story history grants mismatch'; end if;
  if has_table_privilege('authenticated','public.story_views','DELETE') or has_table_privilege('anon','public.checkins','DELETE') then raise exception 'Unexpected delete grant'; end if;
  foreach t in array array['profiles','story_views','story_likes','comment_likes','venue_reviews','notes'] loop
    if not exists(select 1 from pg_trigger where tgrelid=to_regclass('public.'||t) and tgname='interaction_identity_guard' and tgenabled in ('O','A') and tgfoid='public.interaction_identity_guard()'::regprocedure and (tgtype::integer & 19)=19) then raise exception 'Identity guard missing on %',t; end if;
  end loop;
  for p in select * from (values
    ('story_views','interaction_views_read','r'),('story_views','interaction_views_insert','a'),('story_views','interaction_views_update','w'),('story_views','interaction_views_delete','d'),
    ('story_likes','interaction_read','r'),('story_likes','interaction_insert','a'),('story_likes','interaction_update','w'),('story_likes','interaction_delete','d'),
    ('comment_likes','interaction_read','r'),('comment_likes','interaction_insert','a'),('comment_likes','interaction_update','w'),('comment_likes','interaction_delete','d'),
    ('venue_reviews','interaction_reviews_insert','a'),('venue_reviews','interaction_reviews_update','w'),('venue_reviews','interaction_reviews_delete','d'),
    ('checkins','interaction_checkins_insert','a'),('checkins','interaction_checkins_update','w'),('checkins','interaction_checkins_delete','d'),
    ('notes','interaction_notes_read','r'),('notes','interaction_notes_insert','a'),('notes','interaction_notes_update','w'),('notes','interaction_notes_delete','d')) as x(t,n,cmd) loop
    if not exists(select 1 from pg_policy where polrelid=to_regclass('public.'||p.t) and polname=p.n and not polpermissive and polcmd=p.cmd::"char"
      and polroles @> array[(select oid from pg_roles where rolname='anon'),(select oid from pg_roles where rolname='authenticated')]) then raise exception 'Restrictive policy missing: %.%',p.t,p.n; end if;
  end loop;
  if has_function_privilege('anon','public.interaction_identity_guard()','EXECUTE') or has_function_privilege('authenticated','public.interaction_identity_guard()','EXECUTE') then raise exception 'Internal trigger helper exposed'; end if;
  if has_function_privilege('anon','public.interaction_note_write_guard()','EXECUTE') or has_function_privilege('authenticated','public.interaction_note_write_guard()','EXECUTE') then raise exception 'Internal note trigger exposed'; end if;
  if has_table_privilege('anon','public.notes','SELECT') then raise exception 'Anonymous notes read remains granted'; end if;
  if not exists(select 1 from pg_trigger where tgrelid='public.notes'::regclass and tgname='interaction_note_write_guard' and tgenabled in ('O','A') and (tgtype::integer & 23)=23) then raise exception 'Note write guard missing'; end if;
  foreach r in array array['anon','authenticated'] loop
    if exists(select 1 from pg_class cls join pg_namespace n on n.oid=cls.relnamespace where n.nspname='public' and cls.relkind in ('r','p') and has_table_privilege(r,cls.oid,'TRUNCATE')) then raise exception 'Public-table TRUNCATE remains available to %',r; end if;
  end loop;
  if has_function_privilege('anon','public.check_in_venue(uuid)','EXECUTE') or not has_function_privilege('authenticated','public.check_in_venue(uuid)','EXECUTE') then raise exception 'Check-in RPC grants mismatch'; end if;
  if not exists(select 1 from pg_proc where oid='public.check_in_venue(uuid)'::regprocedure and prosecdef and proconfig @> array['search_path=""']) then raise exception 'Check-in definer/search_path mismatch'; end if;
end $$;
commit;
