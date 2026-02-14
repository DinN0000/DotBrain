import SwiftUI

struct ReorganizeView: View {
    @EnvironmentObject var appState: AppState
    @State private var selectedCategory: PARACategory?
    @State private var selectedSubfolder: String?
    @State private var isButtonHovered = false
    @State private var folderMap: [PARACategory: [FolderInfo]] = [:]
    @State private var isLoading = true

    struct FolderInfo: Identifiable {
        var id: String { name }
        let name: String
        let fileCount: Int
        let healthLabel: String // "good", "attention", "urgent"
        let healthIssues: String // tooltip text for health indicator
    }

    private let paraCategories: [PARACategory] = [.project, .area, .resource, .archive]

    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                Button(action: { appState.currentScreen = .inbox }) {
                    Image(systemName: "chevron.left")
                }
                .buttonStyle(.plain)

                Text("폴더 정리")
                    .font(.headline)

                Spacer()
            }
            .padding()

            Divider()

            // Folder list
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
                        ForEach(paraCategories, id: \.self) { category in
                            let folders = folderMap[category] ?? []
                            if !folders.isEmpty {
                                categorySection(category: category, folders: folders)
                            }
                        }

                        if folderMap.values.allSatisfy({ ($0).isEmpty }) {
                            VStack(spacing: 8) {
                                Text("정리할 폴더가 없습니다")
                                    .font(.subheadline)
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

            Divider()

            // Start button
            HStack {
                if let cat = selectedCategory, let folder = selectedSubfolder {
                    Text("\(cat.displayName)/\(folder)")
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .lineLimit(1)
                }

                Spacer()

                Button(action: {
                    guard let cat = selectedCategory, let folder = selectedSubfolder else { return }
                    appState.reorganizeCategory = cat
                    appState.reorganizeSubfolder = folder
                    Task {
                        await appState.startReorganizing()
                    }
                }) {
                    HStack {
                        Image(systemName: "sparkles")
                        Text("정리 시작")
                    }
                    .padding(.vertical, 4)
                    .padding(.horizontal, 12)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.regular)
                .disabled(selectedSubfolder == nil)
                .scaleEffect(isButtonHovered && selectedSubfolder != nil ? 1.03 : 1.0)
                .animation(.easeOut(duration: 0.12), value: isButtonHovered)
                .onHover { isButtonHovered = $0 }
            }
            .padding()
        }
        .onAppear {
            // Pre-select folder if navigated from ResultsView
            if let cat = appState.reorganizeCategory, let sub = appState.reorganizeSubfolder {
                selectedCategory = cat
                selectedSubfolder = sub
            }
            loadFolders()
        }
    }

    // MARK: - Load Folders

    private func loadFolders() {
        isLoading = true
        let root = appState.pkmRootPath
        let cats = paraCategories
        Task.detached(priority: .utility) {
            let map = ReorganizeScanner.scan(pkmRoot: root, categories: cats)
            await MainActor.run {
                folderMap = map
                isLoading = false
            }
        }
    }

    // MARK: - Category Section

    @ViewBuilder
    private func categorySection(category: PARACategory, folders: [FolderInfo]) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 4) {
                Image(systemName: category.icon)
                    .font(.caption)
                    .foregroundColor(.secondary)
                Text(category.displayName)
                    .font(.caption)
                    .fontWeight(.semibold)
                    .foregroundColor(.secondary)
            }
            .padding(.vertical, 6)

            ForEach(folders) { folder in
                FolderRow(
                    name: folder.name,
                    fileCount: folder.fileCount,
                    healthLabel: folder.healthLabel,
                    healthIssues: folder.healthIssues,
                    isSelected: selectedCategory == category && selectedSubfolder == folder.name
                ) {
                    selectedCategory = category
                    selectedSubfolder = folder.name
                }
            }
        }
    }
}

// MARK: - Background Scanner (nonisolated)

private enum ReorganizeScanner {
    static func scan(
        pkmRoot: String,
        categories: [PARACategory]
    ) -> [PARACategory: [ReorganizeView.FolderInfo]] {
        let pathManager = PKMPathManager(root: pkmRoot)
        let fm = FileManager.default
        var map: [PARACategory: [ReorganizeView.FolderInfo]] = [:]

        for cat in categories {
            let basePath = pathManager.paraPath(for: cat)
            guard let entries = try? fm.contentsOfDirectory(atPath: basePath) else {
                map[cat] = []
                continue
            }

            var folders: [ReorganizeView.FolderInfo] = []
            for entry in entries.sorted() {
                guard !entry.hasPrefix("."), !entry.hasPrefix("_") else { continue }
                let fullPath = (basePath as NSString).appendingPathComponent(entry)
                var isDir: ObjCBool = false
                guard fm.fileExists(atPath: fullPath, isDirectory: &isDir), isDir.boolValue else { continue }

                let health = FolderHealthAnalyzer.analyze(
                    folderPath: fullPath, folderName: entry, category: cat
                )
                let issuesText = health.issues.map(\.localizedDescription).joined(separator: "\n")
                folders.append(ReorganizeView.FolderInfo(
                    name: entry,
                    fileCount: health.fileCount,
                    healthLabel: health.label,
                    healthIssues: issuesText
                ))
            }
            map[cat] = folders
        }

        return map
    }
}

// MARK: - Folder Row

private struct FolderRow: View {
    let name: String
    let fileCount: Int
    let healthLabel: String
    let healthIssues: String
    let isSelected: Bool
    let action: () -> Void
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
            HStack {
                Image(systemName: "folder")
                    .font(.system(size: 13))
                    .foregroundColor(isSelected ? .accentColor : .primary.opacity(0.6))

                Text(name)
                    .font(.system(.body, design: .monospaced))
                    .lineLimit(1)

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
                    .padding(.leading, 21)
                    .padding(.top, 2)
                    .transition(.opacity)
            }
        }
        .padding(.vertical, 6)
        .padding(.horizontal, 8)
        .background(
            RoundedRectangle(cornerRadius: 6)
                .fill(isSelected
                    ? Color.accentColor.opacity(0.12)
                    : (isHovered ? Color.primary.opacity(0.04) : Color.clear))
        )
        .contentShape(Rectangle())
        .onTapGesture { action() }
        .animation(.easeOut(duration: 0.15), value: isHovered)
        .animation(.easeOut(duration: 0.12), value: isSelected)
        .onHover { isHovered = $0 }
    }
}
