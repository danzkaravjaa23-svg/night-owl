// Builds only the restriction release; it never opens a database connection.
import {createHash} from 'node:crypto';
import {readFile, writeFile, mkdir} from 'node:fs/promises';
import {fileURLToPath} from 'node:url';
import path from 'node:path';
import {securityRepairFiles} from './security_backend_release.mjs';

const root = path.resolve(path.dirname(fileURLToPath(import.meta.url)), '../..');
const hash = value => createHash('sha256').update(value).digest('hex');
const interactionFile = 'supabase/migrations/202611030004_interaction_boundaries.sql';
const adminFile = 'supabase/migrations/202611030003_admin_console.sql';
const preflightFile = 'tools/deployment/tests/interaction_boundaries_preflight.sql';
const postflightFile = 'tools/deployment/tests/interaction_boundaries_postflight.sql';

function body(source, file, readOnly = false) {
  const start = readOnly ? /^begin read only;$/gm : /^begin;$/gm;
  if ((source.match(start) ?? []).length !== 1 ||
      (source.match(/^commit;$/gm) ?? []).length !== 1 ||
      !source.trimEnd().endsWith('commit;')) throw new Error(`Unexpected transaction: ${file}`);
  return source.replace(start, '').replace(/^commit;$/m, '').trim();
}

function replaceOnce(source, before, after, label) {
  if (source.split(before).length !== 2) throw new Error(`Review changed source before building: ${label}`);
  return source.replace(before, after);
}

