#!/usr/bin/env python3
"""Check that the generated Xcode project bundles Themes.json and not Info.plist.

XcodeGen writes GuacTerm.xcodeproj/project.pbxproj from project.yml, so the only
way to be sure the vendored schemes ship (and that the generated Info.plist does
not get copied a second time) is to read what was actually generated.

    ./scripts/check-bundled-resources.py            # project at GuacTerm.xcodeproj
    ./scripts/check-bundled-resources.py --project path/to/X.xcodeproj

Exits non-zero with a message when a check fails. Standard library only.
"""

from __future__ import annotations

import argparse
import os
import re
import sys

REPO_ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
DEFAULT_PROJECT = os.path.join(REPO_ROOT, "GuacTerm.xcodeproj")

#: Files that must be copied into the app bundle.
REQUIRED_RESOURCES = ["Themes.json"]

#: Files that must never enter a resources build phase (they are generated and
#: referenced through INFOPLIST_FILE instead).
FORBIDDEN_RESOURCES = ["Info.plist"]


def read_pbxproj(project_path: str) -> str:
    candidate = os.path.join(project_path, "project.pbxproj")
    with open(candidate, "r", encoding="utf-8") as handle:
        return handle.read()


def build_phase_files(pbxproj: str) -> dict:
    """Map phase name -> list of (build file id, build file comment)."""
    phases = {}
    pattern = re.compile(
        r"/\* (Begin|End) PBX(Resources|Sources|Frameworks|CopyFiles)BuildPhase section \*/"
    )
    position = 0
    while True:
        start = pattern.search(pbxproj, position)
        if start is None:
            break
        if start.group(1) == "End":
            position = start.end()
            continue

        kind = start.group(2)
        end = re.compile(
            r"/\* End PBX%sBuildPhase section \*/" % kind
        ).search(pbxproj, start.end())
        if end is None:
            raise SystemExit("error: unterminated %s build phase section" % kind)
        section = pbxproj[start.end() : end.start()]

        # Each phase: "<id> /* <name> */ = { isa = PBX..BuildPhase; ... files = ( ... ); }"
        for phase in re.finditer(
            r"([0-9A-F]{24}) /\* (.+?) \*/\s*=\s*\{(.*?)\n\t\t\};",
            section,
            re.DOTALL,
        ):
            body = phase.group(3)
            files = []
            listing = re.search(r"files = \((.*?)\);", body, re.DOTALL)
            if listing:
                for line in listing.group(1).splitlines():
                    entry = re.match(
                        r"\s*([0-9A-F]{24}) /\* (.+?) \*/", line
                    )
                    if entry:
                        files.append((entry.group(1), entry.group(2)))
            phases["%s:%s" % (kind, phase.group(2))] = files

        position = end.end()
    return phases


def main(argv=None) -> int:
    parser = argparse.ArgumentParser(
        description="Verify the generated pbxproj's resources build phases.",
    )
    parser.add_argument("--project", default=DEFAULT_PROJECT)
    args = parser.parse_args(argv)

    pbxproj = read_pbxproj(args.project)

    problems = []
    phases = build_phase_files(pbxproj)
    resource_phases = {
        "%s phase %r" % (kind, name): files
        for key, files in phases.items()
        for kind, name in [key.split(":", 1)]
        if kind == "Resources"
    }

    if not resource_phases:
        problems.append("no PBXResourcesBuildPhase section found")

    bundled = set()
    for name, files in resource_phases.items():
        for _, comment in files:
            bundled.add(comment)
        print("%s: %d file(s)" % (name, len(files)))
        for _, comment in files:
            print("  - %s" % comment)

    for required in REQUIRED_RESOURCES:
        # A phase comment looks like "<file name> in Resources", so match per file
        # rather than against the joined string of every comment.
        pattern = re.compile(r"%s in .+" % re.escape(required))
        if not any(pattern.fullmatch(comment) for comment in bundled):
            problems.append("%s is not in a resources build phase" % required)
        else:
            print("ok: %s is copied as a resource" % required)

    for forbidden in FORBIDDEN_RESOURCES:
        pattern = re.compile(r"%s in .+" % re.escape(forbidden))
        if any(pattern.fullmatch(comment) for comment in bundled):
            problems.append("%s must not be copied as a resource" % forbidden)
        else:
            print("ok: %s is not copied as a resource" % forbidden)

    # The Info.plist must still be referenced through INFOPLIST_FILE instead.
    if "INFOPLIST_FILE = Resources/Info.plist;" not in pbxproj:
        problems.append("INFOPLIST_FILE = Resources/Info.plist is missing")

    if problems:
        for problem in problems:
            sys.stderr.write("FAIL: %s\n" % problem)
        return 1

    print("PASS: project bundles %s and keeps Info.plist generated"
          % ", ".join(REQUIRED_RESOURCES))
    return 0


if __name__ == "__main__":
    sys.exit(main())
