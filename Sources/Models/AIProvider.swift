import Foundation

/// Supported AI providers for classification
enum AIProvider: String, CaseIterable, Identifiable {
    case claudeCLI = "Claude CLI"
    case codexCLI = "Codex CLI"
    case claude = "Claude"
    case gemini = "Gemini"

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .claudeCLI: return "Claude CLI"
        case .codexCLI: return "Codex CLI"
        case .claude: return "Claude (API)"
        case .gemini: return "Gemini (Google)"
        }
    }

    var modelPipeline: String {
        switch self {
        case .claudeCLI: return "Haiku 4.5 → Sonnet 4.5"
        case .codexCLI: return "Spark → 5.3 Codex"
        case .claude: return "Haiku 4.5 → Sonnet 4.5"
        case .gemini: return "Flash → Pro"
        }
    }

    var costInfo: String {
        switch self {
        case .claudeCLI:
            return L10n.Provider.costIncluded
        case .codexCLI:
            return L10n.Provider.costIncluded
        case .claude:
            return L10n.Provider.costPerFile
        case .gemini:
            return L10n.Provider.freeTier
        }
    }

    var keyPlaceholder: String {
        switch self {
        case .claudeCLI, .codexCLI: return ""
        case .claude: return "sk-ant-..."
        case .gemini: return "AIza..."
        }
    }

    var keyPrefix: String {
        switch self {
        case .claudeCLI, .codexCLI: return ""
        case .claude: return "sk-ant-"
        case .gemini: return "AIza"
        }
    }

    /// Whether this provider requires an API key (vs CLI availability)
    var needsAPIKey: Bool {
        switch self {
        case .claude, .gemini: return true
        case .claudeCLI, .codexCLI: return false
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
        case .codexCLI:
            return CodexCLIClient.isAvailable() && CodexCLIClient.isAuthenticated()
        }
    }

    func saveAPIKey(_ key: String) -> Bool {
        switch self {
        case .claude:
            return KeychainService.saveAPIKey(key)
        case .gemini:
            return KeychainService.saveGeminiAPIKey(key)
        case .claudeCLI, .codexCLI:
            return true
        }
    }

    func deleteAPIKey() {
        switch self {
        case .claude:
            KeychainService.deleteAPIKey()
        case .gemini:
            KeychainService.deleteGeminiAPIKey()
        case .claudeCLI, .codexCLI:
            break
        }
    }
}
