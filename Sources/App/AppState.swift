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
        case folderRelationExplorer

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
            case .folderRelationExplorer: return "폴더 짝 매칭"
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
    @Published var pipelineError: String?
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
        isProcessing || (backgroundTaskName != nil && !backgroundTaskCompleted) || viewTaskActive
    }

    private var runningTaskDisplayName: String {
        if let bg = backgroundTaskName { return bg }
        if isProcessing { return "파일 처리" }
        if viewTaskActive { return "재분류" }
        return ""
    }

    // MARK: - Reorg State (Vault Inspector)

    enum ReorgPhase {
        case idle, scanning, reviewPlan, executing, done
    }

    @Published var reorgPhase: ReorgPhase = .idle
    @Published var reorgScope: VaultReorganizer.Scope = .all
    @Published var reorgAnalyses: [VaultReorganizer.FileAnalysis] = []
    @Published var reorgResults: [ProcessedFileResult] = []
    @Published var reorgProgress: Double = 0
    @Published var reorgStatus: String = ""
    var reorgTask: Task<Void, Never>?

    func resetReorg() {
        reorgTask?.cancel()
        viewTaskActive = false
        reorgTask = nil
        reorgPhase = .idle
        reorgAnalyses = []
        reorgResults = []
        reorgProgress = 0
        reorgStatus = ""
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
    @Published var hasClaudeCLI: Bool = false

    private var inboxWatchdog: InboxWatchdog?
    private var securityScopedURL: URL?

    // MARK: - Vault Bookmark

    private static let vaultBookmarkKey = "vaultFolderBookmark"

    /// Save a URL bookmark for persistent vault folder access.
    /// Call after the user selects a folder via NSOpenPanel.
    func saveVaultBookmark(url: URL) {
        do {
            let bookmarkData = try url.bookmarkData(
                options: [],
                includingResourceValuesForKeys: nil,
                relativeTo: nil
            )
            UserDefaults.standard.set(bookmarkData, forKey: Self.vaultBookmarkKey)
        } catch {
            NSLog("[AppState] 북마크 저장 실패: %@", error.localizedDescription)
        }
    }

    /// Resolve the saved vault bookmark. Starts security-scoped access if available.
    private func resolveVaultBookmark() {
        guard let data = UserDefaults.standard.data(forKey: Self.vaultBookmarkKey) else { return }
        do {
            var isStale = false
            let url = try URL(
                resolvingBookmarkData: data,
                options: [],
                relativeTo: nil,
                bookmarkDataIsStale: &isStale
            )
            if isStale {
                saveVaultBookmark(url: url)
            }
            if url.startAccessingSecurityScopedResource() {
                securityScopedURL = url
            }
        } catch {
            NSLog("[AppState] 북마크 리졸브 실패: %@", error.localizedDescription)
        }
    }

    func updateAPIKeyStatus() {
        hasClaudeKey = KeychainService.getAPIKey() != nil
        hasGeminiKey = KeychainService.getGeminiAPIKey() != nil
        hasClaudeCLI = ClaudeCLIClient.isAvailable()
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
        case .folderRelationExplorer:
            return "·_·"
        }
    }

    // MARK: - Init

    private init() {
        self.pkmRootPath = UserDefaults.standard.string(forKey: "pkmRootPath")
            ?? (NSHomeDirectory() + "/Documents/DotBrain")

        // Load saved provider (migrate "Claude Code" → "Claude CLI")
        if let savedProvider = UserDefaults.standard.string(forKey: "selectedProvider") {
            if let provider = AIProvider(rawValue: savedProvider) {
                self.selectedProvider = provider
            } else if savedProvider == "Claude Code" {
                self.selectedProvider = .claudeCLI
                UserDefaults.standard.set(AIProvider.claudeCLI.rawValue, forKey: "selectedProvider")
            } else {
                self.selectedProvider = .claudeCLI
            }
        } else {
            self.selectedProvider = .claudeCLI
        }

        self.hasClaudeKey = KeychainService.getAPIKey() != nil
        self.hasGeminiKey = KeychainService.getGeminiAPIKey() != nil
        self.hasClaudeCLI = ClaudeCLIClient.isAvailable()
        self.hasAPIKey = selectedProvider.hasAPIKey()

        if !UserDefaults.standard.bool(forKey: "onboardingCompleted") {
            self.currentScreen = .onboarding
        } else if !FileManager.default.fileExists(atPath: pkmRootPath) {
            // PKM folder was deleted — send user to settings to recreate
            self.currentScreen = .settings
        } else if !self.hasAPIKey {
            self.currentScreen = .settings
        }

        // Resolve vault bookmark for persistent folder access
        resolveVaultBookmark()

        // Only start services if onboarding is already completed
        if UserDefaults.standard.bool(forKey: "onboardingCompleted") {
            AICompanionService.updateIfNeeded(pkmRoot: pkmRootPath)
            StatisticsService.sharedPkmRoot = pkmRootPath

            // One-time migration: rename _meta/ to .meta/ (hidden from Finder/Obsidian)
            let oldMeta = (pkmRootPath as NSString).appendingPathComponent("_meta")
            let newMeta = (pkmRootPath as NSString).appendingPathComponent(".meta")
            if FileManager.default.fileExists(atPath: oldMeta),
               !FileManager.default.fileExists(atPath: newMeta) {
                try? FileManager.default.moveItem(atPath: oldMeta, toPath: newMeta)
            }

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
        backgroundTaskPhase = "수동 정리 감지 중..."
        backgroundTaskProgress = 0
        backgroundTaskCompleted = false
        vaultCheckResult = nil

        let root = pkmRootPath
        let pipeline = VaultCheckPipeline(pkmRoot: root)
        backgroundTask = Task.detached(priority: .utility) {
            // Detect manual file moves before any DotBrain operations
            Self.detectManualMoves(pkmRoot: root)

            let result = await pipeline.run { progress in
                Task { @MainActor in
                    AppState.shared.backgroundTaskPhase = progress.phase
                    AppState.shared.backgroundTaskProgress = progress.fraction
                }
            }

            await MainActor.run {
                AppState.shared.vaultCheckResult = result
                AppState.shared.backgroundTaskName = nil
                AppState.shared.backgroundTaskPhase = ""
                AppState.shared.backgroundTaskProgress = 0
                AppState.shared.backgroundTaskCompleted = false
            }
        }
    }

    func cancelBackgroundTask() {
        backgroundTask?.cancel()
        backgroundTask = nil
        backgroundTaskName = nil
        backgroundTaskPhase = ""
        backgroundTaskProgress = 0
        backgroundTaskCompleted = false
    }

    /// Compare current vault file locations against note-index.json.
    /// Any file in a different para/folder than the index = user moved it manually.
    /// Called at vault check start, before DotBrain modifies anything.
    private nonisolated static func detectManualMoves(pkmRoot: String) {
        let indexPath = (pkmRoot as NSString).appendingPathComponent(".meta/note-index.json")
        guard let data = FileManager.default.contents(atPath: indexPath),
              let index = try? JSONDecoder().decode(NoteIndex.self, from: data) else { return }

        // Build filename -> old location map
        var oldLocations: [String: (para: String, folder: String, tags: [String])] = [:]
        for (_, entry) in index.notes {
            let name = (entry.path as NSString).lastPathComponent
            oldLocations[name] = (para: entry.para, folder: entry.folder, tags: entry.tags)
        }

        // Scan current vault files
        let fm = FileManager.default
        let pathManager = PKMPathManager(root: pkmRoot)
        let canonicalRoot = URL(fileURLWithPath: pkmRoot).resolvingSymlinksInPath().path
        let rootPrefix = canonicalRoot.hasSuffix("/") ? canonicalRoot : canonicalRoot + "/"
        var recorded = 0

        for category in PARACategory.allCases {
            let basePath = pathManager.paraPath(for: category)
            guard let folders = try? fm.contentsOfDirectory(atPath: basePath) else { continue }
            for folderName in folders {
                guard !folderName.hasPrefix("."), !folderName.hasPrefix("_") else { continue }
                let folderPath = (basePath as NSString).appendingPathComponent(folderName)
                var isDir: ObjCBool = false
                guard fm.fileExists(atPath: folderPath, isDirectory: &isDir), isDir.boolValue else { continue }

                let relFolder: String = {
                    let canonical = URL(fileURLWithPath: folderPath).resolvingSymlinksInPath().path
                    guard canonical.hasPrefix(rootPrefix) else { return folderPath }
                    return String(canonical.dropFirst(rootPrefix.count))
                }()

                guard let files = try? fm.contentsOfDirectory(atPath: folderPath) else { continue }
                for file in files {
                    guard file.hasSuffix(".md"), !file.hasPrefix("."), !file.hasPrefix("_"),
                          file != "\(folderName).md" else { continue }

                    guard let old = oldLocations[file],
                          old.para != category.rawValue || old.folder != relFolder else { continue }

                    // File was somewhere else in the index — user moved it
                    let filePath = (folderPath as NSString).appendingPathComponent(file)
                    let content = try? String(contentsOfFile: filePath, encoding: .utf8)
                    let tags = content.map { Frontmatter.parse(markdown: $0).0.tags } ?? old.tags

                    CorrectionMemory.record(CorrectionEntry(
                        date: Date(),
                        fileName: file,
                        aiPara: old.para,
                        userPara: category.rawValue,
                        aiProject: old.folder,
                        userProject: relFolder,
                        tags: tags,
                        action: "manual-move"
                    ), pkmRoot: pkmRoot)
                    recorded += 1
                }
            }
        }

        if recorded > 0 {
            NSLog("[AppState] Detected %d manual file moves", recorded)
        }
    }

    func clearBackgroundTaskCompletion() {
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

        // Pre-flight: verify vault folder is accessible
        let inboxPath = PKMPathManager(root: pkmRootPath).inboxPath
        if !FileManager.default.isReadableFile(atPath: inboxPath) {
            pipelineError = "인박스 폴더에 접근할 수 없습니다.\n\n" +
                "시스템 설정 > 개인정보 보호 및 보안 > 파일 및 폴더에서 DotBrain의 접근 권한을 확인하거나, " +
                "하단 경로를 클릭해 볼트 폴더를 다시 선택해주세요."
            currentScreen = .results
            return
        }

        isProcessing = true
        processingProgress = 0
        processingStatus = "시작 중..."
        processingCurrentFile = ""
        processingCompletedCount = 0
        processingTotalCount = 0
        processedResults = []
        pipelineError = nil
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
                    pipelineError = InboxProcessor.friendlyErrorMessage(error)
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

        // Record skip for learning
        let aiOption = confirmation.options.first
        CorrectionMemory.record(CorrectionEntry(
            date: Date(),
            fileName: confirmation.fileName,
            aiPara: aiOption?.para.rawValue ?? "",
            userPara: "",
            aiProject: aiOption?.project ?? confirmation.suggestedProjectName,
            userProject: nil,
            tags: aiOption?.tags ?? [],
            action: "skip"
        ), pkmRoot: pkmRootPath)

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

        // Record deletion for learning
        let aiOption = confirmation.options.first
        CorrectionMemory.record(CorrectionEntry(
            date: Date(),
            fileName: confirmation.fileName,
            aiPara: aiOption?.para.rawValue ?? "",
            userPara: "",
            aiProject: aiOption?.project ?? confirmation.suggestedProjectName,
            userProject: nil,
            tags: aiOption?.tags ?? [],
            action: "delete"
        ), pkmRoot: pkmRootPath)

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

        // Register project alias if user selected a project different from AI suggestion
        if let suggestedName = confirmation.suggestedProjectName,
           let chosenProject = choice.project {
            ProjectAliasRegistry.register(aiName: suggestedName, actualName: chosenProject, pkmRoot: pkmRootPath)
        }

        // Record correction for learning
        let aiOption = confirmation.options.first
        CorrectionMemory.record(CorrectionEntry(
            date: Date(),
            fileName: confirmation.fileName,
            aiPara: aiOption?.para.rawValue ?? "",
            userPara: choice.para.rawValue,
            aiProject: aiOption?.project ?? confirmation.suggestedProjectName,
            userProject: choice.project,
            tags: choice.tags,
            action: "confirm"
        ), pkmRoot: pkmRootPath)

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

        // Register alias if AI suggested a different name
        if let suggestedName = confirmation.suggestedProjectName {
            ProjectAliasRegistry.register(aiName: suggestedName, actualName: projectName, pkmRoot: pkmRootPath)
        }

        // Record correction for learning
        let aiOption = confirmation.options.first
        CorrectionMemory.record(CorrectionEntry(
            date: Date(),
            fileName: confirmation.fileName,
            aiPara: aiOption?.para.rawValue ?? "project",
            userPara: "project",
            aiProject: confirmation.suggestedProjectName,
            userProject: projectName,
            tags: aiOption?.tags ?? [],
            action: "create-project"
        ), pkmRoot: pkmRootPath)

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
            try? await Task.sleep(for: .seconds(1.5))
            guard !Task.isCancelled else { return }
            guard pendingConfirmations.isEmpty else { return }
            navigateBack()
        }
    }
}

struct VaultCheckResult: Equatable {
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

    static let empty = VaultCheckResult(
        brokenLinks: 0, missingFrontmatter: 0, missingPARA: 0, untaggedFiles: 0,
        repairCount: 0, enrichCount: 0, mocUpdated: false, linksCreated: 0
    )
}
