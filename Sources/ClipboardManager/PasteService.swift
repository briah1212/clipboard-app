import AppKit

enum PasteService {
    static func paste(_ entry: ClipboardEntry, simulateKeystroke: Bool = true) {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()

        switch entry.content {
        case .text(let text):
            pasteboard.setString(text, forType: .string)
        case .fileURLs(let urls):
            // writeObjects, not setData, so multi-file selections paste
            // as multiple files instead of a single mangled item.
            pasteboard.writeObjects(urls.map { $0 as NSURL })
        case .image(let pngData):
            pasteboard.setData(pngData, forType: .png)
        case .color(let components):
            let color = NSColor(
                red: components.red,
                green: components.green,
                blue: components.blue,
                alpha: components.alpha
            )
            pasteboard.writeObjects([color])
        }

        if simulateKeystroke {
            simulatePasteKeystroke()
        }
    }

    private static func simulatePasteKeystroke() {
        // Requires Accessibility permission. Synthesizes Cmd+V.
        let source = CGEventSource(stateID: .hidSystemState)
        let vKeyCode: CGKeyCode = 9

        guard let keyDown = CGEvent(keyboardEventSource: source, virtualKey: vKeyCode, keyDown: true),
              let keyUp = CGEvent(keyboardEventSource: source, virtualKey: vKeyCode, keyDown: false) else {
            return
        }
        keyDown.flags = .maskCommand
        keyUp.flags = .maskCommand
        keyDown.post(tap: .cghidEventTap)
        keyUp.post(tap: .cghidEventTap)
    }
}
