// Alternative to the native PostgreSQL fixture runner. Accepts an explicitly
// supplied official @electric-sql/pglite module, uses only an in-memory database,
// and executes the same SQL authorization checks. No application DB is accessed.
import assert from 'node:assert/strict';
import { readFile } from 'node:fs/promises';
import { fileURLToPath, pathToFileURL } from 'node:url';
import path from 'node:path';

const modulePath = process.argv[2];
if (!modulePath || !path.isAbsolute(modulePath)) {
  throw new Error('Pass the absolute path to @electric-sql/pglite/dist/index.js');
}
const { PGlite } = await import(pathToFileURL(modulePath).href);
const root = path.resolve(path.dirname(fileURLToPath(import.meta.url)), '../../..');
const read = (file) => readFile(path.join(root, file), 'utf8');
const db = new PGlite();
try {
  await db.exec(await read('tools/deployment/tests/featured_events_fixture.sql'));
  const migration = await read('supabase_featured_events.sql');
  await assert.rejects(db.exec(migration), /protect_profile_flags/);
  await db.exec('ROLLBACK');
  await db.exec("SELECT public.fixture_assert(to_regclass('public.event_features') IS NULL, 'migration rolled back')");
  const protection = await read('supabase_protect_profile_flags.sql');
  const migrationBody = migration.replace(/^begin;$/m, '').replace(/^commit;$/m, '');
  await db.exec(`BEGIN;\n${protection}\n${migrationBody}\nCOMMIT;`);
  await db.exec(migration);
  await db.exec(await read('tools/deployment/tests/featured_events_security.sql'));
  const version = await db.query('SELECT version()');
  console.log(JSON.stringify({
    scope: 'synthetic in-memory PostgreSQL through PGlite',
    postgresVersion: version.rows[0].version,
    missingSecurityPrerequisiteRefused: true,
    companionProtectionAndFeatureMigrationAppliedAtomically: true,
    migrationAtomicAndRepeatable: true,
    ordinaryAndBannedUserMutationsRefused: true,
    anonymousReadAndExpiryVerified: true,
    adminSelectReorderRemoveVerified: true,
  }, null, 2));
} finally {
  await db.close();
}
