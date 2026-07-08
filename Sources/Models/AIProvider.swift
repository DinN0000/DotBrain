import Foundation

/// Supported AI providers for classification
enum AIProvider: String, CaseIterable, Identifiable {
    case claudeCLI = "Claude CLI"
    case codexCLI = "Codex CLI"
    case claude = "Claude"

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .claudeCLI: return "Claude CLI"
        case .codexCLI: return "Codex CLI"
        case .claude: return "Claude (API)"
        }
    }

    var modelPipeline: String {
        switch self {
        case .claudeCLI: return "Claude CLI default"
        case .codexCLI: return "Codex CLI default"
        case .claude: return "Haiku 4.5 → Sonnet 4.5"
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
        }
    }

    var keyPlaceholder: String {
        switch self {
        case .claudeCLI, .codexCLI: return ""
        case .claude: return "sk-ant-..."
        }
    }

    var keyPrefix: String {
        switch self {
        case .claudeCLI, .codexCLI: return ""
        case .claude: return "sk-ant-"
        }
    }

    /// Whether this provider requires an API key (vs CLI availability)
    var needsAPIKey: Bool {
        switch self {
        case .claude: return true
        case .claudeCLI, .codexCLI: return false
        }
    }

    func hasAPIKey() -> Bool {
        switch self {
        case .claude:
            return KeychainService.getAPIKey() != nil
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
        case .claudeCLI, .codexCLI:
            return true
        }
    }

    func deleteAPIKey() {
        switch self {
        case .claude:
            KeychainService.deleteAPIKey()
        case .claudeCLI, .codexCLI:
            break
        }
    }
}
