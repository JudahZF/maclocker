#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT_DIR"

APP_NAME="MacLocker.app"
DIST_DIR="$ROOT_DIR/dist"
DERIVED_DATA="$ROOT_DIR/.build/DerivedData"
EXPORTED_APP_PATH="${1:-}"

project_version() {
  xcodebuild \
    -project MacLocker.xcodeproj \
    -scheme MacLocker \
    -configuration Release \
    -showBuildSettings |
    awk -F' = ' '/MARKETING_VERSION = / { print $2; exit }'
}

rm -rf "$DIST_DIR" "$DERIVED_DATA"
mkdir -p "$DIST_DIR" "$DERIVED_DATA"

if [[ -n "$EXPORTED_APP_PATH" ]]; then
  if [[ ! -d "$EXPORTED_APP_PATH" ]]; then
    echo "error: exported app path does not exist: $EXPORTED_APP_PATH" >&2
    exit 1
  fi
  VERSION="$(plutil -extract CFBundleShortVersionString raw -o - "$EXPORTED_APP_PATH/Contents/Info.plist")"
  echo "Using exported app without re-signing: $EXPORTED_APP_PATH"
  ditto "$EXPORTED_APP_PATH" "$DIST_DIR/$APP_NAME"
else
  VERSION="$(project_version)"
  echo "Building local Release app with ad-hoc signing..."
  xcodebuild \
    -project MacLocker.xcodeproj \
    -scheme MacLocker \
    -destination 'generic/platform=macOS' \
    -configuration Release \
    -derivedDataPath "$DERIVED_DATA" \
    CODE_SIGN_STYLE=Manual \
    DEVELOPMENT_TEAM= \
    CODE_SIGN_IDENTITY=- \
    ONLY_ACTIVE_ARCH=NO \
    build

  BUILT_APP="$DERIVED_DATA/Build/Products/Release/$APP_NAME"
  if [[ ! -d "$BUILT_APP" ]]; then
    echo "error: built app not found at $BUILT_APP" >&2
    exit 1
  fi
  ditto "$BUILT_APP" "$DIST_DIR/$APP_NAME"

  if ! codesign --verify --deep --strict "$DIST_DIR/$APP_NAME" >/dev/null 2>&1; then
    echo "Applying ad-hoc hardened-runtime signature..."
    codesign --force --deep --options runtime --sign - "$DIST_DIR/$APP_NAME"
  fi
fi

ZIP_PATH="$DIST_DIR/MacLocker-$VERSION.zip"
rm -f "$ZIP_PATH"
ditto -c -k --sequesterRsrc --keepParent "$DIST_DIR/$APP_NAME" "$ZIP_PATH"

echo "Created $ZIP_PATH"
echo "Homebrew SHA256: $(shasum -a 256 "$ZIP_PATH" | awk '{print $1}')"
if command -v nix >/dev/null 2>&1; then
  echo "Nix hash: $(nix hash file --type sha256 "$ZIP_PATH")"
else
  echo "Nix hash: nix is not installed"
fi
