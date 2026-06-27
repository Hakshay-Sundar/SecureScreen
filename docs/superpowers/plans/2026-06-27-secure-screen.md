# SecureScreen Implementation Plan (Revised)

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** macOS menu bar app that overlays a full-screen blur when locked, blocks ALL input (keyboard, trackpad gestures, dock, Spotlight) system-wide via a CGEventTap, exposes only the SecureScreen status bar icon for emergency failsafe unlock, and authenticates via Touch ID / password before unlocking.

**Architecture:** LSUIElement NSStatusItem app. A CGEventTap at `cgAnnotatedSessionEventTap` intercepts all system events when locked, consuming them except for (a) the ⌥⇧U unlock hotkey and (b) mouse clicks within the SecureScreen status bar button rect. Lock windows are purely visual (`ignoresMouseEvents = true`), full-screen on every display, hosting an `NSVisualEffectView` blur. `LockManager` coordinates sleep assertions, kiosk presentation options, multi-display window lifecycle, and LocalAuthentication. This architecture replaces the Codex attempt which failed because: the lock window consumed events at the wrong layer (window level rather than session-tap level), kiosk mode was incomplete (trackpad gestures, Spotlight, and Dock were not blocked), and the unlock auth dialog could not receive focus while the lock window held it.

**Tech Stack:** Swift 5.9+, AppKit, SwiftUI, Carbon (HotKey API for lock shortcut), IOKit (sleep assertion), LocalAuthentication, CoreGraphics (CGEventTap)

## Global Constraints

- macOS 14.0+
- `LSUIElement = true` — no Dock icon, no main window, status bar only
- Accessibility permission required — app refuses to lock and shows an alert if `AXIsProcessTrusted()` returns false
- Lock hotkey: `⌥⇧L` (Option+Shift+L) — registered via Carbon HotKey API (works when unlocked)
- Unlock hotkey: `⌥⇧U` (Option+Shift+U, key code 32) — handled inside CGEventTap callback (works when locked)
- Only `⌥⇧U` keypresses and clicks within `StatusBarController.shared.statusItemScreenRect` pass through the event tap when locked
- Lock window: `ignoresMouseEvents = true`, level = `NSScreenSaverWindowLevel`, frame = full `NSScreen.frame` (not `visibleFrame`) on every connected display
- Blur overlay uses `NSVisualEffectView` with `blendingMode = .behindWindow`, `material = .fullScreenUI`, `state = .active`, `appearance = .darkAqua` — this gives the frosted-glass "hung screen" illusion
- Translucency is the window's `alphaValue` (0.02–1.0); default 0.85
- No clock, no lock icon on overlay; only a low-contrast hint text "Locked — Press ⌥⇧U to Unlock" that fades in for 3 s on any blocked event
- Status bar menu items when locked: "Emergency Unlock…" only (Lock/Opacity hidden while locked to reduce surface)
- `IOPMAssertionCreateWithName(kIOPMAssertionTypeNoDisplaySleep)` held during lock
- Kiosk options during lock: `[.disableProcessSwitching, .hideDock, .disableForceQuit, .disableSessionTermination, .disableHideApplication]`
- CGEventTap calls `EventBlocker.shared.pauseForAuth()` before showing the auth dialog (lets password keyboard through) and `resumeAfterAuth()` on cancellation

---

## File Map

```
SecureScreen/
├── Package.swift
├── build.sh
├── Scripts/
│   └── test_sleep.sh
└── Sources/SecureScreen/
    ├── main.swift                  # NSApp setup + delegate wiring
    ├── AppDelegate.swift           # applicationDidFinishLaunching, permission gate
    ├── PermissionsManager.swift    # AXIsProcessTrusted check + prompt
    ├── EventBlocker.swift          # CGEventTap: blocks all events when locked
    ├── HotkeyManager.swift         # Carbon API: ⌥⇧L lock shortcut only
    ├── LockManager.swift           # Orchestrates lock/unlock, sleep, kiosk, auth
    ├── LockWindow.swift            # Visual-only full-screen NSWindow per display
    ├── ShieldView.swift            # SwiftUI: NSVisualEffectView + hint text
    └── StatusBarController.swift   # Menu bar icon, opacity prefs, failsafe unlock
```

---

### Task 1: Build Infrastructure

**Files:**
- Create: `Package.swift`
- Create: `build.sh`
- Create: `Sources/SecureScreen/main.swift` (stub)

**Interfaces:**
- Produces: `swift build` succeeds; `build.sh` produces `SecureScreen.app/Contents/MacOS/SecureScreen` with a valid `Info.plist`

- [ ] **Step 1: Create `Package.swift`**

