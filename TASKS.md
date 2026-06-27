# SecureScreen Implementation Tasks

> Full implementation plan: `docs/superpowers/plans/2026-06-27-secure-screen.md`

## Phase 1: Build Infrastructure
- [ ] `Package.swift` — SPM target, Carbon/IOKit/LocalAuthentication linker flags
- [ ] `build.sh` — release compile + `.app` bundle with `LSUIElement = true` Info.plist
- [ ] `Sources/SecureScreen/main.swift` — NSApp setup + delegate

## Phase 2: Permissions Gate
- [ ] `PermissionsManager.swift` — `AXIsProcessTrusted()` check + system prompt + alert-then-quit on denial
- [ ] `AppDelegate.swift` — gates all startup on Accessibility trust; wires EventBlocker → HotkeyManager → StatusBarController

## Phase 3: Core Security Layer
- [ ] `EventBlocker.swift` — CGEventTap at `cgAnnotatedSessionEventTap`; blocks all events when locked; allowlists ⌥⇧U (triggers unlock) and status bar button rect (mouse pass-through); `pauseForAuth()` / `resumeAfterAuth()` for password entry
- [ ] `HotkeyManager.swift` — Carbon HotKey API for ⌥⇧L (lock only; unlock handled inside EventBlocker)

## Phase 4: Visual Overlay
- [ ] `LockWindow.swift` — borderless NSWindow at `NSScreenSaverWindowLevel`, `ignoresMouseEvents = true`, frame = `screen.frame` (full screen incl. menu bar), one per display
- [ ] `ShieldView.swift` — SwiftUI: NSVisualEffectView (`.behindWindow` blur, `.darkAqua`) fills entire window; `HintState` flashes "Locked — Press ⌥⇧U to Unlock" for 3 s on demand

## Phase 5: Lock Lifecycle
- [ ] `LockManager.swift` — `lock()`: multi-display LockWindows + IOPMAssertion + kiosk options `[.disableProcessSwitching, .hideDock, .disableForceQuit, .disableSessionTermination, .disableHideApplication]` + EventBlocker.enable(); `initiateUnlock()`: pauseForAuth + LAContext `.deviceOwnerAuthentication`; `unlock()`: reverses all; `showFallbackAlert()` failsafe

## Phase 6: Status Bar + Failsafe
- [ ] `StatusBarController.swift` — always-accessible status item; `statusItemScreenRect` fed to EventBlocker; locked menu shows ONLY "Emergency Unlock…" + "Quit"; unlocked menu shows Lock + Opacity presets; "Quit while locked" requires auth

## Phase 7: Integration & Verification
- [ ] `Scripts/test_sleep.sh` — 1-Hz timestamp logger, gap detector; pass = exit 0
- [ ] Build `SecureScreen.app` via `build.sh`
- [ ] Run `test_sleep.sh` — verify no background task interruption during 30 s lock
- [ ] Multi-monitor: blur covers ALL displays
- [ ] Input block checklist: Cmd+Tab, Cmd+Space, Cmd+Opt+Esc, two-finger swipe, three-finger swipe, Dock click, other menu bar items — all blocked
- [ ] Unlock paths: ⌥⇧U → Touch ID, ⌥⇧U → cancel stays locked, status icon → Emergency Unlock, Touch ID unavailable → password fallback
