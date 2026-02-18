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

    var body: some View {
        VStack(spacing: 16) {
            Spacer()

            if appState.inboxFileCount == 0 && !isDragOver {
                emptyStateView
            } else {
                activeStateView
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
                .strokeBorder(isDragOver ? Color.primary.opacity(0.4) : Color.clear, lineWidth: 2)
                .padding(4)
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
    }

    // MARK: - Empty State

    private var emptyStateView: some View {
        VStack(spacing: 12) {
            Text("\u{00B7}_\u{00B7}")
                .font(.system(size: 32, design: .monospaced))
                .foregroundColor(.secondary)
                .offset(y: bounceAnimation ? -3 : 3)

            Text("인박스가 비어 있음")
                .font(.title3)
                .foregroundColor(.secondary)

            Text("파일을 여기에 끌어다 놓거나")
                .font(.caption)
                .foregroundColor(.secondary)
                .padding(.top, 4)

            Button(action: pickFilesForInbox) {
                HStack(spacing: 4) {
                    Image(systemName: "plus.circle")
                    Text("파일 선택")
                }
            }
            .buttonStyle(.bordered)
            .controlSize(.small)
        }
    }

    // MARK: - Active State

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

    private var activeStateView: some View {
        VStack(spacing: 16) {
            Text(isDragOver ? "\u{00B7}o\u{00B7}" : "\u{00B7}\u{203F}\u{00B7}")
                .font(.system(size: 32, design: .monospaced))
                .scaleEffect(isDragOver ? 1.15 : 1.0)
                .animation(.easeInOut(duration: 0.2), value: isDragOver)

            if let feedback = dropFeedback {
                Text(feedback)
                    .font(.subheadline)
                    .foregroundColor(.green)
                    .transition(.opacity)
            }

            if appState.inboxFileCount > 0 {
                VStack(spacing: 4) {
                    ForEach(Array(cachedInboxFiles.prefix(5).enumerated()), id: \.offset) { _, url in
                        HStack(spacing: 8) {
                            FileThumbnailView(url: url)
                            Text(url.lastPathComponent)
                                .font(.caption)
                                .lineLimit(1)
                                .truncationMode(.middle)
                            Spacer()
                        }
                    }
                    if cachedInboxFiles.count > 5 {
                        Text("외 \(cachedInboxFiles.count - 5)개")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }
                .padding(.horizontal, 24)

                HStack(spacing: 8) {
                    Text("\(appState.inboxFileCount)개 파일, 약 \(max(appState.inboxFileCount * 3, 1))초")
                        .font(.caption)
                        .foregroundColor(.secondary)

                    Button(action: pickFilesForInbox) {
                        Image(systemName: "plus.circle")
                            .font(.caption)
                    }
                    .buttonStyle(.plain)
                    .foregroundColor(.accentColor)
                    .accessibilityLabel("인박스 파일 추가")

                    Button(action: clearInbox) {
                        Image(systemName: "trash")
                            .font(.caption)
                    }
                    .buttonStyle(.plain)
                    .foregroundColor(.secondary)
                    .accessibilityLabel("인박스 비우기")
                }

                Button(action: {
                    Task {
                        await appState.startProcessing()
                    }
                }) {
                    HStack {
                        Image(systemName: "sparkles")
                        Text("정리하기")
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 2)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
                .padding(.horizontal, 40)
                .scaleEffect(isButtonHovered ? 1.03 : 1.0)
                .animation(.easeOut(duration: 0.12), value: isButtonHovered)
                .onHover { isButtonHovered = $0 }
                .disabled(!appState.hasAPIKey)

                if !appState.hasAPIKey {
                    Text("API 키를 먼저 설정하세요")
                        .font(.caption)
                        .foregroundColor(.orange)
                }
            }

            if isDragOver {
                Text("놓으면 인박스에 추가됩니다")
                    .font(.caption)
                    .foregroundColor(.primary.opacity(0.6))
                    .fontWeight(.medium)
            }
        }
    }

    // MARK: - PKM Root Picker

    private func pickNewPKMRoot() {
        let panel = NSOpenPanel()
        panel.title = "PKM 볼트 폴더 선택"
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = false
        panel.canCreateDirectories = true

        guard panel.runModal() == .OK, let url = panel.url else { return }
        let newPath = url.path

        appState.pkmRootPath = newPath

        // If folder lacks PARA structure, trigger re-onboarding (skip welcome)
        let pm = PKMPathManager(root: newPath)
        if !pm.isInitialized() {
            UserDefaults.standard.set(1, forKey: "onboardingStep")
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

        for url in items where !url.lastPathComponent.hasPrefix("_") {
            try? fm.trashItem(at: url, resultingItemURL: nil)
        }
        loadInboxFiles()
        Task { await appState.refreshInboxCount() }
        showFeedback("인박스 비움 (휴지통으로 이동)")
    }

    // MARK: - File Picker

    private func pickFilesForInbox() {
        let panel = NSOpenPanel()
        panel.title = "인박스에 추가할 파일 선택"
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
            parts.append("\(result.added)개 추가됨")
        }
        if !result.skippedCode.isEmpty {
            parts.append("코드 \(result.skippedCode.count)개 건너뜀")
        }
        if !result.failedFiles.isEmpty {
            parts.append("\(result.failedFiles.count)개 실패")
        }

        if parts.isEmpty {
            showFeedback("추가할 수 있는 파일이 없습니다")
        } else {
            showFeedback(parts.joined(separator: " · "))
        }
    }

    private func showFeedback(_ message: String) {
        withAnimation {
            dropFeedback = message
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
            withAnimation {
                dropFeedback = nil
            }
        }
    }
}
