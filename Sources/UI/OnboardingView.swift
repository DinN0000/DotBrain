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
    @State private var areas: [String] = []
    @State private var newAreaName: String = ""
    @State private var selectedArea: String = ""
    @State private var projectAreas: [String: String] = [:]

    private let totalSteps = 6

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
                case 2: areaStep
                case 3: projectStep
                case 4: providerAndKeyStep
                case 5: trialStep
                default: trialStep
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

            Text("Built for humans.\nOptimized for AI.")
                .font(.system(.title3, design: .monospaced))
                .fontWeight(.bold)
                .multilineTextAlignment(.center)
                .lineSpacing(2)
                .padding(.bottom, 6)

            Text("문서를 넣으면 AI가 읽고 정리합니다")
                .font(.caption)
                .foregroundColor(.secondary)
                .padding(.bottom, 16)

            // Before — chaos
            VStack(alignment: .leading, spacing: 3) {
                beforeFileRow("킥오프_수정_최종_진짜최종(2).docx")
                beforeFileRow("경쟁사_분석_v3_수정중.xlsx")
                beforeFileRow("서비스플로우_캡처.png")
                beforeFileRow("회의_급한메모_0115.md")
                beforeFileRow("WBS_초안_검토필요.pdf")
            }
            .padding(10)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color.red.opacity(0.04))
            .overlay(
                RoundedRectangle(cornerRadius: 8)
                    .strokeBorder(Color.red.opacity(0.1), lineWidth: 1)
            )
            .cornerRadius(8)
            .padding(.horizontal, 32)

            Image(systemName: "arrow.down")
                .font(.system(size: 11, weight: .semibold))
                .foregroundColor(.green)
                .padding(.vertical, 8)

            // After — order
            VStack(alignment: .leading, spacing: 3) {
                afterFolderRow("Project/신규 서비스/")
                afterFileRow("킥오프 미팅.md", indent: true)
                afterFileRow("WBS.md", indent: true)
                afterFolderRow("Area/전략/")
                afterFileRow("경쟁사 분석.md", indent: true)
                afterFolderRow("Resource/")
                afterFileRow("회의 메모.md", indent: true)

                HStack(spacing: 4) {
                    Image(systemName: "archivebox")
                        .font(.caption2)
                        .foregroundColor(.secondary)
                    Text("_assets/")
                        .font(.system(.caption2, design: .monospaced))
                        .foregroundColor(.secondary)
                    Text("docx · xlsx · png · pdf")
                        .font(.caption2)
                        .foregroundColor(.secondary.opacity(0.7))
                }
                .padding(.top, 2)
            }
            .padding(10)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color.green.opacity(0.05))
            .cornerRadius(8)
            .overlay(
                RoundedRectangle(cornerRadius: 8)
                    .strokeBorder(Color.green.opacity(0.2), lineWidth: 1)
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
            Image(systemName: "doc")
                .font(.caption2)
            Text(name)
                .font(.system(.caption, design: .monospaced))
                .foregroundColor(.secondary)
        }
    }

    private func afterFolderRow(_ name: String) -> some View {
        HStack(spacing: 5) {
            Image(systemName: "folder")
                .font(.caption2)
            Text(name)
                .font(.system(.caption, design: .monospaced))
                .fontWeight(.medium)
        }
    }

    private func afterFileRow(_ name: String, indent: Bool) -> some View {
        HStack(spacing: 5) {
            Image(systemName: "doc")
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
                                metaphor: "진행 중인 작업",
                                desc: "마감이 있는 프로젝트 단위 업무"
                            )
                            paraExplanationRow(
                                folder: "Area",
                                metaphor: "도메인",
                                desc: "지속적으로 관리하는 책임 영역. 제품, 사업, 팀"
                            )
                            paraExplanationRow(
                                folder: "Resource",
                                metaphor: "참고 자료",
                                desc: "가이드, 레퍼런스, 분석 보고서"
                            )
                            paraExplanationRow(
                                folder: "Archive",
                                metaphor: "보관함",
                                desc: "완료되거나 비활성화된 문서"
                            )
                        }
                    }

                }
                .padding(14)
                .background(Color.secondary.opacity(0.05))
                .cornerRadius(8)
                .padding(.horizontal, 24)
            }

            HStack {
                if isReOnboarding {
                    Button("취소") {
                        UserDefaults.standard.removeObject(forKey: "onboardingStep")
                        appState.currentScreen = .inbox
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.regular)
                } else {
                    Button("이전") { goBack() }
                        .buttonStyle(.bordered)
                        .controlSize(.regular)
                }

                Spacer()

                Button(action: {
                    if !isStructureReady {
                        if !validateAndCreateFolder() { return }
                    }
                    loadExistingAreas()
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

    // MARK: - Step 2: Area (Domain) Registration

    private var areaStep: some View {
        VStack(spacing: 0) {
            stepHeader(
                title: "도메인 등록",
                desc: "지속적으로 관리하는 책임 영역을 등록합니다."
            )

            Spacer()

            VStack(alignment: .leading, spacing: 10) {
                HStack(alignment: .top, spacing: 8) {
                    Image(systemName: "lightbulb.fill")
                        .font(.caption)
                        .foregroundColor(.blue)
                    Text("예: 제품명, 사업 도메인, 팀 이름 등")
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
                    TextField("도메인 이름 입력 후 + 버튼", text: $newAreaName)
                        .textFieldStyle(.roundedBorder)
                        .font(.subheadline)
                        .onSubmit { addArea() }

                    Button(action: addArea) {
                        Image(systemName: "plus")
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.regular)
                    .disabled(newAreaName.trimmingCharacters(in: .whitespaces).isEmpty)
                }

                if !areas.isEmpty {
                    ScrollView {
                        VStack(spacing: 3) {
                            ForEach(areas.reversed(), id: \.self) { name in
                                HStack(spacing: 8) {
                                    Image(systemName: "square.stack.3d.up.fill")
                                        .font(.caption)
                                        .foregroundColor(.green)
                                    Text(name)
                                        .font(.subheadline)

                                    Spacer()

                                    Button(action: { removeArea(name) }) {
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
                    Text("건너뛰어도 됩니다. 나중에 추가할 수 있어요.")
                        .font(.caption)
                        .foregroundColor(.secondary)
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

                Button(action: {
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
    }

    // MARK: - Step 3: Project Registration

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

                HStack(spacing: 6) {
                    TextField("프로젝트 이름", text: $newProjectName)
                        .textFieldStyle(.roundedBorder)
                        .font(.subheadline)
                        .onSubmit { addProject() }

                    if !areas.isEmpty {
                        Picker("", selection: $selectedArea) {
                            Text("선택").tag("")
                            ForEach(areas, id: \.self) { area in
                                Text(area).tag(area)
                            }
                        }
                        .pickerStyle(.menu)
                        .frame(maxWidth: 100)
                        .lineLimit(1)
                        .truncationMode(.tail)
                    }

                    Button(action: addProject) {
                        Image(systemName: "plus")
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.regular)
                    .disabled(newProjectName.trimmingCharacters(in: .whitespaces).isEmpty)
                    .accessibilityLabel("프로젝트 추가")
                }

                if !projects.isEmpty {
                    ScrollView {
                        VStack(spacing: 3) {
                            ForEach(projects.reversed(), id: \.self) { name in
                                HStack(spacing: 8) {
                                    Image(systemName: "folder.fill")
                                        .font(.caption)
                                        .foregroundColor(.secondary)
                                    Text(name)
                                        .font(.subheadline)

                                    if let area = projectAreas[name], !area.isEmpty {
                                        Text(area)
                                            .font(.caption2)
                                            .foregroundColor(.green)
                                            .padding(.horizontal, 6)
                                            .padding(.vertical, 1)
                                            .background(Color.green.opacity(0.1))
                                            .cornerRadius(4)
                                    }

                                    Spacer()

                                    Button(action: { removeProject(name) }) {
                                        Image(systemName: "xmark")
                                            .font(.caption2)
                                            .foregroundColor(.secondary)
                                    }
                                    .buttonStyle(.plain)
                                    .accessibilityLabel("\(name) 삭제")
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

                Button(action: {
                    if appState.hasAPIKey {
                        // Skip API key step, go to final
                        direction = 1
                        step = 5
                        UserDefaults.standard.set(step, forKey: "onboardingStep")
                    } else {
                        goNext()
                    }
                }) {
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
                title: "AI 연결",
                desc: "AI가 파일을 읽고 분류합니다. API 키가 필요합니다."
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

                    // Claude Code 안내
                    HStack(alignment: .top, spacing: 8) {
                        Image(systemName: "terminal")
                            .font(.caption)
                            .foregroundColor(.secondary)
                        Text("API 키 없이도, 만들어진 폴더에 Claude Code를 연결해서 사용할 수 있습니다.")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                    .padding(10)
                    .background(Color.secondary.opacity(0.05))
                    .cornerRadius(6)
                }
                .padding(.horizontal, 24)
            }

            VStack(spacing: 6) {
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
                }

                if !appState.hasAPIKey {
                    Button(action: { goNext() }) {
                        Text("건너뛰기")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                    .buttonStyle(.plain)
                }
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
        var cleaned = raw.components(separatedBy: invalid).joined()
        cleaned = cleaned.replacingOccurrences(of: "..", with: "")
        return String(cleaned.prefix(255)).trimmingCharacters(in: .whitespaces)
    }

    private func addProject() {
        let raw = newProjectName.trimmingCharacters(in: .whitespaces)
        let name = sanitizeProjectName(raw)
        guard !name.isEmpty, !projects.contains(name) else { return }

        let pathManager = PKMPathManager(root: appState.pkmRootPath)
        let projectDir = (pathManager.projectsPath as NSString).appendingPathComponent(name)
        guard pathManager.isPathSafe(projectDir) else { return }
        let fm = FileManager.default

        let areaName = selectedArea.isEmpty ? nil : selectedArea

        do {
            try fm.createDirectory(atPath: projectDir, withIntermediateDirectories: true)
            let indexPath = (projectDir as NSString).appendingPathComponent("\(name).md")
            if !fm.fileExists(atPath: indexPath) {
                let content = FrontmatterWriter.createIndexNote(
                    folderName: name,
                    para: .project,
                    description: "\(name) 프로젝트",
                    area: areaName
                )
                try content.write(toFile: indexPath, atomically: true, encoding: .utf8)
            }

            if let area = areaName {
                updateAreaProjects(area: area, addProject: name)
            }

            projects.append(name)
            projectAreas[name] = areaName ?? ""
            newProjectName = ""
        } catch {
            NSLog("[OnboardingView] 프로젝트 생성 실패: %@", error.localizedDescription)
            newProjectName = ""
        }
    }

    private func updateAreaProjects(area: String, addProject projectName: String) {
        let pathManager = PKMPathManager(root: appState.pkmRootPath)
        let areaIndexPath = (pathManager.areaPath as NSString)
            .appendingPathComponent(area)
            .appending("/\(area).md")

        guard let content = try? String(contentsOfFile: areaIndexPath, encoding: .utf8) else { return }
        var (fm, body) = Frontmatter.parse(markdown: content)

        var currentProjects = fm.projects ?? []
        if !currentProjects.contains(projectName) {
            currentProjects.append(projectName)
            currentProjects.sort()
        }
        fm.projects = currentProjects

        let updated = fm.stringify() + "\n" + body
        try? updated.write(toFile: areaIndexPath, atomically: true, encoding: .utf8)
    }

    private func removeProject(_ name: String) {
        let pathManager = PKMPathManager(root: appState.pkmRootPath)
        let projectDir = (pathManager.projectsPath as NSString).appendingPathComponent(name)
        try? FileManager.default.trashItem(at: URL(fileURLWithPath: projectDir), resultingItemURL: nil)
        projects.removeAll { $0 == name }
    }

    private func loadExistingAreas() {
        let pathManager = PKMPathManager(root: appState.pkmRootPath)
        let fm = FileManager.default
        guard let entries = try? fm.contentsOfDirectory(atPath: pathManager.areaPath) else { return }

        areas = entries.filter { name in
            guard !name.hasPrefix("."), !name.hasPrefix("_") else { return false }
            let fullPath = (pathManager.areaPath as NSString).appendingPathComponent(name)
            var isDir: ObjCBool = false
            return fm.fileExists(atPath: fullPath, isDirectory: &isDir) && isDir.boolValue
        }.sorted()
    }

    private func addArea() {
        let raw = newAreaName.trimmingCharacters(in: .whitespaces)
        let name = sanitizeProjectName(raw)
        guard !name.isEmpty, !areas.contains(name) else { return }

        let pathManager = PKMPathManager(root: appState.pkmRootPath)
        let areaDir = (pathManager.areaPath as NSString).appendingPathComponent(name)
        guard pathManager.isPathSafe(areaDir) else { return }
        let fm = FileManager.default

        do {
            try fm.createDirectory(atPath: areaDir, withIntermediateDirectories: true)
            let indexPath = (areaDir as NSString).appendingPathComponent("\(name).md")
            if !fm.fileExists(atPath: indexPath) {
                let content = FrontmatterWriter.createIndexNote(
                    folderName: name,
                    para: .area,
                    description: "\(name) 도메인"
                )
                try content.write(toFile: indexPath, atomically: true, encoding: .utf8)
            }
            areas.append(name)
            newAreaName = ""
        } catch {
            NSLog("[OnboardingView] Area 생성 실패: %@", error.localizedDescription)
            newAreaName = ""
        }
    }

    private func removeArea(_ name: String) {
        let pathManager = PKMPathManager(root: appState.pkmRootPath)
        let areaDir = (pathManager.areaPath as NSString).appendingPathComponent(name)
        try? FileManager.default.trashItem(at: URL(fileURLWithPath: areaDir), resultingItemURL: nil)
        areas.removeAll { $0 == name }
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

    // MARK: - Step 4: Quick Start Guide

    private var isReOnboarding: Bool {
        UserDefaults.standard.bool(forKey: "onboardingCompleted")
    }

    private var trialStep: some View {
        VStack(spacing: 0) {
            stepHeader(
                title: appState.hasAPIKey
                    ? (isReOnboarding ? "볼트 설정 완료!" : "준비 완료!")
                    : "거의 다 됐어요!",
                desc: appState.hasAPIKey
                    ? (isReOnboarding
                        ? "새 볼트가 준비되었습니다.\n인박스에 파일을 넣어 정리를 시작하세요."
                        : "이제 인박스에 파일을 넣으면\nAI가 자동으로 정리합니다.")
                    : "API 키 없이도 폴더 구조를 활용할 수 있습니다."
            )

            Spacer()

            Text(appState.hasAPIKey ? "·‿·" : "·_·")
                .font(.system(size: 36, design: .monospaced))
                .padding(.bottom, 16)

            VStack(alignment: .leading, spacing: 8) {
                if appState.hasAPIKey {
                    guideRow(icon: "1.circle.fill", text: "메뉴바에서 DotBrain을 클릭")
                    guideRow(icon: "2.circle.fill", text: "파일을 드래그하거나 Cmd+V로 붙여넣기")
                    guideRow(icon: "3.circle.fill", text: "\"정리하기\" 버튼을 누르면 AI가 분류")
                } else {
                    guideRow(icon: "terminal", text: "Claude Code로 폴더에 연결해서 사용")
                    guideRow(icon: "gearshape", text: "설정에서 언제든 API 키를 추가 가능")
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

                Button(action: completeOnboarding) {
                    Text("시작하기")
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

    private func guideRow(icon: String, text: String) -> some View {
        HStack(spacing: 10) {
            Image(systemName: icon)
                .font(.subheadline)
                .foregroundColor(.accentColor)
                .frame(width: 20)
            Text(text)
                .font(.subheadline)
        }
    }

    private func completeOnboarding() {
        UserDefaults.standard.set(true, forKey: "onboardingCompleted")
        UserDefaults.standard.removeObject(forKey: "onboardingStep")
        AICompanionService.updateIfNeeded(pkmRoot: appState.pkmRootPath)
        appState.setupWatchdog()
        appState.currentScreen = .inbox

        // Register all onboarding-created files in hash cache so vault inspector starts clean
        let root = appState.pkmRootPath
        Task.detached(priority: .utility) {
            let cache = ContentHashCache(pkmRoot: root)
            await cache.load()
            let pathManager = PKMPathManager(root: root)
            let fm = FileManager.default
            var allFiles: [String] = []
            for category in PARACategory.allCases {
                let basePath = pathManager.paraPath(for: category)
                guard let enumerator = fm.enumerator(atPath: basePath) else { continue }
                while let element = enumerator.nextObject() as? String {
                    guard element.hasSuffix(".md"), !element.hasPrefix("."), !element.hasPrefix("_") else { continue }
                    allFiles.append((basePath as NSString).appendingPathComponent(element))
                }
            }
            if !allFiles.isEmpty {
                await cache.updateHashes(allFiles)
            }
        }
    }
}
