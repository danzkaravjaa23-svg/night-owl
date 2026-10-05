# Night Owl services on an independently operated PostgreSQL host

Status: researched deployment design, 2026-10-05. This file does not install services, export production data, import accounts, upload destination media, or change the deployed app. The deployment host is not yet identified and the private source database password is not configured. Auth, Storage and Realtime are not running in this repository's backend scaffold.

## Recommended boundary

Run PostgreSQL, PostgREST, GoTrue Auth, Storage API and Realtime on infrastructure controlled by Night Owl, behind an HTTPS ingress and a compatible internal API gateway. This removes the managed Supabase project's data and service endpoints after a verified cutover. The Flutter and JavaScript Supabase client libraries can remain as open source protocol clients; using those libraries does not require the managed cloud. Removing all Supabase-origin software would instead require a separate Auth, Storage and websocket protocol implementation and client rewrite. [Self-hosting overview](https://supabase.com/docs/guides/self-hosting).

Use the official `self-hosted/v0.8.2` bundle as the service compatibility baseline. Adapt its roles, database bootstrap and gateway to the chosen host; do not combine only its image names with the current minimal database bootstrap. The full reference also contains optional operational services. Only remove one after checking its dependencies and Night Owl's actual use. [Pinned bundle](https://raw.githubusercontent.com/supabase/supabase/self-hosted/v0.8.2/docker/docker-compose.yml), [deployment guide](https://supabase.com/docs/guides/self-hosting/docker).

| Required service | Reference image pin | Night Owl responsibility |
| --- | --- | --- |
| PostgreSQL | `supabase/postgres:17.6.1.136` | Independently owned database, extension binaries, service roles and bootstrap |
| REST/RPC | `postgrest/postgrest:v14.17` | Existing queries, joins and RPC contracts with verified JWTs and RLS |
| Auth | `supabase/gotrue:v2.196.0` | Accounts, password hashes, OAuth, refresh, recovery and email |
| Storage | `supabase/storage-api:v1.74.0` | Upload/download API, metadata, ownership and durable object bytes |
| Realtime | `supabase/realtime:v2.134.10` | SDK websocket protocol and authorized database events |
| Internal API adapter | `envoyproxy/envoy:v1.39.1` | Route rewriting, API credentials, callbacks and websocket routing |

These are matched bundle pins, not a claim that every image is the newest or has passed Night Owl's production checks. Record reviewed image digests and an update procedure on the target. The current scaffold instead uses `postgres:17.11-bookworm` and PostgREST `v16.4`. Choose either the reference REST version or keep `v16.4` and explicitly validate the resulting combination, including queries, named RPC parameters, schema cache, JWT keys, headers and readiness. This guide does not silently downgrade or replace the scaffold.

