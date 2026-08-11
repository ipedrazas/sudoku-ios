#!/usr/bin/env bash
# Prints an `xcodebuild -destination` value for the newest available simulator
# of the requested family: iphone or ipad.
#
#   simulator-destination.sh iphone
#   DEVICE="iPhone 17 Pro Max" simulator-destination.sh iphone
#
# Simulator device names change with every Xcode release — "iPhone 16" and
# "iPad Pro 11-inch (M4)" were both hardcoded here once, and both stopped
# existing on the CI runner, which failed the build before it compiled a single
# file. Asking the machine what it actually has is the only version of this that
# keeps working, so tests and CI pass no DEVICE and take whatever is newest.
#
# DEVICE exists for the one job that genuinely needs a *particular* model: App
# Store screenshots have to be 6.9" iPhone and 13" iPad, and the default pick is
# neither. It is a substring match, but an exact name always wins — without that
# rule "iPhone 17 Pro" would match "iPhone 17 Pro Max" and hand back a device
# whose screenshots are the wrong size, which is precisely the mistake this is
# here to prevent.
set -euo pipefail

FAMILY="${1:-iphone}"
DEVICE="${DEVICE:-${2:-}}"
case "${FAMILY}" in
    iphone) PREFIX="iPhone" ;;
    ipad) PREFIX="iPad" ;;
    *)
        echo "usage: $(basename "$0") [iphone|ipad]" >&2
        exit 1
        ;;
esac

DEVICES="$(xcrun simctl list devices available --json)" ||
    {
        echo "simulator-destination: could not list simulators; is Xcode installed and selected?" >&2
        exit 1
    }

UDID="$(
    DEVICES_JSON="${DEVICES}" python3 - "${PREFIX}" "${DEVICE}" <<'PY'
import json
import os
import re
import sys

prefix = sys.argv[1]
wanted = sys.argv[2] if len(sys.argv) > 2 else ""
catalog = json.loads(os.environ["DEVICES_JSON"])


def runtime_version(identifier: str) -> tuple:
    """Sort key from a runtime id like com.apple.CoreSimulator.SimRuntime.iOS-26-4."""
    return tuple(int(part) for part in re.findall(r"\d+", identifier.rsplit(".", 1)[-1]))


# Rank 0 beats rank 1: an exact name match always wins over a substring one, so
# asking for "iPhone 17 Pro" cannot return "iPhone 17 Pro Max".
best = None
for runtime, devices in catalog.get("devices", {}).items():
    if "iOS" not in runtime:
        continue
    for device in devices:
        if not device.get("isAvailable"):
            continue
        name = device.get("name", "")
        if not name.startswith(prefix):
            continue
        if wanted:
            if name == wanted:
                rank = 0
            elif wanted.lower() in name.lower():
                rank = 1
            else:
                continue
        else:
            rank = 0
        # Then newest runtime wins; within a runtime the first listed device is
        # the plainest model, which is what a smoke test wants.
        key = (-rank, runtime_version(runtime))
        if best is None or key > best[0]:
            best = (key, device["udid"], name)

print(best[1] if best else "")
print(best[2] if best else "", file=sys.stderr)
PY
)"

[[ -n "${UDID}" ]] || {
    if [[ -n "${DEVICE}" ]]; then
        echo "simulator-destination: no available ${PREFIX} simulator matching '${DEVICE}'." >&2
        echo "  Available:" >&2
        xcrun simctl list devices available | grep "	${PREFIX}" | sed 's/^/    /' >&2
    else
        echo "simulator-destination: no available ${PREFIX} simulator found." >&2
        echo "  Install one from Xcode ▸ Settings ▸ Components." >&2
    fi
    exit 1
}

echo "platform=iOS Simulator,id=${UDID}"
