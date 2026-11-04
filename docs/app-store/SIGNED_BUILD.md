# Signed iOS archive and local export

Prepared on 2026-11-04 for Team `DAVM2JZ4NN`, bundle `com.nightowl.ub.nightOwlUb`, App Store Connect app `6830714135`, version `1.0.0`. Runner Debug/Profile/Release now select this verified Team. The source preflight checks the Team in every configuration; this does not prove a certificate or provisioning profile exists.

The local Mac currently runs macOS 15.5 (`24F74`), with only `/Library/Developer/CommandLineTools` selected. Full Xcode and the iPhoneOS SDK are absent, and `security find-identity -v -p codesigning` reports **0 valid identities**. Nothing was installed, exported, registered, archived or uploaded during this preparation. Use a compatible Xcode host, such as the existing CI toolchain Xcode 26.3 / iOS SDK 26.2, after its signing assets are configured. Local Xcode 26.3 requires a compatible macOS update first; the previously downloaded OS update is not an installed update.

## Required inputs

- A committed, clean iOS/runtime candidate; the old unsigned CI artifact does not prove this Team change has compiled.
- Pinned Flutter 3.44.0, CocoaPods, full Xcode 26+ and iOS SDK 26+, with the owner's license/first-launch setup completed.
- An **already installed** Apple Distribution certificate with its private key in the build host's keychain, and an unexpired App Store Connect distribution profile for this Team, explicit bundle and Sign in with Apple entitlement. Only the profile UUID and certificate SHA-1 fingerprint go into the commands below. These are metadata, not private keys. The `.p8` Apple login key is not an app signing identity.
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

Run from the repository root in a shell on the signing host. Replace the three input placeholders first. The script refuses an existing destination, records the source/config identity, and uses manual signing with existing assets. It does not upload or pass provisioning-update/device-registration flags. Flutter 3.44's ordinary `flutter build ipa` export path includes those flags, so this procedure runs `xcodebuild` directly after Flutter generates its configuration.

```sh
set -eu
nightowl_config='/absolute/path/to/public-backend.json'
nightowl_profile_uuid='REPLACE_WITH_INSTALLED_APP_STORE_PROFILE_UUID'
nightowl_identity_sha1='REPLACE_WITH_EXISTING_DISTRIBUTION_CERTIFICATE_SHA1'
nightowl_backend_ref='sreojqqqhdzkfsrbvlpl'
nightowl_build_number='1'
export nightowl_config nightowl_profile_uuid nightowl_identity_sha1
export nightowl_backend_ref nightowl_build_number

python3 tools/deployment/ios_preflight.py
python3 - <<'PY'
import base64, json, os, re
from pathlib import Path
from sys import path
path.insert(0, str(Path('tools/deployment').resolve()))
from build_admin_clients import ClientConfig, CONFIG_KEYS
values = json.loads(Path(os.environ['nightowl_config']).read_text())
assert isinstance(values, dict) and set(values) == CONFIG_KEYS, 'Use only the three public settings'
config = ClientConfig.parse(values, ('', ''))
ref = os.environ['nightowl_backend_ref']
assert ref in {'sreojqqqhdzkfsrbvlpl', 'jbbdnpsvstwxtgtjoeru'}, 'Unknown release environment'
assert config.mode == 'supabase' and config.url == f'https://{ref}.supabase.co', 'Wrong backend'
segment = config.public_key.split('.')[1]
claims = json.loads(base64.urlsafe_b64decode(segment + '=' * (-len(segment) % 4)))
assert claims.get('ref') == ref, 'Public key belongs to a different project'
assert re.fullmatch(r'[0-9A-Fa-f]{8}(?:-[0-9A-Fa-f]{4}){3}-[0-9A-Fa-f]{12}', os.environ['nightowl_profile_uuid']), 'Profile UUID required'
assert re.fullmatch(r'[0-9A-Fa-f]{40}', os.environ['nightowl_identity_sha1']), 'Certificate SHA-1 required'
assert re.fullmatch(r'[1-9][0-9]{0,8}', os.environ['nightowl_build_number']), 'Positive build number required'
PY

test -z "$(git status --porcelain --untracked-files=normal -- ios lib assets pubspec.yaml pubspec.lock tools/deployment/ios_preflight.py tools/deployment/build_admin_clients.py)"
nightowl_commit=$(git rev-parse HEAD)
nightowl_bundle="$(pwd)/build/ios-signing/${nightowl_commit}-1.0.0-${nightowl_build_number}"
export nightowl_commit nightowl_bundle
test ! -e "$nightowl_bundle"
mkdir -p "$nightowl_bundle"
python3 tools/deployment/build_admin_clients.py --config "$nightowl_config" \
  --output "$nightowl_bundle/admin-clients" \
  --defines-output "$nightowl_bundle/backend-defines.json" --execute
python3 - <<'PY'
import hashlib, json, os, plistlib
from pathlib import Path
bundle = Path(os.environ['nightowl_bundle'])
options = {
    'method': 'app-store-connect', 'destination': 'export',
    'teamID': 'DAVM2JZ4NN', 'signingStyle': 'manual',
    'signingCertificate': os.environ['nightowl_identity_sha1'],
    'provisioningProfiles': {'com.nightowl.ub.nightOwlUb': os.environ['nightowl_profile_uuid']},
    'manageAppVersionAndBuildNumber': False, 'stripSwiftSymbols': True,
}
with (bundle / 'ExportOptions.plist').open('xb') as stream:
    plistlib.dump(options, stream)
receipt = {
    'source_commit': os.environ['nightowl_commit'], 'version': '1.0.0',
    'build_number': os.environ['nightowl_build_number'],
    'team_id': 'DAVM2JZ4NN', 'bundle_id': 'com.nightowl.ub.nightOwlUb',
    'backend_origin': 'https://' + os.environ['nightowl_backend_ref'] + '.supabase.co',
    'public_defines_sha256': hashlib.sha256((bundle / 'backend-defines.json').read_bytes()).hexdigest(),
    'device_preview': False, 'upload_requested': False,
    'status': 'inputs_prepared_not_build_success',
}
with (bundle / 'input-receipt.json').open('x') as stream:
    json.dump(receipt, stream, indent=2)
    stream.write('\n')
PY

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

The commands above are a prepared recipe, **not an executed or native-validated signed build**. A missing/expired identity or profile must be resolved on the signing host; do not turn on automatic provisioning as a silent fallback. Check the archive and exported IPA for the exact Team, bundle, `1.0.0`/chosen build number, Apple entitlement, selected backend and `DEVICE_PREVIEW=false`, then run archive validation and the device acceptance plan. Retain the archive, symbols, config digest and build result together in ignored/private storage. An input receipt alone does not prove build success.

Upload is a separate step after signed artifact validation and the backend/provider gates. TestFlight processing, device acceptance and App Review are still outstanding. [Flutter's official iOS release guide](https://docs.flutter.dev/deployment/ios) describes version/build flags and archive/export; verify export-option support with `xcodebuild -help` on the actual signing host. [Existing acceptance plan](REVIEW_TEST_PLAN.md) covers the required iPhone/iPad behavior.
