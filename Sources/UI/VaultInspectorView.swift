import SwiftUI

struct VaultInspectorView: View {
    @EnvironmentObject var appState: AppState

    @State private var folders: [FolderInfo] = []
    @State private var isLoading = true

    // Vault check state managed by AppState

    @State private var reorgChangedOnly = false

    private enum FlatItemKind {
        case header(PARACategory, Int)
        case folder(FolderInfo)
    }

    private struct FlatItem: Identifiable {
        let id: String
        let kind: FlatItemKind
    }

    private var flatItems: [FlatItem] {
        var items: [FlatItem] = []
        for category in PARACategory.allCases {
            let categoryFolders = folders.filter { $0.category == category }
            guard !categoryFolders.isEmpty else { continue }
            items.append(FlatItem(id: "header-\(category.rawValue)", kind: .header(category, categoryFolders.count)))
            for folder in categoryFolders {
                items.append(FlatItem(id: folder.id.uuidString, kind: .folder(folder)))
            }
        }
        return items
    }

    struct FolderInfo: Identifiable {
        let id = UUID()
        let name: String
        let path: String
        let category: PARACategory
        let fileCount: Int
        let modifiedCount: Int
        let newCount: Int
        let summary: String
        let healthLabel: String
        let healthIssues: String

        var healthRatio: Double {
            guard fileCount > 0 else { return 1.0 }
            return Double(fileCount - modifiedCount - newCount) / Double(fileCount)
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            BreadcrumbView(current: .vaultInspector)
            Divider()

            if appState.reorgPhase == .reviewPlan {
                reorgPlanReviewView
            } else {
                folderListView
            }
        }
        .onAppear { loadFolders() }
        .onChange(of: appState.vaultCheckResult) { result in
            if result != nil {
                // Delay to let SwiftUI settle after batch @Published updates
                Task { @MainActor in
                    try? await Task.sleep(for: .milliseconds(300))
                    loadFolders()
                }
            }
        }
        .onDisappear {
            // Reorg task continues in background — results persist in AppState
        }
    }

    // MARK: - Level 1: Folder List

