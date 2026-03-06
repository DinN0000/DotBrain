import SwiftUI
import AppKit

struct ResultsView: View {
    @EnvironmentObject var appState: AppState

    private var navigateBackLabel: String {
        switch appState.processingOrigin {
        case .paraManage: return L10n.Screen.paraManage
        default: return L10n.Results.goBack
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                Text(L10n.Results.title)
                    .font(.headline)

                Spacer()

                let successCount = appState.processedResults.filter(\.isSuccess).count
                let totalCount = appState.processedResults.count + appState.pendingConfirmations.count
                Text("\(successCount)/\(totalCount)")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
            }
            .padding()

            Divider()

            // Pipeline error banner
            if let error = appState.pipelineError {
                HStack(spacing: 8) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .foregroundColor(.white)
                    Text(error)
                        .font(.caption)
                        .foregroundColor(.white)
                        .lineLimit(3)
                    Spacer()
                }
                .padding(10)
                .background(RoundedRectangle(cornerRadius: 8).fill(Color.red.opacity(0.85)))
                .padding(.horizontal)
                .padding(.top, 8)
            }

            // Results list
            ScrollView {
                if appState.processedResults.isEmpty && appState.pendingConfirmations.isEmpty && appState.pipelineError == nil {
                    VStack(spacing: 8) {
                        Image(systemName: "tray")
                            .font(.title)
                            .foregroundColor(.secondary)
                        Text(L10n.Results.noFiles)
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.top, 40)
                } else {
                    LazyVStack(spacing: 2) {
                        // Summary card
                        ResultsSummaryCard()

                        // Batch actions for pending confirmations
                        if appState.pendingConfirmations.count > 1 {
                            HStack(spacing: 12) {
                                Label(
                                    L10n.Results.confirmWaiting(appState.pendingConfirmations.count),
                                    systemImage: "questionmark.circle"
                                )
                                .font(.caption)
                                .foregroundColor(.orange)

                                Spacer()

                                HoverTextLink(label: L10n.Results.skipAll, color: .secondary) {
                                    let items = appState.pendingConfirmations
                                    for item in items {
                                        appState.skipConfirmation(item)
                                    }
                                }
                            }
                            .padding(.vertical, 6)
                            .padding(.horizontal, 6)
                        }

                        ForEach(appState.pendingConfirmations) { confirmation in
                            ConfirmationRow(confirmation: confirmation)
                        }

                        ForEach(appState.processedResults) { result in
                            ResultRow(result: result)
                        }

                        // Affected folders & next steps (inbox processing only)
                        if appState.processingOrigin == .inbox,
                           !appState.affectedFolders.isEmpty,
                           appState.pendingConfirmations.isEmpty {
                            NextStepsSection()
                        }
                    }
                    .padding(.horizontal)
                    .padding(.vertical, 8)
                }
            }

            Divider()

            // Action buttons
            HStack {
                if !appState.processedResults.isEmpty {
                    HoverTextButton(label: L10n.Results.openInFinder) {
                        openInFinder()
                    }
                }

                Spacer()

                HoverTextButton(label: navigateBackLabel) {
                    appState.navigateBack()
                }
            }
            .padding()
        }
    }

    private func openInFinder() {
        let successPaths = appState.processedResults
            .filter(\.isSuccess)
            .map(\.targetPath)
            .filter { !$0.isEmpty }

        guard !successPaths.isEmpty else { return }

        if successPaths.count == 1 {
            let dir = (successPaths[0] as NSString).deletingLastPathComponent
            NSWorkspace.shared.selectFile(successPaths[0], inFileViewerRootedAtPath: dir)
            return
        }

        // Find common parent folder
        let folders = successPaths.map { ($0 as NSString).deletingLastPathComponent }
        var common = folders[0]
        for folder in folders.dropFirst() {
            while !folder.hasPrefix(common) {
                common = (common as NSString).deletingLastPathComponent
            }
        }
        NSWorkspace.shared.selectFile(nil, inFileViewerRootedAtPath: common)
    }
}

// MARK: - Row Views

struct ResultRow: View {
    let result: ProcessedFileResult
    @State private var isHovered = false
    @State private var isErrorExpanded = false

    private var iconName: String {
        switch result.status {
        case .success: return "checkmark.circle.fill"
        case .relocated: return "arrow.right.circle.fill"
        case .skipped: return "arrow.uturn.backward.circle.fill"
        case .deleted: return "trash.circle.fill"
        case .deduplicated: return "doc.on.doc.fill"
        case .error: return "xmark.circle.fill"
        }
    }

