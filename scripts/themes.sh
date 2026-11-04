#!/bin/bash
#
# Regenerate Resources/Themes.json from iTerm2-Color-Schemes, at a pinned commit.
#
#   ./scripts/themes.sh           # rewrite Resources/Themes.json, then show the diff
#   ./scripts/themes.sh --check   # exit non-zero when the committed file is stale
#
# Why this instead of a git submodule: the upstream collection is ~230 MB of git
# objects and 34k files across 40 output formats (alacritty, vscode, screenshots,
# ...), of which GuacTerm uses 891 files in one format and only the 19 colours in
# each. A shallow, sparse fetch of the single pinned commit into the gitignored
# build/ directory pins exactly as hard as a submodule does, for ~13 MB that only
# this target pays -- a plain clone of GuacTerm still gets nothing extra to fetch.
#
# The generator is scripts/generate-themes.swift, which compiles in the same
# Sources/GuacTerm/ITermColors.swift that the app imports themes with: one
# implementation of reading a .itermcolors file, used at both ends. It is the
# only thing here that needs a compiler (swiftc from the Xcode tools).
#
set -euo pipefail

cd "$(dirname "$0")/.."
REPO_ROOT="$PWD"

# The pin. Keep in sync with THIRD_PARTY_NOTICES.md, which names the same commit.
UPSTREAM_URL="https://github.com/mbadolato/iTerm2-Color-Schemes.git"
UPSTREAM_COMMIT="28ae946da150fd1b3d76f5d5f48a990c357c0256"

# Only schemes/ is needed; everything else in the collection is other formats.
SPARSE_PATH="schemes"

CACHE="build/upstream/iterm-schemes"
OUTPUT="Resources/Themes.json"

GENERATOR="build/tools/generate-themes"
GENERATOR_SOURCES=(
    "$REPO_ROOT/Sources/GuacTerm/ITermColors.swift"
    "$REPO_ROOT/scripts/generate-themes.swift"
)

MODE="write"
while [[ $# -gt 0 ]]; do
    case "$1" in
        --check) MODE="check" ;;
        -h | --help)
            sed -n '2,18p' "$0" | sed 's/^# \{0,1\}//'
            exit 0
            ;;
        *)
            echo "error: unknown argument '$1' (try --help)" >&2
            exit 2
            ;;
    esac
    shift
done

# --------------------------------------------------------------------------- #
# Build the generator (from the app's own parsing code)
# --------------------------------------------------------------------------- #

build_generator() {
    local stale=1
    if [[ -x "$GENERATOR" ]]; then
        stale=0
        for source in "${GENERATOR_SOURCES[@]}"; do
            if [[ "$source" -nt "$GENERATOR" ]]; then
                stale=1
            fi
        done
    fi
    [[ "$stale" -eq 0 ]] && return

    echo "==> Building the catalog generator"
    mkdir -p "$(dirname "$GENERATOR")"
    # Absolute paths on purpose: the tool locates the repository through
    # #filePath, which is whatever Swift was given.
    swiftc -parse-as-library -swift-version 6 -O "${GENERATOR_SOURCES[@]}" -o "$GENERATOR"
}

# --------------------------------------------------------------------------- #
# Fetch the pinned commit, sparsely and shallowly, into the cache
# --------------------------------------------------------------------------- #

have_pinned_source() {
    [[ -d "$CACHE/.git" ]] \
        && [[ "$(git -C "$CACHE" rev-parse HEAD 2>/dev/null || true)" == "$UPSTREAM_COMMIT" ]]
}

fetch_pinned_source() {
    echo "==> Fetching iTerm2-Color-Schemes ${UPSTREAM_COMMIT:0:12} (sparse: $SPARSE_PATH/)"
    rm -rf "$CACHE"
    mkdir -p "$CACHE"

    git -C "$CACHE" init -q
    git -C "$CACHE" remote add origin "$UPSTREAM_URL"
    git -C "$CACHE" sparse-checkout init --cone
    git -C "$CACHE" sparse-checkout set "$SPARSE_PATH"

    # blob:none keeps the download to the tree plus the one directory we checked
    # out. Servers without partial-clone support reject the filter, so retry
    # with a plain shallow fetch (bigger, same result) instead of failing.
    if ! git -C "$CACHE" fetch -q --depth 1 --filter=blob:none origin "$UPSTREAM_COMMIT"; then
        echo "    partial clone unavailable, falling back to a shallow fetch"
        git -C "$CACHE" fetch -q --depth 1 origin "$UPSTREAM_COMMIT"
    fi

    git -C "$CACHE" checkout -q FETCH_HEAD
}

if ! have_pinned_source; then
    fetch_pinned_source
fi

SCHEME_COUNT=$(find "$CACHE/$SPARSE_PATH" -maxdepth 1 -name '*.itermcolors' | wc -l | tr -d ' ')
if [[ "$SCHEME_COUNT" -eq 0 ]]; then
    echo "error: no *.itermcolors files in $CACHE/$SPARSE_PATH" >&2
    echo "       delete $CACHE and run this again" >&2
    exit 1
fi

build_generator

# --------------------------------------------------------------------------- #
# Generate
# --------------------------------------------------------------------------- #

if [[ "$MODE" == "check" ]]; then
    STAGED=$(mktemp -t guacterm-themes)
    trap 'rm -f "$STAGED"' EXIT
    "$GENERATOR" --source "$CACHE" --output "$STAGED"

    if cmp -s "$STAGED" "$OUTPUT"; then
        echo "==> $OUTPUT matches the pinned commit"
        exit 0
    fi

    echo "error: $OUTPUT does not match ${UPSTREAM_COMMIT:0:12}" >&2
    echo "       regenerating is a reviewed change, not a build step:" >&2
    echo "         make themes   # rewrites the file, then review the diff" >&2
    diff -u "$OUTPUT" "$STAGED" | head -40 >&2
    exit 1
fi

BEFORE=$(shasum -a 256 "$OUTPUT" | awk '{print $1}')
"$GENERATOR" --source "$CACHE" --output "$OUTPUT"
AFTER=$(shasum -a 256 "$OUTPUT" | awk '{print $1}')

if [[ "$BEFORE" == "$AFTER" ]]; then
    echo "==> $OUTPUT unchanged"
else
    echo "==> $OUTPUT rewritten; review it with: git diff -- $OUTPUT"
fi
