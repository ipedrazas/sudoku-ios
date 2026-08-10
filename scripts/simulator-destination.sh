#!/usr/bin/env bash
# Prints an `xcodebuild -destination` value for the newest available simulator
# of the requested family: iphone or ipad.
#
# Simulator device names change with every Xcode release — "iPhone 16" and
# "iPad Pro 11-inch (M4)" were both hardcoded here once, and both stopped
# existing on the CI runner, which failed the build before it compiled a single
# file. Asking the machine what it actually has is the only version of this that
# keeps working.
set -euo pipefail

FAMILY="${1:-iphone}"
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
    DEVICES_JSON="${DEVICES}" python3 - "${PREFIX}" <<'PY'
import json
import os
import re
import sys

prefix = sys.argv[1]
catalog = json.loads(os.environ["DEVICES_JSON"])


def runtime_version(identifier: str) -> tuple:
    """Sort key from a runtime id like com.apple.CoreSimulator.SimRuntime.iOS-26-4."""
    return tuple(int(part) for part in re.findall(r"\d+", identifier.rsplit(".", 1)[-1]))


best = None
for runtime, devices in catalog.get("devices", {}).items():
    if "iOS" not in runtime:
        continue
    for device in devices:
        if not device.get("isAvailable"):
            continue
        if not device.get("name", "").startswith(prefix):
            continue
        # Newest runtime wins; within a runtime the first listed device is the
        # plainest model, which is what a smoke test wants.
        key = runtime_version(runtime)
        if best is None or key > best[0]:
            best = (key, device["udid"])

print(best[1] if best else "")
PY
)"

[[ -n "${UDID}" ]] || {
    echo "simulator-destination: no available ${PREFIX} simulator found." >&2
    echo "  Install one from Xcode ▸ Settings ▸ Components." >&2
    exit 1
}

echo "platform=iOS Simulator,id=${UDID}"