    private var iconColor: Color {
        switch result.status {
        case .success: return .green
        case .relocated: return .purple
        case .skipped: return .orange
        case .deleted: return .secondary
        case .deduplicated: return .blue
        case .error: return .red
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack(spacing: 8) {
                Image(systemName: iconName)
                    .foregroundColor(iconColor)
                    .font(.system(size: 14))

                VStack(alignment: .leading, spacing: 2) {
                    Text(result.fileName)
                        .font(.system(.body, design: .monospaced))
                        .lineLimit(1)
                        .underline(isHovered && result.isSuccess)
                        .onTapGesture {
                            if result.isSuccess {
                                openFile(result.targetPath)
                            } else if result.isError {
                                withAnimation(.easeOut(duration: 0.15)) {
                                    isErrorExpanded.toggle()
                                }
                            }
                        }
                        .onHover { inside in
                            guard result.isSuccess else { return }
                            isHovered = inside
                            if inside { NSCursor.pointingHand.push() } else { NSCursor.pop() }
                        }
                        .onDisappear { if isHovered { NSCursor.pop() } }

                    switch result.status {
                    case .success:
                        HStack(spacing: 4) {
                            Image(systemName: result.isAsset ? "paperclip" : result.para.icon)
                                .font(.caption2)
                            Text(result.displayTarget)
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                    case .relocated:
                        HStack(spacing: 4) {
                            Image(systemName: result.para.icon)
                                .font(.caption2)
                            Text(L10n.Results.movedTo(result.displayTarget))
                                .font(.caption)
                                .foregroundColor(.purple)
                        }
                    case .deduplicated(let message):
                        Text(message)
                            .font(.caption)
                            .foregroundColor(.blue)
                    case .skipped(let message):
                        Text(message)
                            .font(.caption)
                            .foregroundColor(.secondary)
                    case .deleted:
                        Text(L10n.Results.deletedLabel)
                            .font(.caption)
                            .foregroundColor(.secondary)
                    case .error:
                        HStack(spacing: 4) {
                            Text(L10n.Results.errorOccurred)
                                .font(.caption)
                                .foregroundColor(.red)
                            Image(systemName: isErrorExpanded ? "chevron.up" : "chevron.down")
                                .font(.caption2)
                                .foregroundColor(.red)
                        }
                        .onTapGesture {
                            withAnimation(.easeOut(duration: 0.15)) {
                                isErrorExpanded.toggle()
                            }
                        }
                        .onHover { inside in
                            if inside { NSCursor.pointingHand.push() } else { NSCursor.pop() }
                        }
                    }
                }

                Spacer()
            }
            .onDisappear {
                if isHovered { NSCursor.pop() }
            }

            if isErrorExpanded, let error = result.error {
                Text(error)
                    .font(.caption)
                    .foregroundColor(.red.opacity(0.8))
                    .textSelection(.enabled)
                    .padding(8)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Color.red.opacity(0.05))
                    .cornerRadius(4)
                    .padding(.leading, 22)
                    .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
        .padding(.vertical, 4)
        .padding(.horizontal, 4)
        .background(
            RoundedRectangle(cornerRadius: 6)
                .fill(isHovered ? Color.primary.opacity(0.04) : Color.clear)
        )
        .animation(.easeOut(duration: 0.15), value: isHovered)
        .onHover { isHovered = $0 }
    }
}

struct ConfirmationRow: View {
    let confirmation: PendingConfirmation
    @EnvironmentObject var appState: AppState
    @State private var isHovered = false
    @State private var isConfirming = false
    @State private var showProjectCreate = false
    @State private var newProjectName = ""

    private var sortedOptions: [ClassifyResult] {
        let paraOrder: [PARACategory] = [.project, .area, .resource, .archive]
        var seen = Set<PARACategory>()
        return paraOrder.compactMap { category in
            guard !seen.contains(category),
                  let option = confirmation.options.first(where: { $0.para == category }) else { return nil }
            seen.insert(category)
            return option
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 8) {
                Image(systemName: confirmation.reason == .unmatchedProject
                    ? "folder.badge.questionmark"
                    : "questionmark.circle.fill")
                    .foregroundColor(.orange)
                    .font(.system(size: 14))

                ClickableFileName(name: confirmation.fileName) {
                    openFile(confirmation.filePath)
                }

                Spacer()
            }

            // Contextual message
            if confirmation.reason == .unmatchedProject {
                if let suggested = confirmation.suggestedProjectName, !suggested.isEmpty {
                    Text(L10n.Results.unmatchedProjectHint)
                        .font(.caption)
                        .foregroundColor(.secondary)
                } else {
                    Text(L10n.Results.unmatchedProjectHint)
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            } else if confirmation.reason == .nameConflict {
                Text(L10n.Results.nameConflictHint)
                    .font(.caption)
                    .foregroundColor(.secondary)
            } else if confirmation.reason == .misclassified {
                Text(L10n.Results.misclassifiedHint)
                    .font(.caption)
                    .foregroundColor(.secondary)
            } else {
                Text(L10n.Results.lowConfidenceHint)
                    .font(.caption)
                    .foregroundColor(.secondary)
            }

            if isConfirming {
                ProgressView()
                    .controlSize(.small)
                    .frame(maxWidth: .infinity)
            } else if confirmation.reason == .unmatchedProject {
                // Inline project creation
                if showProjectCreate {
                    HStack(spacing: 4) {
                        TextField(L10n.Results.projectName, text: $newProjectName)
                            .textFieldStyle(.roundedBorder)
                            .controlSize(.small)
                            .onSubmit { createProject() }

                        Button(L10n.Results.create) { createProject() }
                            .buttonStyle(.borderedProminent)
                            .controlSize(.small)
                            .disabled(newProjectName.trimmingCharacters(in: .whitespaces).isEmpty)

                        Button("취소") { showProjectCreate = false }
                            .buttonStyle(.bordered)
                            .controlSize(.small)
                    }
                } else {
                    HStack(spacing: 4) {
                        Button(action: {
                            newProjectName = confirmation.suggestedProjectName ?? ""
                            showProjectCreate = true
                        }) {
                            Label(L10n.Results.createProject, systemImage: "folder.badge.plus")
                                .font(.caption2)
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 4)
                        }
                        .buttonStyle(.borderedProminent)
                        .controlSize(.small)

                        ForEach(sortedOptions.filter({ $0.para != .project }), id: \.para) { option in
                            HoverPARAButton(para: option.para) {
                                isConfirming = true
                                Task {
                                    await appState.confirmClassification(confirmation, choice: option)
                                    isConfirming = false
                                }
                            }
                        }
                    }
                }
            } else {
                // Standard PARA buttons
                HStack(spacing: 4) {
                    ForEach(sortedOptions, id: \.para) { option in
                        HoverPARAButton(para: option.para) {
                            isConfirming = true
                            Task {
                                await appState.confirmClassification(confirmation, choice: option)
                                isConfirming = false
                            }
                        }
                    }
                }
            }

            // Skip / Delete
            HStack(spacing: 12) {
                Spacer()

                HoverTextLink(label: L10n.Results.skip, color: .secondary) {
                    appState.skipConfirmation(confirmation)
                }

                HoverTextLink(label: L10n.Results.delete, color: .red) {
                    appState.deleteConfirmation(confirmation)
                }
            }
            .disabled(isConfirming)
        }
        .padding(.vertical, 6)
        .padding(.horizontal, 6)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .strokeBorder(Color.primary.opacity(isHovered ? 0.12 : 0), lineWidth: 1)
        )
        .animation(.easeOut(duration: 0.15), value: isHovered)
        .onHover { isHovered = $0 }
    }

