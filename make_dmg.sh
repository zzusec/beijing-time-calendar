#!/bin/bash
set -e
cd "$(dirname "$0")"

APP="北京时间万年历.app"
VERSION="${1:-1.0}"
DMG="BeijingTimeCalendar-$VERSION.dmg"
STAGE="dist/dmg"

[ -d "$APP" ] || ./build_app.sh

rm -rf dist
mkdir -p "$STAGE"
cp -R "$APP" "$STAGE/"
ln -s /Applications "$STAGE/Applications"

rm -f "$DMG"
hdiutil create -volname "北京时间万年历" -srcfolder "$STAGE" \
    -ov -format UDZO "$DMG" >/dev/null

rm -rf dist
echo "✅ 已生成: $DMG"
