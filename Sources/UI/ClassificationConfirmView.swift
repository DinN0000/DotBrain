import SwiftUI

/// Detailed confirmation view for uncertain classifications
struct ClassificationConfirmView: View {
    let confirmation: PendingConfirmation
    @EnvironmentObject var appState: AppState
    @Environment(\.dismiss) var dismiss

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            // File info
            HStack {
                Image(systemName: "doc.questionmark")
                    .font(.title2)
                    .foregroundColor(.orange)

                VStack(alignment: .leading) {
                    Text(confirmation.fileName)
                        .font(.headline)
                    Text("분류 확인이 필요합니다")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }

                Spacer()
            }

            Divider()

            // Content preview
            Text("미리보기:")
                .font(.subheadline)
                .fontWeight(.medium)

            ScrollView {
                Text(confirmation.content)
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .frame(maxHeight: 120)
            .padding(8)
            .background(Color.secondary.opacity(0.05))
            .cornerRadius(8)

            Divider()

            // Classification options
            Text("어디에 분류할까요?")
                .font(.subheadline)
                .fontWeight(.medium)

            ForEach(Array(confirmation.options.enumerated()), id: \.offset) { _, option in
                Button(action: {
                    Task {
                        await appState.confirmClassification(confirmation, choice: option)
                        dismiss()
                    }
                }) {
                    HStack {
                        Image(systemName: option.para.icon)
                        VStack(alignment: .leading) {
                            Text(option.para.displayName)
                                .fontWeight(.medium)
                            if !option.targetFolder.isEmpty {
                                Text(option.targetFolder)
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            }
                            if let project = option.project {
                                Text(project)
                                    .font(.caption)
                                    .foregroundColor(.blue)
                            }
                        }
                        Spacer()
                        if option.confidence >= 0.5 {
                            Text("추천")
                                .font(.caption2)
                                .padding(.horizontal, 6)
                                .padding(.vertical, 2)
                                .background(Color.green.opacity(0.2))
                                .cornerRadius(4)
                        }
                    }
                    .padding(8)
                    .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
            }
        }
        .padding()
    }
}
