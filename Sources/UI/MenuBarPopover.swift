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
            }

            // Footer (hidden during onboarding and processing)
            if ![.onboarding, .processing].contains(appState.currentScreen) {
                Divider()
                HStack(spacing: 0) {
                    footerTab(icon: "tray.and.arrow.down", screen: .inbox)
                    footerTab(icon: "square.grid.2x2", screen: .dashboard)
                    footerTab(icon: "gearshape", screen: .settings)
                }
                .padding(.horizontal, 8)
                .padding(.vertical, 6)
            }
        }
        .frame(width: 360, height: 480)
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
