import SwiftUI
import AppKit

/// Shared app-wide light/dark override. Toggled from the full history
/// window's toolbar and applied to both it and the compact popup (via
/// `.preferredColorScheme`, read from the same `@AppStorage` key in each
/// view) so the two stay visually consistent regardless of which window
/// the user toggled it from.
enum AppearancePreference {
    static let storageKey = "clipboardManager.prefersDarkMode"

    /// Used only as the `@AppStorage` default's initial value, the first
    /// time the app ever runs and no override has been saved yet - matches
    /// whatever the system appearance already is, so the first launch
    /// doesn't visibly change anything until the user actually toggles it.
    static var systemPrefersDark: Bool {
        // Safe: only ever evaluated as a SwiftUI View property default,
        // which is always constructed from the @MainActor window
        // controllers (PickerWindow/HistoryWindow) - never off-main-thread.
        // Uses `NSApplication.shared` rather than the `NSApp` global: `NSApp`
        // is only a weak reference that AppKit sets as a side effect of
        // `.shared` having been accessed at least once, so it can still be
        // nil this early (e.g. in a test process that never otherwise
        // touches it) even though `.shared` itself always self-initializes.
        MainActor.assumeIsolated {
            NSApplication.shared.effectiveAppearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua
        }
    }
}
