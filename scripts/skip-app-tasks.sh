#!/usr/bin/env bash
# Exits 0 when the app-related tasks should be SKIPPED, non-zero when they
# should run. Used as a Taskfile `status:` guard, where a zero exit means
# "already up to date, do nothing".
#
# Two conditions have to hold before the app can be built, and confusing them
# caused a real breakage: installing Xcode made `task test` start failing,
# because the guard only asked whether Xcode existed. XcodeGen refuses a spec
# whose source directories are missing, so an app target with no sources cannot
# be generated no matter how much Xcode is installed.
#
# This lives in a script rather than inline in Taskfile.yml because Task parses
# `status:` commands with its own shell, which does not evaluate a `! a || ! b`
# chain the way bash does — the inline version silently reported "not up to
# date" and ran anyway.
set -uo pipefail

# No XcodeGen: the project is generated rather than committed, so without it
# there is nothing to build from.
if ! command -v xcodegen >/dev/null 2>&1; then
    exit 0
fi

# No usable Xcode: nothing to build with.
if ! xcodebuild -version >/dev/null 2>&1; then
    exit 0
fi

# No app sources yet: nothing to build. The app shell arrives in Phase 3.
if ! find SudokuApp/Sources -name '*.swift' -print -quit 2>/dev/null | grep -q .; then
    exit 0
fi

# Both present — the app tasks should run.
exit 1