    private func createProject() {
        let name = newProjectName.trimmingCharacters(in: .whitespaces)
        guard !name.isEmpty else { return }
        isConfirming = true
        Task {
            await appState.createProjectAndClassify(confirmation, projectName: name)
            isConfirming = false
        }
    }
}

// MARK: - Results Summary Card

struct ResultsSummaryCard: View {
    @EnvironmentObject var appState: AppState

    private var successCount: Int {
        appState.processedResults.filter(\.isSuccess).count
    }
    private var errorCount: Int {
        appState.processedResults.filter(\.isError).count
    }
    private var skippedCount: Int {
        appState.processedResults.filter {
            if case .skipped = $0.status { return true }
            return false
        }.count
    }
    private var relocatedCount: Int {
        appState.processedResults.filter {
            if case .relocated = $0.status { return true }
            return false
        }.count
    }

    var body: some View {
        if successCount > 0 || errorCount > 0 {
            VStack(alignment: .leading, spacing: 6) {
                // Main result
                Label(
                    L10n.Results.filesOrganized(successCount),
                    systemImage: "checkmark.circle"
                )
                .font(.caption)
                .fontWeight(.medium)
                .foregroundColor(.green)

                // Stats row
                HStack(spacing: 10) {
                    if relocatedCount > 0 {
                        HStack(spacing: 2) {
                            Image(systemName: "arrow.right.circle")
                                .font(.caption2)
                                .foregroundColor(.purple)
                            Text(L10n.Results.relocatedCount(relocatedCount))
                                .font(.caption2)
                                .foregroundColor(.secondary)
                        }
                    }
                    if skippedCount > 0 {
                        HStack(spacing: 2) {
                            Image(systemName: "arrow.uturn.backward.circle")
                                .font(.caption2)
                                .foregroundColor(.orange)
                            Text(L10n.Results.skippedCount(skippedCount))
                                .font(.caption2)
                                .foregroundColor(.secondary)
                        }
                    }
                    if errorCount > 0 {
                        HStack(spacing: 2) {
                            Image(systemName: "xmark.circle")
                                .font(.caption2)
                                .foregroundColor(.red)
                            Text(L10n.Results.errorCount(errorCount))
                                .font(.caption2)
                                .foregroundColor(.secondary)
                        }
                    }
                    if !appState.pendingConfirmations.isEmpty {
                        HStack(spacing: 2) {
                            Image(systemName: "questionmark.circle")
                                .font(.caption2)
                                .foregroundColor(.orange)
                            Text(L10n.Results.waitingCount(appState.pendingConfirmations.count))
                                .font(.caption2)
                                .foregroundColor(.secondary)
                        }
                    }
                }

                Text(L10n.Results.autoTagged)
                    .font(.caption2)
                    .foregroundColor(.secondary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(10)
            .background(
                RoundedRectangle(cornerRadius: 8)
                    .fill(Color.green.opacity(0.08))
            )
            .padding(.bottom, 6)
        }
    }
}

// MARK: - Next Steps Section

struct NextStepsSection: View {
    @EnvironmentObject var appState: AppState
    @State private var healthScores: [FolderHealthAnalyzer.HealthScore] = []
    @State private var isLoaded = false

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 4) {
                Image(systemName: "lightbulb.fill")
                    .font(.caption)
                    .foregroundColor(.orange)
                Text(L10n.Results.nextSteps)
                    .font(.caption)
                    .fontWeight(.semibold)
                    .foregroundColor(.primary)
            }
            .padding(.top, 8)

            if !isLoaded {
                HStack {
                    ProgressView()
                        .controlSize(.mini)
                    Text(L10n.Results.analyzingFolders)
                        .font(.caption2)
                        .foregroundColor(.secondary)
                }
                .padding(.vertical, 4)
            } else if healthScores.isEmpty {
                Label(L10n.Results.allFoldersGood, systemImage: "checkmark.circle")
                    .font(.caption)
                    .foregroundColor(.green)
                    .padding(.vertical, 4)
            } else {
                ForEach(healthScores, id: \.folderPath) { score in
                    AffectedFolderRow(healthScore: score)
                }

                if healthScores.count > 1 {
                    HoverTextButton(label: L10n.Results.cleanAll) {
                        let folders = healthScores.map {
                            (category: $0.category, subfolder: $0.folderName)
                        }
                        Task {
                            await appState.startBatchReorganizing(folders: folders)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .trailing)
                    .padding(.top, 2)
                }
            }
        }
        .padding(10)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(Color.orange.opacity(0.06))
        )
        .padding(.top, 6)
        .onAppear { analyzeAffectedFolders() }
    }

    private func analyzeAffectedFolders() {
        let folders = appState.affectedFolders
        let root = appState.pkmRootPath
        Task.detached(priority: .utility) {
            let scores = FolderHealthAnalyzer.analyzeAll(folderPaths: folders, pkmRoot: root)
            // Show folders that need attention (score < 0.8)
            let needsAttention = scores.filter { $0.score < 0.8 }
            await MainActor.run {
                healthScores = needsAttention
                isLoaded = true
            }
        }
    }
}

