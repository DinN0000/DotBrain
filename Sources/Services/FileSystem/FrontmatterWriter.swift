import Foundation

/// Handles frontmatter injection into markdown files
enum FrontmatterWriter {
    /// Inject frontmatter into markdown content, with optional [[project]] wikilink.
    /// Completely replaces existing frontmatter with AI-PKM format (only preserves `created`).
    static func injectFrontmatter(
        into content: String,
        para: PARACategory,
        tags: [String],
        summary: String,
        source: NoteSource = .import,
        project: String? = nil,
        file: FileMetadata? = nil
    ) -> String {
        // Strip existing frontmatter completely — replace with AI-PKM format
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

        // Append [[project]] wikilink if related project exists and not already linked
        if let project = project, !project.isEmpty, !result.contains("[[\(project)]]") {
            result += "\n\n---\nrelated:: [[\(project)]]\n"
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
