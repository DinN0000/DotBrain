import SwiftUI

struct SettingsView: View {
    @EnvironmentObject var appState: AppState
    @State private var showFolderPicker = false
    @State private var isStructureReady = false
    @State private var showHelp = false

    // API key state
    @State private var keyInput = ""
    @State private var showingKey = false
    @State private var saveMessage: String?
    @State private var showOtherProvider = false

    // Update check state
    @State private var isCheckingUpdate = false
    @State private var latestVersion: String?
    @State private var updateError: String?
    @State private var updateIconRotation: Double = 0
    @State private var updateCheckHovered = false
    @State private var isUpdateAnimating = false

    private var activeProvider: AIProvider { appState.selectedProvider }
    private var otherProvider: AIProvider { activeProvider == .claude ? .gemini : .claude }

    private var activeHasKey: Bool {
        activeProvider == .claude ? appState.hasClaudeKey : appState.hasGeminiKey
    }

    private var otherHasKey: Bool {
        otherProvider == .claude ? appState.hasClaudeKey : appState.hasGeminiKey
    }

    var body: some View {
        VStack(spacing: 0) {
            BreadcrumbView(current: .settings)

            Divider()

            ScrollView {
                VStack(spacing: 14) {
                    // MARK: - AI Settings (unified)
                    aiSettingsSection

                    // MARK: - PKM Folder
                    pkmFolderSection

                    // MARK: - App Info
                    appInfoSection
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 10)
            }

            Divider()

            // MARK: - Footer (quit + help)
            footerBar
        }
        .onAppear {
            isStructureReady = PKMPathManager(root: appState.pkmRootPath).isInitialized()
            loadKeyForProvider(activeProvider)
        }
        .onChange(of: appState.selectedProvider) { _ in
            loadKeyForProvider(activeProvider)
            saveMessage = nil
            showingKey = false
        }
        .onChange(of: appState.pkmRootPath) { _ in
            isStructureReady = PKMPathManager(root: appState.pkmRootPath).isInitialized()
        }
        .fileImporter(isPresented: $showFolderPicker, allowedContentTypes: [.folder]) { result in
            if case .success(let url) = result {
                let newPath = url.path
                appState.pkmRootPath = newPath

                // If folder lacks PARA structure, trigger re-onboarding (skip welcome)
                let pm = PKMPathManager(root: newPath)
                if !pm.isInitialized() {
                    UserDefaults.standard.set(1, forKey: "onboardingStep")
                    appState.currentScreen = .onboarding
                }
            }
        }
    }

    // MARK: - AI Settings Section

    private var aiSettingsSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            // Section header
            HStack(spacing: 6) {
                Image(systemName: "cpu")
                    .font(.caption)
                    .foregroundColor(.accentColor)
                    .frame(width: 16)
                Text("AI 설정")
                    .font(.subheadline)
                    .fontWeight(.medium)
            }

            // Provider picker — segmented style
            HStack(spacing: 0) {
                ForEach(AIProvider.allCases) { provider in
                    providerTab(provider)
                }
            }
            .background(Color.primary.opacity(0.04))
            .cornerRadius(6)

            // Active provider key input
            providerKeySection(activeProvider, hasKey: activeHasKey)

            // Cost info inline
            Text(activeProvider.costInfo)
                .font(.caption2)
                .foregroundColor(.secondary)
                .padding(.leading, 2)

