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

        // Wiring order matters: EventBlocker before HotkeyManager before StatusBarController
        EventBlocker.shared.setup()
        HotkeyManager.shared.setup()
        StatusBarController.shared.setup()
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ app: NSApplication) -> Bool {
        false  // stay alive as menu bar agent
    }
}
