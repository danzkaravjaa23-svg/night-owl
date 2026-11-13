# Bundled app fonts

These unmodified TTFs are the exact files described by the resolved
`google_fonts` **6.3.3** package (the pubspec constraint is `^6.2.1`). They were
downloaded from Google's `fonts.gstatic.com` CDN and checked against the
package's expected SHA-256 and byte length. `manifest.json` records each
immutable source URL, checksum, length, weight, and license provenance.

Only variants requested by the current code are included:

| Family | Normal weights | Used by |
| --- | --- | --- |
| Inter | 400, 500, 600, 700, 800 | App theme, text tokens, wordmark (pubspec family); story fallback |
| JetBrains Mono | 400 | Monospaced text tokens |
| Manrope | 800 | Story text option 0 |
| Playfair Display | 700 | Story text option 1 |
| Pacifico | 400 | Story text option 2 |
| Bebas Neue | 400 | Story text option 3 |

Inter is also declared as a pubspec font family (`flutter > fonts` in
`pubspec.yaml`, one file per weight: 400, 500, 600, 700, 800). The engine
registers it at launch. `ThemeData(fontFamily: 'Inter')` and `AppTextStyles`
(`AppTextStyles.fontFamily`) use that family, so every weight renders from its
own file instead of an emboldened Regular. App code does not call
`google_fonts` outside `lib/core/theme/` and the story editor
(`test/design_token_ratchet_test.dart` enforces this). The package now serves
only JetBrains Mono (`AppTextStyles.mono`/`monoSm`), the four story font options
and the story editor's Inter w700 fallback, all from these bundled files.

The story selector changes family, not weight. `google_fonts` finds these
filenames through Flutter's asset manifest before consulting device storage or
the network. `AppFonts.configure()` disables
runtime font downloads and registers the six OFL licenses with Flutter's
`LicenseRegistry`. Font assets total **2,081,092 bytes**; licenses total
**26,338 bytes**. No dynamic download or font transformation is part of a build.

All six families use SIL Open Font License 1.1. The accompanying original
copyright notices and full licenses are included as `<Family>-OFL.txt`, copied
from the official `google/fonts` repository at the commit in `manifest.json`.
Fonts were not renamed internally, subsetted, or otherwise modified.

When adding a family/weight or updating `google_fonts`, use the new resolved
package's `GoogleFontsFile` descriptor, keep the loader's filename suffix
(for example, `Inter-SemiBold.ttf`), verify its SHA-256 and byte length, and
update the manifest, license registration, and offline test. A new Inter
weight also goes into the pubspec `Inter` family with its `weight:`. Do not
silently enable runtime downloads to cover a missing asset.

Verification: `flutter test --no-pub test/bundled_fonts_test.dart`. The test
clears the package's memory cache, forbids disk-cache fallback and HTTP, then
loads the current app styles and all story font variants from the real asset
manifest. It also verifies every packaged font and license checksum, checks
that `pubspec.yaml` and the built `FontManifest.json` declare the five Inter
files as one family with their weights, and checks that each Inter weight
renders its own file (no synthetic bold). `test/flutter_test_config.dart`
registers the Inter family from `FontManifest.json` before every test, so
widget tests and visual captures measure real Inter metrics.

On a Windows checkout with `core.autocrlf=true`, Git writes the license `.txt`
files with CRLF line endings, so the license checksum check fails locally. The
committed files use LF and match the pinned bytes.
