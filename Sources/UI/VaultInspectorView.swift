import SwiftUI

struct VaultInspectorView: View {
    @EnvironmentObject var appState: AppState

    // Level 1: Folder list
    @State private var selectedFolder: FolderInfo?
    @State private var folders: [FolderInfo] = []
    @State private var isLoading = true

    // Vault check state (moved from DashboardView)
    @State private var isVaultChecking = false
    @State private var vaultCheckPhase = ""
    @State private var vaultCheckResult: VaultCheckResult?
    @State private var vaultCheckTask: Task<Void, Never>?

    // Reorganize state (absorbed from VaultReorganizeView)
    @State private var reorgPhase: ReorgPhase = .idle
    @State private var reorgScope: VaultReorganizer.Scope = .all
    @State private var analyses: [VaultReorganizer.FileAnalysis] = []
    @State private var reorgResults: [ProcessedFileResult] = []
    @State private var reorgProgress: Double = 0
    @State private var reorgStatus: String = ""
    @State private var reorgTask: Task<Void, Never>?

    enum ReorgPhase {
        case idle
        case scanning
        case reviewPlan
        case executing
        case done
    }

    struct FolderInfo: Identifiable {
        let id = UUID()
        let name: String
        let path: String
        let category: PARACategory
        let fileCount: Int
        let modifiedCount: Int
        let newCount: Int

        var healthRatio: Double {
            guard fileCount > 0 else { return 1.0 }
            return Double(fileCount - modifiedCount - newCount) / Double(fileCount)
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            BreadcrumbView(current: .vaultInspector)
            Divider()

            if selectedFolder != nil {
                folderDetailView
            } else if reorgPhase != .idle {
                reorgView
            } else {
                folderListView
            }
        }
        .onAppear { loadFolders() }
        .onDisappear {
            vaultCheckTask?.cancel()
            reorgTask?.cancel()
        }
    }

    // MARK: - Level 1: Folder List

