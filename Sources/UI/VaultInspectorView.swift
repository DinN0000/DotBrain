import SwiftUI

struct VaultInspectorView: View {
    @EnvironmentObject var appState: AppState

    @State private var folders: [FolderInfo] = []
    @State private var isLoading = true

    // Vault check state managed by AppState

    // Reorganize state (absorbed from VaultReorganizeView)
    @State private var reorgPhase: ReorgPhase = .idle
    @State private var reorgScope: VaultReorganizer.Scope = .all
    @State private var analyses: [VaultReorganizer.FileAnalysis] = []
    @State private var reorgResults: [ProcessedFileResult] = []
    @State private var reorgProgress: Double = 0
    @State private var reorgStatus: String = ""
    @State private var reorgTask: Task<Void, Never>?
    @State private var reorgChangedOnly = false

    enum ReorgPhase {
        case idle
        case scanning
        case reviewPlan
        case executing
        case done
    }

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

        var healthRatio: Double {
            guard fileCount > 0 else { return 1.0 }
            return Double(fileCount - modifiedCount - newCount) / Double(fileCount)
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            BreadcrumbView(current: .vaultInspector)
            Divider()

            if reorgPhase != .idle {
                reorgView
            } else {
                folderListView
            }
        }
        .onAppear { loadFolders() }
        .onChange(of: appState.backgroundTaskCompleted) { completed in
            if completed { loadFolders() }
        }
        .onDisappear {
            reorgTask?.cancel()
            appState.viewTaskActive = false
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
                            Text("AI 재분류")
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
                .help("AI가 모든 파일을 분석해서 적절한 폴더로 재배치")

                Spacer()
            }
            .padding(.horizontal)
            .padding(.vertical, 8)

            // Vault check inline progress (from AppState)
            if appState.backgroundTaskName == "전체 점검" {
                InlineProgress(message: appState.backgroundTaskPhase)
            }

            if let result = appState.vaultCheckResult {
                vaultCheckResultCard(result)
            }

            Divider()

