import SwiftUI
import AppKit

/// Brand-exact colors from the design spec that don't correspond to a
/// system semantic color (most greys/materials in the popup and history
/// window adapt to light/dark automatically via `.primary`/materials and
/// don't need an entry here).
enum DesignColors {
    /// The accent blue used for selected rows in both the compact popup
    /// and the full history window: #0a6cff in light mode, #0a84ff in dark
    /// mode - close to, but not exactly, the system accent color, so it's
    /// expressed as its own dynamic color rather than `Color.accentColor`.
    static let accentBlue = Color(
        NSColor(name: nil) { appearance in
            let isDark = appearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua
            return isDark
                ? NSColor(red: 10 / 255, green: 132 / 255, blue: 255 / 255, alpha: 1)
                : NSColor(red: 10 / 255, green: 108 / 255, blue: 255 / 255, alpha: 1)
        }
    )
}
