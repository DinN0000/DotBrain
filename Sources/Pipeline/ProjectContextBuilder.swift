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

    // MARK: - Weighted Context

    /// Build weighted document context for classification accuracy.
    /// - Project docs: full detail (tags, summaries, file list) — highest weight
    /// - Area/Resource docs: folder + key tags + file count — medium weight
    /// - Archive: folder names only — low weight
    func buildWeightedContext() -> String {
        var sections: [String] = []

        // HIGH weight: Project documents (full detail)
        let projectSection = buildProjectDocuments()
        if !projectSection.isEmpty {
            sections.append("### 🔴 Project (높은 연결 가중치)\n\(projectSection)")
        }

        // MEDIUM weight: Area documents (folder + tags + count)
        let areaSection = buildFolderSummaries(at: pathManager.areaPath, label: "Area")
        if !areaSection.isEmpty {
            sections.append("### 🟡 Area (중간 연결 가중치)\n\(areaSection)")
        }

        // MEDIUM weight: Resource documents (folder + tags + count)
        let resourceSection = buildFolderSummaries(at: pathManager.resourcePath, label: "Resource")
        if !resourceSection.isEmpty {
            sections.append("### 🟡 Resource (중간 연결 가중치)\n\(resourceSection)")
        }

        // LOW weight: Archive (folder names only)
        let archiveSection = buildArchiveSummary()
        if !archiveSection.isEmpty {
            sections.append("### ⚪ Archive (낮은 연결 가중치)\n\(archiveSection)")
        }

        return sections.isEmpty ? "기존 문서 없음" : sections.joined(separator: "\n\n")
    }

    /// PARA-based linking density limits
    private func linkDensityLimit(for para: PARACategory) -> Int {
        switch para {
        case .project: return 10
        case .area: return 5
        case .resource: return 3
        case .archive: return 1
        }
    }

    /// Build related note suggestions for a classified file.
    /// Returns notes with context descriptions from tag overlap analysis.
    /// Linking density varies by PARA category: Project=10, Area=5, Resource=3, Archive=1.
    func findRelatedNotes(tags: [String], project: String?, para: PARACategory, targetFolder: String) -> [RelatedNote] {
        let fm = FileManager.default
        var candidates: [(name: String, score: Int, context: String)] = []

        // Scan the target folder for existing notes
        let basePath: String
        if para == .project, let project = project {
            basePath = (pathManager.projectsPath as NSString).appendingPathComponent(project)
        } else if !targetFolder.isEmpty {
            basePath = (pathManager.paraPath(for: para) as NSString).appendingPathComponent(targetFolder)
        } else {
            return []
        }

        guard let entries = try? fm.contentsOfDirectory(atPath: basePath) else { return [] }

        let tagSet = Set(tags.map { $0.lowercased() })
        guard !tagSet.isEmpty else { return [] }

        for entry in entries {
            guard entry.hasSuffix(".md"), !entry.hasPrefix("."), !entry.hasPrefix("_") else { continue }
            let filePath = (basePath as NSString).appendingPathComponent(entry)
            guard let content = try? String(contentsOfFile: filePath, encoding: .utf8) else { continue }

            let (entryFM, _) = Frontmatter.parse(markdown: content)
            let entryTags = Set(entryFM.tags.map { $0.lowercased() })
            let sharedTags = tagSet.intersection(entryTags)

            if !sharedTags.isEmpty {
                let baseName = (entry as NSString).deletingPathExtension
                let context = "공유 태그: " + sharedTags.sorted().joined(separator: ", ")
                candidates.append((name: baseName, score: sharedTags.count, context: context))
            }
        }

        // Also scan adjacent PARA categories for cross-links
        // Area ↔ Resource have medium affinity
        let crossCategories: [PARACategory]
        switch para {
        case .area: crossCategories = [.resource]
        case .resource: crossCategories = [.area]
        case .project: crossCategories = [.resource, .area]
        case .archive: crossCategories = []
        }

        for crossCat in crossCategories {
            let crossBase = pathManager.paraPath(for: crossCat)
            guard let folders = try? fm.contentsOfDirectory(atPath: crossBase) else { continue }

            for folder in folders {
                guard !folder.hasPrefix("."), !folder.hasPrefix("_") else { continue }
                let folderPath = (crossBase as NSString).appendingPathComponent(folder)
                var isDir: ObjCBool = false
                guard fm.fileExists(atPath: folderPath, isDirectory: &isDir), isDir.boolValue else { continue }

                guard let files = try? fm.contentsOfDirectory(atPath: folderPath) else { continue }
                for file in files {
                    guard file.hasSuffix(".md"), !file.hasPrefix("."), !file.hasPrefix("_") else { continue }
                    let filePath = (folderPath as NSString).appendingPathComponent(file)
                    guard let content = try? String(contentsOfFile: filePath, encoding: .utf8) else { continue }

                    let (entryFM, _) = Frontmatter.parse(markdown: content)
                    let entryTags = Set(entryFM.tags.map { $0.lowercased() })
                    let sharedTags = tagSet.intersection(entryTags)

                    if sharedTags.count >= 2 { // Cross-category needs stronger signal
                        let baseName = (file as NSString).deletingPathExtension
                        let tagList = sharedTags.sorted().joined(separator: ", ")
                        let context = "\(crossCat.folderName)에서 발견 — 공유 태그: \(tagList)"
                        candidates.append((name: baseName, score: sharedTags.count, context: context))
                    }
                }
            }
        }

        // Apply PARA-based density limit, deduplicated
        let limit = linkDensityLimit(for: para)
        let sorted = candidates.sorted { $0.score > $1.score }
        var seen = Set<String>()
        return sorted.compactMap { candidate -> RelatedNote? in
            guard !seen.contains(candidate.name) else { return nil }
            seen.insert(candidate.name)
            return RelatedNote(name: candidate.name, context: candidate.context)
        }.prefix(limit).map { $0 }
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
