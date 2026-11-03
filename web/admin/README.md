# Night Owl web admin

A static, responsive admin console with the app’s midnight navy and lavender
palette. It shares the app backend. No service-role key, user emails or auth tokens are displayed. The console
has no private-message inbox browser. A reporter can explicitly submit one
selected message and its currently readable attachment for moderation; only
that captured report context appears in the report queue.

## Run and deploy

Serve the repository’s `web/` directory locally, or open `/admin/` on the built
app’s host. The “Апп руу буцах” link points to `/#/feed`. Logo and avatar presets
use the Flutter web build’s `/assets/assets/` files; an isolated admin copy may
lack those decorative assets.

```sh
python3 -m http.server 8080 --directory web
# http://127.0.0.1:8080/admin/
```

`tools/deployment/build_admin_clients.py` can produce backend-specific copies.
The two public config constants and `supabase.createClient` contract remain
compatible with that generator. Run its existing checks before release. Only a
public anonymous key belongs in the client; never place server credentials here.

The Supabase UMD client is pinned to **2.118.0** with SHA-384 subresource integrity
and `crossorigin="anonymous"`. This is the exact version resolved by the previous
`@2` dependency on 2026-11-03, fetched from
`https://cdn.jsdelivr.net/npm/@supabase/supabase-js@2.118.0/dist/umd/supabase.js`.
There is no Tailwind runtime dependency. The hosted Supabase script still needs
network access; this is not an offline admin application.

## Backend prerequisites

Apply and verify the existing social discovery/featured-event prerequisites,
then `202611030001_account_deletion_boundaries.sql` before
`supabase/migrations/202611030003_admin_console.sql` in the intended backend.
The admin migration refuses unsafe legacy profile deletion or media-cleanup
triggers. Run `tools/deployment/tests/admin_console_preflight.sql` before it and
`admin_console_postflight.sql` afterward. Validate on staging before deploying this client. This repository change does not
apply that migration or publish the admin page. Without the RPCs the page shows
an explicit setup error and does not fall back to raw moderation writes.

`admin_console_summary()` must validate an **active, non-banned administrator**
and return an `actor_id` matching the signed-in account before any private admin
view renders. Every admin RPC must enforce the same server-side gate. Client-side
checks are only presentation safeguards, not the authorization boundary.

The native app uses **Profile → Админ панел** or **Settings → Админ панел**,
with routes for reports, users, content, audit, featured events and pilot/venue
review. Native and web consoles share the same RPC and audit contract.

## Manual prepublication review — prepared, not deployed

`202611030009_ugc_review.sql` extends the existing admin console with a manual
review queue. Deploy it only with the matching Flutter/web pending-status UI,
private-bucket media renderers and migration `008` erasure changes. This source
work does not apply it to the hosted backend. Existing published rows retain
approval; new posts, stories, comments, events, reviews, notes, public collections,
profiles and owner-submitted venues wait for review. Private collections and
private conversations do not enter the publication queue.

**Нийтлэхийн өмнөх шалгалт** lists pending content by submission time. Read all
text, inspect every photograph and watch each complete video. If media fails to
open, refresh/retry rather than approving unseen content. The decision dialog
requires an explicit full-review acknowledgment and a 3–1000-character reason.
An approval/rejection is tied to the exact submitted version and returns an audit
receipt; edits require a new review. Approved content can also be hidden with a
recorded rejection. This does not appoint a moderator or provide staffed coverage.

An approved public profile remains visible while a replacement is pending.
Rejecting its pending replacement retains the prior identity; rejecting the
approved identity itself hides it. Captured reports may concern posts, comments,
users, venues, stories, direct/group messages, events, reviews, notes or public
collections. Only the reporter-readable selected row is captured. The service
cannot browse unrelated conversations. Deleting a subject/reporter removes
captured context and quoted report details through the erasure hook; minimal
reason/status/time/audit records follow the owner's documented retention policy.
Operational report retention, response targets, escalation and appeal handling
must be confirmed before submission. No automatic AI moderation is claimed.

Run `tools/deployment/tests/ugc_review_postflight.sql` read-only after a staging
install. Isolated checks are `run_ugc_review_fixture.mjs` and
`run_erasure_ugc_fixture.mjs`; both take an absolute PGlite module path. The second
uses the 69-FK synthetic schema and installs actual `008` plus `009` together.

## Pages and actions

| Page | Behavior |
| --- | --- |
| Dashboard | Authoritative server totals; failed counts remain errors |
| Prepublication review | Kind/status filters, all-media preview, version-bound approval/rejection with audit |
| Reports | Pending/resolved/reviewed/all filters, pagination, target excerpt, resolve/dismiss/reopen |
| Users | Literal name search, pagination, ban/unban and verification changes |
| Posts and comments | Search, pagination, excerpts, deletion with a recorded reason |
| Venues | Existing create/edit/delete flow; validated coordinates, server gate, exact affected-row confirmation |
| Events | Existing list/delete flow with the same gate and affected-row confirmation |
| Audit | Paginated administrator action, target, reason and timestamp |

Legacy moderation uses `admin_console_action`; publication decisions use
`admin_console_review`, with a required 3–1000-character
reason. Linked report actions close the matching pending report atomically on
the server. This UI does not grant or revoke administrator roles. User admin
flags cannot be edited through direct profile updates.

Venue/event CRUD remains on the existing REST endpoints. The migration’s active
admin guards and automatic audit triggers are required; those legacy operations
use the server’s legacy-operation audit reason rather than a moderator-entered
reason. Zero affected rows are never reported as success.

## Session, media and failure behavior

- Requests carry the captured session JWT; every awaited response is rejected
  after session changes. Account/auth events immediately hide previous admin
  content and close dialogs. Supabase auth callbacks schedule verification after
  returning, avoiding reentrant auth calls.
- Queue requests are also scoped to their page and search generation. Older
  requests cannot replace a newer query. Confirmation and mutation controls
  prevent duplicate submissions; successful rows are reloaded from the server.
- A mutation timeout is **uncertain**, not proof of failure. The UI asks the admin
  to refresh and inspect the audit history before retrying.
- Private post media uses a 300-second signed URL requested with the captured JWT.
  The original media must be on the configured backend, in `posts`, and have the
  row’s author path. The server must independently confirm that the object is
  attached to reviewable content. The returned URL must match the same origin
  and exact object path. Media denial is shown as a preview failure, not a blank
  successful result. Signed links are not persisted by this UI.
- External HTTPS media is displayed without an Authorization header or referrer.
  HTML is escaped, URL schemes are checked, and untrusted values never enter
  inline JavaScript event handlers. The admin client performs no DM-table or
  account-email lookups; selected report context comes from the guarded report RPC.

## Local checks

```sh
node --test tools/deployment/tests/test_web_admin.mjs
python3 -m unittest discover -s tools/deployment/tests -p test_admin_clients.py
```

The Node fixtures have no live backend. They exercise role/session races,
duplicate confirmation, stale queues, server rejection, uncertain mutations,
XSS boundaries, signed-media path checks and exact affected-row validation.
These local checks do not establish production deployment or server policy
status; staging verification with an authorized admin is still required.


An additional offline browser check is available at
`tools/deployment/tests/web_admin_browser_check.mjs`. It requires installed
Playwright and Chrome (override `PLAYWRIGHT_MODULE` and `CHROME_BIN` when needed),
uses a fresh profile and intercepts every backend/CDN request. It checks desktop,
390px and 320px layouts, the reason dialog, rejected actions, decoded private
media and account changes. Screenshots and logs belong under the ignored
`build/audit/2026-11-03/admin-refresh/` directory and are labeled fixture data.
