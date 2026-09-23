#!/bin/bash
# ./build.sh          → build/Launcher.app
# ./build.sh install  → also replace /Applications/Launcher.app and (re)start it
set -euo pipefail
cd "$(dirname "$0")"

APP=build/Launcher.app
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"

swiftc -O -swift-version 5 -target arm64-apple-macos26 \
  -sdk "$(xcrun --sdk macosx --show-sdk-path)" \
  Sources/*.swift -o "$APP/Contents/MacOS/Launcher"

cp Resources/Info.plist "$APP/Contents/"
[ -f build/AppIcon.icns ] || scripts/make-icon.sh
cp build/AppIcon.icns Resources/Fonts/InterVariable.ttf "$APP/Contents/Resources/"
cp Resources/Fonts/LICENSE.txt "$APP/Contents/Resources/Inter-LICENSE.txt"
strip -x "$APP/Contents/MacOS/Launcher" # local symbols aren't needed at runtime
codesign --force --sign - "$APP"

if [ "${1:-}" = "install" ]; then
  pkill -x Launcher || true
  rm -rf /Applications/Launcher.app
  cp -R "$APP" /Applications/
  open /Applications/Launcher.app
fi
echo "Built $APP"
