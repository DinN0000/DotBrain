import Foundation

/// Persists user-authored folder descriptions separately from generated note-index summaries.
/// Storage: .meta/folder-descriptions.json
struct FolderDescriptionStore {
    private static let fileName = "folder-descriptions.json"

    struct Store: Codable, Sendable {
        var descriptions: [String: String] = [:]

        func description(for name: String, category: PARACategory) -> String? {
            descriptions[FolderDescriptionStore.key(name: name, category: category)]
        }
    }

    static func load(pkmRoot: String) -> Store {
        let path = filePath(pkmRoot: pkmRoot)
        guard let data = FileManager.default.contents(atPath: path),
              let store = try? JSONDecoder().decode(Store.self, from: data) else {
            return Store()
        }
        return store
    }

    static func set(
        _ description: String,
        for name: String,
        category: PARACategory,
        pkmRoot: String
    ) throws {
        var store = load(pkmRoot: pkmRoot)
        store.descriptions[key(name: name, category: category)] = description
        try save(store, pkmRoot: pkmRoot)
    }

    static func move(
        name: String,
        from source: PARACategory,
        to target: PARACategory,
        newName: String? = nil,
        pkmRoot: String
    ) throws {
        var store = load(pkmRoot: pkmRoot)
        let sourceKey = key(name: name, category: source)
        guard let description = store.descriptions.removeValue(forKey: sourceKey) else { return }
        store.descriptions[key(name: newName ?? name, category: target)] = description
        try save(store, pkmRoot: pkmRoot)
    }

    static func remove(name: String, category: PARACategory, pkmRoot: String) throws {
        var store = load(pkmRoot: pkmRoot)
        guard store.descriptions.removeValue(forKey: key(name: name, category: category)) != nil else {
            return
        }
        try save(store, pkmRoot: pkmRoot)
    }

    private static func save(_ store: Store, pkmRoot: String) throws {
        let path = filePath(pkmRoot: pkmRoot)
        let metaDirectory = (path as NSString).deletingLastPathComponent
        try FileManager.default.createDirectory(
            atPath: metaDirectory,
            withIntermediateDirectories: true
        )
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let data = try encoder.encode(store)
        try data.write(to: URL(fileURLWithPath: path), options: .atomic)
    }

    private static func key(name: String, category: PARACategory) -> String {
        "\(category.rawValue)/\(name.precomposedStringWithCanonicalMapping)"
    }

    private static func filePath(pkmRoot: String) -> String {
        let metaDirectory = (pkmRoot as NSString).appendingPathComponent(".meta")
        return (metaDirectory as NSString).appendingPathComponent(fileName)
    }
}
