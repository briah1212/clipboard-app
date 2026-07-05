import Foundation
import Security

/// Thin wrapper around the macOS Keychain for the one secret this app
/// needs - the Anthropic API key used by semantic search. Never stores or
/// logs the key value itself anywhere else (no plaintext file, no
/// UserDefaults, never embedded in source).
enum KeychainStore {
    private static let service = "com.clipboardmanager.anthropic-api-key"
    private static let account = "ClipboardManager"

    static var anthropicAPIKey: String? {
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
    }
}
