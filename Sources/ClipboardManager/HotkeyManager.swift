import Carbon.HIToolbox
import Foundation

/// Registers a global keyboard shortcut (Cmd+Shift+V) via Carbon's
/// RegisterEventHotKey, the standard mechanism for system-wide hotkeys
/// on macOS (AppKit/SwiftUI have no equivalent API).
final class HotkeyManager {
    static let hotKeyID = EventHotKeyID(signature: OSType(bitPattern: 0x434C4950), id: 1) // "CLIP"

    var onTrigger: (() -> Void)?

    private let keyCode: UInt32 = UInt32(kVK_ANSI_V)
    private let modifiers: UInt32 = UInt32(cmdKey | shiftKey)

    private var hotKeyRef: EventHotKeyRef?
    private var eventHandlerRef: EventHandlerRef?

    @discardableResult
    func start() -> Bool {
        guard hotKeyRef == nil else { return true }

        var eventType = EventTypeSpec(
            eventClass: OSType(kEventClassKeyboard),
            eventKind: UInt32(kEventHotKeyPressed)
        )

        let selfPtr = Unmanaged.passUnretained(self).toOpaque()
        let installStatus = InstallEventHandler(
            GetEventDispatcherTarget(),
            hotKeyEventHandler,
            1,
            &eventType,
            selfPtr,
            &eventHandlerRef
        )
        guard installStatus == noErr else { return false }

        let registerStatus = RegisterEventHotKey(
            keyCode,
            modifiers,
            Self.hotKeyID,
            GetEventDispatcherTarget(),
            0,
            &hotKeyRef
        )
        guard registerStatus == noErr else {
            stop()
            return false
        }
        return true
    }

    func stop() {
        if let hotKeyRef {
            UnregisterEventHotKey(hotKeyRef)
            self.hotKeyRef = nil
        }
        if let eventHandlerRef {
            RemoveEventHandler(eventHandlerRef)
            self.eventHandlerRef = nil
        }
    }

    /// Invoked from the C event handler once it identifies which hotkey
    /// fired. Exposed internally so tests can drive the dispatch logic
    /// directly instead of depending on real OS-level key delivery.
    func hotKeyPressed(id: UInt32) {
        guard id == Self.hotKeyID.id else { return }
        onTrigger?()
    }
}

private func hotKeyEventHandler(
    nextHandler: EventHandlerCallRef?,
    event: EventRef?,
    userData: UnsafeMutableRawPointer?
) -> OSStatus {
    guard let event, let userData else { return noErr }

    var pressedID = EventHotKeyID()
    let status = GetEventParameter(
        event,
        EventParamName(kEventParamDirectObject),
        EventParamType(typeEventHotKeyID),
        nil,
        MemoryLayout<EventHotKeyID>.size,
        nil,
        &pressedID
    )
    guard status == noErr else { return status }

    let manager = Unmanaged<HotkeyManager>.fromOpaque(userData).takeUnretainedValue()
    manager.hotKeyPressed(id: pressedID.id)
    return noErr
}
