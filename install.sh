#!/bin/bash
# FreeFlow installer — builds the app from source and puts it in your Applications folder.
#
#   From a clone:   ./install.sh
#   One-liner:      curl -fsSL https://raw.githubusercontent.com/gaurav-sunthwal/freeflow/main/install.sh | bash
#
# The installed app is self-contained: once this finishes you can delete the source folder.
set -euo pipefail

REPO_URL="https://github.com/gaurav-sunthwal/freeflow.git"
bold=$(tput bold 2>/dev/null || true); dim=$(tput dim 2>/dev/null || true); reset=$(tput sgr0 2>/dev/null || true)
step() { echo "${bold}==>${reset} $*"; }
fail() { echo "❌ $*" >&2; exit 1; }

# --- Requirements ----------------------------------------------------------
[[ "$(uname)" == "Darwin" ]] || fail "FreeFlow only runs on macOS."
[[ "$(uname -m)" == "arm64" ]] || fail "FreeFlow needs a Mac with Apple silicon (M1 or newer)."
MACOS_MAJOR=$(sw_vers -productVersion | cut -d. -f1)
(( MACOS_MAJOR >= 26 )) || fail "FreeFlow needs macOS 26 or later (you have $(sw_vers -productVersion))."

if ! xcrun --find swift >/dev/null 2>&1; then
  echo "FreeFlow is built from source and needs Apple's free developer tools."
  echo "A window will open to install them — run this installer again when it finishes."
  xcode-select --install >/dev/null 2>&1 || true
  exit 1
fi
SDK=$(xcrun --sdk macosx --show-sdk-path 2>/dev/null || true)
[[ -d "$SDK/System/Library/Frameworks/FoundationModels.framework" ]] || \
  fail "Your developer tools are too old. Update Xcode or the Command Line Tools to version 26 or later (Software Update), then try again."

# --- Get the source --------------------------------------------------------
SCRIPT_DIR=""
if [[ -n "${BASH_SOURCE[0]:-}" && -f "${BASH_SOURCE[0]}" ]]; then
  SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
fi
if [[ -n "$SCRIPT_DIR" && -f "$SCRIPT_DIR/Package.swift" && -d "$SCRIPT_DIR/Sources/FreeFlow" ]]; then
  SRC="$SCRIPT_DIR"
else
  command -v git >/dev/null || fail "git is required."
  SRC="$(mktemp -d)/freeflow"
  trap 'rm -rf "$(dirname "$SRC")"' EXIT
  step "Downloading FreeFlow…"
  git clone --depth 1 --quiet "$REPO_URL" "$SRC"
fi

# --- Build -----------------------------------------------------------------
step "Building FreeFlow (first build takes a minute)…"
"$SRC/build.sh" >/dev/null 2>"$SRC/.build-errors.log" || { cat "$SRC/.build-errors.log" >&2; fail "Build failed."; }
APP_SRC="$SRC/dist/FreeFlow.app"
[[ -d "$APP_SRC" ]] || fail "Build did not produce FreeFlow.app."

# --- Install ---------------------------------------------------------------
DEST_DIR="/Applications"
[[ -w "$DEST_DIR" ]] || { DEST_DIR="$HOME/Applications"; mkdir -p "$DEST_DIR"; }
DEST="$DEST_DIR/FreeFlow.app"

if pgrep -x FreeFlow >/dev/null; then
  step "Quitting the running copy of FreeFlow…"
  pkill -x FreeFlow || true
  sleep 1
fi
step "Installing to ${DEST}…"
rm -rf "$DEST"
ditto "$APP_SRC" "$DEST"
xattr -dr com.apple.quarantine "$DEST" 2>/dev/null || true

open "$DEST"

cat <<EOF

${bold}✅ FreeFlow is installed and running${reset} — look for the waveform icon in your menu bar.

  1. Grant ${bold}Microphone${reset}, ${bold}Accessibility${reset} and ${bold}Speech Recognition${reset} in the Setup window.
  2. System Settings → Keyboard → "Press 🌐 key to" → ${bold}Do Nothing${reset}.
  3. Click into any text box, ${bold}hold fn${reset}, speak, and let go.

${dim}Tip: turn on "Launch FreeFlow at login" in FreeFlow → Settings.
The app no longer needs the source folder — you can delete it.
To uninstall later: curl -fsSL https://raw.githubusercontent.com/gaurav-sunthwal/freeflow/main/uninstall.sh | bash${reset}
EOF
