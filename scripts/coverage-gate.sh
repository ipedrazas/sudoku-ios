#!/usr/bin/env bash
# Fail the build if SudokuKit line coverage drops below the given threshold.
#
# SudokuKit is pure logic with no I/O, so anything less than near-total coverage
# means untested branches in the rater — which is exactly where a bug would be
# both silent and expensive.
set -euo pipefail

THRESHOLD="${1:-90}"
# The report path is passed in by the Taskfile, which knows the toolchain flags
# `swift test --show-codecov-path` needs. Falling back to discovery keeps the
# script usable on its own.
REPORT="${2:-}"

if [[ -z "${REPORT}" ]]; then
    REPORT="$(swift test --disable-sandbox --show-codecov-path 2>/dev/null | tail -1 || true)"
fi
if [[ -z "${REPORT}" || ! -f "${REPORT}" ]]; then
    echo "coverage-gate: no coverage report at '${REPORT}'" >&2
    echo "  run 'task test:kit:cover', which builds it first" >&2
    exit 1
fi

# The codecov JSON reports per-file line coverage; we want SudokuKit sources only.
PERCENT="$(
    python3 - "${REPORT}" <<'PY'
import json, sys

with open(sys.argv[1]) as handle:
    report = json.load(handle)

covered = total = 0
for entry in report["data"][0]["files"]:
    if "/SudokuKit/Sources/" not in entry["filename"]:
        continue
    summary = entry["summary"]["lines"]
    covered += summary["covered"]
    total += summary["count"]

print(f"{(100.0 * covered / total) if total else 0.0:.2f}")
PY
)"

echo "SudokuKit line coverage: ${PERCENT}% (threshold ${THRESHOLD}%)"
awk -v pct="${PERCENT}" -v threshold="${THRESHOLD}" 'BEGIN { exit (pct + 0 >= threshold + 0) ? 0 : 1 }' || {
    echo "coverage-gate: ${PERCENT}% is below the ${THRESHOLD}% threshold" >&2
    exit 1
}
