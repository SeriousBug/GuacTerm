#!/usr/bin/env python3
"""Generate Resources/Themes.json from the iTerm2-Color-Schemes collection.

Reads every ``*.itermcolors`` file (an XML property list) from the scheme
repository and writes a single JSON array that GuacTerm bundles as a resource.

Each output entry looks like::

    {
      "id": "3024-night",              # stable slug, unique, used in UserDefaults
      "name": "3024 Night",            # display name, the filename stem verbatim
      "bg": "#090300",
      "fg": "#BBBBBB",
      "cursor": "#BBBBBB",             # falls back to fg when the key is missing
      "ansi": ["#090300", ... 16 values ...]
    }

Colours are sRGB ``#RRGGBB`` uppercase hex. The output is sorted by name, so it
is deterministic: running the script twice on the same source produces a
byte-identical file.

Ids are unique. When two scheme names slugify to the same id (today that is
"Dracula" and "Dracula+"), the scheme whose name is already a clean slug keeps
the plain id and the others get a deterministic ``-2``, ``-3``, ... suffix; the
script prints every such change.

Usage:
    ./scripts/generate-themes.py                       # /tmp/iterm-schemes default
    ./scripts/generate-themes.py --source /tmp/iterm-schemes
    ./scripts/generate-themes.py --output /tmp/Themes.json

Exit status is non-zero when more than 5% of the source files had to be
skipped, so a broken/partial checkout fails loudly instead of silently
shrinking the catalog.

The scheme collection itself is MIT licensed; see THIRD_PARTY_NOTICES.md.
Standard library only: Python 3.8+.
"""

from __future__ import annotations

import argparse
import json
import os
import plistlib
import re
import sys
import unicodedata

# --------------------------------------------------------------------------- #
# Configuration
# --------------------------------------------------------------------------- #

REPO_ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
DEFAULT_SOURCE = "/tmp/iterm-schemes"
DEFAULT_OUTPUT = os.path.join(REPO_ROOT, "Resources", "Themes.json")

#: Skipping more schemes than this fraction of the source files is an error.
MAX_SKIP_RATE = 0.05

ANSI_KEYS = ["Ansi %d Color" % index for index in range(16)]
BACKGROUND_KEY = "Background Color"
FOREGROUND_KEY = "Foreground Color"
CURSOR_KEY = "Cursor Color"

COMPONENT_KEYS = (
    ("Red Component", "red"),
    ("Green Component", "green"),
    ("Blue Component", "blue"),
)

SCHEME_SUFFIX = ".itermcolors"


# --------------------------------------------------------------------------- #
# Colour helpers
# --------------------------------------------------------------------------- #


def _clamp_byte(value: float) -> int:
    """Clamp a 0..1 component to a 0..255 integer, rounding half away from zero."""
    scaled = float(value) * 255.0
    # round() alone would use banker's rounding; add a nudge so X.5 always
    # rounds up and the result is stable across Python versions.
    return max(0, min(255, int(scaled + 0.5)))


def hex_color(color, where: str) -> str:
    """Turn an itermcolors colour dict into ``#RRGGBB``.

    Raises ValueError when a component is missing, so the caller can skip the
    scheme and report why.
    """
    if not isinstance(color, dict):
        raise ValueError("%s is not a colour dict" % where)

    channels = []
    for key, label in COMPONENT_KEYS:
        if key not in color:
            raise ValueError("%s has no %s" % (where, key))
        component = color[key]
        if not isinstance(component, (int, float)) or isinstance(component, bool):
            raise ValueError("%s has a non-numeric %s" % (where, key))
        channels.append(_clamp_byte(component))

    return "#%02X%02X%02X" % tuple(channels)


# --------------------------------------------------------------------------- #
# Identifier helpers
# --------------------------------------------------------------------------- #


def slugify(stem: str) -> str:
    """``"3024 Night"`` -> ``"3024-night"``.

    Lowercase, then collapse every run of non-alphanumerics into a single "-",
    and trim leading/trailing dashes.
    """
    folded = unicodedata.normalize("NFKD", stem)
    folded = "".join(ch for ch in folded if not unicodedata.combining(ch))
    slug = re.sub(r"[^a-z0-9]+", "-", folded.lower())
    return slug.strip("-")


def canonical_rank(stem: str) -> int:
    """0 when the stem is already a clean lowercase slug, 1 otherwise.

    Used to resolve id collisions in favour of the scheme whose name needs no
    mangling: "Dracula" keeps "dracula" and "Dracula+." becomes "dracula-2".
    """
    return 0 if slugify(stem) == stem.lower() else 1


