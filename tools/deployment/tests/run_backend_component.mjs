// Component integration, not a production-schema bootstrap or parity claim.
// Runs only a new official local Supabase stack; never links/logs in/deploys.
import {spawn} from 'node:child_process';
import {createHash, randomBytes, randomUUID} from 'node:crypto';
import {readFile, writeFile, mkdir, cp, chmod, realpath} from 'node:fs/promises';
import {tmpdir} from 'node:os';
import path from 'node:path';
import {fileURLToPath, pathToFileURL} from 'node:url';

const repo = path.resolve(path.dirname(fileURLToPath(import.meta.url)), '../../..');
const project = 'nightowl-component';
const dbContainer = `supabase_db_${project}`;
const apiOrigin = 'http://127.0.0.1:54321';
const evidence = path.join(repo, 'build/backend-component/component-result.json');
const migrations = [
  'supabase/migrations/202610160001_social_discovery.sql',
  'supabase_featured_events.sql',
  'supabase/migrations/202611030001_account_deletion_boundaries.sql',
  'supabase/migrations/202611030003_admin_console.sql',
  'supabase/migrations/202611030005_venue_story_activity.sql',
  'supabase/migrations/202611030007_venue_map_activity.sql',
  'supabase/migrations/202611030008_account_erasure.sql',
  'supabase/migrations/202611030009_ugc_review.sql',
];
class ComponentFailure extends Error {}
function requireCase(condition, label) {
  if (!condition) throw new ComponentFailure(label);
}
export function validateLocalStatus(status) {
  requireCase(status && typeof status === 'object' && !Array.isArray(status), 'invalid local CLI status');
  requireCase(status.API_URL === apiOrigin, 'refusing a noncanonical loopback API');
  const db = new URL(status.DB_URL);
  requireCase(db.protocol === 'postgresql:' && db.hostname === '127.0.0.1' && db.port === '54322' && db.pathname === '/postgres', 'refusing a noncanonical loopback database');
  for (const name of ['ANON_KEY', 'SERVICE_ROLE_KEY']) {
    requireCase(typeof status[name] === 'string' && status[name].length > 40, 'missing generated local API credentials');
    let claims;
    try { claims = JSON.parse(Buffer.from(status[name].split('.')[1], 'base64url').toString()); } catch { /* Refuse malformed credentials. */ }
    requireCase(claims?.role === (name === 'ANON_KEY' ? 'anon' : 'service_role'), 'unexpected generated local credential role');
  }
  return {api: apiOrigin, anon: status.ANON_KEY, service: status.SERVICE_ROLE_KEY};
}
export function validateWorkdir(candidate, temporaryRoot, repository = repo) {
  const value = path.resolve(candidate);
  const temporary = path.resolve(temporaryRoot);
  requireCase(value === path.join(temporary, project), 'refusing a non-disposable component directory');
  requireCase(value !== repository && !value.startsWith(repository + path.sep), 'refusing a repository stack');
  return value;
}
function safeChildEnvironment() {
  const env = {...process.env, SUPABASE_TELEMETRY_DISABLED: 'true', NO_COLOR: '1'};
  // The local CLI generates its own keys. Never forward hosted credentials.
  for (const name of Object.keys(env)) if (/^(SUPABASE_|APPLE_)/.test(name) && name !== 'SUPABASE_TELEMETRY_DISABLED') delete env[name];
  return env;
}
function startProcess(command, args, {input, timeout = 120000, stage = command} = {}) {
  const child = spawn(command, args, {cwd: repo, env: safeChildEnvironment(), stdio: ['pipe', 'pipe', 'pipe']});
  let output = '', error = '';
  const append = (current, bytes) => (current + bytes.toString()).slice(-8 * 1024 * 1024);
  child.stdout.on('data', bytes => { output = append(output, bytes); });
  child.stderr.on('data', bytes => { error = append(error, bytes); });
  // No raw CLI/function output is emitted or saved: it can contain local keys.
  child.stdin.on('error', () => {});
  child.stdin.end(input);
  const completion = new Promise((resolve, reject) => {
    const timer = setTimeout(() => { child.kill('SIGTERM'); reject(new ComponentFailure(`${stage}: deadline exceeded`)); }, timeout);
    child.once('error', () => { clearTimeout(timer); reject(new ComponentFailure(`${stage}: executable unavailable`)); });
    child.once('close', code => {
      clearTimeout(timer);
      if (code === 0) resolve(output);
      else {
        const sqlstate = error.match(/ERROR:\s+([0-9A-Z]{5})\b/)?.[1];
        reject(new ComponentFailure(`${stage}: exit ${code}${sqlstate ? `, SQLSTATE ${sqlstate}` : ''}`));
      }
    });
  });
  // A long-lived functions process is observed later; prevent an early
  // unhandled rejection while readiness polling supplies its own deadline.
  completion.catch(() => {});
  return {child, completion};
}
async function run(command, args, options) { return startProcess(command, args, options).completion; }
async function sql(query, stage = 'local application SQL') {
  return run('docker', ['exec', '-i', dbContainer, 'psql', '-XqAt', '-U', 'postgres', '-d', 'postgres', '-v', 'ON_ERROR_STOP=1', '-v', 'VERBOSITY=sqlstate'], {input: query, stage});
}
async function sqlJson(query) { return JSON.parse((await sql(query)).trim()); }
const quoted = value => {
  requireCase(typeof value === 'string' && /^[0-9a-f-]{36}$/i.test(value), 'invalid synthetic identifier');
  return `'${value}'`;
};
async function localRequest(credentials, pathname, {method = 'GET', bearer, body, binary, timeout = 20000} = {}) {
  requireCase(pathname.startsWith('/') && !pathname.startsWith('//'), 'invalid local API path');
  const headers = {apikey: credentials.anon, ...(bearer ? {Authorization: `Bearer ${bearer}`} : {})};
  if (body !== undefined) headers['Content-Type'] = 'application/json';
  if (binary !== undefined) headers['Content-Type'] = 'application/octet-stream';
  const response = await fetch(apiOrigin + pathname, {method, headers, body: binary ?? (body === undefined ? undefined : JSON.stringify(body)), redirect: 'error', signal: AbortSignal.timeout(timeout)});
  const bytes = new Uint8Array(await response.arrayBuffer());
  let data;
  try { data = JSON.parse(new TextDecoder().decode(bytes)); } catch { /* Binary/empty replies are expected for Storage. */ }
  return {status: response.status, data, bytes};
}
async function until(check, label, timeout = 90000) {
  const deadline = Date.now() + timeout;
  while (Date.now() < deadline) {
    try { if (await check()) return; } catch { /* Startup can precede gateway readiness. */ }
    await new Promise(resolve => setTimeout(resolve, 500));
  }
  throw new ComponentFailure(label);
}
async function cleanup(workdir) {
  // This command is never --all and never targets an existing project.
  await run('supabase', ['stop', '--workdir', workdir, '--project-id', project, '--no-backup'], {stage: 'stop isolated stack', timeout: 90000});
}
async function main() {
  const temporary = process.env.RUNNER_TEMP ?? tmpdir();
  const workdir = validateWorkdir(process.env.NIGHTOWL_COMPONENT_WORKDIR ?? path.join(temporary, project), temporary);
  if (process.argv.includes('--cleanup')) {
    try { await readFile(path.join(workdir, 'supabase/config.toml')); } catch { return; }
    await cleanup(workdir);
    return;
  }
  const started = Date.now();
  const report = {scope: 'real-local-Auth-Storage-Edge-component-integration', production_schema_parity: false,
    apple_live_provider_tested: false, hosted_project_accessed: false,
    source_commit: process.env.GITHUB_SHA ?? null, cli_version: '2.122.1', passed: [], status: 'running'};
  let functions;
  let initialized = false;
  const pass = label => { report.passed.push(label); console.log(`PASS: ${label}`); };
  try {
    // A fresh directory and explicit project ID prevent reuse of a developer's
    // existing local project. CI provides this empty runner-only directory.
    try { await realpath(workdir); throw new ComponentFailure('component directory already exists'); }
    catch (error) { if (error instanceof ComponentFailure) throw error; if (error.code !== 'ENOENT') throw error; }
    await mkdir(workdir, {recursive: false, mode: 0o700});
    await chmod(workdir, 0o700);
    await run('supabase', ['init', '--workdir', workdir], {stage: 'initialize disposable Supabase'});
    initialized = true;
    const configPath = path.join(workdir, 'supabase/config.toml');
    let config = await readFile(configPath, 'utf8');
    config = config.replace(/^project_id\s*=.*$/m, `project_id = "${project}"`);
    config += '\n[functions.delete-account]\nverify_jwt = false\n';
    await writeFile(configPath, config, {mode: 0o600});
    await cp(path.join(repo, 'supabase/functions/delete-account'), path.join(workdir, 'supabase/functions/delete-account'), {recursive: true});
    await run('supabase', ['start', '--workdir', workdir, '--exclude', 'studio,imgproxy,realtime,postgres-meta,logflare,vector,supavisor,mailpit'], {stage: 'start real local Supabase services', timeout: 12 * 60 * 1000});
    const status = JSON.parse(await run('supabase', ['status', '--workdir', workdir, '--output', 'json'], {stage: 'read generated local status'}));
    const credentials = validateLocalStatus(status);
    if (process.env.GITHUB_ACTIONS === 'true') for (const value of [credentials.anon, credentials.service]) console.log(`::add-mask::${value}`);
    const bootstrap = 'tools/deployment/tests/component_application_bootstrap.sql';
    report.source_sha256 = {};
    for (const filename of [bootstrap, ...migrations, 'supabase/functions/delete-account/index.ts', 'supabase/functions/delete-account/apple_revocation.ts']) {
      const source = await readFile(path.join(repo, filename), 'utf8');
      report.source_sha256[filename] = createHash('sha256').update(source).digest('hex');
      if (filename === bootstrap || migrations.includes(filename)) await sql(source, `install ${path.basename(filename)}`);
    }
    // Fixture-only permissive policies supply owner-scoped baseline Storage
    // permissions. Actual 008 then provides its real per-account write guard.
    await sql(`create policy component_owned_storage_read on storage.objects for select to authenticated using(owner_id=auth.uid()::text);
      create policy component_owned_storage_insert on storage.objects for insert to authenticated with check(
        bucket_id in ('avatars','posts','stories','venues') and
        (split_part(name,'/',1)=auth.uid()::text or name='component-legacy/'||auth.uid()::text||'.bin'));
      notify pgrst,'reload schema';`, 'install isolated Storage fixture policies');
    const envfile = path.join(workdir, 'function.env');
    await writeFile(envfile, 'ACCOUNT_DELETION_ENABLED=true\n', {mode: 0o600});
    functions = startProcess('supabase', ['functions', 'serve', '--workdir', workdir, '--env-file', envfile], {stage: 'serve actual erasure Edge source', timeout: 15 * 60 * 1000});
    await until(async () => (await localRequest(credentials, '/functions/v1/delete-account', {method: 'POST', body: {confirmation: 'WAIT'}})).status === 400, 'erasure Edge startup unavailable', 180000);
    pass('official local stack and actual Edge source are reachable');

    const api = (pathname, options) => localRequest(credentials, pathname, options);
    const service = (pathname, options = {}) => api(pathname, {...options, bearer: credentials.service});
    const edge = (body, bearer) => api('/functions/v1/delete-account', {method: 'POST', body: {confirmation: 'DELETE', ...body}, bearer, timeout: 90000});
    async function makeUser(label) {
      const email = `${label}-${randomUUID()}@example.test`;
      const password = randomBytes(30).toString('base64url');
      const created = await service('/auth/v1/admin/users', {method: 'POST', body: {email, password, email_confirm: true}});
      requireCase(created.status === 200 && /^[0-9a-f-]{36}$/i.test(created.data?.id ?? ''), 'synthetic Auth creation failed');
      const id = created.data.id;
      await sql(`insert into profiles(id,username,moderation_status) values(${quoted(id)},'component-${label}','approved');`);
      const session = await api('/auth/v1/token?grant_type=password', {method: 'POST', body: {email, password}});
      requireCase(session.status === 200 && session.data?.user?.id === id && typeof session.data?.access_token === 'string', 'synthetic password sign-in failed');
      return {id, token: session.data.access_token};
    }
    const owner = await makeUser('erased');
    const other = await makeUser('preserved');
    pass('real GoTrue creates and authenticates two disposable accounts');
    const venue = randomUUID(), otherPost = randomUUID(), ownPost = randomUUID(), group = randomUUID();
    await sql(`insert into venues(id,name,owner_id) values(${quoted(venue)},'Shared component venue',${quoted(owner.id)});
      insert into posts(id,user_id,venue_id,caption,moderation_status) values
        (${quoted(ownPost)},${quoted(owner.id)},${quoted(venue)},'Erased authored content','approved'),
        (${quoted(otherPost)},${quoted(other.id)},${quoted(venue)},'Preserved authored content','approved');
      insert into venue_reviews(id,venue_id,user_id,rating,comment,moderation_status) values(gen_random_uuid(),${quoted(venue)},${quoted(other.id)},5,'Preserved review','approved');
      insert into messages(id,sender_id,receiver_id,body) values(gen_random_uuid(),${quoted(owner.id)},${quoted(other.id)},'Disposable direct message');
      insert into group_chats(id,name,created_by) values(${quoted(group)},'Shared component group',${quoted(owner.id)});
      insert into group_members(group_id,user_id) values(${quoted(group)},${quoted(owner.id)}),(${quoted(group)},${quoted(other.id)});
      insert into group_messages(id,group_id,sender_id,body) values(gen_random_uuid(),${quoted(group)},${quoted(owner.id)},'Erased group content'),(gen_random_uuid(),${quoted(group)},${quoted(other.id)},'Preserved group content');`);
    for (const bucket of ['avatars', 'posts', 'stories', 'venues']) {
      const created = await service('/storage/v1/bucket', {method: 'POST', body: {id: bucket, name: bucket, public: false}});
      requireCase(created.status === 200, 'synthetic Storage bucket creation failed');
    }
    const binary = new Uint8Array([78, 73, 71, 72, 84, 0, 255, 10, 3]);
    const ownerPaths = [['posts', `${owner.id}/nested/deep/moment.bin`], ['avatars', `${owner.id}/avatar.bin`],
      ['stories', `${owner.id}/story.bin`], ['venues', `${owner.id}/cover.bin`], ['posts', `component-legacy/${owner.id}.bin`]];
    const otherPath = `${other.id}/preserved.bin`;
    async function upload(bucket, name, user) { return api(`/storage/v1/object/${bucket}/${name}`, {method: 'POST', bearer: user.token, binary}); }
    for (const [bucket, name] of ownerPaths) requireCase((await upload(bucket, name, owner)).status === 200, 'owner binary upload failed');
    requireCase((await upload('posts', otherPath, other)).status === 200, 'other binary upload failed');
    const before = await api(`/storage/v1/object/authenticated/posts/${ownerPaths[0][1]}`, {bearer: owner.token});
    requireCase(before.status === 200 && Buffer.from(before.bytes).equals(Buffer.from(binary)), 'uploaded binary is not retrievable');
    const inventory = await sqlJson(`select json_build_object('owned',(select count(*) from storage.objects where owner_id=${quoted(owner.id)}::text))`);
    requireCase(inventory.owned === ownerPaths.length, 'real Storage ownership metadata was not recorded');
    pass('real Storage persists retrievable binary bytes and trusted ownership metadata');
    requireCase((await edge({action: 'prepare'})).status === 401, 'prepare accepted a missing Auth session');
    requireCase((await edge({action: 'status', receipt_token: randomBytes(32).toString('base64url')})).status === 404, 'unknown receipt was accepted');
    const prepared = await edge({action: 'prepare', client_platform: 'native'}, owner.token);
    requireCase(prepared.status === 200 && prepared.data?.user_id === owner.id && prepared.data?.apple_required === false && /^[A-Za-z0-9_-]{43}$/.test(prepared.data?.receipt_token ?? ''), 'HTTP erasure preparation failed');
    const receipt = prepared.data.receipt_token;
    requireCase((await edge({action: 'delete', receipt_token: receipt})).status === 401, 'receipt alone started account erasure');
    requireCase((await service(`/auth/v1/admin/users/${owner.id}`)).status === 200, 'preparation erased Auth prematurely');
    const latePath = `${owner.id}/prepared-upload.bin`;
    requireCase((await upload('posts', latePath, owner)).status === 200, 'preparation incorrectly froze account writes');
    ownerPaths.push(['posts', latePath]);
    pass('real HTTP preparation requires Auth and a receipt cannot initiate deletion');

    const hash = createHash('sha256').update(receipt).digest('hex');
    const lease = randomUUID();
    const control = (action, leaseId = lease) => service('/rest/v1/rpc/account_erasure_control', {method: 'POST', body: {p_action: action, p_user: owner.id, p_receipt_hash: hash, p_lease: leaseId}});
    const secondLease = randomUUID();
    const claims = await Promise.all([control('claim'), control('claim', secondLease)]);
    requireCase(claims.filter(r => r.status === 200).length === 1 && claims.filter(r => r.data?.code === '55P03').length === 1, 'real concurrent claims did not exclude one worker');
    const activeLease = claims[0].status === 200 ? lease : secondLease;
    const statusDuring = await edge({action: 'status', receipt_token: receipt});
    requireCase(statusDuring.status === 202 && statusDuring.data?.processing === true, 'running receipt recovery state incorrect');
    const writes = await Promise.all([
      api('/rest/v1/posts', {method: 'POST', bearer: owner.token, body: {id: randomUUID(), user_id: owner.id, caption: 'Blocked concurrent content'}}),
      upload('posts', `${owner.id}/blocked-after-claim.bin`, owner),
      api('/rest/v1/posts', {method: 'POST', bearer: other.token, body: {id: randomUUID(), user_id: other.id, caption: 'Preserved concurrent content'}}),
      upload('posts', `${other.id}/concurrent-preserved.bin`, other),
    ]);
    requireCase(writes[0].status >= 400 && writes[0].data?.code === '42501' && writes[1].status >= 400, 'claimed account still accepts PostgREST or Storage writes');
    requireCase(writes[2].status === 201 && writes[3].status === 200, 'claim blocked another account');
    requireCase((await edge({action: 'delete', receipt_token: receipt}, owner.token)).status === 409, 'active worker lease was bypassed');
    requireCase((await control('failed', activeLease)).status === 200, 'durable failure checkpoint could not be recorded');
    pass('real concurrent claims exclude a worker and freeze only the erasing member');
    const deleted = await edge({action: 'delete', receipt_token: receipt}, owner.token);
    requireCase(deleted.status === 200 && deleted.data?.ok === true && deleted.data?.user_id === owner.id, 'real HTTP deletion did not resume and finish');
    pass('actual Edge resumes a durable failed job and hard-deletes through GoTrue');
    requireCase((await service(`/auth/v1/admin/users/${owner.id}`)).status === 404, 'erased Auth user still exists');
    const erasedSession = await api('/auth/v1/user', {bearer: owner.token});
    requireCase([401, 403, 404].includes(erasedSession.status), 'GoTrue still accepts the deleted user');
    requireCase((await api('/auth/v1/user', {bearer: other.token})).status === 200, 'other Auth account was damaged');
    const rows = await sqlJson(`select json_build_object(
      'profile',(select count(*) from profiles where id=${quoted(owner.id)}),
      'own_posts',(select count(*) from posts where user_id=${quoted(owner.id)}),
      'own_messages',(select count(*) from messages where sender_id=${quoted(owner.id)} or receiver_id=${quoted(owner.id)}),
      'venue',(select count(*) from venues where id=${quoted(venue)} and owner_id is null),
      'other_post',(select count(*) from posts where id=${quoted(otherPost)}),
      'other_review',(select count(*) from venue_reviews where user_id=${quoted(other.id)}),
      'shared_group',(select count(*) from group_chats where id=${quoted(group)} and created_by is null),
      'other_group_message',(select count(*) from group_messages where group_id=${quoted(group)} and sender_id=${quoted(other.id)}))`);
    requireCase(rows.profile === 0 && rows.own_posts === 0 && rows.own_messages === 0 && rows.venue === 1 && rows.other_post === 1 && rows.other_review === 1 && rows.shared_group === 1 && rows.other_group_message === 1, 'real Auth cascade or shared-content preservation failed');
    pass('real Auth absence and audited FK cascades preserve other members and shared places');
    for (const [bucket, name] of ownerPaths) {
      const absent = await service(`/storage/v1/object/authenticated/${bucket}/${name}`);
      requireCase([400, 404].includes(absent.status) && ['NoSuchKey', 'not_found', 'Object not found', 'Not found'].some(code => absent.data?.error === code || absent.data?.message === code || absent.data?.code === code), 'service-authorized erased binary absence was not confirmed');
    }
    const remainingBinary = await api(`/storage/v1/object/authenticated/posts/${otherPath}`, {bearer: other.token});
    requireCase(remainingBinary.status === 200 && Buffer.from(remainingBinary.bytes).equals(Buffer.from(binary)), 'other member binary was erased');
    const remaining = await sqlJson(`select json_build_object('objects',(select count(*) from storage.objects where owner_id=${quoted(owner.id)}::text))`);
    requireCase(remaining.objects === 0, 'owned Storage metadata remains');
    pass('real Storage API removes owner binary files including legacy paths and preserves others');
    const recovered = await edge({action: 'status', receipt_token: receipt});
    const recoveredAgain = await edge({action: 'status', receipt_token: receipt});
    requireCase(recovered.status === 200 && recovered.data?.ok === true && recovered.data?.user_id === owner.id && recoveredAgain.status === 200, 'receipt-only completion recovery after Auth erasure failed');
    const stale = await api('/rest/v1/profiles', {method: 'POST', bearer: owner.token, body: {id: owner.id, username: 'blocked-resurrection'}});
    requireCase(stale.status >= 400 && stale.data?.code === '42501', 'stale JWT recreated an erased profile');
    pass('receipt-only repeated recovery works after Auth removal and stale JWT resurrection fails');
    report.component_images = (await run('docker', ['ps', '--format', '{{.Names}} {{.Image}}'], {stage: 'inventory official component images'})).split('\n').filter(line => line.split(' ')[0].endsWith('_' + project));
    report.status = 'passed';
  } catch (error) {
    report.status = 'failed';
    report.failure = error instanceof ComponentFailure ? error.message : 'unexpected component runner failure';
    console.error(`FAIL: ${report.failure}`);
    process.exitCode = 1;
  } finally {
    if (functions) functions.child.kill('SIGTERM');
    if (initialized) {
      try { await cleanup(workdir); } catch { report.cleanup = 'failed; workflow finalizer will retry'; process.exitCode = 1; }
    }
    report.elapsed_seconds = Math.round((Date.now() - started) / 1000);
    report.passed_count = report.passed.length;
    await mkdir(path.dirname(evidence), {recursive: true});
    await writeFile(evidence, JSON.stringify(report, null, 2) + '\n');
  }
}
if (process.argv[1] && import.meta.url === pathToFileURL(path.resolve(process.argv[1])).href) await main();
