import SwiftUI

struct SettingsView: View {
    @EnvironmentObject var appState: AppState
    @State private var apiKeyInput: String = ""
    @State private var showingAPIKey: Bool = false
    @State private var saveMessage: String = ""
    @State private var showFolderPicker: Bool = false

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            // Header
            HStack {
                Button(action: { appState.currentScreen = .inbox }) {
                    Image(systemName: "chevron.left")
                }
                .buttonStyle(.plain)

                Text("설정")
                    .font(.headline)

                Spacer()
            }

            Divider()

            // API Key Section
            VStack(alignment: .leading, spacing: 8) {
                Text("Claude API Key")
                    .font(.subheadline)
                    .fontWeight(.medium)

                HStack {
                    if showingAPIKey {
                        TextField("sk-ant-...", text: $apiKeyInput)
                            .textFieldStyle(.roundedBorder)
                            .font(.system(.body, design: .monospaced))
                    } else {
                        SecureField("sk-ant-...", text: $apiKeyInput)
                            .textFieldStyle(.roundedBorder)
                    }

                    Button(action: { showingAPIKey.toggle() }) {
                        Image(systemName: showingAPIKey ? "eye.slash" : "eye")
                    }
                    .buttonStyle(.plain)
                }

                HStack {
                    Button("저장") {
                        if apiKeyInput.hasPrefix("sk-ant-") {
                            let saved = KeychainService.saveAPIKey(apiKeyInput)
                            saveMessage = saved ? "저장 완료" : "저장 실패"
                            appState.hasAPIKey = saved
                        } else {
                            saveMessage = "유효한 API 키를 입력하세요"
                        }
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.small)

                    if appState.hasAPIKey {
                        Button("삭제") {
                            KeychainService.deleteAPIKey()
                            apiKeyInput = ""
                            appState.hasAPIKey = false
                            saveMessage = "삭제됨"
                        }
                        .buttonStyle(.bordered)
                        .controlSize(.small)
                    }

                    if !saveMessage.isEmpty {
                        Text(saveMessage)
                            .font(.caption)
                            .foregroundColor(saveMessage == "저장 완료" ? .green : .orange)
                    }
                }

                if appState.hasAPIKey {
                    Label("API 키 저장됨 (Keychain)", systemImage: "checkmark.circle.fill")
                        .font(.caption)
                        .foregroundColor(.green)
                }
            }

            Divider()

            // PKM Root Path
            VStack(alignment: .leading, spacing: 8) {
                Text("PKM 폴더 경로")
                    .font(.subheadline)
                    .fontWeight(.medium)

                HStack {
                    Text(appState.pkmRootPath)
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .lineLimit(1)
                        .truncationMode(.middle)

                    Spacer()

                    Button("변경") {
                        showFolderPicker = true
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                }

                let pathManager = PKMPathManager(root: appState.pkmRootPath)
                if pathManager.isInitialized() {
                    Label("PARA 구조 확인됨", systemImage: "checkmark.circle.fill")
                        .font(.caption)
                        .foregroundColor(.green)
                } else {
                    Label("PARA 폴더 구조 없음", systemImage: "exclamationmark.triangle.fill")
                        .font(.caption)
                        .foregroundColor(.orange)
                }
            }

            Divider()

            // Info
            VStack(alignment: .leading, spacing: 4) {
                Text("비용 안내")
                    .font(.subheadline)
                    .fontWeight(.medium)
                Text("파일당 약 $0.002 (Haiku 4.5)")
                    .font(.caption)
                    .foregroundColor(.secondary)
                Text("불확실한 파일은 Sonnet 4.5로 재분류 (약 $0.01)")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }

            Spacer()

            Divider()

            Button(action: { NSApp.terminate(nil) }) {
                HStack {
                    Image(systemName: "power")
                    Text("앱 종료")
                }
                .frame(maxWidth: .infinity)
            }
            .buttonStyle(.bordered)
            .controlSize(.small)
        }
        .padding()
        .fileImporter(isPresented: $showFolderPicker, allowedContentTypes: [.folder]) { result in
            if case .success(let url) = result {
                appState.pkmRootPath = url.path
            }
        }
        .onAppear {
            if appState.hasAPIKey {
                apiKeyInput = "••••••••"
            }
        }
    }
}
