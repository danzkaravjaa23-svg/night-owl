# Night Owl UB

Flutter social discovery app for Ulaanbaatar nightlife, using Supabase for authentication, data, storage and realtime messages.

## Current delivery

Backend decision (2026-10-20): keep the existing managed Supabase/PostgreSQL database, Auth, Storage and Realtime. Independent-host migration and paid server provisioning are deferred; the retained preparation tools are not an active migration plan. Continue local privacy/security audits and regression tests without changing production data, schema or endpoints.

The current release is a free app: no active billing, subscriptions, premium unlocks or in-app purchases. QPay and payment history are removed; legacy QPay links open the corresponding post. Invitations are free sharing links with no reward or unlock promise. There are no paid-content entitlements requiring a payment migration. Payment integration is deferred until after deployment and is not a blocker for this free release. Venue and event admission prices, when shown, are information from their organizers; they do not mean that the app charges users or that every venue/event is free. An RSVP records interest or attendance and is not a ticket or payment.

The user-approved design board is now applied: round purple owl branding, a full-width five-action footer, an adaptive street map with lavender venue details, a clean story/photo feed, and a compact profile with real statistics and square photo tiles. Real account and venue data remain connected. Dimensional glyphs and buttons use gradients, shadows and press motion. The approved owl and layouts remain in place. See [approved reference](docs/BRAND_REFERENCE.md), [design comparison](docs/design-review.html), and [release status](docs/RELEASE_READINESS.md). Release commit `7c277c7` is pushed to `night-owl-features` and published at [nightowl-ub.netlify.app](https://nightowl-ub.netlify.app/). The public JavaScript matches the tested local build and immutable Netlify deploy `6ac415570767e000085a73fd`. PostgreSQL migration remains preparation only; the app continues using its existing hosted backend. Native binaries and store publishing remain incomplete.

Close map zoom now shows each venue separately, including overlapping locations. Displaced pins have leader lines to their real coordinates; selecting one preserves the camera and zoom. Zooming out restores count groups. All 14 focused map tests pass, with direct pin selection and regrouping verified on the public release.

The current performance changes keep the map, camera and tile state mounted when switching to the venue list, pause hidden map painting/animations, and draw cached gradient glyphs directly instead of compositing one ShaderMask per icon. Chat/group RPC failures now fail closed; only an explicitly missing RPC on the current managed backend permits the legacy fallback. All 219 Flutter tests and analysis pass; an actual phone FPS benchmark has not been measured.

The local UX update adds 270 attributed OpenStreetMap places in central Ulaanbaatar, marker grouping, venue contact/source details, improved introductory copy, and a Higgsfield-generated owl emotion atlas for real loading/error/success states. Routes and buttons honor reduced motion. Google Places tooling is prepared, but no Google data has been imported without an API credential. See [venue data sources](tools/venues/README.md). All 219 Flutter tests, 7 web-startup tests, analysis and the web build pass. The public release was verified in the browser on 2026-10-06: startup loading, navigation, day/night, grouped map/list, venue details and profile Saved state; error logs were empty.

Independent PostgreSQL preparation includes guarded export/restore tools, a fail-closed API gateway, shared public configuration for Flutter, web admin and the Chrome extension, and [three target RPCs](backend/patches/README.md) tested with fictional PostgreSQL data and concurrent requests. The source's 60 core tables/1,948 rows and 96 public media files have supplemental private local backups outside Git; this is not a complete database archive or completed migration. A private database password, target host, target authorization review and Auth/Storage/Realtime integration remain required. See [migration status and procedures](docs/POSTGRES_MIGRATION.md), [gateway preparation](backend/README.md), and [services on your own host](backend/OWN_HOST_SERVICES.md).

Settings exposes Day / Night / System appearance choices; sun/moon actions on Feed and Messages offer quick switching. Night remains the default, and System follows device brightness. Surfaces, text, map tiles and controls adapt while photo overlays retain their white actions and the map keeps its camera position and zoom. Theme choices persist on the device in order. Late startup reads cannot replace a newer choice; failed saves report an error, roll back only the latest choice, and attempt to restore storage/cache. Late results after disposal do not change the active colors.

Apple sign-in now has native iOS nonce/identity-token authentication, web/Android OAuth and a public provider-status check. The backend still reported Apple disabled on 2026-10-05, so successful login requires Apple Developer and Supabase configuration. See [Apple sign-in setup](docs/APPLE_SIGN_IN_SETUP.md) for exact identifiers/callbacks and server-only secret handling. No real Apple end-to-end or iOS device login has been verified.

## Development

Independent PostgreSQL migration is deferred by the owner. The [server/API setup and controlled migration sequence](docs/POSTGRES_START_HERE.md) is retained for future reference only. Server provisioning, live migration and endpoint changes have not been performed by this preparation.

### Managed-backend audit (2026-10-20, local only)

A regression fixture reproduced a DM thread retaining the previous account's private message history after an account switch. Direct-message state is now keyed by account and partner: history, composer draft, permission state, subscriptions and polling are discarded on account/route changes; sign-out removes the thread/composer. Reply-note text is not carried to another account. Late profile, message, permission and failed-send results cannot restore an old chat or authorize the new account. Same-account session updates preserve the draft.

Nine new mocked-HTTP tests cover these boundaries. All 381 Flutter tests, Flutter analyze, the isolated social SQL/preflight fixture, 11 client-configuration tests and 7 web-startup tests pass; the JavaScript release web build succeeds with the existing Supabase configuration. The dependency's existing WebAssembly dry-run incompatibility warning remains; this was not a Wasm build. These checks do not verify hosted policies or real-account/device behavior. No production schema/data/endpoint changes, push or deployment were performed.

### Social discovery work (2026-10-16, not yet deployed)

This checkout includes private accounts and follow approvals, a guarded one-message DM request, creator video publishing, compound-cursor Following, shared source-backed venue references, creator discovery, public content links with login return, account-synced venue saves, place collections, reviewed venue details, and an administrator pilot dashboard. The pilot starts empty: 10–15 creators, 20–30 reviewed places and 60–100 reviewed posts are targets, not seeded accomplishments. Creators and ordinary testers are separate cohorts in the dashboard; only enrolled participants produce discovery measurements. Activation uses the first 24 hours after pilot enrollment, D7 uses hours 168–192, and only matured participants enter each denominator. Repeated publishing requires different UTC dates. Directions count unique participant/place/UTC-day combinations after enrollment.

Deploy `supabase/migrations/202610160001_social_discovery.sql`, then `202610160002_osm_catalog.sql` on a staging copy first. The second migration imports the existing attributed 270 OSM records without marking any business reviewed. UUID community venues keep their existing IDs; OSM references never enter UUID columns. Venue approval requires a cover, address, hours and budget. Use **Админ панел → Эхний туршилт** to enroll real creators/testers, prepare and approve places, and select visible venue-linked posts. No person has been recruited or real user content approved by this change.

Before deployment, run `tools/deployment/tests/social_discovery_preflight.sql` as the staging database owner. It is read-only, rejects incompatible column types or API roles that bypass RLS/create public objects, and lists existing content-reading SECURITY DEFINER RPCs for manual review. A passing preflight is not a complete security audit: inspect those RPCs and existing hosted policies, then perform the real-account checks before production.

The first migration tightens existing RLS and switches the `posts` and `stories` buckets to private. Active post/story image/video renderers request authorized five-minute signed links for this backend's Storage objects. External media links remain subject to their host's visibility; previously downloaded/publicly cached copies cannot be revoked. Coordinate the client deployment with this migration: old clients still using public media URLs will need the new version. Verify the hosted schema, existing Storage policies and the latest hosted role grants before applying; offline fixtures are not evidence that the migration is installed on production. Do not reapply older public-bucket setup SQL afterward.

DM permissions refresh every 15 seconds only while that conversation is visible and the app is active, and refresh immediately on resume. Failed permission checks disable sending without dropping the draft. Legacy device bookmarks import in one account-bound transaction; obsolete place IDs are ignored and imports do not count as new pilot saves. Ordinary saves remain server-authoritative even if the device cache cannot be updated.

Following Reels use the invoker/RLS-protected `get_following_reels` RPC, filtering accepted follows and valid video candidates before the 50-video limit rather than filtering the global newest page. Switching tabs ignores late responses; returning after a social/privacy change rechecks the cached clips. Reel reports now use the existing server-backed reporting flow instead of a local success toast. Reel save/remove failures restore the prior state and duplicate taps cannot issue concurrent writes. Place details and the map share one account-scoped bookmark provider; denied writes preserve the current state, bookmark read failures do not hide public place information, and switching accounts removes old place posts while fresh data loads.

Existing block pairs are cleaned up during the migration as well as on new blocks. Expired stories/check-ins are hidden from other accounts by RLS, not just by UI filters. Owners can still read their own historical rows; expiration is not a Storage deletion job.

Place details and collection pages discard cached rows while reloading after account or social/privacy changes. Reusing the collections route for another profile fetches that profile's lists, and collection actions are gated to the current owner. Place pull-to-refresh failures stay in the error/retry view instead of escaping the refresh callback.

Post details and comment streams are account/social-scoped; the comment mini-profile cache follows the account. A different account, privacy state or shared post route clears the old post, comments and reply draft while access is rechecked. Late fetch, like, comment and own-post action results cannot change a newer view. Unavailable posts do not expose cached comments or the comment input. Reaction writes honor the caller's visible state even if the feed cache is stale, off-feed duplicate writes are guarded, counts stay nonnegative, and a failed reaction does not undo a caption saved while it was pending.

Feed and post-detail save/remove actions now serialize duplicate taps through the write and saved-ID refresh, release their guard after failures, and ignore late results for another account or post. The saved-post grid is account/social-scoped: account changes, sign-out and privacy changes remove the old list immediately, and late index/media responses cannot restore it. Pull-to-refresh failure remains retryable.

Post-save ID reads preserve failures instead of treating them as an empty list and time out after 15 seconds. Feed, Details and Reels wait for a successful read before choosing save/remove, retry failed reads, and ignore actions that outlive their account. A confirmed write remains visible if its readback fails, with a separate retryable notice. Fresh reads synchronize the shared saved state without overwriting pending writes. The shared auth stream follows the active Supabase client rather than retaining a disposed client's session stream.

Local verification on 2026-10-16: 372 Flutter tests, the isolated social SQL/preflight fixture, 11 client-configuration tests and 7 web-startup tests pass; Flutter analyze reports no issues and the release web build succeeds. Reactions in post details/Reels update already-loaded Following/All feed caches, and duplicate detail/reel taps are guarded. These results do not verify hosted migrations, native devices or real-account behavior.

The approved local implementation and regression pass are complete. Release gates remain outside this checkout: review the hosted RPCs/roles/Storage policies with the read-only preflight on staging, explicitly authorize and test the two migrations there, run two real-account/device privacy/follow/block/DM/media checks, and supply real consenting creators, reviewed places and content for the pilot. Only review promotion/partnership experiments after real cohort results. No migration, production write, remote push, account creation or paid promotion was performed by the local continuation.

SQL verification (official `@electric-sql/pglite@0.5.8`, installed outside the checkout):

```sh
node tools/deployment/tests/run_social_discovery_fixture.mjs /absolute/path/to/@electric-sql/pglite/dist/index.js
```

`flutter run -d web-server --web-port 5557 -t test/support/discovery_preview.dart` is an isolated visual fixture with synthetic accounts and a mocked HTTP client. It never uses the live backend and is not a production demonstration. Normal development still runs `lib/main.dart`. Production migration, two real-account/device checks, actual partner recruitment and publishing require their real environments and data. Do not start paid venue promotion or creator partnerships until the pilot results have been reviewed; this batch does not activate advertising or billing.

Use Flutter 3.44.0 (Dart 3.12.0) with the committed lockfile.

```sh
flutter pub get
flutter analyze --no-pub
flutter test --no-pub
flutter run -d chrome --dart-define=DEVICE_PREVIEW=false
sh tools/deployment/build_web.sh --no-pub
```

With the current hosted backend, the check-in client requires `supabase/migrations/202610050001_check_in_venue.sql` before release. The independent target uses the reviewed [target RPC patch](backend/patches/README.md) after restore/ownership review. Deploy and test the delete-account function separately. Do not put service-role keys, signing passwords or Apple provider keys into the client or repository.

Production configuration supports `PUBLIC_APP_URL`, `MAP_TILE_URL`, `MAP_ATTRIBUTION`, `MAP_ATTRIBUTION_URL` via Dart defines. Map pins use source-linked reviewed corrections only for exact legacy seed positions; owner edits are preserved. Load-test rows are hidden without deleting server data.

The shared build reads public `BACKEND_MODE`, `BACKEND_URL` and `BACKEND_PUBLIC_KEY` settings from the environment and validates them before compiling. PostgreSQL mode requires an independent HTTPS API origin and a public anonymous JWT; database passwords and server signing/service keys never belong in these settings. Generated `build/backend-defines.json` supplies the same settings to web, Android and iOS CI builds. Default builds keep the working hosted backend until migration verification passes.

CI builds web and unsigned native artifacts, but has not yet run remotely. Android release signing uses ignored `android/key.properties`, with an example committed. iOS uses the existing bundle identifier and requires a developer team/provisioning configuration.
