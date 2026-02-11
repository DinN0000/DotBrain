#!/bin/bash
set -euo pipefail

REPO="DinN0000/DotBrain"
APP_NAME="DotBrain"
APP_BUNDLE="$APP_NAME.app"
INSTALL_DIR="$HOME/Applications"
APP_PATH="$INSTALL_DIR/$APP_BUNDLE"
EXECUTABLE="$APP_PATH/Contents/MacOS/$APP_NAME"
LAUNCHAGENT_DIR="$HOME/Library/LaunchAgents"
PLIST_NAME="com.dotbrain.app"
PLIST_PATH="$LAUNCHAGENT_DIR/$PLIST_NAME.plist"

echo "=== DotBrain 설치 ==="
echo ""

# Detect architecture
ARCH=$(uname -m)
echo "시스템: macOS $(sw_vers -productVersion) ($ARCH)"

# Get latest release download URL
echo "최신 릴리즈 확인 중..."
DOWNLOAD_URL=$(curl -sL "https://api.github.com/repos/$REPO/releases/latest" \
    | grep '"browser_download_url"' \
    | grep "/${APP_NAME}\"" \
    | head -1 \
    | sed -E 's/.*"(https[^"]+)".*/\1/')

if [ -z "$DOWNLOAD_URL" ]; then
    echo "오류: 릴리즈를 찾을 수 없습니다."
    echo "https://github.com/$REPO/releases 에서 직접 다운로드하세요."
    exit 1
fi

echo "다운로드: $DOWNLOAD_URL"

# Create temp directory
TMP_DIR=$(mktemp -d)
trap 'rm -rf "$TMP_DIR"' EXIT

# Download binary
curl -sL "$DOWNLOAD_URL" -o "$TMP_DIR/$APP_NAME"
chmod +x "$TMP_DIR/$APP_NAME"

# Download icon
ICON_URL=$(curl -sL "https://api.github.com/repos/$REPO/releases/latest" \
    | grep '"browser_download_url"' \
    | grep "AppIcon.icns" \
    | head -1 \
    | sed -E 's/.*"(https[^"]+)".*/\1/')
if [ -n "$ICON_URL" ]; then
    curl -sL "$ICON_URL" -o "$TMP_DIR/AppIcon.icns"
fi

# Stop running instance if any
pkill -f "$APP_NAME" 2>/dev/null || true
sleep 1

# --- .app 번들 생성 ---
echo "앱 번들 생성 중..."

mkdir -p "$INSTALL_DIR"
rm -rf "$APP_PATH"
mkdir -p "$APP_PATH/Contents/MacOS"
mkdir -p "$APP_PATH/Contents/Resources"

# Copy binary
cp "$TMP_DIR/$APP_NAME" "$EXECUTABLE"

# Copy icon if downloaded
if [ -f "$TMP_DIR/AppIcon.icns" ]; then
    cp "$TMP_DIR/AppIcon.icns" "$APP_PATH/Contents/Resources/AppIcon.icns"
fi

# Info.plist
cat > "$APP_PATH/Contents/Info.plist" << 'INFOPLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleName</key>
    <string>DotBrain</string>
    <key>CFBundleDisplayName</key>
    <string>DotBrain</string>
    <key>CFBundleIdentifier</key>
    <string>com.hwaa.dotbrain</string>
    <key>CFBundleVersion</key>
    <string>1.0.0</string>
    <key>CFBundleShortVersionString</key>
    <string>1.0.0</string>
    <key>CFBundleExecutable</key>
    <string>DotBrain</string>
    <key>CFBundleIconFile</key>
    <string>AppIcon</string>
    <key>CFBundlePackageType</key>
    <string>APPL</string>
    <key>LSUIElement</key>
    <true/>
    <key>LSMinimumSystemVersion</key>
    <string>13.0</string>
    <key>NSAppTransportSecurity</key>
    <dict>
        <key>NSAllowsArbitraryLoads</key>
        <false/>
        <key>NSExceptionDomains</key>
        <dict>
            <key>api.anthropic.com</key>
            <dict>
                <key>NSExceptionAllowsInsecureHTTPLoads</key>
                <false/>
                <key>NSIncludesSubdomains</key>
                <true/>
            </dict>
        </dict>
    </dict>
</dict>
</plist>
INFOPLIST

# Remove quarantine (Gatekeeper)
xattr -cr "$APP_PATH" 2>/dev/null || true

echo "✓ 앱 설치 완료: $APP_PATH"

# --- LaunchAgent 등록 (로그인 시 자동 시작) ---
echo ""
echo "로그인 시 자동 시작 설정 중..."

# 기존 LaunchAgent 언로드
launchctl bootout "gui/$(id -u)/$PLIST_NAME" 2>/dev/null || true

mkdir -p "$LAUNCHAGENT_DIR"
cat > "$PLIST_PATH" << PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>Label</key>
    <string>$PLIST_NAME</string>
    <key>ProgramArguments</key>
    <array>
        <string>$EXECUTABLE</string>
    </array>
    <key>RunAtLoad</key>
    <true/>
    <key>KeepAlive</key>
    <dict>
        <key>SuccessfulExit</key>
        <false/>
    </dict>
    <key>ProcessType</key>
    <string>Interactive</string>
</dict>
</plist>
PLIST

launchctl bootstrap "gui/$(id -u)" "$PLIST_PATH"

echo "✓ 자동 시작 등록 완료"

# --- 바로 실행 ---
echo ""
echo "앱을 시작합니다..."
launchctl kickstart "gui/$(id -u)/$PLIST_NAME" 2>/dev/null || open "$APP_PATH"

echo ""
echo "================================================"
echo "  설치 완료!"
echo "  메뉴바에서 ·‿· 아이콘을 확인하세요."
echo ""
echo "  • ~/Applications에서 앱을 확인할 수 있습니다"
echo "  • 로그인 시 자동으로 시작됩니다"
echo "  • 비정상 종료 시 자동으로 재시작됩니다"
echo "================================================"
echo ""
echo "제거하려면:"
echo "  pkill -f $APP_NAME; \\"
echo "  launchctl bootout gui/$(id -u)/$PLIST_NAME; \\"
echo "  rm -rf $APP_PATH; \\"
echo "  rm -f $PLIST_PATH; \\"
echo "  echo \"제거 완료\""
