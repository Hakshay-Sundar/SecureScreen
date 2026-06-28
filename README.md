# SecureScreen

A macOS menu bar app that locks your screen without putting it to sleep — designed for long-running AI agent tasks or automated workflows that need the display active but shouldn't be interrupted by accidental input.

## What it does

When locked, SecureScreen:
- Covers every display with a blurred overlay
- Blocks all keyboard and mouse input system-wide
- Prevents the display from sleeping (overrides power settings)
- Hides the Dock and disables process switching (⌘Tab), Force Quit, and Hide

When unlocked, everything returns to normal instantly.

## Requirements

- macOS 14 (Sonoma) or later
- **Accessibility permission** — required to intercept system-wide input events. Grant it in System Settings → Privacy & Security → Accessibility.

## Installation

1. Build the project: `swift build -c release`
2. Copy the binary into the app bundle: `cp .build/arm64-apple-macosx/release/SecureScreen SecureScreen.app/Contents/MacOS/SecureScreen`
3. Open `SecureScreen.app` from Finder
4. Grant Accessibility permission when prompted, then relaunch

## Usage

### Locking

| Method | Action |
|--------|--------|
| Hotkey | `⌥⇧L` from anywhere |
| Menu | Click the 🔒 icon in the menu bar → Lock Screen |

### Unlocking

Press `⌥⇧U` at any time. This triggers Touch ID or your macOS login password via the system authentication dialog.

Two independent unlock layers ensure this always works:
- **Layer 1**: The active input-blocking tap intercepts `⌥⇧U` directly
- **Layer 2**: A Carbon-level hotkey fires below the blocking layer — if Layer 1 is somehow inactive, Layer 2 still triggers unlock

### Menu bar options (when unlocked)

| Option | Description |
|--------|-------------|
| Lock Screen  ⌥⇧L | Lock immediately |
| Overlay Opacity | Set how dark the overlay is (2% – 85%) |
| Launch at Login | Toggle auto-start on boot |
| Quit SecureScreen | Exit the app |

### Launch at Login

Click **Launch at Login** in the menu to enable automatic startup on boot. A checkmark indicates it is active. Disable it the same way.

> If you move `SecureScreen.app` to a different folder, toggle Launch at Login off and on again from the new location.

## How it works

SecureScreen uses a `CGEventTap` at the annotated-session level to intercept and suppress all keyboard and mouse events while locked. A `IOPMAssertion` prevents display sleep. The overlay windows sit at screen-saver level, covering all spaces and full-screen apps.

If macOS auto-disables the event tap (which it can do under load), the tap re-enables itself immediately via the `tapDisabledByTimeout` callback — keeping the block continuous.

## Notes

- The overlay opacity setting controls how much of the screen content is visible through the blur. Lower values (e.g. 2%) are nearly transparent; 85% is nearly opaque.
- Quit SecureScreen is available in the menu bar while unlocked. While locked, quitting requires unlocking first.
- Force Quit (`⌘⌥Esc`) is disabled while locked by design.
