#!/bin/bash
set -euo pipefail

PROJECT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
PROJECT_NAME="JiraTimeTracker"
SCHEME="JiraTimeTracker"
BUILD_DIR="$PROJECT_DIR/build"
APP_NAME="$PROJECT_NAME.app"

echo "==> Cleaning build directory..."
rm -rf "$BUILD_DIR"
mkdir -p "$BUILD_DIR"

echo "==> Building $PROJECT_NAME..."
xcodebuild \
    -project "$PROJECT_DIR/$PROJECT_NAME.xcodeproj" \
    -scheme "$SCHEME" \
    -configuration Release \
    -derivedDataPath "$BUILD_DIR/DerivedData" \
    -destination "generic/platform=macOS" \
    CODE_SIGN_IDENTITY="-" \
    CODE_SIGNING_REQUIRED=NO \
    CODE_SIGNING_ALLOWED=NO \
    ONLY_ACTIVE_ARCH=NO \
    clean build 2>&1 | tail -20

APP_PATH=$(find "$BUILD_DIR/DerivedData" -name "$APP_NAME" -type d | head -1)

if [ -z "$APP_PATH" ]; then
    echo "ERROR: Could not find built app"
    exit 1
fi

echo "==> Found app at: $APP_PATH"

echo "==> Creating .zip archive..."
ZIP_PATH="$BUILD_DIR/$PROJECT_NAME.zip"
cd "$(dirname "$APP_PATH")"
zip -r -y "$ZIP_PATH" "$APP_NAME"

echo "==> Creating .pkg installer..."
PKG_ROOT="$BUILD_DIR/pkg-root"
mkdir -p "$PKG_ROOT/Applications"
cp -R "$APP_PATH" "$PKG_ROOT/Applications/"

PKG_PATH="$BUILD_DIR/$PROJECT_NAME.pkg"
pkgbuild \
    --root "$PKG_ROOT" \
    --identifier "com.danbasnett.JiraTimeTracker" \
    --version "1.0" \
    --install-location "/" \
    "$PKG_PATH"

echo ""
echo "==> Build complete!"
echo "    .zip: $ZIP_PATH  (recommended — just unzip and drag to Applications)"
echo "    .pkg: $PKG_PATH  (installer — will prompt for password once)"
