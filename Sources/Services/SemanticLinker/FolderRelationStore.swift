import Foundation

// MARK: - Models

struct FolderRelation: Codable, Sendable {
    let source: String       // e.g. "2_Area/SwiftUI-패턴"
    let target: String       // e.g. "1_Project/iOS-개발"
    let type: String         // "boost" | "suppress"
    let hint: String?        // AI-generated: "프레임워크 패턴을 프로젝트에 적용할 때"
    let relationType: String? // "비교/대조" | "적용" | "확장" | "관련"
    let origin: String       // "explore" | "manual" | "detected"
    let created: String      // ISO 8601
}

struct FolderRelations: Codable, Sendable {
    let version: Int
    var updated: String
    var relations: [FolderRelation]
}

// MARK: - Store

struct FolderRelationStore: Sendable {
    let pkmRoot: String

    private static let currentVersion = 1

    // MARK: - CRUD

    func load() -> FolderRelations {
        let path = filePath()
        guard let data = FileManager.default.contents(atPath: path),
              let decoded = try? JSONDecoder().decode(FolderRelations.self, from: data) else {
            return FolderRelations(version: Self.currentVersion, updated: Self.timestamp(), relations: [])
        }
        return decoded
    }

    func save(_ relations: FolderRelations) {
        let fm = FileManager.default
        let metaDir = (pkmRoot as NSString).appendingPathComponent(".meta")
        if !fm.fileExists(atPath: metaDir) {
            try? fm.createDirectory(atPath: metaDir, withIntermediateDirectories: true)
        }

        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        guard let data = try? encoder.encode(relations) else { return }
        try? data.write(to: URL(fileURLWithPath: filePath()), options: .atomic)
    }

    func addRelation(_ relation: FolderRelation) {
        var store = load()
        // Remove existing relation for same pair (if any)
        store.relations.removeAll { matchesPair($0, source: relation.source, target: relation.target) }
        store.relations.append(relation)
        store.updated = Self.timestamp()
        save(store)
    }

    func removeRelation(source: String, target: String) {
        var store = load()
        store.relations.removeAll { matchesPair($0, source: source, target: target) }
        store.updated = Self.timestamp()
        save(store)
    }

    // MARK: - Query (bidirectional)

    func relationType(source: String, target: String) -> String? {
        let store = load()
        return store.relations.first { matchesPair($0, source: source, target: target) }?.type
    }

    func hint(source: String, target: String) -> String? {
        let store = load()
        return store.relations.first { matchesPair($0, source: source, target: target) }?.hint
    }

    func boostPairs() -> [(source: String, target: String, hint: String?)] {
        load().relations
            .filter { $0.type == "boost" }
            .map { (source: $0.source, target: $0.target, hint: $0.hint) }
    }

    func suppressPairs() -> Set<String> {
        Set(load().relations
            .filter { $0.type == "suppress" }
            .map { pairKey($0.source, $0.target) })
    }

    func boostPairKeys() -> Set<String> {
        Set(load().relations
            .filter { $0.type == "boost" }
            .map { pairKey($0.source, $0.target) })
    }

    // MARK: - Maintenance

    func renamePath(from oldPath: String, to newPath: String) {
        var store = load()
        var changed = false
        store.relations = store.relations.map { rel in
            var source = rel.source
            var target = rel.target
            var modified = false
            if source == oldPath { source = newPath; modified = true }
            if target == oldPath { target = newPath; modified = true }
            guard modified else { return rel }
            changed = true
            return FolderRelation(
                source: source, target: target,
                type: rel.type, hint: rel.hint,
                relationType: rel.relationType,
                origin: rel.origin, created: rel.created
            )
        }
        if changed {
            store.updated = Self.timestamp()
            save(store)
        }
    }

    func pruneStale(existingFolders: Set<String>) {
        var store = load()
        let before = store.relations.count
        store.relations.removeAll { !existingFolders.contains($0.source) || !existingFolders.contains($0.target) }
        if store.relations.count != before {
            store.updated = Self.timestamp()
            save(store)
            NSLog("[FolderRelationStore] Pruned %d stale relations", before - store.relations.count)
        }
    }

    // MARK: - Helpers

    /// Bidirectional match: (A,B) matches (B,A)
    private func matchesPair(_ rel: FolderRelation, source: String, target: String) -> Bool {
        (rel.source == source && rel.target == target) ||
        (rel.source == target && rel.target == source)
    }

    /// Canonical key for a pair (sorted order)
    func pairKey(_ a: String, _ b: String) -> String {
        a < b ? "\(a)|\(b)" : "\(b)|\(a)"
    }

    private func filePath() -> String {
        (pkmRoot as NSString).appendingPathComponent(".meta/folder-relations.json")
    }

    private static func timestamp() -> String {
        ISO8601DateFormatter().string(from: Date())
    }
}
