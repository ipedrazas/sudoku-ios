#!/usr/bin/env bash
# Check a build for the things that fail silently.
#
#   ./scripts/verify-archive.sh build/SudokuApp.xcarchive
#   ./scripts/verify-archive.sh build/export/SudokuApp.ipa
#
# Each of these produces a perfectly valid build that uploads, passes review and
# is broken on a device, which is the worst shape a bug can take. Checking takes
# a second; discovering it from a TestFlight build takes a day.
#
# Takes either artefact, because one requirement differs between them. **An
# archive is signed for development, and that is correct.** `xcodebuild archive`
# with automatic signing embeds an "iOS Team Provisioning Profile" with
# get-task-allow and a device list; `xcodebuild -exportArchive` then re-signs
# the payload with the distribution certificate and an App Store profile. The
# archive is an intermediate. So the distribution requirement is enforced on the
# .ipa and merely reported on the archive — an earlier version of this script
# failed the archive for it and blocked a build that was fine.
set -euo pipefail

TARGET="${1:?usage: verify-archive.sh <path-to-.xcarchive|.ipa>}"
GROUP="group.dev.andcake.sudoku"

WORK=""
# `if`, not `[[ … ]] && rm`. With no temp directory to remove, the `&&` short
# circuits, cleanup returns 1, and an EXIT trap whose last command fails sets
# the script's exit status — so every check would pass, the summary would say so,
# and the script would still exit 1.
cleanup() {
    if [[ -n "${WORK}" ]]; then rm -rf "${WORK}"; fi
}
trap cleanup EXIT

case "${TARGET}" in
    *.ipa)
        # An .ipa is a zip with the app under Payload/.
        KIND="ipa"
        WORK="$(mktemp -d)"
        unzip -q "${TARGET}" -d "${WORK}" || {
            echo "Could not unzip ${TARGET}" >&2
            exit 1
        }
        APP="$(find "${WORK}/Payload" -maxdepth 1 -name '*.app' -print -quit)"
        ;;
    *)
        KIND="archive"
        APP="${TARGET}/Products/Applications/SudokuApp.app"
        ;;
esac

fail=0
note() { printf '  %s %s\n' "$1" "$2"; }

# Read a bundle's signature once, into a variable.
#
# Never `codesign … | grep -q` or `codesign … | awk '…; exit'`. Those consumers
# close the pipe on the first match, `codesign` takes SIGPIPE on its next write,
# and `set -o pipefail` reports the pipeline as having failed with 141 — after
# every check has already printed "ok". A real signature has three Authority
# lines and more output after them, so it triggers this reliably; an ad-hoc
# signature has none, reads to EOF, and does not. That difference is why this
# script passed every test it was given and then failed on the first real
# archive it ever saw.
#
# Here-strings below have no upstream process to kill, so early-exiting
# consumers are safe against them.
entitlements_of() { codesign -d --entitlements - "$1" 2>/dev/null || true; }
signature_of() { codesign -dvv "$1" 2>&1 || true; }

if [[ -z "${APP}" || ! -d "${APP}" ]]; then
    echo "No app inside ${TARGET} — did the build succeed?" >&2
    exit 1
fi

echo "Verifying ${TARGET}"

# 1. The App Group entitlement in the *signature*, not merely in the source
#    .entitlements file. If the profile did not carry it, the app still works
#    and every widget is blank forever — the state SnapshotStore degrades to.
if grep -q "${GROUP}" <<<"$(entitlements_of "${APP}")"; then
    note "ok  " "App Group ${GROUP} is in the signature"
else
    note "FAIL" "App Group ${GROUP} missing from the signature — widgets would be blank on device"
    fail=1
fi

# 2. The extension is embedded. Built-but-not-embedded means the widgets never
#    appear in the gallery at all.
if [[ -d "${APP}/PlugIns/SudokuWidgets.appex" ]]; then
    note "ok  " "SudokuWidgets.appex is embedded"

    if grep -q "${GROUP}" <<<"$(entitlements_of "${APP}/PlugIns/SudokuWidgets.appex")"; then
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

# 4. Signed for distribution. Required of the .ipa, which is what gets uploaded;
#    reported for the archive, which is re-signed on the way out and is
#    *expected* to be development-signed until then.
authority=$(awk -F= '/^Authority=/ { print $2; exit }' <<<"$(signature_of "${APP}")")
case "${KIND}:${authority}" in
    *:*Distribution*)
        note "ok  " "signed by: ${authority}"
        ;;
    archive:"")
        note "warn" "could not read the signing authority"
        ;;
    archive:*)
        note "ok  " "signed by ${authority} — normal for an archive; export re-signs it"
        ;;
    ipa:"")
        note "FAIL" "could not read the signing authority of the .ipa"
        fail=1
        ;;
    ipa:*)
        note "FAIL" "signed by ${authority} — an App Store upload needs Apple Distribution"
        fail=1
        ;;
esac

echo
if (( fail )); then
    echo "Not uploadable. See plans/releasing.md."
    exit 1
fi
if [[ "${KIND}" == "archive" ]]; then
    echo "Archive looks good. Export it to produce an uploadable .ipa."
else
    echo "Looks uploadable."
fi
