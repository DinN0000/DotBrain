import Foundation

/// Scans across PARA categories and generates a reorganization plan.
/// Phase 1 (scan) classifies files and compares current vs recommended location.
/// Phase 2 (execute) moves only user-approved files.
struct VaultReorganizer {
    let pkmRoot: String
    let scope: Scope
    let onProgress: ((Double, String) -> Void)?
    /// When set, only files in this set are processed (used for "바뀐 파일만 정리")
    var changedFilesOnly: Set<String>?

    private static let maxFilesPerScan = 200

    private var pathManager: PKMPathManager {
        PKMPathManager(root: pkmRoot)
    }

    enum Scope {
        case all
        case category(PARACategory)
        case folder(String)

        var categories: [PARACategory] {
            switch self {
            case .all: return PARACategory.allCases
            case .category(let cat): return [cat]
            case .folder: return PARACategory.allCases
            }
        }
    }

    /// A single file's current vs recommended classification
    struct FileAnalysis: Identifiable {
        let id = UUID()
        let filePath: String
        let fileName: String
        let currentCategory: PARACategory
        let currentFolder: String
        let recommended: ClassifyResult
        var isSelected: Bool = true

        var needsMove: Bool {
            recommended.para != currentCategory || recommended.targetFolder != currentFolder
        }
    }

    /// Result of scanning phase
    struct ScanResult {
        let files: [FileAnalysis]
        let totalScanned: Int
        let skippedCount: Int
    }

    // MARK: - Phase 1: Scan

    /// Scan and classify all files in scope, returning analyses for files that need moving.
    func scan() async throws -> ScanResult {
        StatisticsService.recordActivity(
            fileName: "전체 재정리",
            category: "system",
            action: "started",
            detail: "AI 위치 재분류 스캔"
        )

        // 0-0.1: Collect files
        onProgress?(0.0, "파일 수집 중...")
        let collected = collectFiles()

        guard !collected.isEmpty else {
            onProgress?(1.0, "완료!")
            StatisticsService.recordActivity(
                fileName: "전체 재정리",
                category: "system",
                action: "completed",
                detail: "0개 스캔"
            )
            return ScanResult(files: [], totalScanned: 0, skippedCount: 0)
        }

        let skippedCount = max(0, collected.count - Self.maxFilesPerScan)
        let filesToProcess = Array(collected.prefix(Self.maxFilesPerScan))

        onProgress?(0.1, "\(filesToProcess.count)개 파일 발견")

        // 0.1-0.2: Build project context
        onProgress?(0.1, "프로젝트 컨텍스트 로드 중...")
        let contextBuilder = ProjectContextBuilder(pkmRoot: pkmRoot)
        let projectContext = contextBuilder.buildProjectContext()
        let subfolderContext = contextBuilder.buildSubfolderContext()
        let projectNames = contextBuilder.extractProjectNames(from: projectContext)
        let weightedContext = contextBuilder.buildWeightedContext()
        let areaContext = contextBuilder.buildAreaContext()

        onProgress?(0.2, "프로젝트 컨텍스트 로드 완료")

        // 0.2-0.4: Extract content in parallel
        onProgress?(0.2, "파일 내용 추출 중...")
        let inputs: [ClassifyInput] = await withTaskGroup(
            of: ClassifyInput.self,
            returning: [ClassifyInput].self
        ) { group in
            var collected: [ClassifyInput] = []
            collected.reserveCapacity(filesToProcess.count)
            var activeTasks = 0
            let maxConcurrent = 5

            for entry in filesToProcess {
                if activeTasks >= maxConcurrent {
                    if let result = await group.next() {
                        collected.append(result)
                    }
                    activeTasks -= 1
                }
                group.addTask {
                    let content = self.extractContent(from: entry.filePath)
                    let fileName = (entry.filePath as NSString).lastPathComponent
                    let preview = FileContentExtractor.extractPreview(from: entry.filePath, content: content)
                    return ClassifyInput(
                        filePath: entry.filePath,
                        content: content,
                        fileName: fileName,
                        preview: preview
                    )
                }
                activeTasks += 1
            }

            for await input in group {
                collected.append(input)
            }

            // Preserve original order for stable classification
            let pathIndex = Dictionary(
                uniqueKeysWithValues: filesToProcess.enumerated().map { ($1.filePath, $0) }
            )
            return collected.sorted { a, b in
                (pathIndex[a.filePath] ?? Int.max) < (pathIndex[b.filePath] ?? Int.max)
            }
        }

        onProgress?(0.4, "\(inputs.count)개 파일 내용 추출 완료")

        // 0.4-0.9: Classify with AI
        onProgress?(0.4, "AI 분류 시작...")
        let classifier = Classifier()
        let classifications = try await classifier.classifyFiles(
            inputs,
            projectContext: projectContext,
            subfolderContext: subfolderContext,
            projectNames: projectNames,
            weightedContext: weightedContext,
            areaContext: areaContext,
            onProgress: { [onProgress] progress, status in
                let mapped = 0.4 + progress * 0.5
                onProgress?(mapped, status)
            }
        )

        // 0.9-1.0: Compare current vs recommended
        onProgress?(0.9, "분류 결과 비교 중...")
        var analyses: [FileAnalysis] = []

        for (index, (classification, entry)) in zip(classifications, filesToProcess).enumerated() {
            if Task.isCancelled { throw CancellationError() }

            // Never create new project folders — only allow moves to existing projects
            if classification.para == .project && classification.project == nil {
                continue
            }

            // For matched project files, use project name as targetFolder
            // so needsMove correctly reflects actual destination
            var adjusted = classification
            if classification.para == .project, let project = classification.project {
                adjusted.targetFolder = project
            }

            let analysis = FileAnalysis(
                filePath: entry.filePath,
                fileName: inputs[index].fileName,
                currentCategory: entry.category,
                currentFolder: entry.folder,
                recommended: adjusted
            )

            if analysis.needsMove {
                analyses.append(analysis)
            }
        }

        onProgress?(1.0, "스캔 완료! \(analyses.count)개 파일 이동 필요")

        StatisticsService.recordActivity(
            fileName: "전체 재정리",
            category: "system",
            action: "completed",
            detail: "\(filesToProcess.count)개 스캔, \(analyses.count)개 이동 필요"
        )

        return ScanResult(
            files: analyses,
            totalScanned: filesToProcess.count,
            skippedCount: skippedCount
        )
    }

