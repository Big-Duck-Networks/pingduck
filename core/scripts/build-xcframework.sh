#!/usr/bin/env bash
# Builds pingduck-core as a static xcframework for iOS devices and simulators.
#
#   core/scripts/build-xcframework.sh [out-dir]   (default: core/build-ios)
#
# Needs macOS with Xcode. The result, PingDuckCore.xcframework, is what the
# Flutter plugin's podspec vendors in Phase 2.
set -euo pipefail

core="$(cd "$(dirname "$0")/.." && pwd)"
out="${1:-$core/build-ios}"
mkdir -p "$out" && out="$(cd "$out" && pwd)"  # absolute: CMake and xcodebuild run elsewhere
min_ios=13.0

build() {  # <name> <sdk> <archs>
  cmake -S "$core" -B "$out/$1" -G Xcode \
    -DCMAKE_SYSTEM_NAME=iOS \
    -DCMAKE_OSX_SYSROOT="$2" \
    -DCMAKE_OSX_ARCHITECTURES="$3" \
    -DCMAKE_OSX_DEPLOYMENT_TARGET=$min_ios \
    -DPINGDUCK_BUILD_SHARED=OFF -DPINGDUCK_BUILD_CLI=OFF -DPINGDUCK_BUILD_TESTS=OFF -DPINGDUCK_PCAP=OFF
  # The Xcode generator does not emit libpingduck.a for a static library whose
  # only content is the linked object library, but it does archive the object
  # library itself, and that archive holds every core source. Ship it.
  cmake --build "$out/$1" --config Release --target pingduck_objects -- CODE_SIGNING_ALLOWED=NO
  local archive
  archive="$(find "$out/$1/build/pingduck_objects.build" -maxdepth 2 -name libpingduck_objects.a -path '*Release-*' | head -1)"
  [ -n "$archive" ] || { echo "no libpingduck_objects.a under $out/$1" >&2; exit 1; }
  # Fail loudly rather than package an empty archive.
  nm -g "$archive" | grep -q ' T _pd_scan$' || { echo "$archive lacks pd_scan" >&2; exit 1; }
  mkdir -p "$out/$1/lib"
  cp "$archive" "$out/$1/lib/libpingduck.a"
}

build device iphoneos arm64
build simulator iphonesimulator "arm64;x86_64"

rm -rf "$out/PingDuckCore.xcframework"
xcodebuild -create-xcframework \
  -library "$out/device/lib/libpingduck.a" -headers "$core/include" \
  -library "$out/simulator/lib/libpingduck.a" -headers "$core/include" \
  -output "$out/PingDuckCore.xcframework"
echo "built $out/PingDuckCore.xcframework"
