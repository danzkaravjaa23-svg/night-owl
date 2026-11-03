# Account deletion and Apple revocation

2026-11-03. **New 008/009 migrations and this Edge implementation are local preparation, not an enabled production deletion service. No real account was erased.** Existing Storage/account-boundary/consent/admin/interaction protections were already installed in earlier production rollouts; the older statements that those guards remain uninstalled are historical and superseded. Native signing, Apple provider/keys, real Apple authorization and disposable hosted staging tests remain required.

## Protocol

All requests use POST with `confirmation: "DELETE"`. Preparation and deletion validate the caller with server-side `auth.getUser()`; body user IDs, media URLs and paths never choose the subject.

1. `action: "prepare", client_platform: "native" | "web"` returns `user_id`, a random 256-bit `receipt_token`, and `apple_required`. Apple accounts also receive a five-minute owner-bound raw `nonce`, server-selected `client_id`, and the configured web `redirect_uri` when applicable. Preparation does not delete content or revoke a grant.
2. When required, obtain a fresh Apple authorization code and signed identity token using SHA-256 of that nonce. Reauthorization does **not** sign into, link or replace the Supabase session. Cancellation preserves the current account. Flutter web lazily loads Apple's official JS and requires a fresh user click for its popup.
3. `action: "delete", receipt_token, client_platform` plus `apple_code` and `apple_identity_token` when required claims the durable job. Apple issuer/audience/subject/nonce/time/signature are checked against fixed Apple JWKS, the code is exchanged with a short-lived ES256 client secret, the exchanged identity must match, then its refresh token is revoked. A different account's code/token cannot authorize erasure or revocation. Only then are Storage and account data erased.
4. `action: "status", receipt_token` can confirm/reconcile a completed request after Auth deletion makes its session unavailable. It cannot start account deletion. A strict `200 / {ok:true,user_id}` is the sole completion receipt; `202` means incomplete or processing.

`supabase/config.toml` disables gateway JWT checking **only for delete-account**. The handler authenticates every prepare/delete operation itself. Receipt-only status deliberately remains reachable after logout/JWT expiry; an unguessable capability can only inspect/reconcile its own completed job. Other Edge functions retain their existing gateway verification.

The client stores its opaque receipt and original owner through an injectable secure-storage adapter; it never persists Apple identity tokens, codes or refresh tokens. Recovery is explicit, tied to that owner, and cannot sign out a different account/new session. The client receipt expires 30 days from preparation; the server completed journal expires 30 days from completion. A lost/expired receipt while the Auth account still exists requires authenticated preparation again. Failed jobs remain frozen and require deliberate recovery/operational attention; they are not automatically unfrozen or silently removed after 30 days.

## Durable state and erasure scope

`202611030008_account_erasure.sql` creates a private journal and a service-only control RPC. It stores receipt/nonce hashes, minimal account UUID/state/lease/checkpoints and temporary Apple subject/audience, never raw credentials or user content. Completed reconciliation clears Apple subject/audience. The completed-journal `prune` action is service-only and must be scheduled/run by the operator; code alone does not establish a running retention task.

Preparation and claim lock profile then journal in the same order. A two-minute renewable lease prevents overlapping workers and removes an expired worker's authority. New profile/Storage/application writes are blocked for that account while deletion is running/partly failed; existing DB writes hold a profile key-share lock so claim waits for them. Other accounts retain access. Legitimate self-profile bootstrap is allowed only for a still-existing Auth user without an active erasure job; a deleted user's outstanding JWT cannot recreate its profile or upload.

The migration validates the 69 audited FK relationships before changing schema. Auth hard deletion cascades profiles and person-owned posts/stories/comments/messages/groups/live/social rows. Explicit cleanup removes authored events, subject reports and story mentions, clears copied owner-prefix media references, and unlinks shared venue/group ownership. Shared venue identity/facts and other members' posts, reviews, events and group messages remain. Empty owner-only groups can be removed. The 009 profile-erasure hook additionally redacts newly captured abuse-report snapshots before the profile cascade. Minimal append-only moderation/security audit is retained under the published retention policy; this flow does not rewrite audit history or erase independently authored copies/screenshots.

Physical files are removed through the Storage API, never by deleting `storage.objects`. Modern UUID-prefix objects and legacy paths proven by Storage ownership metadata are inventoried before any removal. Conflicting ownership, unknown buckets, traversal-like names, malformed pages and bounds violations fail closed. Only the four app buckets (avatars/posts/stories/venues) are supported. Final empty-prefix and zero-owned-object checks precede Auth deletion. Enumeration is bounded (20,000 files per bucket, depth eight, 30,000 visited entries per bucket); API batches are at most 100.

Apple revoke, Storage and Auth are separate services. Successful revoke is durably checkpointed so a later Storage/Auth failure can resume without revoking twice. A later sign-in/changed Apple identity invalidates an older checkpoint. Auth identities are re-fetched immediately before hard deletion; a newly linked unrevoked identity aborts. This narrows the cross-service race, but is not a claim of global transactional atomicity or coverage of all historical provider grants without a hosted Auth-hook test. A crash between Apple success and checkpoint persistence may require fresh reauthorization. Partial cleanup is reported honestly and is not rolled back.

GoTrue versions can acknowledge hard deletion without returning a User body. Success therefore requires the service-only completion RPC to verify that the exact `auth.users` row is absent and both cleanup checkpoints exist, then return the matching completed journal. A conflicting returned user ID is still rejected; a successful HTTP acknowledgement alone never proves erasure. This contract was exposed by the real local component gate and is covered by SDK regressions.

## Configuration and enable gates

