import Foundation
import CryptoKit

/// Moves files to PARA folders with conflict resolution and index note creation
struct FileMover {
    let pkmRoot: String
    private let pathManager: PKMPathManager

    /// Per-directory body hash cache to avoid rescanning the same folder repeatedly.
    /// Maps dirPath -> [bodyHash -> filePath].
    private let bodyHashCache = BodyHashCache()

    init(pkmRoot: String) {
        self.pkmRoot = pkmRoot
        self.pathManager = PKMPathManager(root: pkmRoot)
    }

    /// Reference-type wrapper so the cache is mutable without requiring mutating methods.
    private final class BodyHashCache {
        var storage: [String: [String: String]] = [:]
    }

    /// Check if moving this file would conflict with the index note
    func wouldConflictWithIndexNote(fileName: String, classification: ClassifyResult) -> Bool {
        guard classification.para != .project else { return false }
        guard !classification.targetFolder.isEmpty else { return false }
        let targetDir = pathManager.targetDirectory(for: classification)
        let indexBaseName = (targetDir as NSString).lastPathComponent
        let indexNoteName = "\(indexBaseName).md"
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

        // Validate source path is inside PKM root
        guard pathManager.isPathSafe(filePath) else {
            throw NSError(domain: "FileMover", code: 1,
                userInfo: [NSLocalizedDescriptionKey: "안전하지 않은 경로: \(fileName)"])
        }

        // Determine target directory
        let targetDir = pathManager.targetDirectory(for: classification)

        // Create target directory if needed
        try fm.createDirectory(atPath: targetDir, withIntermediateDirectories: true)

        // Create index note FIRST — index note is the authoritative management document
        if classification.para != .project {
            let indexFolderName = (targetDir as NSString).lastPathComponent
            try ensureIndexNote(at: targetDir, para: classification.para, folderName: indexFolderName)
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

        guard pathManager.isPathSafe(folderPath) else {
            throw NSError(domain: "FileMover", code: 1,
                userInfo: [NSLocalizedDescriptionKey: "안전하지 않은 경로: \(folderName)"])
        }

        // Target: PARA category directory
        let targetDir = pathManager.targetDirectory(for: classification)
        try fm.createDirectory(atPath: targetDir, withIntermediateDirectories: true)

        // Move the entire folder into the target
        let destPath = (targetDir as NSString).appendingPathComponent(folderName)
        let resolvedDest = resolveConflict(destPath)
        try fm.moveItem(atPath: folderPath, toPath: resolvedDest)

        // Create index note if missing (frontmatter only — no wikilinks list)
        let indexPath = (resolvedDest as NSString).appendingPathComponent("\(folderName).md")
        if !fm.fileExists(atPath: indexPath) {
            let content = FrontmatterWriter.createIndexNote(
                folderName: folderName,
                para: classification.para,
                description: classification.summary
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

    private func moveBinaryFile(
        filePath: String,
        fileName: String,
        targetDir: String,
        classification: ClassifyResult
    ) async throws -> ProcessedFileResult {
        let fm = FileManager.default

        let assetsDir = pathManager.assetsDirectory(for: filePath)
        try fm.createDirectory(atPath: assetsDir, withIntermediateDirectories: true)

        // Duplicate check: hash for normal files, metadata for large files (>500MB)
        let fileSize = (try? fm.attributesOfItem(atPath: filePath)[.size] as? Int) ?? 0
        let maxHashSize = 500 * 1024 * 1024  // 500MB
        var dupPath: String? = nil

        if fileSize <= maxHashSize,
           let sourceHash = streamingHash(at: filePath) {
            dupPath = findDuplicateByHash(sourceHash, in: assetsDir)
        } else if fileSize > maxHashSize {
            // Large file: compare by size + modification date
            dupPath = findDuplicateByMetadata(fileSize: fileSize, filePath: filePath, in: assetsDir)
        }

        if let dupPath = dupPath {
            StatisticsService.incrementDuplicates()
            let dupFileName = (dupPath as NSString).lastPathComponent
            let companionPath = (targetDir as NSString).appendingPathComponent("\(fileName).md")
            mergeTags(classification.tags, into: companionPath)
            try fm.trashItem(at: URL(fileURLWithPath: filePath), resultingItemURL: nil)
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

        // Skip companion .md for image/video files — no useful text to summarize
        let ext = URL(fileURLWithPath: fileName).pathExtension.lowercased()
        let isImage = BinaryExtractor.imageExtensions.contains(ext)
        let isVideo = BinaryExtractor.videoExtensions.contains(ext)
        if isImage || isVideo {
            return ProcessedFileResult(
                fileName: fileName,
                para: classification.para,
                targetPath: resolvedAssetPath,
                tags: classification.tags
            )
        }

        // Create companion markdown with AI summary (documents only from here)
        let extractResult = BinaryExtractor.extract(at: resolvedAssetPath)

        // AI summarization — use full extracted text for rich companion note
        var aiSummary: String? = nil
        if let fullText = extractResult.text, !fullText.isEmpty {
            let prompt = """
            다음은 "\(fileName)" 파일에서 추출한 텍스트입니다.
            핵심 내용을 한국어로 요약해주세요. 마크다운 형식으로 작성하되:
            - 문서의 주제와 목적을 첫 문단에 서술
            - 주요 내용을 bullet point로 정리
            - 중요한 수치, 날짜, 이름은 그대로 보존
            - 전체 500자 이내로 간결하게

            ---
            \(fullText)
            """
            do {
                let aiResponse = try await AIService.shared.sendFastWithUsage(maxTokens: 1024, message: prompt)
                aiSummary = aiResponse.text
                if let usage = aiResponse.usage {
                    let model = await AIService.shared.fastModel
                    StatisticsService.logTokenUsage(operation: "summary", model: model, usage: usage)
                }
            } catch {
                // AI 요약 실패 시 원본 텍스트 앞부분 사용
                aiSummary = nil
            }
        }

        let mdContent = FrontmatterWriter.createCompanionMarkdown(
            for: extractResult,
            classification: classification,
            aiSummary: aiSummary,
            relatedNotes: classification.relatedNotes
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
        let (_, parsedBody) = Frontmatter.parse(markdown: content)
        let sourceBody = parsedBody.trimmingCharacters(in: .whitespacesAndNewlines)

        // Duplicate check: compare body against existing .md files in target
        if let dupPath = findDuplicateByBody(sourceBody, in: targetDir) {
            StatisticsService.incrementDuplicates()
            // Merge tags into existing file
            let dupFileName = (dupPath as NSString).lastPathComponent
            mergeTags(classification.tags, into: dupPath)
            try fm.trashItem(at: URL(fileURLWithPath: filePath), resultingItemURL: nil)
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

        // Guard: source == destination means file is already in place
        let resolvedSource = URL(fileURLWithPath: filePath).resolvingSymlinksInPath().path
        let resolvedDest = URL(fileURLWithPath: resolvedPath).resolvingSymlinksInPath().path
        if resolvedSource == resolvedDest {
            // Just update frontmatter in-place, no move needed
            let taggedContent = FrontmatterWriter.injectFrontmatter(
                into: content,
                para: classification.para,
                tags: classification.tags,
                summary: classification.summary,
                project: classification.project,
                relatedNotes: classification.relatedNotes
            )
            try taggedContent.write(toFile: filePath, atomically: true, encoding: .utf8)
            return ProcessedFileResult(
                fileName: fileName,
                para: classification.para,
                targetPath: filePath,
                tags: classification.tags
            )
        }

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

    /// Find a duplicate text file by comparing body content (ignoring frontmatter).
    /// Uses a per-directory hash cache so the directory is scanned at most once per FileMover instance.
    private func findDuplicateByBody(_ sourceBody: String, in dirPath: String) -> String? {
        let fm = FileManager.default
        guard !sourceBody.isEmpty else { return nil }

        let sourceHashDigest = SHA256.hash(data: Data(sourceBody.utf8))
        let sourceHash = sourceHashDigest.map { String(format: "%02x", $0) }.joined()

        // Build cache for this directory if not yet populated
        if bodyHashCache.storage[dirPath] == nil {
            var dirCache: [String: String] = [:]
            if let entries = try? fm.contentsOfDirectory(atPath: dirPath) {
                for entry in entries {
                    guard entry.hasSuffix(".md") else { continue }
                    let filePath = (dirPath as NSString).appendingPathComponent(entry)
                    guard let content = try? String(contentsOfFile: filePath, encoding: .utf8) else { continue }
                    let (_, existingBody) = Frontmatter.parse(markdown: content)
                    let trimmedBody = existingBody.trimmingCharacters(in: .whitespacesAndNewlines)
                    guard !trimmedBody.isEmpty else { continue }
                    let hashDigest = SHA256.hash(data: Data(trimmedBody.utf8))
                    let hashString = hashDigest.map { String(format: "%02x", $0) }.joined()
                    dirCache[hashString] = filePath
                }
            }
            bodyHashCache.storage[dirPath] = dirCache
        }

        return bodyHashCache.storage[dirPath]?[sourceHash]
    }

    /// Find a duplicate large binary file by comparing size + modification date
    private func findDuplicateByMetadata(fileSize: Int, filePath: String, in dirPath: String) -> String? {
        let fm = FileManager.default
        guard let entries = try? fm.contentsOfDirectory(atPath: dirPath) else { return nil }
        let srcAttr = try? fm.attributesOfItem(atPath: filePath)
        let srcDate = srcAttr?[.modificationDate] as? Date

        for entry in entries {
            let existingPath = (dirPath as NSString).appendingPathComponent(entry)
            guard let attr = try? fm.attributesOfItem(atPath: existingPath) else { continue }
            let existingSize = attr[.size] as? Int
            let existingDate = attr[.modificationDate] as? Date
            if existingSize == fileSize, existingDate == srcDate {
                return existingPath
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
