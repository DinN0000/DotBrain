import SwiftUI

struct BreadcrumbView: View {
    @EnvironmentObject var appState: AppState
    let current: AppState.Screen
    var trailing: AnyView? = nil

    var body: some View {
        HStack(spacing: 4) {
            if let parent = current.parent {
                Button(action: { appState.currentScreen = parent }) {
                    HStack(spacing: 2) {
                        Image(systemName: "chevron.left")
                            .font(.caption)
                        Text(parent.displayName)
                            .font(.caption)
                    }
                    .foregroundColor(.secondary)
                }
                .buttonStyle(.plain)

                Text("\u{203A}")
                    .font(.caption)
                    .foregroundStyle(.quaternary)
            }

            Text(current.displayName)
                .font(.headline)

            Spacer()

            if let trailing = trailing {
                trailing
            }
        }
        .padding(.horizontal)
        .padding(.top, 12)
        .padding(.bottom, 4)
    }
}
