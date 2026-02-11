import Foundation
import SwiftUI

/// Central state management for the app
@MainActor
final class AppState: ObservableObject {
    static let shared = AppState()

    // MARK: - Published State

    enum Screen {
        case onboarding
        case inbox
        case processing
        case results
        case settings
        case reorganize
    }

    @Published var currentScreen: Screen = .inbox
    @Published var inboxFileCount: Int = 0
    @Published var isProcessing: Bool = false
    @Published var processingProgress: Double = 0
    @Published var processingStatus: String = ""
    @Published var processedResults: [ProcessedFileResult] = []
    @Published var pendingConfirmations: [PendingConfirmation] = []
    @Published var showCoachMarks: Bool = false
    @Published var reorganizeCategory: PARACategory?
    @Published var reorganizeSubfolder: String?
    @Published var processingOrigin: Screen = .inbox

    // MARK: - Settings

    @Published var pkmRootPath: String {
        didSet {
            UserDefaults.standard.set(pkmRootPath, forKey: "pkmRootPath")
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
            return inboxFileCount > 0 ? "·_·!" : "-_-"
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
        }
    }

    // MARK: - Init

    private init() {
        self.pkmRootPath = UserDefaults.standard.string(forKey: "pkmRootPath")
            ?? (NSHomeDirectory() + "/Documents/AI-PKM")

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
        } else if !self.hasAPIKey {
            self.currentScreen = .settings
        }

        // Show coach marks on first inbox visit after onboarding
        if UserDefaults.standard.bool(forKey: "onboardingCompleted")
            && !UserDefaults.standard.bool(forKey: "hasSeenCoachMarks") {
            self.showCoachMarks = true
        }
    }

    // MARK: - Actions

    func refreshInboxCount() async {
        let scanner = InboxScanner(pkmRoot: pkmRootPath)
        let files = scanner.scan()
        inboxFileCount = files.count
    }

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
        processingOrigin = .inbox
        currentScreen = .processing

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
            processedResults = results.processed
            pendingConfirmations = results.needsConfirmation

            if pendingConfirmations.isEmpty {
                currentScreen = .results
            } else {
                currentScreen = .results
            }
        } catch {
            processingStatus = "오류: \(error.localizedDescription)"
        }

        isProcessing = false
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
        processingOrigin = .reorganize
        currentScreen = .processing

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
            processedResults = results.processed
            pendingConfirmations = results.needsConfirmation
            currentScreen = .results
        } catch {
            processingStatus = "오류: \(error.localizedDescription)"
        }

        isProcessing = false
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

    /// Delete a pending file entirely
    func deleteConfirmation(_ confirmation: PendingConfirmation) {
        pendingConfirmations.removeAll { $0.id == confirmation.id }
        try? FileManager.default.removeItem(atPath: confirmation.filePath)
        processedResults.append(ProcessedFileResult(
            fileName: confirmation.fileName,
            para: .archive,
            targetPath: "",
            tags: [],
            status: .deleted
        ))
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

    /// Copy files into _Inbox/ folder, return count of successfully added files
    func addFilesToInbox(urls: [URL]) async -> Int {
        let fm = FileManager.default
        let inboxPath = PKMPathManager(root: pkmRootPath).inboxPath

        // Ensure _Inbox/ exists
        try? fm.createDirectory(atPath: inboxPath, withIntermediateDirectories: true)

        var added = 0
        for url in urls {
            let fileName = url.lastPathComponent
            var destPath = (inboxPath as NSString).appendingPathComponent(fileName)

            // Conflict resolution
            if fm.fileExists(atPath: destPath) {
                let ext = (fileName as NSString).pathExtension
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
                // Skip files that fail to copy
            }
        }

        await refreshInboxCount()
        return added
    }

    func resetToInbox() {
        currentScreen = .inbox
        processedResults = []
        pendingConfirmations = []
        reorganizeCategory = nil
        reorganizeSubfolder = nil
        Task {
            await refreshInboxCount()
        }
    }

    func navigateBack() {
        if processingOrigin == .reorganize, reorganizeCategory != nil, reorganizeSubfolder != nil {
            currentScreen = .reorganize
        } else {
            currentScreen = .inbox
        }
        processedResults = []
        pendingConfirmations = []
        if currentScreen == .inbox {
            reorganizeCategory = nil
            reorganizeSubfolder = nil
            Task {
                await refreshInboxCount()
            }
        }
    }

    private var isAutoNavigating = false

    private func checkConfirmationsComplete() {
        guard pendingConfirmations.isEmpty else { return }
        guard !isAutoNavigating else { return }
        isAutoNavigating = true
        Task { @MainActor in
            try? await Task.sleep(nanoseconds: 1_500_000_000)
            guard pendingConfirmations.isEmpty else {
                isAutoNavigating = false
                return
            }
            navigateBack()
            isAutoNavigating = false
        }
    }
}

// MARK: - Result Types

struct ProcessedFileResult: Identifiable {
    enum Status {
        case success
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
        case .success, .deduplicated: return true
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
    }

    let id = UUID()
    let fileName: String
    let filePath: String
    let content: String
    let options: [ClassifyResult]
    var reason: Reason = .lowConfidence
}
