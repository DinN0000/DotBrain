import Foundation

/// Builds project context map for the classifier
struct ProjectContextBuilder {
    let pkmRoot: String
    let noteIndex: NoteIndex?

    init(pkmRoot: String, noteIndex: NoteIndex? = nil) {
        self.pkmRoot = pkmRoot
        self.noteIndex = noteIndex
    }

    private var pathManager: PKMPathManager {
        PKMPathManager(root: pkmRoot)
    }

    /// Build project context string for classifier prompts
    func buildProjectContext() -> String {
        // Index-first
        if let index = noteIndex {
            var lines: [String] = []
            for (folderKey, folder) in index.folders.sorted(by: { $0.key < $1.key })
                where folder.para == "project" {
                let name = (folderKey as NSString).lastPathComponent
                let tags = folder.tags.isEmpty ? "" : folder.tags.joined(separator: ", ")
                let areaValue = index.notes.values
                    .first(where: { $0.folder == folderKey && $0.area != nil })?.area
                let areaStr = areaValue.map { " (Area: \($0))" } ?? ""
                lines.append("- \(name): \(folder.summary) [\(tags)]\(areaStr)")
            }
            return lines.isEmpty ? "활성 프로젝트 없음" : lines.joined(separator: "\n")
        }

        // Disk fallback
        return buildProjectContextFromDisk()
    }

    private func buildProjectContextFromDisk() -> String {
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
            guard pathManager.isPathSafe(projectDir) else { continue }

            let indexPath = (projectDir as NSString).appendingPathComponent("\(entry).md")

            if let content = try? String(contentsOfFile: indexPath, encoding: .utf8) {
                let (frontmatter, _) = Frontmatter.parse(markdown: content)
                let summary = frontmatter.summary ?? ""
                let tags = frontmatter.tags.isEmpty ? "" : frontmatter.tags.joined(separator: ", ")
                let areaStr = frontmatter.area.map { " (Area: \($0))" } ?? ""
                lines.append("- \(entry): \(summary) [\(tags)]\(areaStr)")
            } else {
                lines.append("- \(entry)")
            }
        }

