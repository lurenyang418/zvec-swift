#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
ARCHIVE="${1:-$ROOT/Artifacts/CZvec.xcframework.zip}"
EXTRACT_ROOT="$(mktemp -d "${TMPDIR:-/tmp}/zvec-native-archive.XXXXXX")"

cleanup() {
  rm -rf "$EXTRACT_ROOT"
}
trap cleanup EXIT

[[ -f "$ARCHIVE" ]] || { echo "missing archive: $ARCHIVE" >&2; exit 1; }
unzip -tq "$ARCHIVE"
ditto -x -k "$ARCHIVE" "$EXTRACT_ROOT"
"$ROOT/scripts/verify-xcframework.sh" "$EXTRACT_ROOT/CZvec.xcframework"

echo "Verified archive $ARCHIVE"