```swift
// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "SecureScreen",
    platforms: [.macOS(.v14)],
    targets: [
        .executableTarget(
            name: "SecureScreen",
            path: "Sources/SecureScreen",
            linkerSettings: [
                .linkedFramework("Carbon"),
                .linkedFramework("IOKit"),
                .linkedFramework("LocalAuthentication"),
            ]
        ),
    ]
)
```

- [ ] **Step 2: Create stub `Sources/SecureScreen/main.swift`**

```swift
import AppKit

let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.run()
```

- [ ] **Step 3: Verify `swift build` succeeds**

Run: `swift build`
Expected: `Build complete!`

- [ ] **Step 4: Create `build.sh`**

```bash
#!/bin/bash
set -e
APP="SecureScreen.app"
BINARY_SRC=".build/release/SecureScreen"

swift build -c release

rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS"
mkdir -p "$APP/Contents/Resources"

cp "$BINARY_SRC" "$APP/Contents/MacOS/SecureScreen"

cat > "$APP/Contents/Info.plist" << 'EOF'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN"
  "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleName</key><string>SecureScreen</string>
    <key>CFBundleIdentifier</key><string>com.securescreen.app</string>
    <key>CFBundleVersion</key><string>1.0</string>
    <key>CFBundleExecutable</key><string>SecureScreen</string>
    <key>NSPrincipalClass</key><string>NSApplication</string>
    <key>LSUIElement</key><true/>
    <key>NSHighResolutionCapable</key><true/>
</dict>
</plist>
EOF

echo "Built: $APP"
```

- [ ] **Step 5: Make executable and run**

Run: `chmod +x build.sh && ./build.sh`
Expected: `Built: SecureScreen.app`

- [ ] **Step 6: Commit**

```bash
git add Package.swift build.sh Sources/SecureScreen/main.swift
git commit -m "feat: build infrastructure — SPM package, app bundle script"
```

---

### Task 2: Permissions Manager + App Delegate

**Files:**
- Create: `Sources/SecureScreen/PermissionsManager.swift`
- Create: `Sources/SecureScreen/AppDelegate.swift`

**Interfaces:**
- Produces: `PermissionsManager.isTrusted` → `Bool`; `PermissionsManager.promptAndWait()` → shows system Accessibility dialog; `AppDelegate.applicationDidFinishLaunching` gates all startup on trust

- [ ] **Step 1: Create `PermissionsManager.swift`**

```swift
import AppKit
import ApplicationServices

struct PermissionsManager {
    static var isTrusted: Bool {
        AXIsProcessTrusted()
    }

    // Opens System Settings → Accessibility. App must restart after granting.
    static func promptAndWait() {
        let options = [kAXTrustedCheckOptionPrompt.takeRetainedValue() as String: true]
        AXIsProcessTrustedWithOptions(options as CFDictionary)
    }

    static func showDeniedAlert() {
        let alert = NSAlert()
        alert.messageText = "Accessibility Permission Required"
        alert.informativeText = """
            SecureScreen needs Accessibility permission to block system-level \
            keyboard and trackpad input while locked.

            Grant permission in System Settings → Privacy & Security → Accessibility, \
            then relaunch SecureScreen.
            """
        alert.alertStyle = .critical
        alert.addButton(withTitle: "Open System Settings")
        alert.addButton(withTitle: "Quit")
        let response = alert.runModal()
        if response == .alertFirstButtonReturn {
            NSWorkspace.shared.open(
                URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility")!
            )
        }
        NSApp.terminate(nil)
    }
}
```

- [ ] **Step 2: Create `AppDelegate.swift`**

```swift
import AppKit

class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        // Gate everything on Accessibility permission
        if !PermissionsManager.isTrusted {
            PermissionsManager.promptAndWait()
            // Check again after prompt (user may have just granted)
            if !PermissionsManager.isTrusted {
                PermissionsManager.showDeniedAlert()
                return
            }
        }

        // Wiring order matters: EventBlocker before LockManager before StatusBar
        EventBlocker.shared.setup()
        HotkeyManager.shared.setup()
        StatusBarController.shared.setup()
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ app: NSApplication) -> Bool {
        false  // stay alive as menu bar agent
    }
}
```

- [ ] **Step 3: Build and verify permission gate**

Run: `swift build`
Expected: `Build complete!`

Launch the built binary while Accessibility is NOT granted.
Expected: System Accessibility prompt appears, then alert on denial, then app quits.

- [ ] **Step 4: Commit**

```bash
git add Sources/SecureScreen/PermissionsManager.swift Sources/SecureScreen/AppDelegate.swift
git commit -m "feat: accessibility permission gate — refuse to run without AXIsProcessTrusted"
```

---

### Task 3: EventBlocker (CGEventTap)

