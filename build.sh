#!/bin/bash
# ./build.sh          → build/Magnetite.app
# ./build.sh install  → also replace /Applications/Magnetite.app and (re)start it
set -euo pipefail
cd "$(dirname "$0")"

APP=build/Magnetite.app
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"

swiftc -O -swift-version 5 -target arm64-apple-macos26 \
  -sdk "$(xcrun --sdk macosx --show-sdk-path)" \
  Sources/*.swift -o "$APP/Contents/MacOS/Magnetite"

cp Resources/Info.plist "$APP/Contents/"
[ -f build/AppIcon.icns ] || scripts/make-icon.sh
cp build/AppIcon.icns Resources/Fonts/InterVariable.ttf "$APP/Contents/Resources/"
cp Resources/Fonts/LICENSE.txt "$APP/Contents/Resources/Inter-LICENSE.txt"
strip -x "$APP/Contents/MacOS/Magnetite" # local symbols aren't needed at runtime
codesign --force --sign - "$APP"

if [ "${1:-}" = "install" ]; then
  pkill -x Magnetite || true
  rm -rf /Applications/Magnetite.app
  cp -R "$APP" /Applications/
  open /Applications/Magnetite.app
fi
echo "Built $APP"
