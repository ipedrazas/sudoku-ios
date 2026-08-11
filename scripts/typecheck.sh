#!/bin/bash
# Type-check the app and widget sources against the iOS Simulator SDK.
#
# `xcodebuild` cannot run inside a nested sandbox — Xcode's SwiftPM manifest
# evaluation applies its own Seatbelt sandbox, and Seatbelt does not nest — so
# this is how app and widget code is checked without it. It catches every
# compile and strict-concurrency error the real build would; it does not link,
# run, or produce a bundle.
#
#   ./scripts/typecheck.sh
#
# `-disable-sandbox` is required or macro plugin servers die with "produced
# malformed response", which is the same nesting problem one layer down.
set -euo pipefail

cd "$(dirname "$0")/.."

SDK=$(xcrun --sdk iphonesimulator --show-sdk-path)
TARGET=arm64-apple-ios18.0-simulator
BUILD=${TMPDIR:-/tmp}/sudoku-typecheck
mkdir -p "$BUILD"

echo "==> SudokuKit"
swiftc -emit-module -module-name SudokuKit -sdk "$SDK" -target "$TARGET" \
    -swift-version 6 -emit-module-path "$BUILD/SudokuKit.swiftmodule" \
    SudokuKit/Sources/SudokuKit/*.swift

# The app and the widget are separate modules that happen to share Sources/Shared,
# so they are checked separately — exactly as the real build compiles them.
echo "==> SudokuApp"
swiftc -typecheck -disable-sandbox -sdk "$SDK" -target "$TARGET" -swift-version 6 \
    -strict-concurrency=complete -warnings-as-errors -I "$BUILD" \
    $(find SudokuApp/Sources -name '*.swift')

echo "==> SudokuWidgets"
swiftc -typecheck -disable-sandbox -sdk "$SDK" -target "$TARGET" -swift-version 6 \
    -strict-concurrency=complete -warnings-as-errors -I "$BUILD" \
    $(find SudokuWidgets -name '*.swift') \
    $(find SudokuApp/Sources/Shared -name '*.swift')

# The app tests cannot be *run* without xcodebuild, which makes checking that
# they still compile the only feedback available on them at all. `@testable
# import` needs the app built with -enable-testing; Swift Testing needs its
# macro plugin loaded explicitly, since there is no build system here to do it.
echo "==> SudokuAppTests"
DEV=$(xcode-select -p)/Platforms/iPhoneSimulator.platform/Developer
PLUGIN=$(xcode-select -p)/Toolchains/XcodeDefault.xctoolchain/usr/lib/swift/host/plugins/testing/libTestingMacros.dylib

swiftc -emit-module -disable-sandbox -module-name SudokuApp -sdk "$SDK" -target "$TARGET" \
    -swift-version 6 -enable-testing -emit-module-path "$BUILD/SudokuApp.swiftmodule" \
    -I "$BUILD" $(find SudokuApp/Sources -name '*.swift')

swiftc -typecheck -disable-sandbox -sdk "$SDK" -target "$TARGET" -swift-version 6 \
    -strict-concurrency=complete -I "$BUILD" -F "$DEV/Library/Frameworks" \
    -load-plugin-library "$PLUGIN" \
    $(find SudokuApp/Tests/SudokuAppTests -name '*.swift')

echo "==> ok"
