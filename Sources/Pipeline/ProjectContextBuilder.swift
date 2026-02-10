import Foundation

/// Builds project context map for the classifier
struct ProjectContextBuilder {
    let pkmRoot: String

    private var pathManager: PKMPathManager {
        PKMPathManager(root: pkmRoot)
    }

    /// Build project context string for classifier prompts
    func buildProjectContext() -> String {
        let projectsPath = pathManager.projectsPath
        let fm = FileManager.default

        guard let entries = try? fm.contentsOfDirectory(atPath: projectsPath) else {
            return "활성 프로젝트 없음"
        }

        var lines: [String] = []

        for entry in entries {
            guard !entry.hasPrefix("."), !entry.hasPrefix("_") else { continue }

            let projectDir = (projectsPath as NSString).appendingPathComponent(entry)
            var isDir: ObjCBool = false
            guard fm.fileExists(atPath: projectDir, isDirectory: &isDir), isDir.boolValue else { continue }

            let indexPath = (projectDir as NSString).appendingPathComponent("\(entry).md")

            if let content = try? String(contentsOfFile: indexPath, encoding: .utf8) {
                let (frontmatter, _) = Frontmatter.parse(markdown: content)
                let summary = frontmatter.summary ?? ""
                let tags = frontmatter.tags.isEmpty ? "" : frontmatter.tags.joined(separator: ", ")
                lines.append("- \(entry): \(summary) [\(tags)]")
            } else {
                lines.append("- \(entry)")
            }
        }

        return lines.isEmpty ? "활성 프로젝트 없음" : lines.joined(separator: "\n")
    }

    /// Build subfolder context string for classifier prompts
    func buildSubfolderContext() -> String {
        let subfolders = pathManager.existingSubfolders()
        var lines: [String] = []

        if let area = subfolders["area"], !area.isEmpty {
            lines.append("2_Area 기존 폴더: \(area.joined(separator: ", "))")
        }
        if let resource = subfolders["resource"], !resource.isEmpty {
            lines.append("3_Resource 기존 폴더: \(resource.joined(separator: ", "))")
        }
        if let archive = subfolders["archive"], !archive.isEmpty {
            lines.append("4_Archive 기존 폴더: \(archive.joined(separator: ", "))")
        }

        return lines.isEmpty ? "기존 하위 폴더 없음" : lines.joined(separator: "\n")
    }

    /// Extract project names from project context string
    func extractProjectNames(from context: String) -> [String] {
        context.split(separator: "\n").compactMap { line in
            guard line.hasPrefix("- ") else { return nil }
            let rest = line.dropFirst(2)
            if let colonIdx = rest.firstIndex(of: ":") {
                return String(rest[..<colonIdx]).trimmingCharacters(in: .whitespaces)
            }
            return String(rest).trimmingCharacters(in: .whitespaces)
        }
    }
}
