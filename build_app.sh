#!/bin/bash
set -e
cd "$(dirname "$0")"

APP_NAME="北京时间万年历"
BUNDLE_ID="com.hx10.beijingtimecalendar"
VERSION="1.8"
BUILD_DIR=".build/release"
APP_DIR="$APP_NAME.app"

swift build -c release

rm -rf "$APP_DIR"
mkdir -p "$APP_DIR/Contents/MacOS"
mkdir -p "$APP_DIR/Contents/Resources"

cp "$BUILD_DIR/BeijingTimeCalendar" "$APP_DIR/Contents/MacOS/$APP_NAME"
chmod +x "$APP_DIR/Contents/MacOS/$APP_NAME"

if [ -f "Resources/AppIcon.icns" ]; then
    cp "Resources/AppIcon.icns" "$APP_DIR/Contents/Resources/AppIcon.icns"
fi

cat > "$APP_DIR/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleName</key>
    <string>$APP_NAME</string>
    <key>CFBundleDisplayName</key>
    <string>$APP_NAME</string>
    <key>CFBundleIdentifier</key>
    <string>$BUNDLE_ID</string>
    <key>CFBundleExecutable</key>
    <string>$APP_NAME</string>
    <key>CFBundleDevelopmentRegion</key>
    <string>zh-Hans</string>
    <key>CFBundleIconFile</key>
    <string>AppIcon</string>
    <key>CFBundleVersion</key>
    <string>$VERSION</string>
    <key>CFBundleShortVersionString</key>
    <string>$VERSION</string>
    <key>CFBundlePackageType</key>
    <string>APPL</string>
    <key>LSMinimumSystemVersion</key>
    <string>13.0</string>
    <key>LSUIElement</key>
    <true/>
    <key>NSHighResolutionCapable</key>
    <true/>
</dict>
</plist>
PLIST

# 本地化应用显示名：中文环境「北京时间万年历」，英文环境 oclock
mkdir -p "$APP_DIR/Contents/Resources/zh-Hans.lproj"
mkdir -p "$APP_DIR/Contents/Resources/en.lproj"
cat > "$APP_DIR/Contents/Resources/zh-Hans.lproj/InfoPlist.strings" <<'STR'
"CFBundleName" = "北京时间万年历";
"CFBundleDisplayName" = "北京时间万年历";
STR
cat > "$APP_DIR/Contents/Resources/en.lproj/InfoPlist.strings" <<'STR'
"CFBundleName" = "oclock";
"CFBundleDisplayName" = "oclock";
STR

# 临时签名，避免 Gatekeeper 拦截
codesign --force --deep --sign - "$APP_DIR" 2>/dev/null || true

echo "✅ 已生成: $APP_DIR"
