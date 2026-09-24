#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
set=build/AppIcon.iconset
rm -rf "$set" && mkdir -p "$set"
swift scripts/art.swift icon build/icon-1024.png
for s in 16 32 128 256 512; do
  sips -z $s $s build/icon-1024.png --out "$set/icon_${s}x${s}.png" >/dev/null
  sips -z $((s * 2)) $((s * 2)) build/icon-1024.png --out "$set/icon_${s}x${s}@2x.png" >/dev/null
done
iconutil -c icns "$set" -o build/AppIcon.icns
rm -rf "$set"
