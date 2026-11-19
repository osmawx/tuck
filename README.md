# Tuck

Tuck is a native macOS utility for organizing menu bar icons. Drag icons between three sections, save the order, and open hidden icons from the menu bar dot.

- **Shown Items** stay in the menu bar.
- **Hidden Items** appear in the panel under the dot. Click one to open its original menu.
- **Always Hidden** stay out of the panel.

## Install and update

Download `Tuck.dmg`, open it, and drag `Tuck.app` onto the Applications shortcut labeled «Программы». Finder shows the installation steps and a Privacy & Security shortcut directly in the disk image window. A ZIP download is also available. [GitHub Releases](https://github.com/osmawx/tuck/releases/latest)

GitHub release builds check for and install ZIP updates through Sparkle. To check immediately, click **Check for Updates…** in the Menu Bar Layout toolbar or in the menu bar dot’s context menu.

GitHub release builds use Tuck’s dedicated self-signed certificate. Apple does not notarize these builds. When you first open a copy you trust, macOS may ask you to approve it in **System Settings → Privacy & Security → Open Anyway**. See [Apple’s instructions](https://support.apple.com/en-us/102445).

Replace an older development build manually once. macOS may ask again for Accessibility or Screen Recording access because release builds use a different signing identity. The application ID and saved layout keys are preserved.

## Build and run

Use macOS 26 and the Xcode Command Line Tools.

```sh
git clone https://github.com/osmawx/tuck.git
cd tuck
./scripts/setup-signing.sh
./scripts/build.sh
open build/Tuck.app
```

`scripts/setup-signing.sh` creates a local signing identity on first use. Keep that identity for subsequent builds so macOS can recognize the app. If upgrading from Hider, quit it before opening Tuck. Tuck keeps the original bundle ID and preference keys. Local builds use the local signing identity and omit the updater by default.

## Set up your menu bar

1. Grant Accessibility access so Tuck can find menu bar items and open their original menus. Grant Screen Recording access if you want previews of the actual tray icons.
2. Drag icons to the desired sections in **Menu Bar Layout**.
3. Click **Sort My Bar** to save the order. The menu bar may blink while Control Center restarts. Tuck restores the saved arrangement at launch as icons become available.
4. Click the dot to open the hidden items panel. Click outside or switch apps to close it. Right-click the dot to reopen **Menu Bar Layout**.

Tuck stores the layout in local preferences. Icon captures stay in memory. Menu diagnostics are written to `/tmp/tuck-menu-diagnostics.log`.

Swift sources and tests live in `app/`. Build and release scripts live in `scripts/`.

See [CONTRIBUTING.md](CONTRIBUTING.md) for development and checks.
