import AppKit
import LocalAuthentication
import IOKit.pwr_mgt

final class LockManager {
    static let shared = LockManager()
    private init() {}

    private(set) var isLocked = false
    private var isAuthenticating = false
    private var lockWindows: [LockWindow] = []
    private var sleepAssertion: IOPMAssertionID = 0

    func lock() {
        guard !isLocked else { return }
        isLocked = true

        // 1. Cover every display
        for screen in NSScreen.screens {
            let w = LockWindow(screen: screen)
            w.alphaValue = StatusBarController.shared.currentOpacity
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
        guard isLocked, !isAuthenticating else { return }
        isAuthenticating = true

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
        lockWindows.forEach { $0.showHint() }

        context.evaluatePolicy(
            .deviceOwnerAuthentication,
            localizedReason: "Unlock SecureScreen"
        ) { [weak self] success, _ in
            DispatchQueue.main.async {
                if success {
                    self?.unlock()
                } else {
                    // Auth cancelled or failed — re-engage keyboard block
                    self?.isAuthenticating = false
                    EventBlocker.shared.resumeAfterAuth()
                }
            }
        }
    }

    func unlock() {
        guard isLocked else { return }
        isLocked = false
        isAuthenticating = false

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
            ctx2.evaluatePolicy(.deviceOwnerAuthentication, localizedReason: "Unlock SecureScreen") { [weak self] success, _ in
                DispatchQueue.main.async {
                    if success {
                        self?.unlock()
                    } else {
                        self?.isAuthenticating = false
                        EventBlocker.shared.resumeAfterAuth()
                    }
                }
            }
        } else {
            isAuthenticating = false
            EventBlocker.shared.resumeAfterAuth()
        }
    }
}
