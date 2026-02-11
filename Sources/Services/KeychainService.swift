import Foundation
import CryptoKit
import IOKit
import Security  // legacy keychain migration only

/// Secure storage for API keys using AES-GCM encrypted local file.
/// Device-bound: encryption key is derived from hardware UUID + salt.
enum KeychainService {
    private static let service = "com.hwaa.ai-pkm-menubar"
    private static let claudeKeyAccount = "anthropic-api-key"
    private static let geminiKeyAccount = "gemini-api-key"

    private static let salt = "ai-pkm-menubar-key-salt-v1"

    private static var storageURL: URL {
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        let dir = appSupport.appendingPathComponent(service)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir.appendingPathComponent("keys.enc")
    }

    // MARK: - Claude API Key

    static func saveAPIKey(_ key: String) -> Bool {
        migrateFromKeychainIfNeeded()
        return saveValue(key, forKey: claudeKeyAccount)
    }

    static func getAPIKey() -> String? {
        migrateFromKeychainIfNeeded()
        return getValue(forKey: claudeKeyAccount)
    }

    @discardableResult
    static func deleteAPIKey() -> Bool {
        migrateFromKeychainIfNeeded()
        return deleteValue(forKey: claudeKeyAccount)
    }

    // MARK: - Gemini API Key

    static func saveGeminiAPIKey(_ key: String) -> Bool {
        migrateFromKeychainIfNeeded()
        return saveValue(key, forKey: geminiKeyAccount)
    }

    static func getGeminiAPIKey() -> String? {
        migrateFromKeychainIfNeeded()
        return getValue(forKey: geminiKeyAccount)
    }

    @discardableResult
    static func deleteGeminiAPIKey() -> Bool {
        migrateFromKeychainIfNeeded()
        return deleteValue(forKey: geminiKeyAccount)
    }

    // MARK: - Encrypted File Storage

    private static func encryptionKey() -> SymmetricKey? {
        guard let uuid = hardwareUUID() else {
            print("[SecureStore] 하드웨어 UUID를 가져올 수 없음")
            return nil
        }
        let material = uuid + salt
        let hash = SHA256.hash(data: Data(material.utf8))
        return SymmetricKey(data: hash)
    }

    private static func loadStore() -> [String: String] {
        guard FileManager.default.fileExists(atPath: storageURL.path) else {
            return [:]
        }
        guard let key = encryptionKey() else { return [:] }

        do {
            let data = try Data(contentsOf: storageURL)
            let box = try AES.GCM.SealedBox(combined: data)
            let decrypted = try AES.GCM.open(box, using: key)
            return (try? JSONDecoder().decode([String: String].self, from: decrypted)) ?? [:]
        } catch {
            print("[SecureStore] 복호화 실패: \(error.localizedDescription)")
            return [:]
        }
    }

    private static func saveStore(_ store: [String: String]) -> Bool {
        guard let key = encryptionKey() else { return false }

        do {
            let data = try JSONEncoder().encode(store)
            let sealed = try AES.GCM.seal(data, using: key)
            guard let combined = sealed.combined else { return false }
            try combined.write(to: storageURL, options: .atomic)
            // Restrict file permissions to owner only
            try FileManager.default.setAttributes(
                [.posixPermissions: 0o600],
                ofItemAtPath: storageURL.path
            )
            return true
        } catch {
            print("[SecureStore] 저장 실패: \(error.localizedDescription)")
            return false
        }
    }

    private static func getValue(forKey key: String) -> String? {
        loadStore()[key]
    }

    private static func saveValue(_ value: String, forKey key: String) -> Bool {
        var store = loadStore()
        store[key] = value
        return saveStore(store)
    }

    private static func deleteValue(forKey key: String) -> Bool {
        var store = loadStore()
        store.removeValue(forKey: key)
        return saveStore(store)
    }

    // MARK: - Hardware UUID

    private static func hardwareUUID() -> String? {
        let service = IOServiceGetMatchingService(
            kIOMainPortDefault,
            IOServiceMatching("IOPlatformExpertDevice")
        )
        guard service != 0 else { return nil }
        defer { IOObjectRelease(service) }

        let key = kIOPlatformUUIDKey as CFString
        guard let uuid = IORegistryEntryCreateCFProperty(service, key, kCFAllocatorDefault, 0)?
            .takeRetainedValue() as? String else {
            return nil
        }
        return uuid
    }

    // MARK: - Keychain Migration

    private static var migrationDone = false

    private static func migrateFromKeychainIfNeeded() {
        guard !migrationDone else { return }
        migrationDone = true

        // Check if we already have an encrypted file — skip migration
        if FileManager.default.fileExists(atPath: storageURL.path) { return }

        // Try to read from legacy keychain
        let claudeKey = legacyKeychainGet(account: claudeKeyAccount)
        let geminiKey = legacyKeychainGet(account: geminiKeyAccount)

        guard claudeKey != nil || geminiKey != nil else { return }

        var store: [String: String] = [:]
        if let k = claudeKey { store[claudeKeyAccount] = k }
        if let k = geminiKey { store[geminiKeyAccount] = k }

        if saveStore(store) {
            print("[SecureStore] 키체인 → 암호화 파일 마이그레이션 완료")
            // Clean up legacy keychain entries
            legacyKeychainDelete(account: claudeKeyAccount)
            legacyKeychainDelete(account: geminiKeyAccount)
        }
    }

    // MARK: - Legacy Keychain (migration only)

    private static func legacyKeychainGet(account: String) -> String? {
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

    private static func legacyKeychainDelete(account: String) {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
        ]
        SecItemDelete(query as CFDictionary)
    }
}
