import Foundation
import SwiftUI

/// Central state management for the app
@MainActor
final class AppState: ObservableObject {
    static let shared = AppState()

    private static let codeExtensions: Set<String> = [
        "swift", "py", "js", "ts", "jsx", "tsx", "go", "rs", "java",
        "c", "cpp", "h", "hpp", "cs", "rb", "php", "kt", "scala",
        "m", "mm", "sh", "bash", "vue", "svelte",
    ]

    // MARK: - Published State

    enum Screen {
        case onboarding
        case inbox
        case processing
        case results
        case settings
        case dashboard
        case search
        case paraManage
        case vaultInspector    // replaces vaultReorganize
        case aiStatistics      // new

        var parent: Screen? {
            switch self {
            case .paraManage, .search, .vaultInspector, .aiStatistics:
                return .dashboard
            default:
                return nil
            }
        }

        var displayName: String {
            switch self {
            case .inbox: return "인박스"
            case .dashboard: return "대시보드"
            case .settings: return "설정"
            case .paraManage: return "폴더 관리"
            case .search: return "검색"
            case .vaultInspector: return "볼트 점검"
            case .aiStatistics: return "AI 통계"
            case .results: return "정리 결과"
            default: return ""
            }
        }
    }

    @Published var currentScreen: Screen = .inbox
    @Published var inboxFileCount: Int = 0
    @Published var isProcessing: Bool = false
    @Published var processingProgress: Double = 0
    @Published var processingStatus: String = ""
    @Published var processingCurrentFile: String = ""
    @Published var processingCompletedCount: Int = 0
    @Published var processingTotalCount: Int = 0
    @Published var processedResults: [ProcessedFileResult] = []
    @Published var pendingConfirmations: [PendingConfirmation] = []
    @Published var reorganizeCategory: PARACategory?
    @Published var reorganizeSubfolder: String?
    @Published var processingPhase: ProcessingPhase = .preparing
    @Published var processingOrigin: Screen = .inbox
    @Published var affectedFolders: Set<String> = []
    @Published var navigationId = UUID()
    @Published var paraManageInitialCategory: PARACategory?

    // MARK: - Background Task State

    @Published var backgroundTaskName: String?
    @Published var backgroundTaskPhase: String = ""
    @Published var backgroundTaskProgress: Double = 0
    @Published var backgroundTaskCompleted: Bool = false
    @Published var vaultCheckResult: VaultCheckResult?
    @Published var taskBlockedAlert: String?
    @Published var viewTaskActive: Bool = false
    private var backgroundTask: Task<Void, Never>?

    var isAnyTaskRunning: Bool {
        isProcessing || backgroundTaskName != nil || viewTaskActive
    }

    private var runningTaskDisplayName: String {
        if let bg = backgroundTaskName { return bg }
        if isProcessing { return "파일 처리" }
        if viewTaskActive { return "재분류" }
        return ""
    }

    // MARK: - Settings

    @Published var pkmRootPath: String {
        didSet {
            UserDefaults.standard.set(pkmRootPath, forKey: "pkmRootPath")
            inboxWatchdog?.stop()
            if UserDefaults.standard.bool(forKey: "onboardingCompleted") {
                setupWatchdog()
                StatisticsService.sharedPkmRoot = pkmRootPath
            }
        }
    }

    @Published var selectedProvider: AIProvider {
        didSet {
            UserDefaults.standard.set(selectedProvider.rawValue, forKey: "selectedProvider")
            updateAPIKeyStatus()
        }
    }

    @Published var hasAPIKey: Bool = false
    @Published var hasClaudeKey: Bool = false
    @Published var hasGeminiKey: Bool = false

    private var inboxWatchdog: InboxWatchdog?

    func updateAPIKeyStatus() {
        hasClaudeKey = KeychainService.getAPIKey() != nil
        hasGeminiKey = KeychainService.getGeminiAPIKey() != nil
        hasAPIKey = selectedProvider.hasAPIKey()
    }

    // MARK: - Menubar Icon

