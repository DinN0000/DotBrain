import SwiftUI

struct AIStatisticsView: View {
    @EnvironmentObject var appState: AppState
    @State private var selectedYear: Int = Calendar.current.component(.year, from: Date())
    @State private var selectedMonth: Int = Calendar.current.component(.month, from: Date())
    @State private var monthlyCost: Double = 0
    @State private var monthlyTokens: Int = 0
    @State private var costByOp: [String: Double] = [:]
    @State private var tokensByOp: [String: Int] = [:]
    @State private var recentEntries: [APIUsageEntry] = []
    @State private var earliestDate: Date?
    @State private var isLoading = true
    @State private var showEstimateInfo = false

    private let maxMonthsBack = 6

    var body: some View {
        VStack(spacing: 0) {
            BreadcrumbView(current: .aiStatistics)
            Divider()

            if isLoading {
                Spacer()
                ProgressView()
                Spacer()
            } else {
                ScrollView {
                    VStack(spacing: 16) {
                        monthNavigator
                        heroSection
                        if showEstimateInfo { estimateDisclaimer }
                        operationBreakdown
                        recentCallsList
                        emptyState
                    }
                    .padding()
                }
            }
        }
        .onAppear { loadStats() }
    }

    // MARK: - Month Navigator

    private var monthNavigator: some View {
        HStack {
            Button(action: { navigateMonth(-1) }) {
                Image(systemName: "chevron.left")
                    .font(.caption)
            }
            .buttonStyle(.plain)
            .disabled(!canGoBack)

            Spacer()

            Text(monthTitle)
                .font(.caption)
                .fontWeight(.semibold)

            Spacer()

            Button(action: { navigateMonth(1) }) {
                Image(systemName: "chevron.right")
                    .font(.caption)
            }
            .buttonStyle(.plain)
            .disabled(!canGoForward)
        }
        .padding(.horizontal, 4)
    }

    // MARK: - Hero Section

