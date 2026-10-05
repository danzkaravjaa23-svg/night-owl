# Standalone PostgreSQL deployment boundary

This scaffold runs **standalone PostgreSQL and PostgREST**, with Caddy preserving the app's existing API routes. It has not imported Night Owl's data, and it does not provide an authentication server, object store or realtime server. Those services still need to be selected, migrated, configured and tested. No self-hosted Supabase distribution is bundled or presented as a completed migration.

Every API request is gated by readiness. Empty service settings, missing verification keys, incomplete database inventory, failed health checks or unapproved cutover return HTTP 503. The default listener is `127.0.0.1:8787`, with PostgreSQL and PostgREST unpublished. This permits preparation without redirecting the deployed app prematurely.

## Included components

| Component | Function |
| --- | --- |
| PostgreSQL 17.11 | Persistent standalone database, initially empty apart from bootstrap metadata |
| PostgREST 16.4 | `/rest/v1/*` queries, mutations, FK joins and RPCs over reviewed database grants/RLS |
| Caddy 2.11.6 | Route-compatible gateway, CORS for one configured web origin, upload bound, readiness gate |
| Readiness sidecar | Restricted catalog query and service health checks; no application/auth rows are read |

Versions were checked against the official project documentation and image listings; the Caddy image listing currently documents 2.11.6 although the project release is newer. Pin deployed images by a reviewed digest and plan patch updates before production use. The PostgreSQL major version must match the source migration strategy; changing a volume's image major version is not an upgrade procedure. [PostgreSQL image documentation](https://hub.docker.com/_/postgres), [PostgREST release](https://github.com/PostgREST/postgrest/releases/tag/v16.4), [Caddy image listing](https://hub.docker.com/_/caddy).

## Service contracts that remain required

- **Auth:** existing `/auth/v1` password/signup/refresh/logout/user/settings/recovery/OTP/PKCE/OAuth endpoints and response shapes. Preserve user UUIDs and identities. Configure SMTP, Google callbacks and later Apple credentials. The service must issue verified tokens with UUID `sub`, `role=authenticated` and `aud=authenticated`. A browser's public anonymous credential must have only `role=anon`; never ship server signing, database or service-role credentials.
- **Storage:** existing `/storage/v1` binary uploads and public object URLs. Copy actual files, not only database metadata. Preserve owner prefixes, MIME rules and bucket limits: avatars 2 MiB, posts/stories 50 MiB, venues 5 MiB. Rewrite stored media URLs, including arrays, or use a compatible media domain. Storage ownership enforcement belongs to the chosen service.
- **Realtime:** existing `/realtime/v1` websocket protocol, initial snapshots and insert/update/delete events. Scope private direct/group messages to participants and notifications to their owner. The gateway does not translate websocket protocols or enforce those service ACLs.

`AUTH_UPSTREAM`, `STORAGE_UPSTREAM` and `REALTIME_UPSTREAM` are origins, not URLs containing credentials or paths. They must accept the complete client paths shown above; adapters for alternative provider protocols are not supplied. Public upstream connections require HTTPS. Plain HTTP is limited to private container origins. Health paths must return 200 without credentials and redirects; use each selected provider's actual health route.

PostgREST verifies signatures using the chosen Auth issuer's verification key/JWK set. `auth.uid()` and `auth.jwt()` merely read its transaction claims; they are **not authentication or JWT verification implementations**. The gateway forwards authorization unchanged and never decodes a token to impersonate a user. [PostgREST authentication](https://docs.postgrest.org/en/stable/references/auth.html).

## Configuration and local preparation

1. Copy `.env.example` to `.env`; keep it out of Git. Set private absolute secret-file paths on the deployment host. Generate distinct strong PostgreSQL, `authenticator` and readiness-role passwords. No secret files are supplied here.
2. The PostgREST connection file must contain `postgresql://authenticator:<percent-encoded-password>@postgres:5432/nightowl`, using the same authenticator password as its separate password file. Its role has no superuser, create-role, bypass-RLS or inherited privileges. Do not connect PostgREST as `postgres`.
3. Supply the selected Auth service's matching verification key or JWK set as `JWT_VERIFICATION_KEY_PATH`. Prefer asymmetric public verification material; do not reuse the hosted project's old credentials. File presence checks are not cryptographic validation.
4. Set `APP_WEB_ORIGIN` to the real web app origin and configure all three service origins/health paths. Keep both release flags false until the restore and integration tests pass.
5. With Docker Compose installed, run from this directory:

```sh
docker compose --env-file .env config --quiet
python3 preflight_secrets.py --env-file .env
docker compose --env-file .env up -d --build
curl --fail http://127.0.0.1:8787/readyz
```

The last command is expected to fail with 503 before migration is complete. Health diagnostics contain named blockers, never raw connection errors or tokens. Missing secret paths cause Compose to stop even earlier. No data export, restore or live deployment is triggered by these instructions alone.

