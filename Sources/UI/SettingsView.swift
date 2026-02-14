import SwiftUI

struct SettingsView: View {
    @EnvironmentObject var appState: AppState
    @State private var showFolderPicker: Bool = false
    @State private var isStructureReady = false

    var body: some View {
        VStack(spacing: 0) {
            // Header (fixed)
            HStack {
                Button(action: { appState.currentScreen = .inbox }) {
                    Image(systemName: "chevron.left")
                }
                .buttonStyle(.plain)

                Text("설정")
                    .font(.headline)

                Spacer()
            }
            .padding()

            Divider()

            // Scrollable content
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    // Provider Switcher
                    VStack(alignment: .leading, spacing: 8) {
                        Text("AI 제공자")
                            .font(.subheadline)
                            .fontWeight(.medium)

                        Picker("", selection: Binding(
                            get: { appState.selectedProvider },
                            set: { appState.selectedProvider = $0 }
                        )) {
                            ForEach(AIProvider.allCases) { provider in
                                Text(provider.displayName).tag(provider)
                            }
                        }
                        .pickerStyle(.segmented)

                        Text(appState.selectedProvider.modelPipeline)
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }

                    Divider()

                    // API Key Section
                    APIKeyInputView()

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

                        if isStructureReady {
                            Label("PARA 구조 확인됨", systemImage: "checkmark.circle.fill")
                                .font(.caption)
                                .foregroundColor(.green)
                        } else {
                            VStack(alignment: .leading, spacing: 6) {
                                Label("PARA 폴더 구조 없음", systemImage: "exclamationmark.triangle.fill")
                                    .font(.caption)
                                    .foregroundColor(.orange)

                                Button(action: {
                                    let pathManager = PKMPathManager(root: appState.pkmRootPath)
                                    try? pathManager.initializeStructure()
                                    isStructureReady = pathManager.isInitialized()
                                }) {
                                    HStack {
                                        Image(systemName: "folder.badge.plus")
                                        Text("폴더 구조 만들기")
                                    }
                                    .frame(maxWidth: .infinity)
                                }
                                .buttonStyle(.bordered)
                                .controlSize(.small)
                            }
                        }
                    }

                    Divider()

                    // Info
                    VStack(alignment: .leading, spacing: 4) {
                        Text("비용 안내")
                            .font(.subheadline)
                            .fontWeight(.medium)
                        Text(appState.selectedProvider.costInfo)
                            .font(.caption)
                            .foregroundColor(.secondary)
                        if appState.selectedProvider == .claude {
                            Text("불확실한 파일은 Sonnet 4.5로 재분류 (약 $0.01)")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        } else {
                            Text("불확실한 파일은 Gemini Pro로 재분류")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                    }
                }
                .padding()
            }

            Divider()

            // Footer (fixed)
            Button(action: { NSApp.terminate(nil) }) {
                HStack {
                    Image(systemName: "power")
                    Text("앱 종료")
                }
                .frame(maxWidth: .infinity)
            }
            .buttonStyle(.bordered)
            .controlSize(.small)
            .padding()
        }
        .onAppear {
            isStructureReady = PKMPathManager(root: appState.pkmRootPath).isInitialized()
        }
        .onChange(of: appState.pkmRootPath) { _ in
            isStructureReady = PKMPathManager(root: appState.pkmRootPath).isInitialized()
        }
        .fileImporter(isPresented: $showFolderPicker, allowedContentTypes: [.folder]) { result in
            if case .success(let url) = result {
                appState.pkmRootPath = url.path
            }
        }
    }
}
