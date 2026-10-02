#!/usr/bin/env bash
set -euo pipefail

MODE="${1:-run}"
APP_NAME="CmdIME"
BUNDLE_ID="com.shunmei.cmd-ime"
VERSION="${VERSION:-$(cat "$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)/VERSION")}"
MIN_SYSTEM_VERSION="13.0"

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
DIST_DIR="$ROOT_DIR/dist"
APP_BUNDLE="$DIST_DIR/$APP_NAME.app"
APP_CONTENTS="$APP_BUNDLE/Contents"
APP_MACOS="$APP_CONTENTS/MacOS"
APP_RESOURCES="$APP_CONTENTS/Resources"
APP_BINARY="$APP_MACOS/$APP_NAME"
INFO_PLIST="$APP_CONTENTS/Info.plist"
ICON_SOURCE="$ROOT_DIR/Assets/AppIcon.icns"

default_codesign_identity() {
  if [[ -n "${CODESIGN_IDENTITY:-}" ]]; then
    printf "%s" "$CODESIGN_IDENTITY"
    return
  fi

  security find-identity -p codesigning -v 2>/dev/null \
    | awk -F'"' '/"Apple Development:|"Developer ID Application:/{print $2; exit}'
}

CODESIGN_IDENTITY="$(default_codesign_identity)"
CODESIGN_IDENTITY="${CODESIGN_IDENTITY:--}"

pkill -x "$APP_NAME" >/dev/null 2>&1 || true

# See script/package_app.sh: record the real SDK version so macOS does not fall back to its
# macOS 13 compatibility appearance. MIN_MACOS must match the platform in Package.swift.
MIN_MACOS="13.0"
SDK_VERSION="$(xcrun --sdk macosx --show-sdk-version)"
swift build --product "$APP_NAME" \
  -Xlinker -platform_version -Xlinker macos -Xlinker "$MIN_MACOS" -Xlinker "$SDK_VERSION"
swift build --product keyboardctl \
  -Xlinker -platform_version -Xlinker macos -Xlinker "$MIN_MACOS" -Xlinker "$SDK_VERSION"
BUILD_BINARY="$(swift build --show-bin-path)/$APP_NAME"

rm -rf "$APP_BUNDLE"
mkdir -p "$APP_MACOS" "$APP_RESOURCES"
cp "$BUILD_BINARY" "$APP_BINARY"
# The settings window lists input sources through this helper (fresh process, no stale TIS list).
cp "$(dirname "$BUILD_BINARY")/keyboardctl" "$APP_MACOS/keyboardctl"
chmod +x "$APP_BINARY"
if [[ -f "$ICON_SOURCE" ]]; then
  cp "$ICON_SOURCE" "$APP_RESOURCES/AppIcon.icns"
fi

# SwiftUI's default localization lookup uses Bundle.main, not Bundle.module.
# Compile catalogs into the assembled app before signing (also works with SwiftPM
# versions that merely copy .xcstrings into their resource bundle).
for catalog in "$ROOT_DIR"/Sources/CmdIME/Resources/*.xcstrings; do
  xcrun xcstringstool compile "$catalog" --output-directory "$APP_RESOURCES"
done

cat >"$INFO_PLIST" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>CFBundleDevelopmentRegion</key>
  <string>en</string>
  <key>CFBundleLocalizations</key>
  <array>
    <string>en</string>
    <string>zh-Hans</string>
    <string>ja</string>
  </array>
  <key>CFBundleExecutable</key>
  <string>$APP_NAME</string>
  <key>CFBundleIdentifier</key>
  <string>$BUNDLE_ID</string>
  <key>CFBundleIconFile</key>
  <string>AppIcon</string>
  <key>CFBundleName</key>
  <string>$APP_NAME</string>
  <key>CFBundlePackageType</key>
  <string>APPL</string>
  <key>CFBundleShortVersionString</key>
  <string>$VERSION</string>
  <key>CFBundleVersion</key>
  <string>1</string>
  <key>LSApplicationCategoryType</key>
  <string>public.app-category.utilities</string>
  <key>LSUIElement</key>
  <true/>
  <key>LSMinimumSystemVersion</key>
  <string>$MIN_SYSTEM_VERSION</string>
  <key>NSHumanReadableCopyright</key>
  <string>Copyright © 2026 Shunmei Cho</string>
  <key>NSInputMonitoringUsageDescription</key>
  <string>CmdIME listens for your configured keyboard shortcuts to switch input sources.</string>
  <key>NSPrincipalClass</key>
  <string>NSApplication</string>
  <key>UTExportedTypeDeclarations</key>
  <array>
    <dict>
      <key>UTTypeIdentifier</key>
      <string>com.shunmei.cmd-ime.app-reference</string>
      <key>UTTypeDescription</key>
      <string>CmdIME app reference</string>
      <key>UTTypeConformsTo</key>
      <array>
        <string>public.data</string>
      </array>
    </dict>
    <dict>
      <key>UTTypeIdentifier</key>
      <string>com.shunmei.cmd-ime.app-rule</string>
      <key>UTTypeDescription</key>
      <string>CmdIME app rule</string>
      <key>UTTypeConformsTo</key>
      <array>
        <string>public.data</string>
      </array>
    </dict>
    <dict>
      <key>UTTypeIdentifier</key>
      <string>com.shunmei.cmd-ime.website-rule</string>
      <key>UTTypeDescription</key>
      <string>CmdIME website rule</string>
      <key>UTTypeConformsTo</key>
      <array>
        <string>public.data</string>
      </array>
    </dict>
  </array>
</dict>
</plist>
PLIST

codesign --force --deep --timestamp=none --sign "$CODESIGN_IDENTITY" "$APP_BUNDLE"

open_app() {
  /usr/bin/open -n "$APP_BUNDLE"
}

case "$MODE" in
  run)
    open_app
    ;;
  --debug|debug)
    lldb -- "$APP_BINARY"
    ;;
  --logs|logs)
    open_app
    /usr/bin/log stream --info --style compact --predicate "process == \"$APP_NAME\""
    ;;
  --telemetry|telemetry)
    open_app
    /usr/bin/log stream --info --style compact --predicate "subsystem == \"$BUNDLE_ID\""
    ;;
  --verify|verify)
    open_app
    sleep 1
    pgrep -x "$APP_NAME" >/dev/null
    ;;
  *)
    echo "usage: $0 [run|--debug|--logs|--telemetry|--verify]" >&2
    exit 2
    ;;
esac
