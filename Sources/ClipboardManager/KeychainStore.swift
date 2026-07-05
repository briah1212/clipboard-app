import Foundation
import Security

/// Thin wrapper around the macOS Keychain for the one secret this app
/// needs - the Anthropic API key used by semantic search. Never stores or
/// logs the key value itself anywhere else (no plaintext file, no
/// UserDefaults, never embedded in source).
enum KeychainStore {
    private static let service = "com.clipboardmanager.anthropic-api-key"
    private static let account = "ClipboardManager"

    /// SecItemCopyMatching blocks the calling thread until it returns -
    /// including, when the item's ACL requires it, however long it takes
    /// the user to respond to the system's "app wants to access your
    /// keychain" authorization dialog. Running that on the main actor
    /// freezes the entire app (not just a small popup) for as long as
    /// that dialog is pending, which is easy to mistake for a hang if the
    /// dialog isn't obviously associated with this app's own window. A
    /// detached background task keeps the UI responsive while it waits.
    static func anthropicAPIKey() async -> String? {
        await Task.detached(priority: .userInitiated) {
            let query: [String: Any] = [
                kSecClass as String: kSecClassGenericPassword,
                kSecAttrService as String: service,
                kSecAttrAccount as String: account,
                kSecReturnData as String: true,
                kSecMatchLimit as String: kSecMatchLimitOne
            ]
            var result: AnyObject?
            let status = SecItemCopyMatching(query as CFDictionary, &result)
            guard status == errSecSuccess, let data = result as? Data else { return nil }
            return String(data: data, encoding: .utf8)
        }.value
    }
}
