import SwiftUI

struct DashboardView: View {
    @EnvironmentObject var appState: AppState
    @State private var stats = PKMStatistics()

    var body: some View {
        VStack(spacing: 0) {
            BreadcrumbView(current: .dashboard)

            Divider()

            ScrollView {
                VStack(spacing: 16) {
                    // Summary line
                    HStack(spacing: 6) {
                        Image(systemName: "doc.fill")
                            .font(.caption)
                            .foregroundColor(.secondary)
                        Text("전체 \(stats.totalFiles)개")
                            .font(.subheadline)
                            .fontWeight(.medium)

                        Spacer()

                        let p = stats.byCategory["project"] ?? 0
                        let a = stats.byCategory["area"] ?? 0
                        let r = stats.byCategory["resource"] ?? 0
                        let ar = stats.byCategory["archive"] ?? 0

                        Text("P \(p)")
                            .foregroundColor(.blue)
                        Text("·")
                            .foregroundColor(.secondary)
                        Text("A \(a)")
                            .foregroundColor(.green)
                        Text("·")
                            .foregroundColor(.secondary)
                        Text("R \(r)")
                            .foregroundColor(.orange)
                        Text("·")
                            .foregroundColor(.secondary)
                        Text("AR \(ar)")
                            .foregroundColor(.gray)
                    }
                    .font(.caption)
                    .monospacedDigit()
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                    .background(Color.primary.opacity(0.03))
                    .cornerRadius(8)

                    // Hub cards 2x2
                    LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 10) {
                        DashboardHubCard(
                            icon: "folder.badge.gearshape",
                            title: "PARA 관리",
                            subtitle: "폴더 이동 · 생성"
                        ) {
                            appState.currentScreen = .paraManage
                        }
                        DashboardHubCard(
                            icon: "list.bullet.clipboard",
                            title: "프로젝트 관리",
                            subtitle: "추가 · 아카이브"
                        ) {
                            appState.currentScreen = .projectManage
                        }
                        DashboardHubCard(
                            icon: "magnifyingglass",
                            title: "검색",
                            subtitle: "파일 · 태그 검색"
                        ) {
                            appState.currentScreen = .search
                        }
                        DashboardHubCard(
                            icon: "wrench.and.screwdriver",
                            title: "볼트 관리",
                            subtitle: "오류 검사 · 정리 · 보완"
                        ) {
                            appState.currentScreen = .vaultManage
                        }
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
                            ForEach(stats.recentActivity.prefix(5)) { entry in
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

struct DashboardHubCard: View {
    let icon: String
    let title: String
    let subtitle: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(spacing: 6) {
                Image(systemName: icon)
                    .font(.system(size: 20))
                    .foregroundColor(.accentColor)

                Text(title)
                    .font(.subheadline)
                    .fontWeight(.medium)

                Text(subtitle)
                    .font(.caption2)
                    .foregroundColor(.secondary)
                    .lineLimit(1)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 14)
        }
        .buttonStyle(.bordered)
        .controlSize(.regular)
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
