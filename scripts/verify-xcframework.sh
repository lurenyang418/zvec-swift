#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
ARTIFACT="${1:-$ROOT/Artifacts/CZvec.xcframework}"

for slice in macos-arm64 ios-arm64 ios-arm64-simulator; do
  case "$slice" in
    macos-arm64) expected_platform=MACOS; expected_minimum=13.0 ;;
    ios-arm64) expected_platform=IOS; expected_minimum=16.0 ;;
    ios-arm64-simulator) expected_platform=IOSSIMULATOR; expected_minimum=16.0 ;;
  esac
  framework="$ARTIFACT/$slice/CZvec.framework"
  binary="$framework/CZvec"
  [[ -f "$binary" ]] || { echo "missing $slice binary" >&2; exit 1; }
  [[ -f "$framework/Headers/zvec/c_api.h" ]] || { echo "missing C API header in $slice" >&2; exit 1; }
  [[ -f "$framework/Headers/zvec/zvec_swift_shim.h" ]] || { echo "missing shim header in $slice" >&2; exit 1; }
  [[ -f "$framework/Modules/module.modulemap" ]] || { echo "missing module map in $slice" >&2; exit 1; }

  file "$binary" | grep -q 'arm64'
  build_info="$(xcrun vtool -show-build "$binary")"
  grep -q "platform $expected_platform" <<<"$build_info"
  grep -q "minos $expected_minimum" <<<"$build_info"
  otool -D "$binary" | grep -q '@rpath/CZvec.framework/CZvec'

  symbols="$(nm -gU "$binary")"
  for symbol in \
    _zvec_swift_doc_array_count \
    _zvec_swift_doc_binary_array_element_copy \
    _zvec_swift_collection_group_by_query \
    _zvec_swift_group_results_free; do
    grep -q "$symbol" <<<"$symbols"
  done
done

echo "Verified $ARTIFACT"
