import Foundation

/// AI response with optional token usage metadata
struct AIResponse: Sendable {
    let text: String
    let usage: TokenUsage?
    let isEstimated: Bool  // true when usage is estimated (CLI providers)

    init(text: String, usage: TokenUsage?, isEstimated: Bool = false) {
        self.text = text
        self.usage = usage
        self.isEstimated = isEstimated
    }
}

/// Protocol for AI provider errors enabling unified retry classification
protocol RetryClassifiable: LocalizedError {
    var isRateLimitError: Bool { get }
    var isServerError: Bool { get }
    var isRetryable: Bool { get }
}

/// Token usage from an AI API call
struct TokenUsage: Codable, Sendable {
    let inputTokens: Int
    let outputTokens: Int
    let cachedTokens: Int  // Claude cache_read, Gemini = 0
    var totalTokens: Int { inputTokens + outputTokens }

    static let zero = TokenUsage(inputTokens: 0, outputTokens: 0, cachedTokens: 0)
}

/// A single logged API usage entry
struct APIUsageEntry: Codable, Identifiable {
    let id: UUID
    let timestamp: Date
    let operation: String   // "classify", "enrich", "moc", "semantic-link", "summary"
    let model: String
    let inputTokens: Int
    let outputTokens: Int
    let cachedTokens: Int
    let cost: Double
    let isEstimated: Bool   // true for CLI-based token estimates

    var totalTokens: Int { inputTokens + outputTokens }

    init(id: UUID, timestamp: Date, operation: String, model: String,
         inputTokens: Int, outputTokens: Int, cachedTokens: Int, cost: Double,
         isEstimated: Bool = false) {
        self.id = id
        self.timestamp = timestamp
        self.operation = operation
        self.model = model
        self.inputTokens = inputTokens
        self.outputTokens = outputTokens
        self.cachedTokens = cachedTokens
        self.cost = cost
        self.isEstimated = isEstimated
    }

    enum CodingKeys: String, CodingKey {
        case id, timestamp, operation, model, inputTokens, outputTokens, cachedTokens, cost, isEstimated
    }

    // Backward compat: decode existing JSON without isEstimated field
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(UUID.self, forKey: .id)
        timestamp = try c.decode(Date.self, forKey: .timestamp)
        operation = try c.decode(String.self, forKey: .operation)
        model = try c.decode(String.self, forKey: .model)
        inputTokens = try c.decode(Int.self, forKey: .inputTokens)
        outputTokens = try c.decode(Int.self, forKey: .outputTokens)
        cachedTokens = try c.decode(Int.self, forKey: .cachedTokens)
        cost = try c.decode(Double.self, forKey: .cost)
        isEstimated = try c.decodeIfPresent(Bool.self, forKey: .isEstimated) ?? false
    }
}
