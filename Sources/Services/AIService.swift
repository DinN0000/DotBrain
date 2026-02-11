import Foundation

/// Provider-agnostic AI service that routes to Claude or Gemini
/// with retry logic, exponential backoff, and provider fallback
actor AIService {
    private let claudeClient = ClaudeAPIClient()
    private let geminiClient = GeminiAPIClient()
    private let maxRetries = 3

    /// Current provider (read from UserDefaults)
    private var currentProvider: AIProvider {
        if let saved = UserDefaults.standard.string(forKey: "selectedProvider"),
           let provider = AIProvider(rawValue: saved) {
            return provider
        }
        return .gemini
    }

    /// Alternate provider for fallback
    private var fallbackProvider: AIProvider? {
        let primary = currentProvider
        let alternate: AIProvider = primary == .claude ? .gemini : .claude
        return alternate.hasAPIKey() ? alternate : nil
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

    private func fastModel(for provider: AIProvider) -> String {
        switch provider {
        case .claude: return ClaudeAPIClient.haikuModel
        case .gemini: return GeminiAPIClient.flashModel
        }
    }

    private func preciseModel(for provider: AIProvider) -> String {
        switch provider {
        case .claude: return ClaudeAPIClient.sonnetModel
        case .gemini: return GeminiAPIClient.proModel
        }
    }

    // MARK: - API Call with Retry

    /// Send a message with retry logic and exponential backoff
    func sendMessage(
        model: String,
        maxTokens: Int,
        userMessage: String
    ) async throws -> String {
        try await sendWithRetry(
            provider: currentProvider,
            model: model,
            maxTokens: maxTokens,
            userMessage: userMessage
        )
    }

    private func sendWithRetry(
        provider: AIProvider,
        model: String,
        maxTokens: Int,
        userMessage: String
    ) async throws -> String {
        var lastError: Error?

        for attempt in 0..<maxRetries {
            do {
                return try await sendDirect(
                    provider: provider,
                    model: model,
                    maxTokens: maxTokens,
                    userMessage: userMessage
                )
            } catch {
                lastError = error

                // Don't retry on non-retryable errors
                if !isRetryable(error) { break }

                // Exponential backoff: 1s, 2s, 4s
                if attempt < maxRetries - 1 {
                    let delay = UInt64(pow(2.0, Double(attempt))) * 1_000_000_000
                    try? await Task.sleep(nanoseconds: delay)
                }
            }
        }

        // Try fallback provider if available
        if let fallback = fallbackProvider, fallback != provider {
            let fallbackModel = model == fastModel(for: provider)
                ? fastModel(for: fallback)
                : preciseModel(for: fallback)

            do {
                print("[AIService] 주 제공자 실패, \(fallback.rawValue)로 폴백 시도")
                return try await sendDirect(
                    provider: fallback,
                    model: fallbackModel,
                    maxTokens: maxTokens,
                    userMessage: userMessage
                )
            } catch {
                // Fallback also failed, throw original error
            }
        }

        throw lastError ?? ClaudeAPIError.invalidResponse
    }

    private func sendDirect(
        provider: AIProvider,
        model: String,
        maxTokens: Int,
        userMessage: String
    ) async throws -> String {
        switch provider {
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

    /// Check if an error is worth retrying
    private func isRetryable(_ error: Error) -> Bool {
        if let claudeError = error as? ClaudeAPIError {
            switch claudeError {
            case .httpError(let status):
                return status == 429 || status >= 500
            case .apiError(let status, _):
                return status == 429 || status >= 500
            case .invalidResponse, .emptyResponse:
                return true
            case .noAPIKey, .invalidURL, .jsonParseFailed:
                return false
            }
        }
        if let geminiError = error as? GeminiAPIError {
            switch geminiError {
            case .httpError(let status):
                return status == 429 || status >= 500
            case .apiError(let status, _):
                return status == 429 || status >= 500
            case .invalidResponse, .emptyResponse:
                return true
            case .noAPIKey, .invalidURL:
                return false
            }
        }
        // Network errors are retryable
        let nsError = error as NSError
        if nsError.domain == NSURLErrorDomain {
            return true
        }
        return false
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