    /// Black text face expression for the menubar
    var menuBarFace: String {
        if backgroundTaskName != nil {
            return "·_·…"
        }
        switch currentScreen {
        case .onboarding:
            return "·‿·"
        case .inbox:
            return inboxFileCount > 0 ? "·_·!" : "·_·"
        case .processing:
            return "·_·…"
        case .results:
            let hasErrors = processedResults.contains(where: \.isError)
            let hasPending = !pendingConfirmations.isEmpty
            if hasErrors || hasPending { return "·_·;" }
            return "^‿^"
        case .settings:
            return "·_·"
        case .dashboard:
            return "·_·"
        case .search:
            return "·_·"
        case .paraManage:
            return "·_·"
        case .vaultInspector:
            return "·_·…"
        case .aiStatistics:
            return "·_·"
        }
    }

    // MARK: - Init

    private init() {
        self.pkmRootPath = UserDefaults.standard.string(forKey: "pkmRootPath")
            ?? (NSHomeDirectory() + "/Documents/DotBrain")

        // Load saved provider or default to Gemini (free tier available)
        if let savedProvider = UserDefaults.standard.string(forKey: "selectedProvider"),
           let provider = AIProvider(rawValue: savedProvider) {
            self.selectedProvider = provider
        } else {
            self.selectedProvider = .gemini
        }

        self.hasClaudeKey = KeychainService.getAPIKey() != nil
        self.hasGeminiKey = KeychainService.getGeminiAPIKey() != nil
        self.hasAPIKey = selectedProvider.hasAPIKey()

        if !UserDefaults.standard.bool(forKey: "onboardingCompleted") {
            self.currentScreen = .onboarding
        } else if !FileManager.default.fileExists(atPath: pkmRootPath) {
            // PKM folder was deleted — send user to settings to recreate
            self.currentScreen = .settings
        } else if !self.hasAPIKey {
            self.currentScreen = .settings
        }

        // Only start services if onboarding is already completed
        if UserDefaults.standard.bool(forKey: "onboardingCompleted") {
            AICompanionService.updateIfNeeded(pkmRoot: pkmRootPath)
            StatisticsService.sharedPkmRoot = pkmRootPath

            // One-time migration: consolidate scattered _Assets/ to central _Assets/{documents,images}/
            let migrationKey = "assetMigrationV1Completed"
            if !UserDefaults.standard.bool(forKey: migrationKey) {
                let root = pkmRootPath
                Task.detached(priority: .utility) {
                    guard AssetMigrator.needsMigration(pkmRoot: root) else {
                        await MainActor.run {
                            UserDefaults.standard.set(true, forKey: migrationKey)
                        }
                        return
                    }
                    let migrationResult = AssetMigrator.migrate(pkmRoot: root)
                    NSLog("[AppState] 에셋 마이그레이션: 문서 %d, 이미지 %d 이동", migrationResult.movedDocuments, migrationResult.movedImages)
                    await MainActor.run {
                        UserDefaults.standard.set(true, forKey: migrationKey)
                    }
                }
            }

            setupWatchdog()
        }
    }

