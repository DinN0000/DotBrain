import SwiftUI

struct DashboardView: View {
    @EnvironmentObject var appState: AppState
    @State private var stats = PKMStatistics()
    @State private var auditReport: AuditReport?
    @State private var isAuditing: Bool = false
    @State private var repairResult: RepairResult?
    @State private var isEnriching: Bool = false
    @State private var enrichResult: Int?
    @State private var isMOCRegenerating: Bool = false
    @State private var mocDone: Bool = false

    var body: some View {
        VStack(spacing: 0) {
            BreadcrumbView(current: .dashboard)

            Divider()

            ScrollView {
                VStack(spacing: 16) {
                    // Summary cards
                    HStack(spacing: 12) {
                        StatCard(title: "전체 파일", value: "\(stats.totalFiles)", icon: "doc.fill")
                        StatCard(title: "중복 발견", value: "\(stats.duplicatesFound)", icon: "doc.on.doc.fill")
                        StatCard(title: "API 비용", value: String(format: "$%.3f", stats.apiCost), icon: "dollarsign.circle.fill")
                    }

                    // PARA management button
                    DashboardActionButton(
                        icon: "folder.badge.gearshape",
                        title: "PARA 관리",
                        subtitle: "폴더 이동 · 아카이브 · 복원"
                    ) {
                        appState.currentScreen = .paraManage
                    }

                    // Vault-wide reorganization button
                    DashboardActionButton(
                        icon: "arrow.triangle.2.circlepath",
                        title: "파일 위치 점검",
                        subtitle: "AI가 잘못된 위치의 파일을 찾아 이동 제안"
                    ) {
                        appState.currentScreen = .vaultReorganize
                    }

                    // --- 오류 검사 + inline results ---
                    VStack(spacing: 0) {
                        DashboardActionButton(
                            icon: "checkmark.shield",
                            title: "오류 검사",
                            subtitle: "깨진 링크 · 누락 태그 · 분류 오류 탐지",
                            isDisabled: isAuditing
                        ) {
                            isAuditing = true
                            auditReport = nil
                            repairResult = nil
                            let rootPath = appState.pkmRootPath
                            Task.detached(priority: .userInitiated) {
                                let auditor = VaultAuditor(pkmRoot: rootPath)
                                let report = auditor.audit()
                                await MainActor.run {
                                    auditReport = report
                                    isAuditing = false
                                }
                            }
                        }

                        if isAuditing {
                            InlineProgress(message: "볼트 점검 중...")
                        }

                        if let report = auditReport {
                            auditResultsView(report: report)
                                .padding(.top, 6)
                        }
                    }

                    // --- 태그 · 요약 보완 + inline results ---
                    VStack(spacing: 0) {
                        DashboardActionButton(
                            icon: "text.badge.star",
                            title: "태그 · 요약 보완",
                            subtitle: "비어있는 메타데이터를 AI로 보완",
                            isDisabled: isEnriching
                        ) {
                            guard !isEnriching else { return }
                            isEnriching = true
                            enrichResult = nil
                            let rootPath = appState.pkmRootPath
                            Task.detached(priority: .userInitiated) {
                                let enricher = NoteEnricher(pkmRoot: rootPath)
                                let pathManager = PKMPathManager(root: rootPath)
                                let fm = FileManager.default
                                let categories = [pathManager.projectsPath, pathManager.areaPath, pathManager.resourcePath]
                                var count = 0

                                for basePath in categories {
                                    guard let folders = try? fm.contentsOfDirectory(atPath: basePath) else { continue }
                                    for folder in folders where !folder.hasPrefix(".") && !folder.hasPrefix("_") {
                                        let folderPath = (basePath as NSString).appendingPathComponent(folder)
                                        let results = await enricher.enrichFolder(at: folderPath)
                                        count += results.count
                                    }
                                }

                                let total = count
                                await MainActor.run {
                                    enrichResult = total
                                    isEnriching = false
                                }
                            }
                        }

                        if isEnriching {
                            InlineProgress(message: "메타데이터 보완 중...")
                        }

                        if let count = enrichResult {
                            InlineResult(
                                icon: "checkmark.circle.fill",
                                message: "\(count)개 노트 메타데이터 보완 완료"
                            ) {
                                enrichResult = nil
                            }
                        }
                    }

                    // --- 폴더 요약 갱신 + inline results ---
                    VStack(spacing: 0) {
                        DashboardActionButton(
                            icon: "doc.text.magnifyingglass",
                            title: "폴더 요약 갱신",
                            subtitle: "각 폴더의 인덱스 노트를 최신 내용으로 재생성",
                            isDisabled: isMOCRegenerating
                        ) {
                            guard !isMOCRegenerating else { return }
                            isMOCRegenerating = true
                            mocDone = false
                            let rootPath = appState.pkmRootPath
                            Task.detached(priority: .userInitiated) {
                                let mocGenerator = MOCGenerator(pkmRoot: rootPath)
                                await mocGenerator.regenerateAll()
                                await MainActor.run {
                                    isMOCRegenerating = false
                                    mocDone = true
                                }
                            }
                        }

                        if isMOCRegenerating {
                            InlineProgress(message: "인덱스 노트 재생성 중...")
                        }

                        if mocDone {
                            InlineResult(
                                icon: "checkmark.circle.fill",
                                message: "모든 폴더 요약 갱신 완료"
                            ) {
                                mocDone = false
                            }
                        }
                    }

                    // Category breakdown
                    VStack(alignment: .leading, spacing: 8) {
                        Text("카테고리별 파일")
                            .font(.subheadline)
                            .fontWeight(.medium)

                        let maxCount = max(stats.byCategory.values.max() ?? 1, 1)

                        CategoryBar(label: "Project", count: stats.byCategory["project"] ?? 0, maxCount: maxCount, color: .blue)
                        CategoryBar(label: "Area", count: stats.byCategory["area"] ?? 0, maxCount: maxCount, color: .green)
                        CategoryBar(label: "Resource", count: stats.byCategory["resource"] ?? 0, maxCount: maxCount, color: .orange)
                        CategoryBar(label: "Archive", count: stats.byCategory["archive"] ?? 0, maxCount: maxCount, color: .gray)
                    }
                    .padding()
                    .background(Color.primary.opacity(0.03))
                    .cornerRadius(8)

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
                                HStack(spacing: 8) {
                                    Image(systemName: activityIcon(for: entry.action))
                                        .font(.caption)
                                        .foregroundColor(activityColor(for: entry.action))
                                        .frame(width: 16)

                                    Text(entry.fileName)
                                        .font(.caption)
                                        .lineLimit(1)

                                    Spacer()

                                    Text(entry.category)
                                        .font(.caption2)
                                        .foregroundColor(.secondary)

                                    Text(relativeDate(entry.date))
                                        .font(.caption2)
                                        .foregroundColor(.secondary)
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
            let service = StatisticsService(pkmRoot: appState.pkmRootPath)
            stats = service.collectStatistics()
        }
    }

    private func activityIcon(for action: String) -> String {
        switch action {
        case "classified": return "checkmark.circle.fill"
        case "deduplicated": return "doc.on.doc.fill"
        case "deleted": return "trash.circle.fill"
        default: return "circle.fill"
        }
    }

    private func activityColor(for action: String) -> Color {
        switch action {
        case "classified": return .green
        case "deduplicated": return .blue
        case "deleted": return .red
        default: return .secondary
        }
    }

    private func relativeDate(_ date: Date) -> String {
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .abbreviated
        return formatter.localizedString(for: date, relativeTo: Date())
    }

    // MARK: - Audit Results

    @ViewBuilder
    private func auditResultsView(report: AuditReport) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("점검 결과")
                    .font(.subheadline)
                    .fontWeight(.medium)
                Spacer()
                Text("총 \(report.totalScanned)개 파일 검사")
                    .font(.caption2)
                    .foregroundColor(.secondary)
            }

            Divider()

            AuditRow(icon: "link", label: "깨진 링크", count: report.brokenLinks.count)
            AuditRow(icon: "doc.badge.ellipsis", label: "프론트매터 누락", count: report.missingFrontmatter.count)
            AuditRow(icon: "tag", label: "태그 없음", count: report.untaggedFiles.count)
            AuditRow(icon: "folder.badge.questionmark", label: "PARA 미지정", count: report.missingPARA.count)

            if let result = repairResult {
                Divider()

                if result.linksFixed > 0 {
                    AuditRepairRow(icon: "checkmark.circle.fill", label: "링크 \(result.linksFixed)건 수정")
                }
                if result.frontmatterInjected > 0 {
                    AuditRepairRow(icon: "checkmark.circle.fill", label: "프론트매터 \(result.frontmatterInjected)건 주입")
                }
                if result.paraFixed > 0 {
                    AuditRepairRow(icon: "checkmark.circle.fill", label: "PARA \(result.paraFixed)건 수정")
                }
                if result.linksFixed == 0 && result.frontmatterInjected == 0 && result.paraFixed == 0 {
                    AuditRepairRow(icon: "checkmark.circle.fill", label: "수정할 항목 없음")
                }
            }

            HStack(spacing: 8) {
                if report.totalIssues > 0 && repairResult == nil {
                    Button(action: {
                        let rootPath = appState.pkmRootPath
                        Task.detached(priority: .userInitiated) {
                            let auditor = VaultAuditor(pkmRoot: rootPath)
                            let result = auditor.repair(report: report)
                            await MainActor.run {
                                repairResult = result
                            }
                        }
                    }) {
                        HStack(spacing: 4) {
                            Image(systemName: "wrench.and.screwdriver")
                            Text("자동 복구")
                        }
                        .font(.caption)
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.small)
                }

                Spacer()

                Button(action: {
                    auditReport = nil
                    repairResult = nil
                }) {
                    Text("닫기")
                        .font(.caption)
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
            }
            .padding(.top, 4)
        }
        .padding()
        .background(Color.primary.opacity(0.03))
        .cornerRadius(8)
    }
}

struct StatCard: View {
    let title: String
    let value: String
    let icon: String

    var body: some View {
        VStack(spacing: 4) {
            Image(systemName: icon)
                .font(.title3)
                .foregroundColor(.accentColor)
            Text(value)
                .font(.headline)
                .monospacedDigit()
            Text(title)
                .font(.caption2)
                .foregroundColor(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 8)
        .background(Color.primary.opacity(0.03))
        .cornerRadius(8)
    }
}

struct CategoryBar: View {
    let label: String
    let count: Int
    let maxCount: Int
    let color: Color

    var body: some View {
        HStack(spacing: 8) {
            Text(label)
                .font(.caption)
                .frame(width: 60, alignment: .leading)

            GeometryReader { geo in
                RoundedRectangle(cornerRadius: 3)
                    .fill(color.opacity(0.7))
                    .frame(width: max(4, geo.size.width * CGFloat(count) / CGFloat(maxCount)))
            }
            .frame(height: 14)

            Text("\(count)")
                .font(.caption)
                .monospacedDigit()
                .foregroundColor(.secondary)
                .frame(width: 30, alignment: .trailing)
        }
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
