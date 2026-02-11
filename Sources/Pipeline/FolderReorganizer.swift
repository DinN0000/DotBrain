import Foundation
import CryptoKit

/// Reorganizes an existing PARA subfolder:
/// Flatten → Scan → Extract → AI Classify → Compare/Process
struct FolderReorganizer {
    let pkmRoot: String
    let category: PARACategory
    let subfolder: String
    let onProgress: ((Double, String) -> Void)?

    private var pathManager: PKMPathManager {
        PKMPathManager(root: pkmRoot)
    }

    struct Result {
        var processed: [ProcessedFileResult]
        var needsConfirmation: [PendingConfirmation]
        var total: Int
    }

    func process() async throws -> Result {
        let folderPath = (pathManager.paraPath(for: category) as NSString)
            .appendingPathComponent(subfolder)

        onProgress?(0.02, "폴더 구조 정리 중...")

        // Step 1: Flatten nested folder hierarchy
        let flattenCount = flattenFolder(at: folderPath)
        if flattenCount > 0 {
            onProgress?(0.05, "\(flattenCount)개 파일 플랫화 완료")
        }

        // Step 2: Scan files (now flat)
        let files = scanFolder(at: folderPath)

        guard !files.isEmpty else {
            return Result(processed: [], needsConfirmation: [], total: 0)
        }

        onProgress?(0.05, "\(files.count)개 파일 발견")

        // Step 3: Deduplicate
        let (uniqueFiles, dupResults) = deduplicateFiles(files, in: folderPath)
        var processed = dupResults

        onProgress?(0.1, "중복 검사 완료")

        guard !uniqueFiles.isEmpty else {
            onProgress?(1.0, "완료!")
            return Result(processed: processed, needsConfirmation: [], total: files.count)
        }

        // Build context
        let contextBuilder = ProjectContextBuilder(pkmRoot: pkmRoot)
        let projectContext = contextBuilder.buildProjectContext()
        let subfolderContext = contextBuilder.buildSubfolderContext()
        let projectNames = contextBuilder.extractProjectNames(from: projectContext)

        onProgress?(0.15, "프로젝트 컨텍스트 로드 완료")

        // Extract content
        var inputs: [ClassifyInput] = []
        for (i, filePath) in uniqueFiles.enumerated() {
            let progress = 0.15 + Double(i) / Double(uniqueFiles.count) * 0.15
            let fileName = (filePath as NSString).lastPathComponent
            onProgress?(progress, "\(fileName) 내용 추출 중...")

            let content = extractContent(from: filePath)
            inputs.append(ClassifyInput(
                filePath: filePath,
                content: content,
                fileName: fileName
            ))
        }

        onProgress?(0.3, "AI 분류 시작...")

        // Classify with AI
        let classifier = Classifier()
        let classifications = try await classifier.classifyFiles(
            inputs,
            projectContext: projectContext,
            subfolderContext: subfolderContext,
            projectNames: projectNames,
            onProgress: { [onProgress] progress, status in
                let mappedProgress = 0.3 + progress * 0.4
                onProgress?(mappedProgress, status)
            }
        )

        // Compare and process
        var needsConfirmation: [PendingConfirmation] = []

        for (i, classification) in classifications.enumerated() {
            let progress = 0.7 + Double(i) / Double(classifications.count) * 0.25
            let input = inputs[i]
            onProgress?(progress, "\(input.fileName) 처리 중...")

            let currentCategory = category
            let currentFolder = subfolder

            let targetFolder = classification.targetFolder
            let targetCategory = classification.para

            let locationMatches = targetCategory == currentCategory && targetFolder == currentFolder

            if locationMatches {
                // Location correct — replace frontmatter with AI-PKM format
                let result = updateFrontmatter(
                    at: input.filePath,
                    classification: classification
                )
                processed.append(result)
            } else {
                // Location wrong — ask user to confirm move
                needsConfirmation.append(PendingConfirmation(
                    fileName: input.fileName,
                    filePath: input.filePath,
                    content: String(input.content.prefix(500)),
                    options: generateOptions(for: classification, projectNames: projectNames),
                    reason: .misclassified
                ))
            }
        }

        onProgress?(0.95, "완료 정리 중...")

        NotificationService.sendProcessingComplete(
            classified: processed.filter(\.isSuccess).count,
            total: files.count,
            failed: 0
        )

        onProgress?(1.0, "완료!")

        return Result(
            processed: processed,
            needsConfirmation: needsConfirmation,
            total: files.count
        )
    }

    // MARK: - Flatten

