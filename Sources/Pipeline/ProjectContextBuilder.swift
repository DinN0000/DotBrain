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
            guard pathManager.isPathSafe(projectDir) else { continue }

            let indexPath = (projectDir as NSString).appendingPathComponent("\(entry).md")

            if let content = try? String(contentsOfFile: indexPath, encoding: .utf8) {
                let (frontmatter, body) = Frontmatter.parse(markdown: content)
                let summary = frontmatter.summary ?? ""
                let tags = frontmatter.tags.isEmpty ? "" : frontmatter.tags.joined(separator: ", ")
                let areaStr = frontmatter.area.map { " (Area: \($0))" } ?? ""
                let scope = extractScope(from: body)
                let scopeStr = scope.isEmpty ? "" : " (scope: \(scope))"
                lines.append("- \(entry)\(scopeStr): \(summary) [\(tags)]\(areaStr)")
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

    /// Build subfolder context as JSON for classifier prompts (prevents folder name hallucination)
    func buildSubfolderContext() -> String {
        let subfolders = pathManager.existingSubfolders()
        var dict: [String: [String]] = [:]

        if let area = subfolders["area"], !area.isEmpty {
            dict["area"] = area.sorted()
        }
        if let resource = subfolders["resource"], !resource.isEmpty {
            dict["resource"] = resource.sorted()
        }
        if let archive = subfolders["archive"], !archive.isEmpty {
            dict["archive"] = archive.sorted()
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

    /// Build weighted context from root index notes (optimized: max 4 file reads)
    /// Per-category hybrid fallback: uses root index note when available, legacy for missing categories
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

            // Try root index note first
            if let content = try? String(contentsOfFile: mocPath, encoding: .utf8) {
                let (_, body) = Frontmatter.parse(markdown: content)
                let trimmed = body.trimmingCharacters(in: .whitespacesAndNewlines)
                if !trimmed.isEmpty {
                    sections.append("### \(label) (\(weight))\n\(trimmed)")
                    continue
                }
            }

            // Per-category fallback: no root index note or empty body
            let fallback = buildCategoryFallback(basePath: basePath, label: label, weight: weight)
            if !fallback.isEmpty {
                sections.append(fallback)
            }
        }

        return sections.isEmpty ? "기존 문서 없음" : sections.joined(separator: "\n\n")
    }

    /// Per-category legacy fallback when root index note is missing or empty
    private func buildCategoryFallback(basePath: String, label: String, weight: String) -> String {
        let section: String
        switch label {
        case "Project":
            section = buildProjectDocuments()
        case "Archive":
            section = buildArchiveSummary()
        default:
            section = buildFolderSummaries(at: basePath, label: label)
        }
        guard !section.isEmpty else { return "" }
        return "### \(label) (\(weight))\n\(section)"
    }

    // MARK: - Private Helpers

    /// Build detailed document list for each project
    private func buildProjectDocuments() -> String {
        let fm = FileManager.default
        let projectsPath = pathManager.projectsPath
        guard let projects = try? fm.contentsOfDirectory(atPath: projectsPath) else { return "" }

        var lines: [String] = []

        for project in projects.sorted() {
            guard !project.hasPrefix("."), !project.hasPrefix("_") else { continue }
            let projectDir = (projectsPath as NSString).appendingPathComponent(project)
            var isDir: ObjCBool = false
            guard fm.fileExists(atPath: projectDir, isDirectory: &isDir), isDir.boolValue else { continue }
            guard pathManager.isPathSafe(projectDir) else { continue }

            // Read index note for project summary
            let indexPath = (projectDir as NSString).appendingPathComponent("\(project).md")
            var projectSummary = ""
            var projectTags: [String] = []
            if let content = try? String(contentsOfFile: indexPath, encoding: .utf8) {
                let (indexFM, _) = Frontmatter.parse(markdown: content)
                projectSummary = indexFM.summary ?? ""
                projectTags = indexFM.tags
            }

            let tagsStr = projectTags.isEmpty ? "" : " [\(projectTags.joined(separator: ", "))]"
            lines.append("- **\(project)**: \(projectSummary)\(tagsStr)")

            // List documents in this project (max 10)
            guard let files = try? fm.contentsOfDirectory(atPath: projectDir) else { continue }
            let mdFiles = files.filter {
                $0.hasSuffix(".md") && !$0.hasPrefix(".") && !$0.hasPrefix("_") && $0 != "\(project).md"
            }.sorted().prefix(10)

            for file in mdFiles {
                let filePath = (projectDir as NSString).appendingPathComponent(file)
                let baseName = (file as NSString).deletingPathExtension
                if let content = try? String(contentsOfFile: filePath, encoding: .utf8) {
                    let (fileFM, _) = Frontmatter.parse(markdown: content)
                    let tags = fileFM.tags.prefix(3).joined(separator: ", ")
                    let summary = fileFM.summary ?? ""
                    let detail = [tags, summary].filter { !$0.isEmpty }.joined(separator: " — ")
                    lines.append("  - \(baseName): \(detail)")
                } else {
                    lines.append("  - \(baseName)")
                }
            }
        }

        return lines.joined(separator: "\n")
    }

    /// Build folder summaries with tag aggregation for Area/Resource
    private func buildFolderSummaries(at basePath: String, label: String) -> String {
        let fm = FileManager.default
        guard let folders = try? fm.contentsOfDirectory(atPath: basePath) else { return "" }

        var lines: [String] = []

        for folder in folders.sorted() {
            guard !folder.hasPrefix("."), !folder.hasPrefix("_") else { continue }
            let folderPath = (basePath as NSString).appendingPathComponent(folder)
            var isDir: ObjCBool = false
            guard fm.fileExists(atPath: folderPath, isDirectory: &isDir), isDir.boolValue else { continue }
            guard pathManager.isPathSafe(folderPath) else { continue }

            // Count files and aggregate tags
            guard let files = try? fm.contentsOfDirectory(atPath: folderPath) else { continue }
            let mdFiles = files.filter { $0.hasSuffix(".md") && !$0.hasPrefix(".") && !$0.hasPrefix("_") && $0 != "\(folder).md" }
            let fileCount = mdFiles.count

            // Read index note for summary + tags
            let indexPath = (folderPath as NSString).appendingPathComponent("\(folder).md")
            var folderTags: [String] = []
            var folderSummary = ""
            if let content = try? String(contentsOfFile: indexPath, encoding: .utf8) {
                let (indexFM, _) = Frontmatter.parse(markdown: content)
                folderTags = indexFM.tags
                folderSummary = indexFM.summary ?? ""
            }

            // Also collect top tags from child documents
            if folderTags.isEmpty {
                var tagCounts: [String: Int] = [:]
                for file in mdFiles.prefix(5) {
                    let filePath = (folderPath as NSString).appendingPathComponent(file)
                    if let content = try? String(contentsOfFile: filePath, encoding: .utf8) {
                        let (fileFM, _) = Frontmatter.parse(markdown: content)
                        for tag in fileFM.tags {
                            tagCounts[tag, default: 0] += 1
                        }
                    }
                }
                folderTags = tagCounts.sorted { $0.value > $1.value }.prefix(5).map { $0.key }
            }

            let tagsStr = folderTags.isEmpty ? "" : " [\(folderTags.joined(separator: ", "))]"
            let summaryStr = folderSummary.isEmpty ? "" : " — \(folderSummary)"
            lines.append("- \(folder): \(fileCount)개 파일\(tagsStr)\(summaryStr)")
        }

        return lines.joined(separator: "\n")
    }

    /// Extract scope description from index note body (first non-empty line or blockquote)
    private func extractScope(from body: String) -> String {
        let lines = body.components(separatedBy: .newlines)
        for line in lines {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed.isEmpty { continue }
            // Skip headings and document list sections
            if trimmed.hasPrefix("#") { continue }
            if trimmed.hasPrefix("- [[") { continue }
            // Use blockquote content if present
            if trimmed.hasPrefix(">") {
                let content = String(trimmed.dropFirst()).trimmingCharacters(in: .whitespaces)
                if !content.isEmpty { return String(content.prefix(100)) }
                continue
            }
            return String(trimmed.prefix(100))
        }
        return ""
    }

    // MARK: - Tag Vocabulary

    /// Collect existing tags from vault for classifier prompt injection
    /// Returns JSON array of top tags sorted by frequency
    func buildTagVocabulary() -> String {
        var tagCounts: [String: Int] = [:]
        let fm = FileManager.default

        let categories = [
            pathManager.projectsPath,
            pathManager.areaPath,
            pathManager.resourcePath,
            pathManager.archivePath,
        ]

        for basePath in categories {
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

        guard !tagCounts.isEmpty else { return "[]" }

        let topTags = tagCounts.sorted { $0.value > $1.value }.prefix(50).map { $0.key }
        if let data = try? JSONSerialization.data(withJSONObject: topTags, options: []),
           let json = String(data: data, encoding: .utf8) {
            return json
        }
        return "[]"
    }

    /// Build minimal archive summary (folder names + count only)
    private func buildArchiveSummary() -> String {
        let fm = FileManager.default
        guard let folders = try? fm.contentsOfDirectory(atPath: pathManager.archivePath) else { return "" }

        var lines: [String] = []

        for folder in folders.sorted() {
            guard !folder.hasPrefix("."), !folder.hasPrefix("_") else { continue }
            let folderPath = (pathManager.archivePath as NSString).appendingPathComponent(folder)
            var isDir: ObjCBool = false
            guard fm.fileExists(atPath: folderPath, isDirectory: &isDir), isDir.boolValue else { continue }

            let count = (try? fm.contentsOfDirectory(atPath: folderPath))?
                .filter { !$0.hasPrefix(".") && !$0.hasPrefix("_") }.count ?? 0
            lines.append("- \(folder) (\(count)개 파일)")
        }

        return lines.joined(separator: "\n")
    }

}
