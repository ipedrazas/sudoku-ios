#!/usr/bin/env python3
"""Check that every localizable string in the app and the widget is translated.

The compiler is the authority on what needs translating, not a regex over the
sources. `-emit-localized-strings` is the same extraction Xcode runs to fill a
String Catalogue: it knows which parameters are `LocalizedStringKey` and which
are plain `String`, so it sees exactly the strings that will actually be looked
up at run time — and, just as usefully, it does *not* see the ones that will
not. A literal that quietly resolved to a non-localising overload shows up here
as a key defined in `Localizable.strings` and used by nothing, which is how the
board's row, column and box rotors were found to have never been translatable
at all.

    ./scripts/check-localization.py

Exits non-zero when a key the compiler emits has no entry in a language, or
when a language defines a key nothing uses.

A key absent from the *development* language is not an error: the key is the
English source text, so a missing entry returns itself. That is deliberate for
phrases whose English does not change with the count ("3 day streak") and for
the `^[…](inflect: true)` markup, which has to reach SwiftUI intact.
"""
from __future__ import annotations

import json
import os
import pathlib
import shutil
import subprocess
import sys
import tempfile

ROOT = pathlib.Path(__file__).resolve().parent.parent
DEVELOPMENT_LANGUAGE = "en"

# (label, source directories, directory holding the .lproj folders)
TARGETS = [
    ("SudokuApp", ["SudokuApp/Sources"], "SudokuApp/Resources"),
    ("SudokuWidgets", ["SudokuWidgets", "SudokuApp/Sources/Shared"], "SudokuWidgets"),
]


def sdk() -> str:
    return subprocess.run(
        ["xcrun", "--sdk", "iphonesimulator", "--show-sdk-path"],
        capture_output=True, text=True, check=True,
    ).stdout.strip()


def build_kit_module(build: pathlib.Path) -> None:
    """SudokuKit has to exist as a module before anything importing it compiles."""
    accessor = build / "resource_bundle_accessor.swift"
    accessor.write_text(
        "import Foundation\n\nextension Bundle {\n    static let module = Bundle.main\n}\n"
    )
    sources = sorted((ROOT / "SudokuKit/Sources/SudokuKit").glob("*.swift"))
    run([
        "swiftc", "-emit-module", "-disable-sandbox", "-module-name", "SudokuKit",
        "-sdk", sdk(), "-target", TARGET, "-swift-version", "6",
        "-emit-module-path", str(build / "SudokuKit.swiftmodule"),
        *map(str, sources), str(accessor),
    ])


def run(command: list[str]) -> None:
    result = subprocess.run(command, capture_output=True, text=True)
    if result.returncode != 0:
        sys.stderr.write(result.stderr)
        raise SystemExit(f"compile failed: {' '.join(command[:3])}…")


TARGET = "arm64-apple-ios18.0-simulator"


def compiler_keys(sources: list[str], build: pathlib.Path) -> set[str]:
    """Every string the compiler will look up at run time."""
    out = build / "stringsdata"
    shutil.rmtree(out, ignore_errors=True)
    out.mkdir(parents=True)

    files: list[str] = []
    for directory in sources:
        files += [str(p) for p in sorted((ROOT / directory).rglob("*.swift"))]

    run([
        "swiftc", "-c", "-disable-sandbox", "-sdk", sdk(), "-target", TARGET,
        "-swift-version", "6", "-wmo", "-o", os.devnull, "-I", str(build),
        "-Xfrontend", "-emit-localized-strings",
        "-Xfrontend", "-emit-localized-strings-path", "-Xfrontend", str(out),
        *files,
    ])

    keys: set[str] = set()
    for path in out.glob("*.stringsdata"):
        for table in json.loads(path.read_text()).get("tables", {}).values():
            for entry in table:
                if key := entry.get("key"):
                    keys.add(key)
    return keys


def defined_keys(resources: pathlib.Path, language: str) -> set[str]:
    keys: set[str] = set()
    for name in ("Localizable.strings", "Localizable.stringsdict"):
        path = resources / f"{language}.lproj" / name
        if not path.exists():
            continue
        plist = subprocess.run(
            ["plutil", "-convert", "json", "-o", "-", str(path)],
            capture_output=True, text=True,
        )
        if plist.returncode != 0:
            raise SystemExit(f"{path} is not valid: {plist.stderr.strip()}")
        keys |= set(json.loads(plist.stdout))
    return keys


def languages(resources: pathlib.Path) -> list[str]:
    return sorted(p.stem for p in resources.glob("*.lproj"))


def main() -> int:
    failures = 0
    with tempfile.TemporaryDirectory() as directory:
        build = pathlib.Path(directory)
        build_kit_module(build)

        for label, sources, resource_directory in TARGETS:
            resources = ROOT / resource_directory
            used = compiler_keys(sources, build)
            print(f"==> {label}: {len(used)} localizable strings")

            for language in languages(resources):
                defined = defined_keys(resources, language)
                missing = sorted(used - defined)
                unused = sorted(defined - used)

                if language == DEVELOPMENT_LANGUAGE:
                    # Falling through to the key is the English text, so a gap
                    # here is a choice rather than a defect. Reported anyway:
                    # the number should move when someone means it to.
                    note = f", {len(missing)} left to fall through" if missing else ""
                    print(f"    {language}: {len(defined)} keys{note}")
                elif missing:
                    failures += len(missing)
                    print(f"    {language}: {len(missing)} untranslated")
                    for key in missing:
                        print(f"      missing: {key!r}")
                else:
                    print(f"    {language}: ok ({len(defined)} keys)")

                if unused:
                    failures += len(unused)
                    print(f"    {language}: {len(unused)} defined but never looked up")
                    for key in unused:
                        print(f"      unused:  {key!r}")

    if failures:
        print(f"\n{failures} problem(s)")
        return 1
    print("\n==> ok")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
