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
        case .claudeCLI: return "claude -p (Sonnet)"
        case .codexCLI: return "o4-mini → o3"
        case .claude: return "Haiku 4.5 → Sonnet 4.5"
        case .gemini: return "Flash → Pro"
        }
    }

    var costInfo: String {
        switch self {
        case .claudeCLI:
            return "구독 포함"
        case .codexCLI:
            return "구독 포함"
        case .claude:
            return "파일당 약 $0.002 (Haiku 4.5)"
        case .gemini:
            return "무료 티어: 분당 15회, 일 1500회"
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