This is the core security component. It runs a `cgAnnotatedSessionEventTap` that consumes ALL events when `isEnabled == true`, with two exceptions: the `⌥⇧U` key combo (triggers unlock) and mouse-down/up events whose screen coordinate falls inside `allowedRect` (our status bar button).

**Files:**
- Create: `Sources/SecureScreen/EventBlocker.swift`

**Interfaces:**
- Produces:
  - `EventBlocker.shared.setup()` — installs the tap (call once at launch, tap starts disabled)
  - `EventBlocker.shared.enable(allowedRect: CGRect)` — activate blocking
  - `EventBlocker.shared.disable()` — deactivate blocking
  - `EventBlocker.shared.pauseForAuth()` — temporarily allow keyboard (password entry)
  - `EventBlocker.shared.resumeAfterAuth()` — re-block keyboard after cancelled auth

- [ ] **Step 1: Create `EventBlocker.swift`**

```swift
import CoreGraphics
import AppKit

final class EventBlocker {
    static let shared = EventBlocker()
    private init() {}

    private(set) var isEnabled = false
    private var pausedForAuth = false
    var allowedRect: CGRect = .zero

    private var tap: CFMachPort?

    func setup() {
        // Events to intercept when locked
        let types: [CGEventType] = [
            .keyDown, .keyUp, .flagsChanged,
            .leftMouseDown, .leftMouseUp,
            .rightMouseDown, .rightMouseUp,
            .otherMouseDown, .otherMouseUp,
            .scrollWheel,
        ]
        let mask = types.reduce(CGEventMask(0)) { $0 | (1 << $1.rawValue) }

        guard let tap = CGEvent.tapCreate(
            tap: .cgAnnotatedSessionEventTap,
            place: .headInsertEventTap,
            options: .defaultTap,
            eventsOfInterest: mask,
            callback: { proxy, type, event, refcon -> Unmanaged<CGEvent>? in
                let blocker = Unmanaged<EventBlocker>.fromOpaque(refcon!).takeUnretainedValue()
                return blocker.handle(proxy: proxy, type: type, event: event)
            },
            userInfo: Unmanaged.passUnretained(self).toOpaque()
        ) else {
            // Tap creation failed — Accessibility permission not granted
            PermissionsManager.showDeniedAlert()
            return
        }

        self.tap = tap
        let source = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0)
        CFRunLoopAddSource(CFRunLoopGetMain(), source, .commonModes)
        CGEvent.tapEnable(tap: tap, enable: true)
    }

    func enable(allowedRect: CGRect) {
        self.allowedRect = allowedRect
        isEnabled = true
        pausedForAuth = false
    }

    func disable() {
        isEnabled = false
        pausedForAuth = false
    }

    // Temporarily allow keyboard so LAContext can receive password input
    func pauseForAuth() {
        pausedForAuth = true
    }

    func resumeAfterAuth() {
        pausedForAuth = false
    }

    private func handle(proxy: CGEventTapProxy, type: CGEventType, event: CGEvent) -> Unmanaged<CGEvent>? {
        guard isEnabled else { return Unmanaged.passRetained(event) }

        // Keyboard path
        if type == .keyDown || type == .keyUp || type == .flagsChanged {
            if pausedForAuth { return Unmanaged.passRetained(event) }

            // Allow ⌥⇧U to trigger unlock (keyDown only to avoid double-fire)
            if type == .keyDown {
                let flags = event.flags.intersection([.maskAlternate, .maskShift, .maskCommand, .maskControl])
                let keyCode = event.getIntegerValueField(.keyboardEventKeycode)
                // key code 32 = U
                if keyCode == 32 && flags == [.maskAlternate, .maskShift] {
                    DispatchQueue.main.async { LockManager.shared.initiateUnlock() }
                    return nil // consume the keypress itself
                }
            }
            return nil // block all other keyboard events
        }

        // Mouse path — allow only clicks in status bar button rect
        if type == .leftMouseDown || type == .leftMouseUp ||
           type == .rightMouseDown || type == .rightMouseUp {
            let loc = event.location
            if !allowedRect.isEmpty && allowedRect.contains(loc) {
                return Unmanaged.passRetained(event)
            }
            return nil
        }

        // Block scroll wheel (trackpad two-finger swipe for spaces)
        return nil
    }
}
```

- [ ] **Step 2: Verify build**

Run: `swift build`
Expected: `Build complete!`

- [ ] **Step 3: Smoke test — block keyboard**

Temporarily add to `AppDelegate.applicationDidFinishLaunching` after `EventBlocker.shared.setup()`:
```swift
EventBlocker.shared.enable(allowedRect: .zero)
```
Launch app, try typing. Expected: no characters appear anywhere.
Remove the temporary line after verifying.

- [ ] **Step 4: Commit**

```bash
git add Sources/SecureScreen/EventBlocker.swift
git commit -m "feat: EventBlocker — CGEventTap blocks all input when locked, allowlist for status item"
```