    func startVaultCheck() {
        guard !isAnyTaskRunning else {
            taskBlockedAlert = "'\(runningTaskDisplayName)' 진행 중입니다. 완료 또는 취소 후 다시 시도해주세요."
            return
        }

        backgroundTaskName = "전체 점검"
        backgroundTaskPhase = "오류 검사 중..."
        backgroundTaskProgress = 0
        vaultCheckResult = nil
        let root = pkmRootPath

        backgroundTask = Task.detached(priority: .utility) {
            defer {
                Task { @MainActor in
                    // Show completion state briefly before clearing
                    AppState.shared.backgroundTaskPhase = "완료"
                    AppState.shared.backgroundTaskProgress = 1.0
                    AppState.shared.backgroundTaskCompleted = true
                    try? await Task.sleep(for: .seconds(3))
                    AppState.shared.backgroundTaskName = nil
                    AppState.shared.backgroundTaskPhase = ""
                    AppState.shared.backgroundTaskProgress = 0
                    AppState.shared.backgroundTaskCompleted = false
                }
            }

            var repairCount = 0
            var enrichCount = 0

            StatisticsService.recordActivity(
                fileName: "볼트 점검",
                category: "system",
                action: "started",
                detail: "오류 검사 · 메타데이터 보완 · MOC 갱신"
            )

            // Load content hash cache for incremental processing
            let cache = ContentHashCache(pkmRoot: root)
            await cache.load()

            // Phase 1: Audit (0% -> 10%)
            await MainActor.run { AppState.shared.backgroundTaskProgress = 0.02 }
            let auditor = VaultAuditor(pkmRoot: root)
            let report = auditor.audit()
            if Task.isCancelled { return }
            await MainActor.run { AppState.shared.backgroundTaskProgress = 0.10 }

            // Phase 2: Repair (10% -> 20%)
            var repairedFiles: [String] = []
            if report.totalIssues > 0 {
                await MainActor.run {
                    AppState.shared.backgroundTaskPhase = "자동 복구 중..."
                    AppState.shared.backgroundTaskProgress = 0.12
                }
                let repair = auditor.repair(report: report)
                repairCount = repair.linksFixed + repair.frontmatterInjected + repair.paraFixed

                repairedFiles = Self.collectRepairedFiles(from: report)
                await cache.updateHashes(repairedFiles)
            }
            if Task.isCancelled { return }
            await MainActor.run { AppState.shared.backgroundTaskProgress = 0.20 }

            // Check all .md files for changes (single batch actor call)
            await MainActor.run { AppState.shared.backgroundTaskPhase = "변경 파일 확인 중..." }
            let pm = PKMPathManager(root: root)
            let allMdFiles = Self.collectAllMdFiles(pm: pm)
            let fileStatuses = await cache.checkFiles(allMdFiles)
            let changedFiles = Set(fileStatuses.filter { $0.value != .unchanged }.map { $0.key })

            NSLog("[VaultCheck] %d/%d files changed", changedFiles.count, allMdFiles.count)

            // Phase 3: Enrich (changed files only, skip archive) (25% -> 60%)
            await MainActor.run {
                AppState.shared.backgroundTaskPhase = "메타데이터 보완 중..."
                AppState.shared.backgroundTaskProgress = 0.25
            }
            let enricher = NoteEnricher(pkmRoot: root)
            let filesToEnrich = Array(changedFiles.filter { !$0.contains("/4_Archive/") })
            var enrichedFiles: [String] = []
            let enrichTotal = filesToEnrich.count
            var enrichDone = 0

            await withTaskGroup(of: EnrichResult?.self) { group in
                var active = 0
                var index = 0

                while index < filesToEnrich.count || !group.isEmpty {
                    while active < 3 && index < filesToEnrich.count {
                        let path = filesToEnrich[index]
                        index += 1
                        active += 1
                        group.addTask {
                            do {
                                return try await enricher.enrichNote(at: path)
                            } catch {
                                NSLog("[NoteEnricher] enrichNote 실패 %@: %@",
                                      (path as NSString).lastPathComponent, error.localizedDescription)
                                return nil
                            }
                        }
                    }
                    if let result = await group.next() {
                        active -= 1
                        enrichDone += 1
                        if let r = result, r.fieldsUpdated > 0 {
                            enrichedFiles.append(r.filePath)
                            enrichCount += 1
                        }
                        let enrichProgress = enrichTotal > 0
                            ? 0.25 + Double(enrichDone) / Double(enrichTotal) * 0.35
                            : 0.60
                        await MainActor.run {
                            AppState.shared.backgroundTaskProgress = enrichProgress
                        }
                    }
                }
            }
            if !enrichedFiles.isEmpty {
                await cache.updateHashes(enrichedFiles)
            }
            if Task.isCancelled { return }

            // Phase 4: MOC (dirty folders only) (60% -> 70%)
            await MainActor.run {
                AppState.shared.backgroundTaskPhase = "폴더 요약 갱신 중..."
                AppState.shared.backgroundTaskProgress = 0.60
            }
            let allChangedFiles = changedFiles.union(Set(enrichedFiles))
            let dirtyFolders = Set(allChangedFiles.map {
                ($0 as NSString).deletingLastPathComponent
            })
            let generator = MOCGenerator(pkmRoot: root)
            await generator.regenerateAll(dirtyFolders: dirtyFolders)
            if Task.isCancelled { return }

            // Phase 5: Semantic Link (changed notes only) (70% -> 95%)
            await MainActor.run {
                AppState.shared.backgroundTaskPhase = "노트 간 시맨틱 연결 중..."
                AppState.shared.backgroundTaskProgress = 0.70
            }
            let linker = SemanticLinker(pkmRoot: root)
            let linkResult = await linker.linkAll(changedFiles: allChangedFiles) { progress, status in
                Task { @MainActor in
                    AppState.shared.backgroundTaskPhase = status
                    AppState.shared.backgroundTaskProgress = 0.70 + progress * 0.25
                }
            }

            // Update hashes for all changed files (including MOC/SemanticLinker modifications) and save
            await cache.updateHashes(Array(allChangedFiles))
            await cache.save()

            StatisticsService.recordActivity(
                fileName: "볼트 점검",
                category: "system",
                action: "completed",
                detail: "\(report.totalIssues)건 발견, \(repairCount)건 복구, \(enrichCount)개 보완, \(linkResult.linksCreated)개 링크"
            )

            let snapshot = VaultCheckResult(
                brokenLinks: report.brokenLinks.count,
                missingFrontmatter: report.missingFrontmatter.count,
                missingPARA: report.missingPARA.count,
                untaggedFiles: report.untaggedFiles.count,
                repairCount: repairCount,
                enrichCount: enrichCount,
                mocUpdated: true,
                linksCreated: linkResult.linksCreated
            )
            await MainActor.run {
                AppState.shared.vaultCheckResult = snapshot
            }
        }
    }

