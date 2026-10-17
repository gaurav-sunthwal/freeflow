#!/bin/bash
# Removes FreeFlow from this Mac.
#
#   ./uninstall.sh            remove the app, keep your history, dictionary and settings
#   ./uninstall.sh --purge    also delete history, dictionary, snippets, settings and permissions
#
# One-liner: curl -fsSL https://raw.githubusercontent.com/gaurav-sunthwal/freeflow/main/uninstall.sh | bash -s -- --purge
set -euo pipefail

BUNDLE_ID="app.freeflow.FreeFlow"
PURGE=0
[[ "${1:-}" == "--purge" ]] && PURGE=1

if pgrep -x FreeFlow >/dev/null; then
  echo "==> Quitting FreeFlow…"
  pkill -x FreeFlow || true
  sleep 1
fi

removed=0
for app in "/Applications/FreeFlow.app" "$HOME/Applications/FreeFlow.app"; do
  if [[ -d "$app" ]]; then
    echo "==> Removing $app"
    rm -rf "$app"
    removed=1
  fi
done
[[ $removed == 1 ]] || echo "FreeFlow.app was not found in Applications."

if [[ $PURGE == 1 ]]; then
  echo "==> Deleting history, dictionary, snippets and settings…"
  rm -rf "$HOME/Library/Application Support/FreeFlow"
  defaults delete "$BUNDLE_ID" >/dev/null 2>&1 || true
  rm -f "$HOME/Library/Preferences/$BUNDLE_ID.plist"
  echo "==> Resetting permissions…"
  tccutil reset All "$BUNDLE_ID" >/dev/null 2>&1 || true
else
  echo "Kept your history and settings (run with --purge to delete them too)."
fi

echo "✅ FreeFlow has been uninstalled."