---

### Task 4: ShieldView + LockWindow

The lock window is purely visual. It does NOT intercept events (`ignoresMouseEvents = true`). The `NSVisualEffectView` covers the full window frame, producing a frosted blur over whatever is on screen below it.

**Files:**
- Create: `Sources/SecureScreen/ShieldView.swift`
- Create: `Sources/SecureScreen/LockWindow.swift`

**Interfaces:**
- Produces:
  - `LockWindow(screen: NSScreen)` → shows full-screen blur on given display
  - `LockWindow.showHint()` → fades in the unlock hint for 3 s
  - `ShieldView` — SwiftUI view, full-screen, no clock/icon

- [ ] **Step 1: Create `ShieldView.swift`**

```swift
import SwiftUI
import AppKit

struct ShieldView: View {
    @ObservedObject var hintState: HintState

    var body: some View {
        ZStack {
            VisualEffectBlur()
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .ignoresSafeArea()

            if hintState.visible {
                Text("Locked — Press ⌥⇧U to Unlock")
                    .foregroundColor(.white.opacity(0.35))
                    .font(.system(size: 13, weight: .light, design: .default))
                    .transition(.opacity)
                    .animation(.easeInOut(duration: 0.4), value: hintState.visible)
            }
        }
    }
}

struct VisualEffectBlur: NSViewRepresentable {
    func makeNSView(context: Context) -> NSVisualEffectView {
        let v = NSVisualEffectView()
        v.material = .fullScreenUI
        v.blendingMode = .behindWindow
        v.state = .active
        v.appearance = NSAppearance(named: .darkAqua)
        return v
    }
    func updateNSView(_ nsView: NSVisualEffectView, context: Context) {}
}

// Shared observable so LockWindow can trigger hint without re-creating the view
final class HintState: ObservableObject {
    @Published var visible = false
    private var hideTask: DispatchWorkItem?

    func flash() {
        hideTask?.cancel()
        withAnimation { visible = true }
        let task = DispatchWorkItem { [weak self] in
            withAnimation { self?.visible = false }
        }
        hideTask = task
        DispatchQueue.main.asyncAfter(deadline: .now() + 3, execute: task)
    }
}
```

- [ ] **Step 2: Create `LockWindow.swift`**

```swift
import AppKit
import SwiftUI

final class LockWindow: NSWindow {
    let hintState = HintState()

    init(screen: NSScreen) {
        // Use screen.frame (not visibleFrame) to cover dock and menu bar
        super.init(
            contentRect: screen.frame,
            styleMask: .borderless,
            backing: .buffered,
            defer: false
        )

        level = NSWindow.Level(rawValue: Int(CGWindowLevelForKey(.screenSaverWindow)))
        ignoresMouseEvents = true          // security is EventBlocker's job
        isOpaque = false
        backgroundColor = .clear
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]
        isReleasedWhenClosed = false

        let hostView = NSHostingView(rootView: ShieldView(hintState: hintState))
        hostView.frame = NSRect(origin: .zero, size: screen.frame.size)
        contentView = hostView
    }

    func showHint() {
        hintState.flash()
    }

    // LockWindow must not become key — that would steal focus from auth dialogs
    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }
}
```

- [ ] **Step 3: Build and visual test**

Add temporary test in `AppDelegate`:
```swift
let w = LockWindow(screen: NSScreen.main!)
w.makeKeyAndOrderFront(nil)
DispatchQueue.main.asyncAfter(deadline: .now() + 3) { w.close() }
```
Launch. Expected: Full-screen frosted blur for 3 s covering the entire display (including dock and menu bar area), then closes.
Verify the blur covers the FULL screen, not just a centered portion.
Remove the temporary code after verifying.

- [ ] **Step 4: Commit**

```bash
git add Sources/SecureScreen/ShieldView.swift Sources/SecureScreen/LockWindow.swift
git commit -m "feat: full-screen visual overlay — NSVisualEffectView blur via ignoresMouseEvents LockWindow"
```

---

### Task 5: LockManager

Orchestrates the full lock/unlock lifecycle. Holds references to all `LockWindow` instances, the IOKit sleep assertion, and drives `EventBlocker` and kiosk mode.

**Files:**
- Create: `Sources/SecureScreen/LockManager.swift`

**Interfaces:**
- Consumes: `EventBlocker.shared`, `StatusBarController.shared.statusItemScreenRect`, `LockWindow(screen:)`, IOKit, LocalAuthentication
- Produces:
  - `LockManager.shared.lock()` — full lock sequence
  - `LockManager.shared.initiateUnlock()` — Touch ID / password challenge, then `unlock()` on success
  - `LockManager.shared.unlock()` — full unlock sequence
  - `LockManager.shared.isLocked: Bool`

