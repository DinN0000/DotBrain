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
            case .dashboard:
                DashboardView()
            case .search:
                SearchView()
            case .projectManage:
                ProjectManageView()
            case .paraManage:
                PARAManageView()
            case .vaultReorganize:
                VaultReorganizeView()
            }

            // Footer (hidden during onboarding, settings, and processing)
            if appState.currentScreen != .settings && appState.currentScreen != .onboarding {
                Divider()
                HStack {
                    Button(action: { appState.currentScreen = .settings }) {
                        Image(systemName: "gear")
                            .foregroundColor(.secondary)
                    }
                    .buttonStyle(.plain)

                    Button(action: { appState.currentScreen = .dashboard }) {
                        Image(systemName: "chart.bar.fill")
                            .foregroundColor(.secondary)
                    }
                    .buttonStyle(.plain)

                    Button(action: { appState.currentScreen = .search }) {
                        Image(systemName: "magnifyingglass")
                            .foregroundColor(.secondary)
                    }
                    .buttonStyle(.plain)

                    Button(action: {
                        if let url = URL(string: "https://github.com/DinN0000/DotBrain#readme") {
                            NSWorkspace.shared.open(url)
                        }
                    }) {
                        Image(systemName: "questionmark.circle")
                            .foregroundColor(.secondary)
                    }
                    .buttonStyle(.plain)
                    .help("도움말")

                    Spacer()

                    Text("DotBrain")
                        .font(.caption)
                        .foregroundColor(.secondary)

                    Spacer()

                    Button(action: { NSApp.terminate(nil) }) {
                        Image(systemName: "power")
                            .foregroundColor(.secondary)
                    }
                    .buttonStyle(.plain)
                }
                .padding(.horizontal)
                .padding(.vertical, 8)
            }
        }
        .frame(width: 360, height: 480)
    }
}
