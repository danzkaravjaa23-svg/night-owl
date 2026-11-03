-- Source retrieval metadata only; this is NOT an operating-status review.
-- Official OSM map response retrieved 2026-11-03T04:16:56.175846+00:00.
-- Raw SHA-256: a588f590e02d66eb20f2398ad744324102dc17da2c170b5f060e270a72a8dbe6
-- ODbL-1.0 / https://www.openstreetmap.org/copyright
-- Exactly 270 known source identities. No inserts, deletes, business-detail,
-- review-status, schema, API, grant, policy, or owned-venue changes.
begin;
set local lock_timeout = '5s';
set local statement_timeout = '30s';

do $refresh$
declare
  v_refs constant jsonb := $refs$[
    "osm:node:6380522595","osm:node:6066788101","osm:node:6452841082","osm:node:1477522457",
    "osm:node:3894653628","osm:node:4997686922","osm:node:11140275605","osm:node:3899304788",
    "osm:node:3617059622","osm:node:3148656454","osm:node:3900952937","osm:node:11158663509",
    "osm:node:3667041925","osm:node:11140275505","osm:node:3900932239","osm:node:4397420592",
    "osm:node:2531717697","osm:way:244261881","osm:node:3900871989","osm:node:3669885826",
    "osm:node:2293321286","osm:node:1784384900","osm:node:3904328243","osm:node:3667073128",
    "osm:node:2514667763","osm:node:3900874549","osm:node:3673039625","osm:node:13369164710",
    "osm:node:3902505438","osm:node:3674191925","osm:node:2321598633","osm:node:3902503193",
    "osm:node:3902482359","osm:node:3900115346","osm:node:2514801014","osm:node:3913503159",
    "osm:node:2514667790","osm:node:3887636695","osm:node:6066771481","osm:node:3886158498",
    "osm:node:5248486522","osm:node:6066767487","osm:node:7001382885","osm:node:3674314326",
    "osm:node:6066771483","osm:node:5733425521","osm:node:3671250725","osm:node:7494632585",
    "osm:node:5248484023","osm:node:5928074486","osm:node:5928074985","osm:node:2871910101",
    "osm:node:3671246825","osm:node:3669998925","osm:node:5811201356","osm:node:11635124352",
    "osm:way:662430190","osm:node:7756958085","osm:node:6066772586","osm:node:13974096701",
    "osm:node:2952191525","osm:node:14030823601","osm:node:3891278774","osm:node:13089216342",
    "osm:node:13165749001","osm:node:3894615949","osm:node:3886158495","osm:node:8087986164",
    "osm:node:3682095928","osm:node:14155437401","osm:node:14061407901","osm:node:14008238891",
    "osm:node:13784253235","osm:node:3093536509","osm:node:3669882025","osm:node:4310060692",
    "osm:node:3669561374","osm:node:4310331989","osm:node:3886158479","osm:node:11158654706",
    "osm:node:3092049234","osm:node:3910207970","osm:node:3886060488","osm:node:3886060533",
    "osm:node:3902589660","osm:node:3886158492","osm:node:2293341555","osm:node:3896158890",
    "osm:node:3902591670","osm:node:3902583956","osm:node:11158664606","osm:node:6566561785",
    "osm:node:11195429039","osm:node:4029481189","osm:node:3673293728","osm:node:4327660898",
    "osm:node:3093535714","osm:node:12345212301","osm:node:2532391369","osm:node:3891276601",
    "osm:node:2511108878","osm:node:3093532124","osm:node:2882186758","osm:node:11949581869",
    "osm:node:3092061831","osm:node:11158664205","osm:node:11158654708","osm:node:11974488832",
    "osm:node:11782344596","osm:node:3892322872","osm:node:1678362169","osm:node:2532391368",
    "osm:way:244790560","osm:node:14026426284","osm:node:14003594106","osm:node:11158664407",
    "osm:node:11113318505","osm:node:3092025632","osm:node:3886060509","osm:node:11158663708",
    "osm:node:6760903185","osm:node:11158664409","osm:node:3092028446","osm:node:3895137758",
    "osm:node:3673293028","osm:node:3673293727","osm:node:2506789934","osm:node:3617034309",
    "osm:node:3886158490","osm:node:11158664408","osm:node:3894695000","osm:node:3617059620",
    "osm:node:3886158496","osm:node:3909307967","osm:node:3904361575","osm:node:4029477189",
    "osm:node:3671096425","osm:node:3891275402","osm:node:3846177957","osm:node:3902637209",
    "osm:node:11158663505","osm:node:7656869688","osm:node:2321598630","osm:node:3886158475",
    "osm:node:3092032978","osm:node:3091939327","osm:node:2293341567","osm:node:3673294128",
    "osm:node:3092023784","osm:node:3669885525","osm:node:11782313992","osm:node:5955920486",
    "osm:node:3902497620","osm:node:3674314327","osm:node:3902502463","osm:node:2492506196",
    "osm:node:5036727023","osm:node:2293321275","osm:node:3902502577","osm:node:3908087450",
    "osm:node:4029461993","osm:node:4029446695","osm:node:3900125417","osm:node:1533728072",
    "osm:node:4423415597","osm:node:2321753376","osm:node:4029472991","osm:node:2505566060",
    "osm:node:3904391170","osm:node:9735289619","osm:node:3904392041","osm:node:1732841389",
    "osm:node:3904453771","osm:node:3913288464","osm:node:3904361574","osm:node:3902583954",
    "osm:node:3673293227","osm:node:3904412708","osm:node:3090167271","osm:node:3912618483",
    "osm:node:3912826423","osm:node:8032903275","osm:node:3092027965","osm:node:4334961291",
    "osm:node:2520777875","osm:node:3092039505","osm:node:3899233604","osm:node:4327660790",
    "osm:node:4327669289","osm:node:4331632100","osm:node:4334971289","osm:node:4029457357",
    "osm:node:4299257493","osm:node:4423415596","osm:node:3902504976","osm:node:3918580935",
    "osm:node:3666976351","osm:node:2531717710","osm:node:3895309450","osm:node:2532391370",
    "osm:way:220239964","osm:way:220893093","osm:node:3091950389","osm:node:4873123021",
    "osm:node:3092030625","osm:node:3091967288","osm:node:3902458755","osm:node:2520517045",
    "osm:node:3093533172","osm:node:3669882725","osm:node:3904448685","osm:node:4327669189",
    "osm:node:4327589589","osm:node:3902458756","osm:node:7611116886","osm:node:4928823022",
    "osm:node:4971571722","osm:node:11635070329","osm:node:6031081588","osm:node:14200550201",
    "osm:node:3886141371","osm:node:6619064485","osm:node:2321491014","osm:node:3913307364",
    "osm:node:3886060466","osm:node:3886114747","osm:node:3902580405","osm:node:11683919244",
    "osm:node:13977386601","osm:node:3886060510","osm:node:5840933686","osm:node:3673023332",
    "osm:node:11140275405","osm:node:4029443407","osm:node:3904175152","osm:node:4029404089",
    "osm:node:11665397009","osm:node:5696519241","osm:node:3913309340","osm:node:11197862837",
    "osm:node:3899307990","osm:node:3148647474","osm:node:2513546957","osm:node:3957977857",
    "osm:node:1247498078","osm:node:7922616556","osm:node:11633777247","osm:node:14003594071",
    "osm:node:12345212302","osm:node:3899326175","osm:node:11665410082","osm:node:6598255586",
    "osm:node:6510601118","osm:node:4029417789","osm:node:2520683345","osm:node:2520627419",
    "osm:node:4029418689","osm:node:3669887125","osm:node:3912619547","osm:node:3896158876",
    "osm:node:2520627434","osm:node:3895308704","osm:node:3895305590","osm:node:3902576444",
    "osm:node:2495869639","osm:node:3669885825","osm:node:2520627417","osm:node:3913314985",
    "osm:node:3875836173","osm:node:4423415595"
  ]$refs$::jsonb;
  v_repairs constant jsonb := $repairs$[{"ref":"osm:node:3913307364","old_url":"https://www.facebook.com/pages/Coffee-Bean-Shop-Bluemon-Center/211157819063969?fref=ts","new_url":"https://www.facebook.com/pages/Coffee-Bean-Shop-Bluemon-Center/211157819063969"},{"ref":"osm:node:7611116886","old_url":"https://www.facebook.com/centralkavezocoffeeshop/?ref=bookmarks","new_url":"https://www.facebook.com/centralkavezocoffeeshop/"}]$repairs$::jsonb;
  v_retrieved_at constant timestamptz := '2026-11-03T04:16:56.175846+00:00'::timestamptz;
  v_changed integer;