Secret-file readability is a required deployment check. Readiness runs as `65534:65534`; PostgreSQL initialization uses the selected image's `postgres` user, and PostgREST uses its reviewed image/Compose runtime identity. A host-owned `0600` file is readable only when the mounted owner matches the reader. Provision narrowly scoped ownership, a private group or explicit ACLs for the actual reader identities, including shared verification material. Do not make passwords world-readable. File-backed Compose secrets are bind mounts: Compose `uid`, `gid` and `mode` attributes cannot repair host ownership. [Docker file-secret behavior](https://docs.docker.com/reference/compose-file/services/).

The preflight requires the reviewed PostgreSQL/PostgREST images to be loaded already. It reads no secret content into output, makes no permission changes and never pulls images. Temporary containers use networking disabled, read-only mounts and no capabilities; they test opening one byte into `/dev/null` under each numeric reader UID/GID, then are removed. Named or UID-only PostgREST identities fail closed because their effective GID cannot safely be guessed in a different probe image. Verify the selected image's UID/GID and supply a reviewed numeric `user` override where required, then repeat. Rootless Docker and Docker Desktop mappings must pass this check on the real deployment host. This proves mount readability, not service startup or JWT trust.

Initialization scripts run only against an empty PostgreSQL volume. Restore into staging rather than deleting/reusing a production volume to rerun bootstrap. Preserve/reapply `nightowl_internal` and the compatibility helpers when adapting the authoritative dump; do not blindly replay duplicate schema/role definitions.

## Restore and release gates

The repository's SQL covers 18 of the 25 client tables. It does **not** define `event_rsvps`, `group_chats`, `group_members`, `group_messages`, `notes`, `live_streams` or `live_comments`, nor all their RPCs. Obtain an authoritative schema/data export; do not invent replacements and claim all data migrated.

The private readiness query checks all **25 client tables**, enabled RLS and policy presence, authenticated SELECT grants, **7 RPC signatures/named inputs** and authenticated execution rights, `auth.users`, claim helpers, `pg_trgm`, and unsafe API-role attributes/memberships. A successful metadata result does not prove policy correctness, mutation permissions, trigger correctness or successful data transfer. It grants no additional table privileges.

Restore reviewed table ownership, foreign keys, constraints, indexes, grants, policies, functions and triggers. Existing authorization includes ownership, participant membership, admin flags, bans and blocks; replacing it with blanket authenticated CRUD would expose private messages or privilege escalation. Review all restored `SECURITY DEFINER` functions and their search paths. Auth password hashes/identities require a chosen service-specific import plan, with forced reauthentication and a tested recovery path.

Reconcile every exported table's rows and IDs, foreign-key integrity, storage objects/checksums, counters and expiry rules. Back up the destination and preserve the source. Inventory deployed extensions, cleanup schedules and functions from the live source, including the unused account-deletion edge function. Moving database metadata does not implement media broadcasting; that transport is absent in the current app.

Before setting `UPSTREAM_PROTOCOL_VERIFIED=true` and `CUTOVER_APPROVED=true`, test real signup/login/refresh/recovery, uploads/downloads, two-user private messages/realtime, group membership, owner/admin restrictions, blocked/banned behavior, feed cursor pagination, RSVP and transactional check-in against staging. Configure a verified HTTPS ingress for the gateway, then switch the app's backend URL/public credential. Test rollback first. Do not terminate the source until reconciliation and the agreed retention window are complete.

Independent Flutter sessions and pending PKCE verifiers are scoped to the complete API origin; existing hosted session storage is preserved during preparation. Installed GoTrue 2.20.0 still names its web BroadcastChannel from the API hostname's first label. Use distinct frontend origins for staging and production, or distinct first API hostname labels, and verify concurrent browser tabs before cutover. Persisted-session/PKCE tests do not establish broadcast isolation for two backends named `api.*` on the same frontend origin.

## Admin and Chrome extension build configuration

The Flutter build alone does not reconfigure the separate admin clients. Their source templates retain the current live defaults: three JavaScript constant pairs and one extension host permission. The generator makes configured copies without editing the admin or extension sources. It prefers `web/admin` when present and falls back to the tracked `admin-web` layout in a clean checkout; the user's staged directory rename is not required for remote builds or implicitly included.

Use the same public `BACKEND_MODE`, `BACKEND_URL` and `BACKEND_PUBLIC_KEY` environment settings as Flutter. Without settings, validation keeps the current Supabase endpoint/anonymous credential. PostgreSQL mode refuses absent settings, managed Supabase origins, user/service-role credentials, a personal `sub`, expired tokens and an incompatible audience. These checks inspect token claims to prevent accidental secret publication; the backend still performs signature verification and authorization.

