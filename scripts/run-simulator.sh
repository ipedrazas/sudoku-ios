#!/usr/bin/env bash
# Build, install and launch the app in a simulator.
#
# Every check happens before the simulator is booted: a script that opens a
# simulator and then discovers it has nothing to install leaves you staring at a
# blank home screen wondering what went wrong.
set -euo pipefail

DESTINATION="${1:-platform=iOS Simulator,name=iPhone 16}"
SCHEME="SudokuApp"
PROJECT="SudokuApp/${SCHEME}.xcodeproj"

die() {
    echo "run-simulator: $1" >&2
    exit 1
}

# --- Preconditions -----------------------------------------------------------

command -v xcodebuild >/dev/null 2>&1 ||
    die "xcodebuild not found. Full Xcode is required; Command Line Tools alone cannot build the app."

xcodebuild -version >/dev/null 2>&1 || die "$(
    cat <<'EOF'
xcodebuild is present but not usable. The active developer directory is probably
still the Command Line Tools:

  xcode-select -p

Point it at Xcode with:

  sudo xcode-select -s /Applications/Xcode.app/Contents/Developer
EOF
)"

if ! find SudokuApp/Sources -name '*.swift' -print -quit 2>/dev/null | grep -q .; then
    die "$(
        cat <<'EOF'
there is no app to run yet.

SudokuApp/Sources contains no Swift files, so nothing can be built or installed.
The app shell arrives with Phase 3 (see plans/implementation-plan.md); until
then only the engine exists, and it is exercised with:

  task test:kit
EOF
    )"
fi

if [[ ! -d "${PROJECT}" ]]; then
    die "no Xcode project at ${PROJECT}. It is generated, not committed — run 'task xcodegen'."
fi

DEVICE_NAME="$(sed -n 's/.*name=\([^,]*\).*/\1/p' <<<"${DESTINATION}")"
[[ -n "${DEVICE_NAME}" ]] || die "could not parse a device name out of '${DESTINATION}'"

# --- Locate the built app ----------------------------------------------------
#
# stderr is deliberately captured and shown rather than discarded. Swallowing it
# is what made an earlier version of this script fail silently: with no output to
# parse, the path below collapsed to "/", which is a directory, so the existence
# check passed and simctl was handed the filesystem root.

if ! SETTINGS="$(xcodebuild -project "${PROJECT}" -scheme "${SCHEME}" \
    -destination "${DESTINATION}" -showBuildSettings 2>&1)"; then
    echo "${SETTINGS}" >&2
    die "could not read build settings (see the xcodebuild output above)"
fi

setting() {
    awk -F' = ' -v key="$1" '$1 ~ "^ *"key"$" { print $2; exit }' <<<"${SETTINGS}"
}

BUILD_DIR="$(setting TARGET_BUILD_DIR)"
PRODUCT_NAME="$(setting FULL_PRODUCT_NAME)"
BUNDLE_ID="$(setting PRODUCT_BUNDLE_IDENTIFIER)"

[[ -n "${BUILD_DIR}" ]] || die "xcodebuild did not report TARGET_BUILD_DIR"
[[ -n "${PRODUCT_NAME}" ]] || die "xcodebuild did not report FULL_PRODUCT_NAME"
[[ -n "${BUNDLE_ID}" ]] || die "xcodebuild did not report PRODUCT_BUNDLE_IDENTIFIER"

APP_PATH="${BUILD_DIR}/${PRODUCT_NAME}"
[[ -d "${APP_PATH}" ]] ||
    die "no app bundle at '${APP_PATH}'. Build it first with 'task build:app', or use 'task run' which does."

# --- Boot, install, launch ---------------------------------------------------

echo "Booting ${DEVICE_NAME}…"
xcrun simctl boot "${DEVICE_NAME}" 2>/dev/null || true  # already booted is fine
open -a Simulator
xcrun simctl bootstatus "${DEVICE_NAME}" -b >/dev/null

echo "Installing ${APP_PATH}…"
xcrun simctl install "${DEVICE_NAME}" "${APP_PATH}"

echo "Launching ${BUNDLE_ID}…"
xcrun simctl launch --console-pty "${DEVICE_NAME}" "${BUNDLE_ID}"
