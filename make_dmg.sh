#!/bin/zsh
# Builds the app and packs it into dist/GlassMonitor.dmg.
# Open the DMG and double-click Install: copies to Applications and strips quarantine.
# The Applications symlink is still there for a manual drag.
set -e
cd "$(dirname "$0")"
./build.sh
rm -rf dist && mkdir -p dist/stage
cp -R GlassMonitor.app dist/stage/
cp Install.command dist/stage/
chmod +x dist/stage/Install.command
ln -s /Applications dist/stage/Applications
hdiutil create -volname "Glass Monitor" -srcfolder dist/stage -ov -format UDZO dist/GlassMonitor.dmg
rm -rf dist/stage
echo "Created $PWD/dist/GlassMonitor.dmg"
