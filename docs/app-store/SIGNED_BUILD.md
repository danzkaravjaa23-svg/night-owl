# Signed iOS archive and local export

Updated on 2026-11-05 for Team `DAVM2JZ4NN`, bundle `com.nightowl.ub.nightOwlUb`, App Store Connect app `6830714135`, version `1.0.0`. Runner Debug/Profile/Release select this verified Team. The local signed staging archive and exported IPA below are verified. Upload and production submission remain separate steps.

**Local toolchain verified on 2026-11-05:** macOS **15.8.2 (`24H232`)**, official Apple-silicon Xcode **26.3 (`17C529`)** at `/Applications/Xcode.app`, selected developer directory `/Applications/Xcode.app/Contents/Developer`, and iPhoneOS SDK **26.2**. The downloaded Xcode passed `pkgutil` system-trust verification as signed Apple Software, and the app passed `codesign --deep --strict`. `xcodebuild -checkFirstLaunchStatus` now exits **0**; the previous macOS/license/first-launch blockers are cleared. SDK presence and this first-launch check do not establish that every required platform component is installed. Full `ios_preflight.py` reports **15 PASS**, including pinned Flutter **3.44.0** and CocoaPods; all **40 `test_ios_*.py` tests PASS**.

**Verified local candidate:** source **`878a941966aa06baf8a03dcf99d33464fc9d2b88`**, **staging 1.0.0 (1)**, `DEVICE_PREVIEW=false`. Flutter retained SwiftPM with CocoaPods fallback for `flutter_secure_storage` and `share_plus`; the six native configuration/lock files were reviewed and committed. Repeated config-only generation and the final scoped source check showed no drift. Online `flutter pub get --enforce-lockfile` failed TLS verification; `flutter pub get --offline --enforce-lockfile` succeeded using the cached locked dependencies. TLS verification was not disabled. The existing Distribution identity/profile were revalidated. The serial **`-jobs 1` archive and manual local export both exited 0**.

**Exported artifact verified at 2026-11-05 10:27:02 UTC:** `build/ios-signing/878a941966aa06baf8a03dcf99d33464fc9d2b88-1.0.0-1-staging/export/night_owl_ub.ipa`, **33,639,810 bytes**, SHA256 **`f4e9286ff15e9090db3fc4db65b3d5fddaebe269c478743e7d7fe7e38a2e5bf3`**. ZIP CRC and 226 safe, unique entries passed; no symlinks were accepted. The repository helper verified the exported signature, Team/bundle/version/Apple entitlement, embedded profile and generated backend/preview config. The actual embedded public signing leaf certificate SHA-1 matches **`D1BFC420BB731368787AAE217CB8FA9B976F16FE`**. There are **12 privacy manifests** and **7 dSYM bundles**. The private local candidate directory retains `Runner.xcarchive`, the IPA, symbols, logs and sanitized `artifact-receipt.json`; [the setup receipt](evidence/local-ios-signing-setup.json) records the result without credentials. No private key was exported.

**Resolved local build issues:** the first archive exited 70 before compilation because iOS Platform Support was missing. The CLI iOS 26.2 download installed an additional simulator; **Xcode Settings → Components → Get** completed the required platform support. Components shows iOS **26.2** and iOS **26.3.1 Simulator** installed, and the fresh destination check lists **Any iOS Device** as available with exit 0 and no ineligible destinations. A later Flutter framework step exited 75 on Finder metadata. Only the observed FinderInfo attribute on the generated Desktop `Flutter.framework` was removed; cached `Flutter.xcframework` provenance/quarantine remained intact. DerivedData moved to `/private/tmp/nightowl-ios-878a941-soq7ps42/DerivedData`. Parallel signing then exited 65 on `app_links_app_links.bundle` with `errSecInternalComponent`. A single-bundle sign probe passed, followed by the successful single-job archive; an incorrect password was not established, and no Keychain ACL was changed. Earlier commands/results/logs remain available privately.

**Xcode handoff:** the archive is open in Organizer as **1.0.0 (1)**, bundle **`com.nightowl.ub.nightOwlUb`**, Team **`DAVM2JZ4NN`**, architecture **arm64**. **Validate App** and **Distribute App** were not clicked. No App Store Connect upload, TestFlight processing, device acceptance or App Review submission has occurred. This staging artifact is for acceptance; production backend/provider and release gates remain open.

**Local signing assets revalidated on 2026-11-05:** Apple Distribution certificate **`B24XM2GM33`**, Team **`DAVM2JZ4NN`**, SHA-1 **`D1BFC420BB731368787AAE217CB8FA9B976F16FE`**, was created with the owner's explicit approval. Its public key matches the Keychain-generated CSR; the private key remains in the login Keychain and was not exported. Apple's WWDR G3 intermediate was verified against the existing root and imported without a trust override. `security find-identity` reports **1 valid identity**.

