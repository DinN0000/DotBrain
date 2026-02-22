import SwiftUI

struct PARAManageView: View {
    @EnvironmentObject var appState: AppState
    @State private var folderMap: [PARACategory: [FolderEntry]] = [:]
    @State private var newFolderCategory: PARACategory?
    @State private var newFolderName = ""
    @State private var statusMessage = ""
    @State private var isStatusError = false
    @State private var isLoading = true
    @State private var deleteTarget: (name: String, category: PARACategory)?
    @State private var renameTarget: (name: String, category: PARACategory)?
    @State private var renameNewName = ""
    @State private var loadTask: Task<Void, Never>?
    @State private var statusClearTask: Task<Void, Never>?

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
                                    .foregroundColor(isStatusError ? .red : .green)
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
                            Task { @MainActor in
                                try? await Task.sleep(for: .milliseconds(100))
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
                category: category
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
        if let event = NSApp.currentEvent,
           let view = NSApp.keyWindow?.contentView {
            NSMenu.popUpContextMenu(menu, with: event, for: view)
        } else {
            menu.popUp(positioning: nil, at: NSEvent.mouseLocation, in: nil)
        }
    }

    private func addMenuItem(to menu: NSMenu, title: String, icon: String?, action: @escaping () -> Void) {
        let item = ClosureMenuItem(title: title, action: #selector(ClosureMenuItem.invoke), keyEquivalent: "")
        item.target = item
        item.callback = action
        if let icon {
            item.image = NSImage(systemSymbolName: icon, accessibilityDescription: nil)
        }
        menu.addItem(item)
    }

    // MARK: - Actions

    private func loadFolders() {
        loadTask?.cancel()
        let showLoading = folderMap.values.allSatisfy({ $0.isEmpty })
        if showLoading { isLoading = true }
        let root = appState.pkmRootPath
        loadTask = Task.detached(priority: .utility) {
            var result: [PARACategory: [FolderEntry]] = [:]
            await withTaskGroup(of: (PARACategory, [FolderEntry]).self) { group in
                for cat in PARACategory.allCases {
                    group.addTask { (cat, Self.scanCategory(cat, pkmRoot: root)) }
                }
                for await (cat, entries) in group {
                    result[cat] = entries
                }
            }
            guard !Task.isCancelled else { return }
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

            // Count .md files
            var mdCount = 0
            if let files = try? fm.contentsOfDirectory(atPath: fullPath) {
                for file in files {
                    if file.hasSuffix(".md"), !file.hasPrefix("."), !file.hasPrefix("_") {
                        mdCount += 1
                    }
                }
            }

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
                fileCount: mdCount,
                summary: summary
            ))
        }
        return results
    }

    private func moveFolder(_ name: String, from source: PARACategory, to target: PARACategory) {
        let mover = PARAMover(pkmRoot: appState.pkmRootPath)
        do {
            let count = try mover.moveFolder(name: name, from: source, to: target)
            isStatusError = false
            statusMessage = "'\(name)' -> \(target.displayName) (\(count)개 노트 갱신)"
            loadFolders()
            clearStatusAfterDelay()
            refreshIndex(folderName: name, category: target)
            refreshCategoryIndex(source)
        } catch {
            isStatusError = true
            statusMessage = error.localizedDescription
            clearStatusAfterDelay()
        }
    }

    private func createFolder(in category: PARACategory) {
        let raw = newFolderName.trimmingCharacters(in: .whitespaces)
        // Sanitize: strip path separators, .., null bytes, enforce 255-char limit
        let name = raw.components(separatedBy: "/")
            .filter { $0 != ".." && $0 != "." && !$0.isEmpty }
            .first.map { String($0.replacingOccurrences(of: "\0", with: "").prefix(255)) } ?? ""
        guard !name.isEmpty else { return }

        let fm = FileManager.default
        let pathManager = PKMPathManager(root: appState.pkmRootPath)
        let basePath = pathManager.paraPath(for: category)
        let folderPath = (basePath as NSString).appendingPathComponent(name)

        guard pathManager.isPathSafe(folderPath) else {
            isStatusError = true
            statusMessage = "잘못된 폴더 이름입니다"
            clearStatusAfterDelay()
            return
        }

        guard !fm.fileExists(atPath: folderPath) else {
            isStatusError = true
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

            isStatusError = false
            statusMessage = "'\(name)' 폴더 생성됨"
            newFolderName = ""
            newFolderCategory = nil
            loadFolders()
            clearStatusAfterDelay()
            refreshCategoryIndex(category)
        } catch {
            isStatusError = true
            statusMessage = error.localizedDescription
            clearStatusAfterDelay()
        }
    }

    private func completeProject(_ name: String) {
        let manager = ProjectManager(pkmRoot: appState.pkmRootPath)
        do {
            let count = try manager.completeProject(name: name)
            isStatusError = false
            statusMessage = "'\(name)' 완료 -> 아카이브 (\(count)개 노트 갱신)"
            loadFolders()
            clearStatusAfterDelay()
            refreshCategoryIndex(.project)
            refreshIndex(folderName: name, category: .archive)
        } catch {
            isStatusError = true
            statusMessage = error.localizedDescription
            clearStatusAfterDelay()
        }
    }

    private func reactivateProject(_ name: String) {
        let manager = ProjectManager(pkmRoot: appState.pkmRootPath)
        do {
            let count = try manager.reactivateProject(name: name)
            isStatusError = false
            statusMessage = "'\(name)' 재활성화됨 (\(count)개 노트 갱신)"
            loadFolders()
            clearStatusAfterDelay()
            refreshCategoryIndex(.archive)
            refreshIndex(folderName: name, category: .project)
        } catch {
            isStatusError = true
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
            isStatusError = false
            statusMessage = "'\(oldName)' -> '\(trimmed)' (\(count)개 노트 갱신)"
            loadFolders()
            clearStatusAfterDelay()
            refreshIndex(folderName: trimmed, category: category)
            refreshCategoryIndex(category)
        } catch {
            isStatusError = true
            statusMessage = error.localizedDescription
            clearStatusAfterDelay()
        }
    }

    private func performDelete(name: String, category: PARACategory) {
        let mover = PARAMover(pkmRoot: appState.pkmRootPath)
        do {
            try mover.deleteFolder(name: name, category: category)
            isStatusError = false
            statusMessage = "'\(name)' 삭제됨 (휴지통)"
            loadFolders()
            clearStatusAfterDelay()
            refreshCategoryIndex(category)
        } catch {
            isStatusError = true
            statusMessage = error.localizedDescription
            clearStatusAfterDelay()
        }
    }

    private func mergeFolder(source: String, into target: String, category: PARACategory) {
        let mover = PARAMover(pkmRoot: appState.pkmRootPath)
        do {
            let count = try mover.mergeFolder(source: source, into: target, category: category)
            isStatusError = false
            statusMessage = "'\(source)' -> '\(target)' 병합 (\(count)개 파일)"
            loadFolders()
            clearStatusAfterDelay()
            refreshIndex(folderName: target, category: category)
            refreshCategoryIndex(category)
        } catch {
            isStatusError = true
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
        let safeURL = URL(fileURLWithPath: folderPath).resolvingSymlinksInPath()
        NSWorkspace.shared.open(safeURL)
    }

    private func refreshIndex(folderName: String, category: PARACategory) {
        let root = appState.pkmRootPath
        Task.detached(priority: .utility) {
            let pathManager = PKMPathManager(root: root)
            let basePath = pathManager.paraPath(for: category)
            let folderPath = (basePath as NSString).appendingPathComponent(folderName)
            let indexGenerator = NoteIndexGenerator(pkmRoot: root)
            await indexGenerator.updateForFolders([folderPath])
        }
    }

    private func refreshCategoryIndex(_ category: PARACategory) {
        let root = appState.pkmRootPath
        Task.detached(priority: .utility) {
            let pathManager = PKMPathManager(root: root)
            let basePath = pathManager.paraPath(for: category)
            let fm = FileManager.default
            guard let folders = try? fm.contentsOfDirectory(atPath: basePath) else { return }
            var folderPaths: Set<String> = []
            for folder in folders {
                guard !folder.hasPrefix("."), !folder.hasPrefix("_") else { continue }
                let folderPath = (basePath as NSString).appendingPathComponent(folder)
                var isDir: ObjCBool = false
                if fm.fileExists(atPath: folderPath, isDirectory: &isDir), isDir.boolValue {
                    folderPaths.insert(folderPath)
                }
            }
            let indexGenerator = NoteIndexGenerator(pkmRoot: root)
            await indexGenerator.updateForFolders(folderPaths)
        }
    }

    private func clearStatusAfterDelay() {
        statusClearTask?.cancel()
        statusClearTask = Task {
            try? await Task.sleep(for: .seconds(3))
            guard !Task.isCancelled else { return }
            statusMessage = ""
        }
    }
}

// MARK: - Data Model

struct FolderEntry: Identifiable {
    var id: String { name }
    let name: String
    let fileCount: Int
    let summary: String
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
                .foregroundColor(category.color)
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

