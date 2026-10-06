# Glass Monitor

A tiny macOS menu-bar system monitor in black-and-white Liquid Glass, with an animated mascot.
Disk, memory (with a list of the heaviest apps you can quit), battery, Claude plan limits with notifications at 20/40/80 %, Wi-Fi throughput + speed test, Bluetooth devices.

## Install

1. Download `GlassMonitor.dmg` from the latest [release](../../releases), open it, drag **Glass Monitor** to Applications.
2. The app is ad-hoc signed (not notarized), so macOS will block the first launch. Either right-click the app → **Open**, or run:
   ```
   xattr -cr /Applications/GlassMonitor.app
   ```
3. Allow Location (needed to read the Wi-Fi name) and Bluetooth when asked.

Works on macOS 14 (Sonoma) or newer, on Apple Silicon and Intel. On macOS 26 it uses Liquid Glass, on older systems a frosted material. It adds itself to Login Items on first launch (toggle it from the right-click menu on the menu-bar icon).

### Claude limits

The Claude card reads the OAuth token Claude Code keeps in your Keychain ("Claude Code-credentials") and asks
Anthropic for your 5-hour / 7-day usage. macOS will ask once to allow access — choose *Always Allow*.
Install and sign in to Claude Code on the Mac first; without it the card just shows "No data yet".
These endpoints are undocumented and may change.

## Build

```
./build.sh       # builds GlassMonitor.app and installs it to ~/Applications
./make_dmg.sh    # also packs dist/GlassMonitor.dmg
```

## Credits

The mascot animations in `Assets/Taby` are Taby character artwork by TRIIIS LABS
([firmware-taby](https://github.com/TRIIIS-LABS/firmware-taby)), used under the Taby Artwork Terms in
`Assets/Taby/LICENSE-TABY.txt`. Modified (rotated, cropped, rendered as a monochrome mask). Not an official Taby product.
