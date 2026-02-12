import Foundation
import CryptoKit

/// Moves files to PARA folders with conflict resolution and index note creation
struct FileMover {
    let pkmRoot: String

    private var pathManager: PKMPathManager {
        PKMPathManager(root: pkmRoot)
    }

    /// Check if moving this file would conflict with the index note
    func wouldConflictWithIndexNote(fileName: String, classification: ClassifyResult) -> Bool {
        guard classification.para != .project else { return false }
        guard !classification.targetFolder.isEmpty else { return false }
        let indexNoteName = "\(classification.targetFolder).md"
        return fileName == indexNoteName
    }

    /// Check if a file with the same name already exists at the target (different content)
    func wouldConflictWithExistingFile(fileName: String, classification: ClassifyResult) -> Bool {
        let targetDir = pathManager.targetDirectory(for: classification)
        let targetPath = (targetDir as NSString).appendingPathComponent(fileName)
        return FileManager.default.fileExists(atPath: targetPath)
    }

    /// Move a file according to its classification result
    func moveFile(at filePath: String, with classification: ClassifyResult) async throws -> ProcessedFileResult {
        let fm = FileManager.default
        let fileName = (filePath as NSString).lastPathComponent

        // Determine target directory
        let targetDir = pathManager.targetDirectory(for: classification)

        // Create target directory if needed
        try fm.createDirectory(atPath: targetDir, withIntermediateDirectories: true)

        // Create index note FIRST — index note is the authoritative management document
        if classification.para != .project {
            try ensureIndexNote(at: targetDir, para: classification.para, folderName: classification.targetFolder)
        }

        let isBinary = BinaryExtractor.isBinaryFile(filePath)

        let result: ProcessedFileResult
        if isBinary {
            result = try await moveBinaryFile(filePath: filePath, fileName: fileName, targetDir: targetDir, classification: classification)
        } else {
            result = try moveTextFile(filePath: filePath, fileName: fileName, targetDir: targetDir, classification: classification)
        }

        return result
    }

    /// Move an entire folder — keep structure intact, create index note with [[wikilinks]]
    func moveFolder(at folderPath: String, with classification: ClassifyResult) throws -> ProcessedFileResult {
        let fm = FileManager.default
        let folderName = (folderPath as NSString).lastPathComponent

        // Target: PARA category directory
        let targetDir = pathManager.targetDirectory(for: classification)
        try fm.createDirectory(atPath: targetDir, withIntermediateDirectories: true)

        // Move the entire folder into the target
        let destPath = (targetDir as NSString).appendingPathComponent(folderName)
        let resolvedDest = resolveConflict(destPath)
        try fm.moveItem(atPath: folderPath, toPath: resolvedDest)

        // Collect all notes inside with context summaries for [[wikilinks]]
        let noteEntries = collectNoteEntries(in: resolvedDest)

        // Create or update index note with wikilinks
        let indexPath = (resolvedDest as NSString).appendingPathComponent("\(folderName).md")
        if fm.fileExists(atPath: indexPath) {
            try appendWikilinksSection(to: indexPath, entries: noteEntries)
        } else {
            let content = createFolderIndexContent(
                folderName: folderName,
                para: classification.para,
                tags: classification.tags,
                summary: classification.summary,
                entries: noteEntries
            )
            try content.write(toFile: indexPath, atomically: true, encoding: .utf8)
        }

        return ProcessedFileResult(
            fileName: folderName,
            para: classification.para,
            targetPath: resolvedDest,
            tags: classification.tags
        )
    }

    // MARK: - Private

    /// Note entry: name (for wikilink) + context summary from content
    private struct NoteEntry {
        let name: String
        let context: String
    }

    /// Collect markdown notes inside a folder with context extracted from each file
    private func collectNoteEntries(in dirPath: String) -> [NoteEntry] {
        let fm = FileManager.default
        guard let entries = try? fm.contentsOfDirectory(atPath: dirPath) else { return [] }
        let folderName = (dirPath as NSString).lastPathComponent

        return entries.sorted().compactMap { fileName -> NoteEntry? in
            guard fileName.hasSuffix(".md") else { return nil }
            let baseName = (fileName as NSString).deletingPathExtension
            guard baseName != folderName else { return nil } // skip index note itself

            let filePath = (dirPath as NSString).appendingPathComponent(fileName)
            let context = extractContext(from: filePath)
            return NoteEntry(name: baseName, context: context)
        }
    }

    /// Extract a one-line context summary from a note's content
    private func extractContext(from filePath: String) -> String {
        guard let content = try? String(contentsOfFile: filePath, encoding: .utf8) else {
            return ""
        }

        // Strip frontmatter (--- ... ---)
        var body = content
        if body.hasPrefix("---") {
            if let endRange = body.range(of: "---", range: body.index(body.startIndex, offsetBy: 3)..<body.endIndex) {
                body = String(body[endRange.upperBound...])
            }
        }

        // Find first meaningful line (skip blank lines and headings)
        let lines = body.components(separatedBy: .newlines)
        for line in lines {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed.isEmpty || trimmed.hasPrefix("#") { continue }
            // Truncate to reasonable length
            let maxLen = 80
            if trimmed.count > maxLen {
                return String(trimmed.prefix(maxLen)) + "…"
            }
            return trimmed
        }

        return ""
    }

