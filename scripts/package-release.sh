#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT_DIR"

VERSION="$(plutil -extract CFBundleShortVersionString raw -o - MacLocker/Info.plist)"
APP_NAME="MacLocker.app"
DIST_DIR="$ROOT_DIR/dist"
DERIVED_DATA="$ROOT_DIR/.build/DerivedData"
ZIP_PATH="$DIST_DIR/MacLocker-$VERSION.zip"
EXPORTED_APP_PATH="${1:-}"

rm -rf "$DIST_DIR" "$DERIVED_DATA"
mkdir -p "$DIST_DIR" "$DERIVED_DATA"

if [[ -n "$EXPORTED_APP_PATH" ]]; then
  if [[ ! -d "$EXPORTED_APP_PATH" ]]; then
    echo "error: exported app path does not exist: $EXPORTED_APP_PATH" >&2
    exit 1
  fi
  echo "Using exported app: $EXPORTED_APP_PATH"
  ditto "$EXPORTED_APP_PATH" "$DIST_DIR/$APP_NAME"
else
  echo "Building Release app with xcodebuild..."
  xcodebuild \
    -project MacLocker.xcodeproj \
    -scheme MacLocker \
    -destination 'generic/platform=macOS' \
    -configuration Release \
    -derivedDataPath "$DERIVED_DATA" \
    ONLY_ACTIVE_ARCH=NO \
    build

  BUILT_APP="$DERIVED_DATA/Build/Products/Release/$APP_NAME"
  if [[ ! -d "$BUILT_APP" ]]; then
    echo "error: built app not found at $BUILT_APP" >&2
    exit 1
  fi
  ditto "$BUILT_APP" "$DIST_DIR/$APP_NAME"

  if ! codesign --verify --deep --strict "$DIST_DIR/$APP_NAME" >/dev/null 2>&1; then
    echo "Applying ad-hoc signature..."
    codesign --force --deep --sign - "$DIST_DIR/$APP_NAME"
  fi
fi

rm -f "$ZIP_PATH"
ditto -c -k --sequesterRsrc --keepParent "$DIST_DIR/$APP_NAME" "$ZIP_PATH"

echo "Created $ZIP_PATH"
echo "Homebrew SHA256: $(shasum -a 256 "$ZIP_PATH" | awk '{print $1}')"
if command -v nix >/dev/null 2>&1; then
  echo "Nix hash: $(nix hash file --type sha256 "$ZIP_PATH")"
else
  echo "Nix hash: nix is not installed"
fi