    /// Collect files that were actually modified by repair
    private nonisolated static func collectRepairedFiles(from report: AuditReport) -> [String] {
        var files = Set<String>()
        // Only include broken links where a suggestion existed (those were actually fixed)
        for link in report.brokenLinks where link.suggestion != nil {
            files.insert(link.filePath)
        }
        for path in report.missingFrontmatter {
            files.insert(path)
        }
        for path in report.missingPARA {
            files.insert(path)
        }
        return Array(files)
    }

    /// Collect all .md files across PARA folders
    private nonisolated static func collectAllMdFiles(pm: PKMPathManager) -> [String] {
        let fm = FileManager.default
        var results: [String] = []
        for basePath in [pm.projectsPath, pm.areaPath, pm.resourcePath, pm.archivePath] {
            guard let enumerator = fm.enumerator(atPath: basePath) else { continue }
            while let element = enumerator.nextObject() as? String {
                let name = (element as NSString).lastPathComponent
                if name.hasPrefix(".") || name.hasPrefix("_") {
                    let full = (basePath as NSString).appendingPathComponent(element)
                    var isDir: ObjCBool = false
                    if fm.fileExists(atPath: full, isDirectory: &isDir), isDir.boolValue {
                        enumerator.skipDescendants()
                    }
                    continue
                }
                guard name.hasSuffix(".md") else { continue }
                let fullPath = (basePath as NSString).appendingPathComponent(element)
                var isDir: ObjCBool = false
                if fm.fileExists(atPath: fullPath, isDirectory: &isDir), !isDir.boolValue {
                    results.append(fullPath)
                }
            }
        }
        return results
    }

    func cancelBackgroundTask() {
        backgroundTask?.cancel()
        backgroundTask = nil
        backgroundTaskName = nil
        backgroundTaskPhase = ""
        backgroundTaskProgress = 0
        backgroundTaskCompleted = false
    }

    // MARK: - Actions

    func setupWatchdog() {
        let inboxPath = PKMPathManager(root: pkmRootPath).inboxPath
        inboxWatchdog = InboxWatchdog(folderPath: inboxPath) { [weak self] in
            Task { @MainActor in
                guard let self = self, !self.isProcessing else { return }
                await self.refreshInboxCount()
            }
        }
        inboxWatchdog?.start()
    }

    func refreshInboxCount() async {
        let scanner = InboxScanner(pkmRoot: pkmRootPath)
        let files = scanner.scan()
        inboxFileCount = files.count
    }

    private var processingTask: Task<Void, Never>?

