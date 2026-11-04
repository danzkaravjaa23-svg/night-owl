# Disposable hosted Auth and media acceptance

This runner is prepared for **night-owl-staging**, ref
`sreojqqqhdzkfsrbvlpl`, at exactly
`https://sreojqqqhdzkfsrbvlpl.supabase.co`. It has no configurable production
target. Preparation and offline tests do not establish hosted acceptance.

Run it only after the reviewed application baseline and the **staging-origin**
008/009 bundle have been installed and their SQL postflights have passed. The
runner installs no schema, grants, policies, buckets, extensions, or Edge code.
It never inserts Auth users or Storage objects through SQL.

The API flow follows the existing component harness and the client's
`content_publication.dart`: authenticated unique uploads, canonical stored media
URLs, pending publication, and signed private reads. It tests a PNG post and an
H.264 video story for each of two independent normal member sessions.

## Minimum private input

The owner supplies one UTF-8 JSON file, **mode 0600**, inside a **0700** directory
outside Git. Its fields must be exactly:

```json
{
  "origin": "https://sreojqqqhdzkfsrbvlpl.supabase.co",
  "anon_key": "<this staging project's legacy anon JWT>",
  "service_role_key": "<this staging project's legacy service_role JWT>"
}
```

Only paths go in command arguments. Do not put keys, passwords, sessions, signed
URLs, or file contents in chat, shell arguments, environment variables, or public
artifacts. The runner checks canonical JWT encoding, HS256 headers, the expected
roles, and the exact staging ref locally; the hosted service authenticates the
keys. JWT parsing alone is not signature verification. Opaque publishable/secret
keys are intentionally unsupported by this narrowly scoped runner.

No DB password, existing user's login, or moderator account is required. The
runner generates two random `@example.test` addresses and passwords, creates
email-confirmed users through the Auth admin API (without sending email), then
signs in through the normal password-grant API and refreshes each session once.
Refresh tokens stay in memory. User access tokens may use asymmetric signing;
the runner does not impose the legacy API-key algorithm on them. It checks the
refreshed user's identity through Auth itself. The service role is limited to
creating, reading the exact synthetic Auth identity for cleanup verification,
and deleting that identity. **Every application and Storage request, including
cleanup, uses an ordinary synthetic user's JWT or the anonymous key.**

## Commands and local files

Without `--execute`, even a supplied config path is not opened and no network
request is possible:

```sh
python3 tools/deployment/tests/hosted_staging_acceptance.py
python3 tools/deployment/tests/hosted_staging_acceptance.test.py
```

After the baseline, bundle, and runner review are complete, the operator runs:

```sh
python3 tools/deployment/tests/hosted_staging_acceptance.py \
  --execute \
  --config-file /ABS/PRIVATE/api.json \
  --ca-file /ABS/PUBLIC/roots.pem \
  --workdir /ABS/PRIVATE/new-acceptance-run
```

`--ca-file` is optional when this Python installation already discovers trusted
roots. Otherwise supply an existing trusted public PEM bundle, such as the
installed `certifi/cacert.pem` or an operator-prepared OS-root bundle. It is not
a secret and need not be in the private credentials directory. The option is
passed directly to `ssl.create_default_context(cafile=...)`; certificate
verification remains `CERT_REQUIRED` and hostname verification remains on.
An unreadable/invalid CA bundle fails before any HTTP request, with no fallback
to another bundle or to disabled verification. The offline default does not
read the CA file either.

Use a real absolute path without symlink components; on macOS use
`/private/tmp/...` instead of the `/tmp` symlink. The work directory's parent
must be 0700 and owned by the current user. The run directory must not exist;
the runner creates it as 0700 and refuses overwrite. All generated files are
0600. `synthetic-state.json` records only this run's synthetic emails, generated
passwords, Auth IDs, planned row IDs, and object paths. It contains private
credentials and must remain private. It contains no source/production data and
no supplied service/anon keys. Identities are journaled **before** writes.

The default cleans up both synthetic accounts, their rows, and their media,
verifies absence, and checks that deleting account A preserves account B's
session and bytes. `--keep-synthetic` explicitly retains them for inspection.
To resume cleanup after a retained or interrupted run:

```sh
python3 tools/deployment/tests/hosted_staging_acceptance.py \
  --execute --cleanup-only \
  --config-file /ABS/PRIVATE/api.json \
  --ca-file /ABS/PUBLIC/roots.pem \
  --workdir /ABS/PRIVATE/existing-acceptance-run
```

Cleanup first checks the exact Auth ID, synthetic email, and per-run metadata
marker, then signs in with that synthetic user's private password if needed.
Row deletes include both journaled row ID and owner ID; Storage deletes name
only exact journaled paths under that owner and run prefix. It never lists or
bulk-deletes real users or another run. A lost Auth-create response can leave
an unknown synthetic ID: the runner marks cleanup incomplete and requires a
private journal review, rather than guessing or widening deletion scope.

`acceptance-result.json` and `cleanup-result.json` contain sanitized check
names, HTTP status codes, fixture hashes/sizes, and result/cleanup state.
Cleanup failures include static codes and, for object deletion, only the
synthetic account label, bucket, response item count, metadata match count, and
verification statuses.
No object names or raw response data are included in these diagnostics.
Stdout contains the same sanitized metadata. Responses, account IDs, emails,
passwords, tokens, signed URLs, request bodies, and raw exceptions are omitted.
The private journal remains available for recovery after cleanup.

## Actual cases and endpoints