    // MARK: - Phase 2: Execute

    /// Execute approved plan — move selected files to their recommended locations.
    func execute(plan: [FileAnalysis]) async throws -> [ProcessedFileResult] {
        let selected = plan.filter(\.isSelected)
        guard !selected.isEmpty else { return [] }

        let mover = FileMover(pkmRoot: pkmRoot)
        var results: [ProcessedFileResult] = []

        for (i, analysis) in selected.enumerated() {
            if Task.isCancelled { throw CancellationError() }
            let progress = Double(i) / Double(selected.count)
            onProgress?(progress, "\(analysis.fileName) 이동 중...")

            // Double-check: never create new project folders (should be filtered in scan already)
            if analysis.recommended.para == .project && analysis.recommended.project == nil {
                continue
            }

            let fromDisplay = "\(analysis.currentCategory.folderName)/\(analysis.currentFolder)"

            do {
                let result = try await mover.moveFile(at: analysis.filePath, with: analysis.recommended)
                results.append(ProcessedFileResult(
                    fileName: result.fileName,
                    para: result.para,
                    targetPath: result.targetPath,
                    tags: result.tags,
                    status: .relocated(from: fromDisplay)
                ))
                let action: String
                if case .deduplicated = result.status {
                    action = "deduplicated"
                } else {
                    action = "vault-reorganized"
                }
                StatisticsService.recordActivity(
                    fileName: analysis.fileName,
                    category: analysis.recommended.para.rawValue,
                    action: action,
                    detail: "\(fromDisplay) → \(analysis.recommended.para.rawValue)/\(analysis.recommended.targetFolder)"
                )
            } catch {
                results.append(ProcessedFileResult(
                    fileName: analysis.fileName,
                    para: analysis.recommended.para,
                    targetPath: "",
                    tags: analysis.recommended.tags,
                    status: .error(InboxProcessor.friendlyErrorMessage(error))
                ))
                StatisticsService.recordActivity(
                    fileName: analysis.fileName,
                    category: analysis.recommended.para.rawValue,
                    action: "error",
                    detail: InboxProcessor.friendlyErrorMessage(error)
                )
            }
        }

        // Update MOCs for affected folders (both source and target) after file moves
        var affectedFolders = Set(results.filter(\.isSuccess).compactMap { result -> String? in
            let dir = (result.targetPath as NSString).deletingLastPathComponent
            return dir.isEmpty ? nil : dir
        })
        // Include source folders so their MOCs drop moved-out files
        for analysis in selected {
            let sourceDir = (pathManager.paraPath(for: analysis.currentCategory) as NSString)
                .appendingPathComponent(analysis.currentFolder)
            affectedFolders.insert(sourceDir)
        }

        if !affectedFolders.isEmpty {
            onProgress?(0.93, "노트 인덱스 갱신 중...")
            let indexGenerator = NoteIndexGenerator(pkmRoot: pkmRoot)
            await indexGenerator.updateForFolders(affectedFolders)
        }

        // Semantic link: reconnect moved files with vault
        let successPaths = results.filter(\.isSuccess).map(\.targetPath)
        if !successPaths.isEmpty {
            onProgress?(0.97, "시맨틱 연결 중...")
            let linker = SemanticLinker(pkmRoot: pkmRoot)
            let _ = await linker.linkNotes(filePaths: successPaths)
        }

        let failedCount = results.filter { if case .error = $0.status { return true }; return false }.count
        NotificationService.sendProcessingComplete(
            classified: results.filter(\.isSuccess).count,
            total: selected.count,
            failed: failedCount
        )

        onProgress?(1.0, "완료!")
        return results
    }

