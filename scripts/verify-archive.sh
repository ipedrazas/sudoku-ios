#!/usr/bin/env bash
# Check an .xcarchive for the three things that fail silently.
#
#   ./scripts/verify-archive.sh build/SudokuApp.xcarchive
#
# Each of these produces a perfectly valid archive that uploads, passes review
# and is broken on a device, which is the worst shape a bug can take. Checking
# takes a second; discovering it from a TestFlight build takes a day.
set -euo pipefail

ARCHIVE="${1:?usage: verify-archive.sh <path-to-.xcarchive>}"
APP="${ARCHIVE}/Products/Applications/SudokuApp.app"
GROUP="group.dev.andcake.sudoku"

fail=0
note() { printf '  %s %s\n' "$1" "$2"; }

if [[ ! -d "${APP}" ]]; then
    echo "No app at ${APP} — did the archive succeed?" >&2
    exit 1
fi

echo "Verifying ${ARCHIVE}"

# 1. The App Group entitlement in the *signature*, not merely in the source
#    .entitlements file. If the profile did not carry it, the app still works
#    and every widget is blank forever — the state SnapshotStore degrades to.
if codesign -d --entitlements - "${APP}" 2>/dev/null | grep -q "${GROUP}"; then
    note "ok  " "App Group ${GROUP} is in the signature"
else
    note "FAIL" "App Group ${GROUP} missing from the signature — widgets would be blank on device"
    fail=1
fi

# 2. The extension is embedded. Built-but-not-embedded means the widgets never
#    appear in the gallery at all.
if [[ -d "${APP}/PlugIns/SudokuWidgets.appex" ]]; then
    note "ok  " "SudokuWidgets.appex is embedded"

    if codesign -d --entitlements - "${APP}/PlugIns/SudokuWidgets.appex" 2>/dev/null | grep -q "${GROUP}"; then
        note "ok  " "the widget carries the App Group too"
    else
        note "FAIL" "the widget is missing the App Group — it could not read the snapshot"
        fail=1
    fi
else
    note "FAIL" "SudokuWidgets.appex is not embedded — no widgets would appear"
    fail=1
fi

# 3. The privacy manifests. A missing one is an App Store Connect warning by
#    email rather than a build error, which is easy to not read.
for manifest in "${APP}/PrivacyInfo.xcprivacy" "${APP}/PlugIns/SudokuWidgets.appex/PrivacyInfo.xcprivacy"; do
    if [[ -f "${manifest}" ]]; then
        note "ok  " "privacy manifest present: ${manifest#"${APP}/"}"
    else
        note "warn" "no privacy manifest at ${manifest#"${APP}/"}"
    fi
done

# 4. Signed with a distribution certificate rather than a development one. Both
#    produce an archive; only one can be uploaded.
authority=$(codesign -dvv "${APP}" 2>&1 | awk -F= '/^Authority=/ { print $2; exit }')
case "${authority}" in
    *Distribution*) note "ok  " "signed by: ${authority}" ;;
    "")             note "warn" "could not read the signing authority" ;;
    *)              note "FAIL" "signed by ${authority} — an App Store upload needs Apple Distribution"; fail=1 ;;
esac

echo
if (( fail )); then
    echo "Not uploadable. See plans/releasing.md."
    exit 1
fi
echo "Looks uploadable."
