import SwiftUI

struct OnboardingView: View {
    @EnvironmentObject var appState: AppState
    @State private var step: Int
    // Folder picker: uses NSOpenPanel directly (pickVaultFolder) to avoid TCC dialogs
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
    @State private var fdaGranted = false

    struct ProjectEntry {
        var area: String
        var summary: String
    }
    @State private var projectEntries: [String: ProjectEntry] = [:]
    @State private var expandedArea: String?
    @State private var areaSummaries: [String: String] = [:]
    @State private var newProjectSummary: String = ""

    private let totalSteps = 6


    init() {
        let saved = UserDefaults.standard.integer(forKey: AppState.DefaultsKey.onboardingStep)
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
                case 1: permissionStep
                case 2: folderStep
                case 3: domainAndProjectStep
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
        .alert(L10n.Onboarding.folderCreationFailed, isPresented: $showFolderError) {
            Button(L10n.Onboarding.confirm) {}
        } message: {
            Text(folderError ?? L10n.Onboarding.unknownError)
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
        UserDefaults.standard.set(step, forKey: AppState.DefaultsKey.onboardingStep)
    }

    private func goBack() {
        direction = -1
        step -= 1
        UserDefaults.standard.set(step, forKey: AppState.DefaultsKey.onboardingStep)
    }

    // MARK: - Step 0: Welcome (Before/After)

    private var welcomeStep: some View {
        VStack(spacing: 0) {
            Text("DotBrain")
                .font(.title)
                .fontWeight(.bold)
                .padding(.top, 16)
                .padding(.bottom, 2)

            Text("Built for humans. Optimized for AI.")
                .font(.caption)
                .foregroundColor(.secondary)
                .padding(.bottom, 20)

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
                Text(L10n.Onboarding.getStarted)
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

    // MARK: - Step 1: Permission (Full Disk Access)

    private var permissionStep: some View {
        VStack(spacing: 0) {
            stepHeader(
                title: L10n.Onboarding.permissionTitle,
                desc: L10n.Onboarding.permissionDesc
            )

            VStack(spacing: 16) {
                // Status indicator
                HStack(spacing: 10) {
                    Image(systemName: fdaGranted ? "checkmark.circle.fill" : "lock.shield")
                        .font(.title2)
                        .foregroundColor(fdaGranted ? .green : .orange)

                    VStack(alignment: .leading, spacing: 2) {
                        Text(fdaGranted ? L10n.Onboarding.permissionGranted : L10n.Onboarding.permissionNeeded)
                            .font(.subheadline)
                            .fontWeight(.medium)
                        Text(fdaGranted
                            ? L10n.Onboarding.permissionReady
                            : L10n.Onboarding.permissionFallback)
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(12)
                .background(
                    RoundedRectangle(cornerRadius: 8)
                        .fill(fdaGranted ? Color.green.opacity(0.05) : Color.orange.opacity(0.05))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 8)
                        .strokeBorder(fdaGranted ? Color.green.opacity(0.2) : Color.orange.opacity(0.2), lineWidth: 1)
                )

                if !fdaGranted {
                    // Instructions
                    VStack(alignment: .leading, spacing: 8) {
                        instructionRow(num: "1", text: L10n.Onboarding.instructionStep1)
                        instructionRow(num: "2", text: L10n.Onboarding.instructionStep2)
                        instructionRow(num: "3", text: L10n.Onboarding.instructionStep3)
                    }
                    .padding(12)
                    .background(Color.secondary.opacity(0.05))
                    .cornerRadius(8)

                    Button(action: { Self.openFullDiskAccessSettings() }) {
                        HStack(spacing: 6) {
                            Image(systemName: "gearshape")
                                .font(.system(size: 12))
                            Text(L10n.Onboarding.openSystemSettings)
                                .fontWeight(.medium)
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 6)
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.regular)
                }
            }
            .padding(.horizontal, 24)

            Spacer()

            HStack {
                Button(L10n.Onboarding.previous) { goBack() }
                    .buttonStyle(.bordered)
                    .controlSize(.regular)

                Spacer()

                if fdaGranted {
                    Button(action: { goNext() }) {
                        Text(L10n.Onboarding.next)
                            .frame(minWidth: 80)
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.regular)
                } else {
                    Button(action: { goNext() }) {
                        Text(L10n.Onboarding.skip)
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
        .task(id: step) {
            guard step == 1 else { return }
            fdaGranted = AppState.hasFullDiskAccess()
            while !fdaGranted && step == 1 {
                try? await Task.sleep(for: .seconds(1))
                fdaGranted = AppState.hasFullDiskAccess()
            }
        }
    }

    private static func openFullDiskAccessSettings() {
        AppState.shared.openFullDiskAccessSettings()
    }

    // MARK: - Step 2: Folder Setup

    private var folderStep: some View {
        VStack(spacing: 0) {
            stepHeader(
                title: L10n.Onboarding.folderTitle,
                desc: L10n.Onboarding.folderDesc
            )

            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    // Folder path selection
                    VStack(alignment: .leading, spacing: 6) {
                        Text(L10n.Onboarding.storagePath)
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

                            Button(L10n.Onboarding.change) {
                                pickVaultFolder()
                            }
                            .buttonStyle(.bordered)
                            .controlSize(.mini)
                        }
                    }

                    Divider()

                    // PARA explanation
                    VStack(alignment: .leading, spacing: 6) {
                        Text(L10n.Onboarding.paraStructure)
                            .font(.caption)
                            .fontWeight(.medium)

                        VStack(alignment: .leading, spacing: 8) {
                            paraExplanationRow(
                                folder: "Project",
                                metaphor: L10n.Onboarding.paraProjectMetaphor,
                                desc: L10n.Onboarding.paraProjectDesc
                            )
                            paraExplanationRow(
                                folder: "Area",
                                metaphor: L10n.Onboarding.paraAreaMetaphor,
                                desc: L10n.Onboarding.paraAreaDesc
                            )
                            paraExplanationRow(
                                folder: "Resource",
                                metaphor: L10n.Onboarding.paraResourceMetaphor,
                                desc: L10n.Onboarding.paraResourceDesc
                            )
                            paraExplanationRow(
                                folder: "Archive",
                                metaphor: L10n.Onboarding.paraArchiveMetaphor,
                                desc: L10n.Onboarding.paraArchiveDesc
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
                    Button(L10n.Onboarding.cancel) {
                        UserDefaults.standard.removeObject(forKey: AppState.DefaultsKey.onboardingStep)
                        appState.currentScreen = .inbox
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.regular)
                } else {
                    Button(L10n.Onboarding.previous) { goBack() }
                        .buttonStyle(.bordered)
                        .controlSize(.regular)
                }

                Spacer()

                Button(action: {
                    if !isStructureReady {
                        if !validateAndCreateFolder() { return }
                    }
                    goNext()
                }) {
                    Text(L10n.Onboarding.next)
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
                Image(systemName: "folder")
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


    private func abbreviatedPath(_ path: String) -> String {
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        if path.hasPrefix(home) {
            return "~" + path.dropFirst(home.count) + "/"
        }
        return path + "/"
    }

    // MARK: - Step 3: Domain & Project (Combined)

    private var domainAndProjectStep: some View {
        VStack(spacing: 0) {
            stepHeader(
                title: L10n.Onboarding.domainProjectTitle,
                desc: L10n.Onboarding.domainProjectDesc
            )

            VStack(alignment: .leading, spacing: 10) {
                HStack(alignment: .top, spacing: 8) {
                    Image(systemName: "lightbulb.fill")
                        .font(.caption)
                        .foregroundColor(.blue)
                    Text(L10n.Onboarding.domainProjectHint)
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                .padding(10)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Color.blue.opacity(0.05))
                .overlay(
                    RoundedRectangle(cornerRadius: 6)
                        .stroke(Color.blue.opacity(0.15), lineWidth: 1)
                )
                .cornerRadius(6)

                HStack(spacing: 8) {
                    TextField(L10n.Onboarding.domainPlaceholder, text: $newAreaName)
                        .textFieldStyle(.roundedBorder)
                        .font(.subheadline)
                        .onSubmit { addAreaAndExpand() }

                    Button(action: addAreaAndExpand) {
                        Image(systemName: "plus")
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.regular)
                    .disabled(newAreaName.trimmingCharacters(in: .whitespaces).isEmpty)
                }

                ScrollView {
                    VStack(spacing: 6) {
                        ForEach(areas, id: \.self) { areaName in
                            areaCard(areaName)
                        }
                    }
                }
                .frame(maxHeight: 300)
            }
            .padding(.horizontal, 16)

            Spacer()

            if areas.isEmpty {
                Text(L10n.Onboarding.addDomainHint)
                    .font(.caption)
                    .foregroundColor(.orange)
                    .padding(.bottom, 8)
            } else if !allAreasHaveSummary {
                Text(L10n.Onboarding.addDomainSummaryHint)
                    .font(.caption)
                    .foregroundColor(.orange)
                    .padding(.bottom, 8)
            }

            HStack {
                if isReOnboarding {
                    Button(L10n.Onboarding.cancel) {
                        UserDefaults.standard.removeObject(forKey: AppState.DefaultsKey.onboardingStep)
                        appState.currentScreen = .inbox
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.regular)
                } else {
                    Button(L10n.Onboarding.previous) { goBack() }
                        .buttonStyle(.bordered)
                        .controlSize(.regular)
                }

                Spacer()

                Button(action: {
                    saveRegistry()
                    goNext()
                }) {
                    Text(L10n.Onboarding.next)
                        .frame(minWidth: 80)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.regular)
                .disabled(areas.isEmpty || !allAreasHaveSummary)
            }
            .padding(.horizontal, 32)
            .padding(.bottom, 20)
        }
        .padding(.horizontal)
        .onAppear {
            loadExistingAreas()
            loadExistingProjects()
        }
    }

    private func areaCard(_ areaName: String) -> some View {
        let isExpanded = expandedArea == areaName
        let areaProjects = projectsForArea(areaName)

        return VStack(spacing: 0) {
            // Header
            HStack(spacing: 8) {
                Image(systemName: isExpanded ? "chevron.down" : "chevron.right")
                    .font(.caption2)
                    .foregroundColor(.secondary)
                    .frame(width: 12)

                Image(systemName: "square.stack.3d.up.fill")
                    .font(.caption)
                    .foregroundColor(.green)

                Text(areaName)
                    .font(.subheadline)
                    .fontWeight(.medium)

                if !isExpanded {
                    Text(L10n.Onboarding.projectCount(areaProjects.count))
                        .font(.caption2)
                        .foregroundColor(.secondary)
                }

                Spacer()

                Button(action: { removeAreaWithProjects(areaName) }) {
                    Image(systemName: "xmark")
                        .font(.caption2)
                        .foregroundColor(.secondary)
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 8)
            .contentShape(Rectangle())
            .onTapGesture {
                withAnimation(.easeInOut(duration: 0.2)) {
                    expandedArea = isExpanded ? nil : areaName
                }
            }

            if isExpanded {
                VStack(alignment: .leading, spacing: 6) {
                    // Area summary (required)
                    TextField(L10n.Onboarding.areaSummaryPlaceholder, text: areaSummaryBinding(areaName))
                        .textFieldStyle(.roundedBorder)
                        .font(.caption)
                        .padding(.horizontal, 10)

                    let hasSummary = !(areaSummaries[areaName]?.trimmingCharacters(in: .whitespaces).isEmpty ?? true)

                    if hasSummary {
                        ForEach(areaProjects, id: \.self) { projectName in
                            HStack(spacing: 8) {
                                Image(systemName: "folder.fill")
                                    .font(.caption2)
                                    .foregroundColor(.blue)

                                Text(projectName)
                                    .font(.caption)

                                Spacer()

                                Button(action: { removeProject(projectName) }) {
                                    Image(systemName: "xmark")
                                        .font(.caption2)
                                        .foregroundColor(.secondary)
                                }
                                .buttonStyle(.plain)
                            }
                            .padding(.horizontal, 10)
                            .padding(.vertical, 4)
                        }

                        HStack(spacing: 6) {
                            TextField(L10n.Onboarding.projectName, text: $newProjectName)
                                .textFieldStyle(.roundedBorder)
                                .font(.caption)
                                .onSubmit { addProjectToArea(areaName) }

                            Button(action: { addProjectToArea(areaName) }) {
                                Image(systemName: "plus")
                            }
                            .buttonStyle(.bordered)
                            .controlSize(.small)
                            .disabled(newProjectName.trimmingCharacters(in: .whitespaces).isEmpty)
                        }
                        .padding(.horizontal, 10)
                    }
                }
                .padding(.bottom, 6)
                .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
        .background(Color.secondary.opacity(0.05))
        .cornerRadius(8)
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .strokeBorder(isExpanded ? Color.green.opacity(0.3) : Color.secondary.opacity(0.1), lineWidth: 1)
        )
    }

    // MARK: - Step 4: Provider + API Key (Combined)

    private var providerAndKeyStep: some View {
        let provider = appState.selectedProvider

        return VStack(spacing: 0) {
            stepHeader(
                title: L10n.Onboarding.aiConnectionTitle,
                desc: L10n.Onboarding.aiConnectionDesc
            )

            ScrollView {
                VStack(spacing: 14) {
                    // Provider selection
                    VStack(spacing: 8) {
                        providerCard(
                            provider: .claudeCLI,
                            badge: L10n.Onboarding.badgeSubscription,
                            badgeColor: .blue
                        )

                        providerCard(
                            provider: .codexCLI,
                            badge: L10n.Onboarding.badgeSubscription,
                            badgeColor: .blue
                        )

                        providerCard(
                            provider: .gemini,
                            badge: L10n.Onboarding.badgeFreeStart,
                            badgeColor: .green
                        )

                        providerCard(
                            provider: .claude,
                            badge: L10n.Onboarding.badgeApiPayment,
                            badgeColor: .orange
                        )
                    }

                    Divider()

                    if provider == .claudeCLI || provider == .codexCLI {
                        // CLI status section (no API key needed)
                        onboardingCLIStatus(for: provider)
                        .padding(12)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(Color.secondary.opacity(0.05))
                        .cornerRadius(8)
                    } else {
                        // API key input inline
                        VStack(alignment: .leading, spacing: 8) {
                            HStack(spacing: 6) {
                                Text(L10n.Onboarding.apiKeyLabel(provider.displayName))
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
                                        Text(L10n.Onboarding.getApiKey)
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
                                Button(L10n.Onboarding.save) {
                                    saveAPIKey(provider: provider)
                                }
                                .buttonStyle(.bordered)
                                .controlSize(.small)
                                .disabled(keyInput.isEmpty || keyInput == "••••••••")

                                if let msg = keySaveMessage {
                                    Text(msg)
                                        .font(.caption2)
                                        .foregroundColor(msg == L10n.Onboarding.keySaved ? .green : .orange)
                                }

                                Spacer()

                                if appState.hasAPIKey {
                                    Label(L10n.Onboarding.ready, systemImage: "checkmark.circle.fill")
                                        .font(.caption)
                                        .foregroundColor(.green)
                                }
                            }
                        }
                        .padding(12)
                        .background(Color.secondary.opacity(0.05))
                        .cornerRadius(8)
                    }
                }
                .padding(.horizontal, 24)
            }

            VStack(spacing: 6) {
                HStack {
                    Button(L10n.Onboarding.previous) { goBack() }
                        .buttonStyle(.bordered)
                        .controlSize(.regular)

                    Spacer()

                    Button(action: { goNext() }) {
                        Text(L10n.Onboarding.next)
                            .frame(minWidth: 80)
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.regular)
                }

                if !appState.hasAPIKey {
                    Button(action: { goNext() }) {
                        Text(L10n.Onboarding.skip)
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

    private func providerCard(provider: AIProvider, badge: String, badgeColor: Color) -> some View {
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

    @ViewBuilder
    private func onboardingCLIStatus(for provider: AIProvider) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            if provider == .claudeCLI {
                if ClaudeCLIClient.isAvailable() {
                    Label(L10n.Onboarding.cliInstalled, systemImage: "checkmark.circle.fill")
                        .font(.caption)
                        .foregroundColor(.green)
                    Text(L10n.Onboarding.cliPipeMode)
                        .font(.caption2)
                        .foregroundColor(.secondary)
                } else {
                    Label(L10n.Onboarding.cliNotFound, systemImage: "xmark.circle.fill")
                        .font(.caption)
                        .foregroundColor(.red)
                    Text(L10n.Onboarding.cliInstallHint)
                        .font(.caption2)
                        .foregroundColor(.secondary)
                }
            } else if provider == .codexCLI {
                if appState.hasCodexCLI {
                    Label(L10n.Onboarding.codexInstalled, systemImage: "checkmark.circle.fill")
                        .font(.caption)
                        .foregroundColor(.green)
                    Text(L10n.Onboarding.codexExecMode)
                        .font(.caption2)
                        .foregroundColor(.secondary)
                } else if appState.codexCLIInstalled {
                    Label(L10n.Onboarding.codexAuthRequired, systemImage: "exclamationmark.triangle.fill")
                        .font(.caption)
                        .foregroundColor(.orange)
                    Text(L10n.Onboarding.codexLoginHint)
                        .font(.caption2)
                        .foregroundColor(.secondary)
                } else {
                    Label(L10n.Onboarding.codexNotFound, systemImage: "xmark.circle.fill")
                        .font(.caption)
                        .foregroundColor(.red)
                    Text(L10n.Onboarding.codexInstallHint)
                        .font(.caption2)
                        .foregroundColor(.secondary)
                }
            }
        }
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
        .padding(.bottom, 20)
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

    /// Open NSOpenPanel to select vault folder.
    /// NSOpenPanel grants implicit file access via user selection, avoiding TCC permission dialogs.
    private func pickVaultFolder() {
        let panel = NSOpenPanel()
        panel.title = L10n.Onboarding.pickVaultTitle
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = false
        panel.canCreateDirectories = true
        panel.directoryURL = URL(fileURLWithPath: (appState.pkmRootPath as NSString).deletingLastPathComponent)

        guard panel.runModal() == .OK, let url = panel.url else { return }
        let resolved = url.resolvingSymlinksInPath()
        appState.pkmRootPath = resolved.path
        appState.saveVaultBookmark(url: resolved)
    }

    private func validateAndCreateFolder() -> Bool {
        let path = appState.pkmRootPath
        let fm = FileManager.default

        // Check if parent directory is writable
        let parent = (path as NSString).deletingLastPathComponent
        if fm.fileExists(atPath: parent) && !fm.isWritableFile(atPath: parent) {
            folderError = L10n.Onboarding.noWritePermission
            showFolderError = true
            return false
        }

        let pathManager = PKMPathManager(root: path)
        do {
            try pathManager.initializeStructure()
            isStructureReady = pathManager.isInitialized()
            appState.saveVaultBookmark(url: URL(fileURLWithPath: path))
            return true
        } catch {
            folderError = L10n.Onboarding.folderCreationError(error.localizedDescription)
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

        // Restore area/summary mappings from registry
        if let registry = ProjectRegistry.load(pkmRoot: appState.pkmRootPath) {
            for (areaName, areaInfo) in registry.areas {
                if areaSummaries[areaName] == nil && !areaInfo.summary.isEmpty {
                    areaSummaries[areaName] = areaInfo.summary
                }
                for (projectName, projectInfo) in areaInfo.projects where projects.contains(projectName) {
                    if projectEntries[projectName] == nil {
                        projectEntries[projectName] = ProjectEntry(area: areaName, summary: projectInfo.summary)
                    }
                }
            }
        }
    }

    private func addAreaAndExpand() {
        let pathManager = PKMPathManager(root: appState.pkmRootPath)
        let raw = newAreaName.trimmingCharacters(in: .whitespaces)
        let name = pathManager.sanitizeFolderName(raw)
        guard !name.isEmpty, !areas.contains(name) else { return }

        let areaDir = (pathManager.areaPath as NSString).appendingPathComponent(name)
        guard pathManager.isPathSafe(areaDir) else { return }

        do {
            try FileManager.default.createDirectory(atPath: areaDir, withIntermediateDirectories: true)
            areas.insert(name, at: 0)
            newAreaName = ""
            withAnimation(.easeInOut(duration: 0.2)) {
                expandedArea = name
            }
        } catch {
            NSLog("[OnboardingView] Area 생성 실패: %@", error.localizedDescription)
            newAreaName = ""
        }
    }

    private func addProjectToArea(_ areaName: String) {
        let pathManager = PKMPathManager(root: appState.pkmRootPath)
        let raw = newProjectName.trimmingCharacters(in: .whitespaces)
        let name = pathManager.sanitizeFolderName(raw)
        guard !name.isEmpty, !projects.contains(name) else { return }

        let projectDir = (pathManager.projectsPath as NSString).appendingPathComponent(name)
        guard pathManager.isPathSafe(projectDir) else { return }

        do {
            try FileManager.default.createDirectory(atPath: projectDir, withIntermediateDirectories: true)
            projects.append(name)
            projectEntries[name] = ProjectEntry(area: areaName, summary: "")
            newProjectName = ""
        } catch {
            NSLog("[OnboardingView] 프로젝트 생성 실패: %@", error.localizedDescription)
            newProjectName = ""
        }
    }

    private func removeProject(_ name: String) {
        let pathManager = PKMPathManager(root: appState.pkmRootPath)
        let projectDir = (pathManager.projectsPath as NSString).appendingPathComponent(name)
        try? FileManager.default.trashItem(at: URL(fileURLWithPath: projectDir), resultingItemURL: nil)
        projects.removeAll { $0 == name }
        projectEntries.removeValue(forKey: name)
    }

    private func removeAreaWithProjects(_ name: String) {
        let pathManager = PKMPathManager(root: appState.pkmRootPath)
        let areaDir = (pathManager.areaPath as NSString).appendingPathComponent(name)
        try? FileManager.default.trashItem(at: URL(fileURLWithPath: areaDir), resultingItemURL: nil)

        let associatedProjects = projectsForArea(name)
        for project in associatedProjects {
            removeProject(project)
        }

        areas.removeAll { $0 == name }
        areaSummaries.removeValue(forKey: name)
        if expandedArea == name { expandedArea = nil }
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

    private func projectsForArea(_ areaName: String) -> [String] {
        projects.filter { projectEntries[$0]?.area == areaName }
    }

    private var allAreasHaveSummary: Bool {
        areas.allSatisfy { !(areaSummaries[$0]?.trimmingCharacters(in: .whitespaces).isEmpty ?? true) }
    }

    private func areaSummaryBinding(_ areaName: String) -> Binding<String> {
        Binding(
            get: { areaSummaries[areaName] ?? "" },
            set: { areaSummaries[areaName] = $0 }
        )
    }

    private func saveRegistry() {
        var registryAreas: [String: ProjectRegistry.AreaInfo] = [:]

        for areaName in areas {
            var projectInfos: [String: ProjectRegistry.ProjectInfo] = [:]
            for projectName in projectsForArea(areaName) {
                let summary = projectEntries[projectName]?.summary ?? ""
                projectInfos[projectName] = ProjectRegistry.ProjectInfo(summary: summary)
            }
            let areaSummary = areaSummaries[areaName] ?? ""
            registryAreas[areaName] = ProjectRegistry.AreaInfo(summary: areaSummary, projects: projectInfos)
        }

        if !registryAreas.isEmpty {
            ProjectRegistry.save(areas: registryAreas, pkmRoot: appState.pkmRootPath)
        } else {
            NSLog("[OnboardingView] Registry 저장 스킵: 데이터 없음")
        }
    }

    private func saveAPIKey(provider: AIProvider) {
        if keyInput.hasPrefix(provider.keyPrefix) {
            let saved = provider.saveAPIKey(keyInput)
            keySaveMessage = saved ? L10n.Onboarding.keySaved : L10n.Onboarding.keySaveFailed
            appState.updateAPIKeyStatus()
        } else {
            keySaveMessage = L10n.Onboarding.keyFormatHint(provider.keyPlaceholder)
        }
    }

    // MARK: - Step 5: Quick Start Guide

    private var isReOnboarding: Bool {
        UserDefaults.standard.bool(forKey: AppState.DefaultsKey.onboardingCompleted)
    }

    private var trialStep: some View {
        VStack(spacing: 0) {
            stepHeader(
                title: appState.hasAPIKey
                    ? (isReOnboarding ? L10n.Onboarding.vaultSetupComplete : L10n.Onboarding.allReady)
                    : L10n.Onboarding.almostDone,
                desc: appState.hasAPIKey
                    ? (isReOnboarding
                        ? L10n.Onboarding.vaultReadyDesc
                        : L10n.Onboarding.inboxReadyDesc)
                    : L10n.Onboarding.noApiKeyDesc
            )

            Text(appState.hasAPIKey ? "·‿·" : "·_·")
                .font(.system(size: 36, design: .monospaced))
                .padding(.bottom, 16)

            VStack(alignment: .leading, spacing: 8) {
                if appState.hasAPIKey {
                    guideRow(icon: "1.circle.fill", text: L10n.Onboarding.guideClickMenubar)
                    guideRow(icon: "2.circle.fill", text: L10n.Onboarding.guideDragOrPaste)
                    guideRow(icon: "3.circle.fill", text: L10n.Onboarding.guideOrganize)
                } else {
                    guideRow(
                        icon: "terminal",
                        text: appState.selectedProvider == .codexCLI
                            ? L10n.Onboarding.guideCodexConnect
                            : L10n.Onboarding.guideCliConnect
                    )
                    guideRow(icon: "gearshape", text: L10n.Onboarding.guideAddApiKey)
                }
            }
            .padding(14)
            .background(Color.secondary.opacity(0.05))
            .cornerRadius(8)
            .padding(.horizontal, 24)

            Spacer()

            HStack {
                Button(L10n.Onboarding.previous) { goBack() }
                    .buttonStyle(.bordered)
                    .controlSize(.regular)

                Spacer()

                Button(action: completeOnboarding) {
                    Text(L10n.Onboarding.getStarted)
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
        UserDefaults.standard.set(true, forKey: AppState.DefaultsKey.onboardingCompleted)
        UserDefaults.standard.removeObject(forKey: AppState.DefaultsKey.onboardingStep)
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
