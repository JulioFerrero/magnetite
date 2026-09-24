#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")"
APP=build/Magnetite.app
rm -rf "$APP" && mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
swift build -c release --arch arm64
cp "$(swift build -c release --arch arm64 --show-bin-path)/Magnetite" "$APP/Contents/MacOS/"
[ -f build/AppIcon.icns ] || scripts/make-icon.sh
cp Resources/Info.plist "$APP/Contents/"
cp build/AppIcon.icns Resources/Fonts/InterVariable.ttf "$APP/Contents/Resources/"
cp Resources/Fonts/LICENSE.txt "$APP/Contents/Resources/Inter-LICENSE.txt"
strip -x "$APP/Contents/MacOS/Magnetite"
codesign --force --sign - "$APP"
if [ "${1:-}" = "install" ]; then
  pkill -x Magnetite || true
  rm -rf /Applications/Magnetite.app && cp -R "$APP" /Applications/ && open /Applications/Magnetite.app
fi
echo "Built $APP"
