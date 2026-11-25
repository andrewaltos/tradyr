#!/bin/bash
# Builds Resources/AppIcon.icns from a single 1024x1024 master PNG.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
MASTER="$ROOT/Resources/AppIcon.png"
ICONSET="$ROOT/.build/AppIcon.iconset"
OUT="$ROOT/Resources/AppIcon.icns"

if [ ! -f "$MASTER" ]; then
  echo "==> generating placeholder master icon"
  mkdir -p "$ROOT/Resources"
  swift "$ROOT/Scripts/make-icon.swift" "$MASTER"
fi

rm -rf "$ICONSET"
mkdir -p "$ICONSET"

# name:pixels — @2x entries are the same pixel size as the next point size up,
# which is why 32, 256 and 512 each appear twice.
for entry in \
  icon_16x16:16 icon_16x16@2x:32 \
  icon_32x32:32 icon_32x32@2x:64 \
  icon_128x128:128 icon_128x128@2x:256 \
  icon_256x256:256 icon_256x256@2x:512 \
  icon_512x512:512 icon_512x512@2x:1024
do
  name="${entry%:*}"
  px="${entry#*:}"
  sips -z "$px" "$px" "$MASTER" --out "$ICONSET/$name.png" >/dev/null
done

iconutil -c icns "$ICONSET" -o "$OUT"
echo "==> $OUT"
