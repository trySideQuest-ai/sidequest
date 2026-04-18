import AppKit
import Carbon

// Global hotkey registration via Carbon RegisterEventHotKey.
// No Accessibility prompt (key advantage over NSEvent.addGlobalMonitorForEvents).
//
// Lifecycle: register() installs ⌘⌃O + ⌘⌃D handlers. unregister() tears down.
// Callers (presenter) should register when queue becomes non-empty,
// unregister when it empties — avoids conflicting with user's own shortcuts.

@MainActor
final class HotkeyManager {
    var onOpen: (() -> Void)?
    var onDismiss: (() -> Void)?

    private var hotKeyRefs: [EventHotKeyRef?] = []
    private var handlerRef: EventHandlerRef?

    // Static bridge — C callback can't capture Swift context
    nonisolated(unsafe) private static weak var active: HotkeyManager?

    init() {}

    deinit {
        for ref in hotKeyRefs { if let r = ref { UnregisterEventHotKey(r) } }
        if let h = handlerRef { RemoveEventHandler(h) }
        if HotkeyManager.active === self { HotkeyManager.active = nil }
    }

    // MARK: - Public

    func register() {
        if handlerRef != nil { return } // already registered — idempotent

        HotkeyManager.active = self

        var eventType = EventTypeSpec(
            eventClass: OSType(kEventClassKeyboard),
            eventKind: UInt32(kEventHotKeyPressed)
        )

        InstallEventHandler(
            GetApplicationEventTarget(),
            { (_: EventHandlerCallRef?, event: EventRef?, _: UnsafeMutableRawPointer?) -> OSStatus in
                var hotKeyID = EventHotKeyID()
                let err = GetEventParameter(
                    event,
                    EventParamName(kEventParamDirectObject),
                    EventParamType(typeEventHotKeyID),
                    nil,
                    MemoryLayout<EventHotKeyID>.size,
                    nil,
                    &hotKeyID
                )
                guard err == noErr else { return err }
                HotkeyManager.fire(id: hotKeyID.id)
                return noErr
            },
            1,
            &eventType,
            nil,
            &handlerRef
        )

        let modifiers = UInt32(cmdKey | controlKey)
        let keys: [(keyCode: UInt32, id: UInt32)] = [
            (31, 1), // 'o' → open
            (2,  2)  // 'd' → dismiss
        ]
        let signature = OSType(0x5351_5354) // "SQST"

        for k in keys {
            var ref: EventHotKeyRef?
            let hkID = EventHotKeyID(signature: signature, id: k.id)
            RegisterEventHotKey(k.keyCode, modifiers, hkID, GetApplicationEventTarget(), 0, &ref)
            hotKeyRefs.append(ref)
        }
    }

    func unregister() {
        for ref in hotKeyRefs { if let r = ref { UnregisterEventHotKey(r) } }
        hotKeyRefs.removeAll()
        if let h = handlerRef {
            RemoveEventHandler(h)
            handlerRef = nil
        }
        if HotkeyManager.active === self { HotkeyManager.active = nil }
    }

    // MARK: - Static dispatch (Carbon callback → MainActor)

    nonisolated private static func fire(id: UInt32) {
        Task { @MainActor in
            guard let m = HotkeyManager.active else { return }
            switch id {
            case 1: m.onOpen?()
            case 2: m.onDismiss?()
            default: break
            }
        }
    }
}
