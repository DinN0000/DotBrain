import Foundation
import Security

/// Secure storage for API keys using macOS Keychain
enum KeychainService {
    private static let service = "com.hwaa.ai-pkm-menubar"
    private static let claudeKeyAccount = "anthropic-api-key"
    private static let geminiKeyAccount = "gemini-api-key"

    // MARK: - Claude API Key (legacy compatibility)

    static func saveAPIKey(_ key: String) -> Bool {
        saveKey(key, account: claudeKeyAccount)
    }

    static func getAPIKey() -> String? {
        getKey(account: claudeKeyAccount)
    }

    @discardableResult
    static func deleteAPIKey() -> Bool {
        deleteKey(account: claudeKeyAccount)
    }

    // MARK: - Gemini API Key

    static func saveGeminiAPIKey(_ key: String) -> Bool {
        saveKey(key, account: geminiKeyAccount)
    }

    static func getGeminiAPIKey() -> String? {
        getKey(account: geminiKeyAccount)
    }

    @discardableResult
    static func deleteGeminiAPIKey() -> Bool {
        deleteKey(account: geminiKeyAccount)
    }

    // MARK: - Generic Key Operations

    private static func saveKey(_ key: String, account: String) -> Bool {
        deleteKey(account: account)

        guard let data = key.data(using: .utf8) else { return false }

        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecValueData as String: data,
            kSecAttrAccessible as String: kSecAttrAccessibleWhenUnlocked,
        ]

        let status = SecItemAdd(query as CFDictionary, nil)
        return status == errSecSuccess
    }

    private static func getKey(account: String) -> String? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne,
        ]

        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)

        guard status == errSecSuccess,
              let data = result as? Data,
              let key = String(data: data, encoding: .utf8) else {
            return nil
        }

        return key
    }

    @discardableResult
    private static func deleteKey(account: String) -> Bool {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
        ]

        let status = SecItemDelete(query as CFDictionary)
        return status == errSecSuccess || status == errSecItemNotFound
    }
}
