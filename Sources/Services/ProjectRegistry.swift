import Foundation

/// Stores user-declared Area-Project mappings from onboarding.
/// Storage: .meta/project-registry.json
/// Fallback data source for ProjectContextBuilder when note-index.json is empty.
struct ProjectRegistry {
    private static let fileName = "project-registry.json"

    // MARK: - Model

    struct ProjectInfo: Codable {
        var summary: String
    }

    struct AreaInfo: Codable {
        var projects: [String: ProjectInfo]
    }

    struct Registry: Codable {
        var areas: [String: AreaInfo]
    }

    // MARK: - Write

    static func save(areas: [String: AreaInfo], pkmRoot: String) {
        let registry = Registry(areas: areas)
        let path = filePath(pkmRoot: pkmRoot)
        let metaDir = (path as NSString).deletingLastPathComponent
        try? FileManager.default.createDirectory(atPath: metaDir, withIntermediateDirectories: true)

        guard let data = try? JSONEncoder().encode(registry) else { return }
        // Pretty-print for human readability
        if let pretty = try? JSONSerialization.jsonObject(with: data),
           let prettyData = try? JSONSerialization.data(withJSONObject: pretty, options: [.prettyPrinted, .sortedKeys]) {
            try? prettyData.write(to: URL(fileURLWithPath: path))
        } else {
            try? data.write(to: URL(fileURLWithPath: path))
        }
    }

    // MARK: - Read

    static func load(pkmRoot: String) -> Registry? {
        let path = filePath(pkmRoot: pkmRoot)
        guard let data = FileManager.default.contents(atPath: path),
              let registry = try? JSONDecoder().decode(Registry.self, from: data) else {
            return nil
        }
        return registry
    }

    // MARK: - Private

    private static func filePath(pkmRoot: String) -> String {
        let metaDir = (pkmRoot as NSString).appendingPathComponent(".meta")
        return (metaDir as NSString).appendingPathComponent(fileName)
    }
}
