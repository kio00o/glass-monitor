#!/bin/zsh
# Builds GlassMonitor.app (ad-hoc signed) next to this script.
set -e
VERSION=1.4.0
cd "$(dirname "$0")"
# one build per architecture (no full Xcode needed), then merge into a universal binary
swift build -c release --triple arm64-apple-macosx14.0
swift build -c release --triple x86_64-apple-macosx14.0
mkdir -p .build/universal
lipo -create .build/arm64-apple-macosx/release/GlassMonitor .build/x86_64-apple-macosx/release/GlassMonitor -output .build/universal/GlassMonitor
APP=GlassMonitor.app
rm -rf $APP && mkdir -p $APP/Contents/MacOS
cp .build/universal/GlassMonitor $APP/Contents/MacOS/
mkdir -p $APP/Contents/Resources && cp -R Assets/Taby $APP/Contents/Resources/Taby
cp Assets/AppIcon.icns $APP/Contents/Resources/
cat > $APP/Contents/Info.plist <<PL
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
<key>CFBundleName</key><string>Glass Monitor</string>
<key>CFBundleExecutable</key><string>GlassMonitor</string>
<key>CFBundleIdentifier</key><string>dev.local.glassmonitor</string>
<key>CFBundleIconFile</key><string>AppIcon</string>
<key>CFBundlePackageType</key><string>APPL</string>
<key>CFBundleShortVersionString</key><string>$VERSION</string>
<key>CFBundleVersion</key><string>$VERSION</string>
<key>LSMinimumSystemVersion</key><string>14.0</string>
<key>NSHighResolutionCapable</key><true/><key>LSUIElement</key><true/>
<key>NSLocationWhenInUseUsageDescription</key><string>Needed to read the name of the Wi-Fi network you are connected to.</string>
<key>NSBluetoothAlwaysUsageDescription</key><string>Needed to list connected Bluetooth devices.</string>
</dict></plist>
PL
codesign --force --sign - $APP
# Install to ~/Applications so the login item keeps a stable path
mkdir -p ~/Applications && rm -rf ~/Applications/$APP && cp -R $APP ~/Applications/
echo "Built $PWD/$APP and installed to ~/Applications/$APP"
