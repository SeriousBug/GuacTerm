#!/bin/bash
#
# Developer ID sign + notarize + staple GuacTerm, producing a publishable zip.
#
#   ./scripts/notarize.sh
#
# Requirements: a "Developer ID Application" certificate in the login keychain and
# notarization credentials, given either as a stored notarytool keychain profile
#   NOTARY_PROFILE=guacterm-notary ./scripts/notarize.sh
# or as an Apple ID + app-specific password
#   APPLE_ID=you@example.com TEAM_ID=ABCDE12345 NOTARY_PASSWORD=abcd-efgh-ijkl-mnop ./scripts/notarize.sh
#
# Optional overrides:
#   SIGNING_IDENTITY   full identity name; defaults to the first "Developer ID
#                      Application" identity in the keychain
#   DEVELOPMENT_TEAM   team id; defaults to the one in the identity name
#   TEAM_ID            team id used for --apple-id notarization (falls back to DEVELOPMENT_TEAM)
#   BUILD_NUMBER       CFBundleVersion to stamp on the build; scripts/release.sh
#                      passes the commit count, so each release outranks the last
#
# Result: dist/GuacTerm-<MARKETING_VERSION>.zip containing the stapled app.
# No secrets are stored in this script or in the repository.
#
set -euo pipefail

cd "$(dirname "$0")/.."

APP_NAME="GuacTerm"
DERIVED_DATA="build/DerivedData"
DIST_DIR="dist"
DIST_APP="$DIST_DIR/$APP_NAME.app"

die() {
    echo "" >&2
    echo "error: $*" >&2
    echo "" >&2
    exit 1
}

# ---------------------------------------------------------------- credentials
NOTARY_PROFILE="${NOTARY_PROFILE:-${NOTARYTOOL_PROFILE:-${NOTARY_KEYCHAIN_PROFILE:-}}}"

IDENTITY="${SIGNING_IDENTITY:-}"
if [[ -z "$IDENTITY" ]]; then
    IDENTITY="$(security find-identity -v -p codesigning 2>/dev/null \
        | sed -n 's/.*"\(Developer ID Application: [^"]*\)".*/\1/p' \
        | head -n 1)"
fi

if [[ -z "$IDENTITY" ]]; then
    die "no 'Developer ID Application' code signing identity found.

  Install a Developer ID Application certificate (Xcode > Settings > Accounts >
  Manage Certificates, or from developer.apple.com), then confirm it with:
      security find-identity -v -p codesigning

  Or pass one explicitly:
      SIGNING_IDENTITY='Developer ID Application: Your Name (ABCDE12345)' ./scripts/notarize.sh"
fi

case "$IDENTITY" in
    "Developer ID Application:"*) ;;
    *) die "SIGNING_IDENTITY must be a Developer ID Application identity for
  notarization (got '$IDENTITY'). Ad-hoc or Apple Development identities are
  rejected by the notary service." ;;
esac

IDENTITY_HASH="$(security find-identity -v -p codesigning 2>/dev/null \
    | awk -v quoted_identity="\"$IDENTITY\"" 'index($0, quoted_identity) { print $2; exit }')"
[[ -n "$IDENTITY_HASH" ]] || die "could not find a valid keychain identity matching '$IDENTITY'"

# Team id: prefer explicit DEVELOPMENT_TEAM / TEAM_ID, else parse "(TEAMID)".
TEAM_ID_RESOLVED="${DEVELOPMENT_TEAM:-${TEAM_ID:-}}"
if [[ -z "$TEAM_ID_RESOLVED" ]]; then
    TEAM_ID_RESOLVED="$(printf '%s' "$IDENTITY" | sed -n 's/.*(\([A-Z0-9]\{10\}\))$/\1/p')"
fi
[[ -n "$TEAM_ID_RESOLVED" ]] || die "could not determine the Apple team id.
  Pass it explicitly: DEVELOPMENT_TEAM=ABCDE12345 ./scripts/notarize.sh"

NOTARY_ARGS=()
if [[ -n "$NOTARY_PROFILE" ]]; then
    command -v xcrun >/dev/null || die "xcrun not found; install Xcode command line tools."
    NOTARY_ARGS+=(--keychain-profile "$NOTARY_PROFILE")
else
    if [[ -z "${APPLE_ID:-}" || -z "${NOTARY_PASSWORD:-}" ]]; then
        die "notarization credentials are incomplete.

  Provide either a stored keychain profile:
      xcrun notarytool store-credentials guacterm-notary \\
          --apple-id you@example.com --team-id ABCDE12345 --password abcd-efgh-ijkl-mnop
      NOTARY_PROFILE=guacterm-notary ./scripts/notarize.sh

  or all three environment variables:
      APPLE_ID, NOTARY_PASSWORD (an app-specific password from appleid.apple.com),
      and TEAM_ID (or DEVELOPMENT_TEAM)."
    fi
    NOTARY_ARGS+=(--apple-id "$APPLE_ID" --team-id "${TEAM_ID:-$TEAM_ID_RESOLVED}" --password "$NOTARY_PASSWORD")
fi

echo "==> Identity: $IDENTITY"
echo "==> Team:     $TEAM_ID_RESOLVED"

# --------------------------------------------------------------------- build
echo "==> Building $APP_NAME (Release, Developer ID)"
mkdir -p "$DERIVED_DATA" "$DIST_DIR"

