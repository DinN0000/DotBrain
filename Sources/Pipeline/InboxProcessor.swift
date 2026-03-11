import Foundation

/// Orchestrates the full inbox processing pipeline
/// Scan → Extract → Classify → Move → Report
struct InboxProcessor {
    let pkmRoot: String
    let onProgress: ((Double, String) -> Void)?
    let onFileProgress: ((Int, Int, String) -> Void)?
    let onPhaseChange: ((ProcessingPhase) -> Void)?
    private static let maxAutoPasses = 3

    struct Result {
        var processed: [ProcessedFileResult]
        var needsConfirmation: [PendingConfirmation]
        var affectedFolders: Set<String>
        var total: Int
        var failed: Int
    }

    func process() async throws -> Result {
        onPhaseChange?(.preparing)
        let scanner = InboxScanner(pkmRoot: pkmRoot)
        var files = scanner.scan()

        guard !files.isEmpty else {
            return Result(processed: [], needsConfirmation: [], affectedFolders: [], total: 0, failed: 0)
        }

        // Warm up CLI process pool concurrently while context is being built
        let warmUpTask = Task { await AIService.shared.warmUpCLIPool() }

        StatisticsService.recordActivity(
            fileName: "인박스 처리",
            category: "system",
            action: "started",
            detail: "\(files.count)개 파일"
        )

        var allProcessed: [ProcessedFileResult] = []
        var allConfirmations: [PendingConfirmation] = []
        var allAffectedFolders: Set<String> = []
        var discoveredPaths = Set(files)
        var totalFailed = 0

        for passIndex in 0..<Self.maxAutoPasses {
            guard !files.isEmpty else { break }

            let rangeStart = Double(passIndex) / Double(Self.maxAutoPasses)
            let rangeEnd = Double(passIndex + 1) / Double(Self.maxAutoPasses)
            let progressMapper: (Double, String) -> Void = { progress, status in
                let mapped = rangeStart + progress * (rangeEnd - rangeStart)
                if passIndex == 0 {
                    self.onProgress?(mapped, status)
                } else {
                    self.onProgress?(mapped, L10n.Processing.processingRemaining(status))
                }
            }

            let passResult = try await processSinglePass(
                files: files,
                warmUpTask: passIndex == 0 ? warmUpTask : nil,
                onProgress: progressMapper
            )

            allProcessed.append(contentsOf: passResult.processed)
            allConfirmations.append(contentsOf: passResult.needsConfirmation)
            allAffectedFolders.formUnion(passResult.affectedFolders)
            totalFailed += passResult.failed

            if !passResult.needsConfirmation.isEmpty {
                files = []
                break
            }

            let remaining = scanner.scan()
            guard !remaining.isEmpty else {
                files = []
                break
            }

            discoveredPaths.formUnion(remaining)

            let passSucceeded = passResult.processed.contains(where: \.isSuccess)
            let countChanged = remaining.count != files.count
            guard passSucceeded || countChanged else {
                files = remaining
                break
            }

            files = remaining
        }

        let successCount = allProcessed.filter(\.isSuccess).count

        NotificationService.sendProcessingComplete(
            classified: successCount,
            total: discoveredPaths.count,
            failed: totalFailed
        )

        onFileProgress?(allProcessed.count + allConfirmations.count, allProcessed.count + allConfirmations.count, "")
        onProgress?(1.0, L10n.Processing.completed)

        StatisticsService.recordActivity(
            fileName: "인박스 처리",
            category: "system",
            action: "completed",
            detail: "\(successCount)/\(discoveredPaths.count)개 완료, \(totalFailed)개 실패"
        )

        return Result(
            processed: allProcessed,
            needsConfirmation: allConfirmations,
            affectedFolders: allAffectedFolders,
            total: discoveredPaths.count,
            failed: totalFailed
        )
    }