        return lines.isEmpty ? "활성 프로젝트 없음" : lines.joined(separator: "\n")
    }

    /// Build Area-Project mapping context for classifier prompts
    func buildAreaContext() -> String {
        let areaPath = pathManager.areaPath
        let fm = FileManager.default

        guard let entries = try? fm.contentsOfDirectory(atPath: areaPath) else {
            return ""
        }

        var lines: [String] = []

        for entry in entries.sorted() {
            guard !entry.hasPrefix("."), !entry.hasPrefix("_") else { continue }
            let areaDir = (areaPath as NSString).appendingPathComponent(entry)
            var isDir: ObjCBool = false
            guard fm.fileExists(atPath: areaDir, isDirectory: &isDir), isDir.boolValue else { continue }
            guard pathManager.isPathSafe(areaDir) else { continue }

            let indexPath = (areaDir as NSString).appendingPathComponent("\(entry).md")
            var projectList = ""
            if let content = try? String(contentsOfFile: indexPath, encoding: .utf8) {
                let (frontmatter, _) = Frontmatter.parse(markdown: content)
                if let projects = frontmatter.projects, !projects.isEmpty {
                    projectList = projects.joined(separator: ", ")
                }
            }
            let detail = projectList.isEmpty ? "(프로젝트 없음)" : projectList
            lines.append("- \(entry): \(detail)")
        }

        return lines.isEmpty ? "" : lines.joined(separator: "\n")
    }

    /// Build subfolder context as enriched JSON for classifier prompts
    /// Each folder includes name, tags, summary, noteCount when index is available
    func buildSubfolderContext() -> String {
        // Disk scan for folder list (covers empty folders not in index)
        let subfolders = pathManager.existingSubfolders()

        let paraMapping: [(String, String)] = [
            ("area", "2_Area"),
            ("resource", "3_Resource"),
            ("archive", "4_Archive"),
        ]

        // Pre-compute note counts per folder to avoid repeated O(N) scans
        var folderNoteCounts: [String: Int] = [:]
        if let index = noteIndex {
            for (_, note) in index.notes {
                folderNoteCounts[note.folder, default: 0] += 1
            }
        }

        var dict: [String: Any] = [:]

        for (category, paraPrefix) in paraMapping {
            guard let folderNames = subfolders[category], !folderNames.isEmpty else { continue }

            var entries: [[String: Any]] = []
            for name in folderNames.sorted() {
                var entry: [String: Any] = ["name": name]

                if let index = noteIndex {
                    let folderKey = "\(paraPrefix)/\(name)"
                    if let folderInfo = index.folders[folderKey] {
                        if !folderInfo.tags.isEmpty {
                            entry["tags"] = folderInfo.tags
                        }
                        if !folderInfo.summary.isEmpty {
                            entry["summary"] = folderInfo.summary
                        }
                    }
                    if let count = folderNoteCounts[folderKey], count > 0 {
                        entry["noteCount"] = count
                    }
                }

                entries.append(entry)
            }
            dict[category] = entries
        }

        guard !dict.isEmpty else { return "{}" }

        if let data = try? JSONSerialization.data(withJSONObject: dict, options: [.sortedKeys]),
           let json = String(data: data, encoding: .utf8) {
            return json
        }
        return "{}"
    }

    /// Extract project names from project context string
    func extractProjectNames(from context: String) -> [String] {
        context.split(separator: "\n").compactMap { line in
            guard line.hasPrefix("- ") else { return nil }
            let rest = line.dropFirst(2)
            // Find name boundary: first '(' (scope) or ':' (summary), whichever comes first
            let parenIdx = rest.firstIndex(of: "(")
            let colonIdx = rest.firstIndex(of: ":")
            let endIdx = [parenIdx, colonIdx].compactMap { $0 }.min() ?? rest.endIndex
            return String(rest[..<endIdx]).trimmingCharacters(in: .whitespaces)
        }
    }

    // MARK: - Weighted Context

    /// Build weighted context from root index notes (max 4 file reads)
    func buildWeightedContext() -> String {
        let categories: [(path: String, label: String, weight: String)] = [
            (pathManager.projectsPath, "Project", "높은 연결 가중치"),
            (pathManager.areaPath, "Area", "중간 연결 가중치"),
            (pathManager.resourcePath, "Resource", "중간 연결 가중치"),
            (pathManager.archivePath, "Archive", "낮은 연결 가중치"),
        ]

        var sections: [String] = []

        for (basePath, label, weight) in categories {
            let categoryName = (basePath as NSString).lastPathComponent
            let mocPath = (basePath as NSString).appendingPathComponent("\(categoryName).md")

            if let content = try? String(contentsOfFile: mocPath, encoding: .utf8) {
                let (_, body) = Frontmatter.parse(markdown: content)
                let trimmed = body.trimmingCharacters(in: .whitespacesAndNewlines)
                if !trimmed.isEmpty {
                    sections.append("### \(label) (\(weight))\n\(trimmed)")
                }
            }
        }

        return sections.isEmpty ? "" : sections.joined(separator: "\n\n")
    }

    // MARK: - Tag Vocabulary

    /// Collect existing tags from vault for classifier prompt injection
    /// Returns JSON array of top tags sorted by frequency
    func buildTagVocabulary() -> String {
        // Index-first: aggregate tags from all notes
        if let index = noteIndex {
            var tagCounts: [String: Int] = [:]
            for (_, note) in index.notes {
                for tag in note.tags {
                    tagCounts[tag, default: 0] += 1
                }
            }
            return encodeTopTags(tagCounts)
        }

        // Disk fallback
        return buildTagVocabularyFromDisk()
    }

    private func buildTagVocabularyFromDisk() -> String {
        var tagCounts: [String: Int] = [:]
        let fm = FileManager.default

        for basePath in [pathManager.projectsPath, pathManager.areaPath,
                         pathManager.resourcePath, pathManager.archivePath] {
            guard let folders = try? fm.contentsOfDirectory(atPath: basePath) else { continue }
            for folder in folders {
                guard !folder.hasPrefix("."), !folder.hasPrefix("_") else { continue }
                let folderPath = (basePath as NSString).appendingPathComponent(folder)
                var isDir: ObjCBool = false
                guard fm.fileExists(atPath: folderPath, isDirectory: &isDir), isDir.boolValue else { continue }
                guard pathManager.isPathSafe(folderPath) else { continue }

                guard let files = try? fm.contentsOfDirectory(atPath: folderPath) else { continue }
                let mdFiles = files.filter { $0.hasSuffix(".md") && !$0.hasPrefix(".") && !$0.hasPrefix("_") }

                for file in mdFiles.prefix(5) {
                    let filePath = (folderPath as NSString).appendingPathComponent(file)
                    if let content = try? String(contentsOfFile: filePath, encoding: .utf8) {
                        let (fileFM, _) = Frontmatter.parse(markdown: content)
                        for tag in fileFM.tags {
                            tagCounts[tag, default: 0] += 1
                        }
                    }
                }
            }
        }

        return encodeTopTags(tagCounts)
    }

    private func encodeTopTags(_ tagCounts: [String: Int]) -> String {
        guard !tagCounts.isEmpty else { return "[]" }
        let topTags = tagCounts.sorted { $0.value > $1.value }.prefix(50).map { $0.key }
        if let data = try? JSONSerialization.data(withJSONObject: topTags, options: []),
           let json = String(data: data, encoding: .utf8) {
            return json
        }
        return "[]"
    }

}
