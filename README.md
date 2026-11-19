# Tuck

Tuck is a native macOS utility for organizing menu bar icons. Drag icons between three sections, save the order, and open hidden icons from the menu bar dot.

- **Shown Items** stay in the menu bar.
- **Hidden Items** appear in the panel under the dot. Click one to open its original menu.
- **Always Hidden** stay out of the panel.

## Build and run

Use macOS 26 and the Xcode Command Line Tools.

```sh
git clone https://github.com/osmawx/tuck.git
cd tuck
./setup-signing.sh
./build.sh
open build/Tuck.app
```

`setup-signing.sh` creates a local signing identity on first use. Keep that identity for subsequent builds so macOS can recognize the app. If upgrading from Hider, quit it before opening Tuck. Tuck keeps the original bundle ID and preference keys.

## Set up your menu bar

1. Grant Accessibility access so Tuck can find menu bar items and open their original menus. Grant Screen Recording access if you want previews of the actual tray icons.
2. Drag icons to the desired sections in **Menu Bar Layout**.
3. Click **Sort My Bar** to save the order. The menu bar may blink while Control Center restarts. Tuck restores the saved arrangement at launch as icons become available.
4. Click the dot to open the hidden items panel. Click outside or switch apps to close it. Right-click the dot to reopen **Menu Bar Layout**.

Tuck stores the layout in local preferences. Icon captures stay in memory. Menu diagnostics are written to `/tmp/tuck-menu-diagnostics.log`.

See [CONTRIBUTING.md](CONTRIBUTING.md) for development and checks.
