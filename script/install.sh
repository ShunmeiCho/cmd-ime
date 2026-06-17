#!/usr/bin/env bash
set -euo pipefail

APP_NAME="CmdIME"
REPO="ShunmeiCho/cmd-ime"
resolve_latest_version() {
  local url
  url="$(curl -fsSLI -o /dev/null -w '%{url_effective}' "https://github.com/$REPO/releases/latest" 2>/dev/null)" || return 1
  printf '%s' "${url##*/v}"
}
VERSION="${CMDIME_VERSION:-$(resolve_latest_version || true)}"
if [[ -z "$VERSION" ]]; then
  echo "error: could not resolve the latest CmdIME release; set CMDIME_VERSION." >&2
  exit 1
fi
INSTALL_DIR="${CMDIME_INSTALL_DIR:-/Applications}"
BIN_DIR="${CMDIME_BIN_DIR:-$HOME/.local/bin}"
OPEN_APP="${CMDIME_OPEN:-1}"
ZIP_URL="${CMDIME_ZIP_URL:-https://github.com/$REPO/releases/download/v$VERSION/$APP_NAME-$VERSION.zip}"
EXPECTED_SHA256="${CMDIME_SHA256:-}"

if [[ "$(uname -s)" != "Darwin" ]]; then
  echo "CmdIME installer supports macOS only." >&2
  exit 1
fi

mkdir -p "$INSTALL_DIR" 2>/dev/null || true
if [[ ! -d "$INSTALL_DIR" || ! -w "$INSTALL_DIR" ]]; then
  INSTALL_DIR="$HOME/Applications"
fi

TMP_DIR="$(mktemp -d)"
cleanup() {
  rm -rf "$TMP_DIR"
}
trap cleanup EXIT

ZIP_PATH="$TMP_DIR/$APP_NAME.zip"
APP_SOURCE="$TMP_DIR/$APP_NAME.app"
APP_TARGET="$INSTALL_DIR/$APP_NAME.app"

echo "Downloading $APP_NAME $VERSION..."
curl -fsSL "$ZIP_URL" -o "$ZIP_PATH"

ACTUAL_SHA256="$(shasum -a 256 "$ZIP_PATH" | awk '{print $1}')"
if [[ -n "$EXPECTED_SHA256" ]]; then
  if [[ "$ACTUAL_SHA256" != "$EXPECTED_SHA256" ]]; then
    echo "error: checksum mismatch for $APP_NAME $VERSION." >&2
    echo "  expected: $EXPECTED_SHA256" >&2
    echo "  actual:   $ACTUAL_SHA256" >&2
    echo "Refusing to install a tampered or corrupted download." >&2
    exit 1
  fi
  echo "Checksum verified ($ACTUAL_SHA256)."
else
  echo "warning: no checksum to verify against (set CMDIME_SHA256 to enable)." >&2
  echo "Downloaded sha256: $ACTUAL_SHA256" >&2
  echo "Compare it with the value published in the release notes before trusting this install." >&2
fi

echo "Expanding app bundle..."
ditto -x -k "$ZIP_PATH" "$TMP_DIR"

if [[ ! -d "$APP_SOURCE" ]]; then
  echo "Downloaded archive did not contain $APP_NAME.app." >&2
  exit 1
fi

echo "Stopping any running $APP_NAME instance..."
pkill -x "$APP_NAME" >/dev/null 2>&1 || true

rm -rf "$APP_TARGET"
ditto "$APP_SOURCE" "$APP_TARGET"

mkdir -p "$BIN_DIR"
ln -sf "$APP_TARGET/Contents/Resources/keyboardctl" "$BIN_DIR/keyboardctl"

echo "Installed $APP_TARGET"
echo "Linked keyboardctl at $BIN_DIR/keyboardctl"

if [[ ":$PATH:" != *":$BIN_DIR:"* ]]; then
  echo "Add $BIN_DIR to PATH to use keyboardctl from any shell."
fi

if [[ "$OPEN_APP" != "0" ]]; then
  open "$APP_TARGET"
  echo "Opened $APP_NAME. Grant Accessibility and Input Monitoring when prompted."
fi
