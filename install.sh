#!/bin/zsh
set -euo pipefail

SCRIPT_DIR="${0:A:h}"
DESTINATION_DIR="$HOME/Applications"
DESTINATION_APP="$DESTINATION_DIR/轻截.app"

SOURCE_APP=$("$SCRIPT_DIR/build.sh" | tail -n 1)
mkdir -p "$DESTINATION_DIR"

pkill -x QuickMarkShot 2>/dev/null || true
ditto "$SOURCE_APP" "$DESTINATION_APP"
xattr -cr "$DESTINATION_APP"
codesign --verify --deep --strict "$DESTINATION_APP"

open "$DESTINATION_APP"
echo "$DESTINATION_APP"
