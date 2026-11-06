#!/bin/bash
# Build CursorHop and package it as a drag-to-install DMG.
#
#   ./make-dmg.sh
#       Free build (ad-hoc signed). Friends must click "Open Anyway" once in
#       System Settings › Privacy & Security.
#
#   SIGN_ID="Developer ID Application: Your Name (TEAMID)" ./make-dmg.sh
#       Signs with your Developer ID (needs the paid Apple Developer Program).
#
#   SIGN_ID="..." NOTARY_PROFILE="cursorhop" ./make-dmg.sh
#       Also notarizes + staples, so it opens with no warnings. Create the
#       profile once with:
#         xcrun notarytool store-credentials cursorhop --apple-id you@example.com --team-id TEAMID
set -euo pipefail
cd "$(dirname "$0")"

./build.sh universal

APP="build/CursorHop.app"
VERSION=$(/usr/libexec/PlistBuddy -c "Print CFBundleShortVersionString" CursorHop/Info.plist)
STAGE="build/dmg"
DMG="build/CursorHop-$VERSION.dmg"

if [[ -n "${SIGN_ID:-}" ]]; then
    echo "Signing app with: $SIGN_ID"
    codesign --force --options runtime --timestamp --sign "$SIGN_ID" "$APP"
fi

# Window contents: the app + a shortcut to /Applications to drag it onto.
rm -rf "$STAGE" "$DMG"
mkdir -p "$STAGE"
cp -R "$APP" "$STAGE/"
ln -s /Applications "$STAGE/Applications"

hdiutil create -volname "CursorHop" -srcfolder "$STAGE" -ov -format UDZO "$DMG"
rm -rf "$STAGE"

if [[ -n "${SIGN_ID:-}" ]]; then
    codesign --force --timestamp --sign "$SIGN_ID" "$DMG"
fi

if [[ -n "${NOTARY_PROFILE:-}" ]]; then
    [[ -n "${SIGN_ID:-}" ]] || { echo "NOTARY_PROFILE needs SIGN_ID too" >&2; exit 1; }
    echo "Submitting for notarization (takes a few minutes)…"
    xcrun notarytool submit "$DMG" --keychain-profile "$NOTARY_PROFILE" --wait
    xcrun stapler staple "$DMG"
fi

echo
echo "Done: $DMG"
