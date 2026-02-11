import SwiftUI

struct DashboardView: View {
    @EnvironmentObject var appState: AppState
    @State private var stats = PKMStatistics()

    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                Text("대시보드")
                    .font(.headline)
                Spacer()
                Button(action: { appState.currentScreen = .inbox }) {
                    Image(systemName: "xmark")
                        .foregroundColor(.secondary)
                }
                .buttonStyle(.plain)
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