    // MARK: - Private

    private struct CollectedFile {
        let filePath: String
        let category: PARACategory
        let folder: String
    }

    /// Collect files from all folders in scope.
    /// Scans each PARA category's subfolders, collecting non-hidden, non-underscore files.
    /// Skips index notes (folderName.md).
    private func collectFiles() -> [CollectedFile] {
        let fm = FileManager.default
        var results: [CollectedFile] = []

        // Handle folder scope: only scan the specified folder
        if case .folder(let folderPath) = scope {
            let folderName = (folderPath as NSString).lastPathComponent
            let category = PARACategory.fromPath(folderPath) ?? .resource
            let indexNoteName = "\(folderName).md"

            guard let entries = try? fm.contentsOfDirectory(atPath: folderPath) else { return [] }
            for entry in entries.sorted() {
                guard !entry.hasPrefix("."), !entry.hasPrefix("_") else { continue }
                guard entry != indexNoteName else { continue }
                let filePath = (folderPath as NSString).appendingPathComponent(entry)
                var fileIsDir: ObjCBool = false
                guard fm.fileExists(atPath: filePath, isDirectory: &fileIsDir),
                      !fileIsDir.boolValue else { continue }
                guard pathManager.isPathSafe(filePath) else { continue }
                if let filter = changedFilesOnly, !filter.contains(filePath) { continue }
                results.append(CollectedFile(filePath: filePath, category: category, folder: folderName))
            }
            return results
        }

        for category in scope.categories {
            let basePath = pathManager.paraPath(for: category)
            guard let folders = try? fm.contentsOfDirectory(atPath: basePath) else { continue }

            for folder in folders.sorted() {
                guard !folder.hasPrefix("."), !folder.hasPrefix("_") else { continue }

                let folderPath = (basePath as NSString).appendingPathComponent(folder)
                var isDir: ObjCBool = false
                guard fm.fileExists(atPath: folderPath, isDirectory: &isDir), isDir.boolValue else {
                    continue
                }

                let indexNoteName = "\(folder).md"
                guard let entries = try? fm.contentsOfDirectory(atPath: folderPath) else { continue }

                for entry in entries.sorted() {
                    guard !entry.hasPrefix("."), !entry.hasPrefix("_") else { continue }
                    guard entry != indexNoteName else { continue }

                    let filePath = (folderPath as NSString).appendingPathComponent(entry)
                    var fileIsDir: ObjCBool = false
                    guard fm.fileExists(atPath: filePath, isDirectory: &fileIsDir),
                          !fileIsDir.boolValue else { continue }
                    guard pathManager.isPathSafe(filePath) else { continue }
                    if let filter = changedFilesOnly, !filter.contains(filePath) { continue }

                    results.append(CollectedFile(
                        filePath: filePath,
                        category: category,
                        folder: folder
                    ))
                }
            }
        }

        return results
    }

    /// Extract text content from a file, handling binary files via BinaryExtractor.
    private func extractContent(from filePath: String) -> String {
        FileContentExtractor.extract(from: filePath)
    }
}
