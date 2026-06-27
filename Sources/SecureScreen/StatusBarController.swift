import AppKit

final class StatusBarController: NSObject {
    static let shared = StatusBarController()
    private override init() {}

    private var statusItem: NSStatusItem!
    private(set) var currentOpacity: Double = 0.85

    var statusItemScreenRect: CGRect {
        guard let button = statusItem?.button,
              let window = button.window else { return .zero }
        let apkRect = window.convertToScreen(button.frame)
        let screenHeight = window.screen?.frame.height ?? NSScreen.screens.first?.frame.height ?? 0
        // Convert AppKit screen coords (y-up) → CG/Quartz coords (y-down) for CGEvent.location comparison
        return CGRect(x: apkRect.minX,
                      y: screenHeight - apkRect.maxY,
                      width: apkRect.width,
                      height: apkRect.height)
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
            for (label, value) in [("2%", 0.02), ("10%", 0.10), ("25%", 0.25), ("50%", 0.50), ("85%", 0.85)] {
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

        let quitKey = locked ? "" : "q"
        let quit = NSMenuItem(title: "Quit SecureScreen", action: #selector(quitApp), keyEquivalent: quitKey)
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
        buildMenu(locked: LockManager.shared.isLocked)
    }

    @objc private func quitApp() {
        if LockManager.shared.isLocked {
            // ponytail: intentional — unlocks but does not auto-quit; user must press Quit again after unlock (deliberate friction)
            LockManager.shared.initiateUnlock()
        } else {
            NSApp.terminate(nil)
        }
    }
}
