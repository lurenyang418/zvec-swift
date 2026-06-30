#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
source "$ROOT/scripts/native-version.env"

MODE="${1:-macos}"
BUILD_ROOT="$ROOT/.build/native"
SOURCE_ROOT="$BUILD_ROOT/zvec"
HOST_ROOT="$BUILD_ROOT/host"
OUTPUT_ROOT="$BUILD_ROOT/frameworks"
ARTIFACT="$ROOT/Artifacts/CZvec.xcframework"
JOBS="$(sysctl -n hw.ncpu)"

case "$MODE" in
  macos) PLATFORMS=(macos-arm64) ;;
  all) PLATFORMS=(macos-arm64 ios-arm64 ios-arm64-simulator) ;;
  *) echo "usage: $0 [macos|all]" >&2; exit 2 ;;
esac

mkdir -p "$BUILD_ROOT" "$OUTPUT_ROOT" "$ROOT/Artifacts"

if [[ ! -d "$SOURCE_ROOT/.git" ]]; then
  git clone --recursive "$ZVEC_REPOSITORY" "$SOURCE_ROOT"
fi
git -C "$SOURCE_ROOT" fetch --tags origin
git -C "$SOURCE_ROOT" checkout --detach "$ZVEC_COMMIT"
git -C "$SOURCE_ROOT" submodule update --init --recursive

if [[ ! -x "$HOST_ROOT/bin/protoc" ]]; then
  cmake -S "$SOURCE_ROOT" -B "$HOST_ROOT" \
    -DCMAKE_BUILD_TYPE=Release \
    -DCMAKE_POLICY_VERSION_MINIMUM=3.5 \
    -DBUILD_C_BINDINGS=OFF \
    -DBUILD_PYTHON_BINDINGS=OFF \
    -DBUILD_TOOLS=OFF
  cmake --build "$HOST_ROOT" --target protoc --parallel "$JOBS"
fi

make_framework() {
  local platform="$1"
  local sdk arch deployment cmake_system plist_platform plist_variant
  case "$platform" in
    macos-arm64)
      sdk=macosx; arch=arm64; deployment=13.0; cmake_system=""
      plist_platform=MacOSX; plist_variant=""
      ;;
    ios-arm64)
      sdk=iphoneos; arch=arm64; deployment=16.0; cmake_system=iOS
      plist_platform=iPhoneOS; plist_variant=""
      ;;
    ios-arm64-simulator)
      sdk=iphonesimulator; arch=arm64; deployment=16.0; cmake_system=iOS
      plist_platform=iPhoneSimulator; plist_variant=simulator
      ;;
  esac

  local build="$BUILD_ROOT/$platform"
  local framework="$OUTPUT_ROOT/$platform/CZvec.framework"
  local sdk_path
  sdk_path="$(xcrun --sdk "$sdk" --show-sdk-path)"

  cmake_args=(
    -S "$SOURCE_ROOT" -B "$build"
    -DCMAKE_OSX_DEPLOYMENT_TARGET="$deployment" \
    -DCMAKE_OSX_ARCHITECTURES="$arch" \
    -DCMAKE_OSX_SYSROOT="$sdk_path" \
    -DCMAKE_BUILD_TYPE=Release \
    -DCMAKE_POLICY_VERSION_MINIMUM=3.5 \
    -DBUILD_C_BINDINGS=ON \
    -DBUILD_PYTHON_BINDINGS=OFF \
    -DBUILD_TOOLS=OFF \
    -DGLOBAL_CC_PROTOBUF_PROTOC="$HOST_ROOT/bin/protoc" \
    -DIOS="$([[ "$cmake_system" == iOS ]] && echo ON || echo OFF)"
  )
  if [[ -n "$cmake_system" ]]; then
    cmake_args+=( -DCMAKE_SYSTEM_NAME="$cmake_system" )
  fi
  MACOSX_DEPLOYMENT_TARGET="$deployment" cmake "${cmake_args[@]}"
  MACOSX_DEPLOYMENT_TARGET="$deployment" \
    cmake --build "$build" --target zvec_c_api --parallel "$JOBS"

  local dylib
  dylib="$(find "$build" -name 'libzvec_c_api.dylib' -type f -print -quit)"
  [[ -n "$dylib" ]] || { echo "zvec C API library not found" >&2; exit 1; }

  rm -rf "$framework"
  mkdir -p "$framework/Headers" "$framework/Modules"
  cp "$dylib" "$framework/CZvec"
  cp "$build/src/generated/zvec/c_api.h" "$framework/Headers/c_api.h"
  install_name_tool -id @rpath/CZvec.framework/CZvec "$framework/CZvec"

  printf '%s\n' 'framework module CZvec {' \
    '  umbrella header "c_api.h"' \
    '  export *' \
    '  module * { export * }' \
    '}' > "$framework/Modules/module.modulemap"

  cat > "$framework/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "https://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
<key>CFBundleExecutable</key><string>CZvec</string>
<key>CFBundleIdentifier</key><string>dev.zvec.swift.native</string>
<key>CFBundleInfoDictionaryVersion</key><string>6.0</string>
<key>CFBundleName</key><string>CZvec</string>
<key>CFBundlePackageType</key><string>FMWK</string>
<key>CFBundleShortVersionString</key><string>$ZVEC_VERSION</string>
<key>CFBundleVersion</key><string>$ZVEC_VERSION</string>
<key>MinimumOSVersion</key><string>$deployment</string>
<key>CFBundleSupportedPlatforms</key><array><string>$plist_platform</string></array>
PLIST
  if [[ -n "$plist_variant" ]]; then
    echo "<key>DTPlatformVariant</key><string>$plist_variant</string>" >> "$framework/Info.plist"
  fi
  echo '</dict></plist>' >> "$framework/Info.plist"
}

for platform in "${PLATFORMS[@]}"; do
  make_framework "$platform"
done

rm -rf "$ARTIFACT"
args=()
for platform in "${PLATFORMS[@]}"; do
  args+=( -framework "$OUTPUT_ROOT/$platform/CZvec.framework" )
done
xcodebuild -create-xcframework "${args[@]}" -output "$ARTIFACT"

echo "Built $ARTIFACT"
