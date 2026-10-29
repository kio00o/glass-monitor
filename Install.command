#!/bin/zsh
# Packed into the DMG next to GlassMonitor.app. Double-click copies it to
# Applications, strips quarantine (ad-hoc builds have no Apple notarization),
# and launches. PREFIX=/tmp/out SKIP_OPEN=1 for checks.
set -e
HERE="$(cd "$(dirname "$0")" && pwd)"
APP="$HERE/GlassMonitor.app"
[[ -d "$APP" ]] || { echo "error: GlassMonitor.app not next to this script" >&2; exit 1; }
ID=$(/usr/bin/defaults read "$APP/Contents/Info" CFBundleIdentifier)
[[ "$ID" == "dev.local.glassmonitor" ]] || { echo "error: unexpected bundle id $ID" >&2; exit 1; }

if [[ -n "$PREFIX" ]]; then
  DEST="$PREFIX"
  /bin/mkdir -p "$DEST"
else
  DEST="/Applications"
  if [[ ! -d "$DEST" || ! -w "$DEST" ]]; then
    DEST="$HOME/Applications"
    /bin/mkdir -p "$DEST"
  fi
fi

echo "Installing to $DEST/GlassMonitor.app"
/bin/rm -rf "$DEST/GlassMonitor.app"
/bin/cp -R "$APP" "$DEST/GlassMonitor.app"
/usr/bin/xattr -cr "$DEST/GlassMonitor.app"
if [[ -z "$SKIP_OPEN" ]]; then
  /usr/bin/open "$DEST/GlassMonitor.app"
fi
echo "Done. Allow Location and Bluetooth when asked."
echo "You can close this window."
