#!/bin/bash
set -euo pipefail

PROJECT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
PROJECT_NAME="JiraTimeTracker"
SCHEME="JiraTimeTracker"
BUILD_DIR="$PROJECT_DIR/build"
APP_NAME="$PROJECT_NAME.app"

# Signing identity — set to your Developer ID Application certificate name
# Find yours with: security find-identity -v -p codesigning
SIGN_IDENTITY="${SIGN_IDENTITY:-Developer ID Application}"

# Notarization credentials — set these env vars or pass them in
# APPLE_ID        — your Apple ID email
# APPLE_PASSWORD  — app-specific password (not your account password)
# APPLE_TEAM_ID   — your 10-character Team ID

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
    CODE_SIGN_IDENTITY="$SIGN_IDENTITY" \
    OTHER_CODE_SIGN_FLAGS="--options=runtime" \
    ONLY_ACTIVE_ARCH=NO \
    clean build 2>&1 | tail -20

APP_PATH=$(find "$BUILD_DIR/DerivedData" -name "$APP_NAME" -type d | head -1)

if [ -z "$APP_PATH" ]; then
    echo "ERROR: Could not find built app"
    exit 1
fi

echo "==> Found app at: $APP_PATH"

# Notarize if credentials are available
if [ -n "${APPLE_ID:-}" ] && [ -n "${APPLE_PASSWORD:-}" ] && [ -n "${APPLE_TEAM_ID:-}" ]; then
    echo "==> Creating zip for notarization..."
    NOTARIZE_ZIP="$BUILD_DIR/notarize.zip"
    ditto -c -k --keepParent "$APP_PATH" "$NOTARIZE_ZIP"

    echo "==> Submitting for notarization..."
    xcrun notarytool submit "$NOTARIZE_ZIP" \
        --apple-id "$APPLE_ID" \
        --password "$APPLE_PASSWORD" \
        --team-id "$APPLE_TEAM_ID" \
        --wait

    echo "==> Stapling notarization ticket..."
    xcrun stapler staple "$APP_PATH"

    rm "$NOTARIZE_ZIP"
else
    echo "==> Skipping notarization (set APPLE_ID, APPLE_PASSWORD, APPLE_TEAM_ID to enable)"
fi

echo "==> Creating .zip archive..."
ZIP_PATH="$BUILD_DIR/$PROJECT_NAME.zip"
cd "$(dirname "$APP_PATH")"
zip -r -y "$ZIP_PATH" "$APP_NAME"

echo "==> Creating .pkg installer..."
PKG_ROOT="$BUILD_DIR/pkg-root"
mkdir -p "$PKG_ROOT/Applications"
cp -R "$APP_PATH" "$PKG_ROOT/Applications/"

UNSIGNED_PKG="$BUILD_DIR/$PROJECT_NAME-unsigned.pkg"
PKG_PATH="$BUILD_DIR/$PROJECT_NAME.pkg"

pkgbuild \
    --root "$PKG_ROOT" \
    --identifier "com.danbasnett.JiraTimeTracker" \
    --version "1.0" \
    --install-location "/" \
    "$UNSIGNED_PKG"

echo "==> Signing .pkg..."
INSTALLER_IDENTITY="${INSTALLER_IDENTITY:-Developer ID Installer}"
productsign --sign "$INSTALLER_IDENTITY" "$UNSIGNED_PKG" "$PKG_PATH"
rm "$UNSIGNED_PKG"

# Notarize .pkg if credentials are available
if [ -n "${APPLE_ID:-}" ] && [ -n "${APPLE_PASSWORD:-}" ] && [ -n "${APPLE_TEAM_ID:-}" ]; then
    echo "==> Notarizing .pkg..."
    xcrun notarytool submit "$PKG_PATH" \
        --apple-id "$APPLE_ID" \
        --password "$APPLE_PASSWORD" \
        --team-id "$APPLE_TEAM_ID" \
        --wait

    echo "==> Stapling .pkg..."
    xcrun stapler staple "$PKG_PATH"
else
    echo "==> Skipping .pkg notarization (set APPLE_ID, APPLE_PASSWORD, APPLE_TEAM_ID to enable)"
fi

echo ""
echo "==> Build complete!"
echo "    .zip: $ZIP_PATH"
echo "    .pkg: $PKG_PATH"
