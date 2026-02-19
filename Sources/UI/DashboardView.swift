import SwiftUI

struct DashboardView: View {
    @EnvironmentObject var appState: AppState
    @State private var stats = PKMStatistics()
    @State private var urgentFolderCount = 0

    // Vault check state
    @State private var isVaultChecking = false
    @State private var vaultCheckPhase = ""
    @State private var vaultCheckResult: VaultCheckResult?
    @State private var selectedActivity: ActivityEntry?
    @State private var healthScanTask: Task<Void, Never>?
    @State private var vaultCheckTask: Task<Void, Never>?

    // Cached PARA counts to avoid recalculation on every render
    private var projectCount: Int { stats.byCategory["project"] ?? 0 }
    private var areaCount: Int { stats.byCategory["area"] ?? 0 }
    private var resourceCount: Int { stats.byCategory["resource"] ?? 0 }
    private var archiveCount: Int { stats.byCategory["archive"] ?? 0 }

    var body: some View {
        VStack(spacing: 0) {
            BreadcrumbView(current: .dashboard)

            Divider()

            ScrollView {
                VStack(spacing: 16) {
                    // Interactive stats line
                    HStack(spacing: 6) {
                        Image(systemName: "doc.fill")
                            .font(.caption)
                            .foregroundColor(.secondary)
                        Text("전체 \(stats.totalFiles)개")
                            .font(.subheadline)
                            .fontWeight(.medium)

                        Spacer()

                        statButton("P", count: projectCount, color: PARACategory.project.color, category: .project)
                        statButton("A", count: areaCount, color: PARACategory.area.color, category: .area)
                        statButton("R", count: resourceCount, color: PARACategory.resource.color, category: .resource)
                        statButton("A", count: archiveCount, color: PARACategory.archive.color, category: .archive)
                    }
                    .font(.caption)
                    .monospacedDigit()
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                    .background(Color.primary.opacity(0.03))
                    .cornerRadius(8)

                    // Health summary
                    if urgentFolderCount > 0 {
                        HStack(spacing: 6) {
                            Circle()
                                .fill(Color.red)
                                .frame(width: 6, height: 6)
                            Text("\(urgentFolderCount)개 폴더 점검 필요")
                                .font(.caption)
                                .foregroundColor(.secondary)
                            Spacer()
                            Button("보기") {
                                appState.currentScreen = .paraManage
                            }
                            .font(.caption)
                            .buttonStyle(.plain)
                            .foregroundColor(.accentColor)
                        }
                        .padding(.horizontal, 12)
                        .padding(.vertical, 6)
                        .background(Color.red.opacity(0.06))
                        .cornerRadius(6)
                    }

                    // Group 1: File operations
                    DashboardCardGroup(
                        label: "수제 도구",
                        description: "폴더와 파일을 직접 관리",
                        tint: .accentColor
                    ) {
                        DashboardHubCard(
                            icon: "folder.badge.gearshape",
                            title: "폴더 관리",
                            subtitle: "이동 · 생성 · 정리",
                            tint: .accentColor
                        ) {
                            appState.currentScreen = .paraManage
                        }
                        DashboardHubCard(
                            icon: "magnifyingglass",
                            title: "검색",
                            subtitle: "파일 · 태그 검색",
                            tint: .accentColor
                        ) {
                            appState.currentScreen = .search
                        }
                    }

                    // Group 2: Vault maintenance
                    DashboardCardGroup(
                        label: "AI 관리",
                        description: "AI가 볼트 전체를 점검하고 분류",
                        tint: .accentColor
                    ) {
                        DashboardHubCard(
                            icon: "checkmark.shield",
                            title: "볼트 점검",
                            subtitle: "오류 수정 · 메타 보완",
                            tint: .accentColor,
                            isDisabled: isVaultChecking
                        ) {
                            runVaultCheck()
                        }
                        DashboardHubCard(
                            icon: "arrow.triangle.2.circlepath",
                            title: "AI 재분류",
                            subtitle: "파일 위치 재배치",
                            tint: .accentColor
                        ) {
                            appState.currentScreen = .vaultReorganize
                        }
                    }

                    // Vault check inline results
                    if isVaultChecking {
                        InlineProgress(message: vaultCheckPhase)
                    }

                    if let result = vaultCheckResult {
                        vaultCheckResultView(result)
                    }

                    // Recent activity
                    VStack(alignment: .leading, spacing: 8) {
                        Text("최근 활동")
                            .font(.subheadline)
                            .fontWeight(.medium)

                        if stats.recentActivity.isEmpty {
                            Text("아직 활동 기록이 없습니다")
                                .font(.caption)
                                .foregroundColor(.secondary)
                                .padding(.vertical, 8)
                        } else {
                            ForEach(stats.recentActivity.prefix(10)) { entry in
                                VStack(spacing: 0) {
                                    Button {
                                        withAnimation(.easeInOut(duration: 0.15)) {
                                            if selectedActivity?.id == entry.id {
                                                selectedActivity = nil
                                            } else {
                                                selectedActivity = entry
                                            }
                                        }
                                    } label: {
                                        HStack(spacing: 8) {
                                            Image(systemName: activityIcon(for: entry.action))
                                                .font(.caption)
                                                .foregroundColor(activityColor(for: entry.action))
                                                .frame(width: 16)

                                            Text(entry.fileName)
                                                .font(.caption)
                                                .lineLimit(1)

                                            Spacer()

                                            if entry.category != "system" {
                                                Text(categoryLabel(for: entry.category))
                                                    .font(.caption2)
                                                    .foregroundColor(.secondary)
                                            }

                                            Text(relativeDate(entry.date))
                                                .font(.caption2)
                                                .foregroundColor(.secondary)

                                            Image(systemName: selectedActivity?.id == entry.id ? "chevron.up" : "chevron.down")
                                                .font(.system(size: 8))
                                                .foregroundColor(.secondary)
                                        }
                                        .padding(.vertical, 3)
                                        .contentShape(Rectangle())
                                    }
                                    .buttonStyle(.plain)

                                    // Detail panel
                                    if selectedActivity?.id == entry.id {
                                        activityDetailView(entry)
                                            .transition(.opacity.combined(with: .move(edge: .top)))
                                    }
                                }
                            }
                        }
                    }
                    .padding()
                    .background(Color.primary.opacity(0.03))
                    .cornerRadius(8)
                }
                .padding()
            }
        }
        .onAppear {
            refreshStats()
        }
        .onDisappear {
            healthScanTask?.cancel()
            healthScanTask = nil
            vaultCheckTask?.cancel()
            vaultCheckTask = nil
        }
        .onChange(of: appState.currentScreen) { newScreen in
            if newScreen == .dashboard {
                refreshStats()
            }
        }
    }

