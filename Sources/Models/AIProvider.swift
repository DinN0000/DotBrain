import Foundation

/// Supported AI providers for classification
enum AIProvider: String, CaseIterable, Identifiable {
    case claudeCLI = "Claude CLI"
    case claude = "Claude"
    case gemini = "Gemini"

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .claudeCLI: return "Claude CLI"
        case .claude: return "Claude (API)"
        case .gemini: return "Gemini (Google)"
        }
    }

    var modelPipeline: String {
        switch self {
        case .claudeCLI: return "claude -p (Sonnet)"
        case .claude: return "Haiku 4.5 → Sonnet 4.5"
        case .gemini: return "Flash → Pro"
        }
    }

    var costInfo: String {
        switch self {
        case .claudeCLI:
            return L10n.Provider.costIncluded
        case .claude:
            return L10n.Provider.costPerFile
        case .gemini:
            return L10n.Provider.freeTier
        }
    }

    var keyPlaceholder: String {
        switch self {
        case .claudeCLI: return ""
        case .claude: return "sk-ant-..."
        case .gemini: return "AIza..."
        }
    }

    var keyPrefix: String {
        switch self {
        case .claudeCLI: return ""
        case .claude: return "sk-ant-"
        case .gemini: return "AIza"
        }
    }

    /// Whether this provider requires an API key (vs CLI availability)
    var needsAPIKey: Bool {
        switch self {
        case .claude, .gemini: return true
        case .claudeCLI: return false
        }
    }

    func hasAPIKey() -> Bool {
        switch self {
        case .claude:
            return KeychainService.getAPIKey() != nil
        case .gemini:
            return KeychainService.getGeminiAPIKey() != nil
        case .claudeCLI:
            return ClaudeCLIClient.isAvailable()
        }
    }

    func saveAPIKey(_ key: String) -> Bool {
        switch self {
        case .claude:
            return KeychainService.saveAPIKey(key)
        case .gemini:
            return KeychainService.saveGeminiAPIKey(key)
        case .claudeCLI:
            return true
        }
    }

    func deleteAPIKey() {
        switch self {
        case .claude:
            KeychainService.deleteAPIKey()
        case .gemini:
            KeychainService.deleteGeminiAPIKey()
        case .claudeCLI:
            break
        }
    }
}
