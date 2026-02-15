import SwiftUI

struct OnboardingView: View {
    @EnvironmentObject var appState: AppState
    @State private var step: Int
    @State private var showFolderPicker = false
    @State private var newProjectName: String = ""
    @State private var projects: [String] = []
    @State private var isStructureReady = false
    @State private var keyInput: String = ""
    @State private var showingKey: Bool = false
    @State private var keySaveMessage: String?
    @State private var direction: Int = 1
    @State private var folderError: String?
    @State private var showFolderError = false

    private let totalSteps = 4

    init() {
        let saved = UserDefaults.standard.integer(forKey: "onboardingStep")
        _step = State(initialValue: saved)
    }

    var body: some View {
        VStack(spacing: 0) {
            stepIndicator
                .padding(.top, 16)
                .padding(.bottom, 8)

            Group {
                switch step {
                case 0: welcomeStep
                case 1: folderStep
                case 2: projectStep
                case 3: providerAndKeyStep
                default: providerAndKeyStep
                }
            }
            .transition(direction > 0
                ? .asymmetric(insertion: .move(edge: .trailing), removal: .move(edge: .leading))
                : .asymmetric(insertion: .move(edge: .leading), removal: .move(edge: .trailing))
            )
            .id(step)
        }
        .frame(width: 360, height: 480)
        .animation(.easeInOut(duration: 0.25), value: step)
        .onChange(of: appState.pkmRootPath) { _ in
            isStructureReady = PKMPathManager(root: appState.pkmRootPath).isInitialized()
            projects = []
        }
        .fileImporter(isPresented: $showFolderPicker, allowedContentTypes: [.folder]) { result in
            if case .success(let url) = result {
                appState.pkmRootPath = url.path
            }
        }
        .alert("폴더 생성 실패", isPresented: $showFolderError) {
            Button("확인") {}
        } message: {
            Text(folderError ?? "알 수 없는 오류가 발생했습니다.")
        }
    }

    // MARK: - Step Indicator

    private var stepIndicator: some View {
        HStack(spacing: 0) {
            ForEach(0..<totalSteps, id: \.self) { i in
                HStack(spacing: 0) {
                    ZStack {
                        Circle()
                            .fill(i < step ? Color.primary : (i == step ? Color.primary : Color.secondary.opacity(0.2)))
                            .frame(width: 20, height: 20)

                        if i < step {
                            Image(systemName: "checkmark")
                                .font(.system(size: 9, weight: .bold))
                                .foregroundColor(Color(nsColor: .windowBackgroundColor))
                        } else {
                            Text("\(i + 1)")
                                .font(.system(size: 10, weight: .medium, design: .monospaced))
                                .foregroundColor(i == step ? Color(nsColor: .windowBackgroundColor) : .secondary)
                        }
                    }

                    if i < totalSteps - 1 {
                        Rectangle()
                            .fill(i < step ? Color.primary : Color.secondary.opacity(0.2))
                            .frame(height: 1.5)
                    }
                }
            }
        }
        .padding(.horizontal, 48)
    }

    // MARK: - Navigation

    private func goNext() {
        direction = 1
        step += 1
        UserDefaults.standard.set(step, forKey: "onboardingStep")
    }

    private func goBack() {
        direction = -1
        step -= 1
        UserDefaults.standard.set(step, forKey: "onboardingStep")
    }

    // MARK: - Step 0: Welcome (Before/After)

