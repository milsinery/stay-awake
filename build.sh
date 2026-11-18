#!/bin/zsh
# Builds Stay Awake.app with xcodebuild and copies it to ~/Applications.
# The app and its root helper have to live in one signed bundle, so the Xcode project is the build.
# Usage: ./build.sh [Debug|Release]
set -euo pipefail

cd "$(dirname "$0")"
CONFIG="${1:-Debug}"
DERIVED="${DERIVED_DATA_PATH:-build}"

xcodebuild \
  -project StayAwake.xcodeproj \
  -scheme StayAwake \
  -configuration "$CONFIG" \
  -destination "generic/platform=macOS" \
  -derivedDataPath "$DERIVED" \
  build

APP="$DERIVED/Build/Products/$CONFIG/Stay Awake.app"
if [[ ! -d "$APP" ]]; then
  echo "Expected app at $APP" >&2
  exit 1
fi

mkdir -p "$HOME/Applications"
rm -rf "$HOME/Applications/Stay Awake.app"
cp -R "$APP" "$HOME/Applications/Stay Awake.app"
echo "Built $HOME/Applications/Stay Awake.app"
