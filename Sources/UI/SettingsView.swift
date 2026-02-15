import SwiftUI

struct SettingsView: View {
    @EnvironmentObject var appState: AppState
    @State private var showFolderPicker: Bool = false
    @State private var isStructureReady = false

    var body: some View {
        VStack(spacing: 0) {
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
            .padding()

            Divider()

            // Scrollable content
            ScrollView {
                VStack(spacing: 14) {
                    // MARK: - AI Provider Section
                    SettingsSection(icon: "cpu", title: "AI 제공자") {
                        VStack(spacing: 8) {
                            ProviderSelectCard(
                                provider: .gemini,
                                isSelected: appState.selectedProvider == .gemini,
                                badge: "무료",
                                badgeColor: .green
                            ) {
                                withAnimation(.easeOut(duration: 0.15)) {
                                    appState.selectedProvider = .gemini
                                }
                            }

                            ProviderSelectCard(
                                provider: .claude,
                                isSelected: appState.selectedProvider == .claude,
                                badge: "유료",
                                badgeColor: .orange
                            ) {
                                withAnimation(.easeOut(duration: 0.15)) {
                                    appState.selectedProvider = .claude
                                }
                            }
                        }
                    }

                    // MARK: - API Key Section
                    SettingsSection(icon: "key", title: "API 키") {
                        APIKeyInputView()
                    }

                    // MARK: - PKM Folder Section
                    SettingsSection(icon: "folder", title: "PKM 폴더") {
                        VStack(alignment: .leading, spacing: 8) {
                            HStack(spacing: 8) {
                                Image(systemName: "externaldrive")
                                    .font(.caption)
                                    .foregroundColor(.secondary)

                                Text(appState.pkmRootPath)
                                    .font(.system(.caption, design: .monospaced))
                                    .foregroundColor(.secondary)
                                    .lineLimit(1)
                                    .truncationMode(.middle)

                                Spacer()

                                Button("변경") {
                                    showFolderPicker = true
                                }
                                .buttonStyle(.bordered)
                                .controlSize(.mini)
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
                                        HStack(spacing: 4) {
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
                    }

                    // MARK: - Cost Info Section
                    SettingsSection(icon: "dollarsign.circle", title: "비용 안내") {
                        VStack(alignment: .leading, spacing: 4) {
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

                    // MARK: - App Info
                    SettingsSection(icon: "info.circle", title: "앱 정보") {
                        VStack(alignment: .leading, spacing: 6) {
                            HStack {
                                Text("DotBrain")
                                    .font(.caption)
                                    .fontWeight(.medium)
                                Spacer()
                                Text("v\(Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "1.5")")
                                    .font(.system(.caption, design: .monospaced))
                                    .foregroundColor(.secondary)
                            }

                            Button(action: {
                                if let url = URL(string: "https://github.com/DinN0000/DotBrain") {
                                    NSWorkspace.shared.open(url)
                                }
                            }) {
                                HStack(spacing: 4) {
                                    Image(systemName: "arrow.up.right.square")
                                        .font(.caption2)
                                    Text("GitHub")
                                        .font(.caption)
                                }
                            }
                            .buttonStyle(.plain)
                            .foregroundColor(.accentColor)
                        }
                    }
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 10)
            }
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

// MARK: - Settings Section Card

struct SettingsSection<Content: View>: View {
    let icon: String
    let title: String
    @ViewBuilder let content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 6) {
                Image(systemName: icon)
                    .font(.caption)
                    .foregroundColor(.accentColor)
                    .frame(width: 16)

                Text(title)
                    .font(.subheadline)
                    .fontWeight(.medium)
            }

            content
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.primary.opacity(0.03))
        .cornerRadius(8)
    }
}

// MARK: - Provider Selection Card

struct ProviderSelectCard: View {
    let provider: AIProvider
    let isSelected: Bool
    let badge: String
    let badgeColor: Color
    let action: () -> Void

    private var accent: Color {
        switch provider {
        case .claude: return Color(red: 0.85, green: 0.45, blue: 0.25)
        case .gemini: return Color(red: 0.25, green: 0.52, blue: 0.96)
        }
    }

    var body: some View {
        Button(action: action) {
            HStack(spacing: 10) {
                // Radio indicator
                ZStack {
                    Circle()
                        .strokeBorder(isSelected ? accent : Color.secondary.opacity(0.4), lineWidth: 1.5)
                        .frame(width: 16, height: 16)
                    if isSelected {
                        Circle()
                            .fill(accent)
                            .frame(width: 8, height: 8)
                    }
                }

                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 6) {
                        Text(provider.displayName)
                            .font(.caption)
                            .fontWeight(isSelected ? .bold : .medium)
                            .foregroundColor(isSelected ? .primary : .secondary)

                        Text(badge)
                            .font(.system(size: 9, weight: .semibold))
                            .foregroundColor(badgeColor)
                            .padding(.horizontal, 5)
                            .padding(.vertical, 1)
                            .background(badgeColor.opacity(0.12))
                            .cornerRadius(3)
                    }

                    Text(provider.modelPipeline)
                        .font(.caption2)
                        .foregroundColor(isSelected ? accent : .secondary.opacity(0.6))
                }

                Spacer()
            }
            .padding(8)
            .background(
                RoundedRectangle(cornerRadius: 6)
                    .fill(isSelected ? accent.opacity(0.06) : Color.clear)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 6)
                    .strokeBorder(isSelected ? accent.opacity(0.3) : Color.secondary.opacity(0.1), lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
    }
}
