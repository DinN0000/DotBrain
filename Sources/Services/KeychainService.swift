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
        guard let data = key.data(using: .utf8) else { return false }

        // First try to read existing key for rollback
        let existingKey = getKey(account: account)

        // Delete existing key before saving
        let deleteStatus = SecItemDelete(deleteQuery(account: account) as CFDictionary)
        if deleteStatus != errSecSuccess && deleteStatus != errSecItemNotFound {
            print("[Keychain] 삭제 실패: \(keychainErrorMessage(deleteStatus))")
        }

        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecValueData as String: data,
            kSecAttrAccessible as String: kSecAttrAccessibleWhenUnlockedThisDeviceOnly,
        ]

        let status = SecItemAdd(query as CFDictionary, nil)
        if status == errSecSuccess {
            return true
        }

        // Rollback: if save failed and we had a previous key, try to restore it
        print("[Keychain] 저장 실패: \(keychainErrorMessage(status))")
        if let existing = existingKey, let existingData = existing.data(using: .utf8) {
            let rollbackQuery: [String: Any] = [
                kSecClass as String: kSecClassGenericPassword,
                kSecAttrService as String: service,
                kSecAttrAccount as String: account,
                kSecValueData as String: existingData,
                kSecAttrAccessible as String: kSecAttrAccessibleWhenUnlockedThisDeviceOnly,
            ]
            SecItemAdd(rollbackQuery as CFDictionary, nil)
        }
        return false
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
            if status != errSecItemNotFound {
                print("[Keychain] 읽기 실패: \(keychainErrorMessage(status))")
            }
            return nil
        }

        return key
    }

    @discardableResult
    private static func deleteKey(account: String) -> Bool {
        let status = SecItemDelete(deleteQuery(account: account) as CFDictionary)
        let success = status == errSecSuccess || status == errSecItemNotFound
        if !success {
            print("[Keychain] 삭제 실패: \(keychainErrorMessage(status))")
        }
        return success
    }

    private static func deleteQuery(account: String) -> [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
        ]
    }

    /// Translate OSStatus to human-readable error message
    private static func keychainErrorMessage(_ status: OSStatus) -> String {
        switch status {
        case errSecSuccess: return "성공"
        case errSecItemNotFound: return "항목 없음"
        case errSecDuplicateItem: return "중복 항목"
        case errSecAuthFailed: return "인증 실패"
        case errSecInteractionNotAllowed: return "잠금 상태에서 접근 불가"
        case errSecDecode: return "디코딩 실패"
        default:
            if let message = SecCopyErrorMessageString(status, nil) {
                return message as String
            }
            return "OSStatus \(status)"
        }
    }
}
