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
            lines.append("- [[\(project)]] — 소속 프로젝트")
        }
        for note in relatedNotes where !result.contains("[[\(note.name)]]") {
            lines.append("- [[\(note.name)]] — \(note.context)")
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

        // Original file link
        result += "\n## 원본 파일\n\n"
        result += "![[_Assets/\(fileName)]]\n"

        // Related Notes
        var lines: [String] = []
        if let project = classification.project, !project.isEmpty {
            lines.append("- [[\(project)]] — 소속 프로젝트")
        }
        for note in relatedNotes where !result.contains("[[\(note.name)]]") {
            lines.append("- [[\(note.name)]] — \(note.context)")
        }
        if !lines.isEmpty {
            result += "\n## Related Notes\n\n" + lines.joined(separator: "\n") + "\n"
        }

        return result
    }

    /// Create index note for a new subfolder
    static func createIndexNote(
        folderName: String,
        para: PARACategory,
        description: String = ""
    ) -> String {
        let fm = Frontmatter.createDefault(
            para: para,
            tags: [],
            summary: description,
            source: .original
        )

        return """
        \(fm.stringify())

        ## 포함된 노트

        """
    }
}
