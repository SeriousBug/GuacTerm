#!/bin/bash
#
# Package GuacTerm into a disk image.
#
#   ./scripts/dmg.sh              # build, then dist/GuacTerm-<version>.dmg
#   ./scripts/dmg.sh --no-build   # package the app already in dist/
#
# The image holds GuacTerm.app next to a symlink to /Applications, so the window
# it opens is a drag target. .dmg files are read-only and compressed; signing and
# notarizing it is a separate step (see scripts/notarize.sh).
#
set -euo pipefail

cd "$(dirname "$0")/.."

APP_NAME="GuacTerm"
DIST_DIR="dist"
DIST_APP="$DIST_DIR/$APP_NAME.app"
BUILD=1

while [[ $# -gt 0 ]]; do
    case "$1" in
        --no-build) BUILD=0 ;;
        -h | --help)
            sed -n '2,12p' "$0" | sed 's/^# \{0,1\}//'
            exit 0
            ;;
        *)
            echo "error: unknown argument '$1' (try --help)" >&2
            exit 2
            ;;
    esac
    shift
done

if [[ $BUILD -eq 1 ]]; then
    ./scripts/build.sh
elif [[ ! -d "$DIST_APP" ]]; then
    echo "error: $DIST_APP not found, drop --no-build or run 'make build'" >&2
    exit 1
fi

VERSION="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$DIST_APP/Contents/Info.plist")"
[[ -n "$VERSION" ]] || {
    echo "error: could not read CFBundleShortVersionString from $DIST_APP" >&2
    exit 1
}
DMG="$DIST_DIR/$APP_NAME-$VERSION.dmg"

# Stage the window's contents: the app, and a shortcut to drag it onto.
STAGE="$(mktemp -d)"
trap 'rm -rf "$STAGE"' EXIT

echo "==> Staging $APP_NAME $VERSION"
/usr/bin/ditto "$DIST_APP" "$STAGE/$APP_NAME.app"
ln -s /Applications "$STAGE/Applications"

# hdiutil is happy to overwrite a mounted image's file on some systems, so the
# old one goes first. UDZO is the compressed, read-only format every macOS
# version mounts.
echo "==> Creating $DMG"
rm -f "$DMG"
hdiutil create \
    -volname "$APP_NAME" \
    -srcfolder "$STAGE" \
    -fs HFS+ \
    -format UDZO \
    -ov \
    -quiet \
    "$DMG"

echo "==> Verifying $DMG"
MOUNT_POINT="$(mktemp -d)"
hdiutil attach "$DMG" -mountpoint "$MOUNT_POINT" -nobrowse -quiet
if [[ ! -d "$MOUNT_POINT/$APP_NAME.app" || ! -L "$MOUNT_POINT/Applications" ]]; then
    hdiutil detach "$MOUNT_POINT" -quiet || true
    echo "error: $DMG does not contain $APP_NAME.app and the Applications link" >&2
    exit 1
fi
codesign --verify --deep --strict "$MOUNT_POINT/$APP_NAME.app" 2>/dev/null \
    || echo "warning: the app inside $DMG does not verify its signature" >&2
hdiutil detach "$MOUNT_POINT" -quiet
rmdir "$MOUNT_POINT"

echo "==> $(du -h "$DMG" | cut -f1) $DMG"
echo ""
echo "$DMG"