    private func refreshStats() {
        let service = StatisticsService(pkmRoot: appState.pkmRootPath)
        stats = service.collectStatistics()
        scanHealthSummary()
    }

    // MARK: - Vault Check Result View

    @ViewBuilder
    private func vaultCheckResultView(_ result: VaultCheckResult) -> some View {
        let hasIssues = result.auditTotal > 0 || result.untaggedFiles > 0
        let allClean = !hasIssues && result.enrichCount == 0

        VStack(spacing: 6) {
            // Audit detail rows
            if result.brokenLinks > 0 {
                auditResultRow(
                    icon: "link",
                    label: "깨진 링크",
                    count: result.brokenLinks,
                    color: .orange
                )
            }
            if result.missingFrontmatter > 0 {
                auditResultRow(
                    icon: "doc.badge.plus",
                    label: "프론트매터 누락",
                    count: result.missingFrontmatter,
                    color: .orange
                )
            }
            if result.missingPARA > 0 {
                auditResultRow(
                    icon: "folder.badge.questionmark",
                    label: "PARA 미분류",
                    count: result.missingPARA,
                    color: .orange
                )
            }

            // Repair summary
            if result.repairCount > 0 {
                HStack(spacing: 6) {
                    Image(systemName: "wrench.and.screwdriver")
                        .font(.caption)
                        .foregroundColor(.green)
                    Text("\(result.repairCount)건 자동 복구")
                        .font(.caption)
                        .foregroundColor(.green)
                    Spacer()
                }
            }

            // Enrich results
            if result.enrichCount > 0 {
                HStack(spacing: 6) {
                    Image(systemName: "text.badge.star")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    Text("\(result.enrichCount)개 메타데이터 보완")
                        .font(.caption)
                    Spacer()
                }
            }

            // Semantic links
            if result.linksCreated > 0 {
                HStack(spacing: 6) {
                    Image(systemName: "arrow.triangle.branch")
                        .font(.caption)
                        .foregroundColor(.blue)
                    Text("\(result.linksCreated)개 시맨틱 링크 생성")
                        .font(.caption)
                        .foregroundColor(.blue)
                    Spacer()
                }
            }

            // MOC update
            if result.mocUpdated {
                HStack(spacing: 6) {
                    Image(systemName: "doc.text.magnifyingglass")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    Text("폴더 요약 갱신 완료")
                        .font(.caption)
                    Spacer()
                }
            }

            // All clean
            if allClean {
                HStack(spacing: 6) {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.caption)
                        .foregroundColor(.green)
                    Text("볼트 상태 양호")
                        .font(.caption)
                        .foregroundColor(.green)
                    Spacer()
                }
            }

            // Dismiss
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
    }

