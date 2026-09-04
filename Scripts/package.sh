#!/bin/zsh
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
BUILD_DIR="$ROOT_DIR/build"
DIST_DIR="$ROOT_DIR/dist"
APP_NAME="RightMenuMini.app"
DIST_APP_NAME="MenuWish.app"
APP_PATH="$BUILD_DIR/Build/Products/Release/$APP_NAME"

VERSION=$(/usr/libexec/PlistBuddy -c "Print :CFBundleShortVersionString" "$ROOT_DIR/RightMenuMini/Info.plist" 2>/dev/null || echo "0.1.3")
ZIP_NAME="MenuWish-${VERSION}.zip"
ZIP_PATH="$DIST_DIR/$ZIP_NAME"

echo "Building Release version ${VERSION}..."
xcodebuild -quiet \
  -project "$ROOT_DIR/RightMenuMini.xcodeproj" \
  -scheme RightMenuMini \
  -configuration Release \
  -derivedDataPath "$BUILD_DIR" \
  CODE_SIGN_IDENTITY="-" \
  CODE_SIGN_STYLE="Manual" \
  build

mkdir -p "$DIST_DIR"
STAGING_DIR="$(mktemp -d)"
trap 'rm -rf "$STAGING_DIR"' EXIT

echo "Staging $DIST_APP_NAME..."
cp -R "$APP_PATH" "$STAGING_DIR/$DIST_APP_NAME"

echo "Creating $ZIP_PATH..."
rm -f "$ZIP_PATH"
ditto -c -k --sequesterRsrc --keepParent "$STAGING_DIR/$DIST_APP_NAME" "$ZIP_PATH"

echo "✅ Package created successfully: $ZIP_PATH"
ls -lh "$ZIP_PATH"
