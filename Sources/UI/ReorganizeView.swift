import SwiftUI

struct ReorganizeView: View {
    @EnvironmentObject var appState: AppState
    @State private var selectedCategory: PARACategory?
    @State private var selectedSubfolder: String?
    @State private var isButtonHovered = false

    /// All PARA categories
    private let paraCategories: [PARACategory] = [.project, .area, .resource, .archive]

    private var subfolderMap: [PARACategory: [(name: String, fileCount: Int)]] {
        let pathManager = PKMPathManager(root: appState.pkmRootPath)
        let fm = FileManager.default
        var map: [PARACategory: [(name: String, fileCount: Int)]] = [:]

        for cat in paraCategories {
            let basePath = pathManager.paraPath(for: cat)
            guard let entries = try? fm.contentsOfDirectory(atPath: basePath) else {
                map[cat] = []
                continue
            }

            var folders: [(name: String, fileCount: Int)] = []
            for entry in entries.sorted() {
                guard !entry.hasPrefix("."), !entry.hasPrefix("_") else { continue }
                let fullPath = (basePath as NSString).appendingPathComponent(entry)
                var isDir: ObjCBool = false
                guard fm.fileExists(atPath: fullPath, isDirectory: &isDir), isDir.boolValue else { continue }

                // Count all content files recursively (exclude hidden, _-prefixed, and index notes)
                let fileCount = countFilesRecursively(at: fullPath, folderName: entry, fm: fm)

                folders.append((name: entry, fileCount: fileCount))
            }
            map[cat] = folders
        }

        return map
    }

    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                HoverTextLink(label: "뒤로", color: .secondary) {
                    appState.currentScreen = .inbox
                }

                Spacer()

                Text("폴더 정리")
                    .font(.headline)

                Spacer()

                // Spacer to balance the back button
                Text("뒤로")
                    .font(.caption)
                    .hidden()
            }
            .padding()

            Divider()

            // Folder list
            ScrollView {
                LazyVStack(spacing: 0) {
                    ForEach(paraCategories, id: \.self) { category in
                        let folders = subfolderMap[category] ?? []
                        if !folders.isEmpty {
                            categorySection(category: category, folders: folders)
                        }
                    }

                    if subfolderMap.values.allSatisfy({ $0.isEmpty }) {
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
    }

    /// Recursively count content files inside a folder
    private func countFilesRecursively(at path: String, folderName: String, fm: FileManager) -> Int {
        guard let enumerator = fm.enumerator(atPath: path) else { return 0 }
        var count = 0
        while let relativePath = enumerator.nextObject() as? String {
            let fullPath = (path as NSString).appendingPathComponent(relativePath)
            var isDir: ObjCBool = false
            guard fm.fileExists(atPath: fullPath, isDirectory: &isDir), !isDir.boolValue else { continue }
            let fileName = (fullPath as NSString).lastPathComponent
            guard !fileName.hasPrefix("."), !fileName.hasPrefix("_") else { continue }
            // Skip index/placeholder files
            let baseName = (fileName as NSString).deletingPathExtension
            let parentDirName = ((fullPath as NSString).deletingLastPathComponent as NSString).lastPathComponent
            if baseName == parentDirName || baseName == folderName { continue }
            count += 1
        }
        return count
    }

    // MARK: - Category Section

    @ViewBuilder
    private func categorySection(category: PARACategory, folders: [(name: String, fileCount: Int)]) -> some View {
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

            ForEach(folders, id: \.name) { folder in
                FolderRow(
                    name: folder.name,
                    fileCount: folder.fileCount,
                    isSelected: selectedCategory == category && selectedSubfolder == folder.name
                ) {
                    selectedCategory = category
                    selectedSubfolder = folder.name
                }
            }
        }
    }
}

// MARK: - Folder Row

private struct FolderRow: View {
    let name: String
    let fileCount: Int
    let isSelected: Bool
    let action: () -> Void
    @State private var isHovered = false

    var body: some View {
        Button(action: action) {
            HStack {
                Image(systemName: "folder")
                    .font(.system(size: 13))
                    .foregroundColor(isSelected ? .accentColor : .primary.opacity(0.6))

                Text(name)
                    .font(.system(.body, design: .monospaced))
                    .lineLimit(1)

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
            .padding(.vertical, 6)
            .padding(.horizontal, 8)
            .background(
                RoundedRectangle(cornerRadius: 6)
                    .fill(isSelected
                        ? Color.accentColor.opacity(0.12)
                        : (isHovered ? Color.primary.opacity(0.04) : Color.clear))
            )
        }
        .buttonStyle(.plain)
        .animation(.easeOut(duration: 0.12), value: isHovered)
        .animation(.easeOut(duration: 0.12), value: isSelected)
        .onHover { isHovered = $0 }
    }
}
