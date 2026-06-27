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
