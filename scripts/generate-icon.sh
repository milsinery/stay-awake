#!/bin/zsh
# Draws AppIcon.icns into the built app. make-icon.swift needs AppKit, so this runs on macOS only.
set -euo pipefail

ICONSET="${TEMP_DIR:-/tmp}/StayAwake.iconset"
rm -rf "$ICONSET"
mkdir -p "$ICONSET"
xcrun swift "${SRCROOT}/make-icon.swift" "$ICONSET/icon_512x512@2x.png"
for size in 16 32 128 256 512; do
  sips -z "$size" "$size" "$ICONSET/icon_512x512@2x.png" --out "$ICONSET/icon_${size}x${size}.png" >/dev/null
  sips -z $((size * 2)) $((size * 2)) "$ICONSET/icon_512x512@2x.png" --out "$ICONSET/icon_${size}x${size}@2x.png" >/dev/null
done
DEST="${TARGET_BUILD_DIR}/${UNLOCALIZED_RESOURCES_FOLDER_PATH}"
mkdir -p "$DEST"
iconutil -c icns "$ICONSET" -o "$DEST/AppIcon.icns"
