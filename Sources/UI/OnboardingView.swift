import SwiftUI

struct OnboardingView: View {
    @EnvironmentObject var appState: AppState
    @State private var step: Int = 0
    @State private var showFolderPicker = false
    @State private var newProjectName: String = ""
    @State private var projects: [String] = []
    @State private var isStructureReady = false
    @State private var keyInput: String = ""
    @State private var showingKey: Bool = false
    @State private var keySaveMessage: String?
    @State private var direction: Int = 1 // 1 = forward, -1 = back

    private let totalSteps = 5

    var body: some View {
        VStack(spacing: 0) {
            // Step indicator
            stepIndicator
                .padding(.top, 16)
                .padding(.bottom, 8)

            // Step content
            Group {
                switch step {
                case 0: welcomeStep
                case 1: providerStep
                case 2: apiKeyStep
                case 3: folderStep
                case 4: projectStep
                default: projectStep
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
        }
        .fileImporter(isPresented: $showFolderPicker, allowedContentTypes: [.folder]) { result in
            if case .success(let url) = result {
                appState.pkmRootPath = url.path
            }
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
    }

    private func goBack() {
        direction = -1
        step -= 1
    }

    private var navButtons: some View {
        HStack {
            if step > 0 {
                Button("이전") { goBack() }
                    .buttonStyle(.bordered)
                    .controlSize(.regular)
            }

            Spacer()
        }
        .padding(.horizontal, 32)
        .padding(.bottom, 20)
    }

    // MARK: - Step 1: Welcome

    private var welcomeStep: some View {
        VStack(spacing: 0) {
            Spacer()

            Text("·‿·")
                .font(.system(size: 36, design: .monospaced))
                .foregroundColor(.primary)
                .padding(.bottom, 12)

            Text("DotBrain에 오신 걸 환영합니다")
                .font(.title3)
                .fontWeight(.semibold)
                .padding(.bottom, 6)

            Text("파일을 던지면 AI가 PARA 구조로 정리합니다")
                .font(.subheadline)
                .foregroundColor(.secondary)
                .padding(.bottom, 20)

            VStack(alignment: .leading, spacing: 6) {
                paraRow(letter: "P", name: "Project", desc: "진행 중인 프로젝트")
                paraRow(letter: "A", name: "Area", desc: "지속적으로 관리하는 영역")
                paraRow(letter: "R", name: "Resource", desc: "참고 자료 및 레퍼런스")
                paraRow(letter: "A", name: "Archive", desc: "완료되거나 보관할 것")
            }
            .padding(14)
            .background(Color.secondary.opacity(0.05))
            .cornerRadius(8)
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

    private func paraRow(letter: String, name: String, desc: String) -> some View {
        HStack(spacing: 10) {
            Text(letter)
                .font(.system(.subheadline, design: .monospaced))
                .fontWeight(.bold)
                .frame(width: 18)
            VStack(alignment: .leading, spacing: 1) {
                Text(name)
                    .font(.subheadline)
                    .fontWeight(.medium)
                Text(desc)
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
        }
    }

    // MARK: - Step 2: Provider Selection

    private var providerStep: some View {
        VStack(spacing: 0) {
            stepHeader(
                title: "AI 제공자 선택",
                desc: "파일 분류에 사용할 AI를 선택하세요.\n나중에 설정에서 변경할 수 있습니다."
            )

            Spacer()

            VStack(spacing: 10) {
                providerCard(
                    provider: .gemini,
                    badge: "무료로 시작 가능",
                    badgeColor: .green,
                    details: "Flash (빠름) → Pro (정밀)\n무료 티어: 분당 15회, 일 1500회"
                )

                providerCard(
                    provider: .claude,
                    badge: "API 결제 필요",
                    badgeColor: .orange,
                    details: "Haiku 4.5 (빠름) → Sonnet 4.5 (정밀)\n파일당 약 $0.002~$0.01"
                )
            }
            .padding(.horizontal, 24)

            Spacer()

            HStack {
                Button("이전") { goBack() }
                    .buttonStyle(.bordered)
                    .controlSize(.regular)

                Spacer()

                Button(action: {
                    keyInput = ""
                    keySaveMessage = nil
                    showingKey = false
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
    }

    private func providerCard(provider: AIProvider, badge: String, badgeColor: Color, details: String) -> some View {
        let isSelected = appState.selectedProvider == provider

        return Button(action: {
            withAnimation(.easeOut(duration: 0.15)) {
                appState.selectedProvider = provider
            }
        }) {
            HStack(alignment: .top, spacing: 12) {
                // Radio circle
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

    // MARK: - Step 3: API Key

    private var apiKeyStep: some View {
        let provider = appState.selectedProvider

        return VStack(spacing: 0) {
            stepHeader(
                title: "\(provider.rawValue) API 키 입력",
                desc: "AI를 사용하려면 API 키가 필요합니다."
            )

            Spacer()

            // How to get a key
            VStack(alignment: .leading, spacing: 8) {
                Text("API 키 발급 방법")
                    .font(.caption)
                    .fontWeight(.semibold)

                if provider == .gemini {
                    instructionRow(num: "1", text: "aistudio.google.com/apikey 접속")
                    instructionRow(num: "2", text: "Google 계정으로 로그인")
                    instructionRow(num: "3", text: "\"Create API Key\" 클릭")
                    instructionRow(num: "4", text: "생성된 키를 아래에 붙여넣기")
                } else {
                    instructionRow(num: "1", text: "console.anthropic.com 접속")
                    instructionRow(num: "2", text: "Settings → API Keys")
                    instructionRow(num: "3", text: "\"Create Key\" 클릭")
                    instructionRow(num: "4", text: "생성된 키를 아래에 붙여넣기")
                }

                Button(action: {
                    let url: URL
                    if provider == .gemini {
                        url = URL(string: "https://aistudio.google.com/apikey")!
                    } else {
                        url = URL(string: "https://console.anthropic.com/settings/keys")!
                    }
                    NSWorkspace.shared.open(url)
                }) {
                    HStack(spacing: 4) {
                        Image(systemName: "arrow.up.right.square")
                            .font(.caption2)
                        Text("브라우저에서 열기")
                            .font(.caption)
                    }
                }
                .buttonStyle(.bordered)
                .controlSize(.mini)
            }
            .padding(12)
            .background(Color.secondary.opacity(0.05))
            .cornerRadius(8)
            .padding(.horizontal, 24)
            .padding(.bottom, 14)

            // Key input
            VStack(alignment: .leading, spacing: 8) {
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
                .disabled(!appState.hasAPIKey)
            }
            .padding(.horizontal, 32)
            .padding(.bottom, 20)
        }
        .padding(.horizontal)
        .onAppear {
            if provider.hasAPIKey() {
                keyInput = "••••••••"
            }
        }
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

    private func saveAPIKey(provider: AIProvider) {
        if keyInput.hasPrefix(provider.keyPrefix) {
            let saved = provider.saveAPIKey(keyInput)
            keySaveMessage = saved ? "저장 완료" : "저장 실패"
            appState.updateAPIKeyStatus()
        } else {
            keySaveMessage = "\(provider.keyPlaceholder)로 시작하는 키를 입력하세요"
        }
    }

    // MARK: - Step 4: Folder Setup

    private var folderStep: some View {
        VStack(spacing: 0) {
            stepHeader(
                title: "PKM 폴더 설정",
                desc: "파일이 정리될 폴더를 선택하세요.\n이 안에 PARA 폴더 구조가 만들어집니다."
            )

            Spacer()

            VStack(alignment: .leading, spacing: 12) {
                // Current path
                VStack(alignment: .leading, spacing: 6) {
                    Text("현재 경로")
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

                // Structure status
                VStack(alignment: .leading, spacing: 8) {
                    Text("폴더 구조")
                        .font(.caption)
                        .fontWeight(.medium)

                    if isStructureReady {
                        Label("PARA 구조 확인됨", systemImage: "checkmark.circle.fill")
                            .font(.caption)
                            .foregroundColor(.green)

                        VStack(alignment: .leading, spacing: 2) {
                            folderPreviewRow("_Inbox/", desc: "파일을 여기에 넣으면 분류 시작")
                            folderPreviewRow("1_Project/", desc: "진행 중인 프로젝트")
                            folderPreviewRow("2_Area/", desc: "지속 관리 영역")
                            folderPreviewRow("3_Resource/", desc: "참고 자료")
                            folderPreviewRow("4_Archive/", desc: "보관")
                        }
                        .padding(8)
                        .background(Color.secondary.opacity(0.03))
                        .cornerRadius(6)
                    } else {
                        Label("아직 PARA 폴더가 없습니다", systemImage: "exclamationmark.triangle.fill")
                            .font(.caption)
                            .foregroundColor(.orange)

                        Button(action: createFolderStructure) {
                            HStack {
                                Image(systemName: "folder.badge.plus")
                                Text("지금 만들기")
                            }
                            .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(.borderedProminent)
                        .controlSize(.small)
                        .tint(.primary.opacity(0.85))
                    }
                }
            }
            .padding(14)
            .background(Color.secondary.opacity(0.05))
            .cornerRadius(8)
            .padding(.horizontal, 24)

            Spacer()

            HStack {
                Button("이전") { goBack() }
                    .buttonStyle(.bordered)
                    .controlSize(.regular)

                Spacer()

                Button(action: {
                    loadExistingProjects()
                    goNext()
                }) {
                    Text("다음")
                        .frame(minWidth: 80)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.regular)
                .disabled(!isStructureReady)
            }
            .padding(.horizontal, 32)
            .padding(.bottom, 20)
        }
        .padding(.horizontal)
        .onAppear {
            isStructureReady = PKMPathManager(root: appState.pkmRootPath).isInitialized()
        }
    }

    private func folderPreviewRow(_ name: String, desc: String) -> some View {
        HStack(spacing: 6) {
            Text(name)
                .font(.system(.caption2, design: .monospaced))
                .fontWeight(.medium)
                .frame(width: 80, alignment: .leading)
            Text(desc)
                .font(.caption2)
                .foregroundColor(.secondary)
        }
    }

    // MARK: - Step 5: Project + Complete

    private var projectStep: some View {
        VStack(spacing: 0) {
            stepHeader(
                title: "프로젝트 등록",
                desc: "지금 진행 중인 작업이 있다면 등록하세요.\nAI가 관련 파일을 이 프로젝트로 분류합니다."
            )

            Spacer()

            VStack(alignment: .leading, spacing: 10) {
                // Info box
                HStack(alignment: .top, spacing: 8) {
                    Image(systemName: "info.circle")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Project만 직접 관리합니다")
                            .font(.caption)
                            .fontWeight(.medium)
                        Text("Area, Resource, Archive는 AI가 자동 분류합니다.")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }
                .padding(10)
                .background(Color.secondary.opacity(0.05))
                .cornerRadius(6)

                // Add project input
                HStack(spacing: 8) {
                    TextField("프로젝트명 (예: MyApp)", text: $newProjectName)
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

                // Project list
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

                Button(action: completeOnboarding) {
                    Text("설정 완료")
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

    // MARK: - Actions

    private func createFolderStructure() {
        let pathManager = PKMPathManager(root: appState.pkmRootPath)
        try? pathManager.initializeStructure()
        isStructureReady = pathManager.isInitialized()
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

    private func addProject() {
        let name = newProjectName.trimmingCharacters(in: .whitespaces)
        guard !name.isEmpty, !projects.contains(name) else { return }

        let pathManager = PKMPathManager(root: appState.pkmRootPath)
        let projectDir = (pathManager.projectsPath as NSString).appendingPathComponent(name)
        let fm = FileManager.default

        try? fm.createDirectory(atPath: projectDir, withIntermediateDirectories: true)
        let indexPath = (projectDir as NSString).appendingPathComponent("\(name).md")
        if !fm.fileExists(atPath: indexPath) {
            let content = FrontmatterWriter.createIndexNote(
                folderName: name,
                para: .project,
                description: "\(name) 프로젝트"
            )
            try? content.write(toFile: indexPath, atomically: true, encoding: .utf8)
        }

        projects.append(name)
        projects.sort()
        newProjectName = ""
    }

    private func removeProject(_ name: String) {
        let pathManager = PKMPathManager(root: appState.pkmRootPath)
        let projectDir = (pathManager.projectsPath as NSString).appendingPathComponent(name)
        try? FileManager.default.removeItem(atPath: projectDir)
        projects.removeAll { $0 == name }
    }

    private func completeOnboarding() {
        UserDefaults.standard.set(true, forKey: "onboardingCompleted")
        appState.currentScreen = .inbox
    }
}