            // Other provider (collapsed)
            if otherHasKey || showOtherProvider {
                Divider()
                    .padding(.vertical, 2)

                HStack(spacing: 6) {
                    Circle()
                        .fill(Color.secondary.opacity(0.3))
                        .frame(width: 6, height: 6)
                    Text(otherProvider.displayName)
                        .font(.caption)
                        .foregroundColor(.secondary)
                    Spacer()
                    if otherHasKey {
                        Text("키 등록됨")
                            .font(.caption2)
                            .foregroundColor(.green)
                        Button("전환") {
                            withAnimation(.easeOut(duration: 0.15)) {
                                appState.selectedProvider = otherProvider
                            }
                        }
                        .font(.caption2)
                        .buttonStyle(.bordered)
                        .controlSize(.mini)
                    }
                }
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.primary.opacity(0.03))
        .cornerRadius(8)
    }

    private func providerTab(_ provider: AIProvider) -> some View {
        let isActive = appState.selectedProvider == provider
        let accent = providerAccentColor(provider)

        return Button {
            withAnimation(.easeOut(duration: 0.15)) {
                appState.selectedProvider = provider
            }
        } label: {
            HStack(spacing: 5) {
                Text(provider.rawValue)
                    .font(.caption)
                    .fontWeight(isActive ? .bold : .medium)

                if provider == .gemini {
                    Text("무료")
                        .font(.system(size: 8, weight: .semibold))
                        .foregroundColor(.secondary)
                        .padding(.horizontal, 4)
                        .padding(.vertical, 1)
                        .background(Color.secondary.opacity(0.12))
                        .cornerRadius(2)
                }
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 6)
            .background(
                RoundedRectangle(cornerRadius: 5)
                    .fill(isActive ? accent.opacity(0.12) : Color.clear)
            )
            .foregroundColor(isActive ? accent : .secondary)
        }
        .buttonStyle(.plain)
    }

    @ViewBuilder
    private func providerKeySection(_ provider: AIProvider, hasKey: Bool) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            // Model pipeline
            Text(provider.modelPipeline)
                .font(.caption2)
                .foregroundColor(providerAccentColor(provider).opacity(0.8))

            // Key input row
            HStack(spacing: 6) {
                if showingKey {
                    TextField(provider.keyPlaceholder, text: $keyInput)
                        .textFieldStyle(.roundedBorder)
                        .font(.system(.caption, design: .monospaced))
                } else {
                    SecureField(provider.keyPlaceholder, text: $keyInput)
                        .textFieldStyle(.roundedBorder)
                        .font(.caption)
                }

                Button(action: toggleKeyVisibility) {
                    Image(systemName: showingKey ? "eye.slash" : "eye")
                        .font(.caption)
                }
                .buttonStyle(.plain)
                .foregroundColor(.secondary)
            }

            // Action row
            HStack(spacing: 6) {
                Button("저장") { saveKey() }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.mini)
                    .disabled(keyInput.isEmpty || keyInput == "••••••••")

                if hasKey {
                    Button("삭제") { deleteKey() }
                        .buttonStyle(.bordered)
                        .controlSize(.mini)
                }

                if let msg = saveMessage {
                    Text(msg)
                        .font(.caption2)
                        .foregroundColor(msg == "저장 완료" ? .green : .orange)
                        .transition(.opacity)
                }

                Spacer()

                if hasKey {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.caption)
                        .foregroundColor(.green)
                }
            }
        }
    }

    // MARK: - PKM Folder Section

    private var pkmFolderSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 6) {
                Image(systemName: "folder")
                    .font(.caption)
                    .foregroundColor(.accentColor)
                    .frame(width: 16)
                Text("PKM 폴더")
                    .font(.subheadline)
                    .fontWeight(.medium)
                Spacer()
                if isStructureReady {
                    Label("PARA 확인됨", systemImage: "checkmark.circle.fill")
                        .font(.caption2)
                        .foregroundColor(.green)
                } else {
                    Label("PARA 없음", systemImage: "exclamationmark.triangle.fill")
                        .font(.caption2)
                        .foregroundColor(.orange)
                }
            }

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

                Button("변경") { showFolderPicker = true }
                    .buttonStyle(.bordered)
                    .controlSize(.mini)
            }

            if !isStructureReady {
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
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.primary.opacity(0.03))
        .cornerRadius(8)
    }

    // MARK: - App Info Section

    private var currentVersion: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "알 수 없음"
    }

    private var appInfoSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 6) {
                Image(systemName: "info.circle")
                    .font(.caption)
                    .foregroundColor(.accentColor)
                    .frame(width: 16)
                Text("앱 정보")
                    .font(.subheadline)
                    .fontWeight(.medium)
                Spacer()
                Text("v\(currentVersion)")
                    .font(.system(.caption2, design: .monospaced))
                    .foregroundColor(.secondary)
                if let latest = latestVersion {
                    if latest != currentVersion {
                        Button(action: { runUpdate() }) {
                            Label("v\(latest) 업데이트", systemImage: "arrow.down.circle.fill")
                                .font(.caption2)
                        }
                        .buttonStyle(.borderedProminent)
                        .controlSize(.mini)
                    } else {
                        Label("최신", systemImage: "checkmark.circle.fill")
                            .font(.caption2)
                            .foregroundColor(.green)
                    }
                }
            }

            if let error = updateError {
                Text(error)
                    .font(.caption2)
                    .foregroundColor(.red)
            }

            HStack(spacing: 12) {
                Text("DotBrain v\(currentVersion)")
                    .font(.system(.caption, design: .monospaced))
                    .foregroundColor(.secondary)

                Spacer()

                Button(action: checkForUpdate) {
                    HStack(spacing: 4) {
                        Image(systemName: "arrow.triangle.2.circlepath")
                            .font(.caption2)
                            .rotationEffect(.degrees(updateIconRotation))
                        Text(isCheckingUpdate ? "확인 중..." : "업데이트 확인")
                            .font(.caption)
                    }
                    .padding(.horizontal, 8)
                    .padding(.vertical, 3)
                    .background(
                        RoundedRectangle(cornerRadius: 4)
                            .fill(updateCheckHovered ? Color.accentColor.opacity(0.1) : Color.clear)
                    )
                }
                .buttonStyle(.plain)
                .foregroundColor(.accentColor)
                .disabled(isCheckingUpdate)
                .onHover { updateCheckHovered = $0 }
                .animation(.easeInOut(duration: 0.15), value: updateCheckHovered)
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.primary.opacity(0.03))
        .cornerRadius(8)
        .onAppear { checkForUpdate() }
    }

    private func checkForUpdate() {
        guard !isCheckingUpdate else { return }
        isCheckingUpdate = true
        updateError = nil
        latestVersion = nil
        isUpdateAnimating = true

        withAnimation(.linear(duration: 0.6).repeatForever(autoreverses: false)) {
            if isUpdateAnimating { updateIconRotation = 360 }
        }

        Task {
            do {
                let url = URL(string: "https://api.github.com/repos/DinN0000/DotBrain/releases/latest")!
                let (data, _) = try await URLSession.shared.data(from: url)
                if let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
                   let tag = json["tag_name"] as? String {
                    let version = tag.hasPrefix("v") ? String(tag.dropFirst()) : tag
                    await MainActor.run {
                        isUpdateAnimating = false
                        withAnimation { updateIconRotation = 0 }
                        latestVersion = version
                        isCheckingUpdate = false
                    }
                } else {
                    await MainActor.run {
                        isUpdateAnimating = false
                        withAnimation { updateIconRotation = 0 }
                        updateError = "릴리즈 정보를 읽을 수 없습니다"
                        isCheckingUpdate = false
                    }
                }
            } catch {
                await MainActor.run {
                    isUpdateAnimating = false
                    withAnimation { updateIconRotation = 0 }
                    updateError = "확인 실패: \(error.localizedDescription)"
                    isCheckingUpdate = false
                }
            }
        }
    }

    private func runUpdate() {
        // Write update script to temp file and run detached
        let appPath = NSHomeDirectory() + "/Applications/DotBrain.app"
        let updateScript = """
        #!/bin/bash
        sleep 2
        curl -sL https://raw.githubusercontent.com/DinN0000/DotBrain/main/install.sh -o /tmp/dotbrain_install.sh
        bash /tmp/dotbrain_install.sh || true
        open "\(appPath)" 2>/dev/null || true
        rm -f /tmp/dotbrain_install.sh /tmp/dotbrain_update.sh
        """
        let scriptPath = "/tmp/dotbrain_update.sh"
        do {
            try updateScript.write(toFile: scriptPath, atomically: true, encoding: .utf8)
            let process = Process()
            process.executableURL = URL(fileURLWithPath: "/bin/bash")
            process.arguments = ["-c", "nohup bash \(scriptPath) > /tmp/dotbrain_update.log 2>&1 &"]
            try process.run()
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                NSApplication.shared.terminate(nil)
            }
        } catch {
            updateError = "업데이트 실패: \(error.localizedDescription)"
        }
    }

    // MARK: - Footer Bar

    private var footerBar: some View {
        HStack(spacing: 12) {
            Button(action: { showHelp = true }) {
                HStack(spacing: 3) {
                    Image(systemName: "questionmark.circle")
                        .font(.caption2)
                    Text("도움말")
                        .font(.caption2)
                }
            }
            .buttonStyle(.plain)
            .foregroundColor(.secondary)
            .popover(isPresented: $showHelp) {
                helpPopover
            }

            Button(action: {
                openExternal("https://github.com/DinN0000/DotBrain")
            }) {
                HStack(spacing: 3) {
                    Image(systemName: "arrow.up.right.square")
                        .font(.caption2)
                    Text("GitHub")
                        .font(.caption2)
                }
            }
            .buttonStyle(.plain)
            .foregroundColor(.secondary)

            Spacer()

            Button(action: {
                NSApplication.shared.terminate(nil)
            }) {
                HStack(spacing: 3) {
                    Image(systemName: "power")
                        .font(.caption2)
                    Text("종료")
                        .font(.caption2)
                }
            }
            .buttonStyle(.plain)
            .foregroundColor(.red.opacity(0.8))
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
    }

    // MARK: - External Links

    private func openExternal(_ urlString: String) {
        guard let url = URL(string: urlString) else { return }
        // Delay so the popover doesn't swallow the URL open
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
            NSWorkspace.shared.open(url)
        }
    }

    // MARK: - Help Popover

    private var helpPopover: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("DotBrain 사용법")
                .font(.subheadline)
                .fontWeight(.semibold)

            VStack(alignment: .leading, spacing: 6) {
                helpRow("1", "인박스에 파일을 드래그하거나 + 버튼으로 추가")
                helpRow("2", "\"정리하기\" 버튼을 누르면 AI가 PARA로 분류")
                helpRow("3", "폴더 관리에서 프로젝트 생성/이름 변경/병합")
                helpRow("4", "검색으로 태그, 키워드, 제목 기반 노트 찾기")
            }

            Divider()

            VStack(alignment: .leading, spacing: 4) {
                Text("PARA 구조")
                    .font(.caption)
                    .fontWeight(.medium)
                Text("Project — 진행 중인 일 (마감 있음)")
                    .font(.caption2).foregroundColor(.secondary)
                Text("Area — 늘 관리하는 영역 (건강, 재무)")
                    .font(.caption2).foregroundColor(.secondary)
                Text("Resource — 참고 자료")
                    .font(.caption2).foregroundColor(.secondary)
                Text("Archive — 완료된 것")
                    .font(.caption2).foregroundColor(.secondary)
            }

            Divider()

            Button(action: {
                showHelp = false
                openExternal("https://github.com/DinN0000/DotBrain/issues")
            }) {
                HStack(spacing: 4) {
                    Image(systemName: "arrow.up.right.square")
                        .font(.caption2)
                    Text("버그 신고 / 기능 요청")
                        .font(.caption)
                }
            }
            .buttonStyle(.plain)
            .foregroundColor(.accentColor)
        }
        .padding(14)
        .frame(width: 260)
    }

    private func helpRow(_ num: String, _ text: String) -> some View {
        HStack(alignment: .top, spacing: 6) {
            Text(num)
                .font(.system(.caption2, design: .monospaced))
                .fontWeight(.bold)
                .foregroundColor(.accentColor)
                .frame(width: 12)
            Text(text)
                .font(.caption)
                .foregroundColor(.secondary)
        }
    }

    // MARK: - Key Actions

    private func loadKeyForProvider(_ provider: AIProvider) {
        let hasKey = provider == .claude ? appState.hasClaudeKey : appState.hasGeminiKey
        keyInput = hasKey ? "••••••••" : ""
    }

    private func toggleKeyVisibility() {
        showingKey.toggle()
        if showingKey, keyInput == "••••••••", activeHasKey {
            if let key = activeProvider == .claude ? KeychainService.getAPIKey() : KeychainService.getGeminiAPIKey() {
                keyInput = key
            }
        } else if !showingKey, activeHasKey, keyInput.hasPrefix(activeProvider.keyPrefix) {
            keyInput = "••••••••"
        }
    }

    private func saveKey() {
        if keyInput.hasPrefix(activeProvider.keyPrefix) {
            let saved = activeProvider.saveAPIKey(keyInput)
            saveMessage = saved ? "저장 완료" : "저장 실패"
            appState.updateAPIKeyStatus()
            clearMessageAfterDelay()
        } else {
            saveMessage = "\(activeProvider.keyPrefix)... 형식 필요"
            clearMessageAfterDelay()
        }
    }

    private func deleteKey() {
        activeProvider.deleteAPIKey()
        keyInput = ""
        appState.updateAPIKeyStatus()
        saveMessage = "삭제됨"
        clearMessageAfterDelay()
    }

    private func clearMessageAfterDelay() {
        Task {
            try? await Task.sleep(nanoseconds: 3_000_000_000)
            await MainActor.run { saveMessage = nil }
        }
    }

    private func providerAccentColor(_ provider: AIProvider) -> Color {
        .accentColor
    }
}

// MARK: - Settings Section Card (kept for potential reuse)

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

// MARK: - Provider Selection Card (kept for potential reuse)

struct ProviderSelectCard: View {
    let provider: AIProvider
    let isSelected: Bool
    let badge: String
    let badgeColor: Color
    let action: () -> Void

    private var accent: Color { .accentColor }

    var body: some View {
        Button(action: action) {
            HStack(spacing: 10) {
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