    private var folderListView: some View {
        VStack(spacing: 0) {
            // Action buttons
            HStack(spacing: 8) {
                Button(action: { appState.startVaultCheck() }) {
                    VStack(spacing: 1) {
                        HStack(spacing: 4) {
                            Image(systemName: "stethoscope")
                                .font(.caption)
                            Text("자동 수리")
                                .font(.caption)
                        }
                        Text("메타 · 링크 · 태그")
                            .font(.system(size: 9))
                            .foregroundColor(.secondary)
                    }
                    .padding(.horizontal, 10)
                    .padding(.vertical, 5)
                }
                .buttonStyle(.bordered)
                .disabled(appState.isAnyTaskRunning)
                .help("깨진 링크, 누락 메타데이터, 태그 등 문제를 찾아 자동 복구")

                Button(action: { startFullReorg() }) {
                    VStack(spacing: 1) {
                        HStack(spacing: 4) {
                            Image(systemName: "arrow.triangle.2.circlepath")
                                .font(.caption)
                            Text("위치 제안")
                                .font(.caption)
                        }
                        Text("파일 위치 재배치")
                            .font(.system(size: 9))
                            .foregroundColor(.secondary)
                    }
                    .padding(.horizontal, 10)
                    .padding(.vertical, 5)
                }
                .buttonStyle(.bordered)
                .disabled(appState.isAnyTaskRunning)
                .help("AI가 파일을 분석해서 적절한 폴더를 제안")

                Spacer()
            }
            .padding(.horizontal)
            .padding(.vertical, 8)

            // Inline progress/result cards
            if appState.backgroundTaskName == "전체 점검" {
                taskProgressCard(
                    title: "자동 수리",
                    progress: appState.backgroundTaskProgress,
                    status: appState.backgroundTaskPhase,
                    onCancel: { appState.cancelBackgroundTask() }
                )
                .padding(.top, 4)
            }

            if let result = appState.vaultCheckResult {
                let hasIssues = result.brokenLinks > 0
                    || result.missingFrontmatter > 0
                    || result.missingPARA > 0
                vaultCheckResultCard(result)
                    .transition(.opacity)
                    .onAppear {
                        guard !hasIssues else { return }
                        Task { @MainActor in
                            try? await Task.sleep(for: .seconds(4))
                            guard appState.vaultCheckResult != nil else { return }
                            withAnimation(.easeOut(duration: 0.3)) {
                                appState.vaultCheckResult = nil
                            }
                        }
                    }
            }

            if appState.reorgPhase == .scanning || appState.reorgPhase == .executing {
                taskProgressCard(
                    title: appState.reorgPhase == .scanning ? "AI 스캔 중" : "위치 이동 중",
                    progress: appState.reorgProgress,
                    status: appState.reorgStatus,
                    onCancel: { resetReorg() }
                )
                .padding(.top, 4)
            }

            if appState.reorgPhase == .done {
                let hasErrors = appState.reorgResults.contains(where: \.isError)
                reorgResultCard
                    .padding(.top, 4)
                    .transition(.opacity)
                    .onAppear {
                        guard !hasErrors else { return }
                        Task { @MainActor in
                            try? await Task.sleep(for: .seconds(4))
                            guard appState.reorgPhase == .done else { return }
                            withAnimation(.easeOut(duration: 0.3)) {
                                resetReorg()
                            }
                        }
                    }
            }

            Spacer().frame(height: 8)
            Divider()

            // Folder list
            if isLoading {
                Spacer()
                ProgressView()
                Spacer()
            } else {
                let isBusy = appState.reorgPhase == .scanning || appState.reorgPhase == .executing
                ScrollView {
                    LazyVStack(spacing: 0) {
                        ForEach(flatItems) { item in
                            switch item.kind {
                            case .header(let category, let count):
                                HStack(spacing: 4) {
                                    Image(systemName: category.icon)
                                        .font(.caption)
                                        .foregroundColor(category.color)
                                    Text(category.displayName)
                                        .font(.caption)
                                        .fontWeight(.semibold)
                                    if count > 0 {
                                        Text("(\(count))")
                                            .font(.caption2)
                                            .foregroundColor(.secondary.opacity(0.7))
                                    }
                                    Spacer()
                                }
                                .padding(.vertical, 6)
                                .padding(.top, 8)
                                .contentShape(Rectangle())
                                .onTapGesture { showCategoryMenu(category) }
                            case .folder(let folder):
                                VaultFolderRow(folder: folder) {
                                    showFolderMenu(folder)
                                }
                            }
                        }
                    }
                    .padding(.horizontal)
                    .padding(.vertical, 8)
                }
                .disabled(isBusy)
                .opacity(isBusy ? 0.5 : 1.0)
            }
        }
    }

    // folderSection/folderContextMenu removed — flat LazyVStack for scroll performance

    // MARK: - Folder Menu (NSMenu popup, matching PARAManageView)

