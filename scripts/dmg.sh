#!/bin/bash
#
# Package GuacTerm into a disk image.
#
#   ./scripts/dmg.sh              # build, then dist/GuacTerm-<version>.dmg
#   ./scripts/dmg.sh --no-build   # package the app already in dist/
#
# The image holds GuacTerm.app next to a symlink to /Applications, so the window
# it opens is a drag target, and it carries the app's icon as its volume icon.
# .dmg files are read-only and compressed; signing and notarizing one is a
# separate step (see scripts/notarize.sh).
#
set -euo pipefail

cd "$(dirname "$0")/.."

APP_NAME="GuacTerm"
DIST_DIR="dist"
DIST_APP="$DIST_DIR/$APP_NAME.app"
ICONSET_SRC="Resources/Assets.xcassets/AppIcon.appiconset"
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

WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT

# The volume icon is built from the same PNGs the app icon is, with iconutil
# rather than actool: actool's .icns stops at 512px, and a volume icon is read
# straight from the icns.
echo "==> Building the volume icon"
ICONSET="$WORK/$APP_NAME.iconset"
mkdir -p "$ICONSET"
cp "$ICONSET_SRC"/*.png "$ICONSET"/
iconutil -c icns "$ICONSET" -o "$WORK/$APP_NAME.icns"

# Stage the window's contents: the app, and a shortcut to drag it onto.
STAGE="$WORK/stage"
mkdir -p "$STAGE"
echo "==> Staging $APP_NAME $VERSION"
/usr/bin/ditto "$DIST_APP" "$STAGE/$APP_NAME.app"
ln -s /Applications "$STAGE/Applications"

# A volume's icon can only be attached to it while it is mounted read-write, so
# the image is built uncompressed, decorated, then converted to UDZO.
echo "==> Laying out the volume"
RW="$WORK/rw.dmg"
hdiutil create \
    -volname "$APP_NAME" \
    -srcfolder "$STAGE" \
    -fs HFS+ \
    -format UDRW \
    -ov \
    -quiet \
    "$RW"

MOUNT_POINT="$WORK/mnt"
mkdir -p "$MOUNT_POINT"
hdiutil attach "$RW" -mountpoint "$MOUNT_POINT" -nobrowse -noautoopen -quiet

cp "$WORK/$APP_NAME.icns" "$MOUNT_POINT/.VolumeIcon.icns"
SetFile -c icnC "$MOUNT_POINT/.VolumeIcon.icns"
SetFile -a C "$MOUNT_POINT"

# Opening a disk image read-write can leave Finder's own bookkeeping behind.
rm -rf "$MOUNT_POINT/.Trashes" "$MOUNT_POINT/.fseventsd"
hdiutil detach "$MOUNT_POINT" -quiet

echo "==> Creating $DMG"
rm -f "$DMG"
hdiutil convert "$RW" -format UDZO -imagekey zlib-level=9 -ov -quiet -o "$DMG"

echo "==> Verifying $DMG"
mkdir -p "$MOUNT_POINT"
hdiutil attach "$DMG" -mountpoint "$MOUNT_POINT" -nobrowse -noautoopen -quiet
fail() {
    hdiutil detach "$MOUNT_POINT" -quiet || true
    echo "error: $*" >&2
    exit 1
}
[[ -d "$MOUNT_POINT/$APP_NAME.app" ]] || fail "$DMG has no $APP_NAME.app"
[[ -L "$MOUNT_POINT/Applications" ]] || fail "$DMG has no Applications link"
[[ -f "$MOUNT_POINT/.VolumeIcon.icns" ]] || fail "$DMG has no volume icon"
GetFileInfo -a "$MOUNT_POINT" | grep -q C \
    || echo "warning: the volume icon is in $DMG but not flagged as custom" >&2
codesign --verify --deep --strict "$MOUNT_POINT/$APP_NAME.app" 2>/dev/null \
    || echo "warning: the app inside $DMG does not verify its signature" >&2
hdiutil detach "$MOUNT_POINT" -quiet

echo "==> $(du -h "$DMG" | cut -f1) $DMG"
echo ""
echo "$DMG"