    /// Create index note content with [[wikilinks]] + context for Obsidian
    private func createFolderIndexContent(
        folderName: String,
        para: PARACategory,
        tags: [String],
        summary: String,
        entries: [NoteEntry]
    ) -> String {
        let fm = Frontmatter.createDefault(
            para: para,
            tags: tags,
            summary: summary,
            source: .original
        )

        var content = fm.stringify() + "\n\n"
        content += "## 포함된 노트\n\n"
        for entry in entries {
            if entry.context.isEmpty {
                content += "- [[\(entry.name)]]\n"
            } else {
                content += "- [[\(entry.name)]] — \(entry.context)\n"
            }
        }
        return content
    }

    /// Append [[wikilinks]] section to an existing index note if not already present
    private func appendWikilinksSection(to indexPath: String, entries: [NoteEntry]) throws {
        var content = try String(contentsOfFile: indexPath, encoding: .utf8)
        guard !content.contains("## 포함된 노트") else { return }

        content += "\n\n## 포함된 노트\n\n"
        for entry in entries {
            if entry.context.isEmpty {
                content += "- [[\(entry.name)]]\n"
            } else {
                content += "- [[\(entry.name)]] — \(entry.context)\n"
            }
        }
        try content.write(toFile: indexPath, atomically: true, encoding: .utf8)
    }

    private func moveBinaryFile(
        filePath: String,
        fileName: String,
        targetDir: String,
        classification: ClassifyResult
    ) async throws -> ProcessedFileResult {
        let fm = FileManager.default

        let assetsDir = pathManager.assetsDirectory(for: targetDir)
        try fm.createDirectory(atPath: assetsDir, withIntermediateDirectories: true)

        // Duplicate check: skip hash for large files (>500MB) to avoid memory issues
        let fileSize = (try? fm.attributesOfItem(atPath: filePath)[.size] as? Int) ?? 0
        let maxHashSize = 500 * 1024 * 1024  // 500MB
        if fileSize <= maxHashSize,
           let sourceHash = streamingHash(at: filePath),
           let dupPath = findDuplicateByHash(sourceHash, in: assetsDir) {
            StatisticsService.incrementDuplicates()
            // Merge tags into companion markdown if it exists
            let dupFileName = (dupPath as NSString).lastPathComponent
            let companionPath = (targetDir as NSString).appendingPathComponent("\(dupFileName).md")
            mergeTags(classification.tags, into: companionPath)
            try fm.removeItem(atPath: filePath)
            return ProcessedFileResult(
                fileName: fileName,
                para: classification.para,
                targetPath: companionPath,
                tags: classification.tags,
                status: .deduplicated("중복 — \(dupFileName)와 병합됨")
            )
        }

        let assetPath = (assetsDir as NSString).appendingPathComponent(fileName)
        let resolvedAssetPath = resolveConflict(assetPath)
        try fm.moveItem(atPath: filePath, toPath: resolvedAssetPath)

        // Create companion markdown
        let extractResult = BinaryExtractor.extract(at: resolvedAssetPath)
        let mdContent = FrontmatterWriter.createCompanionMarkdown(
            for: extractResult,
            classification: classification
        )

        let mdPath = (targetDir as NSString).appendingPathComponent("\(fileName).md")
        try mdContent.write(toFile: mdPath, atomically: true, encoding: .utf8)

        return ProcessedFileResult(
            fileName: fileName,
            para: classification.para,
            targetPath: mdPath,
            tags: classification.tags
        )
    }

    private func moveTextFile(
        filePath: String,
        fileName: String,
        targetDir: String,
        classification: ClassifyResult
    ) throws -> ProcessedFileResult {
        let fm = FileManager.default

        // Read source content body (strip frontmatter for comparison)
        let content = try String(contentsOfFile: filePath, encoding: .utf8)
        let sourceBody = stripFrontmatter(content)

        // Duplicate check: compare body against existing .md files in target
        if let dupPath = findDuplicateByBody(sourceBody, in: targetDir) {
            StatisticsService.incrementDuplicates()
            // Merge tags into existing file
            let dupFileName = (dupPath as NSString).lastPathComponent
            mergeTags(classification.tags, into: dupPath)
            try fm.removeItem(atPath: filePath)
            return ProcessedFileResult(
                fileName: fileName,
                para: classification.para,
                targetPath: dupPath,
                tags: classification.tags,
                status: .deduplicated("중복 — \(dupFileName)와 병합됨")
            )
        }

        let targetPath = (targetDir as NSString).appendingPathComponent(fileName)
        let resolvedPath = resolveConflict(targetPath)

        let taggedContent = FrontmatterWriter.injectFrontmatter(
            into: content,
            para: classification.para,
            tags: classification.tags,
            summary: classification.summary,
            project: classification.project,
            relatedNotes: classification.relatedNotes
        )

        try taggedContent.write(toFile: resolvedPath, atomically: true, encoding: .utf8)
        try fm.removeItem(atPath: filePath)

        return ProcessedFileResult(
            fileName: fileName,
            para: classification.para,
            targetPath: resolvedPath,
            tags: classification.tags
        )
    }

