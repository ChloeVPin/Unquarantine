#!/bin/bash
# Build the Swift executables and assemble dist/Unquarantine.app.

set -euo pipefail
cd "$(dirname "$0")/.."

APP_NAME="Unquarantine"
BUILD_DIR=".build"
APP_DIR="dist/${APP_NAME}.app"
ICON_NAME="unq"
ICON_SOURCE="Sources/Unquarantine/Resources/${ICON_NAME}.icon"
ICON_PARTIAL_PLIST="$BUILD_DIR/${ICON_NAME}-icon-partial.plist"

echo "==> swift build"
SDK_VERSION="$(xcrun --sdk macosx --show-sdk-version)"
if [[ "${SDK_VERSION%%.*}" != "27" ]]; then
	echo "error: expected macOS 27 SDK, found ${SDK_VERSION}" >&2
	exit 1
fi
echo "==> using macOS SDK $SDK_VERSION"
swift build -c release --build-path "$BUILD_DIR"

BIN_APP="$BUILD_DIR/release/Unquarantine"
BIN_WATCHER="$BUILD_DIR/release/UnquarantineWatcher"

echo "==> assemble bundle at $APP_DIR"
rm -rf "$APP_DIR"
mkdir -p "$APP_DIR/Contents/MacOS" "$APP_DIR/Contents/Resources"

cp "$BIN_APP" "$APP_DIR/Contents/MacOS/$APP_NAME"
cp "$BIN_WATCHER" "$APP_DIR/Contents/Resources/UnquarantineWatcher"

cat > "$APP_DIR/Contents/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
	<key>CFBundleDevelopmentRegion</key>
	<string>en</string>
	<key>CFBundleDisplayName</key>
	<string>Unquarantine</string>
	<key>CFBundleExecutable</key>
	<string>Unquarantine</string>
	<key>CFBundleIdentifier</key>
	<string>tools.unquarantine.app</string>
	<key>CFBundleInfoDictionaryVersion</key>
	<string>6.0</string>
	<key>CFBundleName</key>
	<string>Unquarantine</string>
	<key>CFBundlePackageType</key>
	<string>APPL</string>
	<key>CFBundleShortVersionString</key>
	<string>1.0</string>
	<key>CFBundleVersion</key>
	<string>1</string>
	<key>LSMinimumSystemVersion</key>
	<string>27.0</string>
	<key>NSHighResolutionCapable</key>
	<true/>
	<key>NSSupportsAutomaticGraphicsSwitching</key>
	<true/>
</dict>
</plist>
PLIST

echo "==> compile Icon Composer app icon"
xcrun actool \
  --compile "$APP_DIR/Contents/Resources" \
  --platform macosx \
  --minimum-deployment-target 27.0 \
  --target-device mac \
  --app-icon "$ICON_NAME" \
  --output-format human-readable-text \
  --output-partial-info-plist "$ICON_PARTIAL_PLIST" \
  --errors --warnings --notices \
  "$ICON_SOURCE"

if [[ ! -s "$APP_DIR/Contents/Resources/Assets.car" || ! -s "$ICON_PARTIAL_PLIST" ]]; then
	echo "error: actool did not produce the compiled icon assets" >&2
	exit 1
fi
/usr/libexec/PlistBuddy -c "Merge $ICON_PARTIAL_PLIST" "$APP_DIR/Contents/Info.plist"

echo "==> ad-hoc codesign"
codesign --force --sign - --options runtime \
  "$APP_DIR" >/dev/null

echo "==> done: $APP_DIR"
