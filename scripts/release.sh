#!/bin/bash
#
# Publish a release: notarize it, package it, sign the appcast, upload it.
#
#   ./scripts/release.sh                    # everything, ending with the upload
#   ./scripts/release.sh --notes NOTES.md   # notes shown in the updater's window
#   ./scripts/release.sh --no-upload        # stop after dist/appcast.xml
#
# The version is MARKETING_VERSION from project.yml, and the release is tagged
# v<version>. The build number comes from the commit count, so it grows by itself
# and Sparkle has something to compare versions with: CFBundleVersion, not the
# version string, is what decides whether an update is newer.
#
# The upload is a GitHub release carrying the notarized zip (what Sparkle
# installs), the disk image (what people download by hand) and appcast.xml (what
# Sparkle reads). All of it is signed with the EdDSA key in the login Keychain;
# see scripts/appcast.sh for that half.
#
# Requirements: a Developer ID Application certificate and notarization
# credentials, exactly as scripts/notarize.sh needs them, plus an authenticated
# `gh`. Nothing is committed, tagged or pushed until the upload, and nothing is
# uploaded at all with --no-upload.
#
set -euo pipefail

cd "$(dirname "$0")/.."

APP_NAME="GuacTerm"
DIST_DIR="dist"

die() {
    echo "" >&2
    echo "error: $*" >&2
    echo "" >&2
    exit 1
}

NOTES=""
UPLOAD=1
while [[ $# -gt 0 ]]; do
    case "$1" in
        --notes)
            [[ $# -ge 2 ]] || die "--notes needs a file"
            NOTES="$2"
            shift
            ;;
        --no-upload) UPLOAD=0 ;;
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

# -------------------------------------------------------------------- preflight
# The one place a release version comes from: the same setting the app's
# Info.plist is built from, so the two cannot disagree.
VERSION="$(sed -n 's/^ *MARKETING_VERSION: *"\(.*\)"$/\1/p' project.yml | head -n 1)"
[[ -n "$VERSION" ]] || die "could not read MARKETING_VERSION from project.yml"
[[ -z "$NOTES" || -f "$NOTES" ]] || die "release notes file '$NOTES' not found"

TAG="v$VERSION"

if [[ $UPLOAD -eq 1 ]]; then
    [[ -z "$(git status --porcelain)" ]] || die "the working tree has uncommitted changes.
  A release is built from a commit, so commit or stash first, or publish the
  build without uploading it: ./scripts/release.sh --no-upload"

    command -v gh >/dev/null || die "the GitHub CLI is needed for the upload: brew install gh"
    gh auth status >/dev/null 2>&1 || die "gh is not authenticated. Run: gh auth login"

    if git rev-parse -q --verify "refs/tags/$TAG" >/dev/null; then
        die "tag $TAG already exists here. Bump MARKETING_VERSION in project.yml first."
    fi
    if git ls-remote --exit-code --tags origin "refs/tags/$TAG" >/dev/null 2>&1; then
        die "tag $TAG already exists on origin. Bump MARKETING_VERSION in project.yml first."
    fi
else
    [[ -z "$(git status --porcelain)" ]] \
        || echo "note: the working tree has uncommitted changes; fine for --no-upload" >&2
fi

# Sparkle compares CFBundleVersion, so the build number has to grow with every
# release. The commit count does that without anyone remembering to bump it.
BUILD_NUMBER="$(git rev-list --count HEAD)"

echo "==> $APP_NAME $VERSION ($BUILD_NUMBER), tag $TAG"

# --------------------------------------------------------------- build and sign
BUILD_NUMBER="$BUILD_NUMBER" ./scripts/notarize.sh

BUILT_VERSION="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' \
    "$DIST_DIR/$APP_NAME.app/Contents/Info.plist")"
BUILT_BUILD="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleVersion' \
    "$DIST_DIR/$APP_NAME.app/Contents/Info.plist")"
[[ "$BUILT_VERSION" == "$VERSION" ]] || die "the build says $BUILT_VERSION, expected $VERSION
  (MARKETING_VERSION in project.yml and the version this script uses disagree)"
[[ "$BUILT_BUILD" == "$BUILD_NUMBER" ]] || die "the build's CFBundleVersion is $BUILT_BUILD, expected $BUILD_NUMBER
  (scripts/notarize.sh did not pass BUILD_NUMBER on)"

ZIP="$DIST_DIR/$APP_NAME-$VERSION.zip"
[[ -f "$ZIP" ]] || die "$ZIP was not produced by scripts/notarize.sh"

./scripts/dmg.sh --no-build
DMG="$DIST_DIR/$APP_NAME-$VERSION.dmg"
[[ -f "$DMG" ]] || die "$DMG was not produced by scripts/dmg.sh"

if [[ -n "$NOTES" ]]; then
    ./scripts/appcast.sh --notes "$NOTES"
else
    ./scripts/appcast.sh
fi

# ---------------------------------------------------------------------- publish
if [[ $UPLOAD -eq 0 ]]; then
    echo ""
    echo "==> Not uploaded. The assets a release needs are:"
    printf '    %s\n' "$ZIP" "$DMG" "$DIST_DIR/appcast.xml"
    exit 0
fi

NOTES_ARGS=(--generate-notes)
if [[ -n "$NOTES" ]]; then
    NOTES_ARGS=(--notes-file "$NOTES")
fi

echo "==> Uploading $TAG"
gh release create "$TAG" \
    --title "$APP_NAME $VERSION" \
    --target "$(git rev-parse HEAD)" \
    "${NOTES_ARGS[@]}" \
    "$ZIP" \
    "$DMG" \
    "$DIST_DIR/appcast.xml"
