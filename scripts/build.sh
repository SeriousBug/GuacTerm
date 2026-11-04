#!/bin/bash
#
# Build GuacTerm from the command line.
#
#   ./scripts/build.sh            # Release build -> dist/GuacTerm.app
#   ./scripts/build.sh --debug    # Debug build   -> dist/GuacTerm.app
#
# Everything stays inside the repo: DerivedData goes to build/, the product is
# copied to dist/. No developer account is required; the project signs ad-hoc by
# default (see Config/Signing.xcconfig). Override signing from the environment:
#
#   SIGNING_IDENTITY="Developer ID Application: ..." DEVELOPMENT_TEAM=ABCDE12345 ./scripts/build.sh
#
set -euo pipefail

cd "$(dirname "$0")/.."

CONFIGURATION="Release"
while [[ $# -gt 0 ]]; do
    case "$1" in
        --debug) CONFIGURATION="Debug" ;;
        --release) CONFIGURATION="Release" ;;
        -h | --help)
            sed -n '2,13p' "$0" | sed 's/^# \{0,1\}//'
            exit 0
            ;;
        *)
            echo "error: unknown argument '$1' (try --help)" >&2
            exit 2
            ;;
    esac
    shift
done

DERIVED_DATA="build/DerivedData"
APP_NAME="GuacTerm"
BUILT_APP="$DERIVED_DATA/Build/Products/$CONFIGURATION/$APP_NAME.app"
DIST_DIR="dist"
DIST_APP="$DIST_DIR/$APP_NAME.app"

if [[ ! -f GuacTerm.xcodeproj/project.pbxproj ]]; then
    echo "error: GuacTerm.xcodeproj is missing, run 'make project' first" >&2
    exit 1
fi

mkdir -p "$DERIVED_DATA" "$DIST_DIR"

XCODEBUILD_ARGS=(
    -project GuacTerm.xcodeproj
    -scheme GuacTerm
    -configuration "$CONFIGURATION"
    -derivedDataPath "$DERIVED_DATA"
    -destination "platform=macOS"
    # SwiftTerm ships a build-tool plugin; SwiftPM refuses to run one until it is
    # trusted, which Xcode does interactively. CI and CLI builds must say so.
    -skipPackagePluginValidation
    -skipMacroValidation
    -quiet
    build
)

# Optional signing overrides; when unset the xcconfig defaults (ad-hoc) apply.
if [[ -n "${SIGNING_IDENTITY:-}" ]]; then
    XCODEBUILD_ARGS+=(CODE_SIGN_IDENTITY="$SIGNING_IDENTITY")
fi
if [[ -n "${DEVELOPMENT_TEAM:-}" ]]; then
    XCODEBUILD_ARGS+=(DEVELOPMENT_TEAM="$DEVELOPMENT_TEAM")
fi

echo "==> Building $APP_NAME ($CONFIGURATION)"
xcodebuild "${XCODEBUILD_ARGS[@]}"

if [[ ! -d "$BUILT_APP" ]]; then
    echo "error: expected product not found at $BUILT_APP" >&2
    exit 1
fi

# Check the bundle, not project.yml.
#
# A resources phase is configured by a path in project.yml, so a typo there does
# not fail the build: the app still launches and quietly offers only its two
# built-in themes. Same for the Info.plist, which is generated into Contents/ and
# must not also be copied into Resources/ where the real one would shadow it.
# Both used to be checked by scripts/check-bundled-resources.py, which nothing
# ever ran — a check is only worth having where it runs by itself.
echo "==> Checking bundled resources"
BUNDLED_RESOURCES="$BUILT_APP/Contents/Resources"

if [[ ! -s "$BUNDLED_RESOURCES/Themes.json" ]]; then
    echo "error: Themes.json is missing from $BUNDLED_RESOURCES" >&2
    echo "       check the Resources/Themes.json entry in project.yml, then 'make project'" >&2
    exit 1
fi

if [[ ! -f "$BUILT_APP/Contents/Info.plist" ]]; then
    echo "error: no Info.plist in $BUILT_APP/Contents (INFOPLIST_FILE is not set right)" >&2
    exit 1
fi

if [[ -e "$BUNDLED_RESOURCES/Info.plist" ]]; then
    echo "error: Info.plist was copied into Resources/ as well as Contents/" >&2
    echo "       it must only be generated, never listed in a resources phase" >&2
    exit 1
fi

echo "==> Copying to $DIST_APP"
rm -rf "$DIST_APP"
/usr/bin/ditto "$BUILT_APP" "$DIST_APP"

codesign --verify --deep --strict "$DIST_APP" >/dev/null 2>&1 \
    && echo "==> Signature verified" \
    || echo "warning: signature verification reported problems" >&2

echo "$DIST_APP"
