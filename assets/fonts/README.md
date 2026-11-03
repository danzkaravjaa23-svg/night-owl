# Bundled app fonts

These unmodified TTFs are the exact files described by the resolved
`google_fonts` **6.3.3** package (the pubspec constraint is `^6.2.1`). They were
downloaded from Google's `fonts.gstatic.com` CDN and checked against the
package's expected SHA-256 and byte length. `manifest.json` records each
immutable source URL, checksum, length, weight, and license provenance.

Only variants requested by the current code are included:

| Family | Normal weights | Used by |
| --- | --- | --- |
| Inter | 400, 500, 600, 700, 800 | App theme, text tokens, wordmark |
| JetBrains Mono | 400 | Monospaced text tokens |
| Manrope | 800 | Story text option 0 |
| Playfair Display | 700 | Story text option 1 |
| Pacifico | 400 | Story text option 2 |
| Bebas Neue | 400 | Story text option 3 |

The story selector changes family, not weight. Existing style calls remain
unchanged. `google_fonts` finds these filenames through Flutter's asset manifest
before consulting device storage or the network. `AppFonts.configure()` disables
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
update the manifest, license registration, and offline test. Do not silently
enable runtime downloads to cover a missing asset.

Verification: `flutter test --no-pub test/bundled_fonts_test.dart`. The test
clears the package's memory cache, forbids disk-cache fallback and HTTP, then
loads the current app styles and all story font variants from the real asset
manifest. It also verifies every packaged font and license checksum.
