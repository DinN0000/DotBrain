import Foundation

// MARK: - Models

struct LinkFeedbackEntry: Codable, Sendable {
    let date: String
    let sourceNote: String
    let targetNote: String
    let sourceFolder: String
    let targetFolder: String
    let action: String  // "removed"
}

struct LinkFeedback: Codable, Sendable {
    let version: Int
    var entries: [LinkFeedbackEntry]
}

// MARK: - Store

struct LinkFeedbackStore: Sendable {
    let pkmRoot: String

    private static let currentVersion = 1
    private static let maxEntries = 500

    func load() -> LinkFeedback {
        let path = filePath()
        guard let data = FileManager.default.contents(atPath: path),
              let decoded = try? JSONDecoder().decode(LinkFeedback.self, from: data) else {
            return LinkFeedback(version: Self.currentVersion, entries: [])
        }
        return decoded
    }

    func save(_ feedback: LinkFeedback) {
        let fm = FileManager.default
        let metaDir = (pkmRoot as NSString).appendingPathComponent(".meta")
        if !fm.fileExists(atPath: metaDir) {
            try? fm.createDirectory(atPath: metaDir, withIntermediateDirectories: true)
        }

        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        guard let data = try? encoder.encode(feedback) else { return }
        try? data.write(to: URL(fileURLWithPath: filePath()), options: .atomic)
    }

    func recordRemoval(sourceNote: String, targetNote: String,
                       sourceFolder: String, targetFolder: String) {
        var feedback = load()
        feedback.entries.append(LinkFeedbackEntry(
            date: Self.timestamp(),
            sourceNote: sourceNote,
            targetNote: targetNote,
            sourceFolder: sourceFolder,
            targetFolder: targetFolder,
            action: "removed"
        ))

        // FIFO cap
        if feedback.entries.count > Self.maxEntries {
            feedback.entries = Array(feedback.entries.suffix(Self.maxEntries))
        }

        save(feedback)
    }

    /// Build AI prompt context summarizing removal patterns by folder pair
    func buildPromptContext() -> String {
        let feedback = load()
        guard !feedback.entries.isEmpty else { return "" }

        // Count removals per folder pair
        var pairCounts: [String: Int] = [:]
        for entry in feedback.entries where entry.action == "removed" {
            let key = [entry.sourceFolder, entry.targetFolder].sorted().joined(separator: " <> ")
            pairCounts[key, default: 0] += 1
        }

        guard !pairCounts.isEmpty else { return "" }

        let lines = pairCounts
            .sorted { $0.value > $1.value }
            .prefix(10)
            .map { "- \($0.key): \($0.value)회 삭제" }

        return """
        ## 사용자 링크 삭제 패턴
        \(lines.joined(separator: "\n"))
        이 폴더 쌍의 노트 연결은 신중하게 판단하세요.
        """
    }

    // MARK: - Helpers

    private func filePath() -> String {
        (pkmRoot as NSString).appendingPathComponent(".meta/link-feedback.json")
    }

    private static func timestamp() -> String {
        ISO8601DateFormatter().string(from: Date())
    }
}
