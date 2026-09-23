#!/bin/bash
# Builds Resources/Fonts/InterVariable.ttf from the full Inter 4.1 variable font
# (Resources/Fonts/source/, SIL OFL): Latin + punctuation + the ↵ ⌘ symbols,
# hinting dropped (macOS ignores it), optical size pinned to 14 and weight
# limited to the 350–500 the UI uses. 880 KB → ~340 KB. Needs fonttools.
set -euo pipefail
cd "$(dirname "$0")/.."
tmp=$(mktemp -d)
pyftsubset Resources/Fonts/source/InterVariable.ttf \
  --unicodes="U+0020-007E,U+00A0-024F,U+0300-036F,U+1E00-1EFF,U+2000-206F,U+20A0-20CF,U+2100-214F,U+2190-21FF,U+2300-23FF,U+25A0-25FF" \
  --layout-features='*' --no-hinting --output-file="$tmp/subset.ttf"
fonttools varLib.instancer "$tmp/subset.ttf" opsz=14 wght=350:500 -o Resources/Fonts/InterVariable.ttf
rm -rf "$tmp"
