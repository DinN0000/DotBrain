#!/bin/bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

APP_NAME="DotBrain"
APP_BUNDLE="$APP_NAME.app"
INFO_PLIST="$PROJECT_ROOT/Resources/Info.plist"
ICON_FILE="$PROJECT_ROOT/Resources/AppIcon.icns"
BINARY="$PROJECT_ROOT/.build/release/$APP_NAME"

# Read version from Info.plist
VERSION=$(/usr/libexec/PlistBuddy -c "Print :CFBundleShortVersionString" "$INFO_PLIST")
DMG_NAME="$APP_NAME-$VERSION.dmg"

echo "=== DotBrain DMG Builder ==="
echo "Version: $VERSION"
echo ""

# Verify binary exists
if [ ! -f "$BINARY" ]; then
    echo "Error: Binary not found at $BINARY"
    echo "Run 'swift build -c release' first."
    exit 1
fi

# Create temp directory for .app bundle assembly
TMP_DIR=$(mktemp -d)
trap 'rm -rf "$TMP_DIR"' EXIT

APP_PATH="$TMP_DIR/$APP_BUNDLE"

echo "Assembling .app bundle..."
mkdir -p "$APP_PATH/Contents/MacOS"
mkdir -p "$APP_PATH/Contents/Resources"

# Copy binary
cp "$BINARY" "$APP_PATH/Contents/MacOS/$APP_NAME"
chmod +x "$APP_PATH/Contents/MacOS/$APP_NAME"

# Copy icon
if [ -f "$ICON_FILE" ]; then
    cp "$ICON_FILE" "$APP_PATH/Contents/Resources/AppIcon.icns"
fi

# Copy Info.plist (use the release one from Resources/)
cp "$INFO_PLIST" "$APP_PATH/Contents/Info.plist"

# Ensure Info.plist has required keys for .app bundle
/usr/libexec/PlistBuddy -c "Add :CFBundleExecutable string $APP_NAME" "$APP_PATH/Contents/Info.plist" 2>/dev/null || \
    /usr/libexec/PlistBuddy -c "Set :CFBundleExecutable $APP_NAME" "$APP_PATH/Contents/Info.plist"
/usr/libexec/PlistBuddy -c "Add :CFBundleIconFile string AppIcon" "$APP_PATH/Contents/Info.plist" 2>/dev/null || \
    /usr/libexec/PlistBuddy -c "Set :CFBundleIconFile AppIcon" "$APP_PATH/Contents/Info.plist"
/usr/libexec/PlistBuddy -c "Add :CFBundlePackageType string APPL" "$APP_PATH/Contents/Info.plist" 2>/dev/null || \
    /usr/libexec/PlistBuddy -c "Set :CFBundlePackageType APPL" "$APP_PATH/Contents/Info.plist"
/usr/libexec/PlistBuddy -c "Add :CFBundleDisplayName string $APP_NAME" "$APP_PATH/Contents/Info.plist" 2>/dev/null || \
    /usr/libexec/PlistBuddy -c "Set :CFBundleDisplayName $APP_NAME" "$APP_PATH/Contents/Info.plist"
/usr/libexec/PlistBuddy -c "Add :LSMinimumSystemVersion string 13.0" "$APP_PATH/Contents/Info.plist" 2>/dev/null || \
    /usr/libexec/PlistBuddy -c "Set :LSMinimumSystemVersion 13.0" "$APP_PATH/Contents/Info.plist"

# Ad-hoc codesign
echo "Signing .app bundle (ad-hoc)..."
codesign --force --deep --sign - "$APP_PATH"

# Create DMG staging area
DMG_STAGING="$TMP_DIR/dmg-staging"
mkdir -p "$DMG_STAGING"
cp -R "$APP_PATH" "$DMG_STAGING/"
ln -s /Applications "$DMG_STAGING/Applications"

# Create DMG
OUTPUT_PATH="$PROJECT_ROOT/$DMG_NAME"
rm -f "$OUTPUT_PATH"

echo "Creating DMG..."
hdiutil create \
    -volname "$APP_NAME" \
    -srcfolder "$DMG_STAGING" \
    -ov \
    -format UDZO \
    "$OUTPUT_PATH"

echo ""
echo "=== Done ==="
echo "Output: $OUTPUT_PATH"
echo "Size: $(du -h "$OUTPUT_PATH" | cut -f1)"