    func startProcessing() async {
        guard !isAnyTaskRunning else {
            if backgroundTaskName != nil || viewTaskActive {
                taskBlockedAlert = "'\(runningTaskDisplayName)' 진행 중입니다. 완료 또는 취소 후 다시 시도해주세요."
            }
            return
        }
        guard hasAPIKey else {
            currentScreen = .settings
            return
        }

        isProcessing = true
        processingProgress = 0
        processingStatus = "시작 중..."
        processingCurrentFile = ""
        processingCompletedCount = 0
        processingTotalCount = 0
        processedResults = []
        pendingConfirmations = []
        affectedFolders = []
        processingPhase = .preparing
        processingOrigin = .inbox
        currentScreen = .processing

        processingTask = Task { @MainActor in
            defer { isProcessing = false }
            let processor = InboxProcessor(
                pkmRoot: pkmRootPath,
                onProgress: { [weak self] progress, status in
                    Task { @MainActor in
                        self?.processingProgress = progress
                        self?.processingStatus = status
                    }
                },
                onFileProgress: { [weak self] completed, total, fileName in
                    Task { @MainActor in
                        self?.processingCompletedCount = completed
                        self?.processingTotalCount = total
                        self?.processingCurrentFile = fileName
                    }
                },
                onPhaseChange: { [weak self] phase in
                    Task { @MainActor in
                        self?.processingPhase = phase
                    }
                }
            )

            do {
                let results = try await processor.process()
                guard !Task.isCancelled else { return }
                processedResults = results.processed
                affectedFolders = results.affectedFolders
                pendingConfirmations = results.needsConfirmation
                currentScreen = .results
            } catch {
                if !Task.isCancelled {
                    processedResults = [ProcessedFileResult(
                        fileName: "처리 오류",
                        para: .archive,
                        targetPath: "",
                        tags: [],
                        status: .error(InboxProcessor.friendlyErrorMessage(error))
                    )]
                    currentScreen = .results
                }
            }

        }
    }

    func cancelProcessing() {
        processingTask?.cancel()
        processingTask = nil
        isProcessing = false
        processingProgress = 0
        processingStatus = ""
        processingCurrentFile = ""
        processingCompletedCount = 0
        processingTotalCount = 0
        processingPhase = .preparing
        currentScreen = processingOrigin == .paraManage ? .paraManage : .inbox
        Task {
            await refreshInboxCount()
        }
    }

    func startReorganizing() async {
        guard !isAnyTaskRunning else {
            if backgroundTaskName != nil || viewTaskActive {
                taskBlockedAlert = "'\(runningTaskDisplayName)' 진행 중입니다. 완료 또는 취소 후 다시 시도해주세요."
            }
            return
        }
        guard hasAPIKey else {
            currentScreen = .settings
            return
        }
        guard let category = reorganizeCategory, let subfolder = reorganizeSubfolder else { return }

        isProcessing = true
        processingProgress = 0
        processingStatus = "시작 중..."
        processingCurrentFile = ""
        processingCompletedCount = 0
        processingTotalCount = 0
        processedResults = []
        pendingConfirmations = []
        affectedFolders = []
        processingPhase = .preparing
        processingOrigin = .paraManage
        currentScreen = .processing

        processingTask = Task { @MainActor in
            defer { isProcessing = false }
            let reorganizer = FolderReorganizer(
                pkmRoot: pkmRootPath,
                category: category,
                subfolder: subfolder,
                onProgress: { [weak self] progress, status in
                    Task { @MainActor in
                        self?.processingProgress = progress
                        self?.processingStatus = status
                    }
                },
                onFileProgress: { [weak self] completed, total, fileName in
                    Task { @MainActor in
                        self?.processingCompletedCount = completed
                        self?.processingTotalCount = total
                        self?.processingCurrentFile = fileName
                    }
                },
                onPhaseChange: { [weak self] phase in
                    Task { @MainActor in
                        self?.processingPhase = phase
                    }
                }
            )

            do {
                let results = try await reorganizer.process()
                guard !Task.isCancelled else { return }
                processedResults = results.processed
                affectedFolders = Set(results.processed.filter(\.isSuccess).compactMap { result -> String? in
                    let dir = (result.targetPath as NSString).deletingLastPathComponent
                    return dir.isEmpty ? nil : dir
                })
                pendingConfirmations = results.needsConfirmation
                currentScreen = .results
            } catch {
                if !Task.isCancelled {
                    processedResults = [ProcessedFileResult(
                        fileName: "정리 오류",
                        para: reorganizeCategory ?? .archive,
                        targetPath: "",
                        tags: [],
                        status: .error(InboxProcessor.friendlyErrorMessage(error))
                    )]
                    currentScreen = .results
                }
            }
        }
    }

