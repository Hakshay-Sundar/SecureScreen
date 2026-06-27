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