Keep `ACCOUNT_DELETION_ENABLED` absent/false until the disposable staging plan passes. Supabase credentials remain server environment secrets. Apple setup additionally requires:

- `APPLE_CLIENT_ID`: registered native App ID/bundle audience.
- `APPLE_WEB_CLIENT_ID` and `APPLE_WEB_REDIRECT_URI`: registered Services ID and exact HTTPS redirect allowed by Apple for the web popup flow.
- `APPLE_TEAM_ID`, `APPLE_KEY_ID`, `APPLE_PRIVATE_KEY`: server-only Apple signing identity and P-256 .p8 contents. Never put these in Dart defines, public config, repository, logs, screenshots or chat.

The server generates a five-minute client-secret JWT per exchange. Apple JWKS cache is bounded to eight keys / 15 minutes, rotates for an unknown key with a 30-second refresh throttle, and never accepts a caller-supplied issuer/key URL. Apple HTTP requests have a 12-second timeout; Supabase requests have 15 seconds; request JSON is streamed with a 32-KiB cap.

Before enabling:

1. Compare hosted column/FK/trigger metadata with `tools/deployment/tests/account_erasure_preflight.sql`; apply 008 then reviewed 009 in staging. Verify service-only journal/RPC, RLS/write freeze and metadata with the postflight. These migrations install no deletion jobs and delete no existing rows by themselves.
2. Use disposable accounts and real Storage/Auth APIs. Test native and web Apple reauthorization, correct/incorrect Apple IDs, cancellation, revoke failure, key rotation, returning sign-in, linked identities and callback/audience settings. Apple configuration is not certified by synthetic tests.
3. Test every actual FK/legacy file location, metadata ownership, private signed URLs, Storage partial/remove/no-op/list failure, stale JWT, concurrent upload, two workers, expired lease, lost response, app restart, recovery receipt, Auth failure and post-Auth completion reconciliation. Never test by deleting an existing production member.
4. Demonstrate 009 report-snapshot redaction and preservation of other members' shared venue/group content. Confirm lawful audit/backup/public-record retention and operator recovery/escalation. Configure completed-journal pruning and monitor stuck jobs.
5. Only after those gates, deploy the function with its scoped config and set the enable flag through approved server tooling. Function deployment/configuration must not change unrelated endpoints or expose a service key.

## Local verification

No live credentials/accounts are used by these tests. The SDK loopback tests require localhost network permission; Apple requests are intercepted and actual signatures use generated in-memory keys.

```sh
deno check --no-lock supabase/functions/delete-account/index.ts
deno test --no-lock supabase/functions/delete-account/tests/apple_revocation_test.ts
deno test --no-lock --allow-env=SUPABASE_URL,SUPABASE_ANON_KEY,SUPABASE_SERVICE_ROLE_KEY,ACCOUNT_DELETION_ENABLED --allow-net=127.0.0.1 supabase/functions/delete-account/tests/handler_test.ts
deno test --no-lock --allow-env=SUPABASE_URL,SUPABASE_ANON_KEY,SUPABASE_SERVICE_ROLE_KEY,ACCOUNT_DELETION_ENABLED,APPLE_CLIENT_ID,APPLE_WEB_CLIENT_ID,APPLE_WEB_REDIRECT_URI,APPLE_TEAM_ID,APPLE_KEY_ID,APPLE_PRIVATE_KEY --allow-net=127.0.0.1 supabase/functions/delete-account/tests/erasure_protocol_test.ts
node --experimental-vm-modules --test tools/deployment/tests/delete_account_handler.test.mjs
node tools/deployment/tests/run_account_erasure_fixture.mjs /path/to/pglite/dist/index.js
```

Exact final counts and source hashes belong in the release receipt; do not sum historical and current suites. The synthetic FK fixture reflects 69 relationships / 250 column names from a read-only deployment inventory and contains no application rows. It is not hosted multi-connection or signed-device evidence.

`.github/workflows/backend-preparation.yml` adds a separate **real local component** gate on the preparation branch. It uses the official Supabase CLI pinned to 2.122.1, disposable Docker services and the actual Edge source. `run_backend_component.mjs` creates synthetic accounts through GoTrue, uploads/downloads real binary files through Storage, exercises concurrent worker claims and account-scoped write freeze, then verifies HTTP deletion, Auth absence, FK preservation and receipt-only recovery. It never links a hosted project or uses hosted credentials. Only sanitized case results and source hashes are uploaded; raw CLI/function output, generated local keys and session/receipt tokens are excluded.

The application's bootstrap in that gate is an explicitly incomplete metadata fixture with the actual reviewed source migrations applied. Passing it establishes Auth/Storage/Edge component integration, **not full production schema parity, a real Apple-provider test or signed-device acceptance**. A workflow definition or passing endpoint-safety unit test is not a component-test result; record the actual CI run and sanitized result before claiming that gate passed. Official setup references: [pinned v2 CLI release](https://github.com/supabase/cli/releases/tag/v2.122.1), [setup-cli action](https://github.com/supabase/setup-cli/tree/v3), [local stack CLI reference](https://supabase.com/docs/reference/cli/supabase-start).

Official implementation references checked 2026-11-03: [Apple token validation](https://developer.apple.com/documentation/signinwithapplerestapi/generate-and-validate-tokens), [Apple token revocation](https://developer.apple.com/documentation/signinwithapplerestapi/revoke-tokens), [Supabase Apple login](https://supabase.com/docs/guides/auth/social-sign-in/auth-apple), [Supabase user deletion/JWT/Storage behavior](https://supabase.com/docs/guides/auth/managing-user-data).