| API operation | Endpoint | Identity / evidence |
| --- | --- | --- |
| Create synthetic accounts | `POST /auth/v1/admin/users` | Staging service role; random emails and passwords, no email delivery |
| Reject wrong password, then sign in A/B | `POST /auth/v1/token?grant_type=password` | Anonymous API key; password in HTTPS body only |
| Refresh A/B sessions | `POST /auth/v1/token?grant_type=refresh_token` | Fresh session must retain the same Auth user; refresh token in HTTPS body only |
| Verify session identity | `GET /auth/v1/user` | Independent normal A/B JWTs |
| Verify signup-created profile and active membership | `GET /rest/v1/profiles?...`, `POST /rest/v1/rpc/social_active` | Owner JWT; no fabricated profile SQL |
| Upload original PNG / MP4 | `POST /storage/v1/object/{posts,stories}/{uid}/acceptance-{run}/{file}` | Owner JWT; story uses the client's fresh-path `x-upsert: true` |
| Publish pending post / story | `POST /rest/v1/{posts,stories}` | Owner JWT; require returned `moderation_status=pending` |
| Read pending content | `GET /rest/v1/{posts,stories}?id=eq...` | Created response and positive owner read must match exact ID, owner, media URL/type and pending status before other/anonymous isolation checks |
| Read stored bytes | `GET /storage/v1/object/authenticated/{bucket}/{path}` | Owner's full bytes and SHA256 must match; every integrity read uses a new `nightowl_probe` nonce and `Cache-Control: no-cache`; other member/anonymous denied |
| Public URL denial | `GET /storage/v1/object/public/{bucket}/{path}` | Anonymous; private media must not be exposed |
| Sign and download | `POST /storage/v1/object/sign/{bucket}/{path}`, then returned same-origin signed path | Owner can mint a 60-second capability and fetch identical bytes; other member/anonymous cannot mint it |
| Immutable/reference guard | `PUT` and upsert `POST` object; `DELETE /storage/v1/object/{bucket}` with exact prefixes | Owner/foreign overwrites and referenced owner delete must fail; full original bytes are reread afterward |
| Ownership/moderation denial | Foreign-folder upload, foreign-media publication, `PATCH /rest/v1/{posts,stories}?id=eq...` | Both users' objects are uploaded and positively read first; normal user cannot write into the other folder, attach the existing other-user media, or self-approve |
| Clean exact synthetic rows/media | Filtered `DELETE /rest/v1/{posts,stories}` and `DELETE /storage/v1/object/{bucket}`; `POST /storage/v1/object/list/{bucket}` | Normal owner JWT; fresh listing of the exact run prefix must omit the object, and a new nonce/no-cache byte read must return 400/404 before Auth removal |
| Verify and remove exact synthetic Auth identity | `GET`, `DELETE /auth/v1/admin/users/{id}` | Service role; exact ID/email/run marker; subsequent 404 required |

All HTTPS connections use Python's default trust store or the explicit public
CA bundle, mandatory certificate/hostname verification, hard-pinned staging host,
timeouts, bounded response bodies, no proxy inheritance, and no redirects.
Signed capability URLs must name the exact same host and expected object path.
An HTTP 5xx, timeout, malformed response, silent successful referenced delete,
or changed bytes causes failure. Failed negative requests are also journaled so
unexpectedly created synthetic content can be removed safely.

The self-approval PATCH requests `Prefer: return=representation`. An explicit
denial, `200 []`, or `204` can indicate that no row was updated under RLS. Such a
response passes only after another positive owner read confirms the exact row
identity, media fields, and `pending` moderation state. A changed or missing row
fails regardless of the PATCH status. Cleanup requires both fresh metadata
absence and an unsuccessful fresh byte read. A successful DELETE or an empty
listing alone does not prove deletion. A cached old URL is not used as the
verification request, and fresh readable bytes still fail cleanup.

Verified TLS is completed before any HTTP headers or body are passed to the
connection. Sanitized trace entries distinguish `tls_verification_before_http`,
`tls_handshake_before_http`, `tls_ca_load_failed`, and
`transport_connect_before_http` from a request whose outcome is unknown.
`http_request_attempted=false` means that call sent no HTTP credentials/body.
An Auth creation that fails in that pre-request phase is not marked uncertain;
a lost response after the HTTP request starts remains uncertain and is never
automatically reconciled by broad user searches.

There is no automatic retry loop for Auth writes, sign-in, refresh, or HTTP 429.
A rate limit fails the run; the operator can resume exact-identity cleanup later.
Known nonexistent synthetic row/object candidates can return successful empty
delete results and are followed by owner-scoped absence checks. Storage listing
is a POST scoped to the exact owner/run prefix with limit 100 and offset 0;
an unexpected full page fails rather than assuming an object is absent. These checks
prove API-visible cleanup under the owner session, not a privileged catalog
inventory. A signup-trigger, grant, or RLS failure is reported; the runner never
patches permissions or fabricates a missing profile to make the test pass.

## Fixtures and scope limits

The PNG is generated directly from a solid-color 16×16 pixel array using the
Python standard library. `hosted_staging_acceptance.mp4` is an original silent,
one-second 128×128 solid-color H.264 fixture, **941 bytes**, SHA256
`f9e0463f8212936c8dac808a3827a6ec7bb653c9172de8f45e8ac8cd60bc5b0f`.
It was encoded and a frame was independently decoded through the installed
macOS AVFoundation framework using `hosted_staging_acceptance.fixture.swift`.
No third-party footage, image assets, or network download is used. The supplied
fixture hash is checked before any hosted request; regeneration requires a
deliberate hash update and review.

This is a minimum hosted **API** acceptance test. It does not establish UI or
device video playback, signup email delivery, Apple OAuth, admin/moderator
review decisions, banned-member behavior, signed-upload capability rejection,
the account-erasure Edge workflow, all bucket types, or recovery/production
schema parity. Those remain explicit follow-up acceptance cases. Do not mark
the overall release gate complete from this result alone.
