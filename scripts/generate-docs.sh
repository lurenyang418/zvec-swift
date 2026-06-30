#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
BUILD_ROOT="$ROOT/.build"
SYMBOLS="$BUILD_ROOT/docc-symbols"
MODULE_CACHE="$BUILD_ROOT/docc-module-cache"
OUTPUT="$BUILD_ROOT/docc"
SDK="$(xcrun --sdk macosx --show-sdk-path)"

swift build --package-path "$ROOT" --target Zvec
rm -rf "$SYMBOLS" "$MODULE_CACHE" "$OUTPUT"
mkdir -p "$SYMBOLS" "$MODULE_CACHE"

xcrun swift-symbolgraph-extract \
  -module-name Zvec \
  -target arm64-apple-macosx13.0 \
  -sdk "$SDK" \
  -module-cache-path "$MODULE_CACHE" \
  -F "$ROOT/Artifacts/CZvec.xcframework/macos-arm64" \
  -I "$BUILD_ROOT/arm64-apple-macosx/debug/Modules" \
  -minimum-access-level public \
  -skip-inherited-docs \
  -emit-extension-block-symbols \
  -output-dir "$SYMBOLS"

xcrun docc convert "$ROOT/Sources/Zvec/Zvec.docc" \
  --additional-symbol-graph-dir "$SYMBOLS" \
  --output-path "$OUTPUT" \
  --fallback-display-name Zvec \
  --fallback-bundle-identifier dev.zvec.swift \
  --fallback-bundle-version 0.5.1 \
  --warnings-as-errors

echo "Generated $OUTPUT"
