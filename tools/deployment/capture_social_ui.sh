#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/../.."
capture_test=test/_social_capture_review_test.dart
if [[ -e "$capture_test" ]]; then
  echo "Refusing to overwrite an existing capture test: $capture_test" >&2
  exit 1
fi
trap 'rm -f "$capture_test"' EXIT
cp tools/deployment/visual/social_capture_test.dart.txt "$capture_test"
"${FLUTTER:-flutter}" test --no-pub --dart-define=CAPTURE_SOCIAL_UI=true "$capture_test" "$@"