    private func auditResultRow(icon: String, label: String, count: Int, color: Color) -> some View {
        HStack(spacing: 6) {
            Image(systemName: icon)
                .font(.caption)
                .foregroundColor(color)
                .frame(width: 16)
            Text(label)
                .font(.caption)
            Spacer()
            Text("\(count)건")
                .font(.caption)
                .monospacedDigit()
                .foregroundColor(.secondary)
        }
    }

    // MARK: - Interactive Stat Button

    private func statButton(_ label: String, count: Int, color: Color, category: PARACategory) -> some View {
        Button {
            appState.paraManageInitialCategory = category
            appState.currentScreen = .paraManage
        } label: {
            Text("\(label) \(count)")
                .foregroundColor(color)
        }
        .buttonStyle(.plain)
    }

    // MARK: - Health Summary

    private func scanHealthSummary() {
        let root = appState.pkmRootPath
        healthScanTask?.cancel()
        healthScanTask = Task.detached(priority: .utility) {
            let pathManager = PKMPathManager(root: root)
            let fm = FileManager.default
            var count = 0
            for cat in PARACategory.allCases where cat != .archive {
                if Task.isCancelled { return }
                let basePath = pathManager.paraPath(for: cat)
                guard let entries = try? fm.contentsOfDirectory(atPath: basePath) else { continue }
                for entry in entries where !entry.hasPrefix(".") && !entry.hasPrefix("_") {
                    if Task.isCancelled { return }
                    let fullPath = (basePath as NSString).appendingPathComponent(entry)
                    var isDir: ObjCBool = false
                    guard fm.fileExists(atPath: fullPath, isDirectory: &isDir), isDir.boolValue else { continue }
                    let health = FolderHealthAnalyzer.analyze(
                        folderPath: fullPath, folderName: entry, category: cat
                    )
                    if health.label == "urgent" || health.label == "attention" {
                        count += 1
                    }
                }
            }
            let snapshot = count
            if Task.isCancelled { return }
            await MainActor.run {
                urgentFolderCount = snapshot
                healthScanTask = nil
            }
        }
    }

    // MARK: - Vault Check (Audit + Repair + Enrich + MOC)

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

            // 1. Audit
            await MainActor.run { vaultCheckPhase = "오류 검사 중..." }
            let auditor = VaultAuditor(pkmRoot: root)
            let report = auditor.audit()
            if Task.isCancelled { return }

            // 2. Auto-repair
            if report.totalIssues > 0 {
                await MainActor.run { vaultCheckPhase = "자동 복구 중..." }
                let repair = auditor.repair(report: report)
                repairCount = repair.linksFixed + repair.frontmatterInjected + repair.paraFixed
            }
            if Task.isCancelled { return }

            // 3. Enrich metadata
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

            // 4. MOC regenerate — count PARA folders for progress visibility
            var folderCount = 0
            for basePath in [pm.projectsPath, pm.areaPath, pm.resourcePath] {
                if Task.isCancelled { return }
                if let entries = try? fm.contentsOfDirectory(atPath: basePath) {
                    for entry in entries where !entry.hasPrefix(".") && !entry.hasPrefix("_") {
                        let fullPath = (basePath as NSString).appendingPathComponent(entry)
                        var isDir: ObjCBool = false
                        if fm.fileExists(atPath: fullPath, isDirectory: &isDir), isDir.boolValue {
                            folderCount += 1
                        }
                    }
                }
            }
            let folderCountSnapshot = folderCount
            await MainActor.run { vaultCheckPhase = "\(folderCountSnapshot)개 폴더 요약 갱신 중..." }
            let generator = MOCGenerator(pkmRoot: root)
            await generator.regenerateAll()
            if Task.isCancelled { return }

