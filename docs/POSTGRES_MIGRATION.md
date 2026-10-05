# Supabase → independent PostgreSQL migration

Status on 2026-10-05: migration tooling, 59 offline safety checks and a real local PostgreSQL 17.11 export/restore/verification drill are prepared and passing. The drill used newly created synthetic fixture databases only. A separate read-only dashboard snapshot has captured 60 public/auth/storage tables and 1,948 rows, plus schema inventory; it is marked completeDatabaseBackup:false and is a supplemental rescue artifact. No complete actual PostgreSQL archive/role export, production target restore, account conversion, or application cutover has been performed. Private source/target connection files and a confirmed deployment host are still required.

The live read-only schema inventory confirmed PostgreSQL 17.6 and plpgsql, pg_stat_statements, uuid-ossp, pgcrypto, supabase_vault, pg_cron and pg_trgm. The three-schema dashboard row snapshot does not establish a complete backup of extension-owned Vault/cron data, global roles, sequences, large objects, encryption material or external service settings. The private source database password is still pending; no full pg_dump/role backup has run. All 96 public-media objects (229,492,895 bytes) have been downloaded and independently checksum-verified; a persistent private copy of these files and the supplemental snapshots is saved outside the Git repository. These local backups do not establish a destination restore or final write-frozen cutover.

Supabase's database is already PostgreSQL. Removing Supabase also means replacing its Auth, Storage HTTP API, PostgREST access configuration, Realtime transport, Edge Functions and provider/email settings. A database copy alone does not supply those services. Night Owl SQL uses auth.users, auth.uid(), the authenticated role, Storage policies, and the supabase_realtime publication; keep their security behavior when adapting to the independent backend. The live schema, not the collection of local SQL files, is the migration source.

The source lacks `dm_conversations`, `create_group` and `check_in_venue`. A [target-only additive patch](../backend/patches/README.md) supplies these client contracts after restore and ownership review; local PostgreSQL tests with fictional data cover complete unread history, bans/blocks, transactional rollback and concurrent venue swaps/group creation. The mutation RPCs require READ COMMITTED isolation. The patch has not modified the managed source or the empty migration staging target. Client RPC errors no longer trigger a direct-table fallback in PostgreSQL mode; managed mode retains only the explicitly missing-function fallback. This does not repair inherited direct-table policies, which still require target authorization review and real signed API tests before cutover.

## What the tools preserve

tools/migration/migrate.py uses Python's standard library and libpq command-line clients. All actions default to an offline plan. Add --execute explicitly to run one action.

The source is read only (default_transaction_read_only=on, repeatable read, no source mutation commands). A held exported PostgreSQL snapshot is shared by:

- A full custom-format pg_dump archive: application and platform schemas, objects, data, original ownership/grants, and PostgreSQL large objects.
- A separate explicit all-table data archive to preserve inventoried non-system table data that a normal dump may omit because an extension owns a table. It is a rescue artifact; never replay it over the full restored data without a reviewed per-table plan.
- A table/materialized-view inventory with exact row counts and SHA256 digests of sorted canonical JSON rows, sequence state, and PostgreSQL large-object page digests. Foreign tables require a separate external-data plan; their presence refuses a supposedly full export.
- Complete storage.buckets / storage.objects metadata for subsequent binary file download.

A separate pg_dumpall --roles-only --no-role-passwords preserves role definitions without login passwords. Global role definitions and sequence values are not protected by the shared row snapshot, so source writes/role changes must stop during the final export. Managed role secrets and platform settings are outside this logical export.

Every artifact has a SHA256/size manifest. Export folders are private and **must be outside every Git checkout**, including ignored build/ folders. Files are 600, directories 700; no database password, service key, Auth hash, private message or private image belongs in GitHub or a web build. Console errors suppress raw SQL/HTTP error details. Failed exports have no success manifest and are never accepted for restore.

Storage export downloads each object from the authenticated Storage API, including private buckets, with a server-side service key read from a private local file. Downloads are streamed, redirects are refused, object filenames are SHA256 identifiers rather than untrusted bucket paths, and the private manifest maps them back to their original bucket/name. Bucket metadata, empty buckets, object metadata, object count, byte sizes and each binary's SHA256 are preserved. Objects that fail to download or differ from snapshot byte sizes make the export incomplete.

The scripts do not delete the source project, stop users writing, upload private data to another service, apply privileged source roles automatically, create/drop databases, rotate credentials or switch production configuration.

## Prerequisites and private configuration

