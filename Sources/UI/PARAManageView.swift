import SwiftUI

struct PARAManageView: View {
    @EnvironmentObject var appState: AppState
    @State private var folderMap: [PARACategory: [FolderEntry]] = [:]
    @State private var showNewProject = false
    @State private var newProjectName = ""
    @State private var newProjectSummary = ""
    @State private var statusMessage = ""
    @State private var isLoading = true
    @State private var deleteTarget: (name: String, category: PARACategory)?

    var body: some View {
        VStack(spacing: 0) {
            BreadcrumbView(
                current: .paraManage,
                trailing: AnyView(
                    Button(action: { showNewProject.toggle() }) {
                        Image(systemName: showNewProject ? "minus.circle" : "plus.circle")
                    }
                    .buttonStyle(.plain)
                    .help("새 프로젝트")
                )
            )

            Divider()

            if isLoading {
                Spacer()
                ProgressView()
                    .scaleEffect(0.8)
                Text("폴더 스캔 중...")
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .padding(.top, 8)
                Spacer()
            } else {
                ScrollViewReader { proxy in
                    ScrollView {
                        LazyVStack(spacing: 0) {
                            // New project form
                            if showNewProject {
                                VStack(spacing: 8) {
                                    TextField("프로젝트 이름", text: $newProjectName)
                                        .textFieldStyle(.roundedBorder)
                                    TextField("설명 (선택)", text: $newProjectSummary)
                                        .textFieldStyle(.roundedBorder)
                                    Button(action: createProject) {
                                        HStack {
                                            Image(systemName: "plus")
                                            Text("프로젝트 생성")
                                        }
                                        .frame(maxWidth: .infinity)
                                    }
                                    .buttonStyle(.borderedProminent)
                                    .controlSize(.small)
                                    .disabled(newProjectName.trimmingCharacters(in: .whitespaces).isEmpty)
                                }
                                .padding()
                                .background(Color.primary.opacity(0.03))
                                .cornerRadius(8)
                                .padding(.bottom, 8)
                            }

                            // Status message
                            if !statusMessage.isEmpty {
                                Text(statusMessage)
                                    .font(.caption)
                                    .foregroundColor(.green)
                                    .padding(.vertical, 4)
                            }

                            // Category sections
                            ForEach(PARACategory.allCases, id: \.self) { category in
                                categorySection(category)
                                    .id(category)
                            }

                            // Empty state
                            if folderMap.values.allSatisfy({ $0.isEmpty }) {
                                VStack(spacing: 8) {
                                    Text("폴더가 없습니다")
                                        .font(.subheadline)
                                        .foregroundColor(.secondary)
                                    Text("+ 버튼으로 프로젝트를 생성하세요")
                                        .font(.caption)
                                        .foregroundColor(.secondary)
                                }
                                .frame(maxWidth: .infinity)
                                .padding(.top, 40)
                            }
                        }
                        .padding(.horizontal)
                        .padding(.vertical, 8)
                    }
                    .onChange(of: appState.paraManageInitialCategory) { target in
                        if let target {
                            withAnimation {
                                proxy.scrollTo(target, anchor: .top)
                            }
                            appState.paraManageInitialCategory = nil
                        }
                    }
                    .onAppear {
                        if let target = appState.paraManageInitialCategory {
                            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                                withAnimation {
                                    proxy.scrollTo(target, anchor: .top)
                                }
                                appState.paraManageInitialCategory = nil
                            }
                        }
                    }
                }
            }
        }
        .onAppear { loadFolders() }
        .alert("폴더 삭제", isPresented: .init(
            get: { deleteTarget != nil },
            set: { if !$0 { deleteTarget = nil } }
        )) {
            Button("삭제", role: .destructive) {
                if let target = deleteTarget {
                    performDelete(name: target.name, category: target.category)
                }
            }
            Button("취소", role: .cancel) {}
        } message: {
            if let target = deleteTarget {
                Text("'\(target.name)' 폴더를 휴지통으로 보냅니다. Finder에서 복구할 수 있습니다.")
            }
        }
    }

    // MARK: - Category Section

    @ViewBuilder
    private func categorySection(_ category: PARACategory) -> some View {
        let folders = folderMap[category] ?? []

        if folders.isEmpty {
            EmptyView()
        } else if category == .archive {
            DisclosureGroup {
                folderList(folders, category: category)
            } label: {
                categoryHeader(category, count: folders.count)
            }
            .padding(.top, 8)
        } else {
            VStack(alignment: .leading, spacing: 0) {
                categoryHeader(category, count: folders.count)
                    .padding(.vertical, 6)
                folderList(folders, category: category)
            }
            .padding(.top, 8)
        }
    }

    @ViewBuilder
    private func categoryHeader(_ category: PARACategory, count: Int) -> some View {
        HStack(spacing: 4) {
            Image(systemName: category.icon)
                .font(.caption)
                .foregroundColor(.secondary)
            Text(category.displayName)
                .font(.caption)
                .fontWeight(.semibold)
                .foregroundColor(.secondary)
            Text("(\(count))")
                .font(.caption2)
                .foregroundColor(.secondary.opacity(0.7))
        }
    }

    @ViewBuilder
    private func folderList(_ folders: [FolderEntry], category: PARACategory) -> some View {
        ForEach(folders) { folder in
            PARAFolderRow(
                name: folder.name,
                fileCount: folder.fileCount,
                summary: folder.summary,
                category: category,
                healthLabel: folder.healthLabel,
                healthIssues: folder.healthIssues
            )
            .contextMenu {
                // Move to other categories
                ForEach(PARACategory.allCases.filter { $0 != category }, id: \.self) { target in
                    Button {
                        moveFolder(folder.name, from: category, to: target)
                    } label: {
                        Label("\(target.displayName)(으)로 이동", systemImage: target.icon)
                    }
                }

                Divider()

                // Project complete (project category only)
                if category == .project {
                    Button {
                        completeProject(folder.name)
                    } label: {
                        Label("프로젝트 완료", systemImage: "checkmark.circle")
                    }
                }

                // Reactivate (archive category only)
                if category == .archive {
                    Button {
                        reactivateProject(folder.name)
                    } label: {
                        Label("재활성화", systemImage: "arrow.uturn.left.circle")
                    }
                }

                // Auto-reorganize
                Button {
                    startReorganize(category: category, subfolder: folder.name)
                } label: {
                    Label("자동 정리", systemImage: "sparkles")
                }

                Divider()

                // Merge into another folder (same category)
                let siblings = (folderMap[category] ?? []).filter { $0.name != folder.name }
                if !siblings.isEmpty {
                    Menu {
                        ForEach(siblings) { sibling in
                            Button(sibling.name) {
                                mergeFolder(source: folder.name, into: sibling.name, category: category)
                            }
                        }
                    } label: {
                        Label("다른 폴더에 병합", systemImage: "arrow.triangle.merge")
                    }
                }

                // Open in Finder
                Button {
                    openInFinder(folder.name, category: category)
                } label: {
                    Label("Finder에서 열기", systemImage: "folder")
                }

                Divider()

                // Delete folder
                Button(role: .destructive) {
                    deleteTarget = (name: folder.name, category: category)
                } label: {
                    Label("폴더 삭제", systemImage: "trash")
                }
            }
        }
    }

    // MARK: - Actions

    private func loadFolders() {
        isLoading = true
        let root = appState.pkmRootPath
        Task.detached(priority: .utility) {
            var result: [PARACategory: [FolderEntry]] = [:]
            for cat in PARACategory.allCases {
                result[cat] = Self.scanCategory(cat, pkmRoot: root)
            }
            let snapshot = result
            await MainActor.run {
                folderMap = snapshot
                isLoading = false
            }
        }
    }

    private nonisolated static func scanCategory(_ category: PARACategory, pkmRoot: String) -> [FolderEntry] {
        let pathManager = PKMPathManager(root: pkmRoot)
        let fm = FileManager.default
        let basePath = pathManager.paraPath(for: category)
        guard let entries = try? fm.contentsOfDirectory(atPath: basePath) else { return [] }

        var results: [FolderEntry] = []
        for entry in entries.sorted() {
            guard !entry.hasPrefix("."), !entry.hasPrefix("_") else { continue }
            let fullPath = (basePath as NSString).appendingPathComponent(entry)
            var isDir: ObjCBool = false
            guard fm.fileExists(atPath: fullPath, isDirectory: &isDir), isDir.boolValue else { continue }

            let health = FolderHealthAnalyzer.analyze(
                folderPath: fullPath, folderName: entry, category: category
            )
            let issuesText = health.issues.map(\.localizedDescription).joined(separator: "\n")

            // Read index note for summary
            let indexPath = (fullPath as NSString).appendingPathComponent("\(entry).md")
            let summary: String
            if let content = try? String(contentsOfFile: indexPath, encoding: .utf8) {
                let (frontmatter, _) = Frontmatter.parse(markdown: content)
                summary = frontmatter.summary ?? ""
            } else {
                summary = ""
            }

            results.append(FolderEntry(
                name: entry,
                fileCount: health.fileCount,
                summary: summary,
                healthLabel: health.label,
                healthIssues: issuesText
            ))
        }
        return results
    }

    private func moveFolder(_ name: String, from source: PARACategory, to target: PARACategory) {
        let mover = PARAMover(pkmRoot: appState.pkmRootPath)
        do {
            let count = try mover.moveFolder(name: name, from: source, to: target)
            statusMessage = "'\(name)' -> \(target.displayName) (\(count)개 노트 갱신)"
            loadFolders()
            clearStatusAfterDelay()
        } catch {
            statusMessage = error.localizedDescription
            clearStatusAfterDelay()
        }
    }

    private func createProject() {
        let name = newProjectName.trimmingCharacters(in: .whitespaces)
        guard !name.isEmpty else { return }

        let manager = ProjectManager(pkmRoot: appState.pkmRootPath)
        do {
            _ = try manager.createProject(name: name, summary: newProjectSummary)
            statusMessage = "'\(name)' 프로젝트 생성됨"
            newProjectName = ""
            newProjectSummary = ""
            showNewProject = false
            loadFolders()
            clearStatusAfterDelay()
        } catch {
            statusMessage = error.localizedDescription
            clearStatusAfterDelay()
        }
    }

    private func completeProject(_ name: String) {
        let manager = ProjectManager(pkmRoot: appState.pkmRootPath)
        do {
            let count = try manager.completeProject(name: name)
            statusMessage = "'\(name)' 완료 -> 아카이브 (\(count)개 노트 갱신)"
            loadFolders()
            clearStatusAfterDelay()
        } catch {
            statusMessage = error.localizedDescription
            clearStatusAfterDelay()
        }
    }

    private func reactivateProject(_ name: String) {
        let manager = ProjectManager(pkmRoot: appState.pkmRootPath)
        do {
            let count = try manager.reactivateProject(name: name)
            statusMessage = "'\(name)' 재활성화됨 (\(count)개 노트 갱신)"
            loadFolders()
            clearStatusAfterDelay()
        } catch {
            statusMessage = error.localizedDescription
            clearStatusAfterDelay()
        }
    }

    private func performDelete(name: String, category: PARACategory) {
        let mover = PARAMover(pkmRoot: appState.pkmRootPath)
        do {
            try mover.deleteFolder(name: name, category: category)
            statusMessage = "'\(name)' 삭제됨 (휴지통)"
            loadFolders()
            clearStatusAfterDelay()
        } catch {
            statusMessage = error.localizedDescription
            clearStatusAfterDelay()
        }
    }

    private func mergeFolder(source: String, into target: String, category: PARACategory) {
        let mover = PARAMover(pkmRoot: appState.pkmRootPath)
        do {
            let count = try mover.mergeFolder(source: source, into: target, category: category)
            statusMessage = "'\(source)' -> '\(target)' 병합 (\(count)개 파일)"
            loadFolders()
            clearStatusAfterDelay()
        } catch {
            statusMessage = error.localizedDescription
            clearStatusAfterDelay()
        }
    }

    private func startReorganize(category: PARACategory, subfolder: String) {
        appState.reorganizeCategory = category
        appState.reorganizeSubfolder = subfolder
        Task {
            await appState.startReorganizing()
        }
    }

    private func openInFinder(_ name: String, category: PARACategory) {
        let basePath = PKMPathManager(root: appState.pkmRootPath).paraPath(for: category)
        let folderPath = (basePath as NSString).appendingPathComponent(name)
        NSWorkspace.shared.open(URL(fileURLWithPath: folderPath))
    }

    private func clearStatusAfterDelay() {
        Task {
            try? await Task.sleep(nanoseconds: 3_000_000_000)
            await MainActor.run { statusMessage = "" }
        }
    }
}

