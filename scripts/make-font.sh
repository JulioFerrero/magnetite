#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
tmp=$(mktemp -d)
pyftsubset Resources/Fonts/source/InterVariable.ttf --layout-features='*' --no-hinting --output-file="$tmp/subset.ttf" \
  --unicodes="U+0020-007E,U+00A0-024F,U+0300-036F,U+1E00-1EFF,U+2000-206F,U+20A0-20CF,U+2100-214F,U+2190-21FF,U+2300-23FF,U+25A0-25FF"
fonttools varLib.instancer "$tmp/subset.ttf" opsz=14 wght=350:500 -o Resources/Fonts/InterVariable.ttf
rm -rf "$tmp"
