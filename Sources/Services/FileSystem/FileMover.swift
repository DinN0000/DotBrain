import Foundation

/// Moves files to PARA folders with conflict resolution and index note creation
struct FileMover {
    let pkmRoot: String

    private var pathManager: PKMPathManager {
        PKMPathManager(root: pkmRoot)
    }

    /// Move a file according to its classification result
    func moveFile(at filePath: String, with classification: ClassifyResult) async throws -> ProcessedFileResult {
        let fm = FileManager.default
        let fileName = (filePath as NSString).lastPathComponent

        // Determine target directory
        let targetDir = pathManager.targetDirectory(for: classification)

        // Create target directory if needed
        try fm.createDirectory(atPath: targetDir, withIntermediateDirectories: true)

        // Ensure index note exists for new subfolders (Area/Resource/Archive)
        if classification.para != .project {
            try ensureIndexNote(at: targetDir, para: classification.para, folderName: classification.targetFolder)
        }

        let isBinary = BinaryExtractor.isBinaryFile(filePath)

        if isBinary {
            return try await moveBinaryFile(filePath: filePath, fileName: fileName, targetDir: targetDir, classification: classification)
        } else {
            return try moveTextFile(filePath: filePath, fileName: fileName, targetDir: targetDir, classification: classification)
        }
    }

    // MARK: - Private

    private func moveBinaryFile(
        filePath: String,
        fileName: String,
        targetDir: String,
        classification: ClassifyResult
    ) async throws -> ProcessedFileResult {
        let fm = FileManager.default

        // Move binary to _Assets/ subdirectory
        let assetsDir = pathManager.assetsDirectory(for: targetDir)
        try fm.createDirectory(atPath: assetsDir, withIntermediateDirectories: true)

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

        let targetPath = (targetDir as NSString).appendingPathComponent(fileName)
        let resolvedPath = resolveConflict(targetPath)

        // Read content, inject frontmatter, write to target
        let content = try String(contentsOfFile: filePath, encoding: .utf8)
        let taggedContent = FrontmatterWriter.injectFrontmatter(
            into: content,
            para: classification.para,
            tags: classification.tags,
            summary: classification.summary,
            project: classification.project
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
        while true {
            let newName = ext.isEmpty ? "\(baseName)_\(counter)" : "\(baseName)_\(counter).\(ext)"
            let newPath = (dir as NSString).appendingPathComponent(newName)
            if !fm.fileExists(atPath: newPath) {
                return newPath
            }
            counter += 1
        }
    }
}
