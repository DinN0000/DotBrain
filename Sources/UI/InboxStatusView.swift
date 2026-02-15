import SwiftUI
import UniformTypeIdentifiers

struct InboxStatusView: View {
    @EnvironmentObject var appState: AppState
    @State private var isDragOver = false
    @State private var dropFeedback: String?
    @State private var bounceAnimation = false
    @State private var isButtonHovered = false

    var body: some View {
        VStack(spacing: 16) {
            Spacer()

            if appState.inboxFileCount == 0 && !isDragOver {
                emptyStateView
            } else {
                activeStateView
            }

            Spacer()

            HoverTextLink(label: "폴더 정리", color: .secondary) {
                appState.currentScreen = .reorganize
            }

            // PKM path info
            HStack {
                Image(systemName: "folder")
                    .foregroundColor(.secondary)
                Text(appState.pkmRootPath)
                    .font(.caption2)
                    .foregroundColor(.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }
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
        .background(PasteCommandView {
            handlePaste()
        })
        .onAppear {
            Task {
                await appState.refreshInboxCount()
            }
            withAnimation(.easeInOut(duration: 2.0).repeatForever(autoreverses: true)) {
                bounceAnimation = true
            }
        }
    }

    // MARK: - Empty State

    private var emptyStateView: some View {
        VStack(spacing: 12) {
            Image(systemName: "tray.and.arrow.down.fill")
                .font(.system(size: 48))
                .foregroundColor(.secondary.opacity(0.5))
                .offset(y: bounceAnimation ? -3 : 3)

            Text("인박스")
                .font(.title2)
                .fontWeight(.semibold)

            Text("비어 있음")
                .font(.title3)
                .foregroundColor(.secondary)

            VStack(spacing: 4) {
                Text("파일을 여기에 끌어다 놓거나")
                    .font(.caption)
                    .foregroundColor(.secondary)
                HStack(spacing: 2) {
                    Image(systemName: "command")
                        .font(.caption2)
                    Text("V 로 붙여넣기")
                        .font(.caption)
                }
                .foregroundColor(.secondary)
            }
            .padding(.top, 4)
        }
    }

    // MARK: - Active State

    private var inboxFiles: [URL] {
        guard !appState.pkmRootPath.isEmpty else { return [] }
        let inboxPath = PKMPathManager(root: appState.pkmRootPath).inboxPath
        let fm = FileManager.default
        guard let items = try? fm.contentsOfDirectory(
            at: URL(fileURLWithPath: inboxPath),
            includingPropertiesForKeys: nil,
            options: [.skipsHiddenFiles]
        ) else { return [] }
        return items
            .filter { !$0.lastPathComponent.hasPrefix("_") }
            .sorted { $0.lastPathComponent < $1.lastPathComponent }
    }

    private var activeStateView: some View {
        VStack(spacing: 16) {
            Image(systemName: isDragOver ? "tray.and.arrow.down" : "tray.and.arrow.down.fill")
                .font(.system(size: 48))
                .foregroundColor(isDragOver ? .primary : .accentColor)
                .scaleEffect(isDragOver ? 1.2 : 1.0)
                .animation(.easeInOut(duration: 0.2), value: isDragOver)

            VStack(spacing: 4) {
                Text("인박스")
                    .font(.title2)
                    .fontWeight(.semibold)

                if let feedback = dropFeedback {
                    Text(feedback)
                        .font(.subheadline)
                        .foregroundColor(.green)
                        .transition(.opacity)
                }
            }

            if appState.inboxFileCount > 0 {
                VStack(spacing: 4) {
                    ForEach(Array(inboxFiles.prefix(5).enumerated()), id: \.offset) { _, url in
                        HStack(spacing: 8) {
                            FileThumbnailView(url: url)
                            Text(url.lastPathComponent)
                                .font(.caption)
                                .lineLimit(1)
                                .truncationMode(.middle)
                            Spacer()
                        }
                    }
                    if inboxFiles.count > 5 {
                        Text("외 \(inboxFiles.count - 5)개")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }
                .padding(.horizontal, 24)

                Text("\(appState.inboxFileCount)개 파일, 약 \(max(appState.inboxFileCount * 3, 1))초")
                    .font(.caption)
                    .foregroundColor(.secondary)

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

    // MARK: - Paste (Cmd+V)

    private func handlePaste() {
        let pasteboard = NSPasteboard.general
        var urls: [URL] = []

        if let fileURLs = pasteboard.readObjects(forClasses: [NSURL.self], options: [
            .urlReadingFileURLsOnly: true
        ]) as? [URL] {
            urls.append(contentsOf: fileURLs)
        }

        guard !urls.isEmpty else { return }

        Task {
            let result = await appState.addFilesToInboxDetailed(urls: urls)
            showDropFeedback(result)
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

// MARK: - Paste Command Helper

struct PasteCommandView: NSViewRepresentable {
    let onPaste: () -> Void

    func makeNSView(context: Context) -> PasteCapturingView {
        let view = PasteCapturingView()
        view.onPaste = onPaste
        return view
    }

    func updateNSView(_ nsView: PasteCapturingView, context: Context) {
        nsView.onPaste = onPaste
    }
}

class PasteCapturingView: NSView {
    var onPaste: (() -> Void)?

    override var acceptsFirstResponder: Bool { true }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        DispatchQueue.main.async { [weak self] in
            self?.window?.makeFirstResponder(self)
        }
    }

    override func keyDown(with event: NSEvent) {
        if event.modifierFlags.contains(.command) && event.charactersIgnoringModifiers == "v" {
            onPaste?()
        } else {
            super.keyDown(with: event)
        }
    }
}
