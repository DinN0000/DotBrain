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
        case reorganize
        case dashboard
        case search
        case projectManage
        case paraManage
        case vaultReorganize
    }

    @Published var currentScreen: Screen = .inbox
    @Published var inboxFileCount: Int = 0
    @Published var isProcessing: Bool = false
    @Published var processingProgress: Double = 0
    @Published var processingStatus: String = ""
    @Published var processedResults: [ProcessedFileResult] = []
    @Published var pendingConfirmations: [PendingConfirmation] = []
    @Published var reorganizeCategory: PARACategory?
    @Published var reorganizeSubfolder: String?
    @Published var processingOrigin: Screen = .inbox
    @Published var affectedFolders: Set<String> = []
    @Published var navigationId = UUID()

    // MARK: - Settings

    @Published var pkmRootPath: String {
        didSet {
            UserDefaults.standard.set(pkmRootPath, forKey: "pkmRootPath")
            inboxWatchdog?.stop()
            if UserDefaults.standard.bool(forKey: "onboardingCompleted") {
                setupWatchdog()
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
            return "·_·?"
        case .reorganize:
            return "·_·?"
        case .dashboard:
            return "·_·"
        case .search:
            return "·_·?"
        case .projectManage:
            return "·_·"
        case .paraManage:
            return "·_·"
        case .vaultReorganize:
            return "·_·…"
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
            setupWatchdog()
        }
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
        guard !isProcessing else { return }
        guard hasAPIKey else {
            currentScreen = .settings
            return
        }

        isProcessing = true
        processingProgress = 0
        processingStatus = "시작 중..."
        processedResults = []
        pendingConfirmations = []
        affectedFolders = []
        processingOrigin = .inbox
        currentScreen = .processing

        processingTask = Task { @MainActor in
            let processor = InboxProcessor(
                pkmRoot: pkmRootPath,
                onProgress: { [weak self] progress, status in
                    Task { @MainActor in
                        self?.processingProgress = progress
                        self?.processingStatus = status
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
                    processingStatus = "오류: \(InboxProcessor.friendlyErrorMessage(error))"
                }
            }

            isProcessing = false
        }
    }

    func cancelProcessing() {
        processingTask?.cancel()
        processingTask = nil
        isProcessing = false
        processingProgress = 0
        processingStatus = ""
        currentScreen = processingOrigin == .reorganize ? .reorganize
            : processingOrigin == .paraManage ? .paraManage : .inbox
        Task {
            await refreshInboxCount()
        }
    }

    func startReorganizing() async {
        guard !isProcessing else { return }
        guard hasAPIKey else {
            currentScreen = .settings
            return
        }
        guard let category = reorganizeCategory, let subfolder = reorganizeSubfolder else { return }

        isProcessing = true
        processingProgress = 0
        processingStatus = "시작 중..."
        processedResults = []
        pendingConfirmations = []
        affectedFolders = []
        processingOrigin = .reorganize
        currentScreen = .processing

        processingTask = Task { @MainActor in
            let reorganizer = FolderReorganizer(
                pkmRoot: pkmRootPath,
                category: category,
                subfolder: subfolder,
                onProgress: { [weak self] progress, status in
                    Task { @MainActor in
                        self?.processingProgress = progress
                        self?.processingStatus = status
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
                    processingStatus = "오류: \(InboxProcessor.friendlyErrorMessage(error))"
                }
            }

            isProcessing = false
        }
    }

    /// Reorganize multiple folders sequentially
    func startBatchReorganizing(folders: [(category: PARACategory, subfolder: String)]) async {
        guard !isProcessing, !folders.isEmpty else { return }
        guard hasAPIKey else {
            currentScreen = .settings
            return
        }

        isProcessing = true
        processingProgress = 0
        processingStatus = "시작 중..."
        processedResults = []
        pendingConfirmations = []
        affectedFolders = []
        processingOrigin = .reorganize
        currentScreen = .processing

        processingTask = Task { @MainActor in
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
                isProcessing = false
                return
            }

            processedResults = allProcessed
            pendingConfirmations = allConfirmations
            affectedFolders = allAffected
            currentScreen = .results
            isProcessing = false
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
                status: .error("삭제 실패: \(error.localizedDescription)")
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
                confidence: 1.0
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
                status: .error("프로젝트 생성 실패: \(error.localizedDescription)")
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

    func addFilesToInbox(urls: [URL]) async -> Int {
        let result = await addFilesToInboxDetailed(urls: urls)
        return result.added
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
        if processingOrigin == .paraManage, reorganizeCategory != nil, reorganizeSubfolder != nil {
            currentScreen = .paraManage
        } else if processingOrigin == .reorganize, reorganizeCategory != nil, reorganizeSubfolder != nil {
            currentScreen = .reorganize
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

    /// Navigate to ReorganizeView with a specific folder pre-selected
    func navigateToReorganizeFolder(_ folderPath: String) {
        let pathManager = PKMPathManager(root: pkmRootPath)
        let resolvedFolder = URL(fileURLWithPath: folderPath).resolvingSymlinksInPath().path
        for category in PARACategory.allCases {
            let basePath = pathManager.paraPath(for: category)
            let resolvedBase = URL(fileURLWithPath: basePath).resolvingSymlinksInPath().path
            guard resolvedFolder.hasPrefix(resolvedBase) else { continue }
            let relative = String(resolvedFolder.dropFirst(resolvedBase.count))
                .trimmingCharacters(in: CharacterSet(charactersIn: "/"))
            let subfolder = relative.components(separatedBy: "/").first ?? ""
            guard !subfolder.isEmpty else { continue }
            reorganizeCategory = category
            reorganizeSubfolder = subfolder
            processedResults = []
            pendingConfirmations = []
            affectedFolders = []
            currentScreen = .reorganize
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

// MARK: - Result Types

struct ProcessedFileResult: Identifiable {
    enum Status {
        case success
        case relocated(from: String)  // 폴더 정리에서 다른 위치로 자동 이동됨
        case skipped(String)
        case deleted
        case deduplicated(String)
        case error(String)
    }

    let id = UUID()
    let fileName: String
    let para: PARACategory
    let targetPath: String
    let tags: [String]
    var status: Status = .success

    var isSuccess: Bool {
        switch status {
        case .success, .relocated, .deduplicated: return true
        default: return false
        }
    }

    var isError: Bool {
        if case .error = status { return true }
        return false
    }

    var error: String? {
        if case .error(let message) = status { return message }
        return nil
    }

    var displayTarget: String {
        let url = URL(fileURLWithPath: targetPath)
        let components = url.pathComponents
        // Show last 2 meaningful components
        let meaningful = components.filter { $0 != "/" }
        if meaningful.count >= 2 {
            return meaningful.suffix(2).joined(separator: "/")
        }
        return meaningful.last ?? targetPath
    }
}

struct PendingConfirmation: Identifiable {
    enum Reason {
        case lowConfidence
        case indexNoteConflict
        case nameConflict
        case misclassified
        case unmatchedProject
    }

    let id = UUID()
    let fileName: String
    let filePath: String
    let content: String
    let options: [ClassifyResult]
    var reason: Reason = .lowConfidence
    var suggestedProjectName: String?
}
