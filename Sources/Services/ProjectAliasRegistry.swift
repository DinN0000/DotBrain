import Foundation

/// Resolves AI-generated project name variants to actual project folder names.
/// Learns from user corrections in PendingConfirmation flow.
/// Storage: .meta/project-aliases.json
struct ProjectAliasRegistry {
    private static let fileName = "project-aliases.json"

    /// Resolve an AI-returned project name via alias lookup.
    /// Returns the actual project folder name if a mapping exists, nil otherwise.
    static func resolve(_ aiName: String, pkmRoot: String) -> String? {
        let aliases = load(pkmRoot: pkmRoot)
        return aliases[aiName.lowercased()]
    }

    /// Register a new alias mapping: AI name -> actual project folder name.
    static func register(aiName: String, actualName: String, pkmRoot: String) {
        let key = aiName.lowercased()
        // Skip if AI name already matches actual name (case-insensitive)
        guard key != actualName.lowercased() else { return }

        var aliases = load(pkmRoot: pkmRoot)
        aliases[key] = actualName
        save(aliases, pkmRoot: pkmRoot)
    }

    // MARK: - Private

    private static func filePath(pkmRoot: String) -> String {
        let metaDir = (pkmRoot as NSString).appendingPathComponent(".meta")
        return (metaDir as NSString).appendingPathComponent(fileName)
    }

    private static func load(pkmRoot: String) -> [String: String] {
        let path = filePath(pkmRoot: pkmRoot)
        guard let data = FileManager.default.contents(atPath: path),
              let dict = try? JSONDecoder().decode([String: String].self, from: data) else {
            return [:]
        }
        return dict
    }

    private static func save(_ aliases: [String: String], pkmRoot: String) {
        let path = filePath(pkmRoot: pkmRoot)
        let metaDir = (path as NSString).deletingLastPathComponent
        try? FileManager.default.createDirectory(atPath: metaDir, withIntermediateDirectories: true)

        guard let data = try? JSONEncoder().encode(aliases) else { return }
        // Pretty-print for human readability
        if let pretty = try? JSONSerialization.jsonObject(with: data),
           let prettyData = try? JSONSerialization.data(withJSONObject: pretty, options: [.prettyPrinted, .sortedKeys]) {
            try? prettyData.write(to: URL(fileURLWithPath: path))
        } else {
            try? data.write(to: URL(fileURLWithPath: path))
        }
    }
}