    private var welcomeStep: some View {
        VStack(spacing: 0) {
            Spacer()

            Text("DotBrain에 오신 걸 환영합니다")
                .font(.title3)
                .fontWeight(.semibold)
                .padding(.bottom, 4)

            Text("파일을 던지면, AI가 알아서 정리합니다")
                .font(.subheadline)
                .foregroundColor(.secondary)
                .padding(.bottom, 16)

            // Before box
            VStack(alignment: .leading, spacing: 0) {
                Text("지금")
                    .font(.caption)
                    .fontWeight(.semibold)
                    .foregroundColor(.secondary)
                    .padding(.bottom, 6)

                VStack(alignment: .leading, spacing: 3) {
                    beforeFileRow("회의록_최종_진짜최종.pdf")
                    beforeFileRow("보고서(2).docx")
                    beforeFileRow("스크린샷 2026-01-15.png")
                    beforeFileRow("이름없는문서.txt")
                    beforeFileRow("메모.md")
                }
            }
            .padding(10)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color.secondary.opacity(0.08))
            .cornerRadius(8)
            .padding(.horizontal, 32)

            // Arrow
            Image(systemName: "arrow.down")
                .font(.system(size: 14, weight: .semibold))
                .foregroundColor(.secondary)
                .padding(.vertical, 8)

            // After box
            VStack(alignment: .leading, spacing: 0) {
                Text("DotBrain으로 정리하면")
                    .font(.caption)
                    .fontWeight(.semibold)
                    .foregroundColor(.green)
                    .padding(.bottom, 6)

                VStack(alignment: .leading, spacing: 3) {
                    afterFolderRow("Project/마케팅 캠페인/")
                    afterFileRow("회의록.pdf", indent: true)
                    afterFolderRow("Resource/")
                    afterFileRow("보고서.docx", indent: true)
                    afterFolderRow("Area/업무 관리/")
                    afterFileRow("메모.md", indent: true)
                }
            }
            .padding(10)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color.green.opacity(0.06))
            .cornerRadius(8)
            .overlay(
                RoundedRectangle(cornerRadius: 8)
                    .strokeBorder(Color.green.opacity(0.15), lineWidth: 1)
            )
            .padding(.horizontal, 32)

            Spacer()