    private func processSinglePass(
        files: [String],
        warmUpTask: Task<Void, Never>?,
        onProgress: ((Double, String) -> Void)?
    ) async throws -> Result {
        onProgress?(0.05, L10n.Processing.foundFiles(files.count))
        onFileProgress?(0, files.count, "")

        // Build context — run independent builders concurrently
        // Ensure note-index covers all existing folders (new folders since last update)
        let pathManager = PKMPathManager(root: pkmRoot)
        let noteIndex = await Self.ensureIndexFresh(pathManager: pathManager)
        let contextBuilder = ProjectContextBuilder(pkmRoot: pkmRoot, noteIndex: noteIndex)
        let root = pkmRoot

        let contexts = await withTaskGroup(of: (Int, String).self, returning: [String].self) { group in
            group.addTask { (0, contextBuilder.buildProjectContext()) }
            group.addTask { (1, contextBuilder.buildSubfolderContext()) }
            group.addTask { (2, contextBuilder.buildTagVocabulary()) }
            group.addTask { (3, contextBuilder.buildAreaContext()) }
            group.addTask { (4, CorrectionMemory.buildPromptContext(pkmRoot: root)) }

            var results = Array(repeating: "", count: 5)
            for await (index, value) in group {
                results[index] = value
            }
            return results
        }
        let projectContext = contexts[0]
        let subfolderContext = contexts[1]
        let projectNames = contextBuilder.extractProjectNames(from: projectContext)
        let weightedContext = contextBuilder.buildWeightedContext()
        let tagVocabulary = contexts[2]
        let areaContext = contexts[3]
        let correctionContext = contexts[4]

        onProgress?(0.08, L10n.Processing.loadingProjectContext)
        onProgress?(0.1, L10n.Processing.projectContextLoaded)

        // Extract content from all files — parallel using TaskGroup
        onPhaseChange?(.extracting)
        onProgress?(0.1, L10n.Processing.extractingContents(0, files.count))
        let inputs: [ClassifyInput] = await withTaskGroup(
            of: ClassifyInput.self,
            returning: [ClassifyInput].self
        ) { group in
            var collected: [ClassifyInput] = []
            collected.reserveCapacity(files.count)
            var activeTasks = 0
            var completedExtractions = 0
            let maxConcurrent = 5

            func reportExtractionProgress() {
                let total = max(files.count, 1)
                let progress = 0.1 + (Double(completedExtractions) / Double(total) * 0.2)
                onProgress?(progress, L10n.Processing.extractingContents(completedExtractions, files.count))
            }

            for filePath in files {
                if activeTasks >= maxConcurrent {
                    if let result = await group.next() {
                        collected.append(result)
                        completedExtractions += 1
                        reportExtractionProgress()
                    }
                    activeTasks -= 1
                }
                group.addTask {
                    let content = self.extractContent(from: filePath)
                    let fileName = (filePath as NSString).lastPathComponent
                    let preview = FileContentExtractor.extractPreview(from: filePath, content: content)
                    return ClassifyInput(
                        filePath: filePath,
                        content: content,
                        fileName: fileName,
                        preview: preview
                    )
                }
                activeTasks += 1
            }

            for await input in group {
                collected.append(input)
                completedExtractions += 1
                reportExtractionProgress()
            }

            // Preserve original file order for stable classification
            let fileIndex = Dictionary(uniqueKeysWithValues: files.enumerated().map { ($1, $0) })
            return collected.sorted { a, b in
                (fileIndex[a.filePath] ?? Int.max) < (fileIndex[b.filePath] ?? Int.max)
            }
        }

        onProgress?(0.3, L10n.Processing.extractingContents(inputs.count, files.count))

        // Separate media files (image+video) from text files — media skips AI classification
        // Also separate files with existing para: frontmatter — they skip AI classification too
        let mediaExtensions = BinaryExtractor.imageExtensions.union(BinaryExtractor.videoExtensions)
        var mediaInputs: [ClassifyInput] = []
        var textInputs: [ClassifyInput] = []
        var preClassifiedInputs: [(input: ClassifyInput, para: PARACategory)] = []
        for input in inputs {
            let ext = URL(fileURLWithPath: input.filePath).pathExtension.lowercased()
            if mediaExtensions.contains(ext) {
                mediaInputs.append(input)
            } else if let existingPara = Self.extractParaFromContent(input.content) {
                preClassifiedInputs.append((input: input, para: existingPara))
            } else {
                textInputs.append(input)
            }
        }

        // Ensure pool is ready before classification
        if let warmUpTask {
            await warmUpTask.value
        }

        onProgress?(0.3, L10n.Processing.aiClassificationStarting)
        onPhaseChange?(.classifying)

        // Classify only text files with AI
        let classifier = Classifier()
        let textClassifications: [ClassifyResult]
        if textInputs.isEmpty {
            textClassifications = []
        } else {
            textClassifications = try await classifier.classifyFiles(
                textInputs,
                projectContext: projectContext,
                subfolderContext: subfolderContext,
                projectNames: projectNames,
                weightedContext: weightedContext,
                areaContext: areaContext,
                tagVocabulary: tagVocabulary,
                correctionContext: correctionContext,
                pkmRoot: pkmRoot,
                onProgress: { [onProgress] progress, status in
                    // Map classifier's 0-1 progress to our 0.3-0.7 range
                    let mappedProgress = 0.3 + progress * 0.4
                    onProgress?(mappedProgress, status)
                }
            )
        }

        // Media files get a default classification — route directly to _Assets
        let mediaClassifications = mediaInputs.map { _ in
            ClassifyResult(
                para: .resource,
                tags: [],
                summary: "",
                targetFolder: "",
                project: nil,
                confidence: 1.0,
                relatedNotes: []
            )
        }

        // Pre-classified files (existing para: frontmatter) — skip AI, confidence 1.0
        let preClassifiedResults = preClassifiedInputs.map { item in
            ClassifyResult(
                para: item.para,
                tags: [],
                summary: "",
                targetFolder: "",
                project: nil,
                confidence: 1.0,
                relatedNotes: []
            )
        }

        // Merge: media first, then pre-classified, then text (preserves pairing with inputs)
        let allInputs = mediaInputs + preClassifiedInputs.map(\.input) + textInputs
        let allClassifications = mediaClassifications + preClassifiedResults + textClassifications

        // Classifications ready for move (semantic linking happens post-move)
        onPhaseChange?(.linking)
        let enrichedClassifications = allClassifications
        onProgress?(0.7, L10n.Processing.preparingMove)

        // Move files
        onPhaseChange?(.processing)
        let mover = FileMover(pkmRoot: pkmRoot)
        var processed: [ProcessedFileResult] = []
        var needsConfirmation: [PendingConfirmation] = []
        var failed = 0

        for (i, (classification, input)) in zip(enrichedClassifications, allInputs).enumerated() {
            if Task.isCancelled { throw CancellationError() }
            let progress = 0.7 + Double(i) / Double(max(enrichedClassifications.count, 1)) * 0.25
            onProgress?(progress, L10n.Processing.movingFile(input.fileName))
            onFileProgress?(i, allInputs.count, input.fileName)

            // Low confidence: ask user
            if classification.confidence < 0.5 {
                needsConfirmation.append(PendingConfirmation(
                    fileName: input.fileName,
                    filePath: input.filePath,
                    content: String(input.content.prefix(500)),
                    options: generateOptions(for: classification, projectNames: projectNames)
                ))
                continue
            }

            // Unmatched project: AI thinks it's project work but no matching project exists
            if classification.para == .project && classification.project == nil {
                let suggestedName = classification.suggestedProject ?? ""
                needsConfirmation.append(PendingConfirmation(
                    fileName: input.fileName,
                    filePath: input.filePath,
                    content: String(input.content.prefix(500)),
                    options: generateUnmatchedProjectOptions(
                        for: classification,
                        projectNames: projectNames
                    ),
                    reason: .unmatchedProject,
                    suggestedProjectName: suggestedName
                ))
                continue
            }

            // Name conflict: same name exists at target with different content
            if !isDirectory(input.filePath),
               mover.wouldConflictWithExistingFile(fileName: input.fileName, classification: classification) {
                needsConfirmation.append(PendingConfirmation(
                    fileName: input.fileName,
                    filePath: input.filePath,
                    content: String(input.content.prefix(500)),
                    options: generateOptions(for: classification, projectNames: projectNames),
                    reason: .nameConflict
                ))
                continue
            }

            do {
                let result: ProcessedFileResult
                if isDirectory(input.filePath) {
                    result = try mover.moveFolder(at: input.filePath, with: classification)
                } else {
                    result = try await mover.moveFile(at: input.filePath, with: classification)
                }
                processed.append(result)
                let action: String
                if case .deduplicated = result.status {
                    action = "deduplicated"
                } else {
                    action = "classified"
                }
                StatisticsService.recordActivity(
                    fileName: input.fileName,
                    category: classification.para.rawValue,
                    action: action,
                    detail: "→ \(classification.targetFolder)"
                )
            } catch {
                processed.append(ProcessedFileResult(
                    fileName: input.fileName,
                    para: classification.para,
                    targetPath: "",
                    tags: classification.tags,
                    status: .error(Self.friendlyErrorMessage(error))
                ))
                StatisticsService.recordActivity(
                    fileName: input.fileName,
                    category: classification.para.rawValue,
                    action: "error",
                    detail: Self.friendlyErrorMessage(error)
                )
                failed += 1
            }
        }

        // Compute success list once and reuse
        let successes = processed.filter(\.isSuccess)

        // Update MOCs for affected folders
        onPhaseChange?(.finishing)
        let affectedFolders = Set(successes.compactMap { result -> String? in
            let dir = (result.targetPath as NSString).deletingLastPathComponent
            return dir.isEmpty ? nil : dir
        })
        if !affectedFolders.isEmpty {
            let indexGenerator = NoteIndexGenerator(pkmRoot: pkmRoot)
            await indexGenerator.updateForFolders(affectedFolders)
        }

        onFileProgress?(allInputs.count, allInputs.count, "")
        onProgress?(0.95, L10n.Processing.finalizingResults)

        return Result(
            processed: processed,
            needsConfirmation: needsConfirmation,
            affectedFolders: affectedFolders,
            total: files.count,
            failed: failed
        )
    }

