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

            do {
                let result = try await mover.moveFile(at: input.filePath, with: classification)
                processed.append(result)
            } catch {
                processed.append(ProcessedFileResult(
                    fileName: input.fileName,
                    para: classification.para,
                    targetPath: "",
                    tags: classification.tags,
                    error: error.localizedDescription
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

    // MARK: - Private

    /// Extract text content from a file
    private func extractContent(from filePath: String) -> String {
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
