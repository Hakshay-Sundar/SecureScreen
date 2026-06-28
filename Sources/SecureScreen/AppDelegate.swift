import AppKit

class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        // Wiring order matters: EventBlocker before HotkeyManager before StatusBarController
        // If Accessibility is not granted, EventBlocker.setup() shows the denial alert and quits.
        EventBlocker.shared.setup()
        HotkeyManager.shared.setup()
        StatusBarController.shared.setup()
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ app: NSApplication) -> Bool {
        false  // stay alive as menu bar agent
    }
}
