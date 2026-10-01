#!/bin/bash
# Build a Universal Release of Vela and package it as a .dmg for GitHub Releases.
# Usage: scripts/build-dmg.sh
# Output: build/Vela-<version>.dmg
set -euo pipefail

cd "$(dirname "$0")/.."

APP_NAME="Vela"
BUILD_DIR="build"
DERIVED_DATA="$BUILD_DIR/DerivedData"
STAGING="$BUILD_DIR/dmg-staging"

# Use full Xcode even if xcode-select points to Command Line Tools
if ! xcodebuild -version >/dev/null 2>&1; then
    export DEVELOPER_DIR="/Applications/Xcode.app/Contents/Developer"
fi

rm -rf "$BUILD_DIR"

# Not signed with a Developer ID yet; ad-hoc sign so the app runs on Apple Silicon
xcodebuild \
    -project "$APP_NAME.xcodeproj" \
    -scheme "$APP_NAME" \
    -configuration Release \
    -destination "generic/platform=macOS" \
    -derivedDataPath "$DERIVED_DATA" \
    CODE_SIGN_IDENTITY="-" \
    CODE_SIGN_STYLE=Manual \
    DEVELOPMENT_TEAM="" \
    build

APP_PATH="$DERIVED_DATA/Build/Products/Release/$APP_NAME.app"
VERSION=$(/usr/libexec/PlistBuddy -c "Print CFBundleShortVersionString" "$APP_PATH/Contents/Info.plist")
DMG_PATH="$BUILD_DIR/$APP_NAME-$VERSION.dmg"

mkdir -p "$STAGING"
ditto "$APP_PATH" "$STAGING/$APP_NAME.app"
ln -s /Applications "$STAGING/Applications"

hdiutil create \
    -volname "$APP_NAME" \
    -srcfolder "$STAGING" \
    -fs HFS+ \
    -format UDZO \
    -ov \
    "$DMG_PATH"

rm -rf "$STAGING"

echo ""
echo "Created: $DMG_PATH"
echo "Architectures: $(lipo -archs "$APP_PATH/Contents/MacOS/$APP_NAME")"
shasum -a 256 "$DMG_PATH"