    /// Flatten nested folder hierarchy: move all content files to top level,
    /// delete placeholder/index files and empty directories.
    /// Returns the number of files moved.
    @discardableResult
    private func flattenFolder(at dirPath: String) -> Int {
        let fm = FileManager.default
        let topFolderName = (dirPath as NSString).lastPathComponent

        guard let enumerator = fm.enumerator(atPath: dirPath) else { return 0 }

        var filesToMove: [(source: String, fileName: String)] = []
        var placeholderFiles: [String] = []
        var directories: [String] = []

        while let relativePath = enumerator.nextObject() as? String {
            let fullPath = (dirPath as NSString).appendingPathComponent(relativePath)
            var isDir: ObjCBool = false
            guard fm.fileExists(atPath: fullPath, isDirectory: &isDir) else { continue }

            if isDir.boolValue {
                directories.append(fullPath)
                continue
            }

            let fileName = (fullPath as NSString).lastPathComponent

            // Skip hidden files
            guard !fileName.hasPrefix(".") else { continue }

            // Check if top-level file (not nested) — leave as is
            let components = relativePath.components(separatedBy: "/")
            guard components.count > 1 else { continue }

            // Check if placeholder/index file:
            // - filename matches parent directory name (e.g. 3_Resource/3_Resource.md)
            // - filename starts with _ (e.g. _Assets/_Assets.md)
            let parentDir = (fullPath as NSString).deletingLastPathComponent
            let parentDirName = (parentDir as NSString).lastPathComponent
            let baseName = (fileName as NSString).deletingPathExtension

            let isPlaceholder = baseName == parentDirName
                || baseName == topFolderName  // inner DOJANG/DOJANG.md → becomes the index note handled separately
                || fileName.hasPrefix("_")

            if isPlaceholder {
                // Special case: if this is the workspace root note (e.g. DOJANG/DOJANG/DOJANG.md),
                // check if it has real content worth keeping as the index note
                if baseName == topFolderName {
                    let indexDest = (dirPath as NSString).appendingPathComponent("\(topFolderName).md")
                    if !fm.fileExists(atPath: indexDest) {
                        // Move it as the index note instead of deleting
                        try? fm.moveItem(atPath: fullPath, toPath: indexDest)
                        continue
                    }
                }
                placeholderFiles.append(fullPath)
                continue
            }

            filesToMove.append((source: fullPath, fileName: fileName))
        }

        // Move nested content files to top level
        var movedCount = 0
        for file in filesToMove {
            let destPath = (dirPath as NSString).appendingPathComponent(file.fileName)
            if fm.fileExists(atPath: destPath) {
                // Name conflict — append suffix
                let ext = (file.fileName as NSString).pathExtension
                let base = (file.fileName as NSString).deletingPathExtension
                var counter = 2
                var resolved = destPath
                while fm.fileExists(atPath: resolved) {
                    let newName = ext.isEmpty ? "\(base)_\(counter)" : "\(base)_\(counter).\(ext)"
                    resolved = (dirPath as NSString).appendingPathComponent(newName)
                    counter += 1
                }
                try? fm.moveItem(atPath: file.source, toPath: resolved)
            } else {
                try? fm.moveItem(atPath: file.source, toPath: destPath)
            }
            movedCount += 1
        }

        // Delete placeholder files
        for placeholder in placeholderFiles {
            try? fm.removeItem(atPath: placeholder)
        }

        // Delete empty directories (deepest first by path length)
        let sortedDirs = directories.sorted { $0.count > $1.count }
        for dir in sortedDirs {
            let contents = (try? fm.contentsOfDirectory(atPath: dir)) ?? []
            let nonHidden = contents.filter { !$0.hasPrefix(".") }
            if nonHidden.isEmpty {
                try? fm.removeItem(atPath: dir)
            }
        }

        return movedCount
    }

    // MARK: - Scan

    /// Scan folder for top-level files, excluding index note and _Assets/
    private func scanFolder(at dirPath: String) -> [String] {
        let fm = FileManager.default
        guard let entries = try? fm.contentsOfDirectory(atPath: dirPath) else { return [] }
        let indexNoteName = "\(subfolder).md"

        return entries.compactMap { name -> String? in
            // Skip hidden files, _-prefixed, index note
            guard !name.hasPrefix("."), !name.hasPrefix("_") else { return nil }
            guard name != indexNoteName else { return nil }

            let fullPath = (dirPath as NSString).appendingPathComponent(name)
            var isDir: ObjCBool = false
            guard fm.fileExists(atPath: fullPath, isDirectory: &isDir) else { return nil }
            guard !isDir.boolValue else { return nil }
            return fullPath
        }.sorted()
    }

    // MARK: - Deduplication

