import Foundation

/// AI response with optional token usage metadata
struct AIResponse: Sendable {
    let text: String
    let usage: TokenUsage?
}

/// Token usage from an AI API call
struct TokenUsage: Codable, Sendable {
    let inputTokens: Int
    let outputTokens: Int
    let cachedTokens: Int  // Claude cache_read, Gemini = 0
    var totalTokens: Int { inputTokens + outputTokens }
}

/// A single logged API usage entry
struct APIUsageEntry: Codable, Identifiable {
    let id: UUID
    let timestamp: Date
    let operation: String   // "classify-stage1", "classify-stage2", "enrich", "moc", "semantic-link", "summary"
    let model: String
    let inputTokens: Int
    let outputTokens: Int
    let cachedTokens: Int
    let cost: Double
}