struct AffectedFolderRow: View {
    let healthScore: FolderHealthAnalyzer.HealthScore
    @EnvironmentObject var appState: AppState
    @State private var isHovered = false

    private var healthColor: Color {
        switch healthScore.label {
        case "urgent": return .red
        case "attention": return .orange
        default: return .green
        }
    }

    private var healthIcon: String {
        switch healthScore.label {
        case "urgent": return "exclamationmark.triangle.fill"
        case "attention": return "exclamationmark.circle.fill"
        default: return "checkmark.circle.fill"
        }
    }

    private var issueDescription: String {
        guard let first = healthScore.issues.first else { return "" }
        switch first {
        case .tooManyFiles(let count):
            return L10n.Results.tooManyFiles(count)
        case .missingFrontmatter(let count, _):
            return L10n.Results.missingFrontmatter(count)
        case .lowTagDiversity:
            return L10n.Results.lowTagDiversity
        }
    }

    var body: some View {
        Button(action: {
            appState.navigateToReorganizeFolder(healthScore.folderPath)
        }) {
            HStack(spacing: 8) {
                Image(systemName: healthIcon)
                    .font(.system(size: 12))
                    .foregroundColor(healthColor)

                VStack(alignment: .leading, spacing: 1) {
                    HStack(spacing: 4) {
                        Image(systemName: healthScore.category.icon)
                            .font(.caption2)
                            .foregroundColor(.secondary)
                        Text(healthScore.folderName)
                            .font(.caption)
                            .fontWeight(.medium)
                            .lineLimit(1)
                    }

                    Text(issueDescription)
                        .font(.caption2)
                        .foregroundColor(.secondary)
                        .lineLimit(1)
                }

                Spacer()

                HStack(spacing: 2) {
                    Text(L10n.Results.cleanUp)
                        .font(.caption2)
                    Image(systemName: "chevron.right")
                        .font(.system(size: 8))
                }
                .foregroundColor(.accentColor)
                .opacity(isHovered ? 1.0 : 0.6)
            }
            .padding(.vertical, 5)
            .padding(.horizontal, 8)
            .background(
                RoundedRectangle(cornerRadius: 6)
                    .fill(isHovered ? Color.primary.opacity(0.04) : Color.clear)
            )
        }
        .buttonStyle(.plain)
        .animation(.easeOut(duration: 0.12), value: isHovered)
        .onHover { inside in
            isHovered = inside
            if inside { NSCursor.pointingHand.push() } else { NSCursor.pop() }
        }
        .onDisappear { if isHovered { NSCursor.pop() } }
    }
}

