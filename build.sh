#!/bin/zsh
set -euo pipefail

SCRIPT_DIR="${0:A:h}"
PRODUCT_NAME="轻截.app"
OUTPUT_DIR="$SCRIPT_DIR/build"
TEMP_DIR=$(mktemp -d /tmp/QuickMarkShot-build.XXXXXX)
APP_DIR="$TEMP_DIR/$PRODUCT_NAME"
CONTENTS_DIR="$APP_DIR/Contents"
MACOS_DIR="$CONTENTS_DIR/MacOS"
ARCHIVE="$OUTPUT_DIR/轻截-macOS.zip"

mkdir -p "$MACOS_DIR"
mkdir -p "$OUTPUT_DIR"

xcrun swiftc \
  -swift-version 5 \
  -O \
  -framework AppKit \
  -framework Carbon \
  -framework UniformTypeIdentifiers \
  "$SCRIPT_DIR/Sources/QuickMarkShot.swift" \
  -o "$MACOS_DIR/QuickMarkShot"

cp "$SCRIPT_DIR/Info.plist" "$CONTENTS_DIR/Info.plist"
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