# Sparkle picks the newer of two builds by CFBundleVersion, so a release that
# reclaims the default of 1 would never be offered to anyone. scripts/release.sh
# passes a number that grows with every commit.
BUILD_NUMBER_ARG=(CURRENT_PROJECT_VERSION="${BUILD_NUMBER:-1}")

xcodebuild \
    -project GuacTerm.xcodeproj \
    -scheme GuacTerm \
    -configuration Release \
    -derivedDataPath "$DERIVED_DATA" \
    -destination "platform=macOS" \
    -skipPackagePluginValidation \
    -skipMacroValidation \
    "${BUILD_NUMBER_ARG[@]}" \
    CODE_SIGN_STYLE=Manual \
    CODE_SIGN_IDENTITY="$IDENTITY" \
    DEVELOPMENT_TEAM="$TEAM_ID_RESOLVED" \
    PROVISIONING_PROFILE_SPECIFIER="" \
    ENABLE_HARDENED_RUNTIME=YES \
    CODE_SIGN_INJECT_BASE_ENTITLEMENTS=NO \
    ENABLE_APP_SANDBOX=NO \
    OTHER_CODE_SIGN_FLAGS="--timestamp" \
    build

BUILT_APP="$DERIVED_DATA/Build/Products/Release/$APP_NAME.app"
[[ -d "$BUILT_APP" ]] || die "build product not found at $BUILT_APP"

echo "==> Copying to $DIST_APP"
rm -rf "$DIST_APP"
/usr/bin/ditto "$BUILT_APP" "$DIST_APP"

# Sparkle's packaged helpers are ad-hoc signed. This custom build flow does not
# perform Xcode's archive export signing pass, so sign the helpers before their
# containing framework and app.
SPARKLE_FRAMEWORK="$DIST_APP/Contents/Frameworks/Sparkle.framework"
SPARKLE_VERSIONED="$SPARKLE_FRAMEWORK/Versions/Current"
echo "==> Signing Sparkle helpers"
codesign --force --sign "$IDENTITY_HASH" --options runtime --timestamp \
    "$SPARKLE_VERSIONED/XPCServices/Installer.xpc"
codesign --force --sign "$IDENTITY_HASH" --options runtime --preserve-metadata=entitlements --timestamp \
    "$SPARKLE_VERSIONED/XPCServices/Downloader.xpc"
codesign --force --sign "$IDENTITY_HASH" --options runtime --timestamp \
    "$SPARKLE_VERSIONED/Autoupdate"
codesign --force --sign "$IDENTITY_HASH" --options runtime --timestamp \
    "$SPARKLE_VERSIONED/Updater.app"
codesign --force --sign "$IDENTITY_HASH" --options runtime --timestamp "$SPARKLE_FRAMEWORK"
codesign --force --sign "$IDENTITY_HASH" --options runtime --timestamp "$DIST_APP"

# --------------------------------------------------------------------- verify
echo "==> Verifying signature"
codesign --verify --deep --strict --verbose=2 "$DIST_APP" \
    || die "code signature verification failed for $DIST_APP"

SIGNATURE_DETAILS="$(codesign -dv --verbose=4 "$DIST_APP" 2>&1)"
if ! grep -q "flags=.*runtime" <<<"$SIGNATURE_DETAILS"; then
    echo "warning: hardened runtime flag not reported by codesign; notarization may fail" >&2
fi

VERSION="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$DIST_APP/Contents/Info.plist")"
[[ -n "$VERSION" ]] || die "could not read CFBundleShortVersionString from $DIST_APP"
ZIP="$DIST_DIR/$APP_NAME-$VERSION.zip"

# ----------------------------------------------------------------- notarize
echo "==> Zipping $ZIP"
rm -f "$ZIP"
/usr/bin/ditto -c -k --sequesterRsrc --keepParent "$DIST_APP" "$ZIP"

echo "==> Submitting to the notary service (this can take a few minutes)"
set +e
SUBMIT_OUTPUT="$(xcrun notarytool submit "$ZIP" "${NOTARY_ARGS[@]}" --wait 2>&1)"
SUBMIT_STATUS=$?
set -e
printf '%s\n' "$SUBMIT_OUTPUT"

if [[ $SUBMIT_STATUS -ne 0 ]] || ! printf '%s' "$SUBMIT_OUTPUT" | grep -q "status: Accepted"; then
    NOTARY_ID="$(printf '%s' "$SUBMIT_OUTPUT" | sed -n 's/^ *id: *//p' | head -n 1)"
    if [[ -n "$NOTARY_ID" ]]; then
        echo "==> Notarization log for $NOTARY_ID" >&2
        xcrun notarytool log "$NOTARY_ID" "${NOTARY_ARGS[@]}" >&2 || true
    fi
    die "notarization failed (see the log above)"
fi

# --------------------------------------------------------------------- staple
echo "==> Stapling $DIST_APP"
xcrun stapler staple "$DIST_APP" || die "stapling failed for $DIST_APP"
xcrun stapler validate "$DIST_APP" || die "stapler validation failed for $DIST_APP"

# Re-zip so the published archive contains the stapled, ticket-carrying app.
echo "==> Re-zipping stapled app"
rm -f "$ZIP"
/usr/bin/ditto -c -k --sequesterRsrc --keepParent "$DIST_APP" "$ZIP"

echo ""
echo "$ZIP"
