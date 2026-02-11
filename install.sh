#!/bin/bash
set -euo pipefail

REPO="DinN0000/AI-PKM-Bar"
APP_NAME="AI-PKM-MenuBar"
INSTALL_DIR="$HOME/Applications"

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

# Remove quarantine attribute
xattr -cr "$TMP_DIR/$APP_NAME" 2>/dev/null || true

# Set executable permission
chmod +x "$TMP_DIR/$APP_NAME"

# Install to ~/Applications
mkdir -p "$INSTALL_DIR"

# Stop running instance if any
pkill -f "$APP_NAME" 2>/dev/null || true
sleep 1

cp "$TMP_DIR/$APP_NAME" "$INSTALL_DIR/$APP_NAME"

echo ""
echo "설치 완료: $INSTALL_DIR/$APP_NAME"
echo ""
echo "실행하려면:"
echo "  $INSTALL_DIR/$APP_NAME"
echo ""
echo "로그인 시 자동 실행을 원하면:"
echo "  시스템 설정 → 일반 → 로그인 항목에 추가"
