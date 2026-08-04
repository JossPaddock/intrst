#!/usr/bin/env bash
#
# Runs the full intrst test suite and prints the CI-style report
# (Test <name> passed ✅ / failed ❌, phase breakdown for failures, and a
# Passed X/Y tally). Exits non-zero if any test fails.
#
# This is the exact command the CI pipeline runs on push to main.
#
# Usage:
#   ./scripts/run_tests.sh                 # whole suite
#   ./scripts/run_tests.sh test/foo_test.dart   # a subset
set -euo pipefail

FLUTTER_BIN="$(command -v flutter)" || {
  echo "error: 'flutter' was not found on your PATH." >&2
  exit 127
}

# Resolve symlinks so we can find the Dart SDK bundled next to Flutter. That
# bundled Dart matches the project's SDK constraint, unlike a system-wide dart.
while [ -L "$FLUTTER_BIN" ]; do
  target="$(readlink "$FLUTTER_BIN")"
  case "$target" in
    /*) FLUTTER_BIN="$target" ;;
    *)  FLUTTER_BIN="$(dirname "$FLUTTER_BIN")/$target" ;;
  esac
done

DART="$(dirname "$FLUTTER_BIN")/dart"
[ -x "$DART" ] || DART=dart

# Run from the repo root regardless of where the script was invoked.
cd "$(dirname "$0")/.."

exec "$DART" run tool/test_report.dart "$@"