    /// Find and remove duplicate files within the folder (SHA256 body comparison)
    private func deduplicateFiles(_ files: [String], in dirPath: String) -> ([String], [ProcessedFileResult]) {
        var seen: [String: String] = [:] // hash → first file path
        var unique: [String] = []
        var results: [ProcessedFileResult] = []

        for filePath in files {
            let hash = fileBodyHash(filePath)
            if let existingPath = seen[hash] {
                // Duplicate — merge tags and delete
                mergeTagsFromFile(source: filePath, into: existingPath)
                try? FileManager.default.removeItem(atPath: filePath)
                results.append(ProcessedFileResult(
                    fileName: (filePath as NSString).lastPathComponent,
                    para: category,
                    targetPath: existingPath,
                    tags: [],
                    status: .deduplicated("중복 — 태그 병합 후 삭제됨")
                ))
            } else {
                seen[hash] = filePath
                unique.append(filePath)
            }
        }

        return (unique, results)
    }

    /// Compute SHA256 hash of file body (ignoring frontmatter for .md files)
    private func fileBodyHash(_ filePath: String) -> String {
        if filePath.hasSuffix(".md"),
           let content = try? String(contentsOfFile: filePath, encoding: .utf8) {
            let body = stripFrontmatter(content)
            let hash = SHA256.hash(data: Data(body.utf8))
            return hash.map { String(format: "%02x", $0) }.joined()
        }
        if let data = FileManager.default.contents(atPath: filePath) {
            let hash = SHA256.hash(data: data)
            return hash.map { String(format: "%02x", $0) }.joined()
        }
        return UUID().uuidString // fallback: treat as unique
    }

    private func stripFrontmatter(_ text: String) -> String {
        var body = text
        if body.hasPrefix("---") {
            if let endRange = body.range(of: "---", range: body.index(body.startIndex, offsetBy: 3)..<body.endIndex) {
                body = String(body[endRange.upperBound...])
            }
        }
        return body.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// Merge tags from source file into target file's frontmatter
    private func mergeTagsFromFile(source sourcePath: String, into targetPath: String) {
        guard let sourceContent = try? String(contentsOfFile: sourcePath, encoding: .utf8),
              let targetContent = try? String(contentsOfFile: targetPath, encoding: .utf8) else { return }

        let (sourceFM, _) = Frontmatter.parse(markdown: sourceContent)
        let (targetFM, targetBody) = Frontmatter.parse(markdown: targetContent)

        let mergedTags = Array(Set(targetFM.tags + sourceFM.tags)).sorted()
        guard mergedTags != targetFM.tags.sorted() else { return }

        var updated = targetFM
        updated.tags = mergedTags
        let result = updated.stringify() + "\n" + targetBody
        try? result.write(toFile: targetPath, atomically: true, encoding: .utf8)
    }

    // MARK: - Frontmatter Update

    /// Replace frontmatter with AI-PKM format, preserving only `created`
    private func updateFrontmatter(
        at filePath: String,
        classification: ClassifyResult
    ) -> ProcessedFileResult {
        let fileName = (filePath as NSString).lastPathComponent

        guard let content = try? String(contentsOfFile: filePath, encoding: .utf8) else {
            return ProcessedFileResult(
                fileName: fileName,
                para: classification.para,
                targetPath: filePath,
                tags: classification.tags,
                status: .error("파일 읽기 실패")
            )
        }

        let (existing, body) = Frontmatter.parse(markdown: content)

        // Build new frontmatter — AI values override everything except `created`
        let newFM = Frontmatter(
            para: classification.para,
            tags: classification.tags,
            created: existing.created ?? Frontmatter.today(),
            status: .active,
            summary: classification.summary,
            source: .import,
            project: classification.project,
            file: existing.file
        )

        let updatedContent = newFM.stringify() + "\n" + body
        do {
            try updatedContent.write(toFile: filePath, atomically: true, encoding: .utf8)
        } catch {
            return ProcessedFileResult(
                fileName: fileName,
                para: classification.para,
                targetPath: filePath,
                tags: classification.tags,
                status: .error("쓰기 실패: \(error.localizedDescription)")
            )
        }

        return ProcessedFileResult(
            fileName: fileName,
            para: classification.para,
            targetPath: filePath,
            tags: classification.tags
        )
    }

    // MARK: - Content Extraction

    private func extractContent(from filePath: String) -> String {
        if BinaryExtractor.isBinaryFile(filePath) {
            let result = BinaryExtractor.extract(at: filePath)
            return result.text ?? "[바이너리 파일: \(result.file?.name ?? "unknown")]"
        }

        if let content = try? String(contentsOfFile: filePath, encoding: .utf8) {
            return String(content.prefix(5000))
        }

        return "[읽기 실패: \((filePath as NSString).lastPathComponent)]"
    }

    // MARK: - Options

    private func generateOptions(for base: ClassifyResult, projectNames: [String]) -> [ClassifyResult] {
        var options: [ClassifyResult] = [base]

        for cat in PARACategory.allCases where cat != base.para {
            options.append(ClassifyResult(
                para: cat,
                tags: base.tags,
                summary: base.summary,
                targetFolder: base.targetFolder,
                project: cat == .project ? projectNames.first : nil,
                confidence: 0.5
            ))
        }

        return options
    }
}
