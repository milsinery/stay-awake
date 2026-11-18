#!/bin/zsh
# Archive, Developer ID export, notarize, staple, and wrap a drag-to-Applications disk image.
# Run on a Mac with Xcode, the Developer ID Application certificate for team CA23Z5CN46,
# and a notarytool keychain profile named stay-awake-notary. Do not pass passwords on the command line.
set -euo pipefail

cd "$(dirname "$0")/.."
PROFILE="${NOTARY_KEYCHAIN_PROFILE:-stay-awake-notary}"
ARCHIVE="$PWD/build/StayAwake.xcarchive"
EXPORT="$PWD/build/export"
APP="$EXPORT/Stay Awake.app"
ZIP="$PWD/build/StayAwake.zip"
DMG="$PWD/build/StayAwake.dmg"

if ! xcrun notarytool history --keychain-profile "$PROFILE" >/dev/null 2>&1; then
  echo "Store notary credentials once, then run this script again:" >&2
  echo "  xcrun notarytool store-credentials \"$PROFILE\" --apple-id \"APPLE_ID_EMAIL\" --team-id \"CA23Z5CN46\" --password \"APP_SPECIFIC_PASSWORD\"" >&2
  exit 1
fi

xcodebuild \
  -project StayAwake.xcodeproj \
  -scheme StayAwake \
  -configuration Release \
  -destination "generic/platform=macOS" \
  -archivePath "$ARCHIVE" \
  archive

xcodebuild \
  -exportArchive \
  -archivePath "$ARCHIVE" \
  -exportPath "$EXPORT" \
  -exportOptionsPlist Distribution/ExportOptions.plist

codesign --verify --deep --strict --verbose=2 "$APP"
codesign -dv --verbose=4 "$APP"
codesign -dv --verbose=4 "$APP/Contents/MacOS/StayAwakeDaemon"
test -f "$APP/Contents/Library/LaunchDaemons/com.milsinery.stay-awake.daemon.plist"

identifier_of() {
  codesign -dv "$1" 2>&1 | sed -n 's/^Identifier=//p'
}
APP_ID="$(identifier_of "$APP")"
DAEMON_ID="$(identifier_of "$APP/Contents/MacOS/StayAwakeDaemon")"
[[ "$APP_ID" == "com.milsinery.stay-awake" ]] || { echo "App identifier is '$APP_ID', expected com.milsinery.stay-awake" >&2; exit 1; }
[[ "$DAEMON_ID" == "com.milsinery.stay-awake.daemon" ]] || { echo "Helper identifier is '$DAEMON_ID', expected com.milsinery.stay-awake.daemon" >&2; exit 1; }

ditto -c -k --keepParent "$APP" "$ZIP"
xcrun notarytool submit "$ZIP" --keychain-profile "$PROFILE" --wait
xcrun stapler staple "$APP"
xcrun stapler validate "$APP"
spctl --assess --type execute --verbose=4 "$APP"

STAGE="$(mktemp -d)"
cp -R "$APP" "$STAGE/Stay Awake.app"
ln -s /Applications "$STAGE/Applications"
hdiutil create -volname "Stay Awake" -srcfolder "$STAGE" -ov -format UDZO "$DMG"
rm -rf "$STAGE"
codesign --force --sign "Developer ID Application" --timestamp "$DMG"
xcrun notarytool submit "$DMG" --keychain-profile "$PROFILE" --wait
xcrun stapler staple "$DMG"
xcrun stapler validate "$DMG"
spctl --assess --type open --verbose=4 "$DMG"
echo "Disk image: $DMG"
