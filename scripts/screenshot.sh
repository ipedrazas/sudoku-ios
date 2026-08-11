#!/usr/bin/env bash
# Build, install, launch and screenshot the app.
#
# Usage: screenshot.sh <output.png> [iphone|ipad] [launch-args…]
#
# The UI phases need a fast look-at-it loop. Automated tests confirm behaviour —
# they cannot tell you a board is rendering at half width with clipped digits,
# which is exactly what six green CI runs failed to notice and one screenshot
# caught immediately.
#
# Environment:
#   SCREENSHOT_DELAY    seconds to wait before capturing (default 3)
#   CONTENT_SIZE        a Dynamic Type category, e.g.
#                       accessibility-extra-extra-extra-large
#   APPEARANCE          light | dark
#   DEVICE              a simulator model name, passed through to
#                       simulator-destination.sh
#
# DEVICE matters for App Store screenshots and almost nothing else. Without it
# the newest plain model wins — iPhone 17 Pro, which captures at 1206x2622 — and
# App Store Connect wants 6.9" iPhone and 13" iPad:
#
#   DEVICE="iPhone 17 Pro Max"  ->  1320x2868   (6.9", required)
#   DEVICE="iPad Pro 13"        ->  2064x2752   (13", required for a universal app)
#
# Both sizes verified against those simulators.
#
# CONTENT_SIZE is how Phase 9's P9-3 was actually checked, and it is worth
# re-running whenever a layout changes: at the largest category the control bar
# broke "Undo" across two lines into the icon above it, and the win card
# squeezed its buttons into "Ne w…" and "Re- view…". Neither is visible at any
# other size, and no test would have caught either.
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

# Applied before launch, so the app reads them at its first layout rather than
# re-laying out mid-capture.
if [[ -n "${CONTENT_SIZE:-}" ]]; then
    xcrun simctl ui "${DEVICE}" content_size "${CONTENT_SIZE}" >/dev/null
fi
if [[ -n "${APPEARANCE:-}" ]]; then
    xcrun simctl ui "${DEVICE}" appearance "${APPEARANCE}" >/dev/null
fi

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
