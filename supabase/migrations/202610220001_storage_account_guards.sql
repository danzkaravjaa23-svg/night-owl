-- Staging first. Existing permissive upload policies must not bypass ownership
-- or keep accepting writes from an account whose JWT has not expired yet.
begin;

do $$
begin
  if to_regprocedure('public.social_active()') is null then
    raise exception 'Apply and review social discovery prerequisites first';
  end if;
  if not exists(select 1 from pg_class c join pg_namespace n on n.oid=c.relnamespace
    where n.nspname='storage' and c.relname='objects' and c.relrowsecurity) then
    raise exception 'Storage objects must already have RLS enabled';
  end if;
end $$;

create or replace function public.social_media_writable(p_bucket text,p_name text) returns boolean
language sql stable security definer set search_path=public,pg_temp as $$
  select p_bucket not in ('avatars','posts','stories','venues') or
    (public.social_active() and split_part(p_name,'/',1)=auth.uid()::text
      and strpos(p_name,'/')>0 and strpos(p_name,chr(92))=0
      -- Empty path segments also cannot be safely enumerated by account cleanup.
      and p_name !~ '(^|/)(\.{1,2})?(/|$)');
$$;
revoke all on function public.social_media_writable(text,text) from public;
grant execute on function public.social_media_writable(text,text) to anon,authenticated;

drop policy if exists social_media_insert_guard on storage.objects;
create policy social_media_insert_guard on storage.objects as restrictive
  for insert to anon,authenticated
  with check(public.social_media_writable(bucket_id,name));
drop policy if exists social_media_update_guard on storage.objects;
create policy social_media_update_guard on storage.objects as restrictive
  for update to anon,authenticated
  using(public.social_media_writable(bucket_id,name))
  with check(public.social_media_writable(bucket_id,name));
drop policy if exists social_media_delete_guard on storage.objects;
create policy social_media_delete_guard on storage.objects as restrictive
  for delete to anon,authenticated
  using(public.social_media_writable(bucket_id,name));

commit;
