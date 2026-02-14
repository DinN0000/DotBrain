import SwiftUI

struct DashboardView: View {
    @EnvironmentObject var appState: AppState
    @State private var stats = PKMStatistics()
    @State private var auditReport: AuditReport?
    @State private var isAuditing: Bool = false
    @State private var repairResult: RepairResult?
    @State private var statusMessage: String = ""
    @State private var isEnriching: Bool = false
    @State private var isMOCRegenerating: Bool = false

    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                Button(action: { appState.currentScreen = .inbox }) {
                    Image(systemName: "chevron.left")
                }
                .buttonStyle(.plain)

                Text("대시보드")
                    .font(.headline)

                Spacer()
            }
            .padding()

            Divider()

            ScrollView {
                VStack(spacing: 16) {
                    // Summary cards
                    HStack(spacing: 12) {
                        StatCard(title: "전체 파일", value: "\(stats.totalFiles)", icon: "doc.fill")
                        StatCard(title: "중복 발견", value: "\(stats.duplicatesFound)", icon: "doc.on.doc.fill")
                        StatCard(title: "API 비용", value: String(format: "$%.3f", stats.apiCost), icon: "dollarsign.circle.fill")
                    }

                    // MOC regeneration button
                    Button(action: {
                        guard !isMOCRegenerating else { return }
                        isMOCRegenerating = true
                        let rootPath = appState.pkmRootPath
                        Task.detached(priority: .userInitiated) {
                            let mocGenerator = MOCGenerator(pkmRoot: rootPath)
                            await mocGenerator.regenerateAll()
                            await MainActor.run { isMOCRegenerating = false }
                        }
                    }) {
                        HStack {
                            Image(systemName: "doc.text.magnifyingglass")
                            Text("MOC 전체 갱신")
                        }
                        .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.regular)
                    .disabled(isMOCRegenerating)

                    // Full audit button
                    Button(action: {
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
                    }) {
                        HStack {
                            Image(systemName: "checkmark.shield")
                            Text("전체 점검")
                        }
                        .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.regular)
                    .disabled(isAuditing)

                    // PARA management button
                    Button(action: { appState.currentScreen = .paraManage }) {
                        HStack {
                            Image(systemName: "folder.badge.gearshape")
                            Text("PARA 관리")
                        }
                        .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.regular)

                    // Vault-wide reorganization button
                    Button(action: { appState.currentScreen = .vaultReorganize }) {
                        HStack {
                            Image(systemName: "arrow.triangle.2.circlepath")
                            Text("전체 재정리")
                        }
                        .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.regular)

                    // Note enrichment button
                    Button(action: {
                        guard !isEnriching else { return }
                        isEnriching = true
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
                                statusMessage = "\(total)개 노트 메타데이터 보완 완료"
                                isEnriching = false
                            }
                        }
                    }) {
                        HStack {
                            Image(systemName: "text.badge.star")
                            Text("노트 메타데이터 보완")
                        }
                        .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.regular)
                    .disabled(isEnriching)

                    if !statusMessage.isEmpty {
                        Text(statusMessage)
                            .font(.caption)
                            .foregroundColor(.green)
                            .padding(.vertical, 4)
                    }

                    // Audit progress / results
                    if isAuditing {
                        HStack(spacing: 8) {
                            ProgressView()
                                .controlSize(.small)
                            Text("볼트 점검 중...")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 8)
                    }

                    if let report = auditReport {
                        auditResultsView(report: report)
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
