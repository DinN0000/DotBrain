#!/bin/bash
set -euo pipefail

REPO="DinN0000/AI-PKM-Bar"
APP_NAME="AI-PKM-MenuBar"
INSTALL_DIR="$HOME/Applications"
LAUNCHAGENT_DIR="$HOME/Library/LaunchAgents"
PLIST_NAME="com.ai-pkm.menubar"
PLIST_PATH="$LAUNCHAGENT_DIR/$PLIST_NAME.plist"

echo "=== AI-PKM MenuBar 설치 ==="
echo ""

# Detect architecture
ARCH=$(uname -m)
echo "시스템: macOS $(sw_vers -productVersion) ($ARCH)"

# Get latest release download URL
echo "최신 릴리즈 확인 중..."
DOWNLOAD_URL=$(curl -sL "https://api.github.com/repos/$REPO/releases/latest" \
    | grep '"browser_download_url"' \
    | grep "$APP_NAME" \
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

# Download
curl -sL "$DOWNLOAD_URL" -o "$TMP_DIR/$APP_NAME"

# Remove quarantine attribute (Gatekeeper 우회)
xattr -cr "$TMP_DIR/$APP_NAME" 2>/dev/null || true

# Set executable permission
chmod +x "$TMP_DIR/$APP_NAME"

# Install to ~/Applications
mkdir -p "$INSTALL_DIR"

# Stop running instance if any
pkill -f "$APP_NAME" 2>/dev/null || true
sleep 1

cp "$TMP_DIR/$APP_NAME" "$INSTALL_DIR/$APP_NAME"

echo "✓ 바이너리 설치 완료: $INSTALL_DIR/$APP_NAME"

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
        <string>$INSTALL_DIR/$APP_NAME</string>
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
launchctl kickstart "gui/$(id -u)/$PLIST_NAME" 2>/dev/null || "$INSTALL_DIR/$APP_NAME" &

echo ""
echo "================================================"
echo "  설치 완료!"
echo "  메뉴바에서 ·‿· 아이콘을 확인하세요."
echo ""
echo "  • 로그인 시 자동으로 시작됩니다"
echo "  • 비정상 종료 시 자동으로 재시작됩니다"
echo "  • 제거: $0 --uninstall 또는 아래 명령어"
echo "================================================"
echo ""
echo "제거하려면:"
echo "  launchctl bootout gui/$(id -u)/$PLIST_NAME"
echo "  rm $PLIST_PATH"
echo "  rm $INSTALL_DIR/$APP_NAME"