App Store Connect profile **Night Owl UB App Store 2026-11-05** (portal ID **`73ZQZ7J549`**, UUID **`179bf2a0-640f-4b1a-b1c2-6a8b5b221bbc`**) expires **2027-11-04T16:44:33Z**. The helper validated its exact `DAVM2JZ4NN.com.nightowl.ub.nightOwlUb` app identifier, `com.apple.developer.applesignin = ['Default']`, `get-task-allow = false`, `beta-reports-active = true` and matching certificate SHA-1. The profile is installed in both standard Xcode and MobileDevice provisioning-profile folders with mode **0600**. Supporting signing files are in `/Users/usukhesbesty/Night Owl Apple Access 2026-11-04` with file mode **0600**; this does not establish possession of the separate Apple-login `.p8` key. [Verified local setup receipt](evidence/local-ios-signing-setup.json).

## Required inputs

- A committed, clean iOS/runtime candidate; the old unsigned CI artifact does not prove this Team change has compiled.
- Pinned Flutter 3.44.0, CocoaPods, full Xcode 26+ and iOS SDK 26+, with the owner's license/first-launch setup completed.
- The **installed and verified** local Distribution identity and profile above; recheck their validity before each build. The helper reads public profile/identity metadata, not the private key. The `.p8` Apple login key is not an app signing identity.
- One public JSON config containing exactly `BACKEND_MODE`, `BACKEND_URL`, `BACKEND_PUBLIC_KEY`; the existing validator rejects server/user credentials. Staging uses `sreojqqqhdzkfsrbvlpl`; production uses `jbbdnpsvstwxtgtjoeru`. The `anon` JWT's project ref must match the chosen origin. Never supply a server `.env`, service-role key or signing key.
- A build number verified unused in Connect. `1` matches the current source and no build has been uploaded as of this preparation; recheck before each upload. Staging acceptance is not a production submission candidate.

## Protected manual CI candidate

[The signed-candidate workflow](../../.github/workflows/ios-signed-candidate.yml) uses the existing `macos-15` / Xcode 26.3 runner and runs only through `workflow_dispatch`. It accepts the exact source commit, an unused build number, and `staging` or `production`; it refuses another branch than `codex/app-store-preparation`. GitHub must make this workflow available for manual dispatch (the workflow normally needs to be present on the repository default branch). Do not change the default branch or merge other runtime work merely to expose this button.

Before adding any credentials, configure the GitHub environment **`ios-signing`** with required reviewers, prevent self-review where the repository's plan supports it, and restrict deployment branches to `codex/app-store-preparation`. Configure environment variable **`IOS_SIGNING_READY=true`** only after those protections and artifact access have been reviewed. An environment name or this variable alone does not create or prove an approval rule. If the repository plan cannot enforce the required approval, leave the workflow disabled and use the controlled local-host procedure below.

The environment needs exactly these inputs:

| Environment secret | Contents |
|---|---|
| `IOS_DISTRIBUTION_P12_BASE64` | Base64 of an existing Apple Distribution certificate/private-key `.p12` export, provided through the private credential channel |
| `IOS_DISTRIBUTION_P12_PASSWORD` | Password for that `.p12`; do not put it in command text, Git or chat |
| `IOS_APP_STORE_PROFILE_BASE64` | Base64 of an existing unexpired App Store Connect distribution profile for this Team/bundle and Apple entitlement |
| `IOS_PUBLIC_BACKEND_CONFIG_JSON` | The three public BACKEND settings for the explicitly selected environment; no service-role or user token |

An App Store Connect API key is **not required** for this offline manual archive/export workflow. It needs GitHub `contents: read` only, aside from the runner's standard artifact service; it does not grant account/production permissions. No environment, approval rule, secret, certificate or profile was created by preparing this workflow.

The helper validates the profile's Team, explicit app identifier, Apple entitlement, expiry, App Store distribution type and matching valid Distribution identity. It rejects an environment/key-ref mismatch, debug entitlement, altered generated backend/preview settings and version/build drift. Signing uses an isolated temporary keychain, restores the prior search list and removes installed temporary profiles/assets in an `always()` cleanup. The `NIGHTOWL_APP_PROFILE_UUID` input resolves only in Runner target configurations; the profile is never forced globally onto CocoaPods targets. There is no provisioning-update/device-registration flag, automatic fallback, ASC upload or deployment.

After ZIP integrity, exported code-signature, bundle/Team/entitlement/version and generated-config checks pass, the workflow retains only the IPA, its checksum and a sanitized verification receipt for **3 days**. The IPA necessarily contains its public distribution provisioning metadata; it does not contain the `.p12`, private key, password or `.p8`. No raw logs, profile source, keychain, backend-config file, archive or symbols are published. Review artifact access before dispatch. This short-lived candidate is for validation; an operational release handoff still needs controlled archive/symbol retention, device acceptance and a separately authorized upload. The workflow has **not been dispatched** or signed-build-tested yet.

## Archive and export, after those inputs exist

Run from the repository root with the verified full Xcode toolchain. Keep generated DerivedData in private temporary storage outside the Desktop/FileProvider location, as in the current retry. Set the public config path, choose staging or production, and confirm the build number first. `ios_signing.py prepare` refuses an existing destination and generates the receipt consumed by its `verify` command. It uses the existing local identity/profile without exporting a private key. This recipe does not upload or pass provisioning-update/device-registration flags. Flutter 3.44's ordinary `flutter build ipa` export path includes those flags, so it runs `xcodebuild` directly after Flutter generates its configuration.

