# Night Owl UB

Flutter social discovery app for Ulaanbaatar nightlife, using Supabase for authentication, data, storage and realtime messages.

## Current delivery

The current release is a free app: no active billing, subscriptions, premium unlocks or in-app purchases. QPay and payment history are removed; legacy QPay links open the corresponding post. Invitations are free sharing links with no reward or unlock promise. There are no paid-content entitlements requiring a payment migration. Payment integration is deferred until after deployment and is not a blocker for this free release. Venue and event admission prices, when shown, are information from their organizers; they do not mean that the app charges users or that every venue/event is free. An RSVP records interest or attendance and is not a ticket or payment.

The user-approved design board is now applied: round purple owl branding, a full-width five-action footer, an adaptive street map with lavender venue details, a clean story/photo feed, and a compact profile with real statistics and square photo tiles. Real account and venue data remain connected. Dimensional glyphs and buttons use gradients, shadows and press motion. The approved owl and layouts remain in place. See [approved reference](docs/BRAND_REFERENCE.md), [design comparison](docs/design-review.html), and [release status](docs/RELEASE_READINESS.md). Release commit `7c277c7` is pushed to `night-owl-features` and published at [nightowl-ub.netlify.app](https://nightowl-ub.netlify.app/). The public JavaScript matches the tested local build and immutable Netlify deploy `6ac415570767e000085a73fd`. PostgreSQL migration remains preparation only; the app continues using its existing hosted backend. Native binaries and store publishing remain incomplete.

Close map zoom now shows each venue separately, including overlapping locations. Displaced pins have leader lines to their real coordinates; selecting one preserves the camera and zoom. Zooming out restores count groups. All 14 focused map tests pass, with direct pin selection and regrouping verified on the public release.

The current performance changes keep the map, camera and tile state mounted when switching to the venue list, pause hidden map painting/animations, and draw cached gradient glyphs directly instead of compositing one ShaderMask per icon. Chat/group RPC failures now fail closed; only an explicitly missing RPC on the current managed backend permits the legacy fallback. All 219 Flutter tests and analysis pass; an actual phone FPS benchmark has not been measured.

The local UX update adds 270 attributed OpenStreetMap places in central Ulaanbaatar, marker grouping, venue contact/source details, improved introductory copy, and a Higgsfield-generated owl emotion atlas for real loading/error/success states. Routes and buttons honor reduced motion. Google Places tooling is prepared, but no Google data has been imported without an API credential. See [venue data sources](tools/venues/README.md). All 219 Flutter tests, 7 web-startup tests, analysis and the web build pass. The public release was verified in the browser on 2026-10-06: startup loading, navigation, day/night, grouped map/list, venue details and profile Saved state; error logs were empty.

Independent PostgreSQL preparation includes guarded export/restore tools, a fail-closed API gateway, shared public configuration for Flutter, web admin and the Chrome extension, and [three target RPCs](backend/patches/README.md) tested with fictional PostgreSQL data and concurrent requests. The source's 60 core tables/1,948 rows and 96 public media files have supplemental private local backups outside Git; this is not a complete database archive or completed migration. A private database password, target host, target authorization review and Auth/Storage/Realtime integration remain required. See [migration status and procedures](docs/POSTGRES_MIGRATION.md), [gateway preparation](backend/README.md), and [services on your own host](backend/OWN_HOST_SERVICES.md).

Settings exposes Day / Night / System appearance choices; sun/moon actions on Feed and Messages offer quick switching. Night remains the default, and System follows device brightness. Surfaces, text, map tiles and controls adapt while photo overlays retain their white actions and the map keeps its camera position and zoom. Theme choices persist on the device in order. Late startup reads cannot replace a newer choice; failed saves report an error, roll back only the latest choice, and attempt to restore storage/cache. Late results after disposal do not change the active colors.

Apple sign-in now has native iOS nonce/identity-token authentication, web/Android OAuth and a public provider-status check. The backend still reported Apple disabled on 2026-10-05, so successful login requires Apple Developer and Supabase configuration. See [Apple sign-in setup](docs/APPLE_SIGN_IN_SETUP.md) for exact identifiers/callbacks and server-only secret handling. No real Apple end-to-end or iOS device login has been verified.

## Development

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
