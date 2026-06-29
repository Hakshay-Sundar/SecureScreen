import CoreGraphics
import AppKit

final class EventBlocker {
    static let shared = EventBlocker()
    private init() {}

    private(set) var isEnabled = false
    private var pausedForAuth = false
    var allowedRect: CGRect = .zero

    private var tap: CFMachPort?
    // Cached on setup(); menu bar sits at CG y ∈ [0, menuBarThreshold]
    private var menuBarThreshold: CGFloat = 44

    func setup() {
        // Events to intercept when locked
        let types: [CGEventType] = [
            .keyDown, .keyUp, .flagsChanged,
            .leftMouseDown, .leftMouseUp,
            .rightMouseDown, .rightMouseUp,
            .otherMouseDown, .otherMouseUp,
            .leftMouseDragged, .rightMouseDragged, .otherMouseDragged,
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
        menuBarThreshold = NSStatusBar.system.thickness + 4
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

    // Fully disable tap so LAContext auth dialog (cross-process SecurityAgent) receives all events
    func pauseForAuth() {
        pausedForAuth = true
        if let tap = tap { CGEvent.tapEnable(tap: tap, enable: false) }
    }

    func resumeAfterAuth() {
        pausedForAuth = false
        if let tap = tap { CGEvent.tapEnable(tap: tap, enable: true) }
    }

    // Fully disable tap during NSMenu tracking so dropdown items receive clicks
    func suspendForMenuTracking() {
        if let tap = tap { CGEvent.tapEnable(tap: tap, enable: false) }
    }

    func resumeFromMenuTracking() {
        // Only re-enable if still locked and not mid-auth
        if isEnabled && !pausedForAuth {
            if let tap = tap { CGEvent.tapEnable(tap: tap, enable: true) }
        }
    }

    func reenableTap() {
        guard let tap = tap else { return }
        CGEvent.tapEnable(tap: tap, enable: true)
    }

    // Check if loc (CG coords) falls in the menu bar strip of any screen.
    // The naive `loc.y < menuBarThreshold` only works for the primary display;
    // monitors arranged above the primary have negative y, making all their clicks pass.
    private func isInAnyMenuBar(_ loc: CGPoint) -> Bool {
        guard let primary = NSScreen.screens.first else { return loc.y < menuBarThreshold }
        let primaryH = primary.frame.height
        for screen in NSScreen.screens {
            // AppKit y-up → CG y-down: top of screen in CG = primaryH - screen.frame.maxY
            let cgTop = primaryH - screen.frame.maxY
            let menuBarRect = CGRect(x: screen.frame.minX, y: cgTop,
                                    width: screen.frame.width, height: menuBarThreshold)
            if menuBarRect.contains(loc) { return true }
        }
        return false
    }

    private func handle(proxy: CGEventTapProxy, type: CGEventType, event: CGEvent) -> Unmanaged<CGEvent>? {
        // macOS auto-disables the tap after a period of inactivity or under load.
        // Re-enable immediately so blocking stays live.
        if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
            if let tap = tap { CGEvent.tapEnable(tap: tap, enable: true) }
            return nil
        }

        guard isEnabled else { return Unmanaged.passRetained(event) }

        // Auth dialog in progress — let everything through (password UI needs keyboard + mouse)
        if pausedForAuth { return Unmanaged.passRetained(event) }

        // Pass modifier-only events through: suppressing flagsChanged corrupts macOS modifier
        // state, causing the ⌥⇧U check below to see wrong flags on subsequent keyDowns.
        if type == .flagsChanged {
            return Unmanaged.passRetained(event)
        }

        // Keyboard path
        if type == .keyDown || type == .keyUp {
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

        // Mouse path — allow only clicks/drags in status bar button rect
        if type == .leftMouseDown || type == .leftMouseUp ||
           type == .rightMouseDown || type == .rightMouseUp ||
           type == .leftMouseDragged || type == .rightMouseDragged || type == .otherMouseDragged {
            let loc = event.location
            if (!allowedRect.isEmpty && allowedRect.contains(loc)) || isInAnyMenuBar(loc) {
                return Unmanaged.passRetained(event)
            }
            return nil
        }

        // Block scroll wheel (trackpad two-finger swipe for spaces)
        return nil
    }
}
