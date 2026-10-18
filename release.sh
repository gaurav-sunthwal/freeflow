#!/bin/bash
# Publishes a new FreeFlow version that installed apps pick up automatically.
#   ./release.sh 1.2.0 ["What's new in this release"]
set -euo pipefail
cd "$(dirname "$0")"

VERSION="${1:?Usage: ./release.sh <version> [notes]}"
VERSION="${VERSION#v}"
TAG="v$VERSION"
command -v gh >/dev/null || { echo "Install the GitHub CLI first: brew install gh && gh auth login"; exit 1; }
[[ -z "$(git status --porcelain)" ]] || { echo "Commit or stash your changes first."; exit 1; }
git rev-parse "$TAG" >/dev/null 2>&1 && { echo "$TAG already exists."; exit 1; }

PLIST=Resources/Info.plist
BUILD=$(( $(/usr/libexec/PlistBuddy -c 'Print :CFBundleVersion' "$PLIST") + 1 ))
/usr/libexec/PlistBuddy -c "Set :CFBundleShortVersionString $VERSION" -c "Set :CFBundleVersion $BUILD" "$PLIST"

echo "==> Checking that it builds…"
./build.sh >/dev/null

git add "$PLIST"
git commit -qm "Release $TAG"
git tag "$TAG"
git push -q origin HEAD "$TAG"
if [[ -n "${2:-}" ]]; then
  gh release create "$TAG" --title "FreeFlow $VERSION" --notes "$2"
else
  gh release create "$TAG" --title "FreeFlow $VERSION" --generate-notes
fi
echo "✅ Released $TAG — installed copies will update within a few hours."
