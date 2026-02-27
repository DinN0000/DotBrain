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
CURL_OPTS=(--fail --location --silent --show-error --retry 3 --retry-delay 1 --retry-connrefused)

echo "=== DotBrain 설치 ==="
echo ""

# Detect architecture
ARCH=$(uname -m)
echo "시스템: macOS $(sw_vers -productVersion) ($ARCH)"

# --- 릴리즈 정보 조회 ---

DMG_URL=""
DOWNLOAD_URL=""
ICON_URL=""

if [ -n "${1:-}" ]; then
    TAG="$1"
    echo "버전 지정: $TAG"
    DMG_URL="https://github.com/$REPO/releases/download/$TAG/$APP_NAME-${TAG#v}.dmg"
    DOWNLOAD_URL="https://github.com/$REPO/releases/download/$TAG/$APP_NAME"
    ICON_URL="https://github.com/$REPO/releases/download/$TAG/AppIcon.icns"
else
    echo "최신 릴리즈 확인 중..."
    if ! RELEASE_JSON=$(curl "${CURL_OPTS[@]}" "https://api.github.com/repos/$REPO/releases/latest"); then
        echo "오류: 최신 릴리즈 정보를 가져오지 못했습니다. 네트워크 상태를 확인한 뒤 다시 시도해주세요."
        echo "문제가 계속되면 https://github.com/$REPO/releases 에서 직접 다운로드하세요."
        exit 1
    fi

    TAG=$(echo "$RELEASE_JSON" | grep '"tag_name"' | head -1 | sed -E 's/.*"([^"]+)".*/\1/') || true
    if [ -z "$TAG" ]; then
        echo "오류: 릴리즈 정보를 읽을 수 없습니다. (GitHub API 제한일 수 있음)"
        echo "https://github.com/$REPO/releases 에서 직접 다운로드하세요."
        exit 1
    fi

    # DMG asset (preferred)
    DMG_URL=$(echo "$RELEASE_JSON" \
        | grep '"browser_download_url"' \
        | grep '\.dmg"' \
        | head -1 \
        | sed -E 's/.*"(https[^"]+)".*/\1/') || true

    # Binary asset (fallback)
    DOWNLOAD_URL=$(echo "$RELEASE_JSON" \
        | grep '"browser_download_url"' \
        | grep -v -E '\.(icns|txt|md|json|zip|tar|gz|sha256|dmg)' \
        | head -1 \
        | sed -E 's/.*"(https[^"]+)".*/\1/') || true

    ICON_URL=$(echo "$RELEASE_JSON" \
        | grep '"browser_download_url"' \
        | grep "AppIcon.icns" \
        | head -1 \
        | sed -E 's/.*"(https[^"]+)".*/\1/') || true
fi

echo "버전: $TAG"

# Create temp directory
TMP_DIR=$(mktemp -d)
trap 'rm -rf "$TMP_DIR"' EXIT

# --- Unload LaunchAgent + stop app (common for both paths) ---
launchctl bootout "gui/$(id -u)/$PLIST_NAME" 2>/dev/null || true
pkill -x "$APP_NAME" 2>/dev/null || true
sleep 1

# --- DMG 설치 경로 (우선) ---
INSTALLED_VIA_DMG=false

if [ -n "$DMG_URL" ]; then
    echo "DMG 다운로드 중..."
    if curl "${CURL_OPTS[@]}" "$DMG_URL" -o "$TMP_DIR/$APP_NAME.dmg" 2>/dev/null; then
        # Verify DMG checksum if available
        CHECKSUM_URL="https://github.com/$REPO/releases/download/$TAG/checksums.txt"
        if curl "${CURL_OPTS[@]}" "$CHECKSUM_URL" -o "$TMP_DIR/checksums.txt" 2>/dev/null; then
            DMG_FILENAME="$APP_NAME-${TAG#v}.dmg"
            EXPECTED=$(grep " ${DMG_FILENAME}$" "$TMP_DIR/checksums.txt" | awk '{print $1}')
            if [ -n "$EXPECTED" ]; then
                ACTUAL=$(shasum -a 256 "$TMP_DIR/$APP_NAME.dmg" | awk '{print $1}')
                if [ "$EXPECTED" != "$ACTUAL" ]; then
                    echo "오류: DMG 체크섬 불일치! 다운로드가 손상되었을 수 있습니다."
                    echo "  예상: $EXPECTED"
                    echo "  실제: $ACTUAL"
                    exit 1
                fi
                echo "✓ DMG 체크섬 확인 완료"
            fi
        fi
        echo "DMG 마운트 중..."
        MOUNT_OUTPUT=$(hdiutil attach "$TMP_DIR/$APP_NAME.dmg" -nobrowse -readonly 2>/dev/null) || true

        if [ -n "$MOUNT_OUTPUT" ]; then
            MOUNT_POINT=$(echo "$MOUNT_OUTPUT" | tail -1 | awk -F'\t' '{print $NF}' | xargs)

            if [ -d "$MOUNT_POINT/$APP_BUNDLE" ]; then
                echo "DMG에서 앱 복사 중..."
                mkdir -p "$INSTALL_DIR"
                rm -rf "$APP_PATH"
                cp -R "$MOUNT_POINT/$APP_BUNDLE" "$APP_PATH"
                hdiutil detach "$MOUNT_POINT" -quiet 2>/dev/null || true
                xattr -cr "$APP_PATH" 2>/dev/null || true
                INSTALLED_VIA_DMG=true
                echo "✓ DMG에서 앱 설치 완료: $APP_PATH"
            else
                hdiutil detach "$MOUNT_POINT" -quiet 2>/dev/null || true
                echo "경고: DMG 내 앱을 찾을 수 없습니다. 바이너리 설치로 전환합니다."
            fi
        else
            echo "경고: DMG 마운트 실패. 바이너리 설치로 전환합니다."
        fi
    else
        echo "경고: DMG 다운로드 실패. 바이너리 설치로 전환합니다."
    fi