Install Python 3.10+ and psql, pg_dump, pg_dumpall, pg_restore. Use a matching PostgreSQL client release that supports the source version; the target must be the same PostgreSQL major version or newer. The local Postgres.app 17.11 runtime now provides these clients at /tmp/night-owl-postgres-runtime/Postgres.app/Contents/Versions/17/bin. Add this directory to PATH for the prepared runtime. A disposable local PostgreSQL server was tested; Docker was not used. The production host and its dependencies remain separate setup.

Use a direct source connection or session pooler, not a transaction pooler. Create libpq service and password files outside the repository, with 600 permissions. Use the source database administrator/read access sufficient to read **all** schemas and roles; public/anonymous API credentials cannot export all private data.

A service file can have two independently named entries:

    [nightowl_source]
    host=
    port=5432
    dbname=
    user=
    sslmode=verify-full
    sslrootcert=

    [nightowl_staging]
    host=
    port=5432
    dbname=
    user=
    sslmode=verify-full
    sslrootcert=

Fill connection details privately. Store each password in the private PGPASSFILE using libpq's documented escaped host:port:database:user:password format. Do not put connection URLs or passwords in a command or chat. Source and destination aliases must point to different databases. Set the independent exact staging database name as an additional guard.

Use tools/migration/.env.example as a list of environment variables; load the filled configuration from outside the repository. Do not commit the filled version. A private Storage key file contains only the source service-role key. It is needed only for binary downloads and is never sent to a destination.

## Private credential preparation

tools/migration/prepare_pgpass.py combines a private raw source password file with a matching target entry from an existing private passfile. It reads an explicit private libpq service file, escapes colons/backslashes for libpq, preserves password whitespace, and creates a **new** 600 passfile. It refuses blank/multiline passwords, embedded service passwords/options, insecure file/directory permissions, arbitrary symlinks, Git paths, identical source/target identities and existing output files. Remote service entries must require TLS; loopback test entries may use disabled TLS.

    python3 tools/migration/prepare_pgpass.py --service-file PRIVATE_SERVICE_FILE --source-password-file PRIVATE_RAW_SOURCE_PASSWORD --target-passfile PRIVATE_TARGET_PASSFILE --output NEW_PRIVATE_PASSFILE
    python3 tools/migration/prepare_pgpass.py --execute --service-file PRIVATE_SERVICE_FILE --source-password-file PRIVATE_RAW_SOURCE_PASSWORD --target-passfile PRIVATE_TARGET_PASSFILE --output NEW_PRIVATE_PASSFILE

The default is an offline plan that does not even read a password. Set PGPASSFILE to the new file after preparation. Neither command prints a password or connects to a database.

The role export uses --roles-only --no-role-passwords and explicitly selects the source database for its initial connection. PostgreSQL documents that --no-role-passwords reads pg_roles instead of restricted pg_authid. This avoids requesting database-role hashes; it does **not** omit the application Auth password hashes already preserved in auth.users. Those hashes, tokens and private table contents stay in private archives.

Managed Supabase roles can still lack access to an internal table/extension or RLS-protected records. The tools fail rather than silently export a partial table set. Errors give static authentication/permissions/snapshot/network advice; detailed errors are saved only in private 600 diagnostic files within the export directory. Those logs can contain Auth hashes or private SQL rows and must never be pasted into chat or uploaded to GitHub. Snapshot import requires a direct connection or session pooler.

## Export and verify locally

First inspect the offline plan:

    python3 tools/migration/migrate.py export-db

After private environment variables are set and access is confirmed, choose a **new** private export folder:

    python3 tools/migration/migrate.py export-db --execute
    python3 tools/migration/migrate.py export-storage --execute
    python3 tools/migration/migrate.py verify-storage --execute

Existing export directories are never overwritten. If an export fails, preserve that incomplete folder privately for diagnosis and use a new folder for the next complete attempt.

The database snapshot keeps ordinary table contents internally consistent while the source remains online; sequences/global roles still require a write freeze. Storage bytes cannot share the PostgreSQL snapshot. Before the final export, put the source application/API in a write-free maintenance window, stop background writes, and keep database/Storage writes frozen until the final exports and checks finish. Otherwise deleted/overwritten objects or new posts between the database and Storage export can be missing even when a snapshot is valid. A successful local Storage check verifies archived files, not a destination upload.

Exact row digests require sorting every table's JSON rows and can be expensive on a large database. Schedule the export appropriately, monitor available disk/DB resources, and retain a conventional backup as well.

## Supplemental public-media rescue without database credentials

tools/migration/export_public_media.py can use the private dashboard core snapshot plus independent schema inventory to rescue existing **public** Storage binaries while database connection credentials are pending. It requires explicitly declared expected table/object/bucket counts, complete object byte-size metadata, unique table/object identities, and identical bucket identities in both inputs. Every bucket must have public:true in both inputs; private/missing/versioned/deletion-marker objects are refused. It reads no keys and sends no authorization/API-key headers.

