import Foundation

/// Handles frontmatter injection into markdown files
enum FrontmatterWriter {
    /// Inject frontmatter into markdown content, with optional [[project]] and related note wikilinks.
    /// Merges with existing frontmatter — existing values take priority over AI-generated ones.
    static func injectFrontmatter(
        into content: String,
        para: PARACategory,
        tags: [String],
        summary: String,
        source: NoteSource = .import,
        project: String? = nil,
        file: FileMetadata? = nil,
        relatedNotes: [RelatedNote] = []
    ) -> String {
        // Strip existing frontmatter completely — replace with DotBrain format
        let (existing, body) = Frontmatter.parse(markdown: content)

        var newFM = Frontmatter.createDefault(
            para: para,
            tags: tags,
            summary: summary,
            source: source,
            project: project,
            file: file
        )

        // Merge policy: existing values take priority over AI-generated ones
        if existing.para != nil { newFM.para = existing.para }
        if !existing.tags.isEmpty { newFM.tags = existing.tags }
        if let existingCreated = existing.created { newFM.created = existingCreated }
        if existing.status != nil { newFM.status = existing.status }
        if let s = existing.summary, !s.isEmpty { newFM.summary = s }
        if existing.source != nil { newFM.source = existing.source }
        if let p = existing.project, !p.isEmpty { newFM.project = p }
        if existing.file != nil { newFM.file = existing.file }

        var result = newFM.stringify() + "\n" + body

        // Build ## Related Notes section with context descriptions
        var lines: [String] = []
        if let project = project, !project.isEmpty, !result.contains("[[\(project)]]") {
            let safeProject = sanitizeWikilink(project)
            lines.append("- [[\(safeProject)]] — 소속 프로젝트")
        }
        for note in relatedNotes where !result.contains("[[\(note.name)]]") {
            let safeName = sanitizeWikilink(note.name)
            let safeContext = note.context
                .replacingOccurrences(of: "[[", with: "")
                .replacingOccurrences(of: "]]", with: "")
            lines.append("- [[\(safeName)]] — \(safeContext)")
        }

        if !lines.isEmpty {
            result += "\n\n## Related Notes\n" + lines.joined(separator: "\n") + "\n"
        }

        return result
    }

    /// Create companion markdown for binary files with AI summary + original file link
    static func createCompanionMarkdown(
        for extractResult: ExtractResult,
        classification: ClassifyResult,
        aiSummary: String? = nil,
        relatedNotes: [RelatedNote] = []
    ) -> String {
        let fileName = extractResult.file?.name ?? "unknown"
        let fm = Frontmatter.createDefault(
            para: classification.para,
            tags: classification.tags,
            summary: classification.summary,
            source: .import,
            project: classification.project,
            file: extractResult.file.map {
                FileMetadata(name: $0.name, format: $0.format, sizeKB: $0.sizeKB)
            }
        )

        var result = fm.stringify() + "\n\n"

        // Title
        result += "# \(fileName)\n\n"

        // AI summary or fallback to raw text
        if let summary = aiSummary, !summary.isEmpty {
            result += summary + "\n"
        } else {
            result += extractResult.text ?? "파일: \(fileName)"
            result += "\n"
        }

        // Original file link (centralized _Assets/ path)
        let ext = extractResult.file?.format ?? ""
        let subdir = BinaryExtractor.imageExtensions.contains(ext) ? "images" : "documents"
        result += "\n## 원본 파일\n\n"
        result += "![[_Assets/\(subdir)/\(fileName)]]\n"

        // Related Notes
        var lines: [String] = []
        if let project = classification.project, !project.isEmpty {
            let safeProject = sanitizeWikilink(project)
            lines.append("- [[\(safeProject)]] — 소속 프로젝트")
        }
        for note in relatedNotes where !result.contains("[[\(note.name)]]") {
            let safeName = sanitizeWikilink(note.name)
            let safeContext = note.context
                .replacingOccurrences(of: "[[", with: "")
                .replacingOccurrences(of: "]]", with: "")
            lines.append("- [[\(safeName)]] — \(safeContext)")
        }
        if !lines.isEmpty {
            result += "\n## Related Notes\n\n" + lines.joined(separator: "\n") + "\n"
        }

        return result
    }

