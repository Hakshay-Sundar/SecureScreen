# SecureScreen Implementation Tasks

Track the progress of implementing SecureScreen.

## Phase 1: Setup & Build Infrastructure
- [ ] Create `Package.swift` for Swift Package Manager target configuration.
- [ ] Create `build.sh` to package the executable into a `SecureScreen.app` bundle (with `LSUIElement` in `Info.plist`).
- [ ] Create `test_sleep.sh` helper script for testing background task execution during lock.

## Phase 2: Core Logic & Services
- [ ] Implement `HotkeyManager.swift` wrapping Carbon HotKey API for global `⌥⇧L` and `⌥⇧U` shortcuts.
- [ ] Implement `LockWindow.swift` (borderless full-screen NSWindow subclass at `NSScreenSaverWindowLevel` that consumes all user events).
- [ ] Implement `LockManager.swift` (manages sleep assertions, macOS Kiosk Mode presentation options, multi-monitor window lifecycle, and Touch ID / password prompt).

## Phase 3: User Interface
- [ ] Implement `ShieldView.swift` (SwiftUI view with customizable transparency and a fading/low-contrast instruction text).
- [ ] Implement `StatusBarController.swift` (menu bar status item, translucency slider/presets, quit option, and integration test runner).
- [ ] Implement `main.swift` to bootstrap the `NSApplication` runloop and coordinate services.

## Phase 4: Integration & Verification
- [ ] Compile the application and generate the `SecureScreen.app` bundle.
- [ ] Run integration tests with `test_sleep.sh` to verify zero background task interruption.
- [ ] Manually verify:
  - Multi-monitor lock coverage.
  - Interception/blocking of gesture-based desktop switching and standard shortcuts (Cmd+Tab, Cmd+Opt+Esc).
  - Biometric authentication success/fallback scenarios.