            Button(action: { goNext() }) {
                Text("시작하기")
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 4)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            .tint(.primary.opacity(0.85))
            .padding(.horizontal, 40)
            .padding(.bottom, 20)
        }
        .padding(.horizontal)
    }

    private func beforeFileRow(_ name: String) -> some View {
        HStack(spacing: 5) {
            Text("📄")
                .font(.caption2)
            Text(name)
                .font(.system(.caption, design: .monospaced))
                .foregroundColor(.secondary)
        }
    }

    private func afterFolderRow(_ name: String) -> some View {
        HStack(spacing: 5) {
            Text("📁")
                .font(.caption2)
            Text(name)
                .font(.system(.caption, design: .monospaced))
                .fontWeight(.medium)
        }
    }

    private func afterFileRow(_ name: String, indent: Bool) -> some View {
        HStack(spacing: 5) {
            Text("📄")
                .font(.caption2)
            Text(name)
                .font(.system(.caption, design: .monospaced))
                .foregroundColor(.secondary)
        }
        .padding(.leading, indent ? 20 : 0)
    }

    // MARK: - Step 1: Folder Setup

    private var folderStep: some View {
        VStack(spacing: 0) {
            stepHeader(
                title: "내 공간 만들기",
                desc: "파일이 정리될 폴더를 선택하고, PARA 구조를 확인하세요."
            )

            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    // Folder path selection
                    VStack(alignment: .leading, spacing: 6) {
                        Text("저장 경로")
                            .font(.caption)
                            .fontWeight(.medium)

                        HStack {
                            Image(systemName: "folder")
                                .foregroundColor(.secondary)
                                .font(.caption)
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
                    }

                    Divider()

                    // PARA explanation
                    VStack(alignment: .leading, spacing: 6) {
                        Text("PARA 구조")
                            .font(.caption)
                            .fontWeight(.medium)

                        VStack(alignment: .leading, spacing: 8) {
                            paraExplanationRow(
                                folder: "Project",
                                metaphor: "책상 위",
                                desc: "진행 중인 일. 마감이 있는 것"
                            )
                            paraExplanationRow(
                                folder: "Area",
                                metaphor: "서랍",
                                desc: "늘 관리하는 것. 건강, 재무, 팀 운영"
                            )
                            paraExplanationRow(
                                folder: "Resource",
                                metaphor: "책장",
                                desc: "참고 자료. 가이드, 레퍼런스"
                            )
                            paraExplanationRow(
                                folder: "Archive",
                                metaphor: "창고",
                                desc: "끝난 것. 완료된 프로젝트"
                            )
                        }
                    }

                    Divider()

                    // Live folder preview
                    VStack(alignment: .leading, spacing: 6) {
                        if isStructureReady {
                            Label("PARA 구조 확인됨", systemImage: "checkmark.circle.fill")
                                .font(.caption)
                                .foregroundColor(.green)
                        } else {
                            Text("선택한 경로 아래에 이렇게 만들어집니다:")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }

                        VStack(alignment: .leading, spacing: 1) {
                            Text(abbreviatedPath(appState.pkmRootPath))
                                .font(.system(.caption2, design: .monospaced))
                                .fontWeight(.medium)
                                .foregroundColor(.primary)
                            folderTreeRow(prefix: "\u{251C}\u{2500}", name: "_Inbox/")
                            folderTreeRow(prefix: "\u{251C}\u{2500}", name: "1_Project/")
                            folderTreeRow(prefix: "\u{251C}\u{2500}", name: "2_Area/")
                            folderTreeRow(prefix: "\u{251C}\u{2500}", name: "3_Resource/")
                            folderTreeRow(prefix: "\u{2514}\u{2500}", name: "4_Archive/")
                        }
                        .padding(8)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(Color.secondary.opacity(0.03))
                        .cornerRadius(6)
                    }
                }
                .padding(14)
                .background(Color.secondary.opacity(0.05))
                .cornerRadius(8)
                .padding(.horizontal, 24)
            }

            HStack {
                Button("이전") { goBack() }
                    .buttonStyle(.bordered)
                    .controlSize(.regular)

                Spacer()

                Button(action: {
                    if !isStructureReady {
                        if !validateAndCreateFolder() { return }
                    }
                    loadExistingProjects()
                    goNext()
                }) {
                    Text("다음")
                        .frame(minWidth: 80)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.regular)
            }
            .padding(.horizontal, 32)
            .padding(.bottom, 20)
        }
        .padding(.horizontal)
        .onAppear {
            isStructureReady = PKMPathManager(root: appState.pkmRootPath).isInitialized()
        }
    }

    private func paraExplanationRow(folder: String, metaphor: String, desc: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack(spacing: 4) {
                Text("\u{1F4C1}")
                    .font(.caption2)
                Text(folder)
                    .font(.caption)
                    .fontWeight(.medium)
                Text("—")
                    .font(.caption)
                    .foregroundColor(.secondary)
                Text(metaphor)
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            Text(desc)
                .font(.caption2)
                .foregroundColor(.secondary)
                .padding(.leading, 18)
        }
    }

    private func folderTreeRow(prefix: String, name: String) -> some View {
        HStack(spacing: 2) {
            Text(prefix)
                .font(.system(.caption2, design: .monospaced))
                .foregroundColor(.secondary)
            Text(name)
                .font(.system(.caption2, design: .monospaced))
                .foregroundColor(.secondary)
        }
    }

    private func abbreviatedPath(_ path: String) -> String {
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        if path.hasPrefix(home) {
            return "~" + path.dropFirst(home.count) + "/"
        }
        return path + "/"
    }

    // MARK: - Step 2: Project Registration

    private var projectStep: some View {
        VStack(spacing: 0) {
            stepHeader(
                title: "프로젝트 등록",
                desc: "지금 진행 중인 일에 이름을 붙여주세요."
            )

            Spacer()

            VStack(alignment: .leading, spacing: 10) {
                HStack(alignment: .top, spacing: 8) {
                    Image(systemName: "lightbulb.fill")
                        .font(.caption)
                        .foregroundColor(.blue)
                    Text("AI는 여기 등록된 프로젝트 안에서만 파일을 분류합니다. 새 프로젝트가 필요하면 언제든 추가할 수 있습니다.")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                .padding(10)
                .background(Color.blue.opacity(0.05))
                .overlay(
                    RoundedRectangle(cornerRadius: 6)
                        .stroke(Color.blue.opacity(0.15), lineWidth: 1)
                )
                .cornerRadius(6)

                HStack(spacing: 8) {
                    TextField("예: 2026 마케팅 캠페인, 신규 서비스 런칭", text: $newProjectName)
                        .textFieldStyle(.roundedBorder)
                        .font(.subheadline)
                        .onSubmit { addProject() }

                    Button(action: addProject) {
                        Image(systemName: "plus")
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.regular)
                    .disabled(newProjectName.trimmingCharacters(in: .whitespaces).isEmpty)
                }

                if !projects.isEmpty {
                    ScrollView {
                        VStack(spacing: 3) {
                            ForEach(projects, id: \.self) { name in
                                HStack(spacing: 8) {
                                    Image(systemName: "folder.fill")
                                        .font(.caption)
                                        .foregroundColor(.secondary)
                                    Text(name)
                                        .font(.subheadline)

                                    Spacer()

                                    Button(action: { removeProject(name) }) {
                                        Image(systemName: "xmark")
                                            .font(.caption2)
                                            .foregroundColor(.secondary)
                                    }
                                    .buttonStyle(.plain)
                                }
                                .padding(.horizontal, 10)
                                .padding(.vertical, 6)
                                .background(Color.secondary.opacity(0.05))
                                .cornerRadius(6)
                            }
                        }
                    }
                    .frame(maxHeight: 90)
                } else {
                    Text("최소 1개의 프로젝트를 등록해주세요")
                        .font(.caption)
                        .foregroundColor(.orange)
                        .padding(.vertical, 4)
                }
            }
            .padding(.horizontal, 24)

            Spacer()

            HStack {
                Button("이전") { goBack() }
                    .buttonStyle(.bordered)
                    .controlSize(.regular)

                Spacer()

                Button(action: { goNext() }) {
                    Text("다음")
                        .frame(minWidth: 80)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.regular)
                .disabled(projects.isEmpty)
            }
            .padding(.horizontal, 32)
            .padding(.bottom, 20)
        }
        .padding(.horizontal)
    }

    // MARK: - Step 3: Provider + API Key (Combined)

    private var providerAndKeyStep: some View {
        let provider = appState.selectedProvider

        return VStack(spacing: 0) {
            stepHeader(
                title: "AI 설정",
                desc: "파일 분류에 사용할 AI를 선택하고\nAPI 키를 입력하세요."
            )

            ScrollView {
                VStack(spacing: 14) {
                    // Provider selection
                    VStack(spacing: 8) {
                        providerCard(
                            provider: .gemini,
                            badge: "무료로 시작 가능",
                            badgeColor: .green,
                            details: "빠른 모델(Flash) → 정밀 모델(Pro)\n무료 티어: 분당 15회, 일 1,500회"
                        )

                        providerCard(
                            provider: .claude,
                            badge: "API 결제 필요",
                            badgeColor: .orange,
                            details: "빠른 모델(Haiku) → 정밀 모델(Sonnet)\n파일당 약 $0.002~$0.01"
                        )
                    }

                    Divider()

                    // API key input inline
                    VStack(alignment: .leading, spacing: 8) {
                        HStack(spacing: 6) {
                            Text("\(provider.displayName) API 키")
                                .font(.caption)
                                .fontWeight(.semibold)

                            Button(action: {
                                let url: URL
                                if provider == .gemini {
                                    url = URL(string: "https://aistudio.google.com/apikey")!
                                } else {
                                    url = URL(string: "https://console.anthropic.com/settings/keys")!
                                }
                                NSWorkspace.shared.open(url)
                            }) {
                                HStack(spacing: 2) {
                                    Image(systemName: "arrow.up.right.square")
                                        .font(.caption2)
                                    Text("키 발급")
                                        .font(.caption2)
                                }
                            }
                            .buttonStyle(.bordered)
                            .controlSize(.mini)
                        }

                        HStack {
                            if showingKey {
                                TextField(provider.keyPlaceholder, text: $keyInput)
                                    .textFieldStyle(.roundedBorder)
                                    .font(.system(.caption, design: .monospaced))
                            } else {
                                SecureField(provider.keyPlaceholder, text: $keyInput)
                                    .textFieldStyle(.roundedBorder)
                                    .font(.caption)
                            }

                            Button(action: {
                                showingKey.toggle()
                                if showingKey, keyInput == "••••••••", provider.hasAPIKey() {
                                    if let key = provider == .claude ? KeychainService.getAPIKey() : KeychainService.getGeminiAPIKey() {
                                        keyInput = key
                                    }
                                } else if !showingKey, provider.hasAPIKey(), keyInput.hasPrefix(provider.keyPrefix) {
                                    keyInput = "••••••••"
                                }
                            }) {
                                Image(systemName: showingKey ? "eye.slash" : "eye")
                            }
                            .buttonStyle(.plain)
                            .font(.caption)
                        }

                        HStack(spacing: 8) {
                            Button("저장") {
                                saveAPIKey(provider: provider)
                            }
                            .buttonStyle(.bordered)
                            .controlSize(.small)
                            .disabled(keyInput.isEmpty || keyInput == "••••••••")

                            if let msg = keySaveMessage {
                                Text(msg)
                                    .font(.caption2)
                                    .foregroundColor(msg == "저장 완료" ? .green : .orange)
                            }

                            Spacer()

                            if appState.hasAPIKey {
                                Label("준비됨", systemImage: "checkmark.circle.fill")
                                    .font(.caption)
                                    .foregroundColor(.green)
                            }
                        }
                    }
                    .padding(12)
                    .background(Color.secondary.opacity(0.05))
                    .cornerRadius(8)
                }
                .padding(.horizontal, 24)
            }

            HStack {
                Button("이전") { goBack() }
                    .buttonStyle(.bordered)
                    .controlSize(.regular)

                Spacer()

                Button(action: completeOnboarding) {
                    Text("설정 완료")
                        .frame(minWidth: 80)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.regular)
                .disabled(!appState.hasAPIKey)
            }
            .padding(.horizontal, 32)
            .padding(.bottom, 20)
        }
        .padding(.horizontal)
        .onAppear {
            keyInput = ""
            keySaveMessage = nil
            showingKey = false
            if provider.hasAPIKey() {
                keyInput = "••••••••"
            }
        }
    }

    private func providerCard(provider: AIProvider, badge: String, badgeColor: Color, details: String) -> some View {
        let isSelected = appState.selectedProvider == provider

        return Button(action: {
            withAnimation(.easeOut(duration: 0.15)) {
                appState.selectedProvider = provider
                keyInput = ""
                keySaveMessage = nil
                showingKey = false
                if provider.hasAPIKey() {
                    keyInput = "••••••••"
                }
            }
        }) {
            HStack(alignment: .top, spacing: 12) {
                ZStack {
                    Circle()
                        .strokeBorder(isSelected ? Color.primary : Color.secondary.opacity(0.4), lineWidth: 1.5)
                        .frame(width: 18, height: 18)
                    if isSelected {
                        Circle()
                            .fill(Color.primary)
                            .frame(width: 10, height: 10)
                    }
                }
                .padding(.top, 2)

                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: 8) {
                        Text(provider.displayName)
                            .font(.subheadline)
                            .fontWeight(.medium)
                            .foregroundColor(.primary)

                        Text(badge)
                            .font(.caption2)
                            .fontWeight(.medium)
                            .foregroundColor(badgeColor)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(badgeColor.opacity(0.12))
                            .cornerRadius(4)
                    }

                    Text(details)
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .lineSpacing(2)
                }

                Spacer()
            }
            .padding(12)
            .background(
                RoundedRectangle(cornerRadius: 8)
                    .fill(isSelected ? Color.primary.opacity(0.05) : Color.secondary.opacity(0.03))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 8)
                    .strokeBorder(isSelected ? Color.primary.opacity(0.4) : Color.secondary.opacity(0.15), lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
    }

    // MARK: - Shared Components

    private func stepHeader(title: String, desc: String) -> some View {
        VStack(spacing: 6) {
            Text(title)
                .font(.title3)
                .fontWeight(.semibold)
                .padding(.top, 16)

            Text(desc)
                .font(.caption)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
                .lineSpacing(2)
        }
        .padding(.horizontal, 24)
        .padding(.bottom, 8)
    }

    private func instructionRow(num: String, text: String) -> some View {
        HStack(alignment: .top, spacing: 8) {
            Text(num)
                .font(.system(.caption, design: .monospaced))
                .fontWeight(.bold)
                .foregroundColor(.secondary)
                .frame(width: 14)
            Text(text)
                .font(.caption)
                .foregroundColor(.secondary)
        }
    }

    // MARK: - Actions

    private func validateAndCreateFolder() -> Bool {
        let path = appState.pkmRootPath
        let fm = FileManager.default

        // Check if parent directory is writable
        let parent = (path as NSString).deletingLastPathComponent
        if fm.fileExists(atPath: parent) && !fm.isWritableFile(atPath: parent) {
            folderError = "선택한 경로에 쓰기 권한이 없습니다.\n다른 경로를 선택해주세요."
            showFolderError = true
            return false
        }

        let pathManager = PKMPathManager(root: path)
        do {
            try pathManager.initializeStructure()
            isStructureReady = pathManager.isInitialized()
            return true
        } catch {
            folderError = "폴더 생성에 실패했습니다: \(error.localizedDescription)\n다른 경로를 선택해주세요."
            showFolderError = true
            return false
        }
    }

    private func loadExistingProjects() {
        let pathManager = PKMPathManager(root: appState.pkmRootPath)
        let fm = FileManager.default
        guard let entries = try? fm.contentsOfDirectory(atPath: pathManager.projectsPath) else { return }

        projects = entries.filter { name in
            guard !name.hasPrefix("."), !name.hasPrefix("_") else { return false }
            let fullPath = (pathManager.projectsPath as NSString).appendingPathComponent(name)
            var isDir: ObjCBool = false
            return fm.fileExists(atPath: fullPath, isDirectory: &isDir) && isDir.boolValue
        }.sorted()
    }

    private func sanitizeProjectName(_ raw: String) -> String {
        let invalid = CharacterSet(charactersIn: "/:\\0\t\n\r")
        let cleaned = raw.components(separatedBy: invalid).joined()
        return String(cleaned.prefix(255)).trimmingCharacters(in: .whitespaces)
    }

    private func addProject() {
        let raw = newProjectName.trimmingCharacters(in: .whitespaces)
        let name = sanitizeProjectName(raw)
        guard !name.isEmpty, !projects.contains(name) else { return }

        let pathManager = PKMPathManager(root: appState.pkmRootPath)
        let projectDir = (pathManager.projectsPath as NSString).appendingPathComponent(name)
        let fm = FileManager.default

        do {
            try fm.createDirectory(atPath: projectDir, withIntermediateDirectories: true)
            let indexPath = (projectDir as NSString).appendingPathComponent("\(name).md")
            if !fm.fileExists(atPath: indexPath) {
                let content = FrontmatterWriter.createIndexNote(
                    folderName: name,
                    para: .project,
                    description: "\(name) 프로젝트"
                )
                try content.write(toFile: indexPath, atomically: true, encoding: .utf8)
            }
            projects.append(name)
            projects.sort()
            newProjectName = ""
        } catch {
            // Show inline feedback if project creation fails
            newProjectName = ""
        }
    }

    private func removeProject(_ name: String) {
        let pathManager = PKMPathManager(root: appState.pkmRootPath)
        let projectDir = (pathManager.projectsPath as NSString).appendingPathComponent(name)
        try? FileManager.default.removeItem(atPath: projectDir)
        projects.removeAll { $0 == name }
    }

    private func saveAPIKey(provider: AIProvider) {
        if keyInput.hasPrefix(provider.keyPrefix) {
            let saved = provider.saveAPIKey(keyInput)
            keySaveMessage = saved ? "저장 완료" : "저장 실패"
            appState.updateAPIKeyStatus()
        } else {
            keySaveMessage = "\(provider.keyPlaceholder)로 시작하는 키를 입력하세요"
        }
    }

    private func completeOnboarding() {
        UserDefaults.standard.set(true, forKey: "onboardingCompleted")
        UserDefaults.standard.removeObject(forKey: "onboardingStep")
        AICompanionService.updateIfNeeded(pkmRoot: appState.pkmRootPath)
        appState.setupWatchdog()
        appState.currentScreen = .inbox
    }
}
