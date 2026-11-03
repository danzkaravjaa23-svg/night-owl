import assert from 'node:assert/strict';
import test from 'node:test';
import {validateLocalStatus, validateWorkdir} from './run_backend_component.mjs';
const key = role => `local.${Buffer.from(JSON.stringify({role})).toString('base64url')}.disposable-signature`;
const local = {API_URL: 'http://127.0.0.1:54321', DB_URL: 'postgresql://postgres:local@127.0.0.1:54322/postgres', ANON_KEY: key('anon'), SERVICE_ROLE_KEY: key('service_role')};
test('accepts only exact local API and database endpoints with expected local key roles', () => {
  assert.equal(validateLocalStatus(local).api, local.API_URL);
  for (const API_URL of ['https://example.supabase.co', 'http://localhost:54321', 'http://127.0.0.1:9999', 'http://127.0.0.1:54321@evil.test']) assert.throws(() => validateLocalStatus({...local, API_URL}));
  for (const DB_URL of ['postgresql://postgres:x@remote.test:54322/postgres', 'postgresql://postgres:x@127.0.0.1:54322/production', 'postgresql://postgres:x@127.0.0.1:54323/postgres']) assert.throws(() => validateLocalStatus({...local, DB_URL}));
  assert.throws(() => validateLocalStatus({...local, SERVICE_ROLE_KEY: key('authenticated')}));
});
test('cleanup directory must be this one disposable project below the temp root', () => {
  assert.equal(validateWorkdir('/private/tmp/nightowl-component', '/private/tmp', '/workspace/repo'), '/private/tmp/nightowl-component');
  for (const candidate of ['/workspace/repo', '/workspace/repo/supabase', '/private/tmp', '/private/tmp/another-project', '/private/tmp/nightowl-component/../production']) assert.throws(() => validateWorkdir(candidate, '/private/tmp', '/workspace/repo'));
});
