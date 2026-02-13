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
        VStack(alignment: .leading, spacing: 10) {
            providerSection(
                provider: .claude,
                keyInput: $claudeKeyInput,
                showingKey: $showingClaudeKey,
                hasKey: appState.hasClaudeKey
            )

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

    private func providerAccentColor(_ provider: AIProvider) -> Color {
        switch provider {
        case .claude: return Color(red: 0.85, green: 0.45, blue: 0.25) // Anthropic orange-brown
        case .gemini: return Color(red: 0.25, green: 0.52, blue: 0.96) // Google blue
        }
    }

    @ViewBuilder
    private func providerSection(
        provider: AIProvider,
        keyInput: Binding<String>,
        showingKey: Binding<Bool>,
        hasKey: Bool
    ) -> some View {
        let isActive = appState.selectedProvider == provider
        let accent = providerAccentColor(provider)

        VStack(alignment: .leading, spacing: 8) {
            // Header: provider name + active indicator + model pipeline
            HStack(spacing: 6) {
                // Active dot indicator
                Circle()
                    .fill(isActive ? accent : Color.secondary.opacity(0.3))
                    .frame(width: 8, height: 8)

                Text(provider.displayName)
                    .font(.subheadline)
                    .fontWeight(isActive ? .bold : .medium)
                    .foregroundColor(isActive ? .primary : .secondary)

                Spacer()

                if isActive {
                    Text("사용 중")
                        .font(.caption2)
                        .fontWeight(.semibold)
                        .foregroundColor(.white)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 2)
                        .background(Capsule().fill(accent))
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

            // Model pipeline info (only for active provider)
            if isActive {
                Text(provider.modelPipeline)
                    .font(.caption2)
                    .foregroundColor(accent)
                    .padding(.leading, 14)
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

                Button(action: {
                    showingKey.wrappedValue.toggle()
                    if showingKey.wrappedValue, keyInput.wrappedValue == "••••••••", hasKey {
                        if let key = provider == .claude ? KeychainService.getAPIKey() : KeychainService.getGeminiAPIKey() {
                            keyInput.wrappedValue = key
                        }
                    } else if !showingKey.wrappedValue, hasKey, keyInput.wrappedValue.hasPrefix(provider.keyPrefix) {
                        keyInput.wrappedValue = "••••••••"
                    }
                }) {
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
        .padding(10)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(isActive ? accent.opacity(0.06) : Color.clear)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .strokeBorder(isActive ? accent.opacity(0.3) : Color.clear, lineWidth: 1.5)
        )
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