// MARK: - Hover Components

/// Clickable file name with underline on hover
struct ClickableFileName: View {
    let name: String
    let action: () -> Void
    @State private var isHovered = false

    var body: some View {
        Text(name)
            .font(.system(.body, design: .monospaced))
            .lineLimit(1)
            .underline(isHovered)
            .onTapGesture(perform: action)
            .onHover { inside in
                isHovered = inside
                if inside { NSCursor.pointingHand.push() } else { NSCursor.pop() }
            }
            .onDisappear { if isHovered { NSCursor.pop() } }
            .animation(.easeOut(duration: 0.1), value: isHovered)
    }
}

/// PARA category button with hover highlight
struct HoverPARAButton: View {
    let para: PARACategory
    let action: () -> Void
    @State private var isHovered = false

    var body: some View {
        Button(action: action) {
            Text(para.displayName)
                .font(.caption2)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 4)
        }
        .buttonStyle(.bordered)
        .controlSize(.small)
        .opacity(isHovered ? 1.0 : 0.8)
        .scaleEffect(isHovered ? 1.03 : 1.0)
        .animation(.easeOut(duration: 0.12), value: isHovered)
        .onHover { isHovered = $0 }
    }
}

/// Plain text link with hover underline
struct HoverTextLink: View {
    let label: String
    let color: Color
    let action: () -> Void
    @State private var isHovered = false

    var body: some View {
        Button(action: action) {
            Text(label)
                .font(.caption)
                .foregroundColor(color)
                .underline(isHovered)
                .opacity(isHovered ? 1.0 : 0.7)
        }
        .buttonStyle(.plain)
        .animation(.easeOut(duration: 0.1), value: isHovered)
        .onHover { inside in
            isHovered = inside
            if inside { NSCursor.pointingHand.push() } else { NSCursor.pop() }
        }
        .onDisappear { if isHovered { NSCursor.pop() } }
    }
}

/// Bordered button with hover feedback
struct HoverTextButton: View {
    let label: String
    let action: () -> Void
    @State private var isHovered = false

    var body: some View {
        Button(action: action) {
            Text(label)
        }
        .buttonStyle(.bordered)
        .controlSize(.small)
        .opacity(isHovered ? 1.0 : 0.85)
        .animation(.easeOut(duration: 0.12), value: isHovered)
        .onHover { isHovered = $0 }
    }
}

// MARK: - Helpers

private func openFile(_ path: String) {
    let url = URL(fileURLWithPath: path)
    NSWorkspace.shared.open(url)
}