            // 5. Semantic linking
            await MainActor.run { vaultCheckPhase = "노트 간 시맨틱 연결 중..." }
            let linker = SemanticLinker(pkmRoot: root)
            let linkResult = await linker.linkAll { progress, status in
                Task { @MainActor in
                    vaultCheckPhase = status
                }
            }
            let semanticLinksCreated = linkResult.linksCreated

            StatisticsService.recordActivity(
                fileName: "볼트 점검",
                category: "system",
                action: "completed",
                detail: "\(report.totalIssues)건 발견, \(repairCount)건 복구, \(enrichCount)개 보완, \(semanticLinksCreated)개 링크"
            )

            let snapshot = VaultCheckResult(
                brokenLinks: report.brokenLinks.count,
                missingFrontmatter: report.missingFrontmatter.count,
                missingPARA: report.missingPARA.count,
                untaggedFiles: report.untaggedFiles.count,
                repairCount: repairCount,
                enrichCount: enrichCount,
                mocUpdated: true,
                linksCreated: semanticLinksCreated
            )
            await MainActor.run {
                vaultCheckResult = snapshot
                refreshStats()
            }
        }
    }

    // MARK: - Activity Detail View

    @ViewBuilder
    private func activityDetailView(_ entry: ActivityEntry) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 6) {
                Text(actionLabel(for: entry.action))
                    .font(.caption2)
                    .fontWeight(.medium)
                    .foregroundColor(activityColor(for: entry.action))

                if entry.category != "system" {
                    Text("·")
                        .foregroundColor(.secondary)
                    Text(categoryLabel(for: entry.category))
                        .font(.caption2)
                        .foregroundColor(.secondary)
                }
            }

            if !entry.detail.isEmpty {
                Text(entry.detail)
                    .font(.caption2)
                    .foregroundColor(.primary.opacity(0.7))
                    .lineLimit(3)
            }

            Text(fullDate(entry.date))
                .font(.caption2)
                .foregroundColor(.secondary)
        }
        .padding(.horizontal, 24)
        .padding(.vertical, 6)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.primary.opacity(0.02))
        .cornerRadius(4)
    }

    private func activityIcon(for action: String) -> String {
        switch action {
        case "classified": return "checkmark.circle.fill"
        case "reorganized": return "arrow.triangle.2.circlepath"
        case "relocated": return "arrow.right.circle.fill"
        case "vault-reorganized": return "arrow.triangle.swap"
        case "deduplicated": return "doc.on.doc.fill"
        case "deleted": return "trash.circle.fill"
        case "started": return "play.circle.fill"
        case "completed": return "checkmark.seal.fill"
        case "error": return "exclamationmark.triangle.fill"
        default: return "circle.fill"
        }
    }

    private func activityColor(for action: String) -> Color {
        switch action {
        case "classified", "reorganized", "completed": return .green
        case "deleted": return .red
        case "error": return .red
        default: return .secondary
        }
    }

    private func actionLabel(for action: String) -> String {
        switch action {
        case "classified": return "분류 완료"
        case "reorganized": return "정리 완료"
        case "relocated": return "위치 이동"
        case "vault-reorganized": return "재정리 이동"
        case "deduplicated": return "중복 제거"
        case "deleted": return "삭제"
        case "started": return "처리 시작"
        case "completed": return "처리 완료"
        case "error": return "오류"
        default: return action
        }
    }

    private func categoryLabel(for category: String) -> String {
        switch category {
        case "project": return "프로젝트"
        case "area": return "영역"
        case "resource": return "자료"
        case "archive": return "아카이브"
        case "system": return "시스템"
        default: return category
        }
    }

    private func relativeDate(_ date: Date) -> String {
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .abbreviated
        return formatter.localizedString(for: date, relativeTo: Date())
    }

    private func fullDate(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd HH:mm"
        return formatter.string(from: date)
    }
}

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

struct DashboardCardGroup<Content: View>: View {
    let label: String
    let description: String?
    let tint: Color
    let content: () -> Content

