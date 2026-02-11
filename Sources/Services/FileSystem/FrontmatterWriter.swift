import Foundation

/// Handles frontmatter injection into markdown files
enum FrontmatterWriter {
    /// Inject frontmatter into markdown content, with optional [[project]] and related note wikilinks.
    /// Completely replaces existing frontmatter with DotBrain format (only preserves `created`).
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

        // Only preserve `created` from existing frontmatter
        if let existingCreated = existing.created {
            newFM.created = existingCreated
        }

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

    /// Create companion markdown for binary files
    static func createCompanionMarkdown(
        for extractResult: ExtractResult,
        classification: ClassifyResult
    ) -> String {
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

        let body = extractResult.text ?? "파일: \(extractResult.file?.name ?? "unknown")"
        return fm.stringify() + "\n\n" + body + "\n"
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