```sh
set -eu
umask 077
export DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer
nightowl_config='/absolute/path/to/public-backend.json'
nightowl_profile="$HOME/Library/Developer/Xcode/UserData/Provisioning Profiles/179bf2a0-640f-4b1a-b1c2-6a8b5b221bbc.mobileprovision"
nightowl_environment='staging'
nightowl_build_number='1'
nightowl_derived_data=$(mktemp -d '/private/tmp/nightowl-ios-derived-data.XXXXXX')

python3 tools/deployment/ios_preflight.py
test -z "$(git status --porcelain --untracked-files=normal -- ios lib assets pubspec.yaml pubspec.lock tools/deployment/ios_preflight.py tools/deployment/ios_signing.py tools/deployment/build_admin_clients.py)"
nightowl_commit=$(git rev-parse HEAD)
nightowl_bundle="$(pwd)/build/ios-signing/${nightowl_commit}-1.0.0-${nightowl_build_number}"
export nightowl_bundle
test ! -e "$nightowl_bundle"
nightowl_metadata=$(mktemp -d "${TMPDIR:-/tmp}/nightowl-signing-metadata.XXXXXX")
trap 'rm -rf "$nightowl_metadata"' EXIT
security cms -D -i "$nightowl_profile" > "$nightowl_metadata/profile.plist"
security find-identity -v -p codesigning > "$nightowl_metadata/identities.txt"
python3 tools/deployment/ios_signing.py prepare \
  --config "$nightowl_config" --environment "$nightowl_environment" \
  --profile-plist "$nightowl_metadata/profile.plist" \
  --identities "$nightowl_metadata/identities.txt" \
  --source-commit "$nightowl_commit" --build-number "$nightowl_build_number" \
  --output "$nightowl_bundle"
nightowl_profile_uuid=$(python3 -c 'import json,os; print(json.load(open(os.environ["nightowl_bundle"]+"/input-receipt.json"))["profile_uuid"])')
nightowl_identity_sha1=$(python3 -c 'import json,os; print(json.load(open(os.environ["nightowl_bundle"]+"/input-receipt.json"))["signing_identity_sha1"])')

flutter pub get --enforce-lockfile
flutter build ios --config-only --release --no-codesign --no-pub \
  --build-name=1.0.0 --build-number="$nightowl_build_number" \
  --dart-define=DEVICE_PREVIEW=false \
  --dart-define-from-file="$nightowl_bundle/backend-defines.json"
xcodebuild -workspace ios/Runner.xcworkspace -scheme Runner -jobs 1 \
  -configuration Release -destination 'generic/platform=iOS' \
  -archivePath "$nightowl_bundle/Runner.xcarchive" \
  -derivedDataPath "$nightowl_derived_data" \
  DEVELOPMENT_TEAM=DAVM2JZ4NN CODE_SIGN_STYLE=Manual \
  CODE_SIGN_IDENTITY="$nightowl_identity_sha1" \
  NIGHTOWL_APP_PROFILE_UUID="$nightowl_profile_uuid" archive
xcodebuild -exportArchive -archivePath "$nightowl_bundle/Runner.xcarchive" \
  -exportOptionsPlist "$nightowl_bundle/ExportOptions.plist" \
  -exportPath "$nightowl_bundle/export"
```

The local run above completed archive/export and exported-app validation for the recorded staging candidate. A missing/expired identity or profile must still be resolved on the signing host; do not turn on automatic provisioning as a silent fallback. For each new IPA, check ZIP integrity, safe unique paths and absence of symlinks before extracting with executable permissions preserved, then run `ios_signing.py verify` with `--app` pointing to the extracted `Payload/Runner.app`, `--prepared` to the generated bundle directory, `--generated-config ios/Flutter/Generated.xcconfig` and `--receipt` to a new verification JSON file in that private build directory. This checks Team, bundle, version/build, Apple entitlement, embedded profile and generated backend/preview configuration. Also extract the app's public certificate chain with `codesign -d --extract-certificates=PREFIX APP` and compare certificate 0's SHA-1 with the prepared identity; this reads public embedded certificates, not the private key. The optional prefix must be attached with `=`. Retain the archive, symbols, config digest and verification result together in ignored/private storage. An input receipt alone does not prove build success.

For a host whose locked dependencies are already cached, `flutter pub get --offline --enforce-lockfile` is the verified fallback after an online TLS failure; do not disable certificate verification. If Flutter generates tracked native integration changes, review and commit them, confirm repeated generation produces no source drift, then prepare a new candidate directory using that commit before archiving.

Upload is a separate step after signed artifact validation and the backend/provider gates. TestFlight processing, device acceptance and App Review are still outstanding. [Flutter's official iOS release guide](https://docs.flutter.dev/deployment/ios) describes version/build flags and archive/export; verify export-option support with `xcodebuild -help` on the actual signing host. [Existing acceptance plan](REVIEW_TEST_PLAN.md) covers the required iPhone/iPad behavior.
