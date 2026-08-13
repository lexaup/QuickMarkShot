#!/bin/zsh
set -euo pipefail

ROOT_DIR="${0:A:h:h}"
SOURCE_PLIST="$ROOT_DIR/Info.plist"
ARCHIVE="$ROOT_DIR/build/轻截-macOS.zip"
VERIFY_DIR=$(mktemp -d -t quickmarkshot-verify)
trap 'rm -rf "$VERIFY_DIR"' EXIT

cd "$ROOT_DIR"
./build.sh
unzip -t "$ARCHIVE" >/dev/null

if unzip -Z1 "$ARCHIVE" | /usr/bin/grep -Eq '(^|/)__MACOSX/|(^|/)\._'; then
  echo "archive contains Finder metadata" >&2
  exit 1
fi

unzip -q "$ARCHIVE" -d "$VERIFY_DIR"
apps=("$VERIFY_DIR"/*.app(N))
[[ ${#apps[@]} -eq 1 ]] || { echo "archive must contain exactly one app" >&2; exit 1; }
APP_PATH="${apps[1]}"
BUILT_PLIST="$APP_PATH/Contents/Info.plist"

plutil -lint "$SOURCE_PLIST" "$BUILT_PLIST" >/dev/null
source_version=$(plutil -extract CFBundleShortVersionString raw "$SOURCE_PLIST")
source_build=$(plutil -extract CFBundleVersion raw "$SOURCE_PLIST")
built_version=$(plutil -extract CFBundleShortVersionString raw "$BUILT_PLIST")
built_build=$(plutil -extract CFBundleVersion raw "$BUILT_PLIST")

[[ "$source_version" == "$built_version" ]] || { echo "version mismatch: source=$source_version built=$built_version" >&2; exit 1; }
[[ "$source_build" == "$built_build" ]] || { echo "build mismatch: source=$source_build built=$built_build" >&2; exit 1; }
[[ "$(plutil -extract LSMinimumSystemVersion raw "$BUILT_PLIST")" == "15.0" ]] || { echo "minimum system version mismatch" >&2; exit 1; }
[[ "$(plutil -extract LSUIElement raw "$BUILT_PLIST")" == "true" ]] || { echo "LSUIElement must be true" >&2; exit 1; }
[[ -n "$(plutil -extract NSScreenCaptureUsageDescription raw "$BUILT_PLIST")" ]] || { echo "screen-capture usage description is missing" >&2; exit 1; }
[[ -f "$APP_PATH/Contents/Resources/AppIcon.icns" ]] || { echo "AppIcon.icns is missing" >&2; exit 1; }
/usr/bin/file "$APP_PATH/Contents/MacOS/QuickMarkShot" | /usr/bin/grep -q arm64
codesign --verify --deep --strict "$APP_PATH"

/usr/bin/grep -q 'case display' Sources/Recording.swift
/usr/bin/grep -q 'case region' Sources/Recording.swift
/usr/bin/grep -q 'case window' Sources/Recording.swift
/usr/bin/grep -q 'case application' Sources/Recording.swift
/usr/bin/grep -q 'capturesAudio' Sources/Recording.swift
/usr/bin/grep -q 'zoomAmount' Sources/MouseZoom.swift
for key in kVK_ANSI_0 kVK_ANSI_1 kVK_ANSI_2 kVK_ANSI_5; do
  /usr/bin/grep -q "$key" Sources/QuickMarkShot.swift
done

echo "QuickMarkShot verification passed: $source_version ($source_build)"
