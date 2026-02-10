import SwiftUI

struct MenuBarPopover: View {
    @EnvironmentObject var appState: AppState

    var body: some View {
        VStack(spacing: 0) {
            switch appState.currentScreen {
            case .inbox:
                InboxStatusView()
            case .processing:
                ProcessingView()
            case .results:
                ResultsView()
            case .settings:
                SettingsView()
            }

            // Footer
            if appState.currentScreen != .settings {
                Divider()
                HStack {
                    Button(action: { appState.currentScreen = .settings }) {
                        Image(systemName: "gear")
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
        .frame(width: 360, height: 480)
    }
}
