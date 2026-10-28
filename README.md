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

Works on macOS 14 (Sonoma) or newer, on Apple Silicon and Intel. On macOS 26 it uses Liquid Glass, on older systems a frosted material. It adds itself to Login Items on first launch (toggle it from the right-click menu on the menu-bar icon). Later versions appear there as **Update to …** when a newer GitHub release is out.

The **Widgets** box on the panel opens a page to show, hide and drag-reorder the cards (disk, memory, CPU, Claude, Wi-Fi, Bluetooth, battery, air alerts), up to seven at a time.

### Claude limits

The Claude card reads the OAuth token Claude Code keeps in your Keychain ("Claude Code-credentials") and asks
Anthropic for your 5-hour / 7-day usage. macOS will ask once to allow access — choose *Always Allow*.
Install and sign in to Claude Code on the Mac first; without it the card just shows "No data yet".
These endpoints are undocumented and may change.

### Air-raid alerts (Ukraine)

During an air-raid alert in your area the menu-bar eyes get angry and sink, an orange drone icon slides in next to them with a red (missile) or yellow (drone) severity dot, the mascot gets a fright and then puts on boxing gloves, and a card at the bottom of the panel shows the area, the threat level and what is flying nearby. Clicking the drone or the card opens a Ukraine map of current alerts.
Your oblast / raion / hromada is detected from the Mac's location (matched locally — the location never leaves the Mac) or picked by hand: right-click the menu-bar icon → **Air Alert Region**.

Data: active alerts from [siren.pp.ua](https://siren.pp.ua) (a public mirror of the official "Повітряна тривога" / ukrainealarm.com API), threat details from the [alerts.in.ua live report](https://alerts.in.ua/llms.txt), which it allows fetching without a token (only while an alert is active, at most once a minute).

**This is not an official warning system.** The Mac may be asleep or offline and third-party services can lag or stop working — always rely on the official "Повітряна тривога" app and sirens.

## Build

```
./build.sh       # builds GlassMonitor.app and installs it to ~/Applications
./make_dmg.sh    # also packs dist/GlassMonitor.dmg
```

## Credits

The Ukraine map outlines in `Assets/ukraine_map.json` are derived from [Natural Earth](https://www.naturalearthdata.com) (public domain), simplified.

The mascot animations in `Assets/Taby` are Taby character artwork by TRIIIS LABS
([firmware-taby](https://github.com/TRIIIS-LABS/firmware-taby)), used under the Taby Artwork Terms in
`Assets/Taby/LICENSE-TABY.txt`. Modified (rotated, cropped, rendered as a monochrome mask). Not an official Taby product.
