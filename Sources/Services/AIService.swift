import Foundation

/// Provider-agnostic AI service that routes to Claude or Gemini
actor AIService {
    private let claudeClient = ClaudeAPIClient()
    private let geminiClient = GeminiAPIClient()

    /// Current provider (read from UserDefaults)
    private var currentProvider: AIProvider {
        if let saved = UserDefaults.standard.string(forKey: "selectedProvider"),
           let provider = AIProvider(rawValue: saved) {
            return provider
        }
        return .gemini
    }

    // MARK: - Model Names

    var fastModel: String {
        switch currentProvider {
        case .claude:
            return ClaudeAPIClient.haikuModel
        case .gemini:
            return GeminiAPIClient.flashModel
        }
    }

    var preciseModel: String {
        switch currentProvider {
        case .claude:
            return ClaudeAPIClient.sonnetModel
        case .gemini:
            return GeminiAPIClient.proModel
        }
    }

    // MARK: - API Call

    /// Send a message using the current provider
    func sendMessage(
        model: String,
        maxTokens: Int,
        userMessage: String
    ) async throws -> String {
        switch currentProvider {
        case .claude:
            return try await claudeClient.sendMessage(
                model: model,
                maxTokens: maxTokens,
                userMessage: userMessage
            )
        case .gemini:
            return try await geminiClient.sendMessage(
                model: model,
                maxTokens: maxTokens,
                userMessage: userMessage
            )
        }
    }

    /// Send using the fast model (Haiku / Flash)
    func sendFast(maxTokens: Int = 4096, message: String) async throws -> String {
        try await sendMessage(model: fastModel, maxTokens: maxTokens, userMessage: message)
    }

    /// Send using the precise model (Sonnet / Pro)
    func sendPrecise(maxTokens: Int = 2048, message: String) async throws -> String {
        try await sendMessage(model: preciseModel, maxTokens: maxTokens, userMessage: message)
    }
}
