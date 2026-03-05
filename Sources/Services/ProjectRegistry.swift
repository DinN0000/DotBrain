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

        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        guard let data = try? encoder.encode(registry) else {
            NSLog("[ProjectRegistry] JSON 인코딩 실패")
            return
        }
        do {
            try data.write(to: URL(fileURLWithPath: path))
        } catch {
            NSLog("[ProjectRegistry] 저장 실패: %@", error.localizedDescription)
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
