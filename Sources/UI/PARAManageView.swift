import SwiftUI

struct PARAManageView: View {
    @EnvironmentObject var appState: AppState
    @State private var folderMap: [PARACategory: [FolderEntry]] = [:]
    @State private var newFolderCategory: PARACategory?
    @State private var newFolderName = ""
    @State private var statusMessage = ""
    @State private var isLoading = true
    @State private var deleteTarget: (name: String, category: PARACategory)?
    @State private var renameTarget: (name: String, category: PARACategory)?
    @State private var renameNewName = ""

    var body: some View {
        VStack(spacing: 0) {
            BreadcrumbView(current: .paraManage)

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
                                    Text("+ 버튼으로 폴더를 생성하세요")
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
        .alert("이름 변경", isPresented: .init(
            get: { renameTarget != nil },
            set: { if !$0 { renameTarget = nil } }
        )) {
            TextField("새 이름", text: $renameNewName)
            Button("변경") {
                if let target = renameTarget {
                    performRename(oldName: target.name, newName: renameNewName, category: target.category)
                }
            }
            Button("취소", role: .cancel) {}
        } message: {
            if let target = renameTarget {
                Text("'\(target.name)' 폴더의 새 이름을 입력하세요.")
            }
        }
    }

    // MARK: - Category Section

    @ViewBuilder
    private func categorySection(_ category: PARACategory) -> some View {
        let folders = folderMap[category] ?? []

        if category == .archive && !folders.isEmpty {
            DisclosureGroup {
                newFolderForm(category: category)
                folderList(folders, category: category)
            } label: {
                categoryHeader(category, count: folders.count)
            }
            .padding(.top, 8)
        } else {
            VStack(alignment: .leading, spacing: 0) {
                categoryHeader(category, count: folders.count)
                    .padding(.vertical, 6)
                newFolderForm(category: category)
                folderList(folders, category: category)
            }
            .padding(.top, 8)
        }
    }

    private func categoryHeader(_ category: PARACategory, count: Int) -> some View {
        CategoryHeaderView(
            category: category,
            count: count,
            onTap: {
                withAnimation(.easeOut(duration: 0.15)) {
                    if newFolderCategory == category {
                        newFolderCategory = nil
                        newFolderName = ""
                    } else {
                        newFolderCategory = category
                        newFolderName = ""
                    }
                }
            }
        )
    }

    @ViewBuilder
    private func newFolderForm(category: PARACategory) -> some View {
        if newFolderCategory == category {
            HStack(spacing: 6) {
                TextField("폴더 이름", text: $newFolderName)
                    .textFieldStyle(.roundedBorder)
                    .font(.caption)
                    .onSubmit { createFolder(in: category) }
                Button(action: { createFolder(in: category) }) {
                    Image(systemName: "plus.circle.fill")
                        .foregroundColor(.accentColor)
                }
                .buttonStyle(.plain)
                .disabled(newFolderName.trimmingCharacters(in: .whitespaces).isEmpty)
            }
            .padding(.vertical, 4)
            .padding(.horizontal, 8)
            .transition(.opacity.combined(with: .move(edge: .top)))
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
            .contentShape(Rectangle())
            .onTapGesture {
                showFolderMenu(folder: folder, category: category)
            }
            .contextMenu {
                folderMenuContent(folder: folder, category: category)
            }
        }
    }

    @ViewBuilder
    private func folderMenuContent(folder: FolderEntry, category: PARACategory) -> some View {
        ForEach(PARACategory.allCases.filter { $0 != category }, id: \.self) { target in
            Button {
                moveFolder(folder.name, from: category, to: target)
            } label: {
                Label("\(target.displayName)(으)로 이동", systemImage: target.icon)
            }
        }

        Divider()

        if category == .project {
            Button {
                completeProject(folder.name)
            } label: {
                Label("프로젝트 완료", systemImage: "checkmark.circle")
            }
        }

        if category == .archive {
            Button {
                reactivateProject(folder.name)
            } label: {
                Label("재활성화", systemImage: "arrow.uturn.left.circle")
            }
        }

        Button {
            startReorganize(category: category, subfolder: folder.name)
        } label: {
            Label("자동 정리", systemImage: "sparkles")
        }

        Divider()

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

        Button {
            renameTarget = (name: folder.name, category: category)
            renameNewName = folder.name
        } label: {
            Label("이름 변경", systemImage: "pencil")
        }

        Button {
            openInFinder(folder.name, category: category)
        } label: {
            Label("Finder에서 열기", systemImage: "folder")
        }

        Divider()

        Button(role: .destructive) {
            deleteTarget = (name: folder.name, category: category)
        } label: {
            Label("폴더 삭제", systemImage: "trash")
        }
    }

    private func showFolderMenu(folder: FolderEntry, category: PARACategory) {
        let menu = NSMenu()

        for target in PARACategory.allCases where target != category {
            addMenuItem(to: menu, title: "\(target.displayName)(으)로 이동", icon: target.icon) {
                self.moveFolder(folder.name, from: category, to: target)
            }
        }

        menu.addItem(.separator())

        if category == .project {
            addMenuItem(to: menu, title: "프로젝트 완료", icon: "checkmark.circle") {
                completeProject(folder.name)
            }
        }
        if category == .archive {
            addMenuItem(to: menu, title: "재활성화", icon: "arrow.uturn.left.circle") {
                reactivateProject(folder.name)
            }
        }

        addMenuItem(to: menu, title: "자동 정리", icon: "sparkles") {
            startReorganize(category: category, subfolder: folder.name)
        }

        menu.addItem(.separator())

        let siblings = (folderMap[category] ?? []).filter { $0.name != folder.name }
        if !siblings.isEmpty {
            let mergeItem = NSMenuItem(title: "다른 폴더에 병합", action: nil, keyEquivalent: "")
            mergeItem.image = NSImage(systemSymbolName: "arrow.triangle.merge", accessibilityDescription: nil)
            let subMenu = NSMenu()
            for sibling in siblings {
                addMenuItem(to: subMenu, title: sibling.name, icon: nil) {
                    self.mergeFolder(source: folder.name, into: sibling.name, category: category)
                }
            }
            mergeItem.submenu = subMenu
            menu.addItem(mergeItem)
        }

        addMenuItem(to: menu, title: "이름 변경", icon: "pencil") {
            renameTarget = (name: folder.name, category: category)
            renameNewName = folder.name
        }

        addMenuItem(to: menu, title: "Finder에서 열기", icon: "folder") {
            openInFinder(folder.name, category: category)
        }

        menu.addItem(.separator())

        addMenuItem(to: menu, title: "폴더 삭제", icon: "trash") {
            deleteTarget = (name: folder.name, category: category)
        }

        // Show at mouse location
        menu.popUp(positioning: nil, at: NSEvent.mouseLocation, in: nil)
    }

    private func addMenuItem(to menu: NSMenu, title: String, icon: String?, action: @escaping () -> Void) {
        let item = FolderMenuItem(title: title, action: #selector(FolderMenuItem.invoke), keyEquivalent: "")
        item.target = item
        item.callback = action
        if let icon {
            item.image = NSImage(systemSymbolName: icon, accessibilityDescription: nil)
        }
        menu.addItem(item)
    }

    // MARK: - Actions

    private func loadFolders() {
        let showLoading = folderMap.values.allSatisfy({ $0.isEmpty })
        if showLoading { isLoading = true }
        let root = appState.pkmRootPath
        Task {
            var result: [PARACategory: [FolderEntry]] = [:]
            for cat in PARACategory.allCases {
                result[cat] = await Task.detached(priority: .utility) {
                    Self.scanCategory(cat, pkmRoot: root)
                }.value
            }
            folderMap = result
            isLoading = false
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
            refreshMOC(folderName: name, category: target)
            refreshCategoryMOC(source)
        } catch {
            statusMessage = error.localizedDescription
            clearStatusAfterDelay()
        }
    }

    private func createFolder(in category: PARACategory) {
        let name = newFolderName.trimmingCharacters(in: .whitespaces)
        guard !name.isEmpty else { return }

        let fm = FileManager.default
        let pathManager = PKMPathManager(root: appState.pkmRootPath)
        let basePath = pathManager.paraPath(for: category)
        let folderPath = (basePath as NSString).appendingPathComponent(name)

        guard !fm.fileExists(atPath: folderPath) else {
            statusMessage = "'\(name)' 이미 존재합니다"
            clearStatusAfterDelay()
            return
        }

        do {
            try fm.createDirectory(atPath: folderPath, withIntermediateDirectories: true)
            // Create index note
            let indexContent = FrontmatterWriter.createIndexNote(
                folderName: name, para: category
            )
            let indexPath = (folderPath as NSString).appendingPathComponent("\(name).md")
            try indexContent.write(toFile: indexPath, atomically: true, encoding: .utf8)

            statusMessage = "'\(name)' 폴더 생성됨"
            newFolderName = ""
            newFolderCategory = nil
            loadFolders()
            clearStatusAfterDelay()
            refreshCategoryMOC(category)
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
            refreshCategoryMOC(.project)
            refreshMOC(folderName: name, category: .archive)
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
            refreshCategoryMOC(.archive)
            refreshMOC(folderName: name, category: .project)
        } catch {
            statusMessage = error.localizedDescription
            clearStatusAfterDelay()
        }
    }

    private func performRename(oldName: String, newName: String, category: PARACategory) {
        let trimmed = newName.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty, trimmed != oldName else { return }
        let mover = PARAMover(pkmRoot: appState.pkmRootPath)
        do {
            let count = try mover.renameFolder(oldName: oldName, newName: trimmed, category: category)
            statusMessage = "'\(oldName)' -> '\(trimmed)' (\(count)개 노트 갱신)"
            loadFolders()
            clearStatusAfterDelay()
            refreshMOC(folderName: trimmed, category: category)
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
            refreshCategoryMOC(category)
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
            refreshMOC(folderName: target, category: category)
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

    private func refreshMOC(folderName: String, category: PARACategory) {
        let root = appState.pkmRootPath
        Task {
            let moc = MOCGenerator(pkmRoot: root)
            let pathManager = PKMPathManager(root: root)
            let basePath = pathManager.paraPath(for: category)
            let folderPath = (basePath as NSString).appendingPathComponent(folderName)
            try? await moc.generateMOC(folderPath: folderPath, folderName: folderName, para: category)
            try? await moc.generateCategoryRootMOC(basePath: basePath, para: category)
        }
    }

    private func refreshCategoryMOC(_ category: PARACategory) {
        let root = appState.pkmRootPath
        Task {
            let moc = MOCGenerator(pkmRoot: root)
            let basePath = PKMPathManager(root: root).paraPath(for: category)
            try? await moc.generateCategoryRootMOC(basePath: basePath, para: category)
        }
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

// MARK: - Category Header

private struct CategoryHeaderView: View {
    let category: PARACategory
    let count: Int
    let onTap: () -> Void
    @State private var isHovered = false

    var body: some View {
        HStack(spacing: 4) {
            Image(systemName: category.icon)
                .font(.caption)
                .foregroundColor(isHovered ? .primary : .secondary)
            Text(category.displayName)
                .font(.caption)
                .fontWeight(.semibold)
                .foregroundColor(isHovered ? .primary : .secondary)
            if count > 0 {
                Text("(\(count))")
                    .font(.caption2)
                    .foregroundColor(.secondary.opacity(0.7))
            }
        }
        .padding(.vertical, 2)
        .padding(.horizontal, 4)
        .background(
            RoundedRectangle(cornerRadius: 4)
                .fill(isHovered ? Color.primary.opacity(0.06) : Color.clear)
        )
        .contentShape(Rectangle())
        .onTapGesture { onTap() }
        .onHover { isHovered = $0 }
        .animation(.easeOut(duration: 0.12), value: isHovered)
    }
}

// MARK: - NSMenuItem with Closure

private class FolderMenuItem: NSMenuItem {
    var callback: (() -> Void)?

    @objc func invoke() {
        callback?()
    }
}
