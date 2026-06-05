#!/bin/zsh
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
BUILD_DIR="$ROOT_DIR/build"
APP_NAME="RightMenuMini.app"
APP_PATH="$BUILD_DIR/Build/Products/Release/$APP_NAME"
INSTALL_PATH="/Applications/$APP_NAME"
EXTENSION_ID="com.codex.RightMenuMini.FinderExtension"
EXTENSION_PATH="$INSTALL_PATH/Contents/PlugIns/RightMenuMiniFinderExtension.appex"

xcodebuild -quiet \
  -project "$ROOT_DIR/RightMenuMini.xcodeproj" \
  -scheme RightMenuMini \
  -configuration Release \
  -derivedDataPath "$BUILD_DIR" \
  build

/usr/bin/killall RightMenuMini || true
/usr/bin/killall RightMenuMiniFinderExtension || true
rm -rf "$INSTALL_PATH"
cp -R "$APP_PATH" "$INSTALL_PATH"

/System/Library/Frameworks/CoreServices.framework/Versions/Current/Frameworks/LaunchServices.framework/Versions/Current/Support/lsregister -f -R -trusted "$INSTALL_PATH"
/usr/bin/pluginkit -a "$EXTENSION_PATH"
/usr/bin/pluginkit -r "$APP_PATH/Contents/PlugIns/RightMenuMiniFinderExtension.appex" || true
/System/Library/Frameworks/CoreServices.framework/Versions/Current/Frameworks/LaunchServices.framework/Versions/Current/Support/lsregister -u "$APP_PATH" || true
open "$INSTALL_PATH"
/usr/bin/killall Finder || true

echo "Installed: $INSTALL_PATH"
echo "Finder extension: $EXTENSION_ID"
echo "If the menu is not visible yet, click the app's 初次授予权限 button and enable 右键菜单助手 in the 文件提供程序 sheet."
