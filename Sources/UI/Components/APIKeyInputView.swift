import SwiftUI

/// Reusable API key input component used in Onboarding and Settings
struct APIKeyInputView: View {
    @EnvironmentObject var appState: AppState
    @State private var claudeKeyInput: String = ""
    @State private var geminiKeyInput: String = ""
    @State private var showingClaudeKey: Bool = false
    @State private var showingGeminiKey: Bool = false
    @State private var saveMessage: (provider: AIProvider, text: String)?

    /// Whether to show the delete button when a key exists
    var showDeleteButton: Bool = true
    /// Called after a successful save
    var onSaved: (() -> Void)?

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            providerSection(
                provider: .claude,
                keyInput: $claudeKeyInput,
                showingKey: $showingClaudeKey,
                hasKey: appState.hasClaudeKey
            )

            Divider()

            providerSection(
                provider: .gemini,
                keyInput: $geminiKeyInput,
                showingKey: $showingGeminiKey,
                hasKey: appState.hasGeminiKey
            )
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

    // MARK: - Provider Section

    @ViewBuilder
    private func providerSection(
        provider: AIProvider,
        keyInput: Binding<String>,
        showingKey: Binding<Bool>,
        hasKey: Bool
    ) -> some View {
        let isActive = appState.selectedProvider == provider

        VStack(alignment: .leading, spacing: 8) {
            // Header: provider name + status
            HStack {
                Text(provider.displayName)
                    .font(.subheadline)
                    .fontWeight(.medium)

                Spacer()

                if isActive {
                    Text("사용 중")
                        .font(.caption2)
                        .fontWeight(.semibold)
                        .foregroundColor(.white)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 2)
                        .background(Capsule().fill(Color.green))
                } else if hasKey {
                    Button("활성화") {
                        withAnimation(.easeOut(duration: 0.15)) {
                            appState.selectedProvider = provider
                        }
                    }
                    .font(.caption2)
                    .buttonStyle(.bordered)
                    .controlSize(.mini)
                }
            }

            // API Key input
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
                        saveMessage = (provider: provider, text: "삭제됨")
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.mini)
                }

                if let msg = saveMessage, msg.provider == provider {
                    Text(msg.text)
                        .font(.caption2)
                        .foregroundColor(msg.text == "저장 완료" ? .green : .orange)
                }
            }
        }
    }

    private func saveKey(_ key: String, provider: AIProvider) {
        if key.hasPrefix(provider.keyPrefix) {
            let saved = provider.saveAPIKey(key)
            saveMessage = (provider: provider, text: saved ? "저장 완료" : "저장 실패")
            appState.updateAPIKeyStatus()
            if saved { onSaved?() }
        } else {
            saveMessage = (provider: provider, text: "유효한 \(provider.rawValue) API 키를 입력하세요")
        }
    }
}
