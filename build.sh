#!/bin/zsh
set -euo pipefail

SCRIPT_DIR="${0:A:h}"
PRODUCT_NAME="轻截.app"
OUTPUT_DIR="$SCRIPT_DIR/build"
TEMP_DIR=$(mktemp -d /tmp/QuickMarkShot-build.XXXXXX)
APP_DIR="$TEMP_DIR/$PRODUCT_NAME"
CONTENTS_DIR="$APP_DIR/Contents"
MACOS_DIR="$CONTENTS_DIR/MacOS"
RESOURCES_DIR="$CONTENTS_DIR/Resources"
ARCHIVE="$OUTPUT_DIR/轻截-macOS.zip"

mkdir -p "$MACOS_DIR"
mkdir -p "$RESOURCES_DIR"
mkdir -p "$OUTPUT_DIR"

xcrun swiftc \
  -swift-version 5 \
  -O \
  -framework AppKit \
  -framework Carbon \
  -framework UniformTypeIdentifiers \
  -framework ScreenCaptureKit \
  -framework AVFoundation \
  -framework CoreMedia \
  -framework CoreVideo \
  "$SCRIPT_DIR/Sources/QuickMarkShot.swift" \
  "$SCRIPT_DIR/Sources/Recording.swift" \
  "$SCRIPT_DIR/Sources/MouseZoom.swift" \
  "$SCRIPT_DIR/Sources/main.swift" \
  -o "$MACOS_DIR/QuickMarkShot"

cp "$SCRIPT_DIR/Info.plist" "$CONTENTS_DIR/Info.plist"
cp "$SCRIPT_DIR/Assets/AppIcon.icns" "$RESOURCES_DIR/AppIcon.icns"
xattr -cr "$APP_DIR"
codesign --force --deep --sign - --identifier local.codex.quickmarkshot "$APP_DIR"
codesign --verify --deep --strict "$APP_DIR"

if [[ -e "$ARCHIVE" ]]; then
  unlink "$ARCHIVE"
fi
(
  cd "$TEMP_DIR"
  /usr/bin/zip -qry -X "$ARCHIVE" "$PRODUCT_NAME"
)

echo "$APP_DIR"
