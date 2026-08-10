#!/usr/bin/env bash
# Build, install, launch and screenshot the app.
#
# Usage: screenshot.sh <output.png> [iphone|ipad] [launch-args…]
#
# The UI phases need a fast look-at-it loop. Automated tests confirm behaviour —
# they cannot tell you a board is rendering at half width with clipped digits,
# which is exactly what six green CI runs failed to notice and one screenshot
# caught immediately.
set -euo pipefail

OUTPUT="${1:?usage: screenshot.sh <output.png> [iphone|ipad] [launch-args…]}"
FAMILY="${2:-iphone}"
shift 2 2>/dev/null || shift 1 2>/dev/null || true

SCHEME="SudokuApp"
PROJECT="SudokuApp/${SCHEME}.xcodeproj"
BUNDLE_ID="dev.andcake.sudoku"

DESTINATION="$(./scripts/simulator-destination.sh "${FAMILY}")"
DEVICE="${DESTINATION##*id=}"

xcodebuild build -project "${PROJECT}" -scheme "${SCHEME}" -destination "${DESTINATION}" \
    -quiet CODE_SIGNING_ALLOWED=NO

SETTINGS="$(xcodebuild -project "${PROJECT}" -scheme "${SCHEME}" \
    -destination "${DESTINATION}" -showBuildSettings 2>/dev/null)"
setting() { awk -F' = ' -v key="$1" '$1 ~ "^ *"key"$" { print $2; exit }' <<<"${SETTINGS}"; }
APP_PATH="$(setting TARGET_BUILD_DIR)/$(setting FULL_PRODUCT_NAME)"

xcrun simctl boot "${DEVICE}" 2>/dev/null || true
xcrun simctl bootstatus "${DEVICE}" -b >/dev/null

# Terminate first: relaunching a live app would keep its old state, and a stale
# screenshot is worse than no screenshot.
xcrun simctl terminate "${DEVICE}" "${BUNDLE_ID}" 2>/dev/null || true
xcrun simctl install "${DEVICE}" "${APP_PATH}"
xcrun simctl launch "${DEVICE}" "${BUNDLE_ID}" "$@" >/dev/null

# Give SwiftUI a moment to lay out and any generation to finish.
sleep "${SCREENSHOT_DELAY:-3}"

mkdir -p "$(dirname "${OUTPUT}")"
xcrun simctl io "${DEVICE}" screenshot --type=png "${OUTPUT}" 2>/dev/null
echo "wrote ${OUTPUT}"
