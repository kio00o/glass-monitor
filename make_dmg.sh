#!/bin/zsh
# Builds the app and packs it into dist/GlassMonitor.dmg (drag-to-Applications layout).
set -e
cd "$(dirname "$0")"
./build.sh
rm -rf dist && mkdir -p dist/stage
cp -R GlassMonitor.app dist/stage/
ln -s /Applications dist/stage/Applications
hdiutil create -volname "Glass Monitor" -srcfolder dist/stage -ov -format UDZO dist/GlassMonitor.dmg
rm -rf dist/stage
echo "Created $PWD/dist/GlassMonitor.dmg"