    private var folderListView: some View {
        VStack(spacing: 0) {
            // Action buttons
            HStack(spacing: 8) {
                Button(action: { runVaultCheck() }) {
                    HStack(spacing: 4) {
                        Image(systemName: "stethoscope")
                            .font(.caption)
                        Text("전체 점검")
                            .font(.caption)
                    }
                    .padding(.horizontal, 10)
                    .padding(.vertical, 5)
                }
                .buttonStyle(.bordered)
                .disabled(isVaultChecking)

                Button(action: { startFullReorg() }) {
                    HStack(spacing: 4) {
                        Image(systemName: "arrow.triangle.2.circlepath")
                            .font(.caption)
                        Text("전체 재분류")
                            .font(.caption)
                    }
                    .padding(.horizontal, 10)
                    .padding(.vertical, 5)
                }
                .buttonStyle(.bordered)

                Spacer()
            }
            .padding(.horizontal)
            .padding(.vertical, 8)

            // Vault check inline progress
            if isVaultChecking {
                InlineProgress(message: vaultCheckPhase)
            }

            if let result = vaultCheckResult {
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
                        ForEach(PARACategory.allCases, id: \.self) { category in
                            let categoryFolders = folders.filter { $0.category == category }
                            if !categoryFolders.isEmpty {
                                folderSection(category: category, folders: categoryFolders)
                            }
                        }
                    }
                    .padding(.horizontal)
                    .padding(.vertical, 8)
                }
            }
        }
    }

    @ViewBuilder
    private func folderSection(category: PARACategory, folders: [FolderInfo]) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 6) {
                Image(systemName: category.icon)
                    .font(.caption)
                    .foregroundColor(category.color)
                Text(category.displayName)
                    .font(.caption)
                    .fontWeight(.semibold)
                Text("(\(folders.count))")
                    .font(.caption2)
                    .foregroundColor(.secondary)
                Spacer()
            }
            .padding(.vertical, 6)

            ForEach(folders) { folder in
                folderRow(folder)
            }
        }
    }

    private func folderRow(_ folder: FolderInfo) -> some View {
        Button {
            selectedFolder = folder
        } label: {
            HStack(spacing: 8) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(folder.name)
                        .font(.caption)
                        .fontWeight(.medium)
                        .lineLimit(1)

                    HStack(spacing: 4) {
                        Text("\(folder.fileCount)개")
                            .font(.caption2)
                            .foregroundColor(.secondary)
                        if folder.modifiedCount > 0 {
                            Text("변경 \(folder.modifiedCount)")
                                .font(.caption2)
                                .foregroundColor(.orange)
                        }
                        if folder.newCount > 0 {
                            Text("신규 \(folder.newCount)")
                                .font(.caption2)
                                .foregroundColor(.blue)
                        }
                    }
                }

                Spacer()

                // Health bar
                GeometryReader { geo in
                    ZStack(alignment: .leading) {
                        RoundedRectangle(cornerRadius: 2)
                            .fill(Color.primary.opacity(0.08))
                        RoundedRectangle(cornerRadius: 2)
                            .fill(folder.healthRatio > 0.8 ? Color.green : folder.healthRatio > 0.5 ? Color.orange : Color.red)
                            .frame(width: geo.size.width * folder.healthRatio)
                    }
                }
                .frame(width: 40, height: 4)

                Image(systemName: "chevron.right")
                    .font(.caption2)
                    .foregroundColor(.secondary)
            }
            .padding(.vertical, 6)
            .padding(.horizontal, 8)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    // MARK: - Level 2: Folder Detail

    private var folderDetailView: some View {
        VStack(spacing: 0) {
            // Back button + folder name
            HStack(spacing: 8) {
                Button {
                    selectedFolder = nil
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: "chevron.left")
                            .font(.caption)
                        Text("목록")
                            .font(.caption)
                    }
                }
                .buttonStyle(.plain)
                .foregroundColor(.accentColor)

                if let folder = selectedFolder {
                    Text(folder.name)
                        .font(.subheadline)
                        .fontWeight(.medium)
                }

                Spacer()
            }
            .padding(.horizontal)
            .padding(.vertical, 8)

            Divider()

            if let folder = selectedFolder {
                ScrollView {
                    VStack(spacing: 12) {
                        // Diagnostic summary
                        HStack(spacing: 12) {
                            miniStat(value: "\(folder.fileCount)", label: "파일")
                            miniStat(value: "\(folder.modifiedCount)", label: "변경됨", color: .orange)
                            miniStat(value: "\(folder.newCount)", label: "신규", color: .blue)
                        }
                        .padding(.horizontal)

                        // Tool cards
                        VStack(alignment: .leading, spacing: 8) {
                            Text("도구")
                                .font(.caption)
                                .fontWeight(.semibold)
                                .foregroundColor(.secondary)

                            HStack(spacing: 8) {
                                toolButton(
                                    icon: "arrow.triangle.2.circlepath",
                                    label: "변경 파일 재분류",
                                    isDisabled: folder.modifiedCount + folder.newCount == 0
                                ) {
                                    startFolderReorg(folder)
                                }

                                toolButton(
                                    icon: "arrow.2.squarepath",
                                    label: "전체 재분류",
                                    isDisabled: false
                                ) {
                                    startFolderFullReorg(folder)
                                }
                            }
                        }
                        .padding(.horizontal)
                    }
                    .padding(.vertical, 8)
                }
            }
        }
    }

    private func miniStat(value: String, label: String, color: Color = .primary) -> some View {
        VStack(spacing: 2) {
            Text(value)
                .font(.title3)
                .fontWeight(.bold)
                .foregroundColor(color)
                .monospacedDigit()
            Text(label)
                .font(.caption2)
                .foregroundColor(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 8)
        .background(Color.primary.opacity(0.03))
        .cornerRadius(8)
    }

    private func toolButton(icon: String, label: String, isDisabled: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            VStack(spacing: 4) {
                Image(systemName: icon)
                    .font(.system(size: 14))
                Text(label)
                    .font(.caption2)
                    .lineLimit(2)
                    .multilineTextAlignment(.center)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 8)
            .background(Color.primary.opacity(0.03))
            .cornerRadius(8)
            .overlay(
                RoundedRectangle(cornerRadius: 8)
                    .strokeBorder(Color.primary.opacity(0.06), lineWidth: 0.5)
            )
        }
        .buttonStyle(.plain)
        .disabled(isDisabled)
        .opacity(isDisabled ? 0.4 : 1)
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

                    if successCount > 0 || errorCount > 0 {
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
                Button("닫기") { vaultCheckResult = nil }
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

            var result: [FolderInfo] = []

            for category in PARACategory.allCases {
                let basePath = pathManager.paraPath(for: category)
                guard let entries = try? fm.contentsOfDirectory(atPath: basePath) else { continue }

                for entry in entries.sorted() {
                    guard !entry.hasPrefix("."), !entry.hasPrefix("_") else { continue }
                    let folderPath = (basePath as NSString).appendingPathComponent(entry)
                    var isDir: ObjCBool = false
                    guard fm.fileExists(atPath: folderPath, isDirectory: &isDir), isDir.boolValue else { continue }

                    let statusEntries = await hashCache.checkFolder(folderPath)
                    let fileCount = statusEntries.count
                    let modifiedCount = statusEntries.filter { $0.status == .modified }.count
                    let newCount = statusEntries.filter { $0.status == .new }.count

                    result.append(FolderInfo(
                        name: entry,
                        path: folderPath,
                        category: category,
                        fileCount: fileCount,
                        modifiedCount: modifiedCount,
                        newCount: newCount
                    ))
                }
            }

            let loaded = result
            await MainActor.run {
                folders = loaded
                isLoading = false
            }
        }
    }

    private func runVaultCheck() {
        guard !isVaultChecking else { return }
        isVaultChecking = true
        vaultCheckResult = nil
        let root = appState.pkmRootPath

        vaultCheckTask?.cancel()
        vaultCheckTask = Task.detached(priority: .utility) {
            defer {
                Task { @MainActor in
                    isVaultChecking = false
                    vaultCheckTask = nil
                }
            }
            var repairCount = 0
            var enrichCount = 0

            StatisticsService.recordActivity(
                fileName: "볼트 점검",
                category: "system",
                action: "started",
                detail: "오류 검사 · 메타데이터 보완 · MOC 갱신"
            )

            await MainActor.run { vaultCheckPhase = "오류 검사 중..." }
            let auditor = VaultAuditor(pkmRoot: root)
            let report = auditor.audit()
            if Task.isCancelled { return }

            if report.totalIssues > 0 {
                await MainActor.run { vaultCheckPhase = "자동 복구 중..." }
                let repair = auditor.repair(report: report)
                repairCount = repair.linksFixed + repair.frontmatterInjected + repair.paraFixed
            }
            if Task.isCancelled { return }

            await MainActor.run { vaultCheckPhase = "메타데이터 보완 중..." }
            let enricher = NoteEnricher(pkmRoot: root)
            let pm = PKMPathManager(root: root)
            let fm = FileManager.default
            for basePath in [pm.projectsPath, pm.areaPath, pm.resourcePath] {
                if Task.isCancelled { return }
                guard let folders = try? fm.contentsOfDirectory(atPath: basePath) else { continue }
                for folder in folders where !folder.hasPrefix(".") && !folder.hasPrefix("_") {
                    if Task.isCancelled { return }
                    let folderPath = (basePath as NSString).appendingPathComponent(folder)
                    let results = await enricher.enrichFolder(at: folderPath)
                    enrichCount += results.filter { $0.fieldsUpdated > 0 }.count
                }
            }

            await MainActor.run { vaultCheckPhase = "폴더 요약 갱신 중..." }
            let generator = MOCGenerator(pkmRoot: root)
            await generator.regenerateAll()
            if Task.isCancelled { return }

            await MainActor.run { vaultCheckPhase = "노트 간 시맨틱 연결 중..." }
            let linker = SemanticLinker(pkmRoot: root)
            let linkResult = await linker.linkAll { progress, status in
                Task { @MainActor in
                    vaultCheckPhase = status
                }
            }

            StatisticsService.recordActivity(
                fileName: "볼트 점검",
                category: "system",
                action: "completed",
                detail: "\(report.totalIssues)건 발견, \(repairCount)건 복구, \(enrichCount)개 보완, \(linkResult.linksCreated)개 링크"
            )

            let snapshot = VaultCheckResult(
                brokenLinks: report.brokenLinks.count,
                missingFrontmatter: report.missingFrontmatter.count,
                missingPARA: report.missingPARA.count,
                untaggedFiles: report.untaggedFiles.count,
                repairCount: repairCount,
                enrichCount: enrichCount,
                mocUpdated: true,
                linksCreated: linkResult.linksCreated
            )
            await MainActor.run {
                vaultCheckResult = snapshot
                loadFolders()  // Refresh after check
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
        selectedFolder = nil
        reorgPhase = .scanning
        startReorgScan()
    }

    private func startFolderFullReorg(_ folder: FolderInfo) {
        reorgScope = .category(folder.category)
        selectedFolder = nil
        reorgPhase = .scanning
        startReorgScan()
    }

    private func startReorgScan() {
        reorgProgress = 0
        reorgStatus = "스캔 준비 중..."
        let root = appState.pkmRootPath
        let currentScope = reorgScope

        reorgTask?.cancel()
        reorgTask = Task {
            let reorganizer = VaultReorganizer(
                pkmRoot: root,
                scope: currentScope,
                onProgress: { value, status in
                    Task { @MainActor in
                        reorgProgress = value
                        reorgStatus = status
                    }
                }
            )

            do {
                let result = try await reorganizer.scan()
                if Task.isCancelled { return }

                await MainActor.run {
                    analyses = result.files
                    if analyses.contains(where: \.needsMove) {
                        reorgPhase = .reviewPlan
                    } else {
                        reorgResults = []
                        reorgPhase = .done
                    }
                }
            } catch {
                await MainActor.run {
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

                await MainActor.run {
                    reorgResults = executionResults
                    reorgPhase = .done
                }
            } catch {
                await MainActor.run {
                    reorgStatus = "오류: \(error.localizedDescription)"
                    reorgPhase = .done
                }
            }
        }
    }

    private func resetReorg() {
        reorgTask?.cancel()
        reorgTask = nil
        reorgPhase = .idle
        analyses = []
        reorgResults = []
        reorgProgress = 0
        reorgStatus = ""
        loadFolders()
    }
}

// Reused from DashboardView -- now lives with VaultInspectorView
private struct VaultCheckResult {
    let brokenLinks: Int
    let missingFrontmatter: Int
    let missingPARA: Int
    let untaggedFiles: Int
    let repairCount: Int
    let enrichCount: Int
    let mocUpdated: Bool
    let linksCreated: Int

    var auditTotal: Int {
        brokenLinks + missingFrontmatter + missingPARA
    }
}
