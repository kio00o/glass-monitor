#!/bin/zsh
# Debug build for development: packs .build/GlassMonitor-Dev.app (not installed anywhere) and runs it
# with stdout/stderr in this terminal. Ctrl+C quits it.
#   ./dev.sh        build + run
#   ./dev.sh lldb   build + run under lldb (attaches as soon as it starts)
#   ./dev.sh cmd <show|hide|hot-cpu|low-battery|alert-yellow|alert-red|alert-off|claude-NN|update-on|update-off|update>
#                   drive the running dev build's Debug menu without clicking
#   GM_LOG=<file>   send the app's output to a file instead of this terminal
# Own bundle id, so it has its own settings and permissions and runs next to the installed release.
# Launched through `open`, so macOS attributes Location/Bluetooth/Keychain prompts to the app, not the terminal.
set -e
cd "$(dirname "$0")"
if [ "$1" = cmd ]; then
  osascript -l JavaScript -e "ObjC.import('Foundation'); \$.NSDistributedNotificationCenter.defaultCenter.postNotificationNameObjectUserInfoDeliverImmediately('dev.local.glassmonitor.debug', '$2', \$(), true)" >/dev/null
  exit 0
fi
swift build
BIN="$(swift build --show-bin-path)/GlassMonitor"
APP=.build/GlassMonitor-Dev.app
DEV_PROC="GlassMonitor-Dev.app/Contents/MacOS/GlassMonitor"
rm -rf $APP && mkdir -p $APP/Contents/MacOS $APP/Contents/Resources
cp "$BIN" $APP/Contents/MacOS/
cp -R Assets/Taby $APP/Contents/Resources/Taby
cp Assets/AppIcon.icns Assets/ukraine_map.json $APP/Contents/Resources/
cat > $APP/Contents/Info.plist <<PL
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
<key>CFBundleName</key><string>Glass Monitor Dev</string>
<key>CFBundleExecutable</key><string>GlassMonitor</string>
<key>CFBundleIdentifier</key><string>dev.local.glassmonitor.dev</string>
<key>CFBundleIconFile</key><string>AppIcon</string>
<key>CFBundlePackageType</key><string>APPL</string>
<key>CFBundleShortVersionString</key><string>dev</string>
<key>CFBundleVersion</key><string>0</string>
<key>LSMinimumSystemVersion</key><string>14.0</string>
<key>NSHighResolutionCapable</key><true/><key>LSUIElement</key><true/>
<key>NSLocationWhenInUseUsageDescription</key><string>Needed to read the name of the Wi-Fi network you are connected to.</string>
<key>NSBluetoothAlwaysUsageDescription</key><string>Needed to list connected Bluetooth devices.</string>
</dict></plist>
PL
codesign --force --sign - $APP

pkill -f $DEV_PROC && sleep 0.5 || true
trap "pkill -f $DEV_PROC || true" INT TERM EXIT
OUT=/dev/null; tty -s && OUT=$(tty)
[ -n "$GM_LOG" ] && OUT=$GM_LOG && : > "$OUT"
if [ "$1" = lldb ]; then
  (sleep 1; open -n --stdout $OUT --stderr $OUT $APP) &
  lldb --wait-for --attach-name GlassMonitor -o continue
else
  open -n -W --stdout $OUT --stderr $OUT $APP
fi
