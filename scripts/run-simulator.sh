#!/usr/bin/env bash
# Boot a simulator, install the freshly built app and launch it.
# Requires full Xcode; `task run` builds first.
set -euo pipefail

DESTINATION="${1:-platform=iOS Simulator,name=iPhone 16}"
BUNDLE_ID="dev.andcake.sudoku"
SCHEME="SudokuApp"

DEVICE_NAME="$(sed -n 's/.*name=\([^,]*\).*/\1/p' <<<"${DESTINATION}")"
if [[ -z "${DEVICE_NAME}" ]]; then
    echo "run-simulator: could not parse a device name out of '${DESTINATION}'" >&2
    exit 1
fi

echo "Booting ${DEVICE_NAME}…"
xcrun simctl boot "${DEVICE_NAME}" 2>/dev/null || true
open -a Simulator

APP_PATH="$(
    xcodebuild -project "SudokuApp/${SCHEME}.xcodeproj" -scheme "${SCHEME}" \
        -destination "${DESTINATION}" -showBuildSettings 2>/dev/null |
        awk -F' = ' '/ TARGET_BUILD_DIR/ { dir = $2 } / FULL_PRODUCT_NAME/ { name = $2 } END { print dir "/" name }'
)"

if [[ ! -d "${APP_PATH}" ]]; then
    echo "run-simulator: no app bundle at '${APP_PATH}' — run 'task build:app' first" >&2
    exit 1
fi

echo "Installing ${APP_PATH}…"
xcrun simctl install "${DEVICE_NAME}" "${APP_PATH}"
xcrun simctl launch --console-pty "${DEVICE_NAME}" "${BUNDLE_ID}"