    /// Reorganize multiple folders sequentially
    func startBatchReorganizing(folders: [(category: PARACategory, subfolder: String)]) async {
        guard !isAnyTaskRunning, !folders.isEmpty else {
            if isAnyTaskRunning {
                taskBlockedAlert = "'\(runningTaskDisplayName)' 진행 중입니다. 완료 또는 취소 후 다시 시도해주세요."
            }
            return
        }
        guard hasAPIKey else {
            currentScreen = .settings
            return
        }

        isProcessing = true
        processingProgress = 0
        processingStatus = "시작 중..."
        processingCurrentFile = ""
        processingCompletedCount = 0
        processingTotalCount = 0
        processedResults = []
        pendingConfirmations = []
        affectedFolders = []
        processingOrigin = .paraManage
        currentScreen = .processing

        processingTask = Task { @MainActor in
            defer { isProcessing = false }
            var allProcessed: [ProcessedFileResult] = []
            var allConfirmations: [PendingConfirmation] = []
            var allAffected: Set<String> = []

            for (index, folder) in folders.enumerated() {
                guard !Task.isCancelled else { break }
                let folderProgress = Double(index) / Double(folders.count)

                processingStatus = "[\(index + 1)/\(folders.count)] \(folder.subfolder) 정리 중..."
                processingProgress = folderProgress

                let reorganizer = FolderReorganizer(
                    pkmRoot: pkmRootPath,
                    category: folder.category,
                    subfolder: folder.subfolder,
                    onProgress: { [weak self] progress, status in
                        Task { @MainActor in
                            let scaled = folderProgress + progress / Double(folders.count)
                            self?.processingProgress = scaled
                            self?.processingStatus = "[\(index + 1)/\(folders.count)] \(status)"
                        }
                    },
                    onFileProgress: { [weak self] completed, total, fileName in
                        Task { @MainActor in
                            self?.processingCompletedCount = completed
                            self?.processingTotalCount = total
                            self?.processingCurrentFile = fileName
                        }
                    },
                    onPhaseChange: { [weak self] phase in
                        Task { @MainActor in
                            self?.processingPhase = phase
                        }
                    }
                )

                do {
                    let results = try await reorganizer.process()
                    allProcessed.append(contentsOf: results.processed)
                    allConfirmations.append(contentsOf: results.needsConfirmation)
                    let affected = Set(results.processed.filter(\.isSuccess).compactMap { result -> String? in
                        let dir = (result.targetPath as NSString).deletingLastPathComponent
                        return dir.isEmpty ? nil : dir
                    })
                    allAffected.formUnion(affected)
                } catch {
                    if !Task.isCancelled {
                        allProcessed.append(ProcessedFileResult(
                            fileName: folder.subfolder,
                            para: folder.category,
                            targetPath: "",
                            tags: [],
                            status: .error(InboxProcessor.friendlyErrorMessage(error))
                        ))
                    }
                }
            }

            guard !Task.isCancelled else {
                currentScreen = processingOrigin == .paraManage ? .paraManage : .inbox
                return
            }

            processedResults = allProcessed
            pendingConfirmations = allConfirmations
            affectedFolders = allAffected
            currentScreen = .results
        }
    }

    /// Skip a pending confirmation — file stays where it is
    func skipConfirmation(_ confirmation: PendingConfirmation) {
        pendingConfirmations.removeAll { $0.id == confirmation.id }
        let message = confirmation.reason == .misclassified
            ? "건너뜀 — 현재 위치 유지"
            : "건너뜀 — 인박스에 유지"
        processedResults.append(ProcessedFileResult(
            fileName: confirmation.fileName,
            para: .archive,
            targetPath: confirmation.filePath,
            tags: [],
            status: .skipped(message)
        ))
        checkConfirmationsComplete()
    }

