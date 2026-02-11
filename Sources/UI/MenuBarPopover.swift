import SwiftUI

struct MenuBarPopover: View {
    @EnvironmentObject var appState: AppState

    var body: some View {
        ZStack {
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
                }

                // Footer (hidden during onboarding and settings)
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

                        Spacer()

                        Text("AI-PKM")
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

            // Coach mark overlay
            if appState.showCoachMarks && appState.currentScreen == .inbox {
                CoachMarkOverlay {
                    withAnimation {
                        appState.showCoachMarks = false
                        UserDefaults.standard.set(true, forKey: "hasSeenCoachMarks")
                    }
                }
            }
        }
        .frame(width: 360, height: 480)
    }
}