    // MARK: - Error Messages

    /// Convert technical errors to user-friendly messages
    static func friendlyErrorMessage(_ error: Error) -> String {
        let desc = error.localizedDescription

        // API key / quota errors
        if error is ClaudeAPIError || error is GeminiAPIError {
            if desc.contains("API 키") || desc.contains("noAPIKey") {
                return "API 키를 확인해주세요. 설정에서 올바른 키를 입력하세요."
            }
            if desc.contains("usage limit") || desc.contains("exceeded your current quota") {
                return "API 월간 사용 한도에 도달했습니다. API 제공자 콘솔에서 한도를 확인해주세요."
            }
            if desc.contains("429") || desc.contains("rate") {
                return "API 요청 한도 초과. 잠시 후 다시 시도해주세요."
            }
            if desc.contains("credit") || desc.contains("balance") || desc.contains("400") {
                return "API 크레딧이 부족합니다. API 제공자 콘솔에서 잔액을 확인해주세요."
            }
            if desc.contains("401") || desc.contains("403") || desc.contains("authentication") {
                return "API 키가 유효하지 않습니다. 설정에서 확인해주세요."
            }
            if desc.contains("500") || desc.contains("502") || desc.contains("503") {
                return "AI 서비스 일시 장애. 잠시 후 다시 시도해주세요."
            }
        }

        // Network errors
        let nsError = error as NSError
        if nsError.domain == NSURLErrorDomain {
            switch nsError.code {
            case NSURLErrorNotConnectedToInternet, NSURLErrorNetworkConnectionLost:
                return "인터넷 연결을 확인해주세요."
            case NSURLErrorTimedOut:
                return "요청 시간이 초과되었습니다. 다시 시도해주세요."
            default:
                return "네트워크 오류가 발생했습니다. 연결을 확인해주세요."
            }
        }

        // File permission errors
        if nsError.domain == NSCocoaErrorDomain {
            if nsError.code == NSFileReadNoPermissionError || nsError.code == NSFileWriteNoPermissionError {
                return "파일 접근 권한이 필요합니다. 시스템 설정에서 권한을 확인해주세요."
            }
            if nsError.code == NSFileNoSuchFileError || nsError.code == NSFileReadNoSuchFileError {
                return "파일을 찾을 수 없습니다. 파일이 이동되거나 삭제되었을 수 있습니다."
            }
        }

        if error is CancellationError {
            return "작업이 취소되었습니다."
        }

        return "알 수 없는 오류가 발생했습니다. 앱을 재시작하거나 설정을 확인해주세요."
    }

