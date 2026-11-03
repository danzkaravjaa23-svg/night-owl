#!/bin/sh
set -eu

task_root=$(CDPATH= cd -- "$(dirname -- "$0")/../.." && pwd)
cd "$task_root"
for task_option in "$@"; do
  case "$task_option" in
    --no-pub) ;;
    *) printf '%s\n' 'Only --no-pub is allowed. Signing, upload and backend overrides are separate steps.' >&2; exit 2 ;;
  esac
done
python3 tools/deployment/ios_preflight.py
python3 tools/deployment/build_admin_clients.py \
  --output build/client-bundle --defines-output build/backend-defines.json --execute
flutter build ios --release --no-codesign --dart-define=DEVICE_PREVIEW=false \
  --dart-define-from-file=build/backend-defines.json "$@"
printf '%s\n' 'Unsigned Runner.app built. Not an IPA or App Store upload; signing/device/review checks remain.'
