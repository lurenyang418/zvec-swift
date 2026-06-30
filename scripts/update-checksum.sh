#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
ARCHIVE="${1:-$ROOT/Artifacts/CZvec.xcframework.zip}"

[[ -f "$ARCHIVE" ]] || { echo "missing archive: $ARCHIVE" >&2; exit 1; }
checksum="$(swift package compute-checksum "$ARCHIVE")"

CHECKSUM="$checksum" perl -0pi -e \
  's/checksum: "[0-9a-f]{64}"/checksum: "$ENV{CHECKSUM}"/' \
  "$ROOT/Package.swift"

grep -q "checksum: \"$checksum\"" "$ROOT/Package.swift"
echo "$checksum"
