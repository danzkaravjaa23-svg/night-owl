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
# Flutter generates a retirement worker that navigates every open tab. Use our
# no-navigation version so a deployment cannot discard an in-progress draft.
cp web/flutter_service_worker.js build/web/flutter_service_worker.js
# The admin page is deployed with the same server settings as the app.
mkdir -p build/web/admin
cp build/client-bundle/web-admin/index.html build/web/admin/index.html
cp build/client-bundle/web-admin/README.md build/web/admin/README.md
# Finder metadata is not a public web asset.
find build/web -type f -name '.DS_Store' -delete
# Public release identity lets deployment checks distinguish a fresh build from
# an older cached app shell without exposing build credentials or local paths.
python3 - <<'PY'
import datetime
import hashlib
import json
from pathlib import Path
import subprocess

root = Path('build/web')
commit = subprocess.check_output(['git', 'rev-parse', 'HEAD'], text=True).strip()
(root / 'release.json').write_text(json.dumps({
    'commit': commit,
    'built_at': datetime.datetime.now(datetime.timezone.utc).isoformat(),
    'main_dart_sha256': hashlib.sha256((root / 'main.dart.js').read_bytes()).hexdigest(),
}, indent=2) + '\n')
PY
