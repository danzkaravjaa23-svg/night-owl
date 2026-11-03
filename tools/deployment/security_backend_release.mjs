// Builds the pending security release only. Never opens a database connection.
import {createHash} from 'node:crypto';
import {readFile, writeFile, mkdir} from 'node:fs/promises';
import {fileURLToPath} from 'node:url';
import path from 'node:path';

const root = path.resolve(path.dirname(fileURLToPath(import.meta.url)), '../..');
const hash = value => createHash('sha256').update(value).digest('hex');
export const securityRepairFiles = [
  'supabase/migrations/202610220001_storage_account_guards.sql',
  'supabase/migrations/202611030001_account_deletion_boundaries.sql',
  'supabase/migrations/202611030002_discovery_analytics_consent.sql',
  'supabase/migrations/202611030003_admin_console.sql',
  'supabase/migrations/202611030004_interaction_boundaries.sql',
];
const checks = {
  adminPre: 'tools/deployment/tests/admin_console_preflight.sql',
  interactionPre: 'tools/deployment/tests/interaction_boundaries_preflight.sql',
  adminPost: 'tools/deployment/tests/admin_console_postflight.sql',
  interactionPost: 'tools/deployment/tests/interaction_boundaries_postflight.sql',
};

function transactionBody(source, file, readOnly = false) {
  const start = readOnly ? /^begin read only;$/gm : /^begin;$/gm;
  if ((source.match(start) ?? []).length !== 1 ||
      (source.match(/^commit;$/gm) ?? []).length !== 1 ||
      !source.trimEnd().endsWith('commit;')) {
    throw new Error(`Expected one explicit outer transaction: ${file}`);
  }
  return source.replace(start, '').replace(/^commit;$/m, '').trim();
}

export async function buildSecurityRepair({evidence = null, metadata = null} = {}) {
  const order = [];
  const assertions = [];
  const bodies = [];
  async function append(file, readOnly = false) {
    const source = await readFile(path.join(root, file), 'utf8');
    const record = {source: file, sha256: hash(source), bytes: Buffer.byteLength(source)};
    (readOnly ? assertions : order).push(record);
    bodies.push(`-- Source: ${file}\n${transactionBody(source, file, readOnly)}`);
  }
  for (const file of securityRepairFiles) {
    if (file.endsWith('202611030003_admin_console.sql')) await append(checks.adminPre, true);
    if (file.endsWith('202611030004_interaction_boundaries.sql')) await append(checks.interactionPre, true);
    await append(file);
  }
  await append(checks.adminPost, true);
  await append(checks.interactionPost, true);
  const sql = `-- Night Owl pending security release. Review the attached manifest before use.
-- The previously installed social/catalog/hosted-RPC migrations are NOT replayed.
-- No existing application, Auth or Storage rows are changed by installation.
-- Existing active admins gain private-post/comment moderation access; no admin
-- identity is granted. Deployment must include that explicit access review.
-- Every prerequisite and final assertion executes before this transaction commits.
begin;
set local lock_timeout='5s';
set local statement_timeout='60s';

${bodies.join('\n\n')}

commit;
`;
  if ((sql.match(/^begin;$/gm) ?? []).length !== 1 ||
      (sql.match(/^commit;$/gm) ?? []).length !== 1) {
    throw new Error('Release must contain exactly one outer transaction');
  }
  return {sql, manifest: {
    prepared: true,
    executed: false,
    order,
    assertions,
    bundle_sha256: hash(sql),
    transaction: {atomic: true, lock_timeout: '5s', statement_timeout: '60s',
      assertions_before_commit: true},
    prerequisites: [
      'Reviewed, already installed social-discovery, OSM catalog and hosted-client RPC schema',
      'Featured-event schema and active protect_profile_flags trigger',
      'Fresh actual metadata and complete recovery metadata saved outside the public app',
      'Explicit review of the active-admin private-post/comment moderation access',
    ],
    access_change: {
      actor: 'Existing profiles with is_admin=true and is_banned!=true only',
      expands: [
        'Enumerate/search post and comment moderation records, including private accounts',
        'Read private post/comment excerpts linked to reports',
        'Read/sign Storage media attached to private posts for moderation',
      ],
      excluded: ['Private stories', 'Private messages', 'Blanket story viewing history', 'Granting admin status'],
      tightens: ['Active-account writes', 'Owner identity', 'Visible-parent interaction access',
        'Mutual-friend Notes with server-controlled expiry', 'RPC-only check-ins', 'All current public-table TRUNCATE'],
    },
    hosted_metadata: metadata,
    local_evidence: evidence,
    limits: [
      'This builder never contacts a hosted database',
      'Synthetic SQL fixtures do not certify concurrent Auth/Storage or native-device workflows',
      'The recovery snapshot is a reference; blindly restoring old policies reopens audited defects',
      'Future schema migrations must preserve the public-table TRUNCATE invariant',
    ],
  }};
}

async function evidenceFrom(directory) {
  const output = {};
  for (const [key, name, expected] of [
    ['interaction', 'interaction-sql.log', 22],
    ['admin', 'admin-sql.log', 24],
    ['hosted_client', 'hosted-rpc-sql.log', true],
  ]) {
    const source = await readFile(path.resolve(directory, name), 'utf8');
    const start = source.lastIndexOf('\n{');
    const result = key === 'hosted_client' && source.startsWith('PASS: hosted RPC') ?
      {passed: true, scope: source.trim()} :
      JSON.parse(source.slice(start < 0 ? 0 : start + 1));
    if (result.passed !== expected) throw new Error(`Unexpected ${key} fixture result: ${result.passed}`);
    output[key] = {log: path.relative(root, path.resolve(directory, name)),
      sha256: hash(source), result};
  }
  return output;
}

if (process.argv[1] && path.resolve(process.argv[1]) === fileURLToPath(import.meta.url)) {
  const args = process.argv.slice(2);
  function option(name, fallback = null) {
    const index = args.indexOf(name);
    if (index < 0) return fallback;
    if (!args[index + 1] || args[index + 1].startsWith('--')) throw new Error(`Missing value: ${name}`);
    return args[index + 1];
  }
  const output = path.resolve(option('--output', path.join(root, 'build/security-backend-release')));
  const evidenceDirectory = option('--evidence-dir');
  const metadataFile = option('--metadata');
  const metadata = metadataFile ? {
    file: path.relative(root, path.resolve(metadataFile)),
    sha256: hash(await readFile(path.resolve(metadataFile))),
    scope: 'Read-only hosted table/constraint/policy/function metadata; no user rows',
  } : null;
  const {sql, manifest} = await buildSecurityRepair({
    evidence: evidenceDirectory ? await evidenceFrom(evidenceDirectory) : null, metadata,
  });
  await mkdir(output, {recursive: true});
  for (const file of securityRepairFiles) {
    await writeFile(path.join(output, path.basename(file)), await readFile(path.join(root, file)));
  }
  for (const file of Object.values(checks)) {
    await writeFile(path.join(output, path.basename(file)), await readFile(path.join(root, file)));
  }
  await writeFile(path.join(output, 'pending-security-repair.sql'), sql);
  await writeFile(path.join(output, 'manifest.json'), JSON.stringify(manifest, null, 2) + '\n');
  console.log(JSON.stringify({prepared: true, executed: false, output,
    bundle_sha256: manifest.bundle_sha256, migrations: manifest.order.length,
    assertions: manifest.assertions.length, evidence: !!manifest.local_evidence}));
}
