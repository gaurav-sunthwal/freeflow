#!/bin/zsh
# Builds FreeFlow.app into ./dist. Usage: ./build.sh [--install]
set -euo pipefail
cd "$(dirname "$0")"

swift build -c release
BIN="$(swift build -c release --show-bin-path)/FreeFlow"
APP="dist/FreeFlow.app"

rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BIN" "$APP/Contents/MacOS/FreeFlow"
cp Resources/Info.plist "$APP/Contents/Info.plist"
cp Resources/AppIcon.icns "$APP/Contents/Resources/AppIcon.icns"

# Use a stable signing identity if one exists so macOS keeps permissions across rebuilds;
# otherwise fall back to ad-hoc signing.
IDENTITY="${FREEFLOW_SIGN_IDENTITY:-$(security find-identity -v -p codesigning 2>/dev/null | awk -F'"' '/Apple Development|Developer ID/ {print $2; exit}')}"
KEYCHAIN_ARGS=()
[[ -n "${FREEFLOW_SIGN_KEYCHAIN:-}" ]] && KEYCHAIN_ARGS=(--keychain "$FREEFLOW_SIGN_KEYCHAIN")
codesign --force --deep --options runtime --entitlements Resources/FreeFlow.entitlements \
  "${KEYCHAIN_ARGS[@]}" --sign "${IDENTITY:--}" "$APP"
echo "Built $APP (signed with: ${IDENTITY:-ad-hoc})"

if [[ "${1:-}" == "--install" ]]; then
  pkill -x FreeFlow || true
  rm -rf /Applications/FreeFlow.app
  cp -R "$APP" /Applications/
  open /Applications/FreeFlow.app
  echo "Installed to /Applications/FreeFlow.app"
fi
