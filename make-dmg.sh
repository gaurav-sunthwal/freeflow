#!/bin/zsh
# Builds dist/FreeFlow-<version>.dmg (drag-to-Applications installer).
#
# Signing: uses a "Developer ID Application" certificate when one is installed (required for
# downloads from the internet); otherwise falls back to whatever identity build.sh finds.
# Notarization: set NOTARY_PROFILE to a profile created with
#   xcrun notarytool store-credentials <profile> --apple-id <id> --team-id <team> --password <app-specific-password>
set -euo pipefail
cd "$(dirname "$0")"

DEVID="$(security find-identity -v -p codesigning 2>/dev/null | awk -F'"' '/Developer ID Application/ {print $2; exit}')"
if [[ -n "$DEVID" ]]; then export FREEFLOW_SIGN_IDENTITY="$DEVID"; fi
./build.sh

APP="dist/FreeFlow.app"
VERSION="$(/usr/libexec/PlistBuddy -c 'Print CFBundleShortVersionString' "$APP/Contents/Info.plist")"
DMG="dist/FreeFlow-$VERSION.dmg"
STAGE="$(mktemp -d)"
trap 'rm -rf "$STAGE"' EXIT

cp -R "$APP" "$STAGE/"
ln -s /Applications "$STAGE/Applications"
rm -f "$DMG"
hdiutil create -volname "FreeFlow" -srcfolder "$STAGE" -fs HFS+ -format UDZO -imagekey zlib-level=9 -ov "$DMG" >/dev/null

IDENTITY="${FREEFLOW_SIGN_IDENTITY:-$(security find-identity -v -p codesigning 2>/dev/null | awk -F'"' '/Apple Development/ {print $2; exit}')}"
[[ -n "$IDENTITY" ]] && codesign --force --sign "$IDENTITY" "$DMG"

if [[ -n "$DEVID" && -n "${NOTARY_PROFILE:-}" ]]; then
  echo "Notarizing (this can take a few minutes)…"
  xcrun notarytool submit "$DMG" --keychain-profile "$NOTARY_PROFILE" --wait
  xcrun stapler staple "$DMG"
  echo "Notarized and stapled: ready for public download."
elif [[ -n "$DEVID" ]]; then
  echo "Signed with Developer ID but NOT notarized — set NOTARY_PROFILE to notarize."
else
  echo "WARNING: no Developer ID certificate — this DMG works on your Macs, but Gatekeeper will block it for downloaders."
fi
echo "Created $DMG ($(du -h "$DMG" | cut -f1))"
