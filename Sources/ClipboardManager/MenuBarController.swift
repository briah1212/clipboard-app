import AppKit

final class MenuBarController {
    private var statusItem: NSStatusItem?
    private let watcher = PasteboardWatcher()
    private let hotkeyManager = HotkeyManager()

    func install() {
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        item.button?.image = NSImage(systemSymbolName: "doc.on.clipboard", accessibilityDescription: "Clipboard Manager")

        let menu = NSMenu()
        menu.addItem(NSMenuItem(title: "Open History", action: #selector(openHistory), keyEquivalent: ""))
        menu.addItem(NSMenuItem.separator())
        menu.addItem(NSMenuItem(title: "Quit", action: #selector(quit), keyEquivalent: "q"))
        for menuItem in menu.items {
            menuItem.target = self
        }
        item.menu = menu
        statusItem = item

        watcher.start()
        hotkeyManager.onTrigger = { [weak self] in self?.openHistory() }
        hotkeyManager.start()
    }

    @objc private func openHistory() {
        PickerWindow.shared.show(history: watcher.store)
    }

    @objc private func quit() {
        NSApp.terminate(nil)
    }
}
