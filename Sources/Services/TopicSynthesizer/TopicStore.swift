import Foundation

// MARK: - Models

struct Topic: Codable, Sendable {
    let id: String              // filename-safe slug, e.g. "swift-concurrency"
    var name: String            // display name == page filename stem
    var pagePath: String        // vault-relative, e.g. "_Wiki/Swift Concurrency.md"
    var members: [String]       // vault-relative note paths
    var keywords: [String]      // lowercased matching hints
    var summary: String         // first paragraph of "## 현재 이해"
    var membersHash: String     // resynthesis skip-gate ("" = never synthesized)
    let created: String         // ISO 8601
    var lastSynthesized: String?
}

struct TopicIndex: Codable, Sendable {
    let version: Int
    var updated: String
    var topics: [Topic]
    var deletedTopics: [String]   // tombstoned topic ids — never auto-recreated
    var unassigned: [String]      // note paths awaiting assignment (FIFO, capped)
}

// MARK: - Store

/// Persists .meta/topic-index.json. Same load-modify-write pattern as
/// FolderRelationStore; all writers run inside the serialized
/// post-processing / vault-check pipelines, so no write queue is needed.
struct TopicStore: Sendable {
    let pkmRoot: String

    private static let currentVersion = 1
    static let unassignedCap = 100

    func load() -> TopicIndex {
        guard let data = FileManager.default.contents(atPath: filePath()),
              let decoded = try? JSONDecoder().decode(TopicIndex.self, from: data) else {
            return TopicIndex(version: Self.currentVersion, updated: Self.timestamp(),
                              topics: [], deletedTopics: [], unassigned: [])
        }
        return decoded
    }

    func save(_ index: TopicIndex) {
        let fm = FileManager.default
        let metaDir = (pkmRoot as NSString).appendingPathComponent(".meta")
        if !fm.fileExists(atPath: metaDir) {
            try? fm.createDirectory(atPath: metaDir, withIntermediateDirectories: true)
        }
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        guard let data = try? encoder.encode(index) else { return }
        try? data.write(to: URL(fileURLWithPath: filePath()), options: .atomic)
    }

    func topic(id: String) -> Topic? {
        load().topics.first { $0.id == id }
    }

    func upsert(_ topic: Topic) {
        var index = load()
        index.topics.removeAll { $0.id == topic.id }
        index.topics.append(topic)
        index.updated = Self.timestamp()
        save(index)
    }

    func isTombstoned(_ id: String) -> Bool {
        load().deletedTopics.contains(id)
    }

    /// Remove the topic and remember its id so it is never auto-recreated
    func tombstone(id: String) {
        var index = load()
        index.topics.removeAll { $0.id == id }
        if !index.deletedTopics.contains(id) {
            index.deletedTopics.append(id)
        }
        index.updated = Self.timestamp()
        save(index)
    }

    /// Add notes to the unassigned pool — skips already-assigned notes,
    /// dedupes, and enforces the FIFO cap (oldest dropped first)
    func addUnassigned(_ paths: [String]) {
        guard !paths.isEmpty else { return }
        var index = load()
        let assigned = Set(index.topics.flatMap(\.members))
        for path in paths where !assigned.contains(path) && !index.unassigned.contains(path) {
            index.unassigned.append(path)
        }
        if index.unassigned.count > Self.unassignedCap {
            index.unassigned.removeFirst(index.unassigned.count - Self.unassignedCap)
        }
        index.updated = Self.timestamp()
        save(index)
    }

    func removeUnassigned(_ paths: [String]) {
        guard !paths.isEmpty else { return }
        var index = load()
        let removal = Set(paths)
        index.unassigned.removeAll { removal.contains($0) }
        index.updated = Self.timestamp()
        save(index)
    }

    /// Drop members/pool entries whose notes no longer exist in the vault
    /// index. Emptied topics stay — the lint phase reports them as orphans;
    /// deleting them here would erase the page and tombstone semantics.
    func pruneStale(existingNotePaths: Set<String>) {
        var index = load()
        var changed = false
        index.topics = index.topics.map { topic in
            let live = topic.members.filter { existingNotePaths.contains($0) }
            guard live.count != topic.members.count else { return topic }
            changed = true
            var updated = topic
            updated.members = live
            return updated
        }
        let poolBefore = index.unassigned.count
        index.unassigned.removeAll { !existingNotePaths.contains($0) }
        if index.unassigned.count != poolBefore { changed = true }
        guard changed else { return }
        index.updated = Self.timestamp()
        save(index)
    }

    // MARK: - Helpers

    private func filePath() -> String {
        (pkmRoot as NSString).appendingPathComponent(".meta/topic-index.json")
    }

    private static func timestamp() -> String {
        ISO8601DateFormatter().string(from: Date())
    }
}
