import AppKit
import ServiceManagement

@MainActor
final class MenuBarController: NSObject, NSMenuDelegate {
    private var statusItem: NSStatusItem?
    private var launchAtLoginItem: NSMenuItem?
    private let watcher = PasteboardWatcher()
    private let hotkeyManager = HotkeyManager()

    func install() {
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        item.button?.image = NSImage(systemSymbolName: "doc.on.clipboard", accessibilityDescription: "Clipboard Manager")

        let menu = NSMenu()
        menu.addItem(NSMenuItem(title: "Open History", action: #selector(openHistory), keyEquivalent: ""))
        menu.addItem(NSMenuItem.separator())
        // Login items need a real .app bundle (see Scripts/install.sh); a
        // bare `swift run` binary can't register, so don't offer it there.
        if Bundle.main.bundleURL.pathExtension == "app" {
            let loginItem = NSMenuItem(title: "Launch at Login", action: #selector(toggleLaunchAtLogin), keyEquivalent: "")
            menu.addItem(loginItem)
            launchAtLoginItem = loginItem
            enableLaunchAtLoginOnFirstRun()
        }
        menu.addItem(NSMenuItem(title: "Quit", action: #selector(quit), keyEquivalent: "q"))
        for menuItem in menu.items {
            menuItem.target = self
        }
        menu.delegate = self
        item.menu = menu
        statusItem = item

        // Pasting synthesizes Cmd+V, which macOS silently drops without
        // Accessibility; ask up front instead of failing the first paste.
        // The literal value of kAXTrustedCheckOptionPrompt, which Swift 6
        // rejects as a non-concurrency-safe global.
        AXIsProcessTrustedWithOptions(["AXTrustedCheckOptionPrompt": true] as CFDictionary)

        watcher.start()
        hotkeyManager.onTrigger = { [weak self] in self?.openHistory() }
        hotkeyManager.start()
    }

    // Re-read the status every time the menu opens, since it can also be
    // changed from System Settings > General > Login Items.
    func menuNeedsUpdate(_ menu: NSMenu) {
        launchAtLoginItem?.state = SMAppService.mainApp.status == .enabled ? .on : .off
    }

    @objc private func openHistory() {
        PickerWindow.shared.show(history: watcher.store)
    }

    // On by default: the menu bar icon can be hidden behind the notch on a
    // crowded menu bar, so setup can't depend on reaching the toggle. Done
    // once only, so turning it off from the menu or System Settings sticks.
    private func enableLaunchAtLoginOnFirstRun() {
        let key = "didEnableLaunchAtLoginOnFirstRun"
        guard !UserDefaults.standard.bool(forKey: key) else { return }
        UserDefaults.standard.set(true, forKey: key)
        try? SMAppService.mainApp.register()
    }

    @objc private func toggleLaunchAtLogin() {
        let service = SMAppService.mainApp
        do {
            if service.status == .enabled {
                try service.unregister()
            } else {
                try service.register()
                if service.status == .requiresApproval {
                    SMAppService.openSystemSettingsLoginItems()
                }
            }
        } catch {
            let alert = NSAlert(error: error)
            alert.messageText = "Couldn't change Launch at Login"
            NSApp.activate(ignoringOtherApps: true)
            alert.runModal()
        }
    }

    @objc private func quit() {
        NSApp.terminate(nil)
    }
}
