#!/usr/bin/env bash
set -euo pipefail
TASK_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
CAPTURE_TEST="$TASK_ROOT/test/_ugc_review_capture_test.dart"
if [[ -e "$CAPTURE_TEST" ]]; then
  echo "Capture test already exists: $CAPTURE_TEST" >&2
  exit 1
fi
trap 'rm -f "$CAPTURE_TEST"' EXIT
cp "$TASK_ROOT/tools/visual_review/ugc_review_capture.dart.txt" "$CAPTURE_TEST"
cd "$TASK_ROOT"
"${FLUTTER_BIN:-flutter}" test --no-pub --concurrency=1 "$CAPTURE_TEST" "$@"
