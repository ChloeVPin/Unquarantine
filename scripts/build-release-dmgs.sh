#!/bin/bash
# Package architecture-specific release installers from the universal app.

set -euo pipefail
cd "$(dirname "$0")/.."

APP_NAME="Unquarantine"
VERSION="${1:-0.1.0}"
MINIMUM_MACOS="26.0"
APP_SOURCE="dist/${APP_NAME}.app"
OUTPUT_DIR="dist/releases"
STAGING_ROOT=".build/release-staging"

if [[ ! "$VERSION" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
	echo "error: version must use major.minor.patch format, such as 0.1.0" >&2
	exit 1
fi

echo "==> build universal app for $VERSION"
APP_VERSION="$VERSION" ./scripts/build-app.sh

if [[ ! -d "$APP_SOURCE" ]]; then
	echo "error: app bundle was not created: $APP_SOURCE" >&2
	exit 1
fi

mkdir -p "$OUTPUT_DIR" "$STAGING_ROOT"

for ARCHITECTURE in arm64 x86_64; do
	if ! lipo -archs "$APP_SOURCE/Contents/MacOS/$APP_NAME" | grep -q "$ARCHITECTURE"; then
		echo "error: universal app is missing $ARCHITECTURE" >&2
		exit 1
	fi

	if [[ "$ARCHITECTURE" == "arm64" ]]; then
		ARCH_LABEL="AppleSilicon"
		VOLUME_NAME="Unquarantine ${VERSION} Apple silicon"
	else
		ARCH_LABEL="Intel"
		VOLUME_NAME="Unquarantine ${VERSION} Intel"
	fi

	STAGING_DIR="${STAGING_ROOT}/${ARCH_LABEL}"
	STAGED_APP="${STAGING_DIR}/${APP_NAME}.app"
	DMG_PATH="${OUTPUT_DIR}/${APP_NAME}-${VERSION}-${ARCH_LABEL}.dmg"
	echo "==> stage $ARCH_LABEL app"
	rm -rf "$STAGING_DIR"
	mkdir -p "$STAGING_DIR"
	ditto "$APP_SOURCE" "$STAGED_APP"

	for BINARY in \
		"$STAGED_APP/Contents/MacOS/$APP_NAME" \
		"$STAGED_APP/Contents/Resources/UnquarantineWatcher"; do
		if [[ ! -s "$BINARY" ]]; then
			echo "error: missing executable: $BINARY" >&2
			exit 1
		fi
		THIN_BINARY="${BINARY}.thin"
		lipo -thin "$ARCHITECTURE" "$BINARY" -output "$THIN_BINARY"
		chmod 755 "$THIN_BINARY"
		mv "$THIN_BINARY" "$BINARY"
	done

	if [[ "$(lipo -archs "$STAGED_APP/Contents/MacOS/$APP_NAME")" != "$ARCHITECTURE" ]]; then
		echo "error: app did not thin to $ARCHITECTURE" >&2
		exit 1
	fi
	if [[ "$(lipo -archs "$STAGED_APP/Contents/Resources/UnquarantineWatcher")" != "$ARCHITECTURE" ]]; then
		echo "error: watcher did not thin to $ARCHITECTURE" >&2
		exit 1
	fi

	/usr/libexec/PlistBuddy -c "Set :LSMinimumSystemVersion ${MINIMUM_MACOS}" "$STAGED_APP/Contents/Info.plist"
	codesign --force --sign - --options runtime \
		"$STAGED_APP/Contents/Resources/UnquarantineWatcher" >/dev/null
	codesign --force --sign - --options runtime "$STAGED_APP" >/dev/null
	codesign --verify --deep --strict "$STAGED_APP"

	ln -s /Applications "$STAGING_DIR/Applications"
	rm -f "$DMG_PATH"
	echo "==> create compressed disk image $DMG_PATH"
	diskutil image create from \
		--format UDZO \
		--volumeName "$VOLUME_NAME" \
		"$STAGING_DIR" \
		"$DMG_PATH" >/dev/null

	MOUNT_OUTPUT="$(diskutil image attach --readOnly --nobrowse "$DMG_PATH")"
	MOUNT_POINT="$(printf '%s\n' "$MOUNT_OUTPUT" | awk -F '\t' '$NF ~ /\/Volumes\// {print $NF; exit}')"
	if [[ -z "$MOUNT_POINT" ]]; then
		echo "error: could not mount $DMG_PATH for verification" >&2
		exit 1
	fi
	if [[ ! -d "$MOUNT_POINT/${APP_NAME}.app" || ! -L "$MOUNT_POINT/Applications" ]]; then
		diskutil eject "$MOUNT_POINT" >/dev/null
		echo "error: disk image is missing the app or Applications shortcut" >&2
		exit 1
	fi
	diskutil eject "$MOUNT_POINT" >/dev/null
	hdiutil verify "$DMG_PATH" >/dev/null
	shasum -a 256 "$DMG_PATH"
done

(
	cd "$OUTPUT_DIR"
	shasum -a 256 \
		"${APP_NAME}-${VERSION}-AppleSilicon.dmg" \
		"${APP_NAME}-${VERSION}-Intel.dmg" \
		> "SHA256SUMS-${VERSION}.txt"
)

echo "==> installers created in $OUTPUT_DIR"