    /// Sanitize a string for use inside [[wikilink]] — remove brackets and path traversal
    static func sanitizeWikilink(_ name: String) -> String {
        name.replacingOccurrences(of: "[[", with: "")
            .replacingOccurrences(of: "]]", with: "")
            .replacingOccurrences(of: "/", with: "-")
            .replacingOccurrences(of: "\\", with: "-")
            .replacingOccurrences(of: "..", with: "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    // MARK: - Area Projects Cleanup

    /// Find which Area contains a given project by checking frontmatter and Area index notes
    static func findAreaForProject(projectName: String, pkmRoot: String) -> String? {
        let pm = PKMPathManager(root: pkmRoot)
        let fm = FileManager.default

        // 1. Check project index note for area field
        let projectIndexPath = (pm.projectsPath as NSString)
            .appendingPathComponent(projectName)
            .appending("/\(projectName).md")
        if let content = try? String(contentsOfFile: projectIndexPath, encoding: .utf8) {
            let (frontmatter, _) = Frontmatter.parse(markdown: content)
            if let area = frontmatter.area { return area }
        }

        // 2. Scan all Area index notes for projects field containing this project
        guard let areas = try? fm.contentsOfDirectory(atPath: pm.areaPath) else { return nil }
        for area in areas {
            guard !area.hasPrefix("."), !area.hasPrefix("_") else { continue }
            let areaIndexPath = (pm.areaPath as NSString)
                .appendingPathComponent(area)
                .appending("/\(area).md")
            guard let content = try? String(contentsOfFile: areaIndexPath, encoding: .utf8) else { continue }
            let (frontmatter, _) = Frontmatter.parse(markdown: content)
            if let projects = frontmatter.projects, projects.contains(projectName) {
                return area
            }
        }
        return nil
    }

    /// Remove a project name from its Area index note's projects field
    static func removeProjectFromArea(projectName: String, pkmRoot: String) {
        guard let areaName = findAreaForProject(projectName: projectName, pkmRoot: pkmRoot) else { return }
        let pm = PKMPathManager(root: pkmRoot)
        let areaIndexPath = (pm.areaPath as NSString)
            .appendingPathComponent(areaName)
            .appending("/\(areaName).md")

        guard let content = try? String(contentsOfFile: areaIndexPath, encoding: .utf8) else { return }
        var (frontmatter, body) = Frontmatter.parse(markdown: content)
        guard var projects = frontmatter.projects, projects.contains(projectName) else { return }

        projects.removeAll { $0 == projectName }
        frontmatter.projects = projects.isEmpty ? nil : projects

        let updated = frontmatter.stringify() + "\n" + body
        try? updated.write(toFile: areaIndexPath, atomically: true, encoding: .utf8)
    }

    /// Rename a project reference in its Area index note's projects field
    static func renameProjectInArea(oldName: String, newName: String, pkmRoot: String) {
        guard let areaName = findAreaForProject(projectName: oldName, pkmRoot: pkmRoot) else { return }
        let pm = PKMPathManager(root: pkmRoot)
        let areaIndexPath = (pm.areaPath as NSString)
            .appendingPathComponent(areaName)
            .appending("/\(areaName).md")

        guard let content = try? String(contentsOfFile: areaIndexPath, encoding: .utf8) else { return }
        var (frontmatter, body) = Frontmatter.parse(markdown: content)
        guard var projects = frontmatter.projects, projects.contains(oldName) else { return }

        projects = projects.map { $0 == oldName ? newName : $0 }
        frontmatter.projects = projects

        let updated = frontmatter.stringify() + "\n" + body
        try? updated.write(toFile: areaIndexPath, atomically: true, encoding: .utf8)
    }

    /// Add a project name to its Area index note's projects field
    static func addProjectToArea(projectName: String, areaName: String, pkmRoot: String) {
        let pm = PKMPathManager(root: pkmRoot)
        let areaIndexPath = (pm.areaPath as NSString)
            .appendingPathComponent(areaName)
            .appending("/\(areaName).md")

        guard let content = try? String(contentsOfFile: areaIndexPath, encoding: .utf8) else { return }
        var (frontmatter, body) = Frontmatter.parse(markdown: content)

        var projects = frontmatter.projects ?? []
        guard !projects.contains(projectName) else { return }
        projects.append(projectName)
        projects.sort()
        frontmatter.projects = projects

        let updated = frontmatter.stringify() + "\n" + body
        try? updated.write(toFile: areaIndexPath, atomically: true, encoding: .utf8)
    }

    /// Create index note for a new subfolder
    static func createIndexNote(
        folderName: String,
        para: PARACategory,
        description: String = "",
        area: String? = nil,
        projects: [String]? = nil
    ) -> String {
        var fm = Frontmatter.createDefault(
            para: para,
            tags: [],
            summary: description,
            source: .original
        )
        fm.area = area
        fm.projects = projects

        return fm.stringify() + "\n"
    }
}
