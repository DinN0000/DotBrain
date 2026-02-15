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
            case .reorganize:
                ReorganizeView()
                    .id(appState.navigationId)
            case .dashboard:
                DashboardView()
            case .search:
                SearchView()
            case .projectManage:
                ProjectManageView()
            case .paraManage:
                PARAManageView()
                    .id(appState.navigationId)
            case .vaultManage:
                VaultManageView()
            case .vaultReorganize:
                VaultReorganizeView()
            }

            // Footer (hidden during onboarding and processing)
            if ![.onboarding, .processing].contains(appState.currentScreen) {
                Divider()
                HStack(spacing: 0) {
                    footerTab(icon: "tray.and.arrow.down", label: "인박스", screen: .inbox)
                    footerTab(icon: "square.grid.2x2", label: "대시보드", screen: .dashboard)
                    footerTab(icon: "gearshape", label: "설정", screen: .settings)
                }
                .padding(.horizontal, 8)
                .padding(.vertical, 6)
            }
        }
        .frame(width: 360, height: 480)
    }

    private func footerTab(icon: String, label: String, screen: AppState.Screen) -> some View {
        Button(action: { appState.currentScreen = screen }) {
            VStack(spacing: 2) {
                Image(systemName: icon)
                    .font(.system(size: 16))
                Text(label)
                    .font(.caption2)
            }
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
