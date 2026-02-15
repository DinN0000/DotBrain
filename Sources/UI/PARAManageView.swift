import SwiftUI

struct PARAManageView: View {
    @EnvironmentObject var appState: AppState
    @State private var folderMap: [PARACategory: [(name: String, fileCount: Int, summary: String)]] = [:]
    @State private var showNewProject = false
    @State private var newProjectName = ""
    @State private var newProjectSummary = ""
    @State private var statusMessage = ""
    @State private var isLoading = true

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
            }
        }
        .onAppear { loadFolders() }
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
    private func folderList(_ folders: [(name: String, fileCount: Int, summary: String)], category: PARACategory) -> some View {
        ForEach(folders, id: \.name) { folder in
            PARAFolderRow(
                name: folder.name,
                fileCount: folder.fileCount,
                summary: folder.summary,
                category: category
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

                // Auto-reorganize
                Button {
                    startReorganize(category: category, subfolder: folder.name)
                } label: {
                    Label("자동 정리", systemImage: "sparkles")
                }

                Divider()

                // Open in Finder
                Button {
                    openInFinder(folder.name, category: category)
                } label: {
                    Label("Finder에서 열기", systemImage: "folder")
                }
            }
        }
    }

    // MARK: - Actions

    private func loadFolders() {
        isLoading = true
        let root = appState.pkmRootPath
        Task.detached(priority: .utility) {
            let mover = PARAMover(pkmRoot: root)
            var map: [PARACategory: [(name: String, fileCount: Int, summary: String)]] = [:]
            for cat in PARACategory.allCases {
                map[cat] = mover.listFolders(in: cat)
            }
            await MainActor.run {
                folderMap = map
                isLoading = false
            }
        }
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

// MARK: - Folder Row

private struct PARAFolderRow: View {
    let name: String
    let fileCount: Int
    let summary: String
    let category: PARACategory
    @State private var isHovered = false

    var body: some View {
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
