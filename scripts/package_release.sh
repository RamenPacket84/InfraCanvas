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
SIGNING_IDENTITY="${DEVELOPER_ID_APPLICATION:-}"
NOTARY_PROFILE="${NOTARYTOOL_PROFILE:-InfraCanvasNotary}"
NOTARIZE=0

usage() {
  cat <<USAGE
Usage: scripts/package_release.sh [version] [options]

Options:
  --signing-identity NAME   Developer ID Application identity to use.
                            Can also be set with DEVELOPER_ID_APPLICATION.
  --notarize                Submit the DMG to Apple, staple the ticket, and validate it.
  --notary-profile NAME     notarytool keychain profile name.
                            Defaults to NOTARYTOOL_PROFILE or InfraCanvasNotary.
  -h, --help                Show this help.

Examples:
  scripts/package_release.sh 0.1.0
  scripts/package_release.sh 0.1.0 \\
    --signing-identity "Developer ID Application: Your Name (TEAMID)" \\
    --notarize
USAGE
}

if [[ "${1:-}" == "-h" || "${1:-}" == "--help" ]]; then
  usage
  exit 0
fi

if [[ $# -gt 0 && "${1:-}" != --* ]]; then
  VERSION="$1"
  shift
fi

while [[ $# -gt 0 ]]; do
  case "$1" in
    --signing-identity)
      SIGNING_IDENTITY="${2:-}"
      shift 2
      ;;
    --notarize)
      NOTARIZE=1
      shift
      ;;
    --notary-profile)
      NOTARY_PROFILE="${2:-}"
      shift 2
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    *)
      echo "Unknown option: $1" >&2
      usage >&2
      exit 1
      ;;
  esac
done

DMG_PATH="$DIST_DIR/$APP_NAME-$VERSION.dmg"

if [[ "$NOTARIZE" -eq 1 && -z "$SIGNING_IDENTITY" ]]; then
  echo "Notarization requires --signing-identity or DEVELOPER_ID_APPLICATION." >&2
  exit 1
fi

cd "$ROOT_DIR"

mkdir -p "$DIST_DIR"

BUILD_ARGS=(
  -project "$APP_NAME.xcodeproj"
  -scheme "$SCHEME"
  -configuration "$CONFIGURATION"
  -derivedDataPath "$DERIVED_DATA_PATH"
  -destination "platform=macOS"
)

if [[ -n "$SIGNING_IDENTITY" ]]; then
  BUILD_ARGS+=(
    CODE_SIGN_STYLE=Manual
    CODE_SIGN_IDENTITY="$SIGNING_IDENTITY"
    CODE_SIGN_INJECT_BASE_ENTITLEMENTS=NO
    ENABLE_HARDENED_RUNTIME=YES
    OTHER_CODE_SIGN_FLAGS=--timestamp
  )
fi

xcodebuild "${BUILD_ARGS[@]}" build

if [[ ! -d "$APP_PATH" ]]; then
  echo "Expected app was not built at: $APP_PATH" >&2
  exit 1
fi

if [[ -n "$SIGNING_IDENTITY" ]]; then
  codesign --verify --deep --strict --verbose=2 "$APP_PATH"
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

if [[ -n "$SIGNING_IDENTITY" ]]; then
  codesign --force --sign "$SIGNING_IDENTITY" --timestamp "$DMG_PATH"
fi

if [[ "$NOTARIZE" -eq 1 ]]; then
  NOTARY_OUTPUT="$(xcrun notarytool submit "$DMG_PATH" \
    --keychain-profile "$NOTARY_PROFILE" \
    --wait 2>&1)"
  echo "$NOTARY_OUTPUT"
  if grep -q "status: Invalid" <<< "$NOTARY_OUTPUT"; then
    echo "Notarization failed. Run this command for details:" >&2
    echo "xcrun notarytool log <submission-id> --keychain-profile \"$NOTARY_PROFILE\"" >&2
    exit 1
  fi
  xcrun stapler staple "$DMG_PATH"
  xcrun stapler validate "$DMG_PATH"
  spctl -a -t open --context context:primary-signature -v "$DMG_PATH"
fi

echo "Created $DMG_PATH"