begin
  if to_regclass('public.venue_catalog') is null then
    raise exception 'OSM metadata refresh requires the existing venue catalog';
  end if;
  if (select count(*) from pg_attribute
      where attrelid = 'public.venue_catalog'::regclass and not attisdropped
        and attname in ('ref','venue_id','source_url','source_label',
          'source_retrieved_at','website_url','reviewed_at','reviewed_by')) <> 8 then
    raise exception 'OSM metadata refresh requires the existing source/review columns';
  end if;
  if jsonb_array_length(v_refs) <> 270 or
      (select count(distinct ref) from jsonb_array_elements_text(v_refs) as s(ref)) <> 270 or exists (
      select 1 from jsonb_array_elements_text(v_refs) as s(ref)
      where ref !~ '^osm:(node|way|relation):[1-9][0-9]*$'
    ) or jsonb_array_length(v_repairs) <> 2 then
    raise exception 'OSM metadata refresh identity manifest is invalid';
  end if;

  -- Exact source identity plus unowned/unreviewed guards preserve local edits.
  -- A newer retrieval is authoritative; the fixed timestamp never regresses it.
  -- Website cleanup is an exact old-value match, preserving any changed URL.
  with sources as (
    select ref, 'https://www.openstreetmap.org/' || split_part(ref,':',2) || '/' || split_part(ref,':',3)
      as source_url from jsonb_array_elements_text(v_refs) as s(ref)
  ), repairs as (
    select * from jsonb_to_recordset(v_repairs)
      as r(ref text, old_url text, new_url text)
  )
  update public.venue_catalog as v
    set source_retrieved_at = v_retrieved_at,
      website_url = case when v.website_url = r.old_url then r.new_url
        else v.website_url end
    from sources s left join repairs r on r.ref = s.ref
    where v.ref = s.ref and v.source_url = s.source_url
      and v.source_label = 'OpenStreetMap' and v.venue_id is null
      and v.reviewed_at is null and v.reviewed_by is null
      and (v.source_retrieved_at is null or v.source_retrieved_at <= v_retrieved_at)
      and (v.source_retrieved_at is distinct from v_retrieved_at
        or (r.old_url is not null and v.website_url = r.old_url));
  get diagnostics v_changed = row_count;
  if v_changed > 270 then
    raise exception 'OSM metadata refresh exceeded the 270-row manifest';
  end if;
  raise notice 'OSM source-metadata rows refreshed: % (maximum 270); no operating-status assertion', v_changed;
end
$refresh$;

commit;