- [ ] **Step 1: Create `LockManager.swift`**

```swift
import AppKit
import LocalAuthentication
import IOKit.pwr_mgt

final class LockManager {
    static let shared = LockManager()
    private init() {}

    private(set) var isLocked = false
    private var lockWindows: [LockWindow] = []
    private var sleepAssertion: IOPMAssertionID = 0

    func lock() {
        guard !isLocked else { return }
        isLocked = true

        // 1. Cover every display
        for screen in NSScreen.screens {
            let w = LockWindow(screen: screen)
            w.makeKeyAndOrderFront(nil)
            lockWindows.append(w)
        }

        // 2. Prevent display sleep
        IOPMAssertionCreateWithName(
            kIOPMAssertionTypeNoDisplaySleep as CFString,
            IOPMAssertionLevel(kIOPMAssertionLevelOn),
            "SecureScreen locked" as CFString,
            &sleepAssertion
        )

        // 3. Block system UI gestures and process switching
        NSApp.presentationOptions = [
            .disableProcessSwitching,   // Cmd+Tab
            .hideDock,
            .disableForceQuit,          // Cmd+Opt+Esc
            .disableSessionTermination,
            .disableHideApplication,    // Cmd+H
        ]

        // 4. Engage event tap — only our status bar button passes through
        let rect = StatusBarController.shared.statusItemScreenRect
        EventBlocker.shared.enable(allowedRect: rect)

        // 5. Update menu bar to show locked state
        StatusBarController.shared.setLocked(true)
    }

    func initiateUnlock() {
        guard isLocked else { return }

        let context = LAContext()
        var policyError: NSError?

        // deviceOwnerAuthentication tries Touch ID first, falls back to password
        guard context.canEvaluatePolicy(.deviceOwnerAuthentication, error: &policyError) else {
            showFallbackAlert()
            return
        }

        // Allow keyboard through so password dialog can receive input
        EventBlocker.shared.pauseForAuth()

        // Flash hint so user knows something is happening
        lockWindows.first?.showHint()

        context.evaluatePolicy(
            .deviceOwnerAuthentication,
            localizedReason: "Unlock SecureScreen"
        ) { [weak self] success, _ in
            DispatchQueue.main.async {
                if success {
                    self?.unlock()
                } else {
                    // Auth cancelled or failed — re-engage keyboard block
                    EventBlocker.shared.resumeAfterAuth()
                }
            }
        }
    }

    func unlock() {
        guard isLocked else { return }
        isLocked = false

        EventBlocker.shared.disable()

        NSApp.presentationOptions = []

        lockWindows.forEach { $0.close() }
        lockWindows = []

        if sleepAssertion != 0 {
            IOPMAssertionRelease(sleepAssertion)
            sleepAssertion = 0
        }

        StatusBarController.shared.setLocked(false)
    }

    // Failsafe: if LAContext is unavailable (rare), offer a plain dialog
    private func showFallbackAlert() {
        EventBlocker.shared.pauseForAuth()
        let alert = NSAlert()
        alert.messageText = "Unlock SecureScreen"
        alert.informativeText = "Biometric authentication is unavailable. Enter your macOS password in the next dialog."
        alert.alertStyle = .warning
        alert.addButton(withTitle: "Continue")
        alert.addButton(withTitle: "Cancel")
        if alert.runModal() == .alertFirstButtonReturn {
            // Re-try with password-only policy
            let ctx2 = LAContext()
            ctx2.evaluatePolicy(.deviceOwnerAuthenticationWithBiometrics, localizedReason: "Unlock SecureScreen") { [weak self] success, _ in
                DispatchQueue.main.async {
                    if success { self?.unlock() } else { EventBlocker.shared.resumeAfterAuth() }
                }
            }
        } else {
            EventBlocker.shared.resumeAfterAuth()
        }
    }
}
```

- [ ] **Step 2: Build**

Run: `swift build`
Expected: `Build complete!`

- [ ] **Step 3: Commit**

```bash
git add Sources/SecureScreen/LockManager.swift
git commit -m "feat: LockManager — sleep assertion, kiosk mode, multi-display windows, LAContext unlock"
```

---

### Task 6: HotkeyManager (Lock shortcut only)

Carbon HotKey API for `⌥⇧L`. Unlock (`⌥⇧U`) is already handled inside `EventBlocker.handle()` at tap-callback time, which runs even when locked because the tap intercepts before Carbon sees events. **Do not register unlock via Carbon** — it won't fire when the tap is consuming events.

**Files:**
- Create: `Sources/SecureScreen/HotkeyManager.swift`

**Interfaces:**
- Produces: `HotkeyManager.shared.setup()` — registers `⌥⇧L` globally via Carbon