    init(
        label: String,
        description: String? = nil,
        tint: Color,
        @ViewBuilder content: @escaping () -> Content
    ) {
        self.label = label
        self.description = description
        self.tint = tint
        self.content = content
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 4) {
                RoundedRectangle(cornerRadius: 1)
                    .fill(tint.opacity(0.5))
                    .frame(width: 2, height: 10)
                Text(label)
                    .font(.caption2)
                    .fontWeight(.semibold)
                    .foregroundColor(tint.opacity(0.7))
                    .textCase(.uppercase)
                if let description {
                    Text(description)
                        .font(.caption2)
                        .foregroundColor(.secondary.opacity(0.7))
                }
            }
            .padding(.leading, 4)

            HStack(spacing: 8) {
                content()
            }
        }
    }
}

struct DashboardHubCard: View {
    let icon: String
    let title: String
    let subtitle: String
    var tint: Color = .accentColor
    var isDisabled: Bool = false
    let action: () -> Void

    @State private var isHovered = false

    var body: some View {
        Button(action: action) {
            VStack(spacing: 4) {
                ZStack {
                    Circle()
                        .fill(tint.opacity(isHovered ? 0.15 : 0.08))
                        .frame(width: 28, height: 28)
                    Image(systemName: icon)
                        .font(.system(size: 12, weight: .medium))
                        .foregroundColor(tint)
                }

                Text(title)
                    .font(.caption)
                    .fontWeight(.semibold)

                Text(subtitle)
                    .font(.caption2)
                    .foregroundColor(.secondary)
                    .lineLimit(1)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 8)
            .background(
                RoundedRectangle(cornerRadius: 8)
                    .fill(isHovered ? tint.opacity(0.06) : Color.primary.opacity(0.02))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 8)
                    .strokeBorder(isHovered ? tint.opacity(0.2) : Color.primary.opacity(0.06), lineWidth: 0.5)
            )
        }
        .buttonStyle(.plain)
        .disabled(isDisabled)
        .opacity(isDisabled ? 0.5 : 1)
        .onHover { isHovered = $0 }
        .animation(.easeOut(duration: 0.15), value: isHovered)
    }
}

struct AuditRow: View {
    let icon: String
    let label: String
    let count: Int

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: icon)
                .font(.caption)
                .foregroundColor(count > 0 ? .orange : .green)
                .frame(width: 16)
            Text(label)
                .font(.caption)
            Spacer()
            Text("\(count)건")
                .font(.caption)
                .monospacedDigit()
                .foregroundColor(count > 0 ? .primary : .secondary)
        }
    }
}

struct AuditRepairRow: View {
    let icon: String
    let label: String

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: icon)
                .font(.caption)
                .foregroundColor(.green)
                .frame(width: 16)
            Text(label)
                .font(.caption)
                .foregroundColor(.green)
            Spacer()
        }
    }
}

struct InlineProgress: View {
    let message: String

    var body: some View {
        HStack(spacing: 8) {
            ProgressView()
                .controlSize(.small)
            Text(message)
                .font(.caption)
                .foregroundColor(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
    }
}

struct InlineResult: View {
    let icon: String
    let message: String
    let onDismiss: () -> Void

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: icon)
                .font(.caption)
                .foregroundColor(.green)
            Text(message)
                .font(.caption)
                .foregroundColor(.green)
            Spacer()
            Button(action: onDismiss) {
                Image(systemName: "xmark")
                    .font(.caption2)
                    .foregroundColor(.secondary)
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(Color.green.opacity(0.06))
        .cornerRadius(6)
        .padding(.top, 4)
    }
}

struct DashboardActionButton: View {
    let icon: String
    let title: String
    let subtitle: String
    var isDisabled: Bool = false
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 10) {
                Image(systemName: icon)
                    .font(.system(size: 16))
                    .foregroundColor(.accentColor)
                    .frame(width: 24)

                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .font(.subheadline)
                        .fontWeight(.medium)
                    Text(subtitle)
                        .font(.caption2)
                        .foregroundColor(.secondary)
                        .lineLimit(1)
                }

                Spacer()

                Image(systemName: "chevron.right")
                    .font(.caption2)
                    .foregroundColor(.secondary)
            }
            .padding(.vertical, 4)
            .frame(maxWidth: .infinity)
        }
        .buttonStyle(.bordered)
        .controlSize(.regular)
        .disabled(isDisabled)
    }
}
