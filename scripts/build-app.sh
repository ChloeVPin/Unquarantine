#!/bin/bash
# Build a universal app for Apple silicon and Intel.

set -euo pipefail
cd "$(dirname "$0")/.."

APP_NAME="Unquarantine"
APP_VERSION="${APP_VERSION:-0.1.0}"
BUILD_ROOT=".build/universal"
APP_DIR="dist/${APP_NAME}.app"
ICON_NAME="unq"
ICON_SOURCE="Sources/Unquarantine/Resources/${ICON_NAME}.icon"
ICON_PARTIAL_PLIST="$BUILD_ROOT/${ICON_NAME}-icon-partial.plist"
MINIMUM_MACOS="26.0"

if [[ ! "$APP_VERSION" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
	echo "error: app version must use major.minor.patch format, such as 0.1.0" >&2
	exit 1
fi

echo "==> swift build"
SDK_VERSION="$(xcrun --sdk macosx --show-sdk-version)"
if [[ "${SDK_VERSION%%.*}" != "27" ]]; then
	echo "error: expected macOS 27 SDK, found ${SDK_VERSION}" >&2
	exit 1
fi
echo "==> using macOS SDK $SDK_VERSION"
SDK_PATH="$(xcrun --sdk macosx --show-sdk-path)"

echo "==> build arm64 and x86_64 executables"
for ARCHITECTURE in arm64 x86_64; do
	TRIPLE="${ARCHITECTURE}-apple-macosx${MINIMUM_MACOS}"
	SCRATCH_PATH="${BUILD_ROOT}/${ARCHITECTURE}"
	echo "==> swift build ${TRIPLE}"
	swift build \
		-c release \
		--triple "$TRIPLE" \
		--sdk "$SDK_PATH" \
		--scratch-path "$SCRATCH_PATH"
done

echo "==> assemble bundle at $APP_DIR"
rm -rf "$APP_DIR"
mkdir -p "$APP_DIR/Contents/MacOS" "$APP_DIR/Contents/Resources"

APP_ARM64="${BUILD_ROOT}/arm64/release/Unquarantine"
APP_X86_64="${BUILD_ROOT}/x86_64/release/Unquarantine"
WATCHER_ARM64="${BUILD_ROOT}/arm64/release/UnquarantineWatcher"
WATCHER_X86_64="${BUILD_ROOT}/x86_64/release/UnquarantineWatcher"

for BINARY in "$APP_ARM64" "$APP_X86_64" "$WATCHER_ARM64" "$WATCHER_X86_64"; do
	if [[ ! -s "$BINARY" ]]; then
		echo "error: expected build product was not created: $BINARY" >&2
		exit 1
	fi
done

lipo -create "$APP_ARM64" "$APP_X86_64" \
	-output "$APP_DIR/Contents/MacOS/$APP_NAME"
lipo -create "$WATCHER_ARM64" "$WATCHER_X86_64" \
	-output "$APP_DIR/Contents/Resources/UnquarantineWatcher"

for BINARY in \
	"$APP_DIR/Contents/MacOS/$APP_NAME" \
	"$APP_DIR/Contents/Resources/UnquarantineWatcher"; do
	ARCHITECTURES="$(lipo -archs "$BINARY")"
	if [[ "$ARCHITECTURES" != *arm64* || "$ARCHITECTURES" != *x86_64* ]]; then
		echo "error: $BINARY is missing a required architecture: $ARCHITECTURES" >&2
		exit 1
	fi
done

cat > "$APP_DIR/Contents/Info.plist" <<PLIST
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
	<string>${APP_VERSION}</string>
	<key>CFBundleVersion</key>
	<string>1</string>
	<key>LSMinimumSystemVersion</key>
	<string>26.0</string>
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
  --minimum-deployment-target "$MINIMUM_MACOS" \
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

echo "==> universal app architectures: $(lipo -archs "$APP_DIR/Contents/MacOS/$APP_NAME")"
echo "==> done: $APP_DIR"