fi

# --- 바이너리 설치 경로 (fallback) ---

if [ "$INSTALLED_VIA_DMG" = false ]; then
    if [ -z "$DOWNLOAD_URL" ]; then
        echo "오류: 설치 가능한 에셋을 찾을 수 없습니다."
        echo "https://github.com/$REPO/releases 에서 직접 다운로드하세요."
        exit 1
    fi

    echo "바이너리 다운로드 중: $DOWNLOAD_URL"
    curl "${CURL_OPTS[@]}" "$DOWNLOAD_URL" -o "$TMP_DIR/$APP_NAME"
    chmod +x "$TMP_DIR/$APP_NAME"

    # Verify checksum if available
    CHECKSUM_URL="https://github.com/$REPO/releases/download/$TAG/checksums.txt"
    if curl "${CURL_OPTS[@]}" "$CHECKSUM_URL" -o "$TMP_DIR/checksums.txt" 2>/dev/null; then
        EXPECTED=$(grep " ${APP_NAME}$" "$TMP_DIR/checksums.txt" | awk '{print $1}')
        ACTUAL=$(shasum -a 256 "$TMP_DIR/$APP_NAME" | awk '{print $1}')
        if [ -z "$EXPECTED" ]; then
            echo "오류: checksums.txt에서 $APP_NAME 항목을 찾지 못했습니다."
            exit 1
        fi
        if [ "$EXPECTED" != "$ACTUAL" ]; then
            echo "오류: 체크섬 불일치! 다운로드가 손상되었을 수 있습니다."
            echo "  예상: $EXPECTED"
            echo "  실제: $ACTUAL"
            exit 1
        fi
        echo "✓ 체크섬 확인 완료"
    fi

    # Download icon
    if [ -n "${ICON_URL:-}" ]; then
        if ! curl "${CURL_OPTS[@]}" "$ICON_URL" -o "$TMP_DIR/AppIcon.icns"; then
            echo "경고: 아이콘 다운로드 실패, 기본 아이콘으로 계속 진행합니다."
        fi
    fi

    # .app 번들 생성
    echo "앱 번들 생성 중..."

    mkdir -p "$INSTALL_DIR"
    rm -rf "$APP_PATH"
    mkdir -p "$APP_PATH/Contents/MacOS"
    mkdir -p "$APP_PATH/Contents/Resources"

    cp "$TMP_DIR/$APP_NAME" "$EXECUTABLE"

    if [ -f "$TMP_DIR/AppIcon.icns" ]; then
        cp "$TMP_DIR/AppIcon.icns" "$APP_PATH/Contents/Resources/AppIcon.icns"
    fi

    APP_VERSION=$(echo "$TAG" | sed 's/^v//')
    echo "버전: $APP_VERSION"

    cat > "$APP_PATH/Contents/Info.plist" << INFOPLIST
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
    <string>$APP_VERSION</string>
    <key>CFBundleShortVersionString</key>
    <string>$APP_VERSION</string>
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

    xattr -cr "$APP_PATH" 2>/dev/null || true
    echo "✓ 앱 설치 완료: $APP_PATH"
fi

# --- LaunchAgent 등록 (로그인 시 자동 시작) ---
echo ""
echo "로그인 시 자동 시작 설정 중..."

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
    <true/>
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
if ! launchctl kickstart "gui/$(id -u)/$PLIST_NAME" 2>/dev/null; then
    echo "경고: LaunchAgent 시작 실패, 앱을 직접 실행합니다."
    open "$APP_PATH"
fi

echo ""
echo "================================================"
echo "  설치 완료!"
echo "  메뉴바에서 ·‿· 아이콘을 확인하세요."
echo ""
echo "  - ~/Applications에서 앱을 확인할 수 있습니다"
echo "  - 로그인 시 자동으로 시작됩니다"
echo "  - 비정상 종료 시 자동으로 재시작됩니다"
echo "================================================"
echo ""
echo "제거하려면:"
echo "  pkill -f $APP_NAME; \\"
echo "  launchctl bootout gui/\$(id -u)/$PLIST_NAME; \\"
echo "  rm -rf $APP_PATH; \\"
echo "  rm -f $PLIST_PATH; \\"
echo "  echo \"제거 완료\""
