import SwiftUI

struct MenuBarPopover: View {
    @EnvironmentObject var appState: AppState

    var body: some View {
        VStack(spacing: 0) {
            switch appState.currentScreen {
            case .onboarding:
                OnboardingView()
            case .inbox:
                InboxStatusView()
            case .processing:
                ProcessingView()
            case .results:
                ResultsView()
            case .settings:
                SettingsView()
            case .dashboard:
                DashboardView()
            case .search:
                SearchView()
            case .paraManage:
                PARAManageView()
                    .id(appState.navigationId)
            case .vaultInspector:
                VaultInspectorView()
            case .aiStatistics:
                AIStatisticsView()
            case .folderRelationExplorer:
                FolderRelationExplorer()
            }

            // Background task indicator (hidden when VaultInspector shows its own inline card)
            if let taskName = appState.backgroundTaskName,
               !(appState.currentScreen == .vaultInspector && taskName == "전체 점검") {
                Divider()
                VStack(spacing: 6) {
                    HStack(spacing: 8) {
                        if appState.backgroundTaskCompleted {
                            Image(systemName: "checkmark.circle.fill")
                                .font(.system(size: 14))
                                .foregroundColor(.green)
                        } else {
                            ProgressView()
                                .controlSize(.small)
                        }
                        VStack(alignment: .leading, spacing: 1) {
                            Text(taskName)
                                .font(.caption2)
                                .fontWeight(.medium)
                            if !appState.backgroundTaskPhase.isEmpty {
                                Text(appState.backgroundTaskPhase)
                                    .font(.caption2)
                                    .foregroundColor(appState.backgroundTaskCompleted ? .green : .secondary)
                                    .lineLimit(1)
                            }
                        }
                        Spacer()
                        if appState.backgroundTaskCompleted {
                            Button {
                                appState.clearBackgroundTaskCompletion()
                            } label: {
                                Image(systemName: "xmark.circle.fill")
                                    .font(.system(size: 14))
                                    .foregroundColor(.secondary.opacity(0.6))
                            }
                            .buttonStyle(.plain)
                        } else {
                            Button {
                                appState.cancelBackgroundTask()
                            } label: {
                                Image(systemName: "xmark.circle.fill")
                                    .font(.system(size: 14))
                                    .foregroundColor(.secondary)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    if !appState.backgroundTaskCompleted {
                        ProgressView(value: appState.backgroundTaskProgress)
                            .progressViewStyle(.linear)
                    }
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .background(appState.backgroundTaskCompleted
                    ? Color.green.opacity(0.06)
                    : Color.accentColor.opacity(0.06))
            }

            // Footer (hidden during onboarding and processing)
            if ![.onboarding, .processing].contains(appState.currentScreen) {
                Divider()
                HStack(spacing: 0) {
                    footerTab(icon: "tray.and.arrow.down", screen: .inbox)
                    footerTab(icon: "square.grid.2x2", screen: .dashboard)
                    footerTab(icon: "rectangle.2.swap", screen: .folderRelationExplorer)
                    footerTab(icon: "gearshape", screen: .settings)
                }
                .padding(.horizontal, 8)
                .padding(.vertical, 6)
            }
        }
        .frame(width: 360, height: 480)
        .alert("작업 충돌", isPresented: Binding(
            get: { appState.taskBlockedAlert != nil },
            set: { if !$0 { appState.taskBlockedAlert = nil } }
        )) {
            Button("확인", role: .cancel) {
                appState.taskBlockedAlert = nil
            }
        } message: {
            Text(appState.taskBlockedAlert ?? "")
        }
    }

    private func footerTab(icon: String, screen: AppState.Screen) -> some View {
        Button(action: { appState.currentScreen = screen }) {
            Image(systemName: icon)
                .font(.system(size: 18))
                .frame(maxWidth: .infinity)
                .foregroundColor(isActive(screen) ? .accentColor : .secondary)
        }
        .buttonStyle(.plain)
    }

    private func isActive(_ screen: AppState.Screen) -> Bool {
        if appState.currentScreen == screen { return true }
        var current = appState.currentScreen.parent
        while let parent = current {
            if parent == screen { return true }
            current = parent.parent
        }
        return false
    }
}
