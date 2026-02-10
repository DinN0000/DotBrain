import Foundation
import SwiftUI

/// Central state management for the app
@MainActor
final class AppState: ObservableObject {
    static let shared = AppState()

    // MARK: - Published State

    enum Screen {
        case inbox
        case processing
        case results
        case settings
    }

    @Published var currentScreen: Screen = .inbox
    @Published var inboxFileCount: Int = 0
    @Published var isProcessing: Bool = false
    @Published var processingProgress: Double = 0
    @Published var processingStatus: String = ""
    @Published var processedResults: [ProcessedFileResult] = []
    @Published var pendingConfirmations: [PendingConfirmation] = []

    // MARK: - Settings

    @Published var pkmRootPath: String {
        didSet {
            UserDefaults.standard.set(pkmRootPath, forKey: "pkmRootPath")
        }
    }

    @Published var hasAPIKey: Bool = false

    // MARK: - Init

    private init() {
        self.pkmRootPath = UserDefaults.standard.string(forKey: "pkmRootPath")
            ?? (NSHomeDirectory() + "/Documents/AI-PKM")
        self.hasAPIKey = KeychainService.getAPIKey() != nil
        // Show settings on first launch if no API key
        if !self.hasAPIKey {
            self.currentScreen = .settings
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
                error: error.localizedDescription
            ))
        }
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
        Task {
            await refreshInboxCount()
        }
    }
}

// MARK: - Result Types

struct ProcessedFileResult: Identifiable {
    let id = UUID()
    let fileName: String
    let para: PARACategory
    let targetPath: String
    let tags: [String]
    var error: String?

    var isSuccess: Bool { error == nil }

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
    let id = UUID()
    let fileName: String
    let filePath: String
    let content: String
    let options: [ClassifyResult]
}