    /// Delete a pending file — move to macOS Trash
    func deleteConfirmation(_ confirmation: PendingConfirmation) {
        pendingConfirmations.removeAll { $0.id == confirmation.id }
        do {
            let fileURL = URL(fileURLWithPath: confirmation.filePath)
            try FileManager.default.trashItem(at: fileURL, resultingItemURL: nil)
            processedResults.append(ProcessedFileResult(
                fileName: confirmation.fileName,
                para: .archive,
                targetPath: "",
                tags: [],
                status: .deleted
            ))
        } catch {
            processedResults.append(ProcessedFileResult(
                fileName: confirmation.fileName,
                para: .archive,
                targetPath: "",
                tags: [],
                status: .error(InboxProcessor.friendlyErrorMessage(error))
            ))
        }
        checkConfirmationsComplete()
    }

    func confirmClassification(_ confirmation: PendingConfirmation, choice: ClassifyResult) async {
        pendingConfirmations.removeAll { $0.id == confirmation.id }

        let mover = FileMover(pkmRoot: pkmRootPath)
        do {
            let result = try await mover.moveFile(
                at: confirmation.filePath,
                with: choice
            )
            processedResults.append(result)
        } catch {
            processedResults.append(ProcessedFileResult(
                fileName: confirmation.fileName,
                para: choice.para,
                targetPath: "",
                tags: choice.tags,
                status: .error(error.localizedDescription)
            ))
        }
        checkConfirmationsComplete()
    }

    /// Create a new project and move the file into it
    func createProjectAndClassify(_ confirmation: PendingConfirmation, projectName: String) async {
        pendingConfirmations.removeAll { $0.id == confirmation.id }

        let pm = ProjectManager(pkmRoot: pkmRootPath)
        do {
            let _ = try pm.createProject(name: projectName)

            // Build classification pointing to new project
            let base = confirmation.options.first ?? ClassifyResult(
                para: .project, tags: [], summary: "", targetFolder: "",
                project: projectName, confidence: 1.0
            )
            let classification = ClassifyResult(
                para: .project,
                tags: base.tags,
                summary: base.summary,
                targetFolder: "",
                project: projectName,
                confidence: 1.0,
                relatedNotes: base.relatedNotes
            )

            let mover = FileMover(pkmRoot: pkmRootPath)
            let result = try await mover.moveFile(at: confirmation.filePath, with: classification)
            processedResults.append(result)
        } catch {
            processedResults.append(ProcessedFileResult(
                fileName: confirmation.fileName,
                para: .project,
                targetPath: "",
                tags: [],
                status: .error(InboxProcessor.friendlyErrorMessage(error))
            ))
        }
        checkConfirmationsComplete()
    }

    /// Copy files into _Inbox/ folder, return (added count, skipped code files)
    struct AddFilesResult {
        let added: Int
        let failedFiles: [String]
        let skippedCode: [String]
    }

    func addFilesToInboxDetailed(urls: [URL]) async -> AddFilesResult {
        let fm = FileManager.default
        let inboxPath = PKMPathManager(root: pkmRootPath).inboxPath

        // Ensure _Inbox/ exists
        try? fm.createDirectory(atPath: inboxPath, withIntermediateDirectories: true)

        var added = 0
        var failedFiles: [String] = []
        var skippedCode: [String] = []
        for url in urls {
            let fileName = url.lastPathComponent

            // Skip code project folders
            var isDir: ObjCBool = false
            if fm.fileExists(atPath: url.path, isDirectory: &isDir), isDir.boolValue {
                if InboxScanner.isCodeProject(at: url.path, fm: fm) {
                    skippedCode.append(fileName)
                    continue
                }
            }

            // Skip code/dev files by extension
            let ext = (fileName as NSString).pathExtension.lowercased()
            if Self.codeExtensions.contains(ext) {
                skippedCode.append(fileName)
                continue
            }

            var destPath = (inboxPath as NSString).appendingPathComponent(fileName)

            // Conflict resolution
            if fm.fileExists(atPath: destPath) {
                let base = (fileName as NSString).deletingPathExtension
                var counter = 2
                repeat {
                    let newName = ext.isEmpty ? "\(base)_\(counter)" : "\(base)_\(counter).\(ext)"
                    destPath = (inboxPath as NSString).appendingPathComponent(newName)
                    counter += 1
                } while fm.fileExists(atPath: destPath)
            }

            do {
                // Security-scoped resource access for sandboxed / drag-drop files
                let accessing = url.startAccessingSecurityScopedResource()
                defer { if accessing { url.stopAccessingSecurityScopedResource() } }

                try fm.copyItem(atPath: url.path, toPath: destPath)
                added += 1
            } catch {
                failedFiles.append(fileName)
                NSLog("[AppState] 파일 복사 실패 %@: %@", fileName, error.localizedDescription)
            }
        }

        await refreshInboxCount()
        return AddFilesResult(added: added, failedFiles: failedFiles, skippedCode: skippedCode)
    }