For the captured source inventory, the independent counts are 60 tables, 96 objects and 4 buckets. This is a local metadata validation result; download completion must be verified separately.

    python3 tools/migration/export_public_media.py export --core-snapshot PRIVATE_CORE_JSON --schema-inventory PRIVATE_SCHEMA_JSON --source-origin HTTPS_SOURCE_ORIGIN --expected-table-count 60 --expected-object-count 96 --expected-bucket-count 4 --output NEW_PRIVATE_MEDIA_DIRECTORY
    python3 tools/migration/export_public_media.py export --execute --core-snapshot PRIVATE_CORE_JSON --schema-inventory PRIVATE_SCHEMA_JSON --source-origin HTTPS_SOURCE_ORIGIN --expected-table-count 60 --expected-object-count 96 --expected-bucket-count 4 --output NEW_PRIVATE_MEDIA_DIRECTORY
    python3 tools/migration/export_public_media.py verify --execute --core-snapshot PRIVATE_CORE_JSON --schema-inventory PRIVATE_SCHEMA_JSON --source-origin HTTPS_SOURCE_ORIGIN --expected-table-count 60 --expected-object-count 96 --expected-bucket-count 4 --output NEW_PRIVATE_MEDIA_DIRECTORY

The source origin must be plain HTTPS without user credentials, path, query or fragment. Downloads use only the public-object endpoint, refuse redirects and size changes, stream into hashed filenames in a new 700 directory outside Git, and preserve bucket/name/id/metadata plus SHA256/byte totals. The manifest verifies against input-file checksums and every binary. Private Auth rows from the core snapshot are never copied into this media manifest or requests.

The artifact is explicitly labeled supplemental-public-media-backup with completeDatabaseBackup:false. It is **not** a PostgreSQL backup, destination Storage upload, final consistent write-frozen export, or Supabase removal. A missing download or changed object gives no success manifest. The source still needs a final write-free full export and target verification before cutover.

## Empty staging restore and portability

Review archive-toc.txt, extensions, RLS, roles, functions/triggers, publications and roles.sql privately before restore. Do not run source role SQL blindly: it can contain privileged managed roles. An independent PostgreSQL installation may not support Supabase extensions, platform-owned objects or their dependencies.

restore-db is deliberately a full **staging compatibility trial**, not an automatic conversion from Supabase services to a plain PostgreSQL product:

    python3 tools/migration/migrate.py restore-db --execute
    python3 tools/migration/migrate.py verify-db --execute

The script checks actual source/target server/database identity, the independently declared target database name, target version and an empty target. It restores with --single-transaction --exit-on-error --no-owner --no-acl; it never uses --clean, --create or disabled triggers. Ownership and privileges from the original archive remain available for review but are not blindly applied to the new server. Restore SQL executes source-defined functions, so only use the trusted Night Owl archive and reviewed compatibility objects.

Missing extensions/roles/functions cause the restore transaction to roll back. A non-empty or older target is refused. Pre-provision only reviewed compatibility roles/extensions in an empty test database. If the source archive cannot restore directly, adapt a copy of its schema for the new backend and use reviewed table data from all-table-data.dump; keep the original archive untouched. Do not discard a schema or an Auth/Storage table merely to make restore pass. This conversion step depends on the chosen backend and is not implemented as an unsafe generic SQL rewrite.

verify-db compares every inventoried table's exact row count and sorted JSON SHA256 against the source snapshot. Missing, extra or changed tables, sequence state or large-object pages fail verification. Run it before intentionally rewriting media URLs or other data. For transformed target schemas, add and review an explicit mapping verifier; the supplied unchanged-schema verifier must not be reported as passing when it has not run.

Restore and verify the object files in the chosen file/object storage service separately. Preserve each bucket/name and metadata, then compare destination object counts, byte totals and SHA256 against the local Storage manifest. The current tooling exports/verifies a private local Storage archive; it does **not** implement an unconfigured S3/filesystem upload or claim destination Storage is populated. Update persisted media URLs through a reversible mapping after the target media service is validated, and verify no old Supabase URL is needed.

## Auth, sessions and service cutover

The full archive preserves auth.users, password hashes, user UUIDs, linked identities and the remaining Auth tables. Preserve those UUIDs so profiles/posts/comments/messages retain their owners. Auth hashes are sensitive data, not public deployment files.