    private var heroSection: some View {
        VStack(spacing: 12) {
            HStack(spacing: 24) {
                VStack(spacing: 4) {
                    HStack(spacing: 2) {
                        Text(L10n.AIStats.estimatedCost)
                            .font(.caption)
                            .foregroundColor(.secondary)
                        infoButton
                    }
                    Text("~" + String(format: "$%.4f", monthlyCost))
                        .font(.system(.title3, design: .monospaced))
                        .fontWeight(.bold)
                }

                VStack(spacing: 4) {
                    HStack(spacing: 2) {
                        Text(L10n.AIStats.estimatedTokens)
                            .font(.caption)
                            .foregroundColor(.secondary)
                        infoButton
                    }
                    Text("~" + formatTokenCount(monthlyTokens))
                        .font(.system(.title3, design: .monospaced))
                        .fontWeight(.bold)
                }
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 16)
        .background(Color.primary.opacity(0.03))
        .cornerRadius(12)
    }

    private var infoButton: some View {
        Button(action: { showEstimateInfo.toggle() }) {
            Image(systemName: "info.circle")
                .font(.caption2)
                .foregroundColor(.secondary)
        }
        .buttonStyle(.plain)
    }

    private var estimateDisclaimer: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(L10n.AIStats.estimateDisclaimer)
                .font(.caption2)
                .foregroundColor(.secondary)
            Text(L10n.AIStats.estimateDisclaimerCLI)
                .font(.caption2)
                .foregroundColor(.secondary)
        }
        .padding(8)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.yellow.opacity(0.08))
        .cornerRadius(6)
    }

    // MARK: - Operation Breakdown

    @ViewBuilder
    private var operationBreakdown: some View {
        if !costByOp.isEmpty {
            VStack(alignment: .leading, spacing: 8) {
                Text(L10n.AIStats.costByOperation)
                    .font(.caption)
                    .fontWeight(.semibold)
                    .foregroundColor(.secondary)

                ForEach(sortedOperations, id: \.key) { op in
                    HStack {
                        Text(operationLabel(op.key))
                            .font(.caption)
                        Spacer()
                        Text("~" + String(format: "$%.4f", op.value))
                            .font(.caption)
                            .monospacedDigit()
                            .foregroundColor(.secondary)
                        Text(formatTokenCount(tokensByOp[op.key] ?? 0))
                            .font(.caption)
                            .monospacedDigit()
                            .foregroundColor(.secondary)
                            .frame(width: 50, alignment: .trailing)
                    }
                }
            }
            .padding()
            .background(Color.primary.opacity(0.03))
            .cornerRadius(8)
        }
    }

    // MARK: - Recent Calls

    @ViewBuilder
    private var recentCallsList: some View {
        if !recentEntries.isEmpty {
            VStack(alignment: .leading, spacing: 8) {
                Text(L10n.AIStats.recentCalls)
                    .font(.caption)
                    .fontWeight(.semibold)
                    .foregroundColor(.secondary)

                ForEach(recentEntries) { entry in
                    VStack(alignment: .leading, spacing: 2) {
                        HStack {
                            Text(operationLabel(entry.operation))
                                .font(.caption)
                                .fontWeight(.medium)
                            Spacer()
                            Text("~" + String(format: "$%.6f", entry.cost))
                                .font(.caption2)
                                .monospacedDigit()
                                .foregroundColor(.secondary)
                        }
                        HStack {
                            Text(shortModelName(entry.model))
                                .font(.caption2)
                                .foregroundColor(.secondary)
                            Text(formatTokenCount(entry.totalTokens))
                                .font(.caption2)
                                .foregroundColor(.secondary)
                            if entry.isEstimated {
                                Text("(\(L10n.AIStats.estimated))")
                                    .font(.caption2)
                                    .foregroundColor(.orange)
                            }
                            Spacer()
                            Text(entry.timestamp.relativeFormatted)
                                .font(.caption2)
                                .foregroundColor(.secondary)
                        }
                    }
                    .padding(.vertical, 4)

                    if entry.id != recentEntries.last?.id {
                        Divider()
                    }
                }
            }
            .padding()
            .background(Color.primary.opacity(0.03))
            .cornerRadius(8)
        }
    }

    // MARK: - Empty State

    @ViewBuilder
    private var emptyState: some View {
        if costByOp.isEmpty && recentEntries.isEmpty {
            VStack(spacing: 8) {
                Image(systemName: "chart.bar.xaxis")
                    .font(.title2)
                    .foregroundColor(.secondary)
                Text(L10n.AIStats.noUsage)
                    .font(.caption)
                    .foregroundColor(.secondary)
                Text(L10n.AIStats.noUsageHint)
                    .font(.caption2)
                    .foregroundColor(.secondary)
            }
            .padding(.vertical, 24)
        }
    }

    // MARK: - Navigation Logic

    private var monthTitle: String {
        "\(selectedYear)\(L10n.AIStats.yearSuffix) \(selectedMonth)\(L10n.AIStats.monthSuffix)"
    }

    private var canGoForward: Bool {
        let cal = Calendar.current
        let now = Date()
        return yearMonth(selectedYear, selectedMonth) < yearMonth(cal.component(.year, from: now), cal.component(.month, from: now))
    }

    private var canGoBack: Bool {
        guard let earliest = earliestDate else { return false }
        let cal = Calendar.current
        let now = Date()
        let eComps = cal.dateComponents([.year, .month], from: earliest)
        guard let eY = eComps.year, let eM = eComps.month else { return false }

        // 6 month limit from current month
        let curY = cal.component(.year, from: now)
        let curM = cal.component(.month, from: now)
        var limitY = curY
        var limitM = curM - maxMonthsBack
        if limitM < 1 { limitM += 12; limitY -= 1 }

        // Bound is the later of (earliest entry, 6-month limit)
        let bound = max(yearMonth(eY, eM), yearMonth(limitY, limitM))
        return yearMonth(selectedYear, selectedMonth) > bound
    }

    /// Encode year+month into a single comparable Int (e.g. 202603)
    private func yearMonth(_ y: Int, _ m: Int) -> Int { y * 100 + m }

    private func navigateMonth(_ delta: Int) {
        var newMonth = selectedMonth + delta
        var newYear = selectedYear
        if newMonth > 12 {
            newMonth = 1
            newYear += 1
        } else if newMonth < 1 {
            newMonth = 12
            newYear -= 1
        }
        selectedYear = newYear
        selectedMonth = newMonth
        loadStats()
    }

    // MARK: - Data Loading

    private var sortedOperations: [(key: String, value: Double)] {
        costByOp.sorted { $0.value > $1.value }
    }

    private func loadStats() {
        let root = appState.pkmRootPath
        let year = selectedYear
        let month = selectedMonth
        isLoading = true

        Task.detached(priority: .utility) {
            let logger = APIUsageLogger(pkmRoot: root)
            let summary = await logger.monthlySummary(year: year, month: month)
            let earliest = await logger.earliestEntryDate()

            await MainActor.run {
                monthlyCost = summary.totalCost
                monthlyTokens = summary.totalTokens
                costByOp = summary.costByOperation
                tokensByOp = summary.tokensByOperation
                recentEntries = summary.recentEntries
                earliestDate = earliest
                isLoading = false
            }
        }
    }

    // MARK: - Formatting

    private func formatTokenCount(_ count: Int) -> String {
        if count >= 1_000_000 {
            return String(format: "%.1fM", Double(count) / 1_000_000)
        } else if count >= 1_000 {
            return String(format: "%.1fk", Double(count) / 1_000)
        }
        return "\(count)"
    }

    private func operationLabel(_ op: String) -> String {
        switch op {
        case "classify": return L10n.AIStats.opClassify
        case "classify-stage1": return L10n.AIStats.opClassifyStage1
        case "classify-stage2": return L10n.AIStats.opClassifyStage2
        case "enrich": return L10n.AIStats.opEnrich
        case "moc": return L10n.AIStats.opMoc
        case "semantic-link", "semantic-link-context": return L10n.AIStats.opSemanticLink
        case "folder-relation-analyze": return L10n.AIStats.opFolderRelation
        case "summary": return L10n.AIStats.opSummary
        default: return op
        }
    }

    private func shortModelName(_ model: String) -> String {
        if model.contains("haiku") { return "Haiku" }
        if model.contains("sonnet") { return "Sonnet" }
        if model.contains("flash") { return "Flash" }
        if model.contains("pro") { return "Pro" }
        return model
    }

}
