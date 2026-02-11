import SwiftUI

/// Reusable API key input component used in Onboarding and Settings
struct APIKeyInputView: View {
    @EnvironmentObject var appState: AppState
    @State private var claudeKeyInput: String = ""
    @State private var geminiKeyInput: String = ""
    @State private var showingClaudeKey: Bool = false
    @State private var showingGeminiKey: Bool = false
    @State private var saveMessage: String = ""

    /// Whether to show the delete button when a key exists
    var showDeleteButton: Bool = true
    /// Called after a successful save
    var onSaved: (() -> Void)?

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            // Provider Selection
            VStack(alignment: .leading, spacing: 6) {
                Text("AI 제공자")
                    .font(.subheadline)
                    .fontWeight(.medium)

                Picker("", selection: $appState.selectedProvider) {
                    ForEach(AIProvider.allCases) { provider in
                        Text(provider.displayName).tag(provider)
                    }
                }
                .pickerStyle(.segmented)
                .labelsHidden()
            }

            Divider()

            // Gemini API Key
            apiKeySection(
                title: "Gemini API Key",
                keyInput: $geminiKeyInput,
                showingKey: $showingGeminiKey,
                provider: .gemini,
                hasKey: appState.hasGeminiKey
            )

            // Claude API Key
            apiKeySection(
                title: "Claude API Key",
                keyInput: $claudeKeyInput,
                showingKey: $showingClaudeKey,
                provider: .claude,
                hasKey: appState.hasClaudeKey
            )

            // Current provider status
            if appState.hasAPIKey {
                Label("\(appState.selectedProvider.displayName) 사용 중", systemImage: "checkmark.circle.fill")
                    .font(.caption)
                    .foregroundColor(.green)
            } else {
                Label("\(appState.selectedProvider.displayName) API 키 필요", systemImage: "exclamationmark.triangle.fill")
                    .font(.caption)
                    .foregroundColor(.orange)
            }
        }
        .onAppear {
            if appState.hasClaudeKey {
                claudeKeyInput = "••••••••"
            }
            if appState.hasGeminiKey {
                geminiKeyInput = "••••••••"
            }
        }
    }

    @ViewBuilder
    private func apiKeySection(
        title: String,
        keyInput: Binding<String>,
        showingKey: Binding<Bool>,
        provider: AIProvider,
        hasKey: Bool
    ) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(title)
                    .font(.caption)
                    .fontWeight(.medium)

                if hasKey {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundColor(.green)
                        .font(.caption)
                }

                if provider == appState.selectedProvider {
                    Text("(활성)")
                        .font(.caption2)
                        .foregroundColor(.blue)
                }
            }

            HStack {
                if showingKey.wrappedValue {
                    TextField(provider.keyPlaceholder, text: keyInput)
                        .textFieldStyle(.roundedBorder)
                        .font(.system(.caption, design: .monospaced))
                } else {
                    SecureField(provider.keyPlaceholder, text: keyInput)
                        .textFieldStyle(.roundedBorder)
                        .font(.caption)
                }

                Button(action: { showingKey.wrappedValue.toggle() }) {
                    Image(systemName: showingKey.wrappedValue ? "eye.slash" : "eye")
                }
                .buttonStyle(.plain)
                .font(.caption)
            }

            HStack {
                Button("저장") {
                    saveKey(keyInput.wrappedValue, provider: provider)
                }
                .buttonStyle(.bordered)
                .controlSize(.mini)
                .disabled(keyInput.wrappedValue.isEmpty || keyInput.wrappedValue == "••••••••")

                if showDeleteButton && hasKey {
                    Button("삭제") {
                        provider.deleteAPIKey()
                        keyInput.wrappedValue = ""
                        appState.updateAPIKeyStatus()
                        saveMessage = "삭제됨"
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.mini)
                }

                if !saveMessage.isEmpty {
                    Text(saveMessage)
                        .font(.caption2)
                        .foregroundColor(saveMessage == "저장 완료" ? .green : .orange)
                }
            }
        }
    }

    private func saveKey(_ key: String, provider: AIProvider) {
        if key.hasPrefix(provider.keyPrefix) {
            let saved = provider.saveAPIKey(key)
            saveMessage = saved ? "저장 완료" : "저장 실패"
            appState.updateAPIKeyStatus()
            if saved { onSaved?() }
        } else {
            saveMessage = "유효한 \(provider.rawValue) API 키를 입력하세요"
        }
    }
}
