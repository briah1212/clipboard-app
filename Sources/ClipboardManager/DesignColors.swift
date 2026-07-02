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

    /// Flat, opaque panel background in the spirit of Raycast's clipboard
    /// history UI: a deep near-black navy in dark mode, a soft neutral
    /// off-white in light mode - deliberately not a translucent/vibrancy
    /// material, since Raycast's look is flat and information-dense rather
    /// than glassy.
    static let panelBackground = Color(
        NSColor(name: nil) { appearance in
            let isDark = appearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua
            return isDark
                ? NSColor(red: 24 / 255, green: 24 / 255, blue: 32 / 255, alpha: 1)
                : NSColor(red: 248 / 255, green: 248 / 255, blue: 250 / 255, alpha: 1)
        }
    )

    /// Hairline border around panels and controls on the flat background
    /// above, where a plain `.primary.opacity()` would be either too harsh
    /// or too faint in one of the two appearances.
    static let panelBorder = Color(
        NSColor(name: nil) { appearance in
            let isDark = appearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua
            return isDark ? .white.withAlphaComponent(0.09) : .black.withAlphaComponent(0.08)
        }
    )
}