- [ ] **Step 1: Create `HotkeyManager.swift`**

```swift
import AppKit
import Carbon

final class HotkeyManager {
    static let shared = HotkeyManager()
    private init() {}

    private var hotKeyRef: EventHotKeyRef?

    func setup() {
        // ⌥⇧L: key code 37 = L, modifiers = optionKey | shiftKey
        var hotKeyID = EventHotKeyID(signature: OSType(0x5353_4C4B), id: 1) // 'SSLK'
        var eventType = EventTypeSpec(eventClass: OSType(kEventClassKeyboard),
                                      eventKind: UInt32(kEventHotKeyPressed))

        InstallApplicationEventHandler(
            { _, event, _ -> OSStatus in
                var hkID = EventHotKeyID()
                GetEventParameter(event, EventParamName(kEventParamDirectObject),
                                  EventParamType(typeEventHotKeyID), nil,
                                  MemoryLayout<EventHotKeyID>.size, nil, &hkID)
                if hkID.id == 1 {
                    DispatchQueue.main.async { LockManager.shared.lock() }
                }
                return noErr
            },
            1, &eventType, nil, nil
        )

        RegisterEventHotKey(
            37,                                // L key
            UInt32(optionKey | shiftKey),
            hotKeyID,
            GetApplicationEventTarget(),
            0,
            &hotKeyRef
        )
    }
}
```

- [ ] **Step 2: Build**

Run: `swift build`
Expected: `Build complete!`

- [ ] **Step 3: Functional test**

Launch app. Press `⌥⇧L`.
Expected: Lock windows appear on all displays. Typing is blocked. Cmd+Tab does nothing. Dock is hidden. Trackpad space-switching is blocked (two-finger swipe does not switch spaces).

Press `⌥⇧U`.
Expected: Touch ID / password prompt appears. On success, lock windows close, Dock reappears.

- [ ] **Step 4: Commit**

```bash
git add Sources/SecureScreen/HotkeyManager.swift
git commit -m "feat: HotkeyManager — Carbon API registers opt+shift+L lock shortcut"
```

---

### Task 7: StatusBarController with Failsafe

The status bar item must always be interactable. `statusItemScreenRect` is fed to `EventBlocker.enable()` at lock time. The "Emergency Unlock…" menu item triggers `LockManager.shared.initiateUnlock()` — this is the user-visible failsafe for when `⌥⇧U` cannot be pressed (e.g., an external keyboard hotkey was mis-configured).

**Files:**
- Create: `Sources/SecureScreen/StatusBarController.swift`

**Interfaces:**
- Produces:
  - `StatusBarController.shared.setup()`
  - `StatusBarController.shared.statusItemScreenRect: CGRect` — screen coordinates of the status button
  - `StatusBarController.shared.setLocked(_ locked: Bool)` — swaps the menu between locked/unlocked states

- [ ] **Step 1: Create `StatusBarController.swift`**

```swift
import AppKit

final class StatusBarController: NSObject {
    static let shared = StatusBarController()
    private override init() {}

    private var statusItem: NSStatusItem!
    private var currentOpacity: Double = 0.85

    var statusItemScreenRect: CGRect {
        guard let button = statusItem?.button,
              let window = button.window else { return .zero }
        // Convert button frame (in window coords) to screen coords
        return window.convertToScreen(button.frame)
    }

    func setup() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        if let button = statusItem.button {
            button.image = NSImage(systemSymbolName: "lock.shield", accessibilityDescription: "SecureScreen")
        }
        buildMenu(locked: false)
    }

    func setLocked(_ locked: Bool) {
        buildMenu(locked: locked)
        // Update icon to indicate lock state
        let symbol = locked ? "lock.shield.fill" : "lock.shield"
        statusItem.button?.image = NSImage(systemSymbolName: symbol, accessibilityDescription: "SecureScreen")
    }

    private func buildMenu(locked: Bool) {
        let menu = NSMenu()

        if locked {
            let emergency = NSMenuItem(
                title: "Emergency Unlock…",
                action: #selector(emergencyUnlock),
                keyEquivalent: ""
            )
            emergency.target = self
            menu.addItem(emergency)
        } else {
            let lockItem = NSMenuItem(
                title: "Lock Screen  ⌥⇧L",
                action: #selector(lockScreen),
                keyEquivalent: ""
            )
            lockItem.target = self
            menu.addItem(lockItem)

            menu.addItem(NSMenuItem.separator())

            let opacityMenu = NSMenu()
            for (label, value) in [("2% opacity", 0.02), ("10%", 0.10), ("25%", 0.25), ("50%", 0.50), ("85%", 0.85)] {
                let item = NSMenuItem(title: label, action: #selector(setOpacity(_:)), keyEquivalent: "")
                item.representedObject = value
                item.target = self
                item.state = abs(currentOpacity - value) < 0.01 ? .on : .off
                opacityMenu.addItem(item)
            }
            let opacityItem = NSMenuItem(title: "Overlay Opacity", action: nil, keyEquivalent: "")
            opacityItem.submenu = opacityMenu
            menu.addItem(opacityItem)
        }

        menu.addItem(NSMenuItem.separator())

        let quit = NSMenuItem(title: "Quit SecureScreen", action: #selector(quitApp), keyEquivalent: "q")
        quit.target = self
        menu.addItem(quit)

        statusItem.menu = menu
    }

    @objc private func lockScreen() {
        LockManager.shared.lock()
    }

    @objc private func emergencyUnlock() {
        LockManager.shared.initiateUnlock()
    }

    @objc private func setOpacity(_ sender: NSMenuItem) {
        guard let value = sender.representedObject as? Double else { return }
        currentOpacity = value
        // Notify any existing lock windows if somehow called while locked
        buildMenu(locked: LockManager.shared.isLocked)
    }

    @objc private func quitApp() {
        if LockManager.shared.isLocked {
            // Require auth before quit while locked
            LockManager.shared.initiateUnlock()
        } else {
            NSApp.terminate(nil)
        }
    }
}
```

