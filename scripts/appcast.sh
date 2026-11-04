#!/bin/bash
#
# Sign a release archive and write the appcast Sparkle reads.
#
#   ./scripts/appcast.sh                    # dist/GuacTerm-<version>.zip -> dist/appcast.xml
#   ./scripts/appcast.sh --notes NOTES.md   # attach release notes to the entry
#   ./scripts/appcast.sh --archive FILE     # publish something other than the default
#
# The appcast lists one version: the one in dist/, whose enclosure points at the
# archive inside the matching GitHub release. That release has to be tagged
# v<version> and carry both files, which is what scripts/release.sh arranges;
# the feed URL baked into the app is the appcast.xml of the newest release, so
# every published check sees the newest version and nothing is hosted elsewhere.
#
# Signing uses the EdDSA key in the login Keychain whose public half is
# SUPublicEDKey in project.yml: the archive, the appcast itself and the notes are
# all signed with it, and an app refuses anything signed by another key.
#
#   SPARKLE_ACCOUNT   keychain account of the private key (default: guacterm)
#   SPARKLE_KEY_FILE  read the private key from this file instead of the Keychain
#   SPARKLE_BIN       directory holding generate_appcast, when it is not the one
#                     the resolved Sparkle package ships in build/
#
set -euo pipefail

cd "$(dirname "$0")/.."

APP_NAME="GuacTerm"
DIST_DIR="dist"
DIST_APP="$DIST_DIR/$APP_NAME.app"

die() {
    echo "" >&2
    echo "error: $*" >&2
    echo "" >&2
    exit 1
}

NOTES=""
ARCHIVE=""
while [[ $# -gt 0 ]]; do
    case "$1" in
        --notes)
            [[ $# -ge 2 ]] || die "--notes needs a file"
            NOTES="$2"
            shift
            ;;
        --archive)
            [[ $# -ge 2 ]] || die "--archive needs a file"
            ARCHIVE="$2"
            shift
            ;;
        -h | --help)
            # Every line of the comment block at the top, without the '#'.
            sed -n '/^#!/d; /^set /q; p' "$0" | sed 's/^# \{0,1\}//'
            exit 0
            ;;
        *)
            echo "error: unknown argument '$1' (try --help)" >&2
            exit 2
            ;;
    esac
    shift
done

# ---------------------------------------------------------------- what to sign
[[ -d "$DIST_APP" ]] || die "$DIST_APP not found. Build it first:
  make dist     # sign, notarize and staple a publishable build"

VERSION="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$DIST_APP/Contents/Info.plist")"
[[ -n "$VERSION" ]] || die "could not read CFBundleShortVersionString from $DIST_APP"

if [[ -z "$ARCHIVE" ]]; then
    ARCHIVE="$DIST_DIR/$APP_NAME-$VERSION.zip"
fi
[[ -f "$ARCHIVE" ]] || die "$ARCHIVE not found. 'make dist' writes it, together with
  the notarized app it was made from."

if [[ -n "$NOTES" && ! -f "$NOTES" ]]; then
    die "release notes file '$NOTES' not found"
fi

# ------------------------------------------------------------------- the tools
# Sparkle ships generate_appcast in the same archive the package resolves from,
# so there is nothing to download and no version to keep in sync by hand.
if [[ -z "${SPARKLE_BIN:-}" ]]; then
    artifact="build/DerivedData/SourcePackages/artifacts/sparkle/Sparkle/bin"
    if [[ -x "$artifact/generate_appcast" ]]; then
        SPARKLE_BIN="$artifact"
    else
        # The resolved location carries the package's identity in its path, so
        # this survives a rename of either half.
        SPARKLE_BIN="$(find build/DerivedData/SourcePackages/artifacts \
            -type d -name bin -path '*Sparkle*' -not -path '*extract*' 2>/dev/null | head -n 1)"
    fi
fi
[[ -n "${SPARKLE_BIN:-}" && -x "${SPARKLE_BIN:-/nonexistent}/generate_appcast" ]] || die "generate_appcast not found. Resolve the Sparkle package first:
  make build
  or point SPARKLE_BIN at a directory holding the Sparkle tools."

SIGN_ARGS=()
if [[ -n "${SPARKLE_KEY_FILE:-}" ]]; then
    SIGN_ARGS+=(--ed-key-file "$SPARKLE_KEY_FILE")
else
    SIGN_ARGS+=(--account "${SPARKLE_ACCOUNT:-guacterm}")
fi

# ------------------------------------------------------------ where it will live
# Derived from origin rather than hardcoded, so a fork publishes to itself.
REMOTE="$(git remote get-url origin 2>/dev/null || true)"
SLUG="$(printf '%s' "$REMOTE" \
    | sed -e 's/\.git$//' \
        -e 's#^.*[:/]\([^/]*/[^/]*\)$#\1#')"
[[ "$SLUG" == */* ]] || die "could not work out the GitHub repository from origin ('$REMOTE')"
DOWNLOAD_PREFIX="https://github.com/$SLUG/releases/download/v$VERSION/"

# ------------------------------------------------------------------- generate
WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT

# generate_appcast reads the bundle inside the archive for the version, so the
# archive has to be named after the file it will be published as, and release
# notes are picked up by sharing that name.
cp "$ARCHIVE" "$WORK/$(basename "$ARCHIVE")"
if [[ -n "$NOTES" ]]; then
    cp "$NOTES" "$WORK/$(basename "${ARCHIVE%.*}").md"
fi

echo "==> Signing $(basename "$ARCHIVE") for $DOWNLOAD_PREFIX"
# Written into the work directory on purpose: generate_appcast appends to an
# appcast.xml it finds at its output path, and this feed describes one release,
# not a history of them.
"$SPARKLE_BIN/generate_appcast" "$WORK" \
    "${SIGN_ARGS[@]}" \
    --download-url-prefix "$DOWNLOAD_PREFIX" \
    --link "https://github.com/$SLUG" \
    -o "$WORK/appcast.xml"

[[ -s "$WORK/appcast.xml" ]] || die "generate_appcast wrote no appcast"
cp "$WORK/appcast.xml" "$DIST_DIR/appcast.xml"

echo "==> $(du -h "$DIST_DIR/appcast.xml" | cut -f1) $DIST_DIR/appcast.xml"
echo ""
echo "$DIST_DIR/appcast.xml"
