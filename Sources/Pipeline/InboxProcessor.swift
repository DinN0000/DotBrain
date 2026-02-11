import Foundation

/// Orchestrates the full inbox processing pipeline
/// Scan → Extract → Classify → Move → Report
struct InboxProcessor {
    let pkmRoot: String
    let onProgress: ((Double, String) -> Void)?

    struct Result {
        var processed: [ProcessedFileResult]
        var needsConfirmation: [PendingConfirmation]
        var total: Int
        var failed: Int
    }

    func process() async throws -> Result {
        let scanner = InboxScanner(pkmRoot: pkmRoot)
        let files = scanner.scan()

        guard !files.isEmpty else {
            return Result(processed: [], needsConfirmation: [], total: 0, failed: 0)
        }

        onProgress?(0.05, "\(files.count)개 파일 발견")

        // Build context
        let contextBuilder = ProjectContextBuilder(pkmRoot: pkmRoot)
        let projectContext = contextBuilder.buildProjectContext()
        let subfolderContext = contextBuilder.buildSubfolderContext()
        let projectNames = contextBuilder.extractProjectNames(from: projectContext)

        onProgress?(0.1, "프로젝트 컨텍스트 로드 완료")

        // Extract content from all files
        var inputs: [ClassifyInput] = []
        for (i, filePath) in files.enumerated() {
            let progress = 0.1 + Double(i) / Double(files.count) * 0.2
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

        // Classify with 2-stage AI
        let classifier = Classifier()
        let classifications = try await classifier.classifyFiles(
            inputs,
            projectContext: projectContext,
            subfolderContext: subfolderContext,
            projectNames: projectNames,
            onProgress: { [onProgress] progress, status in
                // Map classifier's 0-1 progress to our 0.3-0.7 range
                let mappedProgress = 0.3 + progress * 0.4
                onProgress?(mappedProgress, status)
            }
        )

        // Move files
        let mover = FileMover(pkmRoot: pkmRoot)
        var processed: [ProcessedFileResult] = []
        var needsConfirmation: [PendingConfirmation] = []
        var failed = 0

        for (i, classification) in classifications.enumerated() {
            let progress = 0.7 + Double(i) / Double(classifications.count) * 0.25
            let input = inputs[i]
            onProgress?(progress, "\(input.fileName) 이동 중...")

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

            // Index note conflict: file name matches 폴더명.md — ask user instead of auto-renaming
            if mover.wouldConflictWithIndexNote(fileName: input.fileName, classification: classification) {
                needsConfirmation.append(PendingConfirmation(
                    fileName: input.fileName,
                    filePath: input.filePath,
                    content: String(input.content.prefix(500)),
                    options: generateOptions(for: classification, projectNames: projectNames),
                    reason: .indexNoteConflict
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
                StatisticsService.recordActivity(
                    fileName: input.fileName,
                    category: classification.para.rawValue,
                    action: "classified"
                )
            } catch {
                processed.append(ProcessedFileResult(
                    fileName: input.fileName,
                    para: classification.para,
                    targetPath: "",
                    tags: classification.tags,
                    status: .error(Self.friendlyErrorMessage(error))
                ))
                failed += 1
            }
        }

        onProgress?(0.95, "완료 정리 중...")

        // Send notification
        NotificationService.sendProcessingComplete(
            classified: processed.filter(\.isSuccess).count,
            total: files.count,
            failed: failed
        )

        onProgress?(1.0, "완료!")

        return Result(
            processed: processed,
            needsConfirmation: needsConfirmation,
            total: files.count,
            failed: failed
        )
    }

    // MARK: - Error Messages

    /// Convert technical errors to user-friendly messages
    static func friendlyErrorMessage(_ error: Error) -> String {
        let desc = error.localizedDescription

        // API key errors
        if error is ClaudeAPIError || error is GeminiAPIError {
            if desc.contains("API 키") || desc.contains("noAPIKey") {
                return "API 키를 확인해주세요. 설정에서 올바른 키를 입력하세요."
            }
            if desc.contains("429") || desc.contains("rate") {
                return "API 요청 한도 초과. 잠시 후 다시 시도해주세요."
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

        return desc
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

        if BinaryExtractor.isBinaryFile(filePath) {
            let result = BinaryExtractor.extract(at: filePath)
            return result.text ?? "[바이너리 파일: \(result.file?.name ?? "unknown")]"
        }

        // Text file
        if let content = try? String(contentsOfFile: filePath, encoding: .utf8) {
            return String(content.prefix(5000))
        }

        return "[읽기 실패: \((filePath as NSString).lastPathComponent)]"
    }

    /// Extract combined content from all files inside a folder
    private func extractFolderContent(from dirPath: String) -> String {
        let folderName = (dirPath as NSString).lastPathComponent
        let scanner = InboxScanner(pkmRoot: pkmRoot)
        let files = scanner.filesInDirectory(at: dirPath)

        var content = "[폴더: \(folderName)] 포함 파일 \(files.count)개\n\n"
        for file in files {
            let name = (file as NSString).lastPathComponent
            if let text = try? String(contentsOfFile: file, encoding: .utf8) {
                content += "--- \(name) ---\n"
                content += String(text.prefix(1500)) + "\n\n"
            } else {
                content += "--- \(name) [바이너리] ---\n\n"
            }
        }
        return String(content.prefix(5000))
    }

    /// Generate alternative classification options for uncertain files
    private func generateOptions(for base: ClassifyResult, projectNames: [String]) -> [ClassifyResult] {
        var options: [ClassifyResult] = [base]

        // Add alternative PARA categories
        for category in PARACategory.allCases where category != base.para {
            var alt = base
            alt.confidence = 0.5
            options.append(ClassifyResult(
                para: category,
                tags: base.tags,
                summary: base.summary,
                targetFolder: base.targetFolder,
                project: category == .project ? projectNames.first : nil,
                confidence: 0.5
            ))
        }

        return options
    }
}
