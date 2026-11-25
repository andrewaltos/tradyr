#!/bin/bash
# Builds Tradyr.app into .build/ — no Xcode required.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
APP_NAME="Tradyr"
CONFIG="${CONFIG:-release}"
VERSION="$(tr -d '[:space:]' < "$ROOT/VERSION")"
BUILD_NUMBER="${BUILD_NUMBER:-1}"

APP="$ROOT/.build/$APP_NAME.app"
CONTENTS="$APP/Contents"

echo "==> swift build -c $CONFIG"
swift build --package-path "$ROOT" -c "$CONFIG" --product "$APP_NAME"
BINARY="$(swift build --package-path "$ROOT" -c "$CONFIG" --show-bin-path)/$APP_NAME"

echo "==> assembling bundle"
rm -rf "$APP"
mkdir -p "$CONTENTS/MacOS" "$CONTENTS/Resources"
cp "$BINARY" "$CONTENTS/MacOS/$APP_NAME"
printf 'APPL????' > "$CONTENTS/PkgInfo"

sed -e "s/__VERSION__/$VERSION/" -e "s/__BUILD__/$BUILD_NUMBER/" \
  "$ROOT/Resources/Info.plist" > "$CONTENTS/Info.plist"
plutil -lint "$CONTENTS/Info.plist" >/dev/null

if [ ! -f "$ROOT/Resources/AppIcon.icns" ]; then
  "$ROOT/Scripts/make-icns.sh"
fi
cp "$ROOT/Resources/AppIcon.icns" "$CONTENTS/Resources/AppIcon.icns"

# Signing identity. A stable self-signed cert (Scripts/make-identity.sh) keeps the microphone,
# speech and system-audio grants across rebuilds; ad-hoc signing re-prompts every build
# because TCC then keys on the binary's cdhash.
#
# Deliberately no `--options runtime`: the hardened runtime would need an audio-input
# entitlement before the microphone works, and this build is never notarized.
IDENTITY="${TRADYR_IDENTITY:-}"
if [ -z "$IDENTITY" ]; then
  if security find-identity -v -p codesigning 2>/dev/null | grep -q "Tradyr Local"; then
    IDENTITY="Tradyr Local"
  else
    IDENTITY="-"
    echo "!!! signing ad-hoc; microphone, speech and audio permissions will reset on each rebuild."
    echo "!!! run 'make identity' once to avoid that."
  fi
fi

echo "==> codesign ($IDENTITY)"
codesign --force --timestamp=none --sign "$IDENTITY" "$APP"
codesign --verify --strict "$APP"

echo "==> $APP"
