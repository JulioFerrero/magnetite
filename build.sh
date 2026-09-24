#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")"
APP=build/Magnetite.app
VERSION=${VERSION:-$(git describe --tags --abbrev=0 2>/dev/null || echo 0.0.0)}
VERSION=${VERSION#v}
rm -rf "$APP" && mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
swift build -c release --arch arm64
cp "$(swift build -c release --arch arm64 --show-bin-path)/Magnetite" "$APP/Contents/MacOS/"
[ -f build/AppIcon.icns ] || scripts/make-icon.sh
cp Resources/Info.plist "$APP/Contents/"
plutil -replace CFBundleShortVersionString -string "$VERSION" "$APP/Contents/Info.plist"
plutil -replace CFBundleVersion -string "$(git rev-list --count HEAD)" "$APP/Contents/Info.plist"
cp build/AppIcon.icns Resources/Fonts/InterVariable.ttf "$APP/Contents/Resources/"
cp Resources/Fonts/LICENSE.txt "$APP/Contents/Resources/Inter-LICENSE.txt"
strip -x "$APP/Contents/MacOS/Magnetite"
codesign --force --sign - "$APP"
if [ "${1:-}" = "install" ]; then
  pkill -x Magnetite || true
  rm -rf /Applications/Magnetite.app && cp -R "$APP" /Applications/ && open /Applications/Magnetite.app
fi
if [ "${1:-}" = "dmg" ]; then
  [ -x build/venv/bin/dmgbuild ] || { python3 -m venv build/venv && build/venv/bin/pip install -q dmgbuild; }
  rm -f "build/Magnetite-$VERSION.dmg"
  build/venv/bin/dmgbuild -s scripts/dmg.py -D app="$APP" Magnetite "build/Magnetite-$VERSION.dmg"
  echo "Built build/Magnetite-$VERSION.dmg"
fi
echo "Built $APP ($VERSION)"
