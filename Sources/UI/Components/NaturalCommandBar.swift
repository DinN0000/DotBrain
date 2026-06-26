import SwiftUI

struct NaturalCommandBar: View {
    @EnvironmentObject private var appState: AppState

    let context: () -> NaturalCommandContext
    let onConfirm: (NaturalCommandPlan) -> Void

    @State private var input = ""
    @State private var proposedPlan: NaturalCommandPlan?
    @State private var errorMessage: String?
    @State private var isPlanning = false
    @State private var planningTask: Task<Void, Never>?

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                Image(systemName: "text.bubble")
                    .font(.caption)
                    .foregroundColor(.secondary)
                TextField(L10n.NaturalCommand.placeholder, text: $input)
                    .textFieldStyle(.plain)
                    .font(.caption)
                    .onSubmit(submit)
                    .disabled(isPlanning)

                Button(action: submit) {
                    if isPlanning {
                        ProgressView()
                            .controlSize(.small)
                            .frame(width: 14, height: 14)
                    } else {
                        Image(systemName: "arrow.up.circle.fill")
                    }
                }
                .buttonStyle(.plain)
                .disabled(
                    isPlanning ||
                    input.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ||
                    !appState.hasAPIKey
                )
                .accessibilityLabel(L10n.NaturalCommand.plan)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 7)
            .background(Color.primary.opacity(0.04))
            .clipShape(RoundedRectangle(cornerRadius: 8))

            if let plan = proposedPlan {
                HStack(spacing: 8) {
                    Text(plan.confirmationText)
                        .font(.caption)
                        .lineLimit(2)
                    Spacer()
                    Button(L10n.Common.cancel) {
                        proposedPlan = nil
                    }
                    .buttonStyle(.plain)
                    .foregroundColor(.secondary)
                    Button(L10n.NaturalCommand.execute) {
                        proposedPlan = nil
                        input = ""
                        onConfirm(plan)
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.mini)
                    .disabled(appState.isAnyTaskRunning)
                }
                .padding(.horizontal, 8)
            }

            if let errorMessage {
                Text(errorMessage)
                    .font(.caption2)
                    .foregroundColor(.red)
                    .padding(.horizontal, 8)
            } else if !appState.hasAPIKey {
                Text(L10n.Inbox.setApiKey)
                    .font(.caption2)
                    .foregroundColor(.orange)
                    .padding(.horizontal, 8)
            }
        }
        .onDisappear {
            planningTask?.cancel()
            planningTask = nil
            isPlanning = false
        }
    }

    private func submit() {
        let request = input.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !request.isEmpty, appState.hasAPIKey, !isPlanning else { return }
        proposedPlan = nil
        errorMessage = nil
        isPlanning = true
        let snapshot = context()

        planningTask?.cancel()
        planningTask = Task {
            defer { isPlanning = false }
            do {
                let plan = try await NaturalCommandService.shared.plan(request, context: snapshot)
                guard !Task.isCancelled else { return }
                proposedPlan = plan
            } catch {
                guard !Task.isCancelled else { return }
                errorMessage = error.localizedDescription
            }
        }
    }
}
