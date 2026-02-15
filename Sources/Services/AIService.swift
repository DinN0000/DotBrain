import Foundation

/// Provider-agnostic AI service that routes to Claude or Gemini
/// with adaptive rate limiting, retry logic, and provider fallback
actor AIService {
    static let shared = AIService()

    private let claudeClient = ClaudeAPIClient()
    private let geminiClient = GeminiAPIClient()
    private let rateLimiter = RateLimiter.shared
    private let maxRetries = 3

    private init() {}

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

    // MARK: - API Call with Retry + Rate Limiting

    /// Send a message with adaptive rate limiting, retry logic, and provider fallback
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
        let deadline = ContinuousClock.now + .seconds(120)

        for _ in 0..<maxRetries {
            if ContinuousClock.now >= deadline {
                throw AIServiceError.timeout
            }

            // Rate limiter controls pacing — waits if needed
            await rateLimiter.acquire(for: provider)

            let start = ContinuousClock.now
            do {
                let result = try await sendDirect(
                    provider: provider,
                    model: model,
                    maxTokens: maxTokens,
                    userMessage: userMessage
                )
                await rateLimiter.recordSuccess(for: provider, duration: ContinuousClock.now - start)
                return result
            } catch {
                lastError = error

                let is429 = isRateLimitError(error)
                let isServerErr = isServerError(error)
                if is429 || isServerErr {
                    await rateLimiter.recordFailure(for: provider, isRateLimit: is429)
                }

                // Don't retry on non-retryable errors
                if !isRetryable(error) { break }

                // Rate limiter handles pacing for next attempt — no manual sleep needed
            }
        }

        // Try fallback provider if available
        if let fallback = fallbackProvider, fallback != provider {
            let fallbackModel = model == fastModel(for: provider)
                ? fastModel(for: fallback)
                : preciseModel(for: fallback)

            do {
                print("[AIService] 주 제공자 실패, \(fallback.rawValue)로 폴백 시도")
                await rateLimiter.acquire(for: fallback)
                let start = ContinuousClock.now
                let result = try await sendDirect(
                    provider: fallback,
                    model: fallbackModel,
                    maxTokens: maxTokens,
                    userMessage: userMessage
                )
                await rateLimiter.recordSuccess(for: fallback, duration: ContinuousClock.now - start)
                return result
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

    // MARK: - Error Classification

    /// Check if error is a rate limit (429) error
    private func isRateLimitError(_ error: Error) -> Bool {
        if let e = error as? ClaudeAPIError {
            switch e {
            case .httpError(let s): return s == 429
            case .apiError(let s, _): return s == 429
            default: return false
            }
        }
        if let e = error as? GeminiAPIError {
            switch e {
            case .httpError(let s): return s == 429
            case .apiError(let s, _): return s == 429
            default: return false
            }
        }
        return false
    }

    /// Check if error is a server error (5xx)
    private func isServerError(_ error: Error) -> Bool {
        if let e = error as? ClaudeAPIError {
            switch e {
            case .httpError(let s): return s >= 500
            case .apiError(let s, _): return s >= 500
            default: return false
            }
        }
        if let e = error as? GeminiAPIError {
            switch e {
            case .httpError(let s): return s >= 500
            case .apiError(let s, _): return s >= 500
            default: return false
            }
        }
        return false
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

enum AIServiceError: LocalizedError {
    case timeout

    var errorDescription: String? {
        switch self {
        case .timeout:
            return "AI 요청 시간이 초과되었습니다 (120초). 잠시 후 다시 시도해주세요."
        }
    }
}