def unique_id(base: str, used: set) -> tuple:
    """Return an id that is not in ``used``, plus the suffix when it had to change."""
    if base and base not in used:
        return base, None

    stem = base or "theme"
    suffix = 2
    while "%s-%d" % (stem, suffix) in used:
        suffix += 1
    return "%s-%d" % (stem, suffix), suffix


# --------------------------------------------------------------------------- #
# Reading schemes
# --------------------------------------------------------------------------- #


def find_scheme_files(source: str) -> list:
    """All ``*.itermcolors`` files under ``source``.

    Accepts either the repository root (``<source>/schemes/*.itermcolors``) or a
    directory of scheme files directly.
    """
    schemes_dir = os.path.join(source, "schemes")
    directory = schemes_dir if os.path.isdir(schemes_dir) else source
    if not os.path.isdir(directory):
        return []

    names = [
        name
        for name in os.listdir(directory)
        if name.endswith(SCHEME_SUFFIX) and not name.startswith(".")
    ]
    # Case-sensitive sort keeps the assignment of ids deterministic even on
    # filesystems that would otherwise hand the names back in any order.
    names.sort()
    return [os.path.join(directory, name) for name in names]


def read_scheme(path: str) -> tuple:
    """Parse one itermcolors file into ``(entry, cursor_was_synthesised)``.

    Raises ValueError with a human-readable reason when the file cannot be used.
    """
    stem = os.path.basename(path)[: -len(SCHEME_SUFFIX)]

    try:
        with open(path, "rb") as handle:
            plist = plistlib.load(handle)
    except Exception as error:  # noqa: BLE001 - any failure means "skip this file"
        raise ValueError("unreadable plist (%s)" % type(error).__name__)

    if not isinstance(plist, dict):
        raise ValueError("plist root is not a dict")

    missing = [key for key in ANSI_KEYS if key not in plist]
    if missing:
        raise ValueError("missing %s" % ", ".join(missing))
    if BACKGROUND_KEY not in plist:
        raise ValueError("missing %s" % BACKGROUND_KEY)
    if FOREGROUND_KEY not in plist:
        raise ValueError("missing %s" % FOREGROUND_KEY)

    ansi = [hex_color(plist[key], key) for key in ANSI_KEYS]
    background = hex_color(plist[BACKGROUND_KEY], BACKGROUND_KEY)
    foreground = hex_color(plist[FOREGROUND_KEY], FOREGROUND_KEY)

    # The cursor is cosmetic; every scheme in the upstream collection has one,
    # but fall back to the foreground rather than dropping a usable scheme.
    cursor_synthesised = False
    if CURSOR_KEY in plist:
        try:
            cursor = hex_color(plist[CURSOR_KEY], CURSOR_KEY)
        except ValueError:
            cursor = foreground
            cursor_synthesised = True
    else:
        cursor = foreground
        cursor_synthesised = True

    entry = {
        "name": stem,
        "bg": background,
        "fg": foreground,
        "cursor": cursor,
        "ansi": ansi,
    }
    return entry, cursor_synthesised


# --------------------------------------------------------------------------- #
# Writing the catalog
# --------------------------------------------------------------------------- #


def sort_key(entry: dict) -> tuple:
    """Sort by name, written so Swift can reproduce it with lowercased().

    Python's ``str.lower()`` and Swift's ``lowercased()`` agree on ASCII, and
    scheme names are ASCII today; the textual tiebreakers keep the order total
    even if that ever changes.
    """
    return (entry["name"].lower(), entry["name"], entry["id"])


def render(entries: list) -> str:
    """One object per line: compact enough to be small, diffable in git."""
    lines = []
    for entry in entries:
        ansi = ",".join(json.dumps(color) for color in entry["ansi"])
        lines.append(
            '  {"id":%s,"name":%s,"bg":%s,"fg":%s,"cursor":%s,"ansi":[%s]}'
            % (
                json.dumps(entry["id"]),
                json.dumps(entry["name"]),
                json.dumps(entry["bg"]),
                json.dumps(entry["fg"]),
                json.dumps(entry["cursor"]),
                ansi,
            )
        )
    return "[\n" + ",\n".join(lines) + "\n]\n"


