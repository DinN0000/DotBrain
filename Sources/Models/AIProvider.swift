import Foundation

/// Supported AI providers for classification
enum AIProvider: String, CaseIterable, Identifiable {
    case claude = "Claude"
    case gemini = "Gemini"

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .claude: return "Claude (Anthropic)"
        case .gemini: return "Gemini (Google)"
        }
    }

    var costInfo: String {
        switch self {
        case .claude:
            return "파일당 약 $0.002 (Haiku 4.5)"
        case .gemini:
            return "무료 티어: 분당 15회, 일 1500회"
        }
    }

    var keyPlaceholder: String {
        switch self {
        case .claude: return "sk-ant-..."
        case .gemini: return "AIza..."
        }
    }

    var keyPrefix: String {
        switch self {
        case .claude: return "sk-ant-"
        case .gemini: return "AIza"
        }
    }

    func hasAPIKey() -> Bool {
        switch self {
        case .claude:
            return KeychainService.getAPIKey() != nil
        case .gemini:
            return KeychainService.getGeminiAPIKey() != nil
        }
    }

    func saveAPIKey(_ key: String) -> Bool {
        switch self {
        case .claude:
            return KeychainService.saveAPIKey(key)
        case .gemini:
            return KeychainService.saveGeminiAPIKey(key)
        }
    }

    func deleteAPIKey() {
        switch self {
        case .claude:
            KeychainService.deleteAPIKey()
        case .gemini:
            KeychainService.deleteGeminiAPIKey()
        }
    }
}