    // MARK: - Streaming Hash

    /// Compute SHA256 hash by reading in 1MB chunks instead of loading entire file
    private func streamingHash(at path: String) -> SHA256Digest? {
        guard let handle = FileHandle(forReadingAtPath: path) else { return nil }
        defer { try? handle.close() }
        var hasher = SHA256()
        while true {
            let chunk = handle.readData(ofLength: 1024 * 1024) // 1MB chunks
            guard !chunk.isEmpty else { break }
            hasher.update(data: chunk)
        }
        return hasher.finalize()
    }

    // MARK: - Duplicate Detection

    /// Strip frontmatter and whitespace for content comparison
    private func stripFrontmatter(_ text: String) -> String {
        var body = text
        if body.hasPrefix("---") {
            if let endRange = body.range(of: "---", range: body.index(body.startIndex, offsetBy: 3)..<body.endIndex) {
                body = String(body[endRange.upperBound...])
            }
        }
        return body.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// Find a duplicate text file by comparing body content (ignoring frontmatter)
    private func findDuplicateByBody(_ sourceBody: String, in dirPath: String) -> String? {
        let fm = FileManager.default
        guard !sourceBody.isEmpty else { return nil }
        guard let entries = try? fm.contentsOfDirectory(atPath: dirPath) else { return nil }

        let sourceHash = SHA256.hash(data: Data(sourceBody.utf8))

        for entry in entries {
            guard entry.hasSuffix(".md") else { continue }
            let filePath = (dirPath as NSString).appendingPathComponent(entry)

            guard let content = try? String(contentsOfFile: filePath, encoding: .utf8) else { continue }
            let existingBody = stripFrontmatter(content)
            let existingHash = SHA256.hash(data: Data(existingBody.utf8))

            if sourceHash == existingHash {
                return filePath
            }
        }
        return nil
    }

    /// Find a duplicate binary file by comparing streaming hash digests
    private func findDuplicateByHash(_ sourceHash: SHA256Digest, in dirPath: String) -> String? {
        let fm = FileManager.default
        guard let entries = try? fm.contentsOfDirectory(atPath: dirPath) else { return nil }

        for entry in entries {
            let filePath = (dirPath as NSString).appendingPathComponent(entry)
            guard let existingHash = streamingHash(at: filePath) else { continue }
            if existingHash == sourceHash {
                return filePath
            }
        }
        return nil
    }

    /// Merge new tags into an existing file's frontmatter (deduplicates and sorts)
    @discardableResult
    private func mergeTags(_ newTags: [String], into filePath: String) -> Bool {
        guard !newTags.isEmpty else { return true }
        guard let content = try? String(contentsOfFile: filePath, encoding: .utf8) else { return false }

        let (existing, body) = Frontmatter.parse(markdown: content)
        let mergedTags = Array(Set(existing.tags + newTags)).sorted()

        guard mergedTags != existing.tags.sorted() else { return true } // no change needed

        var updated = existing
        updated.tags = mergedTags
        let result = updated.stringify() + "\n" + body
        do {
            try result.write(toFile: filePath, atomically: true, encoding: .utf8)
            return true
        } catch {
            return false
        }
    }

    /// Ensure index note exists for subfolder
    private func ensureIndexNote(at dir: String, para: PARACategory, folderName: String) throws {
        guard !folderName.isEmpty else { return }

        let indexPath = (dir as NSString).appendingPathComponent("\(folderName).md")
        let fm = FileManager.default

        guard !fm.fileExists(atPath: indexPath) else { return }

        let content = FrontmatterWriter.createIndexNote(
            folderName: folderName,
            para: para,
            description: "\(folderName) 관련 자료"
        )

        try content.write(toFile: indexPath, atomically: true, encoding: .utf8)
    }

    /// Resolve filename conflicts by appending _2, _3, etc.
    private func resolveConflict(_ path: String) -> String {
        let fm = FileManager.default
        guard fm.fileExists(atPath: path) else { return path }

        let dir = (path as NSString).deletingLastPathComponent
        let ext = (path as NSString).pathExtension
        let baseName: String
        if ext.isEmpty {
            baseName = (path as NSString).lastPathComponent
        } else {
            baseName = ((path as NSString).lastPathComponent as NSString).deletingPathExtension
        }

        var counter = 2
        let maxAttempts = 1000
        while counter < maxAttempts {
            let newName = ext.isEmpty ? "\(baseName)_\(counter)" : "\(baseName)_\(counter).\(ext)"
            let newPath = (dir as NSString).appendingPathComponent(newName)
            if !fm.fileExists(atPath: newPath) {
                return newPath
            }
            counter += 1
        }
        // Fallback with UUID to guarantee uniqueness
        let uuid = UUID().uuidString.prefix(8)
        let fallbackName = ext.isEmpty ? "\(baseName)_\(uuid)" : "\(baseName)_\(uuid).\(ext)"
        return (dir as NSString).appendingPathComponent(fallbackName)
    }
}