            // Folder list
            if isLoading {
                Spacer()
                ProgressView()
                Spacer()
            } else {
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
            }
        }
    }

    // folderSection/folderContextMenu removed — flat LazyVStack for scroll performance

    // MARK: - Folder Menu (NSMenu popup, matching PARAManageView)

    private func showFolderMenu(_ folder: FolderInfo) {
        let menu = NSMenu()
        let changedCount = folder.modifiedCount + folder.newCount

        if changedCount > 0 {
            addMenuItem(
                to: menu,
                title: "바뀐 파일만 정리 (\(changedCount)개)",
                icon: "sparkles"
            ) {
                self.startFolderReorg(folder)
            }
        }

        addMenuItem(
            to: menu,
            title: "전체 파일 정리",
            icon: "arrow.2.squarepath"
        ) {
            self.startFolderFullReorg(folder)
        }

        menu.addItem(.separator())

        addMenuItem(to: menu, title: "Finder에서 열기", icon: "folder") {
            self.openInFinder(folder)
        }

        menu.popUp(positioning: nil, at: NSEvent.mouseLocation, in: nil)
    }

    private func addMenuItem(to menu: NSMenu, title: String, icon: String?, action: @escaping () -> Void) {
        let item = VaultMenuItem(title: title, action: #selector(VaultMenuItem.invoke), keyEquivalent: "")
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
            title: "\(category.displayName) 전체 AI 재분류",
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

    // MARK: - Reorganize View (absorbed from VaultReorganizeView)

    @ViewBuilder
    private var reorgView: some View {
        switch reorgPhase {
        case .idle:
            EmptyView()
        case .scanning:
            reorgScanningView
        case .reviewPlan:
            reorgPlanReviewView
        case .executing:
            reorgExecutingView
        case .done:
            reorgResultsView
        }
    }

    private var reorgScanningView: some View {
        VStack(spacing: 16) {
            Spacer()
            Text("AI 스캔 중")
                .font(.headline)
            ProgressView()
                .controlSize(.large)
            VStack(spacing: 6) {
                ProgressView(value: reorgProgress)
                    .progressViewStyle(.linear)
                    .padding(.horizontal, 40)
                HStack {
                    Spacer()
                    Text("\(Int(reorgProgress * 100))%")
                        .font(.subheadline)
                        .fontWeight(.medium)
                        .monospacedDigit()
                }
                .padding(.horizontal, 40)
            }
            Text(reorgStatus)
                .font(.caption)
                .foregroundColor(.secondary)
                .lineLimit(2)
                .multilineTextAlignment(.center)
                .padding(.horizontal)
            Spacer()
        }
        .padding()
    }

    private var reorgPlanReviewView: some View {
        let movableCount = analyses.filter(\.needsMove).count
        let selectedCount = analyses.filter { $0.isSelected && $0.needsMove }.count
        let allSelected: Bool = {
            let movable = analyses.filter(\.needsMove)
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
                        let categoryFiles = analyses.filter {
                            $0.needsMove && $0.recommended.para == category
                        }
                        if !categoryFiles.isEmpty {
                            reorgCategorySection(category: category, files: categoryFiles)
                        }
                    }

                    let unchangedCount = analyses.filter { !$0.needsMove }.count
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
                        for i in analyses.indices where analyses[i].needsMove {
                            analyses[i].isSelected = newValue
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
                if let analysisIndex = analyses.firstIndex(where: {
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
            Toggle(isOn: $analyses[index].isSelected) {
                EmptyView()
            }
            .toggleStyle(.checkbox)
            .labelsHidden()

            VStack(alignment: .leading, spacing: 3) {
                Text(analyses[index].fileName)
                    .font(.system(.body, design: .monospaced))
                    .lineLimit(1)

                if !analyses[index].recommended.summary.isEmpty {
                    Text(analyses[index].recommended.summary)
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .lineLimit(1)
                }

                HStack(spacing: 3) {
                    Text(analyses[index].currentCategory.displayName)
                        .font(.caption2)
                        .foregroundColor(.secondary)
                    Text("/")
                        .font(.caption2)
                        .foregroundColor(.secondary.opacity(0.5))
                    Text(analyses[index].currentFolder)
                        .font(.caption2)
                        .foregroundColor(.secondary)
                    Image(systemName: "arrow.right")
                        .font(.system(size: 8))
                        .foregroundColor(.accentColor)
                    Text(analyses[index].recommended.para.displayName)
                        .font(.caption2)
                        .fontWeight(.medium)
                        .foregroundColor(.accentColor)
                    Text("/")
                        .font(.caption2)
                        .foregroundColor(.accentColor.opacity(0.5))
                    Text(analyses[index].recommended.targetFolder)
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

    private var reorgExecutingView: some View {
        VStack(spacing: 16) {
            Spacer()
            Text("재정리 실행 중")
                .font(.headline)
            ProgressView()
                .controlSize(.large)
            VStack(spacing: 6) {
                ProgressView(value: reorgProgress)
                    .progressViewStyle(.linear)
                    .padding(.horizontal, 40)
                HStack {
                    Spacer()
                    Text("\(Int(reorgProgress * 100))%")
                        .font(.subheadline)
                        .fontWeight(.medium)
                        .monospacedDigit()
                }
                .padding(.horizontal, 40)
            }
            Text(reorgStatus)
                .font(.caption)
                .foregroundColor(.secondary)
                .lineLimit(2)
                .multilineTextAlignment(.center)
                .padding(.horizontal)
            Spacer()
        }
        .padding()
    }

    private var reorgResultsView: some View {
        VStack(spacing: 0) {
            ScrollView {
                LazyVStack(spacing: 2) {
                    let successCount = reorgResults.filter(\.isSuccess).count
                    let errorCount = reorgResults.filter(\.isError).count

                    if reorgResults.isEmpty {
                        // No files needed moving
                        VStack(spacing: 8) {
                            Image(systemName: "checkmark.circle.fill")
                                .font(.title2)
                                .foregroundColor(.green)
                            Text("모든 파일이 적절한 위치에 있습니다")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 24)
                    } else if successCount > 0 || errorCount > 0 {
                        VStack(alignment: .leading, spacing: 6) {
                            Label("\(successCount)개 파일 재정리 완료", systemImage: "checkmark.circle")
                                .font(.caption)
                                .fontWeight(.medium)
                                .foregroundColor(.green)
                            if errorCount > 0 {
                                HStack(spacing: 2) {
                                    Image(systemName: "xmark.circle")
                                        .font(.caption2)
                                        .foregroundColor(.red)
                                    Text("\(errorCount) 오류")
                                        .font(.caption2)
                                        .foregroundColor(.secondary)
                                }
                            }
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(10)
                        .background(RoundedRectangle(cornerRadius: 8).fill(Color.green.opacity(0.08)))
                        .padding(.bottom, 6)
                    }

                    ForEach(reorgResults) { result in
                        ResultRow(result: result)
                    }
                }
                .padding(.horizontal)
                .padding(.vertical, 8)
            }

            Divider()

            HStack {
                Spacer()
                Button("돌아가기") { resetReorg() }
                    .font(.caption)
                    .buttonStyle(.bordered)
            }
            .padding()
        }
    }

    // MARK: - Vault Check Result Card

    @ViewBuilder
    private func vaultCheckResultCard(_ result: VaultCheckResult) -> some View {
        let hasIssues = result.auditTotal > 0 || result.untaggedFiles > 0
        let allClean = !hasIssues && result.enrichCount == 0

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

                result.append(FolderInfo(
                    name: info.name,
                    path: folderPath,
                    category: info.category,
                    fileCount: fileCount,
                    modifiedCount: modifiedCount,
                    newCount: newCount,
                    summary: summary
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
        reorgScope = .all
        reorgPhase = .scanning
        startReorgScan()
    }

    private func startFolderReorg(_ folder: FolderInfo) {
        reorgScope = .folder(folder.path)
        reorgChangedOnly = true
        reorgPhase = .scanning
        startReorgScan()
    }

    private func startFolderFullReorg(_ folder: FolderInfo) {
        reorgScope = .folder(folder.path)
        reorgPhase = .scanning
        startReorgScan()
    }

    private func startCategoryReorg(_ category: PARACategory) {
        reorgScope = .category(category)
        reorgPhase = .scanning
        startReorgScan()
    }

    private func startReorgScan() {
        reorgProgress = 0
        reorgStatus = "스캔 준비 중..."
        appState.viewTaskActive = true
        let root = appState.pkmRootPath
        let currentScope = reorgScope

        let changedOnly = reorgChangedOnly
        reorgChangedOnly = false

        reorgTask?.cancel()
        reorgTask = Task {
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
                        analyses = []
                        appState.viewTaskActive = false
                        reorgResults = []
                        reorgPhase = .done
                        reorgStatus = "변경된 파일이 없습니다"
                    }
                    return
                }
            }

            var reorganizer = VaultReorganizer(
                pkmRoot: root,
                scope: currentScope,
                onProgress: { value, status in
                    Task { @MainActor in
                        reorgProgress = value
                        reorgStatus = status
                    }
                }
            )
            reorganizer.changedFilesOnly = changedFileSet

            do {
                let result = try await reorganizer.scan()
                if Task.isCancelled { return }

                // Update hash cache for scanned files so health dots refresh
                let scannedPaths = result.files.map { $0.filePath }
                if !scannedPaths.isEmpty {
                    let cache = ContentHashCache(pkmRoot: root)
                    await cache.load()
                    await cache.updateHashes(scannedPaths)
                    await cache.save()
                }

                await MainActor.run {
                    analyses = result.files
                    appState.viewTaskActive = false
                    if analyses.contains(where: \.needsMove) {
                        reorgPhase = .reviewPlan
                    } else {
                        reorgResults = []
                        reorgPhase = .done
                    }
                }
            } catch {
                await MainActor.run {
                    appState.viewTaskActive = false
                    reorgStatus = "오류: \(error.localizedDescription)"
                    reorgPhase = .idle
                }
            }
        }
    }

    private func executeReorgPlan() {
        let selected = analyses.filter { $0.isSelected && $0.needsMove }
        guard !selected.isEmpty else { return }

        reorgPhase = .executing
        reorgProgress = 0
        reorgStatus = "실행 준비 중..."
        appState.viewTaskActive = true
        let root = appState.pkmRootPath

        reorgTask?.cancel()
        reorgTask = Task {
            let reorganizer = VaultReorganizer(
                pkmRoot: root,
                scope: reorgScope,
                onProgress: { value, status in
                    Task { @MainActor in
                        reorgProgress = value
                        reorgStatus = status
                    }
                }
            )

            do {
                let executionResults = try await reorganizer.execute(plan: selected)
                if Task.isCancelled { return }

                // Update hash cache for moved files (new paths)
                let movedPaths = executionResults.filter(\.isSuccess).map { $0.targetPath }
                if !movedPaths.isEmpty {
                    let cache = ContentHashCache(pkmRoot: root)
                    await cache.load()
                    await cache.updateHashes(movedPaths)
                    await cache.save()
                }

                await MainActor.run {
                    appState.viewTaskActive = false
                    reorgResults = executionResults
                    reorgPhase = .done
                }
            } catch {
                await MainActor.run {
                    appState.viewTaskActive = false
                    reorgStatus = "오류: \(error.localizedDescription)"
                    reorgPhase = .done
                }
            }
        }
    }

    private func resetReorg() {
        reorgTask?.cancel()
        appState.viewTaskActive = false
        reorgTask = nil
        reorgPhase = .idle
        reorgChangedOnly = false
        analyses = []
        reorgResults = []
        reorgProgress = 0
        reorgStatus = ""
        loadFolders()
    }
}

// MARK: - Vault Folder Row

private struct VaultFolderRow: View {
    let folder: VaultInspectorView.FolderInfo
    let action: () -> Void
    @State private var isHovered = false

    private var healthColor: Color {
        if folder.healthRatio > 0.8 { return .green }
        if folder.healthRatio > 0.5 { return .orange }
        return .red
    }

    private var hasHealthIssue: Bool {
        folder.healthRatio <= 0.8
    }

    private var healthIssues: String {
        var parts: [String] = []
        if folder.modifiedCount > 0 { parts.append("변경 \(folder.modifiedCount)개") }
        if folder.newCount > 0 { parts.append("신규 \(folder.newCount)개") }
        if folder.healthRatio <= 0.5 {
            parts.append("정리 필요")
        } else {
            parts.append("점검 권장")
        }
        return parts.joined(separator: " · ")
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

                if hasHealthIssue {
                    Circle()
                        .fill(healthColor)
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

            if hasHealthIssue {
                Text(healthIssues)
                    .font(.caption2)
                    .foregroundColor(healthColor)
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

// MARK: - NSMenuItem with Closure

private class VaultMenuItem: NSMenuItem {
    var callback: (() -> Void)?

    @objc func invoke() {
        callback?()
    }
}