    // MARK: - Private

    private func isDirectory(_ path: String) -> Bool {
        var isDir: ObjCBool = false
        FileManager.default.fileExists(atPath: path, isDirectory: &isDir)
        return isDir.boolValue
    }

    /// Extract text content from a file or folder
    private func extractContent(from filePath: String) -> String {
        if isDirectory(filePath) {
            return extractFolderContent(from: filePath)
        }
        return FileContentExtractor.extract(from: filePath)
    }

    /// Extract combined content from all files inside a folder
    /// Uses smart extraction per file instead of raw prefix truncation
    private func extractFolderContent(from dirPath: String) -> String {
        let folderName = (dirPath as NSString).lastPathComponent
        let scanner = InboxScanner(pkmRoot: pkmRoot)
        let files = scanner.filesInDirectory(at: dirPath)

        let perFileBudget = max(500, 5000 / max(files.count, 1))

        var content = "[폴더: \(folderName)] 포함 파일 \(files.count)개\n\n"
        for file in files {
            let name = (file as NSString).lastPathComponent
            let extracted = FileContentExtractor.extract(from: file, maxLength: perFileBudget)
            if extracted.hasPrefix("[읽기 실패") || extracted.hasPrefix("[바이너리") {
                content += "--- \(name) [바이너리] ---\n\n"
            } else {
                content += "--- \(name) ---\n"
                content += extracted + "\n\n"
            }
        }
        return String(content.prefix(5000))
    }

