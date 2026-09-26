-- ============================================================
--  АЮУЛГҮЙ БАЙДАЛ: хэрэглэгч өөрийгөө админ болгохоос хамгаалах
--  Огноо: 2026-09-26
-- ============================================================
--  Асуудал: "Own profile editable" policy (supabase_rls_security.sql:85)
--    for update using (auth.uid()=id or public.is_admin())
--  нь ямар баганыг засахыг хязгаарладаггүй. Тиймээс нэвтэрсэн ЯМАР Ч
--  хэрэглэгч хөтчийн консолоос нийтийн anon түлхүүр + өөрийн JWT-ээр
--      profiles.update({'is_admin': true}).eq('id', <өөрийн id>)
--  гэж өөрийгөө АДМИН болгож чадна → бусдын пост/профайл устгах, бан
--  тавих эрх авна. Мөн бан авсан хэрэглэгч is_banned=false болгож,
--  хэн ч is_verified=true (баталгаажсан тэмдэг) тавьж чадна.
--
--  Засвар: BEFORE INSERT/UPDATE trigger — админ биш хүн эдгээр гурван
--  тугийг өөрчлөх оролдлогыг чимээгүй хуучин утгаар нь буцаана.
--  SQL Editor / service_role (JWT-гүй) дуудлагад хөндөхгүй — та өөрөө
--  SQL-ээр админ томилох боломж хэвээр.
--
--  Supabase → SQL Editor дээр БҮТНЭЭР нь нэг удаа ажиллуулна.
-- ============================================================

create or replace function public.protect_profile_flags()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
  -- SQL Editor / service_role / auth-admin (эцсийн хэрэглэгчийн JWT-гүй) → зөвшөөрнө
  if auth.uid() is null or coalesce(auth.jwt()->>'role', '') = 'service_role' then
    return new;
  end if;

  if tg_op = 'INSERT' then
    if not public.is_admin() then
      new.is_admin    := false;
      new.is_banned   := false;
      new.is_verified := false;
    end if;
  elsif (new.is_admin    is distinct from old.is_admin
      or new.is_banned   is distinct from old.is_banned
      or new.is_verified is distinct from old.is_verified)
     and not public.is_admin() then
    -- Админ биш — тугуудыг хуучнаар нь үлдээнэ (бусад баганын засвар хэвээр)
    new.is_admin    := old.is_admin;
    new.is_banned   := old.is_banned;
    new.is_verified := old.is_verified;
  end if;

  return new;
end
$$;

drop trigger if exists protect_profile_flags on public.profiles;
create trigger protect_profile_flags
  before insert or update on public.profiles
  for each row execute function public.protect_profile_flags();

notify pgrst, 'reload schema';

-- ── ШАЛГАЛТ (заавал биш) ──
-- Одоогийн админууд — зөвхөн хүлээж буй хүмүүс байх ёстой:
--   select id, username, is_admin from public.profiles where is_admin order by username;
