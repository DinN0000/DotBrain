import Foundation

/// Actor-based logger for API token usage and cost tracking.
/// Persists entries to `pkmRoot/.dotbrain/api-usage.json`.
actor APIUsageLogger {
    private let pkmRoot: String
    private let logPath: String
    private var entries: [APIUsageEntry] = []
    private var loaded: Bool = false

    // MARK: - Model Pricing (per 1M tokens)

    private struct ModelPricing {
        let inputPerMillion: Double
        let outputPerMillion: Double
    }

    private static let pricing: [String: ModelPricing] = [
        "claude-haiku-4-5-20251001": ModelPricing(inputPerMillion: 0.80, outputPerMillion: 4.00),
        "claude-sonnet-4-5-20250929": ModelPricing(inputPerMillion: 3.00, outputPerMillion: 15.00),
        "gemini-2.5-flash": ModelPricing(inputPerMillion: 0.15, outputPerMillion: 0.60),
        "gemini-2.5-pro": ModelPricing(inputPerMillion: 1.25, outputPerMillion: 5.00),
    ]

    init(pkmRoot: String) {
        self.pkmRoot = pkmRoot
        self.logPath = (pkmRoot as NSString).appendingPathComponent(".dotbrain/api-usage.json")
    }

    // MARK: - Logging

    /// Log a single API usage entry with automatic cost calculation
    func log(operation: String, model: String, usage: TokenUsage) {
        ensureLoaded()

        let cost = Self.calculateCost(model: model, usage: usage)
        let entry = APIUsageEntry(
            id: UUID(),
            timestamp: Date(),
            operation: operation,
            model: model,
            inputTokens: usage.inputTokens,
            outputTokens: usage.outputTokens,
            cachedTokens: usage.cachedTokens,
            cost: cost
        )
        entries.append(entry)
        save()
    }

    // MARK: - Queries

    /// Load and return all entries from disk
    func loadEntries() -> [APIUsageEntry] {
        ensureLoaded()
        return entries
    }

    /// Aggregate cost by operation type
    func costByOperation() -> [String: Double] {
        ensureLoaded()
        var result: [String: Double] = [:]
        for entry in entries {
            result[entry.operation, default: 0] += entry.cost
        }
        return result
    }

    /// Total accumulated cost across all entries
    func totalCost() -> Double {
        ensureLoaded()
        return entries.reduce(0) { $0 + $1.cost }
    }

    /// Return the most recent entries, newest first
    func recentEntries(limit: Int) -> [APIUsageEntry] {
        ensureLoaded()
        let sorted = entries.sorted { $0.timestamp > $1.timestamp }
        return Array(sorted.prefix(limit))
    }

    // MARK: - Cost Calculation (static for external use)

    /// Calculate cost for a given model and token usage.
    /// Static so StatisticsService can call it without an actor instance.
    static func calculateCost(model: String, usage: TokenUsage) -> Double {
        guard let price = pricing[model] else { return 0 }
        let inputCost = Double(usage.inputTokens) * price.inputPerMillion / 1_000_000.0
        let outputCost = Double(usage.outputTokens) * price.outputPerMillion / 1_000_000.0
        return inputCost + outputCost
    }

    // MARK: - Private Helpers

    /// Load entries from disk if not yet loaded
    private func ensureLoaded() {
        guard !loaded else { return }
        loaded = true

        let fm = FileManager.default
        guard fm.fileExists(atPath: logPath),
              let data = fm.contents(atPath: logPath) else {
            return
        }
        do {
            let decoder = JSONDecoder()
            decoder.dateDecodingStrategy = .iso8601
            entries = try decoder.decode([APIUsageEntry].self, from: data)
        } catch {
            // Corrupted log file -- start fresh
            entries = []
        }
    }

    /// Persist all entries to disk as JSON
    private func save() {
        let fm = FileManager.default
        let dirPath = (logPath as NSString).deletingLastPathComponent
        if !fm.fileExists(atPath: dirPath) {
            try? fm.createDirectory(atPath: dirPath, withIntermediateDirectories: true)
        }
        do {
            let encoder = JSONEncoder()
            encoder.dateEncodingStrategy = .iso8601
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            let data = try encoder.encode(entries)
            try data.write(to: URL(fileURLWithPath: logPath))
        } catch {
            // Silently fail -- logging is best-effort
        }
    }
}