```sh
python3 tools/deployment/build_admin_clients.py
python3 tools/deployment/build_admin_clients.py \
  --output build/client-bundle --execute \
  --defines-output build/backend-defines.json
```

Run from the repository root. The first command validates only; the second writes generated copies and an exact three-field public defines file usable by Flutter's `--dart-define-from-file`. Alternatively pass `--config` pointing to a copy of `tools/deployment/public-config.example.json` containing public settings only. An empty independent example fails; it is not a deployable configuration. Loopback HTTP is allowed only with the explicit `--allow-local-http` staging option.

The generated bundle updates the web admin, extension query client, background refresh/badge client, host permission and network CSP together. Both clients' stored sessions are scoped to the chosen mode/full API origin, requiring login after a backend switch. The generated manifest removes the obsolete `badges` permission because badges use `chrome.action`. The sources remain unchanged. Only a bundle bearing this generator's receipt can be replaced; unrelated output folders are refused. Output belongs under ignored `build/` or a temporary directory.

Publish the generated `web-admin` files and load/package the generated `chrome-extension` directory after real admin/owner/ordinary-user authorization tests. The generator does not deploy, grant administrator privileges, replace server ACLs or implement missing Auth services. The web admin retains its existing CDN dependencies and protocol-compatible Supabase JavaScript SDK; using that client library does not mean the new data service is hosted by Supabase. The extension's `/auth/v1/admin/users` helper remains a server-protected endpoint and must never be made callable with a service-role key embedded in the extension.

Source metadata review on 2026-10-05 confirmed all 25 public client tables and four public buckets, but found three client RPCs missing: `dm_conversations`, `create_group` and `check_in_venue`. The [target-only patch](patches/README.md) now supplies those contracts and passes local PostgreSQL tests with fictional data, including rollback, bans/blocks, unread counts and concurrent check-ins/group creation. It requires a reviewed nonsuperuser table owner and has not been applied to the source or reserved migration staging database. Direct-table RLS/ACL review and signed HTTP/provider integration still keep the release gate closed. Flutter's PostgreSQL mode no longer uses direct fallbacks after RPC errors; managed mode allows only an explicit missing-function response. The private source inventory is not included in this repository. Restored `SECURITY DEFINER` functions and their search paths still require review; no blanket ACL fix is applied here.

Generator tests: `python3 -m unittest discover -s tools/deployment/tests -v`. Chrome manifest references: [host permissions](https://developer.chrome.com/docs/extensions/develop/concepts/declare-permissions), [match patterns](https://developer.chrome.com/docs/extensions/develop/concepts/match-patterns), [action badges](https://developer.chrome.com/docs/extensions/reference/api/action).

## Verification scope

```sh
python3 -m unittest discover -s backend/tests -v
```

Run that command from the repository root. Thirteen offline tests cover fail-closed configuration, unavailable services/database, secret-safe diagnostics, cached success expiry, gateway health behavior and secret preflight error paths. The generator has eleven separate tests, including clean-checkout directory compatibility and unchanged source files.

Bootstrap and SQL integration checks also passed against an isolated local PostgreSQL 17.11 test database on 2026-10-05: missing 25 tables/7 RPCs fail readiness; API roles have no implicit table/RPC grants; private inventory execution stays restricted; missing/malformed claims cannot manufacture valid identities; the readiness role cannot read application rows; an API role with RLS bypass is detected. SQL probes run inside a transaction and roll back. They neither load nor test source data.

To repeat after bootstrap in an isolated database, set PostgreSQL connection variables and a private `PGPASSFILE`, then run `sh backend/tests/run_sql.sh` from the repository root. The runner refuses database names that do not end in `_backend_test`; bootstrap role creation is cluster-wide and must run only in a disposable test cluster. SQL claims fixtures do not replace real signed JWT tests.

The official Caddy 2.11.6 macOS binary was checked against its release checksum, and native Caddyfile adaptation/validation passed. Docker is unavailable in the authoring workspace, so container startup and actual secret bind-mount readability remain unverified. No production schema/data restore or Auth/Storage/Realtime provider integration has been performed. [Required own-host service wiring](OWN_HOST_SERVICES.md) records protocol adapters and source extension constraints.

Relevant primary references: [PostgREST configuration](https://docs.postgrest.org/en/stable/references/configuration.html), [database authorization](https://docs.postgrest.org/en/stable/explanations/db_authz.html), [PostgREST readiness](https://docs.postgrest.org/en/stable/references/admin_server.html), [PostgreSQL default privileges](https://www.postgresql.org/docs/17/sql-alterdefaultprivileges.html), [Caddy routing](https://caddyserver.com/docs/caddyfile/directives/handle), [reverse proxy](https://caddyserver.com/docs/caddyfile/directives/reverse_proxy), [forward auth](https://caddyserver.com/docs/caddyfile/directives/forward_auth).
