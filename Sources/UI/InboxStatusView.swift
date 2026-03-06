import SwiftUI
import UniformTypeIdentifiers

struct InboxStatusView: View {
    @EnvironmentObject var appState: AppState
    @State private var isDragOver = false
    @State private var dropFeedback: String?
    @State private var bounceAnimation = false
    @State private var isButtonHovered = false
    @State private var isBounceAnimating = false
    @State private var cachedInboxFiles: [URL] = []
    @State private var showClearConfirmation = false

    private var hasFiles: Bool { appState.inboxFileCount > 0 }

    var body: some View {
        VStack(spacing: 0) {
            // --- Zone 1: Face (fixed position) ---
            Spacer()

            faceView(mouth: currentMouth)
                .offset(y: (!hasFiles && !isDragOver) ? (bounceAnimation ? -3 : 3) : 0)
                .scaleEffect(isDragOver ? 1.1 : 1.0)
                .animation(.easeInOut(duration: 0.2), value: isDragOver)
                .overlay(alignment: .topTrailing) {
                    if hasFiles && !isDragOver {
                        Text("\(appState.inboxFileCount)")
                            .font(.system(size: 11, weight: .medium, design: .rounded))
                            .foregroundColor(.secondary)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(Capsule().fill(Color.secondary.opacity(0.1)))
                            .offset(x: 20, y: -4)
                    }
                }

            // --- Zone 2: Content (fixed position between face and footer) ---
            Spacer()

            Group {
                if isDragOver {
                    dragContent
                } else if hasFiles {
                    fileContent
                } else {
                    emptyContent
                }
            }

            Spacer()

            // PKM path — click to change
            Button(action: pickNewPKMRoot) {
                HStack(spacing: 4) {
                    Image(systemName: "folder")
                        .font(.caption2)
                        .foregroundColor(.secondary)
                    Text(abbreviatePath(appState.pkmRootPath))
                        .font(.caption2)
                        .foregroundColor(.secondary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                    Image(systemName: "chevron.right")
                        .font(.system(size: 8))
                        .foregroundColor(.secondary.opacity(0.5))
                }
            }
            .buttonStyle(.plain)
            .padding(.horizontal)
        }
        .padding()
        .background(
            RoundedRectangle(cornerRadius: 8)
                .strokeBorder(
                    isDragOver ? Color.accentColor.opacity(0.4) : Color.clear,
                    style: StrokeStyle(lineWidth: 1.5, dash: isDragOver ? [6, 4] : [])
                )
                .background(
                    RoundedRectangle(cornerRadius: 8)
                        .fill(isDragOver ? Color.accentColor.opacity(0.03) : Color.clear)
                )
                .padding(4)
                .animation(.easeInOut(duration: 0.2), value: isDragOver)
        )
        .onDrop(of: [.fileURL], isTargeted: $isDragOver) { providers in
            handleDrop(providers)
            return true
        }
        .onAppear {
            loadInboxFiles()
            Task {
                await appState.refreshInboxCount()
            }
            isBounceAnimating = true
            withAnimation(.easeInOut(duration: 2.0).repeatForever(autoreverses: true)) {
                if isBounceAnimating { bounceAnimation = true }
            }
        }
        .onDisappear {
            isBounceAnimating = false
            bounceAnimation = false
        }
        .onChange(of: appState.pkmRootPath) { _ in
            loadInboxFiles()
        }
        .onChange(of: appState.inboxFileCount) { _ in
            loadInboxFiles()
        }
    }

    // MARK: - Shared

    private var currentMouth: String {
        if isDragOver { return "o" }
        if hasFiles { return "\u{203F}" }
        return "_"
    }

    private func faceView(mouth: String) -> some View {
        Text("\u{00B7}\(mouth)\u{00B7}")
            .font(.system(size: 48, design: .monospaced))
            .foregroundColor(.secondary)
    }

    private func loadInboxFiles() {
        guard !appState.pkmRootPath.isEmpty else {
            cachedInboxFiles = []
            return
        }
        let inboxPath = PKMPathManager(root: appState.pkmRootPath).inboxPath
        let fm = FileManager.default
        guard let items = try? fm.contentsOfDirectory(
            at: URL(fileURLWithPath: inboxPath),
            includingPropertiesForKeys: nil,
            options: [.skipsHiddenFiles]
        ) else {
            cachedInboxFiles = []
            return
        }
        cachedInboxFiles = items
            .filter { !$0.lastPathComponent.hasPrefix("_") }
            .sorted { $0.lastPathComponent < $1.lastPathComponent }
    }

    // MARK: - Content per state (Zone 2 only — face is in Zone 1)

    private var emptyContent: some View {
        VStack(spacing: 8) {
            Text(L10n.Inbox.empty)
                .font(.title3)
                .foregroundColor(.secondary)

            Text(L10n.Inbox.dragHint)
                .font(.caption)
                .foregroundColor(.secondary)

            Button(action: pickFilesForInbox) {
                HStack(spacing: 4) {
                    Image(systemName: "plus.circle")
                    Text(L10n.Inbox.selectFiles)
                }
            }
            .buttonStyle(.bordered)
            .controlSize(.small)
        }
    }

    private var dragContent: some View {
        Text(L10n.Inbox.dropToAdd)
            .font(.subheadline)
            .fontWeight(.medium)
            .foregroundColor(.primary.opacity(0.7))
    }

    private var fileContent: some View {
        VStack(spacing: 8) {
            // Feedback pill
            if let feedback = dropFeedback {
                Text(feedback)
                    .font(.caption)
                    .fontWeight(.medium)
                    .foregroundColor(.green)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 4)
                    .background(Capsule().fill(Color.green.opacity(0.1)))
                    .transition(.opacity.combined(with: .scale(scale: 0.9)))
            }

            // File rows
            ScrollView {
                VStack(spacing: 2) {
                    ForEach(Array(cachedInboxFiles.prefix(6).enumerated()), id: \.offset) { _, url in
                        fileRow(url: url)
                    }
                    if cachedInboxFiles.count > 6 {
                        Text(L10n.Inbox.moreFiles(cachedInboxFiles.count - 6))
                            .font(.caption2)
                            .foregroundColor(.secondary)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 4)
                    }
                }
            }
            .frame(maxHeight: 160)
            .padding(.horizontal, 12)

            // Action bar
            HStack(spacing: 12) {
                Text(L10n.Inbox.estimatedTime(max(appState.inboxFileCount * 3, 1)))
                    .font(.caption2)
                    .foregroundColor(.secondary)

                Spacer()

                Button(action: pickFilesForInbox) {
                    Image(systemName: "plus.circle")
                        .font(.system(size: 13))
                }
                .buttonStyle(.plain)
                .foregroundColor(.accentColor)
                .accessibilityLabel(L10n.Inbox.addLabel)

                Button(action: { showClearConfirmation = true }) {
                    Image(systemName: "trash")
                        .font(.system(size: 12))
                }
                .buttonStyle(.plain)
                .foregroundColor(.secondary)
                .accessibilityLabel(L10n.Inbox.clearLabel)
                .alert(L10n.Inbox.clearTitle, isPresented: $showClearConfirmation) {
                    Button(L10n.Inbox.clearButton, role: .destructive) { clearInbox() }
                    Button(L10n.Common.cancel, role: .cancel) {}
                } message: {
                    Text(L10n.Inbox.clearMessage(appState.inboxFileCount))
                }
            }
            .padding(.horizontal, 20)

            Button(action: {
                Task { await appState.startProcessing() }
            }) {
                HStack(spacing: 6) {
                    Image(systemName: "sparkles")
                        .font(.system(size: 12))
                    Text(L10n.Inbox.organize)
                        .fontWeight(.medium)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 6)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.regular)
            .padding(.horizontal, 24)
            .scaleEffect(isButtonHovered ? 1.02 : 1.0)
            .animation(.easeOut(duration: 0.1), value: isButtonHovered)
            .onHover { isButtonHovered = $0 }
            .disabled(!appState.hasAPIKey)

            if !appState.hasAPIKey {
                Text(L10n.Inbox.setApiKey)
                    .font(.caption2)
                    .foregroundColor(.orange)
            }
        }
    }

    private func fileRow(url: URL) -> some View {
        HStack(spacing: 8) {
            FileThumbnailView(url: url)
            Text(url.lastPathComponent)
                .font(.system(size: 12))
                .lineLimit(1)
                .truncationMode(.middle)
            Spacer()
            Text(fileSizeString(url))
                .font(.caption2)
                .foregroundColor(.secondary.opacity(0.6))
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 5)
        .background(
            RoundedRectangle(cornerRadius: 6)
                .fill(Color.primary.opacity(0.03))
        )
    }

    private func fileSizeString(_ url: URL) -> String {
        guard let attrs = try? FileManager.default.attributesOfItem(atPath: url.path),
              let size = attrs[.size] as? Int64 else { return "" }
        if size < 1024 { return "\(size)B" }
        if size < 1024 * 1024 { return "\(size / 1024)KB" }
        return String(format: "%.1fMB", Double(size) / 1_048_576)
    }

    // MARK: - PKM Root Picker

    private func pickNewPKMRoot() {
        let panel = NSOpenPanel()
        panel.title = L10n.Inbox.pickVaultTitle
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = false
        panel.canCreateDirectories = true

        guard panel.runModal() == .OK, let url = panel.url else { return }
        let resolved = url.resolvingSymlinksInPath()
        let newPath = resolved.path

        appState.pkmRootPath = newPath
        appState.saveVaultBookmark(url: resolved)

        // If folder lacks PARA structure, trigger re-onboarding (skip welcome)
        let pm = PKMPathManager(root: newPath)
        if !pm.isInitialized() {
            UserDefaults.standard.set(2, forKey: AppState.DefaultsKey.onboardingStep)
            appState.currentScreen = .onboarding
            return
        }

        loadInboxFiles()
        Task {
            await appState.refreshInboxCount()
        }
    }

    private func abbreviatePath(_ path: String) -> String {
        path.replacingOccurrences(of: NSHomeDirectory(), with: "~")
    }

    // MARK: - Inbox Actions

    private func clearInbox() {
        let inboxPath = PKMPathManager(root: appState.pkmRootPath).inboxPath
        let fm = FileManager.default
        guard let items = try? fm.contentsOfDirectory(
            at: URL(fileURLWithPath: inboxPath),
            includingPropertiesForKeys: nil,
            options: [.skipsHiddenFiles]
        ) else { return }

        var failed = 0
        for url in items where !url.lastPathComponent.hasPrefix("_") {
            do {
                try fm.trashItem(at: url, resultingItemURL: nil)
            } catch {
                failed += 1
            }
        }
        loadInboxFiles()
        Task { await appState.refreshInboxCount() }
        let message = failed > 0
            ? L10n.Inbox.clearFailed(failed)
            : L10n.Inbox.clearSuccess
        showFeedback(message)
    }

    // MARK: - File Picker

    private func pickFilesForInbox() {
        let panel = NSOpenPanel()
        panel.title = L10n.Inbox.pickFilesTitle
        panel.canChooseDirectories = false
        panel.canChooseFiles = true
        panel.allowsMultipleSelection = true

        guard panel.runModal() == .OK, !panel.urls.isEmpty else { return }
        Task {
            let result = await appState.addFilesToInboxDetailed(urls: panel.urls)
            showDropFeedback(result)
        }
    }

    // MARK: - Drag & Drop

    private func handleDrop(_ providers: [NSItemProvider]) {
        let lock = NSLock()
        var urls: [URL] = []
        let group = DispatchGroup()

        for provider in providers {
            guard provider.hasItemConformingToTypeIdentifier(UTType.fileURL.identifier) else { continue }
            group.enter()
            provider.loadItem(forTypeIdentifier: UTType.fileURL.identifier, options: nil) { item, _ in
                defer { group.leave() }
                if let data = item as? Data, let url = URL(dataRepresentation: data, relativeTo: nil) {
                    lock.withLock { urls.append(url) }
                }
            }
        }

        group.notify(queue: .main) {
            guard !urls.isEmpty else { return }
            Task {
                let result = await appState.addFilesToInboxDetailed(urls: urls)
                showDropFeedback(result)
            }
        }
    }

    private func showDropFeedback(_ result: AppState.AddFilesResult) {
        var parts: [String] = []

        if result.added > 0 {
            parts.append(L10n.Inbox.addedCount(result.added))
        }
        if !result.skippedCode.isEmpty {
            parts.append(L10n.Inbox.skippedCode(result.skippedCode.count))
        }
        if !result.failedFiles.isEmpty {
            parts.append(L10n.Inbox.failedCount(result.failedFiles.count))
        }

        if parts.isEmpty {
            showFeedback(L10n.Inbox.noAddableFiles)
        } else {
            showFeedback(parts.joined(separator: " · "))
        }
    }

    private func showFeedback(_ message: String) {
        withAnimation {
            dropFeedback = message
        }
        Task { @MainActor in
            try? await Task.sleep(for: .seconds(2))
            withAnimation {
                dropFeedback = nil
            }
        }
    }
}