A new Auth implementation must explicitly support the source hash algorithm or provide a controlled password reset. Never invent plaintext passwords or replace hashes with dummy values. Import linked OAuth identities and account state deliberately; configure Google callbacks, email delivery/templates, redirect URLs and account lifecycle behavior on the new service. Apple's provider configuration remains deferred per the user. Test migrated email/password and provider accounts with authorized test accounts.

Old JWTs/refresh sessions are not automatically trusted by a different Auth service. Plan re-authentication and revoke/expire source tokens as part of the controlled cutover. Do not leave an API accepting arbitrary user IDs or anonymous access to private messages. RLS and server-side authorization need independently reviewed replacements for auth.uid() / Supabase JWT claims.

Replace Realtime subscriptions with the chosen authenticated WebSocket/SSE/notification service. PostgreSQL publications alone do not provide the mobile/web transport. Test direct/group messages, notifications, stories, reactions and connection recovery against the target, including denial of another user's private records. Redeploy/rewrite Edge Functions and inventory external schedules/secrets separately; database archives do not export their runtime configuration.

Before changing production:

1. Restore a staging copy and verify all preserved data and Storage binaries.
2. Validate target Auth, authorization, media access, RPCs and Realtime workflows; make a reversible media URL mapping.
3. Freeze source writes, take the final complete export, and restore/verify the final target.
4. Switch the app's server endpoints, run authorized smoke checks and monitor target errors.
5. Keep the source read-only and retain encrypted private archives for rollback. Source deletion is a separate later decision.

This document does not assert that a migration, deployment or Supabase removal has already occurred.

## Offline checks

    python3 -m unittest discover -s tools/migration/tests -v

The tests cover plan-only behavior, credentials/permissions, archive corruption, path traversal/symlinks, same-source target aliases, non-empty/wrong/older targets, transactional restore arguments, missing/changed data, Storage redirects/identity/checksums and error redaction. They complement the real PostgreSQL fixture drill below; neither verifies actual production data until the production export/restore runs.

## Reproducible local PostgreSQL drill

The opt-in fixture runner checks its private admin service file and accepts only an explicit loopback host. It creates two **new** databases with random nightowl_migration_fixture_ / nightowl_migration_restore_ prefixes, and never drops, clears or reuses an existing database. Source and target service files/artifacts remain in a private temporary directory outside Git. The admin account must be allowed to create databases on a disposable local test cluster, and its private password file must match the new database names.

    python3 tools/migration/tests/run_postgres_fixture.py --admin-service LOCAL_TEST_ALIAS
    python3 tools/migration/tests/run_postgres_fixture.py --admin-service LOCAL_TEST_ALIAS --execute

On 2026-10-05 the PostgreSQL 17.11 drill passed full export, transactional restore and independent verification for 12 synthetic tables/materialized views, including Auth users/identities, private messages, empty buckets/tables, Storage metadata, Unicode/newline/bytea/numeric values, quoted identifiers, partitioned rows, sequence state and large-object pages. A second restore into the populated target was refused. A read-only source DML attempt was refused and left the source empty table unchanged. Target-only synthetic message corruption was detected despite unchanged row counts.

The fixture has deliberately invalid, synthetic password-hash placeholders and example.invalid media/provider identities; it contains no real user data. Storage's network API is not exercised by the database drill. Offline Storage tests separately exercise authenticated request construction, streamed synthetic bytes, identity/path preservation, checksums, size mismatch failures and redirect refusal. Fixture databases remain for inspection, including the intentionally changed target from the corruption check; they are not release databases.

## Primary references

- [Supabase database backups](https://supabase.com/docs/guides/platform/backups): database backups preserve metadata but exclude Storage object bytes.
- [Restore a Platform Project to Self-Hosted](https://supabase.com/docs/guides/self-hosting/restore-from-platform): platform objects and extensions affect compatibility; Auth/provider, Storage and Edge Function configuration require separate work.
- [PostgreSQL pg_dump](https://www.postgresql.org/docs/current/app-pgdump.html): consistent snapshots, full archives, global objects, extension-owned table behavior and source/target version constraints.
- [PostgreSQL pg_restore](https://www.postgresql.org/docs/current/app-pgrestore.html): archive inspection, transaction restore and role/privilege handling.
- [Supabase Storage access control](https://supabase.com/docs/guides/storage/security/access-control): private downloads and server-side service keys.
- [PostgreSQL role export](https://www.postgresql.org/docs/17/app-pg-dumpall.html): --no-role-passwords avoids pg_authid and the initial database is selected explicitly.
- [libpq service files](https://www.postgresql.org/docs/current/libpq-pgservice.html) and [password files](https://www.postgresql.org/docs/current/libpq-pgpass.html): private, non-command-line connection credentials.
