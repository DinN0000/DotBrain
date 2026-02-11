import SwiftUI

struct ProcessingView: View {
    @EnvironmentObject var appState: AppState

    var body: some View {
        VStack(spacing: 20) {
            Spacer()

            // Spinner
            ProgressView()
                .controlSize(.large)
                .padding(.bottom, 8)

            // Progress bar
            VStack(spacing: 8) {
                ProgressView(value: appState.processingProgress)
                    .progressViewStyle(.linear)
                    .padding(.horizontal, 40)

                Text("\(Int(appState.processingProgress * 100))%")
                    .font(.title2)
                    .fontWeight(.medium)
                    .monospacedDigit()
            }

            // Status text
            Text(appState.processingStatus)
                .font(.subheadline)
                .foregroundColor(.secondary)
                .lineLimit(2)
                .multilineTextAlignment(.center)
                .padding(.horizontal)

            Spacer()

            // Cancel button
            Button(action: {
                appState.cancelProcessing()
            }) {
                Text("취소")
            }
            .buttonStyle(.bordered)
            .controlSize(.small)
            .padding(.bottom, 4)
        }
        .padding()
    }
}
