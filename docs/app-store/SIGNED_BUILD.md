# Signed iOS archive and local export

Updated on 2026-11-05 for Team `DAVM2JZ4NN`, bundle `com.nightowl.ub.nightOwlUb`, App Store Connect app `6830714135`, version `1.0.0`. Runner Debug/Profile/Release select this verified Team. Source checks and the installed signing assets below do not prove a signed build or upload.

**Local toolchain:** official Apple-silicon Xcode **26.3** is now at `/Applications/Xcode.app`. Its download passed `pkgutil` system-trust verification as signed Apple Software, and the app passed `codesign --deep --strict`. Xcode requires macOS **15.6+**; the last verified host version is **15.5 (`24F74`)**. On 2026-11-05 the owner explicitly approved the Sequoia **15.8.2** EULA and **Agree** was clicked. The owner entered the Mac password locally and later reported a restart. The local reboot record confirms a reboot at **2026-11-05 01:40 +08**, but fresh `sw_vers` and System Settings still show **15.5 (`24F74`)**. Sequoia **15.8.2** is downloaded/prepared and System Settings shows **Restart Now** (about 20 minutes); only that update is selected, with macOS 27 and Safari unchecked. After the owner authorized it, **Restart Now** was clicked. System Settings requested the Mac password again in **“Enter your password to install software update”**, with an empty secure field. The owner must complete this second authorization locally; the installation restart has not started and OS update completion is not confirmed. Xcode first launch, its separate license and platform components are not complete; the developer directory must select full Xcode after the OS update. No signed archive, export or upload has run.

Installation selected `/Applications/Xcode.app/Contents/Developer` system-wide, so Apple tool shims currently stop at the unaccepted Xcode license. Until the owner completes setup, read-only repository work can use `env DEVELOPER_DIR=/Library/Developer/CommandLineTools git …`; this per-command workaround does not enable iOS builds or accept any license. Restoring the system-wide selection requires administrator authentication and has not been performed.

**Local signing assets verified on 2026-11-05:** Apple Distribution certificate **`B24XM2GM33`**, Team **`DAVM2JZ4NN`**, SHA-1 **`D1BFC420BB731368787AAE217CB8FA9B976F16FE`**, was created with the owner's explicit approval. Its public key matches the Keychain-generated CSR; the private key remains in the login Keychain and was not exported. Apple's WWDR G3 intermediate was verified against the existing root and imported without a trust override. `security find-identity` reports **1 valid identity**.

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

Run from the repository root only after the OS update and Xcode first launch are complete. Set the public config path, choose staging or production, and confirm the build number first. `ios_signing.py prepare` refuses an existing destination and generates the receipt consumed by its `verify` command. It uses the existing local identity/profile without exporting a private key. This recipe does not upload or pass provisioning-update/device-registration flags. Flutter 3.44's ordinary `flutter build ipa` export path includes those flags, so it runs `xcodebuild` directly after Flutter generates its configuration.

```sh
set -eu
umask 077
export DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer
nightowl_config='/absolute/path/to/public-backend.json'
nightowl_profile="$HOME/Library/Developer/Xcode/UserData/Provisioning Profiles/179bf2a0-640f-4b1a-b1c2-6a8b5b221bbc.mobileprovision"
nightowl_environment='staging'
nightowl_build_number='1'

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
xcodebuild -workspace ios/Runner.xcworkspace -scheme Runner \
  -configuration Release -destination 'generic/platform=iOS' \
  -archivePath "$nightowl_bundle/Runner.xcarchive" \
  DEVELOPMENT_TEAM=DAVM2JZ4NN CODE_SIGN_STYLE=Manual \
  CODE_SIGN_IDENTITY="$nightowl_identity_sha1" \
  NIGHTOWL_APP_PROFILE_UUID="$nightowl_profile_uuid" archive
xcodebuild -exportArchive -archivePath "$nightowl_bundle/Runner.xcarchive" \
  -exportOptionsPlist "$nightowl_bundle/ExportOptions.plist" \
  -exportPath "$nightowl_bundle/export"
```

The commands above are a prepared recipe, **not an executed or native-validated signed build**. A missing/expired identity or profile must be resolved on the signing host; do not turn on automatic provisioning as a silent fallback. Check the exported IPA's ZIP integrity and paths before extracting it with executable permissions preserved, then run `ios_signing.py verify` with `--app` pointing to the extracted `Payload/Runner.app`, `--prepared` to the generated bundle directory, `--generated-config ios/Flutter/Generated.xcconfig` and `--receipt` to a new verification JSON file in that private build directory. This checks the exact Team, bundle, `1.0.0`/chosen build number, Apple entitlement, selected backend and `DEVICE_PREVIEW=false`; follow the same extraction checks as the CI workflow. Retain the archive, symbols, config digest and build result together in ignored/private storage. An input receipt alone does not prove build success.

Upload is a separate step after signed artifact validation and the backend/provider gates. TestFlight processing, device acceptance and App Review are still outstanding. [Flutter's official iOS release guide](https://docs.flutter.dev/deployment/ios) describes version/build flags and archive/export; verify export-option support with `xcodebuild -help` on the actual signing host. [Existing acceptance plan](REVIEW_TEST_PLAN.md) covers the required iPhone/iPad behavior.