A plain PostgreSQL distribution is also possible, but its image must contain the required extensions and service bootstrap. An operator-owned Supabase PostgreSQL image is still independently hosted PostgreSQL. Decide the database major version from the actual source version and the restore/upgrade plan; replacing an image tag on an existing data volume is not a major upgrade. [PostgreSQL project](https://github.com/supabase/postgres), [PostgreSQL upgrade guidance](https://www.postgresql.org/docs/17/upgrading.html).

Publish only the selected HTTPS ingress. Keep database, REST administration, Auth, Storage, Realtime tenant management and Envoy administration ports private. The reference's public port bindings are examples to adapt, not production firewall policy. Keep Studio/Meta or other management interfaces private if retained. Persistent database/object volumes, encrypted off-host backups, restore drills, disk/WAL monitoring and certificate renewal belong to the chosen host design. [Docker deployment guide](https://supabase.com/docs/guides/self-hosting/docker).

## API gateway and public origins

The current Caddy configuration is a fail-closed contract gateway. It strips `/rest/v1` for PostgREST but forwards the full Auth, Storage and Realtime paths unchanged. Bare GoTrue, Storage API and Realtime origins do not satisfy that contract. Configure an internal Envoy adapter, or implement and test an equivalent adapter, before pointing those origins at real services. This file does not add that adapter.

The reference Envoy performs these protocol changes:

| Public client path | Internal path/service |
| --- | --- |
| `/auth/v1/*` | `/*` on GoTrue |
| `/storage/v1/*` | `/*` on Storage API |
| `/rest/v1/*` | `/*` on PostgREST |
| `/realtime/v1/websocket` | `/socket/websocket` on Realtime, with websocket upgrade |
| `/realtime/v1/api/*` | `/api/*` on Realtime, restricted routes |

It sets forwarded prefixes and the Realtime tenant host, accepts the browser websocket `apikey` query parameter, preserves the user's Authorization token, and supports opaque API-key translation. Auth callback/verification/JWKS exceptions differ from ordinary protected routes; tenant administration must remain inaccessible publicly. Preserve these behaviors when adapting it. [Pinned Envoy routes](https://raw.githubusercontent.com/supabase/supabase/self-hosted/v0.8.2/docker/volumes/api/envoy/lds.template.yaml).

A concrete integration must also decide how REST reaches the adapter: route all API families through internal Envoy, or retain direct REST with a tested legacy anonymous JWT and matching user-token verification. The current direct REST route cannot translate an opaque publishable credential. Setting only `AUTH_UPSTREAM`, `STORAGE_UPSTREAM` and `REALTIME_UPSTREAM` does not solve this. Readiness also needs private health origins or a dedicated health adapter: its current contract expects unauthenticated HTTP 200, while protected gateway/tenant health endpoints may require a credential. Do not expose tenant administration to make a health check pass.

| Private health probe | What it proves |
| --- | --- |
| GoTrue `/health` | Auth process health; account flows still require integration tests |
| Storage `/status` | Storage process response; actual database/object permissions still require upload/download tests |
| Realtime `/healthcheck` | Process response; tenant replication requires the protected `/api/tenants/<tenant-id>/health` and event tests |
| PostgREST administration `/ready` | REST database/schema-cache readiness, on its private admin listener |

Implement separate protected tenant diagnostics without adding service credentials to public URLs or client bundles. [Auth routes](https://raw.githubusercontent.com/supabase/auth/v2.196.0/internal/api/api.go), [Storage application](https://raw.githubusercontent.com/supabase/storage/v1.74.0/src/app.ts), [Realtime routes](https://raw.githubusercontent.com/supabase/realtime/v2.134.10/lib/realtime_web/router.ex), [PostgREST administration](https://docs.postgrest.org/en/stable/references/admin_server.html).

Use these public settings on the target, with actual owned names replacing placeholders:

```text
SUPABASE_PUBLIC_URL=https://<owned-api-host>
API_EXTERNAL_URL=https://<owned-api-host>/auth/v1
SITE_URL=https://nightowl-ub.netlify.app
ADDITIONAL_REDIRECT_URLS=https://nightowl-ub.netlify.app/,com.nightowl.ub://login-callback/
STORAGE_PUBLIC_URL=https://<owned-api-host>
APP_WEB_ORIGIN=https://nightowl-ub.netlify.app
```

The native callback above matches Night Owl's current URL scheme. Add only deployed callback origins/paths actually required by web, admin and native builds; validate recovery links separately. Set trusted proxy/forwarded-path behavior and CORS for the actual frontend origins. Do not publish localhost service ports or enable unrestricted origin access by copying the reference configuration verbatim. [Public URL configuration](https://supabase.com/docs/guides/self-hosting/docker#configure-supabase-urls).

## Auth, keys and account migration

The selected GoTrue service requires its real `auth` schema and migration history. The scaffold's minimal `auth.users(id)` compatibility table is not an account server. Restore and reconcile the authoritative Auth schema with the pinned service on staging before starting automatic service migrations against a release database. Preserve UUIDs, password hashes and algorithms, identities, confirmation/ban state, factors and all remaining account records. Profiles, messages and uploaded object prefixes depend on these UUIDs. Never replace hashes with dummy values or skip incompatible Auth tables to make a restore succeed. [Auth implementation](https://github.com/supabase/auth), [platform restore guide](https://supabase.com/docs/guides/self-hosting/restore-from-platform).

Required GoTrue configuration groups are:

| Group | Settings to supply/review |
| --- | --- |
| Database/listener | `GOTRUE_DB_DRIVER=postgres`, `GOTRUE_DB_DATABASE_URL` for a private Auth service role, the pinned `auth` namespace default, private `GOTRUE_API_HOST`/`GOTRUE_API_PORT` |
| URLs | `API_EXTERNAL_URL`, `GOTRUE_SITE_URL`, `GOTRUE_URI_ALLOW_LIST`, `GOTRUE_JWT_ISSUER` |
| Claims/signing | `GOTRUE_JWT_AUD=authenticated`, `GOTRUE_JWT_DEFAULT_GROUP_NAME=authenticated`, `GOTRUE_JWT_ADMIN_ROLES=service_role`, expiry, `GOTRUE_JWT_SECRET` and, when asymmetric signing is enabled, `GOTRUE_JWT_KEYS` |
| Email | Email/signup policy, `GOTRUE_MAILER_AUTOCONFIRM`, `GOTRUE_SMTP_ADMIN_EMAIL`, host, port, user, password, sender and confirmation/recovery/invite/email-change URL paths |
| Google | `GOTRUE_EXTERNAL_GOOGLE_ENABLED`, client ID, secret, `GOTRUE_EXTERNAL_GOOGLE_REDIRECT_URI` ending in `/auth/v1/callback` |

Use private distinct service credentials and reviewed permissions; the reference service-role names may be retained where bootstrap requires them. Configure SMTP and test delivery rather than enabling auto-confirm to bypass missing mail. Keep Google nonce verification and validate both web PKCE and native return flows. Apple provider configuration remains deferred per the user; keep it disabled with an honest unavailable state until its registration and credentials exist. [Pinned Auth configuration](https://raw.githubusercontent.com/supabase/auth/v2.196.0/internal/conf/configuration.go), [Auth setup](https://raw.githubusercontent.com/supabase/auth/v2.196.0/README.md).

Generate independent target signing/API credentials. For asymmetric signing, GoTrue uses `GOTRUE_JWT_KEYS`; PostgREST uses `PGRST_JWT_SECRET` with the appropriate verification material; Realtime uses `API_JWT_JWKS`; Storage uses `JWT_JWKS`. The reference combined JWKS can include a symmetric secret and must not be published wholesale. The public Auth JWKS endpoint exposes only public keys. Keep private signing keys, database passwords, service-role/secret API keys and SMTP/provider secrets out of every client bundle. [Self-hosted key configuration](https://supabase.com/docs/guides/self-hosting/self-hosted-auth-keys).

The first compatible public client credential can be a target-signed anonymous JWT. Using an opaque publishable key additionally requires tested gateway translation and client build acceptance. A client credential has only anonymous privileges; authenticated tokens require a verified signature and UUID `sub`, `role=authenticated`, `aud=authenticated`. Existing `auth.uid()`/`auth.jwt()` helpers merely read verified request claims. They do not validate tokens. [PostgREST authentication](https://docs.postgrest.org/en/stable/references/auth.html).

Plan forced reauthentication on the new origin/signing keys. Importing sessions and refresh records is not a promise that source sessions remain valid. Test a migrated account's password login, refresh rotation, logout and recovery; use a controlled reset only if its hash algorithm is unsupported. Scope saved Flutter, admin and extension sessions to the target origin. Retaining source signing secrets indefinitely is not the migration plan.

## Storage API and actual media bytes

Configure the pinned Storage API with `DATABASE_URL`, `ANON_KEY`, private `SERVICE_KEY`, `AUTH_JWT_SECRET` plus `JWT_JWKS` when asymmetric tokens are enabled, `TENANT_ID`, `REGION`, `GLOBAL_S3_BUCKET`, `STORAGE_PUBLIC_URL` and `REQUEST_ALLOW_X_FORWARDED_PATH=true`. For local durable files use `STORAGE_BACKEND=file` and `FILE_STORAGE_BACKEND_PATH=/var/lib/storage` on a backed-up persistent volume. For an independently selected S3-compatible backend configure its endpoint, protocol/path style and server-only access credentials. Set `FILE_SIZE_LIMIT=52428800` and preserve Night Owl's stricter bucket limits/MIME rules: avatars 2 MiB, posts/stories 50 MiB, venues 5 MiB. Image transformations can remain disabled if unused; enabling them requires a configured image service. Follow the pinned implementation rather than assuming every older example variable is still consumed. [Storage configuration](https://raw.githubusercontent.com/supabase/storage/v1.74.0/src/config.ts), [S3 backend options](https://supabase.com/docs/guides/self-hosting/self-hosted-s3).

Restore reviewed bucket/policy metadata and migrate bytes through the Storage API or its configured S3 protocol endpoint. Placing downloaded files directly inside the Storage volume does not create the service's expected internal object structure. Coordinate existing restored metadata with the chosen upload/import procedure on staging; do not duplicate records, blindly upsert or overwrite the authoritative archive. Use copy semantics and preserve the source. [Platform object copy procedure](https://supabase.com/docs/guides/self-hosting/copy-from-platform-s3).

Check every bucket, including empty/private buckets, object name, MIME type, size and SHA256. Administrative uploads can change ownership metadata: explicitly preserve or map it and test owner UUID prefixes/RLS. Test public URLs, private downloads, upload/update/delete authorization and expired links. Rewrite stored old media URLs, including arrays, using a reversible target-only mapping after unchanged-data verification. Local archive checksum verification alone does not mean destination Storage contains the media.

## Realtime and PostgreSQL prerequisites

Realtime needs private database connectivity and reviewed service/replication permissions, its `_realtime`/`realtime` schema migrations and a seeded tenant. Configure `DB_HOST`, `DB_PORT`, `DB_USER`, `DB_PASSWORD`, `DB_NAME`, `DB_AFTER_CONNECT_QUERY='SET search_path TO _realtime'`, a distinct 16-byte `DB_ENC_KEY`, a `SECRET_KEY_BASE` of at least 64 characters, `API_JWT_SECRET` plus `API_JWT_JWKS` when asymmetric tokens are enabled, private `METRICS_JWT_SECRET`, `SEED_SELF_HOST=true` and `RUN_JANITOR=true`. The seed tenant and gateway host rewrite must match, commonly `realtime-dev` in the reference. Do not retain reference secrets or seed database defaults. [Pinned runtime configuration](https://raw.githubusercontent.com/supabase/realtime/v2.134.10/config/runtime.exs), [tenant seeding](https://raw.githubusercontent.com/supabase/realtime/v2.134.10/priv/repo/seeds.exs).

The pinned Postgres Changes implementation creates logical slots with the `wal2json` output plugin. Stock PostgreSQL contains logical decoding support but not that external plugin. Supply the compatible plugin binary, configure `wal_level=logical`, sufficient replication slots/WAL senders and the required publication/permissions. Plan capacity for the chosen tenant/features and monitor slot lag/WAL disk growth; a generic alive response does not prove replication is running. [Pinned replication implementation](https://raw.githubusercontent.com/supabase/realtime/v2.134.10/lib/extensions/postgres_cdc_rls/replications.ex), [PostgreSQL logical decoding](https://www.postgresql.org/docs/17/logicaldecoding-example.html), [Realtime database concepts](https://supabase.com/docs/guides/realtime/concepts).

Source review confirmed `pg_cron`, `supabase_vault` and `pg_trgm`. Inventory all source extensions and versions; this is not a claim that those are the only extensions. Provision compatible binaries/dependencies or review explicit replacements before restoring their objects. A logical dump does not install extension binaries or preserve every external encryption/service setting. Review Vault secret/key portability privately. Keep copied cron jobs disabled until their URLs, credentials and write behavior are retargeted; an old job can otherwise continue reaching the managed project. [pg_cron](https://github.com/citusdata/pg_cron), [Vault](https://github.com/supabase/vault), [pg_trgm](https://www.postgresql.org/docs/17/pgtrgm.html).

Keep application RLS and participant/owner checks on subscriptions. Test reconnect, token renewal and missed-event recovery with two actual authorized staging accounts. Realtime table events do not supply live video/audio broadcasting or calls; those media transports are absent from the current app and require separate implementation. Payments remain deferred and the app remains free.

## Thirty release gates

All gates require recorded staging/target evidence. Catalog checks and offline fixtures are useful preparation, but are not substitutes for service integration or production-data reconciliation.

1. **Target ownership:** identify the independently controlled host, API DNS name, region, TLS ingress, private network and operator responsible for backups/updates.
2. **Version decision:** record source PostgreSQL/extension versions, the target upgrade/restore strategy, service image digests and the PostgREST `14.17` versus `16.4` decision.
3. **Private credentials:** provision source/target connection files and distinct target service/signing/provider secrets outside Git; confirm the app contains only a public credential.
4. **Authoritative inventory:** retain the private live schema, all schemas/tables, roles, extensions, publications, triggers, functions, sequences, large objects, jobs, buckets and object inventory.
5. **Missing contracts:** source review confirmed all 25 public client tables and four public buckets, but `dm_conversations`, `create_group` and `check_in_venue` are absent. Add reviewed target migrations for their exact named parameters/results and transactional authorization; do not label them restored source functions.
6. **Source preservation:** retain a conventional private backup and immutable export archives; prove tools cannot overwrite the source or restore to the same database.
7. **Schema compatibility:** restore into an empty staging database with reviewed extension/service bootstrap; resolve collisions with the scaffold's minimal Auth table and platform roles deliberately.
8. **Complete data restore:** reconcile all table rows/IDs/digests, sequence state, large objects and constraints before intentional transformations; retain explicit verifiers for transformed schemas.
9. **Authorization review:** restore reviewed ownership, grants, RLS, block/ban/admin/participant checks and safe `SECURITY DEFINER` search paths; no blanket authenticated CRUD.
10. **Role boundary:** prove the REST authenticator cannot bypass RLS, read privileged schemas, create roles or gain service privileges; keep privileged service credentials private.
11. **Auth schema/import:** validate real GoTrue schema/migrations, migrated UUIDs, hashes, identities, account state and any factors without discarded records.
12. **Password lifecycle:** test migrated password login, signup policy, confirmation, refresh rotation, logout, invalid/expired tokens and recovery with authorized staging accounts.
13. **Email delivery:** verify real SMTP delivery and correct target confirmation/recovery/invite/email-change links, redirects and expiry behavior.
14. **Provider callbacks:** test Google web/native flows and allowlists; keep Apple disabled until configured. Confirm callback URLs do not retain consumed credentials.
15. **Key enforcement:** prove valid target signatures work and forged/wrong-issuer/expired/source tokens fail; public/ordinary users cannot call Auth administration.
16. **Gateway protocol:** verify full SDK paths, forwarded prefixes, API-key modes, user Authorization retention, CORS, websocket upgrades and private health routing through the actual ingress/adapter.
17. **Service startup:** prove Auth/Storage/Realtime migrations and tenant seeding work on the selected database and survive restarts; inspect safe private diagnostics.
18. **Destination objects:** upload/copy all archived bytes through a tested service import path and reconcile bucket/name/size/SHA256/metadata/ownership, including private and empty buckets.
19. **Storage permissions:** test own/other-user upload, overwrite and delete; bucket MIME/size limits; public/private reads and signed URL expiry.
20. **Media mapping:** apply a reversible target-only URL mapping and verify stored scalar/array URLs and all client media requests no longer need the managed host.
21. **Realtime isolation:** confirm logical plugin/slots/publications work; test two-user DM/group events, notification ownership and denial of outsiders, blocked/banned users and expired tokens.
22. **Realtime recovery:** test disconnect/reconnect, renewed tokens, missed events and bounded WAL/slot cleanup; direct server health alone is insufficient.
23. **Feed/profile flows:** exercise cursor pagination without duplicates, reactions, stories/expiry/views, profile edits, saves and upload failures using real target services.
24. **Groups/venues/events:** verify transactional group creation/membership, DM unread results, check-in counters/limits, map data, RSVP uniqueness and owner/admin restrictions.
25. **Auxiliary services:** inventory Edge Functions, cleanup schedules, secrets and integrations; retarget needed functions/jobs and explicitly account for unused ones rather than silently omitting them.
26. **Every client build:** configure Flutter web/native and generated admin/Chrome clients with the same own API origin/public credential; invalidate source sessions and test ordinary/admin permissions independently.
27. **Operations:** test encrypted database/object backup restoration, disk/WAL alerts, resource limits, HTTPS renewal and restart/failure behavior; no public management/database ports.
28. **Final consistent export:** freeze app/API, cron/background and Storage writes for the final database-plus-object export and reconciliation. Database snapshots do not make object bytes, global roles or sequences one atomic snapshot.
29. **Controlled cutover:** repeat the verified restore/import on the release target, then set protocol/cutover flags only after evidence passes; switch all built clients and monitor authorized smoke checks/errors.
30. **Rollback/retention:** rehearse endpoint/data rollback, define how target writes are preserved during rollback and retain the source read-only plus private archives for the agreed period. Source deletion is a separate later action.

Use [the migration procedure](../docs/POSTGRES_MIGRATION.md) for private export/restore/verification tooling and [the backend scaffold instructions](README.md) for current fail-closed checks and generated admin/extension configuration. The existing readiness flags are operator assertions, not automatic proof of these gates.

## What remains before implementation

Choose the host, private source access and service/version/key plan. Then implement the reviewed service composition, real database bootstrap, internal gateway adapter and health wiring for that environment; perform the staging import and gates above. No Docker installation/container launch, source write, production-data export, full-service integration, destination object import or cutover was performed to author this guide. Until those steps succeed, retain `UPSTREAM_PROTOCOL_VERIFIED=false` and `CUTOVER_APPROVED=false` and keep the deployed app on its current backend.
