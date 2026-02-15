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
        let weightedContext = contextBuilder.buildWeightedContext()

        onProgress?(0.15, "프로젝트 컨텍스트 로드 완료")

        // Extract content — parallel using TaskGroup
        let inputs: [ClassifyInput] = await withTaskGroup(
            of: ClassifyInput.self,
            returning: [ClassifyInput].self
        ) { group in
            for filePath in uniqueFiles {
                group.addTask {
                    let content = self.extractContent(from: filePath)
                    let fileName = (filePath as NSString).lastPathComponent
                    return ClassifyInput(
                        filePath: filePath,
                        content: content,
                        fileName: fileName
                    )
                }
            }

            var collected: [ClassifyInput] = []
            collected.reserveCapacity(uniqueFiles.count)
            for await input in group {
                collected.append(input)
            }
            let fileIndex = Dictionary(uniqueKeysWithValues: uniqueFiles.enumerated().map { ($1, $0) })
            return collected.sorted { a, b in
                (fileIndex[a.filePath] ?? Int.max) < (fileIndex[b.filePath] ?? Int.max)
            }
        }

        onProgress?(0.3, "\(inputs.count)개 파일 내용 추출 완료")

        onProgress?(0.3, "AI 분류 시작...")

        // Classify with AI
        let classifier = Classifier()
        let classifications = try await classifier.classifyFiles(
            inputs,
            projectContext: projectContext,
            subfolderContext: subfolderContext,
            projectNames: projectNames,
            weightedContext: weightedContext,
            onProgress: { [onProgress] progress, status in
                let mappedProgress = 0.3 + progress * 0.4
                onProgress?(mappedProgress, status)
            }
        )

        // Record estimated API cost
        let estimatedCost = Double(inputs.count) * 0.001  // ~$0.001 per file (rough estimate)
        StatisticsService.addApiCost(estimatedCost)

        // Enrich with related notes — AI-based context linking
        let contextMap = await ContextMapBuilder(pkmRoot: pkmRoot).build()
        let linker = ContextLinker(pkmRoot: pkmRoot)
        let filePairs = zip(inputs, classifications).map { (input: $0, classification: $1) }
        let relatedMap = await linker.findRelatedNotes(for: filePairs, contextMap: contextMap)

        var enrichedClassifications = classifications
        for (index, notes) in relatedMap {
            enrichedClassifications[index].relatedNotes = notes
        }

        // Compare and process
        for (i, (classification, input)) in zip(enrichedClassifications, inputs).enumerated() {
            let progress = 0.7 + Double(i) / Double(max(enrichedClassifications.count, 1)) * 0.25
            onProgress?(progress, "\(input.fileName) 처리 중...")

            let currentCategory = category
            let currentFolder = subfolder

            let targetFolder = classification.targetFolder
            let targetCategory = classification.para

            let locationMatches = targetCategory == currentCategory && targetFolder == currentFolder

            if locationMatches {
                // Location correct — replace frontmatter with DotBrain format
                let result = updateFrontmatter(
                    at: input.filePath,
                    classification: classification
                )
                processed.append(result)
                if result.isSuccess {
                    StatisticsService.recordActivity(
                        fileName: input.fileName,
                        category: classification.para.rawValue,
                        action: "reorganized"
                    )
                }
            } else {
                // Location wrong — auto-move to AI-recommended location
                let fromDisplay = "\(category.folderName)/\(subfolder)"
                let mover = FileMover(pkmRoot: pkmRoot)
                do {
                    let result = try await mover.moveFile(at: input.filePath, with: classification)
                    processed.append(ProcessedFileResult(
                        fileName: result.fileName,
                        para: result.para,
                        targetPath: result.targetPath,
                        tags: result.tags,
                        status: .relocated(from: fromDisplay)
                    ))
                    StatisticsService.recordActivity(
                        fileName: input.fileName,
                        category: classification.para.rawValue,
                        action: "relocated"
                    )
                } catch {
                    processed.append(ProcessedFileResult(
                        fileName: input.fileName,
                        para: classification.para,
                        targetPath: "",
                        tags: classification.tags,
                        status: .error("이동 실패: \(error.localizedDescription)")
                    ))
                }
            }
        }

        // Update MOCs for affected folders (source + all targets)
        let mocGenerator = MOCGenerator(pkmRoot: pkmRoot)
        try? await mocGenerator.generateMOC(folderPath: folderPath, folderName: subfolder, para: category)

        let affectedFolders = Set(processed.filter(\.isSuccess).compactMap { result -> String? in
            let dir = (result.targetPath as NSString).deletingLastPathComponent
            return dir.isEmpty || dir == folderPath ? nil : dir
        })
        if !affectedFolders.isEmpty {
            await mocGenerator.updateMOCsForFolders(affectedFolders)
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
            needsConfirmation: [],
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
            do {
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
                    try fm.moveItem(atPath: file.source, toPath: resolved)
                } else {
                    try fm.moveItem(atPath: file.source, toPath: destPath)
                }
                movedCount += 1
            } catch {
                print("[FolderReorganizer] 이동 실패: \(file.fileName) — \(error.localizedDescription)")
            }
        }

        // Delete placeholder files
        for placeholder in placeholderFiles {
            do {
                try fm.removeItem(atPath: placeholder)
            } catch {
                print("[FolderReorganizer] 플레이스홀더 삭제 실패: \(error.localizedDescription)")
            }
        }

        // Delete empty directories (deepest first by path length)
        let sortedDirs = directories.sorted { $0.count > $1.count }
        for dir in sortedDirs {
            let contents = (try? fm.contentsOfDirectory(atPath: dir)) ?? []
            let nonHidden = contents.filter { !$0.hasPrefix(".") }
            if nonHidden.isEmpty {
                do {
                    try fm.removeItem(atPath: dir)
                } catch {
                    print("[FolderReorganizer] 빈 폴더 삭제 실패: \(error.localizedDescription)")
                }
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
                try? FileManager.default.trashItem(at: URL(fileURLWithPath: filePath), resultingItemURL: nil)
                StatisticsService.incrementDuplicates()
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

    /// Replace frontmatter with DotBrain format, preserving only `created`
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

        // Build ## Related Notes section with context descriptions
        var relatedBody = body
        var lines: [String] = []
        if let project = classification.project, !project.isEmpty, !relatedBody.contains("[[\(project)]]") {
            lines.append("- [[\(project)]] — 소속 프로젝트")
        }
        for note in classification.relatedNotes where !relatedBody.contains("[[\(note.name)]]") {
            lines.append("- [[\(note.name)]] — \(note.context)")
        }
        if !lines.isEmpty {
            relatedBody += "\n\n## Related Notes\n" + lines.joined(separator: "\n") + "\n"
        }

        let updatedContent = newFM.stringify() + "\n" + relatedBody
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
        FileContentExtractor.extract(from: filePath)
    }

}
