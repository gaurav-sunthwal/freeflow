#!/bin/bash
# FreeFlow installer — builds the app from source and puts it in your Applications folder.
#
#   From a clone:   ./install.sh
#   One-liner:      curl -fsSL https://raw.githubusercontent.com/gaurav-sunthwal/freeflow/main/install.sh | bash
#
# The installed app is self-contained: once this finishes you can delete the source folder.
#
# Used by FreeFlow's built-in updater:
#   FREEFLOW_REF=v1.2.0        build that tag/branch instead of main
#   FREEFLOW_STAGE_DIR=/path   only build, copy FreeFlow.app there, and don't install or launch
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
  git clone --depth 1 --quiet ${FREEFLOW_REF:+--branch "$FREEFLOW_REF"} "$REPO_URL" "$SRC"
fi

# --- Signing ---------------------------------------------------------------
# macOS ties Microphone/Accessibility permissions to an app's code signature. Without a developer
# certificate every rebuild looks like a brand-new app and permissions are lost on each update, so we
# create a permanent local signing certificate once per Mac and reuse it for every build.
has_dev_identity() {
  security find-identity -v -p codesigning 2>/dev/null | grep -qE "Developer ID Application|Apple Development"
}
if [[ -z "${FREEFLOW_SIGN_IDENTITY:-}" ]] && ! has_dev_identity; then
  SIGN_DIR="$HOME/Library/Application Support/FreeFlow/signing"
  KEYCHAIN="$SIGN_DIR/freeflow-signing.keychain-db"
  mkdir -p "$SIGN_DIR"; chmod 700 "$SIGN_DIR"
  if [[ ! -f "$KEYCHAIN" || ! -f "$SIGN_DIR/identity" ]]; then
    step "Creating a local signing certificate (one time, keeps permissions across updates)…"
    rm -f "$KEYCHAIN"
    WORK="$(mktemp -d)"
    openssl rand -hex 24 > "$SIGN_DIR/keychain-password"; chmod 600 "$SIGN_DIR/keychain-password"
    cat > "$WORK/cert.cnf" <<'CNF'
[req]
distinguished_name = dn
x509_extensions = ext
prompt = no
[dn]
CN = FreeFlow Local Signing
[ext]
basicConstraints = critical,CA:false
keyUsage = critical,digitalSignature
extendedKeyUsage = critical,codeSigning
CNF
    openssl req -x509 -newkey rsa:2048 -nodes -keyout "$WORK/key.pem" -out "$WORK/cert.pem" \
      -days 7300 -config "$WORK/cert.cnf" 2>/dev/null
    openssl pkcs12 -export -inkey "$WORK/key.pem" -in "$WORK/cert.pem" -out "$WORK/id.p12" \
      -passout pass:freeflow -name "FreeFlow Local Signing" 2>/dev/null
    KC_PASS="$(cat "$SIGN_DIR/keychain-password")"
    security create-keychain -p "$KC_PASS" "$KEYCHAIN"
    security set-keychain-settings "$KEYCHAIN"   # never auto-lock
    security unlock-keychain -p "$KC_PASS" "$KEYCHAIN"
    security import "$WORK/id.p12" -k "$KEYCHAIN" -P freeflow -T /usr/bin/codesign >/dev/null
    security set-key-partition-list -S apple-tool:,apple: -k "$KC_PASS" "$KEYCHAIN" >/dev/null 2>&1
    openssl x509 -in "$WORK/cert.pem" -noout -fingerprint -sha1 | cut -d= -f2 | tr -d : > "$SIGN_DIR/identity"
    rm -rf "$WORK"
  fi
  security unlock-keychain -p "$(cat "$SIGN_DIR/keychain-password")" "$KEYCHAIN"
  export FREEFLOW_SIGN_IDENTITY="$(cat "$SIGN_DIR/identity")"
  export FREEFLOW_SIGN_KEYCHAIN="$KEYCHAIN"
fi

# --- Build -----------------------------------------------------------------
step "Building FreeFlow (first build takes a minute)…"
"$SRC/build.sh" >/dev/null 2>"$SRC/.build-errors.log" || { cat "$SRC/.build-errors.log" >&2; fail "Build failed."; }
APP_SRC="$SRC/dist/FreeFlow.app"
[[ -d "$APP_SRC" ]] || fail "Build did not produce FreeFlow.app."

if [[ -n "${FREEFLOW_STAGE_DIR:-}" ]]; then
  mkdir -p "$FREEFLOW_STAGE_DIR"
  rm -rf "$FREEFLOW_STAGE_DIR/FreeFlow.app"
  ditto "$APP_SRC" "$FREEFLOW_STAGE_DIR/FreeFlow.app"
  echo "Staged $FREEFLOW_STAGE_DIR/FreeFlow.app"
  exit 0
fi

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
