import Foundation

/// A single classification correction event
struct CorrectionEntry: Codable {
    let date: Date
    let fileName: String
    let aiPara: String
    let userPara: String
    let aiProject: String?
    let userProject: String?
    let tags: [String]
    let action: String  // "confirm", "skip", "create-project", "delete"
}

/// Records and aggregates user corrections to AI classification decisions.
/// Generates few-shot prompt context from repeated correction patterns.
/// Storage: .meta/correction-memory.json (FIFO, 200 entries max)
struct CorrectionMemory {
    private static let fileName = "correction-memory.json"
    private static let maxEntries = 200

    /// Record a correction entry
    static func record(_ entry: CorrectionEntry, pkmRoot: String) {
        var entries = load(pkmRoot: pkmRoot)
        entries.append(entry)
        // FIFO cap
        if entries.count > maxEntries {
            entries = Array(entries.suffix(maxEntries))
        }
        save(entries, pkmRoot: pkmRoot)
    }

    /// Build prompt context from repeated correction patterns (3+ occurrences)
    static func buildPromptContext(pkmRoot: String) -> String {
        let entries = load(pkmRoot: pkmRoot)
        guard !entries.isEmpty else { return "" }

        var patterns: [String] = []

        // Pattern 1: PARA category corrections (AI -> User, 3+ times same direction)
        var paraCorrectionCounts: [String: Int] = [:]
        for entry in entries where entry.action == "confirm" && !entry.aiPara.isEmpty && !entry.userPara.isEmpty && entry.aiPara != entry.userPara {
            let key = "\(entry.aiPara) -> \(entry.userPara)"
            paraCorrectionCounts[key, default: 0] += 1
        }
        for (correction, count) in paraCorrectionCounts where count >= 3 {
            let parts = correction.split(separator: " -> ")
            if parts.count == 2 {
                patterns.append("- AI가 \(parts[0])으로 분류한 문서를 사용자가 \(parts[1])로 수정 (\(count)회)")
            }
        }

        // Pattern 2: Tag-based patterns (common tags in corrected entries)
        var tagCorrections: [String: [String: Int]] = [:]  // tag -> (userPara -> count)
        for entry in entries where entry.action == "confirm" && !entry.userPara.isEmpty && entry.aiPara != entry.userPara {
            for tag in entry.tags {
                tagCorrections[tag, default: [:]][entry.userPara, default: 0] += 1
            }
        }
        for (tag, paraCounts) in tagCorrections {
            if let (para, count) = paraCounts.max(by: { $0.value < $1.value }), count >= 3 {
                patterns.append("- tags에 \"\(tag)\" 포함 문서: \(para)일 가능성 높음 (\(count)회 수정)")
            }
        }

        // Pattern 3: Project reassignment patterns
        var projectCorrectionCounts: [String: Int] = [:]  // "aiProject -> userProject"
        for entry in entries where entry.action == "confirm" || entry.action == "create-project" {
            let aiProj = entry.aiProject ?? "(없음)"
            let userProj = entry.userProject ?? "(없음)"
            guard aiProj != userProj else { continue }
            let key = "\(aiProj) -> \(userProj)"
            projectCorrectionCounts[key, default: 0] += 1
        }
        for (correction, count) in projectCorrectionCounts where count >= 2 {
            let parts = correction.split(separator: " -> ")
            if parts.count == 2 {
                patterns.append("- 프로젝트 \(parts[0]) -> \(parts[1])로 수정 (\(count)회)")
            }
        }

        guard !patterns.isEmpty else { return "" }

        return "## 사용자 수정 이력 (과거 분류 피드백)\n\(patterns.joined(separator: "\n"))"
    }

    // MARK: - Private

    private static func filePath(pkmRoot: String) -> String {
        let metaDir = (pkmRoot as NSString).appendingPathComponent(".meta")
        return (metaDir as NSString).appendingPathComponent(fileName)
    }

    private static func load(pkmRoot: String) -> [CorrectionEntry] {
        let path = filePath(pkmRoot: pkmRoot)
        guard let data = FileManager.default.contents(atPath: path) else { return [] }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return (try? decoder.decode([CorrectionEntry].self, from: data)) ?? []
    }

    private static func save(_ entries: [CorrectionEntry], pkmRoot: String) {
        let path = filePath(pkmRoot: pkmRoot)
        let metaDir = (path as NSString).deletingLastPathComponent
        try? FileManager.default.createDirectory(atPath: metaDir, withIntermediateDirectories: true)

        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        guard let data = try? encoder.encode(entries) else { return }
        try? data.write(to: URL(fileURLWithPath: path))
    }
}
