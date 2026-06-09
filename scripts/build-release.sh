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

echo "==> Creating .pkg installer..."
PKG_PATH="$BUILD_DIR/$PROJECT_NAME.pkg"
pkgbuild \
    --root "$APP_PATH" \
    --identifier "com.danbasnett.JiraTimeTracker" \
    --version "1.0" \
    --install-location "/Applications/$APP_NAME" \
    --component-plist /dev/stdin \
    "$PKG_PATH" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<array>
    <dict>
        <key>BundleHasStrictIdentifier</key>
        <false/>
        <key>BundleIsRelocatable</key>
        <true/>
        <key>BundleOverwriteAction</key>
        <string>upgrade</string>
        <key>RootRelativeBundlePath</key>
        <string>JiraTimeTracker.app</string>
    </dict>
</array>
</plist>
PLIST

echo "==> Creating .zip archive..."
ZIP_PATH="$BUILD_DIR/$PROJECT_NAME.zip"
cd "$(dirname "$APP_PATH")"
zip -r -y "$ZIP_PATH" "$APP_NAME"

echo ""
echo "==> Build complete!"
echo "    .pkg: $PKG_PATH"
echo "    .zip: $ZIP_PATH"