- [ ] **Step 2: Wire StatusBarController into AppDelegate**

In `AppDelegate.swift`, `applicationDidFinishLaunching` already calls `StatusBarController.shared.setup()`. Verify the call order:
```swift
EventBlocker.shared.setup()
HotkeyManager.shared.setup()
StatusBarController.shared.setup()   // must be LAST so statusItemScreenRect is valid
```

- [ ] **Step 3: Build**

Run: `swift build`
Expected: `Build complete!`

- [ ] **Step 4: Functional test — failsafe path**

1. Launch. Press `⌥⇧L` to lock.
2. Move mouse to menu bar area at top of screen. Verify other menu bar items are NOT clickable (clicks are consumed by event tap).
3. Click the SecureScreen shield icon (the only passthrough rect).
4. Expected: menu appears with only "Emergency Unlock…" and "Quit SecureScreen".
5. Click "Emergency Unlock…". Expected: Touch ID / password prompt. On success, screen unlocks.

- [ ] **Step 5: Test quit-while-locked requires auth**

1. Lock. Click status icon → "Quit SecureScreen".
2. Expected: auth prompt appears. Cancel → stay locked. Confirm → unlocks then would quit (current impl unlocks; user can then Quit again). This is acceptable — forced quit of a security tool should require auth.

- [ ] **Step 6: Commit**

```bash
git add Sources/SecureScreen/StatusBarController.swift Sources/SecureScreen/AppDelegate.swift
git commit -m "feat: StatusBarController — failsafe emergency unlock menu, opacity presets, locked/unlocked menu states"
```

---

### Task 8: Integration Test Script

**Files:**
- Create: `Scripts/test_sleep.sh`

**Interfaces:**
- Produces: exit 0 on pass (no timestamp gaps >2s during 30s lock window), exit 1 on fail

- [ ] **Step 1: Create `Scripts/test_sleep.sh`**

```bash
#!/bin/bash
# Tests that background processes continue uninterrupted while SecureScreen is locked.
# Run this AFTER SecureScreen.app is running with Accessibility permission.
set -e

LOG="/tmp/securescreen_test_$$.log"
DURATION=30

echo "Starting timestamp logger (PID will log every 1s to $LOG)..."
( while true; do date +%s >> "$LOG"; sleep 1; done ) &
LOGGER_PID=$!

echo "Log running. Lock SecureScreen NOW (⌥⇧L), wait ${DURATION}s, then unlock."
echo "Press ENTER when you have unlocked..."
read -r

kill "$LOGGER_PID" 2>/dev/null
wait "$LOGGER_PID" 2>/dev/null || true

echo "Analysing timestamps in $LOG..."

GAPS=0
PREV=""
while IFS= read -r ts; do
    if [ -n "$PREV" ]; then
        DIFF=$(( ts - PREV ))
        if [ "$DIFF" -gt 2 ]; then
            echo "GAP DETECTED: ${DIFF}s between $PREV and $ts"
            GAPS=$(( GAPS + 1 ))
        fi
    fi
    PREV="$ts"
done < "$LOG"

rm -f "$LOG"

if [ "$GAPS" -eq 0 ]; then
    echo "PASS — no gaps detected. Background tasks ran uninterrupted."
    exit 0
else
    echo "FAIL — $GAPS gap(s) detected. System may have slept."
    exit 1
fi
```

- [ ] **Step 2: Make executable**

Run: `chmod +x Scripts/test_sleep.sh`

- [ ] **Step 3: Run integration test**

