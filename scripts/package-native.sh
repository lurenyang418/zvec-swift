#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
ARTIFACT="$ROOT/Artifacts/CZvec.xcframework"
ARCHIVE="$ROOT/Artifacts/CZvec.xcframework.zip"

[[ -d "$ARTIFACT" ]] || { echo "run scripts/build-xcframework.sh all first" >&2; exit 1; }
rm -f "$ARCHIVE"
ditto -c -k --sequesterRsrc --keepParent "$ARTIFACT" "$ARCHIVE"
swift package compute-checksum "$ARCHIVE"
