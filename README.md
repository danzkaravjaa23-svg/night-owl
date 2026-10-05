# Night Owl UB

Flutter social discovery app for Ulaanbaatar nightlife, using Supabase for authentication, data, storage and realtime messages.

## Current delivery

The current release is a free app: no active billing, subscriptions, premium unlocks or in-app purchases. QPay and payment history are removed; legacy QPay links open the corresponding post. Invitations are free sharing links with no reward or unlock promise. There are no paid-content entitlements requiring a payment migration. Payment integration is deferred until after deployment and is not a blocker for this free release. Venue and event admission prices, when shown, are information from their organizers; they do not mean that the app charges users or that every venue/event is free. An RSVP records interest or attendance and is not a ticket or payment.

The user-approved design board is now applied: round purple owl branding, a full-width five-action footer, an adaptive street map with lavender venue details, a clean story/photo feed, and a centered profile with square photo tiles. Real account and venue data remain connected. The latest requested dimensional glyphs and buttons use Flutter vector layers, gradient shaders, shadows and press motion; they are UI rendering, not 3D models or new AI artwork. The approved flat owl and reference layouts remain in place. See [approved reference and logo prompts](docs/BRAND_REFERENCE.md), [design comparison with screenshots](docs/design-review.html), [design decisions and location sources](docs/DESIGN_REVIEW.md), and [release status and blockers](docs/RELEASE_READINESS.md). This update has not been confirmed pushed to GitHub or deployed. Native binaries and store publishing have not been completed.

Settings exposes Day / Night / System appearance choices; sun/moon actions on Feed and Messages offer quick switching. Night remains the default, and System follows device brightness. Surfaces, text, map tiles and controls adapt while photo overlays retain their white actions and the map keeps its camera position and zoom. Theme choices persist on the device in order. Late startup reads cannot replace a newer choice; failed saves report an error, roll back only the latest choice, and attempt to restore storage/cache. Late results after disposal do not change the active colors.

Apple sign-in now has native iOS nonce/identity-token authentication, web/Android OAuth and a public provider-status check. The backend still reported Apple disabled on 2026-10-05, so successful login requires Apple Developer and Supabase configuration. See [Apple sign-in setup](docs/APPLE_SIGN_IN_SETUP.md) for exact identifiers/callbacks and server-only secret handling. No real Apple end-to-end or iOS device login has been verified.

## Development

Use Flutter 3.44.0 (Dart 3.12.0) with the committed lockfile.

```sh
flutter pub get
flutter analyze --no-pub
flutter test --no-pub
flutter run -d chrome --dart-define=DEVICE_PREVIEW=false
flutter build web --no-pub --release --dart-define=DEVICE_PREVIEW=false
```

The new check-in client requires `supabase/migrations/202610050001_check_in_venue.sql` before release. Deploy and test the delete-account function separately. Do not put service-role keys, signing passwords or Apple provider keys into the client or repository.

Production configuration supports `PUBLIC_APP_URL`, `MAP_TILE_URL`, `MAP_ATTRIBUTION`, `MAP_ATTRIBUTION_URL` via Dart defines. Map pins use source-linked reviewed corrections only for exact legacy seed positions; owner edits are preserved. Load-test rows are hidden without deleting server data.

CI builds web and unsigned native artifacts, but has not yet run remotely. Android release signing uses ignored `android/key.properties`, with an example committed. iOS uses the existing bundle identifier and requires a developer team/provisioning configuration.
