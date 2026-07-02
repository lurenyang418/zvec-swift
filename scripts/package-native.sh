#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
ARTIFACT="$ROOT/Artifacts/CZvec.xcframework"
ARCHIVE="$ROOT/Artifacts/CZvec.xcframework.zip"

[[ -d "$ARTIFACT" ]] || { echo "run scripts/build-xcframework.sh all first" >&2; exit 1; }
rm -f "$ARCHIVE"
DITTONORSRC=1 ditto -c -k --norsrc --noextattr --noqtn --noacl \
  --zlibCompressionLevel 9 --keepParent "$ARTIFACT" "$ARCHIVE"
unzip -tq "$ARCHIVE"
swift package compute-checksum "$ARCHIVE"
