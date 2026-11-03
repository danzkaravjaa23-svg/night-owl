// Synthetic in-memory PostgreSQL only. Never connects to a hosted database.
// Usage: node tools/deployment/verify_osm_refresh.mjs /absolute/path/to/pglite/dist/index.js [postflight.sql]
import assert from 'node:assert/strict';
import {readFile} from 'node:fs/promises';
import {pathToFileURL} from 'node:url';
if (!process.argv[2]) throw new Error('Pass the local PGlite module path');
const {PGlite} = await import(pathToFileURL(process.argv[2]).href);
const db = new PGlite();
const read = file => readFile(new URL('../../' + file, import.meta.url), 'utf8');
const migration = await read('supabase/migrations/202611030006_refresh_osm_source_metadata.sql');
const refs = JSON.parse(migration.match(/\$refs\$(.*?)\$refs\$/s)[1]);
const sources = refs.map(ref => ({
  ref,
  source_url: 'https://www.openstreetmap.org/' + ref.split(':')[1] + '/' + ref.split(':')[2],
}));
const repairs = JSON.parse(migration.match(/\$repairs\$(.*?)\$repairs\$/s)[1]);
const target = migration.match(/v_retrieved_at constant timestamptz := '([^']+)'/)[1];
const catalog = JSON.parse(await read('assets/data/ulaanbaatar_osm_venues.json'));
let passed = 0;
const check = (name, body) => {body(); passed++; console.log(`PASS: ${name}`);};
const rows = async () => (await db.query('select * from public.venue_catalog order by ref')).rows;
const byRef = entries => new Map(entries.map(row => [row.ref, row]));
const scalar = async sql => Object.values((await db.query(sql)).rows[0])[0];
const detail = row => Object.fromEntries(Object.entries(row).filter(([key]) => !['source_retrieved_at', 'website_url'].includes(key)));
const snapshot = async () => ({
  classes: (await db.query(`select c.relname,c.relkind,c.relrowsecurity,c.relforcerowsecurity,c.relacl
    from pg_class c join pg_namespace n on n.oid=c.relnamespace
    where n.nspname='public' order by c.relname`)).rows,
  policies: (await db.query(`select polname,polcmd,polpermissive,polroles,
    pg_get_expr(polqual,polrelid) as using_expression,pg_get_expr(polwithcheck,polrelid) as check_expression
    from pg_policy order by polname`)).rows,
  functions: (await db.query(`select p.proname,p.proacl,pg_get_functiondef(p.oid) as definition
    from pg_proc p join pg_namespace n on n.oid=p.pronamespace
    where n.nspname='public' order by p.oid`)).rows,
});
try {
  check('fixed manifest equals the attributed bundled source identities', () => {
    assert.equal(sources.length, 270);
    assert.equal(new Set(sources.map(row => row.ref)).size, 270);
    assert.deepEqual(sources, catalog.venues.map(row => ({ref: row.id, source_url: row.source_url})));
    assert.equal(target, catalog.retrievedAt);
    assert.equal(repairs.length, 2);
  });
  await db.exec(`create role anon; create role authenticated;
    create table public.venue_catalog (
      ref text primary key,venue_id uuid unique,name text not null,venue_type text,address text,district text,
      lat double precision,lng double precision,cover_url text,phone text,website_url text,
      source_url text,source_label text,source_retrieved_at timestamptz,hours text,
      price_min integer,price_max integer,menu_url text,vibes text[] not null default '{}',
      reviewed_at timestamptz,reviewed_by uuid
    );
    alter table public.venue_catalog enable row level security;
    create policy social_catalog_read on public.venue_catalog for select using(true);
    grant select on public.venue_catalog to anon,authenticated;
    revoke insert,update,delete on public.venue_catalog from anon,authenticated;
    create table public.fixture_updates(ref text);
    create function public.fixture_watch_update() returns trigger language plpgsql as $$
    begin
      if (to_jsonb(new)-'source_retrieved_at'-'website_url') is distinct from
          (to_jsonb(old)-'source_retrieved_at'-'website_url') then
        raise exception 'Unexpected business-detail or identity mutation';
      end if;
      insert into public.fixture_updates values(new.ref);
      return new;
    end $$;
    create trigger fixture_update before update on public.venue_catalog
      for each row execute function public.fixture_watch_update();`);
  for (const [index, source] of sources.entries()) {
    const repair = repairs.find(row => row.ref === source.ref);
    await db.query(`insert into public.venue_catalog
      (ref,name,venue_type,address,district,lat,lng,phone,website_url,source_url,source_label,
        source_retrieved_at,hours,price_min,price_max,menu_url,vibes)
      values($1,$2,'cafe','Synthetic local address','Fixture district',47.91,106.92,'+976-00000000',
        $3,$4,'OpenStreetMap','2026-10-05T04:34:47.342639+00:00','Local owner hours',100,200,
        'https://owner.invalid/menu',array['local fixture'])`,
      [source.ref, `Synthetic place ${index}`, repair?.old_url ?? 'https://owner.invalid/custom', source.source_url]);
  }
  const ordinary = sources.filter(source => !repairs.some(repair => repair.ref === source.ref));
  const guards = ordinary.slice(0, 6).map(source => source.ref);
  // The watcher guards only the migration, so fixture setup temporarily disables it.
  await db.exec('alter table public.venue_catalog disable trigger fixture_update');
  await db.query(`update public.venue_catalog set venue_id='10000000-0000-0000-0000-000000000001' where ref=$1`, [guards[0]]);
  await db.query(`update public.venue_catalog set reviewed_at='2026-10-20T00:00:00Z',reviewed_by='10000000-0000-0000-0000-000000000002' where ref=$1`, [guards[1]]);
  await db.query(`update public.venue_catalog set reviewed_by='10000000-0000-0000-0000-000000000002' where ref=$1`, [guards[2]]);
  await db.query(`update public.venue_catalog set source_label='Owner supplied' where ref=$1`, [guards[3]]);
  await db.query(`update public.venue_catalog set source_url='https://owner.invalid/overridden-source' where ref=$1`, [guards[4]]);
  await db.query(`update public.venue_catalog set source_retrieved_at='2026-11-04T00:00:00Z' where ref=$1`, [guards[5]]);
  await db.query('update public.venue_catalog set source_retrieved_at=null where ref=$1', [ordinary[6].ref]);
  await db.query(`insert into public.venue_catalog(ref,name,source_url,source_label,source_retrieved_at)
    values('osm:node:999999999999','Unlisted fixture','https://www.openstreetmap.org/node/999999999999','OpenStreetMap','2026-01-01T00:00:00Z'),
      ('10000000-0000-0000-0000-000000000003','Business fixture','https://owner.invalid','Owner supplied','2026-01-01T00:00:00Z')`);
  await db.exec('alter table public.venue_catalog enable trigger fixture_update;truncate public.fixture_updates');
  const before = byRef(await rows());
  const beforeSchema = await snapshot();
  await db.exec(migration);
  const after = byRef(await rows());
  check('only the 264 eligible rows are updated; no row is inserted or deleted', () => {
    assert.equal(after.size, before.size);
    assert.equal(after.size, 272);
  });
  assert.equal(await scalar('select count(*)::int from public.fixture_updates'), 264);
  check('source date advances for eligible null/old retrievals', () => {
    for (const source of sources.filter(source => !guards.includes(source.ref))) {
      assert.equal(after.get(source.ref).source_retrieved_at.toISOString(), new Date(target).toISOString());
    }
  });
  check('business-linked, reviewed, reviewer-only, different-source and newer rows are untouched', () => {
    for (const ref of guards) assert.deepEqual(after.get(ref), before.get(ref));
    assert.deepEqual(after.get('osm:node:999999999999'), before.get('osm:node:999999999999'));
    assert.deepEqual(after.get('10000000-0000-0000-0000-000000000003'), before.get('10000000-0000-0000-0000-000000000003'));
  });
  check('all business fields, identities, coordinates and review flags are preserved', () => {
    for (const [ref, row] of after) assert.deepEqual(detail(row), detail(before.get(ref)));
  });
  check('only the two exactly recorded old tracking URLs are cleaned', () => {
    for (const repair of repairs) assert.equal(after.get(repair.ref).website_url, repair.new_url);
    for (const source of sources.filter(source => !repairs.some(repair => repair.ref === source.ref))) {
      assert.equal(after.get(source.ref).website_url, before.get(source.ref).website_url);
    }
  });
  if (process.argv[3]) {
    const postflight = await readFile(process.argv[3], 'utf8');
    const receipt = (await db.query(postflight)).rows[0].osm_source_metadata_verification;
    check('read-only postflight distinguishes eligible, skipped, newer and cleaned rows', () => {
      assert.equal(receipt.manifest_count, 270);
      assert.equal(receipt.present_count, 270);
      assert.equal(receipt.eligible_count, 265);
      assert.equal(receipt.at_target_retrieval, 264);
      assert.equal(receipt.newer_retrieval_preserved, 1);
      assert.equal(receipt.eligible_older_or_missing, 0);
      assert.equal(receipt.eligible_old_tracking_urls, 0);
      assert.equal(receipt.cleaned_tracking_urls, 2);
      assert.equal(receipt.business_status_verified, false);
    });
  }
  const afterSchema = await snapshot();
  check('schema, functions, grants and RLS policies remain unchanged', () => assert.deepEqual(afterSchema, beforeSchema));
  await db.exec('truncate public.fixture_updates');
  await db.exec(migration);
  const repeated = byRef(await rows());
  check('idempotent repeat preserves every row', () => assert.deepEqual(repeated, after));
  assert.equal(await scalar('select count(*)::int from public.fixture_updates'), 0);
  await db.exec('alter table public.venue_catalog disable trigger fixture_update');
  await db.query(`update public.venue_catalog set website_url='https://owner.invalid/new-website',source_retrieved_at='2026-10-01T00:00:00Z' where ref=$1`, [repairs[0].ref]);
  await db.query(`update public.venue_catalog set website_url=$2,source_retrieved_at='2026-11-04T00:00:00Z' where ref=$1`, [repairs[1].ref, repairs[1].old_url]);
  await db.exec('alter table public.venue_catalog enable trigger fixture_update;truncate public.fixture_updates');
  await db.exec(migration);
  const adjusted = byRef(await rows());
  check('manually changed website survives while its source date refreshes', () => {
    assert.equal(adjusted.get(repairs[0].ref).website_url, 'https://owner.invalid/new-website');
    assert.equal(adjusted.get(repairs[0].ref).source_retrieved_at.toISOString(), new Date(target).toISOString());
  });
  check('newer source metadata prevents even a matching old tracking URL from being replaced', () => {
    assert.equal(adjusted.get(repairs[1].ref).website_url, repairs[1].old_url);
    assert.equal(adjusted.get(repairs[1].ref).source_retrieved_at.toISOString(), '2026-11-04T00:00:00.000Z');
  });
  assert.equal(await scalar('select count(*)::int from public.fixture_updates'), 1);
  const badManifest = migration.replace(`"${sources[0].ref}"`, `"${sources[1].ref}"`);
  await assert.rejects(db.exec(badManifest), /identity manifest is invalid/);
  await db.exec('rollback');
  check('invalid duplicate manifest fails atomically', () => {});
  assert.deepEqual(byRef(await rows()), adjusted);
  await db.exec('alter table public.venue_catalog disable trigger fixture_update;alter table public.venue_catalog drop column reviewed_by');
  await assert.rejects(db.exec(migration), /requires the existing source\/review columns/);
  await db.exec('rollback');
  check('missing review prerequisite fails without writes', () => {});
  assert.equal(await scalar('select count(*)::int from public.fixture_updates'), 1);
  console.log(`PASS: ${passed} OSM source-metadata fixture groups; in-memory only`);
} finally {
  await db.close();
}