// MARK: - Data Model

struct FolderEntry: Identifiable {
    var id: String { name }
    let name: String
    let fileCount: Int
    let summary: String
    let healthLabel: String
    let healthIssues: String
}

// MARK: - Folder Row

private struct PARAFolderRow: View {
    let name: String
    let fileCount: Int
    let summary: String
    let category: PARACategory
    let healthLabel: String
    let healthIssues: String
    @State private var isHovered = false

    private var healthColor: Color {
        switch healthLabel {
        case "urgent": return .red
        case "attention": return .orange
        default: return .green
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 8) {
                Image(systemName: "folder")
                    .font(.system(size: 13))
                    .foregroundColor(categoryColor)
                    .frame(width: 16)

                VStack(alignment: .leading, spacing: 1) {
                    Text(name)
                        .font(.caption)
                        .fontWeight(.medium)
                        .lineLimit(1)
                    if !summary.isEmpty {
                        Text(summary)
                            .font(.caption2)
                            .foregroundColor(.secondary)
                            .lineLimit(1)
                    }
                }

                Spacer()

                // Health indicator dot
                if healthLabel != "good" {
                    Circle()
                        .fill(healthColor)
                        .frame(width: 6, height: 6)
                }

                Text("\(fileCount)")
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(
                        Capsule()
                            .fill(Color.secondary.opacity(0.12))
                    )
            }

            // Health issues text (shown on hover)
            if healthLabel != "good" && isHovered && !healthIssues.isEmpty {
                Text(healthIssues)
                    .font(.caption2)
                    .foregroundColor(healthColor)
                    .padding(.leading, 24)
                    .padding(.top, 2)
                    .transition(.opacity)
            }
        }
        .padding(.vertical, 4)
        .padding(.horizontal, 8)
        .background(
            RoundedRectangle(cornerRadius: 6)
                .fill(isHovered ? Color.primary.opacity(0.04) : Color.primary.opacity(0.02))
        )
        .animation(.easeOut(duration: 0.12), value: isHovered)
        .onHover { isHovered = $0 }
    }

    private var categoryColor: Color {
        switch category {
        case .project: return .blue
        case .area: return .purple
        case .resource: return .orange
        case .archive: return .gray
        }
    }
}