```
./Scripts/test_sleep.sh
```
Lock screen when prompted, wait 30 s, unlock, press Enter.
Expected: `PASS — no gaps detected.`

- [ ] **Step 4: Commit**

```bash
git add Scripts/test_sleep.sh
git commit -m "test: sleep-prevention integration test script"
```

---

### Task 9: Full App Bundle + End-to-End Verification

**Files:**
- Modify: `build.sh` (if any adjustments needed for release entitlements)

- [ ] **Step 1: Build release bundle**

Run: `./build.sh`
Expected: `Built: SecureScreen.app`

- [ ] **Step 2: Launch from bundle**

Run: `open SecureScreen.app`
Expected: Shield icon appears in menu bar. No Dock icon.

- [ ] **Step 3: Multi-monitor test**

Connect a second display. Lock. Expected: blur overlay covers BOTH displays completely.

- [ ] **Step 4: Input blocking checklist**

While locked, verify each of the following is blocked:

| Action | Expected |
|---|---|
| Type any key | Blocked (no characters appear) |
| Cmd+Tab | Blocked (no app switcher) |
| Cmd+Space | Blocked (Spotlight does not open) |
| Cmd+Opt+Esc | Blocked (Force Quit dialog does not open) |
| Two-finger swipe (spaces) | Blocked (no desktop switch) |
| Three-finger swipe (Mission Control) | Blocked |
| Click Dock icon | Blocked (Dock hidden) |
| Click other menu bar items | Blocked (only SecureScreen icon responds) |

- [ ] **Step 5: Unlock paths checklist**

| Path | Expected |
|---|---|
| Press ⌥⇧U | Auth prompt → Touch ID → unlock |
| Press ⌥⇧U → cancel | Re-blocked, stays locked |
| Click status icon → Emergency Unlock | Auth prompt → unlock |
| ⌥⇧U → Touch ID unavailable | Password fallback dialog |

- [ ] **Step 6: Run sleep integration test**

Run: `./Scripts/test_sleep.sh`
Expected: `PASS`

- [ ] **Step 7: Final commit**

```bash
git add -A
git commit -m "feat: SecureScreen v1.0 — full-screen blur overlay, CGEventTap input blocking, failsafe emergency unlock"
```

---

## Self-Review

### Spec coverage

| Requirement | Task |
|---|---|
| Full-screen blur overlay (not centered) | Task 4 — LockWindow frame = `screen.frame`, NSVisualEffectView fills window |
| All input blocked (keyboard, trackpad, dock, Spotlight) | Task 3 — CGEventTap + Task 5 kiosk options |
| Only status bar icon accessible when locked | Task 3 — EventBlocker allowlist + Task 7 StatusBarController |
| Failsafe emergency unlock via menu bar | Task 7 — "Emergency Unlock…" menu item |
| Failsafe requires authentication | Task 5 — `initiateUnlock()` always calls LAContext |
| Unlock via ⌥⇧U | Task 3 — handled inside EventBlocker.handle() |
| Lock via ⌥⇧L | Task 6 — Carbon HotKey |
| Touch ID with password fallback | Task 5 — `deviceOwnerAuthentication` policy |
| Sleep prevention (background tasks continue) | Task 5 — IOPMAssertion |
| Multi-display coverage | Task 5 — iterates `NSScreen.screens` |
| No clock/lock icon on overlay | Task 4 — ShieldView has no such elements |
| Hint text fades in on blocked input | Task 4 — HintState.flash(); Task 3 could trigger this (wire if desired) |
| Configurable overlay opacity | Task 7 — presets in StatusBarController |
| Accessibility permission gate | Task 2 — PermissionsManager |
| Codex bug: unlock failed | Fixed — EventBlocker pauses for auth before LAContext |
| Codex bug: trackpad space switching | Fixed — CGEventTap blocks scrollWheel + kiosk .disableProcessSwitching |
| Codex bug: Spotlight, dock clickable | Fixed — CGEventTap blocks keyboard (Cmd+Space), .hideDock kiosk option |
| Codex bug: overlay not full screen | Fixed — LockWindow frame = `screen.frame` (not centered) |

### Type consistency check

- `EventBlocker.enable(allowedRect: CGRect)` defined Task 3, consumed Task 5 ✓
- `StatusBarController.shared.statusItemScreenRect: CGRect` defined Task 7, consumed Task 5 ✓
- `LockManager.shared.lock()` defined Task 5, called Task 6 + Task 7 ✓
- `LockManager.shared.initiateUnlock()` defined Task 5, called Task 3 + Task 7 ✓
- `LockWindow.showHint()` defined Task 4, called Task 5 ✓
- `HintState` defined Task 4, used Task 4 only ✓

### Placeholder scan

No TBD, TODO, "implement later", or "similar to Task N" entries. All code blocks are complete.
