import AppKit
import Carbon

final class HotkeyManager {
    static let shared = HotkeyManager()
    private init() {}

    private var hotKeyRef: EventHotKeyRef?

    func setup() {
        // ⌥⇧L: key code 37 = L, modifiers = optionKey | shiftKey
        let hotKeyID = EventHotKeyID(signature: OSType(0x5353_4C4B), id: 1) // 'SSLK'
        var eventType = EventTypeSpec(eventClass: OSType(kEventClassKeyboard),
                                      eventKind: UInt32(kEventHotKeyPressed))

        InstallEventHandler(
            GetApplicationEventTarget(),
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
