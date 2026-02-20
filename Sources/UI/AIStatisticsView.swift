import SwiftUI

struct AIStatisticsView: View {
    @EnvironmentObject var appState: AppState
    @State private var totalCost: Double = 0
    @State private var costByOperation: [String: Double] = [:]
    @State private var recentEntries: [APIUsageEntry] = []
    @State private var duplicatesFound: Int = 0
    @State private var isLoading = true

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
                        // Total cost hero
                        VStack(spacing: 4) {
                            Text("총 API 비용")
                                .font(.caption)
                                .foregroundColor(.secondary)
                            Text(String(format: "$%.4f", totalCost))
                                .font(.system(.title, design: .monospaced))
                                .fontWeight(.bold)
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 16)
                        .background(Color.primary.opacity(0.03))
                        .cornerRadius(12)

                        // Cost by operation
                        if !costByOperation.isEmpty {
                            VStack(alignment: .leading, spacing: 8) {
                                Text("작업별 비용")
                                    .font(.caption)
                                    .fontWeight(.semibold)
                                    .foregroundColor(.secondary)

                                ForEach(sortedOperations, id: \.key) { op in
                                    HStack {
                                        Text(operationLabel(op.key))
                                            .font(.caption)
                                        Spacer()
                                        Text(String(format: "$%.4f", op.value))
                                            .font(.caption)
                                            .monospacedDigit()
                                            .foregroundColor(.secondary)
                                    }
                                }
                            }
                            .padding()
                            .background(Color.primary.opacity(0.03))
                            .cornerRadius(8)
                        }

                        // Duplicates
                        if duplicatesFound > 0 {
                            HStack(spacing: 6) {
                                Image(systemName: "doc.on.doc")
                                    .font(.caption)
                                    .foregroundColor(.orange)
                                Text("중복 발견: \(duplicatesFound)건")
                                    .font(.caption)
                                Spacer()
                            }
                            .padding()
                            .background(Color.orange.opacity(0.06))
                            .cornerRadius(8)
                        }

                        // Recent API calls
                        if !recentEntries.isEmpty {
                            VStack(alignment: .leading, spacing: 8) {
                                Text("최근 API 호출")
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
                                            Text(String(format: "$%.6f", entry.cost))
                                                .font(.caption2)
                                                .monospacedDigit()
                                                .foregroundColor(.secondary)
                                        }
                                        HStack {
                                            Text(shortModelName(entry.model))
                                                .font(.caption2)
                                                .foregroundColor(.secondary)
                                            Text("\(entry.inputTokens + entry.outputTokens) tokens")
                                                .font(.caption2)
                                                .foregroundColor(.secondary)
                                            Spacer()
                                            Text(relativeDate(entry.timestamp))
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

                        if costByOperation.isEmpty && recentEntries.isEmpty {
                            VStack(spacing: 8) {
                                Image(systemName: "chart.bar.xaxis")
                                    .font(.title2)
                                    .foregroundColor(.secondary)
                                Text("아직 API 사용 기록이 없습니다")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                                Text("파일을 분류하면 여기에 비용이 표시됩니다")
                                    .font(.caption2)
                                    .foregroundColor(.secondary)
                            }
                            .padding(.vertical, 24)
                        }
                    }
                    .padding()
                }
            }
        }
        .onAppear { loadStats() }
    }

    private var sortedOperations: [(key: String, value: Double)] {
        costByOperation.sorted { $0.value > $1.value }
    }

    private func loadStats() {
        let root = appState.pkmRootPath
        isLoading = true

        Task.detached(priority: .utility) {
            let logger = APIUsageLogger(pkmRoot: root)
            let byOp = await logger.costByOperation()
            let total = await logger.totalCost()
            let recent = await logger.recentEntries(limit: 20)
            let dupes = UserDefaults.standard.integer(forKey: "pkmDuplicatesFound")

            await MainActor.run {
                totalCost = total
                costByOperation = byOp
                recentEntries = recent
                duplicatesFound = dupes
                isLoading = false
            }
        }
    }

    private func operationLabel(_ op: String) -> String {
        switch op {
        case "classify-stage1": return "분류 (1단계)"
        case "classify-stage2": return "분류 (2단계)"
        case "enrich": return "메타 보완"
        case "moc": return "폴더 요약"
        case "semantic-link": return "시맨틱 링크"
        case "summary": return "AI 요약"
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

    private func relativeDate(_ date: Date) -> String {
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .abbreviated
        return formatter.localizedString(for: date, relativeTo: Date())
    }
}
