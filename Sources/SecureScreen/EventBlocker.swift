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

        // Mouse path — allow only clicks/drags in status bar button rect
        if type == .leftMouseDown || type == .leftMouseUp ||
           type == .rightMouseDown || type == .rightMouseUp ||
           type == .leftMouseDragged || type == .rightMouseDragged || type == .otherMouseDragged {
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
