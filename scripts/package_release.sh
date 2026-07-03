#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
APP_NAME="InfraCanvas"
SCHEME="InfraCanvas"
CONFIGURATION="Release"
DERIVED_DATA_PATH="$ROOT_DIR/.build/XcodeDerivedData"
DIST_DIR="$ROOT_DIR/dist"
APP_PATH="$DERIVED_DATA_PATH/Build/Products/$CONFIGURATION/$APP_NAME.app"
DMG_STAGING="$DIST_DIR/dmg-staging"
VERSION="${1:-0.1.0}"
DMG_PATH="$DIST_DIR/$APP_NAME-$VERSION.dmg"

cd "$ROOT_DIR"

mkdir -p "$DIST_DIR"

xcodebuild \
  -project "$APP_NAME.xcodeproj" \
  -scheme "$SCHEME" \
  -configuration "$CONFIGURATION" \
  -derivedDataPath "$DERIVED_DATA_PATH" \
  -destination "platform=macOS" \
  build

if [[ ! -d "$APP_PATH" ]]; then
  echo "Expected app was not built at: $APP_PATH" >&2
  exit 1
fi

rm -rf "$DMG_STAGING"
mkdir -p "$DMG_STAGING"
cp -R "$APP_PATH" "$DMG_STAGING/"
ln -s /Applications "$DMG_STAGING/Applications"

rm -f "$DMG_PATH"
hdiutil create \
  -volname "$APP_NAME" \
  -srcfolder "$DMG_STAGING" \
  -ov \
  -format UDZO \
  "$DMG_PATH"

echo "Created $DMG_PATH"