    private func showFolderMenu(_ folder: FolderInfo) {
        let menu = NSMenu()
        let changedCount = folder.modifiedCount + folder.newCount

        addMenuItem(
            to: menu,
            title: "위치 제안",
            icon: "arrow.triangle.2.circlepath"
        ) {
            // Smart default: changed files only if any, otherwise full folder
            if changedCount > 0 {
                self.startFolderReorg(folder)
            } else {
                self.startFolderFullReorg(folder)
            }
        }

        menu.addItem(.separator())

        addMenuItem(to: menu, title: "Finder에서 열기", icon: "folder") {
            self.openInFinder(folder)
        }

        menu.popUp(positioning: nil, at: NSEvent.mouseLocation, in: nil)
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

    private func showCategoryMenu(_ category: PARACategory) {
        let menu = NSMenu()
        addMenuItem(
            to: menu,
            title: "\(category.displayName) 전체 위치 제안",
            icon: "arrow.triangle.2.circlepath"
        ) {
            self.startCategoryReorg(category)
        }
        menu.popUp(positioning: nil, at: NSEvent.mouseLocation, in: nil)
    }

    private func openInFinder(_ folder: FolderInfo) {
        let safeURL = URL(fileURLWithPath: folder.path).resolvingSymlinksInPath()
        NSWorkspace.shared.open(safeURL)
    }

    // MARK: - Reorganize Plan Review (full-screen)

    private var reorgPlanReviewView: some View {
        let movableCount = appState.reorgAnalyses.filter(\.needsMove).count
        let selectedCount = appState.reorgAnalyses.filter { $0.isSelected && $0.needsMove }.count
        let allSelected: Bool = {
            let movable = appState.reorgAnalyses.filter(\.needsMove)
            return !movable.isEmpty && movable.allSatisfy(\.isSelected)
        }()

        return VStack(spacing: 0) {
            VStack(alignment: .leading, spacing: 4) {
                Label(
                    "\(movableCount)개 파일 이동 필요",
                    systemImage: "arrow.triangle.2.circlepath"
                )
                .font(.caption)
                .fontWeight(.medium)
                .foregroundColor(.accentColor)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal)
            .padding(.vertical, 8)

            Divider()

            ScrollView {
                LazyVStack(spacing: 0) {
                    ForEach(PARACategory.allCases, id: \.self) { category in
                        let categoryFiles = appState.reorgAnalyses.filter {
                            $0.needsMove && $0.recommended.para == category
                        }
                        if !categoryFiles.isEmpty {
                            reorgCategorySection(category: category, files: categoryFiles)
                        }
                    }

                    let unchangedCount = appState.reorgAnalyses.filter { !$0.needsMove }.count
                    if unchangedCount > 0 {
                        HStack(spacing: 4) {
                            Image(systemName: "checkmark.circle")
                                .font(.caption2)
                                .foregroundColor(.green)
                            Text("\(unchangedCount)개 파일은 현재 위치가 적절합니다")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                        .padding(.vertical, 8)
                        .padding(.horizontal)
                    }
                }
                .padding(.horizontal)
                .padding(.vertical, 8)
            }

            Divider()

            HStack {
                Toggle(isOn: Binding(
                    get: { allSelected },
                    set: { newValue in
                        for i in appState.reorgAnalyses.indices where appState.reorgAnalyses[i].needsMove {
                            appState.reorgAnalyses[i].isSelected = newValue
                        }
                    }
                )) {
                    Text("전체")
                        .font(.caption)
                }
                .toggleStyle(.checkbox)

                Spacer()

                Button("취소") { resetReorg() }
                    .font(.caption)
                    .buttonStyle(.plain)
                    .foregroundColor(.secondary)

                Button(action: { executeReorgPlan() }) {
                    HStack {
                        Image(systemName: "sparkles")
                        Text("실행")
                    }
                    .padding(.vertical, 4)
                    .padding(.horizontal, 12)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.regular)
                .disabled(selectedCount == 0)
            }
            .padding()
        }
    }

    @ViewBuilder
    private func reorgCategorySection(category: PARACategory, files: [VaultReorganizer.FileAnalysis]) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 6) {
                Image(systemName: "arrow.right.circle.fill")
                    .font(.caption)
                    .foregroundColor(.accentColor)
                Image(systemName: category.icon)
                    .font(.caption)
                    .foregroundColor(.secondary)
                Text(category.displayName)
                    .font(.caption)
                    .fontWeight(.semibold)
                Text("(\(files.count))")
                    .font(.caption2)
                    .foregroundColor(.secondary)
                Spacer()
            }
            .padding(.vertical, 8)
            .padding(.horizontal, 4)

            ForEach(files.indices, id: \.self) { idx in
                if let analysisIndex = appState.reorgAnalyses.firstIndex(where: {
                    $0.fileName == files[idx].fileName
                        && $0.currentCategory == files[idx].currentCategory
                        && $0.currentFolder == files[idx].currentFolder
                }) {
                    reorgFileRow(index: analysisIndex)
                }
            }
        }
    }

    private func reorgFileRow(index: Int) -> some View {
        HStack(spacing: 8) {
            Toggle(isOn: $appState.reorgAnalyses[index].isSelected) {
                EmptyView()
            }
            .toggleStyle(.checkbox)
            .labelsHidden()

            VStack(alignment: .leading, spacing: 3) {
                Text(appState.reorgAnalyses[index].fileName)
                    .font(.system(.body, design: .monospaced))
                    .lineLimit(1)

                if !appState.reorgAnalyses[index].recommended.summary.isEmpty {
                    Text(appState.reorgAnalyses[index].recommended.summary)
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .lineLimit(1)
                }

                HStack(spacing: 3) {
                    Text(appState.reorgAnalyses[index].currentCategory.displayName)
                        .font(.caption2)
                        .foregroundColor(.secondary)
                    Text("/")
                        .font(.caption2)
                        .foregroundColor(.secondary.opacity(0.5))
                    Text(appState.reorgAnalyses[index].currentFolder)
                        .font(.caption2)
                        .foregroundColor(.secondary)
                    Image(systemName: "arrow.right")
                        .font(.system(size: 8))
                        .foregroundColor(.accentColor)
                    Text(appState.reorgAnalyses[index].recommended.para.displayName)
                        .font(.caption2)
                        .fontWeight(.medium)
                        .foregroundColor(.accentColor)
                    Text("/")
                        .font(.caption2)
                        .foregroundColor(.accentColor.opacity(0.5))
                    Text(appState.reorgAnalyses[index].recommended.targetFolder)
                        .font(.caption2)
                        .fontWeight(.medium)
                        .foregroundColor(.accentColor)
                }
            }

            Spacer()
        }
        .padding(.vertical, 6)
        .padding(.horizontal, 8)
    }

    // MARK: - Task Progress Card (inline)

    @ViewBuilder
    private func taskProgressCard(title: String, progress: Double, status: String, onCancel: @escaping () -> Void) -> some View {
        VStack(spacing: 6) {
            HStack {
                ProgressView()
                    .controlSize(.small)
                Text(title)
                    .font(.caption)
                    .fontWeight(.medium)
                Spacer()
                Button("취소") { onCancel() }
                    .font(.caption2)
                    .buttonStyle(.plain)
                    .foregroundColor(.secondary)
            }
            ProgressView(value: progress)
                .progressViewStyle(.linear)
            if !status.isEmpty {
                HStack {
                    Text(status)
                        .font(.caption2)
                        .foregroundColor(.secondary)
                        .lineLimit(1)
                    Spacer()
                    Text("\(Int(progress * 100))%")
                        .font(.caption2)
                        .monospacedDigit()
                        .foregroundColor(.secondary)
                }
            }
        }
        .padding(10)
        .background(Color.accentColor.opacity(0.06))
        .cornerRadius(8)
        .padding(.horizontal)
    }

    // MARK: - Reorg Result Card (inline)

    @ViewBuilder
    private var reorgResultCard: some View {
        let successCount = appState.reorgResults.filter(\.isSuccess).count
        let errorResults = appState.reorgResults.filter(\.isError)
        let hasErrors = !errorResults.isEmpty
        let isEmpty = appState.reorgResults.isEmpty

        VStack(alignment: .leading, spacing: 6) {
            if isEmpty {
                HStack(spacing: 6) {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.caption)
                        .foregroundColor(.green)
                    Text("모든 파일이 적절한 위치에 있습니다")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            } else {
                if successCount > 0 {
                    HStack(spacing: 6) {
                        Image(systemName: "checkmark.circle")
                            .font(.caption)
                            .foregroundColor(.green)
                        Text("\(successCount)개 파일 이동 완료")
                            .font(.caption)
                            .fontWeight(.medium)
                            .foregroundColor(.green)
                        Spacer()
                    }
                }
                if hasErrors {
                    HStack(spacing: 6) {
                        Image(systemName: "xmark.circle")
                            .font(.caption)
                            .foregroundColor(.red)
                        Text("\(errorResults.count)건 오류")
                            .font(.caption)
                            .foregroundColor(.red)
                        Spacer()
                    }
                    ForEach(errorResults) { result in
                        Text("\(result.fileName) — \(result.error ?? "이동 실패")")
                            .font(.caption2)
                            .foregroundColor(.secondary)
                            .padding(.leading, 22)
                    }
                }
            }
            HStack {
                Spacer()
                Button("닫기") { resetReorg() }
                    .font(.caption2)
                    .buttonStyle(.plain)
                    .foregroundColor(.secondary)
            }
        }
        .padding(10)
        .background(hasErrors ? Color.orange.opacity(0.06) : Color.green.opacity(0.06))
        .cornerRadius(8)
        .padding(.horizontal)
    }

    // MARK: - Vault Check Result Card

    @ViewBuilder
    private func vaultCheckResultCard(_ result: VaultCheckResult) -> some View {
        let anyRowVisible = result.brokenLinks > 0
            || result.missingFrontmatter > 0
            || result.missingPARA > 0
            || result.repairCount > 0
            || result.enrichCount > 0
            || result.linksCreated > 0
            || result.mocUpdated
        let allClean = !anyRowVisible

        VStack(spacing: 6) {
            if result.brokenLinks > 0 {
                auditRow(icon: "link", label: "깨진 링크", count: result.brokenLinks, color: .orange)
            }
            if result.missingFrontmatter > 0 {
                auditRow(icon: "doc.badge.plus", label: "프론트매터 누락", count: result.missingFrontmatter, color: .orange)
            }
            if result.missingPARA > 0 {
                auditRow(icon: "folder.badge.questionmark", label: "PARA 미분류", count: result.missingPARA, color: .orange)
            }
            if result.repairCount > 0 {
                HStack(spacing: 6) {
                    Image(systemName: "wrench.and.screwdriver").font(.caption).foregroundColor(.green)
                    Text("\(result.repairCount)건 자동 복구").font(.caption).foregroundColor(.green)
                    Spacer()
                }
            }
            if result.enrichCount > 0 {
                HStack(spacing: 6) {
                    Image(systemName: "text.badge.star").font(.caption).foregroundColor(.secondary)
                    Text("\(result.enrichCount)개 메타데이터 보완").font(.caption)
                    Spacer()
                }
            }
            if result.linksCreated > 0 {
                HStack(spacing: 6) {
                    Image(systemName: "arrow.triangle.branch").font(.caption).foregroundColor(.blue)
                    Text("\(result.linksCreated)개 시맨틱 링크 생성").font(.caption).foregroundColor(.blue)
                    Spacer()
                }
            }
            if result.mocUpdated {
                HStack(spacing: 6) {
                    Image(systemName: "doc.text.magnifyingglass").font(.caption).foregroundColor(.secondary)
                    Text("폴더 요약 갱신 완료").font(.caption)
                    Spacer()
                }
            }
            if allClean {
                HStack(spacing: 6) {
                    Image(systemName: "checkmark.circle.fill").font(.caption).foregroundColor(.green)
                    Text("볼트 상태 양호").font(.caption).foregroundColor(.green)
                    Spacer()
                }
            }
            HStack {
                Spacer()
                Button("닫기") { appState.vaultCheckResult = nil }
                    .font(.caption2)
                    .buttonStyle(.plain)
                    .foregroundColor(.secondary)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(allClean ? Color.green.opacity(0.06) : Color.orange.opacity(0.06))
        .cornerRadius(8)
        .padding(.horizontal)
    }

    private func auditRow(icon: String, label: String, count: Int, color: Color) -> some View {
        HStack(spacing: 6) {
            Image(systemName: icon).font(.caption).foregroundColor(color).frame(width: 16)
            Text(label).font(.caption)
            Spacer()
            Text("\(count)건").font(.caption).monospacedDigit().foregroundColor(.secondary)
        }
    }

    // MARK: - Actions

    private func loadFolders() {
        let root = appState.pkmRootPath
        isLoading = true

        Task.detached(priority: .utility) {
            let pathManager = PKMPathManager(root: root)
            let fm = FileManager.default
            let hashCache = ContentHashCache(pkmRoot: root)
            await hashCache.load()

            // Collect all .md file paths and their folder info in one pass
            var folderFiles: [String: (name: String, category: PARACategory, files: [String])] = [:]

            for category in PARACategory.allCases {
                let basePath = pathManager.paraPath(for: category)
                guard let entries = try? fm.contentsOfDirectory(atPath: basePath) else { continue }

                for entry in entries.sorted() {
                    guard !entry.hasPrefix("."), !entry.hasPrefix("_") else { continue }
                    let folderPath = (basePath as NSString).appendingPathComponent(entry)
                    var isDir: ObjCBool = false
                    guard fm.fileExists(atPath: folderPath, isDirectory: &isDir), isDir.boolValue else { continue }

                    // Collect .md files for this folder
                    var mdFiles: [String] = []
                    if let files = try? fm.contentsOfDirectory(atPath: folderPath) {
                        for file in files {
                            guard file.hasSuffix(".md"), !file.hasPrefix("."), !file.hasPrefix("_") else { continue }
                            mdFiles.append((folderPath as NSString).appendingPathComponent(file))
                        }
                    }
                    folderFiles[folderPath] = (name: entry, category: category, files: mdFiles)
                }
            }

            // Single batch call to check all files at once
            let allFiles = folderFiles.values.flatMap { $0.files }
            let allStatuses = await hashCache.checkFiles(allFiles)

            // Build folder info from batch results
            var result: [FolderInfo] = []
            for (folderPath, info) in folderFiles.sorted(by: { $0.key < $1.key }) {
                var fileCount = 0
                var modifiedCount = 0
                var newCount = 0
                for file in info.files {
                    fileCount += 1
                    switch allStatuses[file] {
                    case .modified: modifiedCount += 1
                    case .new: newCount += 1
                    default: break
                    }
                }
                // Read summary from index note
                let indexPath = (folderPath as NSString).appendingPathComponent("\(info.name).md")
                let summary: String
                if let content = try? String(contentsOfFile: indexPath, encoding: .utf8) {
                    let (frontmatter, _) = Frontmatter.parse(markdown: content)
                    summary = frontmatter.summary ?? ""
                } else {
                    summary = ""
                }

                let health = FolderHealthAnalyzer.analyze(
                    folderPath: folderPath, folderName: info.name, category: info.category
                )
                let issuesText = health.issues.map(\.localizedDescription).joined(separator: "\n")

                result.append(FolderInfo(
                    name: info.name,
                    path: folderPath,
                    category: info.category,
                    fileCount: fileCount,
                    modifiedCount: modifiedCount,
                    newCount: newCount,
                    summary: summary,
                    healthLabel: health.label,
                    healthIssues: issuesText
                ))
            }

            let loaded = result
            await MainActor.run {
                folders = loaded
                isLoading = false
            }
        }
    }

    private func startFullReorg() {
        appState.reorgScope = .all
        appState.reorgPhase = .scanning
        startReorgScan()
    }

    private func startFolderReorg(_ folder: FolderInfo) {
        appState.reorgScope = .folder(folder.path)
        reorgChangedOnly = true
        appState.reorgPhase = .scanning
        startReorgScan()
    }

    private func startFolderFullReorg(_ folder: FolderInfo) {
        appState.reorgScope = .folder(folder.path)
        appState.reorgPhase = .scanning
        startReorgScan()
    }

    private func startCategoryReorg(_ category: PARACategory) {
        appState.reorgScope = .category(category)
        appState.reorgPhase = .scanning
        startReorgScan()
    }

    private func startReorgScan() {
        appState.reorgProgress = 0
        appState.reorgStatus = "스캔 준비 중..."
        appState.viewTaskActive = true
        let root = appState.pkmRootPath
        let currentScope = appState.reorgScope

        let changedOnly = reorgChangedOnly
        reorgChangedOnly = false

        appState.reorgTask?.cancel()
        appState.reorgTask = Task {
            // When filtering changed files only, load hash cache and collect non-unchanged paths
            var changedFileSet: Set<String>?
            if changedOnly, case .folder(let folderPath) = currentScope {
                let cache = ContentHashCache(pkmRoot: root)
                await cache.load()
                let statuses = await cache.checkFolder(folderPath)
                let changedPaths = statuses
                    .filter { $0.status != .unchanged }
                    .map { $0.filePath }
                if !changedPaths.isEmpty {
                    changedFileSet = Set(changedPaths)
                } else {
                    // Nothing changed — skip scan
                    await MainActor.run {
                        AppState.shared.reorgAnalyses = []
                        AppState.shared.viewTaskActive = false
                        AppState.shared.reorgResults = []
                        AppState.shared.reorgPhase = .done
                        AppState.shared.reorgStatus = "변경된 파일이 없습니다"
                    }
                    return
                }
            }

            var reorganizer = VaultReorganizer(
                pkmRoot: root,
                scope: currentScope,
                onProgress: { value, status in
                    Task { @MainActor in
                        AppState.shared.reorgProgress = value
                        AppState.shared.reorgStatus = status
                    }
                }
            )
            reorganizer.changedFilesOnly = changedFileSet

            do {
                let result = try await reorganizer.scan()
                if Task.isCancelled { return }

                // Update hash cache for ALL files in scope so health dots refresh
                // (includes index notes which reorg scan skips)
                let allScopePaths = Self.collectAllMdFiles(scope: currentScope, pkmRoot: root)
                if !allScopePaths.isEmpty {
                    let cache = ContentHashCache(pkmRoot: root)
                    await cache.load()
                    await cache.updateHashes(allScopePaths)
                    await cache.save()
                }

                await MainActor.run {
                    AppState.shared.reorgAnalyses = result.files
                    AppState.shared.viewTaskActive = false
                    if AppState.shared.reorgAnalyses.contains(where: \.needsMove) {
                        AppState.shared.reorgPhase = .reviewPlan
                    } else {
                        AppState.shared.reorgResults = []
                        AppState.shared.reorgPhase = .done
                    }
                }
            } catch {
                await MainActor.run {
                    AppState.shared.viewTaskActive = false
                    AppState.shared.reorgStatus = "오류: \(error.localizedDescription)"
                    AppState.shared.reorgPhase = .idle
                }
            }
        }
    }

    private func executeReorgPlan() {
        let selected = appState.reorgAnalyses.filter { $0.isSelected && $0.needsMove }
        guard !selected.isEmpty else { return }

        appState.reorgPhase = .executing
        appState.reorgProgress = 0
        appState.reorgStatus = "실행 준비 중..."
        appState.viewTaskActive = true
        let root = appState.pkmRootPath
        let currentScope = appState.reorgScope

        // Record rejected AI suggestions for learning
        let rejected = appState.reorgAnalyses.filter { $0.needsMove && !$0.isSelected }
        for file in rejected {
            CorrectionMemory.record(CorrectionEntry(
                date: Date(),
                fileName: file.fileName,
                aiPara: file.recommended.para.rawValue,
                userPara: file.currentCategory.rawValue,
                aiProject: file.recommended.targetFolder,
                userProject: file.currentFolder,
                tags: file.recommended.tags,
                action: "skip"
            ), pkmRoot: root)
        }

        appState.reorgTask?.cancel()
        appState.reorgTask = Task {
            let reorganizer = VaultReorganizer(
                pkmRoot: root,
                scope: currentScope,
                onProgress: { value, status in
                    Task { @MainActor in
                        AppState.shared.reorgProgress = value
                        AppState.shared.reorgStatus = status
                    }
                }
            )

            do {
                let executionResults = try await reorganizer.execute(plan: selected)
                if Task.isCancelled { return }

                // Update hash cache for ALL files in affected folders
                // (reorg may modify other files via SemanticLinker/NoteIndexGenerator)
                let allScopePaths = Self.collectAllMdFiles(scope: currentScope, pkmRoot: root)
                if !allScopePaths.isEmpty {
                    let cache = ContentHashCache(pkmRoot: root)
                    await cache.load()
                    await cache.updateHashes(allScopePaths)
                    await cache.save()
                }

                await MainActor.run {
                    AppState.shared.viewTaskActive = false
                    AppState.shared.reorgResults = executionResults
                    AppState.shared.reorgPhase = .done
                }
            } catch {
                await MainActor.run {
                    AppState.shared.viewTaskActive = false
                    AppState.shared.reorgStatus = "오류: \(error.localizedDescription)"
                    AppState.shared.reorgPhase = .done
                }
            }
        }
    }

    /// Collect all .md file paths within a reorg scope (including index notes).
    private nonisolated static func collectAllMdFiles(scope: VaultReorganizer.Scope, pkmRoot: String) -> [String] {
        let fm = FileManager.default
        let pathManager = PKMPathManager(root: pkmRoot)
        var paths: [String] = []

        func collectFromFolder(_ folderPath: String) {
            guard let entries = try? fm.contentsOfDirectory(atPath: folderPath) else { return }
            for entry in entries {
                guard entry.hasSuffix(".md"), !entry.hasPrefix("."), !entry.hasPrefix("_") else { continue }
                paths.append((folderPath as NSString).appendingPathComponent(entry))
            }
        }

        switch scope {
        case .folder(let folderPath):
            collectFromFolder(folderPath)
        case .category(let category):
            let basePath = pathManager.paraPath(for: category)
            guard let folders = try? fm.contentsOfDirectory(atPath: basePath) else { return paths }
            for folder in folders {
                guard !folder.hasPrefix("."), !folder.hasPrefix("_") else { continue }
                let folderPath = (basePath as NSString).appendingPathComponent(folder)
                var isDir: ObjCBool = false
                guard fm.fileExists(atPath: folderPath, isDirectory: &isDir), isDir.boolValue else { continue }
                collectFromFolder(folderPath)
            }
        case .all:
            for category in PARACategory.allCases {
                let basePath = pathManager.paraPath(for: category)
                guard let folders = try? fm.contentsOfDirectory(atPath: basePath) else { continue }
                for folder in folders {
                    guard !folder.hasPrefix("."), !folder.hasPrefix("_") else { continue }
                    let folderPath = (basePath as NSString).appendingPathComponent(folder)
                    var isDir: ObjCBool = false
                    guard fm.fileExists(atPath: folderPath, isDirectory: &isDir), isDir.boolValue else { continue }
                    collectFromFolder(folderPath)
                }
            }
        }
        return paths
    }

    private func resetReorg() {
        appState.resetReorg()
        reorgChangedOnly = false
        loadFolders()
    }
}

// MARK: - Vault Folder Row

private struct VaultFolderRow: View {
    let folder: VaultInspectorView.FolderInfo
    let action: () -> Void
    @State private var isHovered = false

    private var orgHealthColor: Color {
        switch folder.healthLabel {
        case "urgent": return .red
        case "attention": return .orange
        default: return .green
        }
    }

    private var modHealthColor: Color {
        if folder.healthRatio > 0.8 { return .green }
        if folder.healthRatio > 0.5 { return .orange }
        return .red
    }

    private var hasIssue: Bool {
        folder.healthLabel != "good" || folder.healthRatio <= 0.8
    }

    private var issueText: String {
        var parts: [String] = []
        if folder.healthLabel != "good" && !folder.healthIssues.isEmpty {
            parts.append(folder.healthIssues)
        }
        if folder.modifiedCount > 0 { parts.append("변경 \(folder.modifiedCount)개") }
        if folder.newCount > 0 { parts.append("신규 \(folder.newCount)개") }
        return parts.joined(separator: " · ")
    }

    private var dotColor: Color {
        if folder.healthLabel == "urgent" { return .red }
        if folder.healthLabel == "attention" || folder.healthRatio <= 0.5 { return .orange }
        if folder.healthRatio <= 0.8 { return .orange }
        return .green
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 8) {
                Image(systemName: "folder")
                    .font(.system(size: 13))
                    .foregroundColor(folder.category.color)
                    .frame(width: 16)

                VStack(alignment: .leading, spacing: 1) {
                    Text(folder.name)
                        .font(.caption)
                        .fontWeight(.medium)
                        .lineLimit(1)
                    if !folder.summary.isEmpty {
                        Text(folder.summary)
                            .font(.caption2)
                            .foregroundColor(.secondary)
                            .lineLimit(1)
                    }
                }

                Spacer()

                if hasIssue {
                    Circle()
                        .fill(dotColor)
                        .frame(width: 6, height: 6)
                }

                Text("\(folder.fileCount)")
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(
                        Capsule()
                            .fill(Color.secondary.opacity(0.12))
                    )
            }

            if hasIssue && !issueText.isEmpty {
                Text(issueText)
                    .font(.caption2)
                    .foregroundColor(dotColor)
                    .opacity(isHovered ? 1.0 : 0.8)
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
        .contentShape(Rectangle())
        .onTapGesture { action() }
        .animation(.easeOut(duration: 0.12), value: isHovered)
        .onHover { isHovered = $0 }
    }
}

