import AppKit
import SwiftUI

struct FolderRelationExplorer: View {
    @EnvironmentObject var appState: AppState

    @State private var candidates: [FolderPairCandidate] = []
    @State private var currentIndex: Int = 0
    @State private var isLoading: Bool = true
    @State private var cardOffset: CGFloat = 0
    @State private var cardOpacity: Double = 1
    @State private var keyMonitor: Any?

    private enum SwipeDirection { case none, left, right, down }
    @State private var swipeDirection: SwipeDirection = .none

    var body: some View {
        VStack(spacing: 0) {
            BreadcrumbView(
                current: .folderRelationExplorer,
                trailing: AnyView(counterView)
            )
            Divider()

            if isLoading {
                loadingView
            } else if candidates.isEmpty {
                emptyView
            } else if currentIndex < candidates.count {
                cardView
            } else {
                completedView
            }
        }
        .task { await loadCandidates() }
    }

    // MARK: - Counter

    private var counterView: some View {
        Group {
            if !isLoading && !candidates.isEmpty && currentIndex < candidates.count {
                Text("\(currentIndex + 1) / \(candidates.count)")
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .monospacedDigit()
            }
        }
    }

    // MARK: - Loading

    private var loadingView: some View {
        VStack(spacing: 12) {
            Spacer()
            ProgressView()
                .controlSize(.regular)
            Text("AI가 폴더 관계를 분석하고 있습니다...")
                .font(.subheadline)
                .foregroundColor(.secondary)
            Spacer()
        }
        .frame(maxWidth: .infinity)
    }

    // MARK: - Empty

    private var emptyView: some View {
        VStack(spacing: 12) {
            Spacer()
            Image(systemName: "checkmark.circle")
                .font(.system(size: 32))
                .foregroundColor(.green)
            Text("모든 폴더 관계를 검토했습니다")
                .font(.subheadline)
            Button("돌아가기") {
                appState.currentScreen = .dashboard
            }
            .buttonStyle(.plain)
            .foregroundColor(.accentColor)
            Spacer()
        }
        .frame(maxWidth: .infinity)
    }

    // MARK: - Completed

    private var completedView: some View {
        VStack(spacing: 12) {
            Spacer()
            Image(systemName: "hand.thumbsup")
                .font(.system(size: 32))
                .foregroundColor(.green)
            Text("\(candidates.count)개 폴더 쌍 검토 완료")
                .font(.subheadline)
                .fontWeight(.medium)
            Button("돌아가기") {
                appState.currentScreen = .dashboard
            }
            .buttonStyle(.plain)
            .foregroundColor(.accentColor)
            Spacer()
        }
        .frame(maxWidth: .infinity)
    }

    // MARK: - Card