export async function buildSecurityRestriction({evidence = null} = {}) {
  const order = [];
  const assertions = [];
  const parts = [];
  for (const file of securityRepairFiles.filter(file => file !== adminFile && file !== interactionFile)) {
    const source = await readFile(path.join(root, file), 'utf8');
    order.push({source: file, sha256: hash(source), bytes: Buffer.byteLength(source)});
    parts.push(`-- Source: ${file}\n${body(source, file)}`);
  }
  // 004 needs only the role/maintenance predicate from 003. This helper has no
  // table reads, no SECURITY DEFINER, and no client EXECUTE permission. No admin
  // data/read/action RPC, audit table or media-access exception is installed.
  const admin = await readFile(path.join(root, adminFile), 'utf8');
  const helper = admin.match(/create or replace function public\.admin_console_maintenance\(\) returns boolean\n[\s\S]*?\n\$\$;/g);
  if (helper?.length !== 1) throw new Error('Review changed maintenance helper source');
  const helperSql = `${helper[0]}\nrevoke all on function public.admin_console_maintenance() from public,anon,authenticated;`;
  order.push({source: adminFile, source_sha256: hash(admin),
    included_slice: 'admin_console_maintenance() definition only, client EXECUTE revoked',
    included_sha256: hash(helperSql)});
  parts.push(`-- Narrow compatibility helper only; not the 003 migration.\n${helperSql}`);

  const preflight = await readFile(path.join(root, preflightFile), 'utf8');
  const adaptedPreflight = replaceOnce(preflight,
    " or to_regprocedure('public.admin_console_action(text,uuid,text,uuid)') is null",
    '', 'interaction preflight admin-action existence check');
  assertions.push({source: preflightFile, sha256: hash(preflight),
    adaptation: 'Omit only the admin_console_action existence requirement',
    included_sha256: hash(adaptedPreflight)});
  parts.push(`-- Source: ${preflightFile}; admin action is deliberately withheld.\n${body(adaptedPreflight, preflightFile, true)}`);

  const interaction = await readFile(path.join(root, interactionFile), 'utf8');
  const adaptedInteraction = replaceOnce(interaction,
    "     or to_regprocedure('public.admin_console_action(text,uuid,text,uuid)') is null\n",
    '', 'interaction migration admin-action existence check');
  order.push({source: interactionFile, sha256: hash(interaction),
    adaptation: 'Omit only the admin_console_action existence requirement',
    included_sha256: hash(adaptedInteraction), bytes: Buffer.byteLength(adaptedInteraction)});
  parts.push(`-- Source: ${interactionFile}; admin action is deliberately withheld.\n${body(adaptedInteraction, interactionFile)}`);

  const postflight = await readFile(path.join(root, postflightFile), 'utf8');
  assertions.push({source: postflightFile, sha256: hash(postflight)});
  parts.push(`-- Source: ${postflightFile}\n${body(postflight, postflightFile, true)}`);
  const sql = `-- Night Owl restrictions-only release. No admin moderation access is installed.
-- Previously applied social/catalog/hosted RPC migrations are not replayed.
-- No existing application, Auth or Storage rows are changed by installation.
-- 003 is withheld except for its internal, client-inaccessible role predicate.
begin;
set local lock_timeout='5s';
set local statement_timeout='60s';
do $$ begin
  if exists(select 1 from pg_proc p join pg_namespace n on n.oid=p.pronamespace
    where n.nspname='public' and p.proname in ('admin_console_summary','admin_console_users','admin_console_content','admin_console_reports','admin_console_audit','admin_console_action')) then
    raise exception 'Restriction-only release requires the pre-admin baseline';
  end if;
  perform set_config('nightowl.restriction_read_contract',
    (select md5(string_agg(pg_get_functiondef(p.oid),E'\\n' order by p.oid::regprocedure::text))
      from pg_proc p where p.oid in ('public.social_media_readable(text,text)'::regprocedure,
        'public.can_view_author(uuid)'::regprocedure,'public.is_admin()'::regprocedure,'public.protect_profile_flags()'::regprocedure)),true);
end $$;

${parts.join('\n\n')}

do $$ begin
  if current_setting('nightowl.restriction_read_contract') is distinct from
    (select md5(string_agg(pg_get_functiondef(p.oid),E'\\n' order by p.oid::regprocedure::text))
      from pg_proc p where p.oid in ('public.social_media_readable(text,text)'::regprocedure,
        'public.can_view_author(uuid)'::regprocedure,'public.is_admin()'::regprocedure,'public.protect_profile_flags()'::regprocedure)) then
    raise exception 'Existing private-read/admin flag contract changed';
  end if;
  if has_function_privilege('anon','public.admin_console_maintenance()','EXECUTE')
    or has_function_privilege('authenticated','public.admin_console_maintenance()','EXECUTE')
    or exists(select 1 from pg_proc where oid='public.admin_console_maintenance()'::regprocedure and prosecdef) then
    raise exception 'Maintenance predicate must remain internal and invoker-only';
  end if;
  if exists(select 1 from pg_proc p join pg_namespace n on n.oid=p.pronamespace
    where n.nspname='public' and p.proname in ('admin_console_summary','admin_console_users','admin_console_content','admin_console_reports','admin_console_audit','admin_console_action'))
    or to_regclass('public.admin_audit_log') is not null or to_regnamespace('admin_private') is not null then
    raise exception 'Admin console access must remain withheld';
  end if;
end $$;
commit;
`;
  if ((sql.match(/^begin;$/gm) ?? []).length !== 1 || (sql.match(/^commit;$/gm) ?? []).length !== 1) throw new Error('Expected one outer transaction');
  return {sql, manifest: {
    prepared: true, executed: false, scope: 'Restrictions only; admin moderation access withheld',
    order, assertions, bundle_sha256: hash(sql),
    transaction: {atomic: true, lock_timeout: '5s', statement_timeout: '60s', assertions_before_commit: true},
    withheld: ['003 admin read/action RPCs', 'Admin private-post/comment search', 'Private-post media moderation exception', 'Admin audit and action-context tables'],
    changes_existing_rows: false,
    local_evidence: evidence,
    compatibility: 'Pre-admin hosted baseline only. The original full 003+004 release remains applicable afterward.',
    limits: ['No hosted database was contacted by this builder', 'No new admin status or private-content access is granted'],
  }};
}

if (process.argv[1] && path.resolve(process.argv[1]) === fileURLToPath(import.meta.url)) {
  const output = path.resolve(process.argv[2] ?? path.join(root, 'build/security-restriction-release'));
  let evidence = null;
  if (process.argv[3]) {
    const log = await readFile(path.resolve(process.argv[3]), 'utf8');
    const result = JSON.parse(log.slice(log.lastIndexOf('\n{') + 1));
    if (result.passed !== 10 || result.restrictionsOnly !== true || result.originalFullReleaseCompatible !== true) {
      throw new Error('Expected the complete restriction-only fixture result');
    }
    evidence = {file: path.relative(root, path.resolve(process.argv[3])), sha256: hash(log), result};
  }
  const {sql, manifest} = await buildSecurityRestriction({evidence});
  if (evidence && evidence.result.restrictionSha256 !== manifest.bundle_sha256) {
    throw new Error('Fixture tested a different restriction artifact');
  }
  await mkdir(output, {recursive: true});
  await writeFile(path.join(output, 'pending-restrictions-only.sql'), sql);
  await writeFile(path.join(output, 'manifest.json'), JSON.stringify(manifest, null, 2) + '\n');
  console.log(JSON.stringify({prepared: true, executed: false, output, bytes: Buffer.byteLength(sql), bundle_sha256: manifest.bundle_sha256}));
}
