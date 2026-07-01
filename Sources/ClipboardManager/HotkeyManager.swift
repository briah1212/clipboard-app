import Foundation

/// Registers a global keyboard shortcut (target: Cmd+Shift+V) via Carbon's
/// RegisterEventHotKey. Implementation deferred; `onTrigger` fires when pressed.
final class HotkeyManager {
    var onTrigger: (() -> Void)?

    func start() {
        // TODO: register Carbon global hotkey and call onTrigger?()
    }

    func stop() {
        // TODO: unregister hotkey
    }
}