    func resetToInbox() {
        currentScreen = .inbox
        processedResults = []
        pendingConfirmations = []
        affectedFolders = []
        reorganizeCategory = nil
        reorganizeSubfolder = nil
        Task {
            await refreshInboxCount()
        }
    }

    func navigateBack() {
        if currentScreen == .results {
            if processingOrigin == .paraManage {
                currentScreen = .paraManage
            } else if processingOrigin == .vaultInspector {
                currentScreen = .vaultInspector
            } else {
                currentScreen = .inbox
            }
        } else if let parent = currentScreen.parent {
            currentScreen = parent
        } else {
            currentScreen = .inbox
        }
        processedResults = []
        pendingConfirmations = []
        affectedFolders = []
        navigationId = UUID()
        if currentScreen == .inbox {
            reorganizeCategory = nil
            reorganizeSubfolder = nil
            Task {
                await refreshInboxCount()
            }
        }
    }

    /// Navigate to PARAManageView with a specific folder's category pre-selected
    func navigateToReorganizeFolder(_ folderPath: String) {
        let pathManager = PKMPathManager(root: pkmRootPath)
        let resolvedFolder = URL(fileURLWithPath: folderPath).resolvingSymlinksInPath().path
        for category in PARACategory.allCases {
            let basePath = pathManager.paraPath(for: category)
            let resolvedBase = URL(fileURLWithPath: basePath).resolvingSymlinksInPath().path
            let resolvedBaseDir = resolvedBase.hasSuffix("/") ? resolvedBase : resolvedBase + "/"
            guard resolvedFolder.hasPrefix(resolvedBaseDir) || resolvedFolder == resolvedBase else { continue }
            let relative = String(resolvedFolder.dropFirst(resolvedBase.count))
                .trimmingCharacters(in: CharacterSet(charactersIn: "/"))
            let subfolder = relative.components(separatedBy: "/").first ?? ""
            guard !subfolder.isEmpty else { continue }
            reorganizeCategory = category
            reorganizeSubfolder = subfolder
            processedResults = []
            pendingConfirmations = []
            affectedFolders = []
            paraManageInitialCategory = category
            currentScreen = .paraManage
            return
        }
    }

    private var isAutoNavigating = false
    private var autoNavigateTask: Task<Void, Never>?

    private func checkConfirmationsComplete() {
        guard pendingConfirmations.isEmpty else { return }
        guard !isAutoNavigating else { return }
        isAutoNavigating = true

        // Cancel any previous auto-navigate task
        autoNavigateTask?.cancel()
        autoNavigateTask = Task { @MainActor in
            defer { isAutoNavigating = false }
            try? await Task.sleep(nanoseconds: 1_500_000_000)
            guard !Task.isCancelled else { return }
            guard pendingConfirmations.isEmpty else { return }
            navigateBack()
        }
    }
}

struct VaultCheckResult {
    let brokenLinks: Int
    let missingFrontmatter: Int
    let missingPARA: Int
    let untaggedFiles: Int
    let repairCount: Int
    let enrichCount: Int
    let mocUpdated: Bool
    let linksCreated: Int

    var auditTotal: Int {
        brokenLinks + missingFrontmatter + missingPARA
    }
}