    private var cardView: some View {
        let candidate = candidates[currentIndex]

        return VStack(spacing: 0) {
            Spacer()

            VStack(spacing: 16) {
                // Source folder
                folderBadge(
                    name: (candidate.sourceFolder as NSString).lastPathComponent,
                    para: candidate.sourcePara,
                    noteCount: candidate.sourceNoteCount
                )

                // Hint + relation type
                VStack(spacing: 4) {
                    if let hint = candidate.hint {
                        Text("\"\(hint)\"")
                            .font(.subheadline)
                            .italic()
                            .foregroundColor(.primary.opacity(0.8))
                    }
                    if let relType = candidate.relationType {
                        Text(relType)
                            .font(.caption)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 2)
                            .background(Color.accentColor.opacity(0.1))
                            .cornerRadius(4)
                    }
                }

                // Target folder
                folderBadge(
                    name: (candidate.targetFolder as NSString).lastPathComponent,
                    para: candidate.targetPara,
                    noteCount: candidate.targetNoteCount
                )
            }
            .padding(20)
            .frame(maxWidth: .infinity)
            .background(Color.primary.opacity(0.03))
            .cornerRadius(12)
            .overlay(
                RoundedRectangle(cornerRadius: 12)
                    .stroke(swipeBorderColor, lineWidth: swipeDirection == .none ? 0 : 2)
            )
            .offset(x: cardOffset, y: swipeDirection == .down ? cardOffset / 3 : 0)
            .opacity(cardOpacity)
            .padding(.horizontal, 16)

            // Evidence
            HStack(spacing: 12) {
                if !candidate.topSharedTags.isEmpty {
                    Label("공유 태그 \(candidate.sharedTagCount)개", systemImage: "tag")
                }
                if candidate.existingLinkCount > 0 {
                    Label("기존 연결 \(candidate.existingLinkCount)개", systemImage: "link")
                }
            }
            .font(.caption)
            .foregroundColor(.secondary)
            .padding(.top, 8)

            Spacer()

            // Action buttons
            HStack(spacing: 12) {
                actionButton(label: "아니야", icon: "arrow.left", color: .red) {
                    handleAction(.left)
                }
                actionButton(label: "글쎄", icon: "arrow.down", color: .secondary) {
                    handleAction(.down)
                }
                actionButton(label: "맞아!", icon: "arrow.right", color: .green) {
                    handleAction(.right)
                }
            }
            .padding(.horizontal, 16)
            .padding(.bottom, 8)

            Text("키보드: <- -> (화살표)")
                .font(.caption2)
                .foregroundStyle(.quaternary)
                .padding(.bottom, 8)
        }
        .onAppear { setupKeyMonitor() }
        .onDisappear { removeKeyMonitor() }
    }

    // MARK: - Subviews

    private func folderBadge(name: String, para: PARACategory, noteCount: Int) -> some View {
        HStack(spacing: 8) {
            Image(systemName: "folder.fill")
                .foregroundColor(para.color)
            VStack(alignment: .leading, spacing: 1) {
                Text(name)
                    .font(.subheadline)
                    .fontWeight(.medium)
                    .lineLimit(1)
                Text("\(para.rawValue) · \(noteCount)개 노트")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            Spacer()
        }
        .padding(10)
        .background(Color.primary.opacity(0.02))
        .cornerRadius(8)
    }

    private func actionButton(label: String, icon: String, color: Color, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 4) {
                Image(systemName: icon)
                    .font(.caption)
                Text(label)
                    .font(.caption)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 8)
            .background(color.opacity(0.08))
            .foregroundColor(color)
            .cornerRadius(8)
        }
        .buttonStyle(.plain)
    }

    private var swipeBorderColor: Color {
        switch swipeDirection {
        case .left: return .red
        case .right: return .green
        case .down: return .secondary
        case .none: return .clear
        }
    }

    // MARK: - Actions

    private func handleAction(_ direction: SwipeDirection) {
        guard currentIndex < candidates.count else { return }
        let candidate = candidates[currentIndex]

        swipeDirection = direction

        // Animate card out
        withAnimation(.easeIn(duration: 0.25)) {
            switch direction {
            case .left:
                cardOffset = -300
                cardOpacity = 0
            case .right:
                cardOffset = 300
                cardOpacity = 0
            case .down:
                cardOffset = 200
                cardOpacity = 0
            case .none:
                break
            }
        }

        // Save result and advance after animation completes
        Task { @MainActor in
            try? await Task.sleep(for: .seconds(0.25))

            switch direction {
            case .right:
                saveRelation(candidate, type: "boost")
            case .left:
                saveRelation(candidate, type: "suppress")
            case .down, .none:
                break  // skip — no save
            }

            currentIndex += 1
            cardOffset = 0
            cardOpacity = 1
            swipeDirection = .none
        }
    }

    private func saveRelation(_ candidate: FolderPairCandidate, type: String) {
        let store = FolderRelationStore(pkmRoot: appState.pkmRootPath)
        store.addRelation(FolderRelation(
            source: candidate.sourceFolder,
            target: candidate.targetFolder,
            type: type,
            hint: candidate.hint,
            relationType: candidate.relationType,
            origin: "explore",
            created: ISO8601DateFormatter().string(from: Date())
        ))

        let src = (candidate.sourceFolder as NSString).lastPathComponent
        let tgt = (candidate.targetFolder as NSString).lastPathComponent
        StatisticsService.recordActivity(
            fileName: "\(src) <> \(tgt)",
            category: "folder-relation",
            action: type,
            detail: candidate.hint ?? ""
        )
    }

    // MARK: - Keyboard

    private func setupKeyMonitor() {
        keyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
            guard appState.currentScreen == .folderRelationExplorer else { return event }
            switch event.keyCode {
            case 123: // left arrow
                handleAction(.left)
                return nil
            case 124: // right arrow
                handleAction(.right)
                return nil
            case 125: // down arrow
                handleAction(.down)
                return nil
            default:
                return event
            }
        }
    }

    private func removeKeyMonitor() {
        if let monitor = keyMonitor {
            NSEvent.removeMonitor(monitor)
            keyMonitor = nil
        }
    }

    // MARK: - Load

    private func loadCandidates() async {
        let root = appState.pkmRootPath
        let linker = SemanticLinker(pkmRoot: root)
        let allNotes = linker.buildNoteIndex()

        let relationStore = FolderRelationStore(pkmRoot: root)
        let existingRelations = relationStore.load()

        let analyzer = FolderRelationAnalyzer(pkmRoot: root)
        let result = await analyzer.generateCandidates(
            allNotes: allNotes,
            existingRelations: existingRelations
        )

        await MainActor.run {
            candidates = result
            isLoading = false
        }
    }
}
