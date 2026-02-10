import SwiftUI

struct ResultsView: View {
    @EnvironmentObject var appState: AppState

    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                Text("정리 결과")
                    .font(.headline)

                Spacer()

                let successCount = appState.processedResults.filter(\.isSuccess).count
                let totalCount = appState.processedResults.count + appState.pendingConfirmations.count
                Text("\(successCount)/\(totalCount)")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
            }
            .padding()

            Divider()

            // Results list
            ScrollView {
                LazyVStack(spacing: 2) {
                    // Processed files
                    ForEach(appState.processedResults) { result in
                        ResultRow(result: result)
                    }

                    // Pending confirmations
                    ForEach(appState.pendingConfirmations) { confirmation in
                        ConfirmationRow(confirmation: confirmation)
                    }
                }
                .padding(.horizontal)
                .padding(.vertical, 8)
            }

            Divider()

            // Action buttons
            HStack {
                Button("돌아가기") {
                    appState.resetToInbox()
                }
                .buttonStyle(.bordered)
                .controlSize(.small)

                Spacer()

                if !appState.processedResults.isEmpty {
                    Button("Finder에서 열기") {
                        openInFinder()
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                }
            }
            .padding()
        }
    }

    private func openInFinder() {
        if let firstSuccess = appState.processedResults.first(where: \.isSuccess) {
            let dir = (firstSuccess.targetPath as NSString).deletingLastPathComponent
            NSWorkspace.shared.selectFile(firstSuccess.targetPath, inFileViewerRootedAtPath: dir)
        }
    }
}

// MARK: - Row Views

struct ResultRow: View {
    let result: ProcessedFileResult

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: result.isSuccess ? "checkmark.circle.fill" : "xmark.circle.fill")
                .foregroundColor(result.isSuccess ? .green : .red)
                .font(.system(size: 14))

            VStack(alignment: .leading, spacing: 2) {
                Text(result.fileName)
                    .font(.system(.body, design: .monospaced))
                    .lineLimit(1)

                if result.isSuccess {
                    HStack(spacing: 4) {
                        Image(systemName: result.para.icon)
                            .font(.caption2)
                        Text(result.displayTarget)
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                } else if let error = result.error {
                    Text(error)
                        .font(.caption)
                        .foregroundColor(.red)
                }
            }

            Spacer()
        }
        .padding(.vertical, 4)
    }
}

struct ConfirmationRow: View {
    let confirmation: PendingConfirmation
    @EnvironmentObject var appState: AppState

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 8) {
                Image(systemName: "questionmark.circle.fill")
                    .foregroundColor(.orange)
                    .font(.system(size: 14))

                Text(confirmation.fileName)
                    .font(.system(.body, design: .monospaced))
                    .lineLimit(1)

                Spacer()
            }

            // Option buttons
            HStack(spacing: 6) {
                ForEach(Array(confirmation.options.prefix(4).enumerated()), id: \.offset) { _, option in
                    Button(action: {
                        Task {
                            await appState.confirmClassification(confirmation, choice: option)
                        }
                    }) {
                        VStack(spacing: 2) {
                            Image(systemName: option.para.icon)
                                .font(.caption)
                            Text(option.para.displayName)
                                .font(.caption2)
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 4)
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                }
            }
        }
        .padding(.vertical, 6)
        .padding(.horizontal, 4)
        .background(Color.orange.opacity(0.05))
        .cornerRadius(8)
    }
}
