#!/bin/sh
set -eu

# One validated public configuration for Flutter, admin and the extension.
# Private database/Auth/Storage keys must never be exported as Dart defines.
task_root=$(CDPATH= cd -- "$(dirname -- "$0")/../.." && pwd)
cd "$task_root"
for task_option in "$@"; do
  case "$task_option" in
    --no-pub|--no-wasm-dry-run) ;;
    *) printf '%s\n' 'Build options may not override validated public backend settings.' >&2; exit 2 ;;
  esac
done
python3 tools/deployment/build_admin_clients.py \
  --output build/client-bundle --defines-output build/backend-defines.json --execute
flutter build web --release --dart-define=DEVICE_PREVIEW=false \
  --dart-define-from-file=build/backend-defines.json "$@"
# The admin page is deployed with the same server settings as the app.
mkdir -p build/web/admin
cp build/client-bundle/web-admin/index.html build/web/admin/index.html
cp build/client-bundle/web-admin/README.md build/web/admin/README.md