    /// Generate options for files classified as project but with no matching project
    private func generateUnmatchedProjectOptions(
        for base: ClassifyResult,
        projectNames: [String]
    ) -> [ClassifyResult] {
        var options: [ClassifyResult] = []

        // Option 1: Resource (safe fallback)
        options.append(ClassifyResult(
            para: .resource,
            tags: base.tags,
            summary: base.summary,
            targetFolder: base.targetFolder,
            project: nil,
            confidence: 0.7,
            relatedNotes: base.relatedNotes
        ))

        // Option 2: Area (ongoing responsibility)
        options.append(ClassifyResult(
            para: .area,
            tags: base.tags,
            summary: base.summary,
            targetFolder: base.targetFolder,
            project: nil,
            confidence: 0.6,
            relatedNotes: base.relatedNotes
        ))

        // Option 3: Archive (completed/inactive)
        options.append(ClassifyResult(
            para: .archive,
            tags: base.tags,
            summary: base.summary,
            targetFolder: base.suggestedProject ?? "",
            project: nil,
            confidence: 0.5,
            relatedNotes: base.relatedNotes
        ))

        return options
    }

    /// Generate alternative classification options for uncertain files
    private func generateOptions(for base: ClassifyResult, projectNames: [String]) -> [ClassifyResult] {
        var options: [ClassifyResult] = [base]

        // Add alternative PARA categories
        for category in PARACategory.allCases where category != base.para {
            options.append(ClassifyResult(
                para: category,
                tags: base.tags,
                summary: base.summary,
                targetFolder: base.targetFolder,
                project: category == .project ? projectNames.first : nil,
                confidence: 0.5,
                relatedNotes: base.relatedNotes
            ))
        }

        return options
    }

    /// Extract existing para: value from frontmatter content
    private static func extractParaFromContent(_ content: String) -> PARACategory? {
        Frontmatter.parse(markdown: content).frontmatter.para
    }

    /// Ensure note-index.json covers all existing PARA folders.
    /// Detects folders on disk that are missing from the index and runs incremental update.
    private static func ensureIndexFresh(pathManager: PKMPathManager) async -> NoteIndex? {
        let existingIndex = pathManager.loadNoteIndex()
        let indexedFolders: Set<String> = existingIndex.map { Set($0.folders.keys) } ?? []

        let fm = FileManager.default
        let categories: [(PARACategory, String)] = [
            (.project, pathManager.projectsPath),
            (.area, pathManager.areaPath),
            (.resource, pathManager.resourcePath),
            (.archive, pathManager.archivePath),
        ]

        var missingFolderPaths: Set<String> = []
        for (category, basePath) in categories {
            guard let entries = try? fm.contentsOfDirectory(atPath: basePath) else { continue }
            for entry in entries {
                guard !entry.hasPrefix("."), !entry.hasPrefix("_") else { continue }
                let folderPath = (basePath as NSString).appendingPathComponent(entry)
                var isDir: ObjCBool = false
                guard fm.fileExists(atPath: folderPath, isDirectory: &isDir), isDir.boolValue else { continue }
                let relKey = "\(category.folderName)/\(entry)"
                if !indexedFolders.contains(relKey) {
                    missingFolderPaths.insert(folderPath)
                }
            }
        }

        guard !missingFolderPaths.isEmpty else { return existingIndex }

        NSLog("[InboxProcessor] 인덱스 누락 폴더 %d개 갱신", missingFolderPaths.count)
        let generator = NoteIndexGenerator(pkmRoot: pathManager.root)
        await generator.updateForFolders(missingFolderPaths)
        return pathManager.loadNoteIndex()
    }
}
