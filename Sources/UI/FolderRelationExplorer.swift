import AppKit
import SwiftUI

struct FolderRelationExplorer: View {
    @EnvironmentObject var appState: AppState

    @State private var candidates: [FolderPairCandidate] = []
    @State private var currentIndex: Int = 0
    @State private var isLoading: Bool = true
    @State private var keyMonitor: Any?

    // Drag state
    @State private var dragOffset: CGSize = .zero
    @State private var isDragging: Bool = false

    // Dismiss animation
    @State private var dismissed: Bool = false
    @State private var dismissDirection: SwipeDirection = .none

    private enum SwipeDirection { case none, left, right, down }

    private let dragThreshold: CGFloat = 80

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
        let dragDirection = currentDragDirection

        return VStack(spacing: 0) {
            Spacer()

            ZStack(alignment: .top) {
                // Card
                VStack(spacing: 14) {
                    // Source folder
                    folderBadge(
                        name: (candidate.sourceFolder as NSString).lastPathComponent,
                        para: candidate.sourcePara,
                        noteCount: candidate.sourceNoteCount
                    )

                    // Hint + relation type
                    VStack(spacing: 6) {
                        if let hint = candidate.hint {
                            Text("\"\(hint)\"")
                                .font(.subheadline)
                                .italic()
                                .foregroundColor(.primary.opacity(0.8))
                                .multilineTextAlignment(.center)
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

                    // Evidence
                    HStack(spacing: 12) {
                        if !candidate.topSharedTags.isEmpty {
                            Label("\(candidate.sharedTagCount) tags", systemImage: "tag")
                        }
                        if candidate.existingLinkCount > 0 {
                            Label("\(candidate.existingLinkCount) links", systemImage: "link")
                        }
                    }
                    .font(.caption2)
                    .foregroundColor(.secondary)
                }
                .padding(20)
                .frame(maxWidth: .infinity)
                .background(.ultraThinMaterial)
                .cornerRadius(16)
                .shadow(color: .black.opacity(0.08), radius: 8, y: 4)
                .overlay(
                    RoundedRectangle(cornerRadius: 16)
                        .stroke(dragBorderColor.opacity(dragBorderOpacity), lineWidth: 2.5)
                )

                // Stamp overlay
                if dragDirection != .none {
                    stampOverlay(dragDirection)
                }
            }
            .offset(x: dismissed ? dismissOffset.width : dragOffset.width,
                    y: dismissed ? dismissOffset.height : min(dragOffset.height, 0) * 0.3)
            .rotationEffect(.degrees(dismissed ? dismissRotation : Double(dragOffset.width / 25)))
            .opacity(dismissed ? 0 : 1)
            .padding(.horizontal, 16)
            .gesture(
                DragGesture()
                    .onChanged { value in
                        isDragging = true
                        dragOffset = value.translation
                    }
                    .onEnded { value in
                        isDragging = false
                        let h = value.translation.width
                        let v = value.translation.height
                        if h < -dragThreshold {
                            handleAction(.left)
                        } else if h > dragThreshold {
                            handleAction(.right)
                        } else if v > dragThreshold {
                            handleAction(.down)
                        } else {
                            withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                                dragOffset = .zero
                            }
                        }
                    }
            )

            Spacer()

            // Action buttons with labels
            HStack(spacing: 24) {
                VStack(spacing: 4) {
                    circleButton(icon: "xmark", color: .red, size: 48) {
                        handleAction(.left)
                    }
                    Text("Suppress")
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                }
                VStack(spacing: 4) {
                    circleButton(icon: "forward.fill", color: .secondary, size: 38) {
                        handleAction(.down)
                    }
                    Text("Skip")
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                }
                VStack(spacing: 4) {
                    circleButton(icon: "bolt.heart.fill", color: .green, size: 48) {
                        handleAction(.right)
                    }
                    Text("Boost")
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                }
            }
            .padding(.bottom, 4)

            // Keyboard hint
            HStack(spacing: 4) {
                Image(systemName: "arrow.left")
                Image(systemName: "arrow.down")
                Image(systemName: "arrow.right")
            }
            .font(.system(size: 9))
            .foregroundStyle(.quaternary)
            .padding(.bottom, 6)
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
        .background(Color.primary.opacity(0.03))
        .cornerRadius(8)
    }

    private func circleButton(icon: String, color: Color, size: CGFloat, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: icon)
                .font(.system(size: size * 0.36, weight: .bold))
                .foregroundColor(color)
                .frame(width: size, height: size)
                .background(color.opacity(0.1))
                .clipShape(Circle())
                .overlay(Circle().stroke(color.opacity(0.2), lineWidth: 1))
        }
        .buttonStyle(.plain)
    }

    private func stampOverlay(_ direction: SwipeDirection) -> some View {
        let (text, color, rotation): (String, Color, Double) = {
            switch direction {
            case .right: return ("BOOST", .green, -15)
            case .left: return ("NOPE", .red, 15)
            case .down: return ("SKIP", .secondary, 0)
            case .none: return ("", .clear, 0)
            }
        }()

        return Text(text)
            .font(.system(size: 28, weight: .heavy))
            .foregroundColor(color)
            .padding(.horizontal, 12)
            .padding(.vertical, 4)
            .overlay(
                RoundedRectangle(cornerRadius: 6)
                    .stroke(color, lineWidth: 3)
            )
            .rotationEffect(.degrees(rotation))
            .opacity(stampOpacity)
            .padding(.top, 24)
    }

    // MARK: - Drag Visuals

    private var currentDragDirection: SwipeDirection {
        if dismissed { return dismissDirection }
        let h = dragOffset.width
        let v = dragOffset.height
        if abs(h) > 30 { return h > 0 ? .right : .left }
        if v > 30 { return .down }
        return .none
    }

    private var dragBorderColor: Color {
        switch currentDragDirection {
        case .left: return .red
        case .right: return .green
        case .down: return .secondary
        case .none: return .clear
        }
    }

    private var dragBorderOpacity: Double {
        let progress = max(abs(dragOffset.width), dragOffset.height) / dragThreshold
        return min(progress, 1.0)
    }

    private var stampOpacity: Double {
        let progress = max(abs(dragOffset.width), dragOffset.height) / dragThreshold
        return min(progress * 0.8, 0.8)
    }

    private var dismissOffset: CGSize {
        switch dismissDirection {
        case .left: return CGSize(width: -400, height: 0)
        case .right: return CGSize(width: 400, height: 0)
        case .down: return CGSize(width: 0, height: 300)
        case .none: return .zero
        }
    }

    private var dismissRotation: Double {
        switch dismissDirection {
        case .left: return -20
        case .right: return 20
        default: return 0
        }
    }

    // MARK: - Actions

    private func handleAction(_ direction: SwipeDirection) {
        guard currentIndex < candidates.count, !dismissed else { return }
        let candidate = candidates[currentIndex]

        dismissDirection = direction

        withAnimation(.easeIn(duration: 0.3)) {
            dismissed = true
        }

        Task { @MainActor in
            try? await Task.sleep(for: .seconds(0.3))

            switch direction {
            case .right:
                saveRelation(candidate, type: "boost")
            case .left:
                saveRelation(candidate, type: "suppress")
            case .down, .none:
                break
            }

            currentIndex += 1
            dragOffset = .zero
            dismissed = false
            dismissDirection = .none
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
