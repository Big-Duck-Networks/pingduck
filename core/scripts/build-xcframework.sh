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
min_ios=13.0

build() {  # <name> <sdk> <archs>
  cmake -S "$core" -B "$out/$1" -G Xcode \
    -DCMAKE_SYSTEM_NAME=iOS \
    -DCMAKE_OSX_SYSROOT="$2" \
    -DCMAKE_OSX_ARCHITECTURES="$3" \
    -DCMAKE_OSX_DEPLOYMENT_TARGET=$min_ios \
    -DPINGDUCK_BUILD_SHARED=OFF -DPINGDUCK_BUILD_CLI=OFF -DPINGDUCK_BUILD_TESTS=OFF -DPINGDUCK_PCAP=OFF
  cmake --build "$out/$1" --config Release --target pingduck -- CODE_SIGNING_ALLOWED=NO
}

build device iphoneos arm64
build simulator iphonesimulator "arm64;x86_64"

rm -rf "$out/PingDuckCore.xcframework"
xcodebuild -create-xcframework \
  -library "$(find "$out/device" -name libpingduck.a -path '*Release*' | head -1)" -headers "$core/include" \
  -library "$(find "$out/simulator" -name libpingduck.a -path '*Release*' | head -1)" -headers "$core/include" \
  -output "$out/PingDuckCore.xcframework"
echo "built $out/PingDuckCore.xcframework"
