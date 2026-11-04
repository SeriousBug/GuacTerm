#!/bin/bash
#
# Render the app icon into Resources/Assets.xcassets from Resources/logo.svg.
#
#   ./scripts/make-icon.sh
#
# logo.svg is the one source of the artwork: this puts it on a light rounded-square
# plate (what macOS expects of an app icon) and writes the ten PNGs an
# AppIcon.appiconset wants. Run it again after any change to logo.svg, then
# commit the regenerated PNGs. Needs librsvg:
#
#   brew install librsvg
#
set -euo pipefail

cd "$(dirname "$0")/.."

if ! command -v rsvg-convert >/dev/null 2>&1; then
    echo "error: rsvg-convert not found, install it with: brew install librsvg" >&2
    exit 2
fi
if ! command -v magick >/dev/null 2>&1; then
    echo "error: magick not found, install it with: brew install imagemagick" >&2
    exit 2
fi

ICONSET="Resources/Assets.xcassets/AppIcon.appiconset"
WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT

# The plate: a 1024px canvas with macOS's 824px rounded square inset by 100px.
PLATE_SIZE=1024
PLATE_FILL="#f2f3f0"
SQUIRCLE_INSET=100
SQUIRCLE_RADIUS=184

# logo.svg is 512 units wide and its artwork spans x=58..454, so rendering it at
# 832px wide leaves the mortar 643px across the plate: 78% of the plate's width.
ART_WIDTH=832

echo "==> Rendering the plate"
magick -size "${PLATE_SIZE}x${PLATE_SIZE}" xc:none \
    -fill "$PLATE_FILL" \
    -draw "roundrectangle ${SQUIRCLE_INSET},${SQUIRCLE_INSET} \
$((PLATE_SIZE - SQUIRCLE_INSET)),$((PLATE_SIZE - SQUIRCLE_INSET)) \
${SQUIRCLE_RADIUS},${SQUIRCLE_RADIUS}" \
    "$WORK/plate.png"

echo "==> Placing logo.svg on it"
rsvg-convert -w "$ART_WIDTH" Resources/logo.svg -o "$WORK/art.png"
magick "$WORK/plate.png" "$WORK/art.png" -gravity center -composite "$WORK/icon-1024.png"

echo "==> Writing $ICONSET"
mkdir -p "$ICONSET"
rm -f "$ICONSET"/*.png
for size in 16 32 128 256 512; do
    magick "$WORK/icon-1024.png" -filter Lanczos -resize "${size}x${size}" \
        -strip "$ICONSET/icon_${size}x${size}.png"
    magick "$WORK/icon-1024.png" -filter Lanczos -resize "$((size * 2))x$((size * 2))" \
        -strip "$ICONSET/icon_${size}x${size}@2x.png"
done

echo "==> Done, $(find "$ICONSET" -name '*.png' | wc -l | tr -d ' ') PNGs written"
