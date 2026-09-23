#!/bin/bash
# ./build.sh          → build/Topaz.app
# ./build.sh install  → also replace /Applications/Topaz.app and (re)start it
set -euo pipefail
cd "$(dirname "$0")"

APP=build/Topaz.app
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"

swiftc -O -swift-version 5 -target arm64-apple-macos26 \
  -sdk "$(xcrun --sdk macosx --show-sdk-path)" \
  Sources/*.swift -o "$APP/Contents/MacOS/Topaz"

cp Resources/Info.plist "$APP/Contents/"
[ -f build/AppIcon.icns ] || scripts/make-icon.sh
cp build/AppIcon.icns Resources/Fonts/InterVariable.ttf "$APP/Contents/Resources/"
cp Resources/Fonts/LICENSE.txt "$APP/Contents/Resources/Inter-LICENSE.txt"
strip -x "$APP/Contents/MacOS/Topaz" # local symbols aren't needed at runtime
codesign --force --sign - "$APP"

if [ "${1:-}" = "install" ]; then
  pkill -x Topaz || true
  rm -rf /Applications/Topaz.app
  cp -R "$APP" /Applications/
  open /Applications/Topaz.app
fi
echo "Built $APP"