def parse_args(argv):
    parser = argparse.ArgumentParser(
        description="Generate Resources/Themes.json from *.itermcolors files.",
    )
    parser.add_argument(
        "--source",
        default=DEFAULT_SOURCE,
        help="clone of iTerm2-Color-Schemes, or a directory of "
        "*.itermcolors files (default: %(default)s)",
    )
    parser.add_argument(
        "--output",
        default=DEFAULT_OUTPUT,
        help="JSON file to write (default: Resources/Themes.json in the repo)",
    )
    return parser.parse_args(argv)


def main(argv=None) -> int:
    args = parse_args(argv)

    source = os.path.abspath(os.path.expanduser(args.source))
    output = os.path.abspath(os.path.expanduser(args.output))

    files = find_scheme_files(source)
    if not files:
        sys.stderr.write(
            "error: no %s files found in %s\n"
            "       clone the collection with:\n"
            "         git clone --depth 1 "
            "https://github.com/mbadolato/iTerm2-Color-Schemes.git %s\n"
            % (SCHEME_SUFFIX, source, source)
        )
        return 2

    parsed = []
    skipped = []
    for path in files:
        display_name = os.path.basename(path)
        try:
            entry, cursor_synthesised = read_scheme(path)
        except ValueError as reason:
            skipped.append((display_name, str(reason)))
            continue
        parsed.append((display_name, entry, slugify(entry["name"]), cursor_synthesised))

    # Group by base id so a collision is resolved in a fixed order: the scheme
    # whose name is already a clean slug keeps the plain id, and the others get
    # "-2", "-3", ... in name order. Everything is driven by sorted keys, so the
    # result does not depend on directory iteration order.
    groups = {}
    for item in parsed:
        groups.setdefault(item[2], []).append(item)

    entries = []
    used_ids = set()
    collisions = []
    cursor_fallbacks = []

    for base_id in sorted(groups):
        members = sorted(
            groups[base_id],
            key=lambda item: (
                canonical_rank(item[1]["name"]),
                item[1]["name"].lower(),
                item[1]["name"],
                item[0],
            ),
        )
        for display_name, entry, base, cursor_synthesised in members:
            theme_id, suffix = unique_id(base, used_ids)
            if suffix is not None:
                collisions.append(
                    (entry["name"], display_name, base or "(nothing usable)", theme_id)
                )
            used_ids.add(theme_id)
            entry["id"] = theme_id
            entries.append(entry)
            if cursor_synthesised:
                cursor_fallbacks.append(display_name)

    entries.sort(key=sort_key)

    text = render(entries)

    # Cheap self-check: what we wrote must parse back to the same entry count.
    if len(json.loads(text)) != len(entries):
        sys.stderr.write("error: internal error, JSON did not round-trip\n")
        return 3

    output_dir = os.path.dirname(output)
    if output_dir:
        os.makedirs(output_dir, exist_ok=True)
    with open(output, "w", encoding="utf-8", newline="\n") as handle:
        handle.write(text)

    size = len(text.encode("utf-8"))
    total = len(files)
    written = len(entries)
    skip_rate = len(skipped) / total if total else 0.0

    # ------------------------------------------------------------------ report
    print("source:  %s" % source)
    print("output:  %s  (%d bytes, %.1f KiB)" % (output, size, size / 1024.0))
    print("total:   %d files" % total)
    print("written: %d themes" % written)
    print("skipped: %d (%.2f%%)" % (len(skipped), skip_rate * 100.0))
    for display_name, reason in skipped:
        print("  - %s: %s" % (display_name, reason))

    if collisions:
        print("duplicate ids disambiguated: %d" % len(collisions))
        for name, display_name, base_id, theme_id in collisions:
            print('  - "%s" (%s): "%s" -> "%s"' % (name, display_name, base_id, theme_id))
    else:
        print("duplicate ids disambiguated: 0")

    if cursor_fallbacks:
        # Schemes with no usable "Cursor Color": the foreground stood in.
        print(
            "cursor fell back to foreground: %d (%s)"
            % (len(cursor_fallbacks), ", ".join(cursor_fallbacks[:5]))
            + ("..." if len(cursor_fallbacks) > 5 else "")
        )

    if skip_rate > MAX_SKIP_RATE:
        sys.stderr.write(
            "error: skipped %.2f%% of the schemes, above the %.0f%% limit\n"
            % (skip_rate * 100.0, MAX_SKIP_RATE * 100.0)
        )
        return 1

    return 0


if __name__ == "__main__":
    sys.exit(main())
