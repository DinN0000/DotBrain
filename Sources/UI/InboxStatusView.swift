import SwiftUI
import UniformTypeIdentifiers

struct InboxStatusView: View {
    @EnvironmentObject var appState: AppState
    @State private var isDragOver = false
    @State private var dropFeedback: String?

    var body: some View {
        VStack(spacing: 16) {
            Spacer()

            // Inbox icon
            Image(systemName: isDragOver ? "tray.and.arrow.down" : "tray.and.arrow.down.fill")
                .font(.system(size: 48))
                .foregroundColor(isDragOver ? .green : .accentColor)
                .scaleEffect(isDragOver ? 1.2 : 1.0)
                .animation(.easeInOut(duration: 0.2), value: isDragOver)

            // File count
            VStack(spacing: 4) {
                Text("인박스")
                    .font(.title2)
                    .fontWeight(.semibold)

                if let feedback = dropFeedback {
                    Text(feedback)
                        .font(.subheadline)
                        .foregroundColor(.green)
                        .transition(.opacity)
                } else if appState.inboxFileCount > 0 {
                    Text("\(appState.inboxFileCount)개 파일")
                        .font(.title3)
                        .foregroundColor(.secondary)
                } else {
                    Text("비어 있음")
                        .font(.title3)
                        .foregroundColor(.secondary)
                }
            }

            // Action button
            if appState.inboxFileCount > 0 {
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
                    .padding(.vertical, 8)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
                .padding(.horizontal, 40)
                .disabled(!appState.hasAPIKey)

                if !appState.hasAPIKey {
                    Text("API 키를 먼저 설정하세요")
                        .font(.caption)
                        .foregroundColor(.orange)
                }
            }

            // Drop hint
            if appState.inboxFileCount == 0 && !isDragOver {
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
            }

            if isDragOver {
                Text("놓으면 인박스에 추가됩니다")
                    .font(.caption)
                    .foregroundColor(.green)
                    .fontWeight(.medium)
            }

            Spacer()

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
                .strokeBorder(isDragOver ? Color.green : Color.clear, lineWidth: 2)
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
        }
    }

    // MARK: - Drag & Drop

    private func handleDrop(_ providers: [NSItemProvider]) {
        var urls: [URL] = []
        let group = DispatchGroup()

        for provider in providers {
            guard provider.hasItemConformingToTypeIdentifier(UTType.fileURL.identifier) else { continue }
            group.enter()
            provider.loadItem(forTypeIdentifier: UTType.fileURL.identifier, options: nil) { item, _ in
                defer { group.leave() }
                if let data = item as? Data, let url = URL(dataRepresentation: data, relativeTo: nil) {
                    urls.append(url)
                }
            }
        }

        group.notify(queue: .main) {
            guard !urls.isEmpty else { return }
            Task {
                let count = await appState.addFilesToInbox(urls: urls)
                showFeedback("\(count)개 파일 추가됨")
            }
        }
    }

    // MARK: - Paste (Cmd+V)

    private func handlePaste() {
        let pasteboard = NSPasteboard.general
        var urls: [URL] = []

        // File URLs from pasteboard
        if let fileURLs = pasteboard.readObjects(forClasses: [NSURL.self], options: [
            .urlReadingFileURLsOnly: true
        ]) as? [URL] {
            urls.append(contentsOf: fileURLs)
        }

        guard !urls.isEmpty else { return }

        Task {
            let count = await appState.addFilesToInbox(urls: urls)
            showFeedback("\(count)개 파일 붙여넣기 완료")
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

/// NSView-backed view that captures Cmd+V paste events
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

    override func keyDown(with event: NSEvent) {
        if event.modifierFlags.contains(.command) && event.charactersIgnoringModifiers == "v" {
            onPaste?()
        } else {
            super.keyDown(with: event)
        }
    }
}
