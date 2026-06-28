import AppKit
import Carbon

final class HotkeyManager {
    static let shared = HotkeyManager()
    private init() {}

    private var lockHotKeyRef: EventHotKeyRef?
    private var unlockHotKeyRef: EventHotKeyRef?

    func setup() {
        var eventType = EventTypeSpec(eventClass: OSType(kEventClassKeyboard),
                                      eventKind: UInt32(kEventHotKeyPressed))

        // Carbon hotkeys fire before the CGAnnotatedSessionEventTap, so ⌥⇧U here is a reliable
        // fallback: when the tap is alive it also intercepts ⌥⇧U, but when the tap dies this
        // handler still fires because events reach the Carbon layer before the session tap.
        InstallEventHandler(
            GetApplicationEventTarget(),
            { _, event, _ -> OSStatus in
                var hkID = EventHotKeyID()
                GetEventParameter(event, EventParamName(kEventParamDirectObject),
                                  EventParamType(typeEventHotKeyID), nil,
                                  MemoryLayout<EventHotKeyID>.size, nil, &hkID)
                switch hkID.id {
                case 1:
                    DispatchQueue.main.async { LockManager.shared.lock() }
                case 2:
                    DispatchQueue.main.async {
                        if LockManager.shared.isLocked { LockManager.shared.initiateUnlock() }
                    }
                default: break
                }
                return noErr
            },
            1, &eventType, nil, nil
        )

        // ⌥⇧L → lock
        RegisterEventHotKey(
            37,
            UInt32(optionKey | shiftKey),
            EventHotKeyID(signature: OSType(0x5353_4C4B), id: 1),
            GetApplicationEventTarget(),
            0,
            &lockHotKeyRef
        )

        // ⌥⇧U → unlock (Carbon fallback for when tap is dead)
        RegisterEventHotKey(
            32,
            UInt32(optionKey | shiftKey),
            EventHotKeyID(signature: OSType(0x5353_4C4B), id: 2),
            GetApplicationEventTarget(),
            0,
            &unlockHotKeyRef
        )
    }
}
