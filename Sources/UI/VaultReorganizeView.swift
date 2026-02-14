import SwiftUI

struct VaultReorganizeView: View {
    @EnvironmentObject var appState: AppState
    @State private var scope: VaultReorganizer.Scope = .all
    @State private var phase: Phase = .selectScope
    @State private var scanResult: VaultReorganizer.ScanResult?
    @State private var analyses: [VaultReorganizer.FileAnalysis] = []
    @State private var results: [ProcessedFileResult] = []
    @State private var isScanning = false
    @State private var isExecuting = false
    @State private var progress: Double = 0
    @State private var progressStatus: String = ""

    enum Phase {
        case selectScope
        case scanning
        case reviewPlan
        case executing
        case done
    }

    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                Button(action: goBack) {
                    Image(systemName: "chevron.left")
                }
                .buttonStyle(.plain)

                Text("전체 재정리")
                    .font(.headline)

                Spacer()

                if phase == .reviewPlan {
                    Text("\(selectedCount)개 선택")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }
            .padding()

            Divider()

            switch phase {
            case .selectScope:
                scopeSelectionView
            case .scanning:
                scanningView
            case .reviewPlan:
                planReviewView
            case .executing:
                executingView
            case .done:
                resultsView
            }
        }
    }

    // MARK: - Computed Properties

    private var selectedCount: Int {
        analyses.filter { $0.isSelected && $0.needsMove }.count
    }

    private var movableCount: Int {
        analyses.filter(\.needsMove).count
    }

    private var allSelected: Bool {
        let movable = analyses.filter(\.needsMove)
        return !movable.isEmpty && movable.allSatisfy(\.isSelected)
    }

    // MARK: - Step 1: Scope Selection

    private var scopeSelectionView: some View {
        ScrollView {
            VStack(spacing: 12) {
                Text("어떤 범위를 스캔할까요?")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                    .padding(.top, 12)

                // Full vault button
                Button(action: {
                    scope = .all
                    startScan()
                }) {
                    HStack {
                        Image(systemName: "tray.2.fill")
                        Text("전체 볼트")
                        Spacer()
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 4)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.regular)

                // Per-category buttons
                ForEach(PARACategory.allCases, id: \.self) { category in
                    Button(action: {
                        scope = .category(category)
                        startScan()
                    }) {
                        HStack(spacing: 6) {
                            Image(systemName: category.icon)
                            Text(category.displayName)
                            Spacer()
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 4)
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.regular)
                }
            }
            .padding(.horizontal)
            .padding(.vertical, 8)
        }
    }

    // MARK: - Step 2: Scanning

    private var scanningView: some View {
        VStack(spacing: 16) {
            Spacer()

            Text("AI 스캔 중")
                .font(.headline)

            ProgressView()
                .controlSize(.large)

            VStack(spacing: 6) {
                ProgressView(value: progress)
                    .progressViewStyle(.linear)
                    .padding(.horizontal, 40)

                HStack {
                    Spacer()
                    Text("\(Int(progress * 100))%")
                        .font(.subheadline)
                        .fontWeight(.medium)
                        .monospacedDigit()
                }
                .padding(.horizontal, 40)
            }

            Text(progressStatus)
                .font(.caption)
                .foregroundColor(.secondary)
                .lineLimit(2)
                .multilineTextAlignment(.center)
                .padding(.horizontal)

            Spacer()
        }
        .padding()
    }

    // MARK: - Step 3: Plan Review

    private var planReviewView: some View {
        VStack(spacing: 0) {
            // Summary bar
            VStack(alignment: .leading, spacing: 4) {
                Label(
                    "\(movableCount)개 파일 이동 필요",
                    systemImage: "arrow.triangle.2.circlepath"
                )
                .font(.caption)
                .fontWeight(.medium)
                .foregroundColor(.accentColor)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal)
            .padding(.vertical, 8)

            Divider()

            // File list grouped by current category
            ScrollView {
                LazyVStack(spacing: 0) {
                    ForEach(PARACategory.allCases, id: \.self) { category in
                        let categoryFiles = analyses.filter {
                            $0.needsMove && $0.currentCategory == category
                        }
                        if !categoryFiles.isEmpty {
                            planCategorySection(category: category, files: categoryFiles)
                        }
                    }

                    // Files that don't need moving
                    let unchangedCount = analyses.filter { !$0.needsMove }.count
                    if unchangedCount > 0 {
                        HStack(spacing: 4) {
                            Image(systemName: "checkmark.circle")
                                .font(.caption2)
                                .foregroundColor(.green)
                            Text("\(unchangedCount)개 파일은 현재 위치가 적절합니다")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                        .padding(.vertical, 8)
                        .padding(.horizontal)
                    }
                }
                .padding(.horizontal)
                .padding(.vertical, 8)
            }

            Divider()

            // Bottom action bar
            HStack {
                Toggle(isOn: Binding(
                    get: { allSelected },
                    set: { newValue in toggleAll(newValue) }
                )) {
                    Text("전체")
                        .font(.caption)
                }
                .toggleStyle(.checkbox)

                Spacer()

                Button(action: executePlan) {
                    HStack {
                        Image(systemName: "sparkles")
                        Text("실행")
                    }
                    .padding(.vertical, 4)
                    .padding(.horizontal, 12)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.regular)
                .disabled(selectedCount == 0)
            }
            .padding()
        }
    }

    @ViewBuilder
    private func planCategorySection(
        category: PARACategory,
        files: [VaultReorganizer.FileAnalysis]
    ) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            // Category header
            HStack(spacing: 4) {
                Image(systemName: category.icon)
                    .font(.caption)
                    .foregroundColor(.secondary)
                Text(category.displayName)
                    .font(.caption)
                    .fontWeight(.semibold)
                    .foregroundColor(.secondary)
                Text("(\(files.count))")
                    .font(.caption2)
                    .foregroundColor(.secondary)
            }
            .padding(.vertical, 6)

            ForEach(files.indices, id: \.self) { idx in
                if let analysisIndex = analyses.firstIndex(where: {
                    $0.fileName == files[idx].fileName
                        && $0.currentCategory == files[idx].currentCategory
                        && $0.currentFolder == files[idx].currentFolder
                }) {
                    PlanFileRow(analysis: $analyses[analysisIndex])
                }
            }
        }
    }

    // MARK: - Step 4: Executing

    private var executingView: some View {
        VStack(spacing: 16) {
            Spacer()

            Text("재정리 실행 중")
                .font(.headline)

            ProgressView()
                .controlSize(.large)

            VStack(spacing: 6) {
                ProgressView(value: progress)
                    .progressViewStyle(.linear)
                    .padding(.horizontal, 40)

                HStack {
                    Spacer()
                    Text("\(Int(progress * 100))%")
                        .font(.subheadline)
                        .fontWeight(.medium)
                        .monospacedDigit()
                }
                .padding(.horizontal, 40)
            }

            Text(progressStatus)
                .font(.caption)
                .foregroundColor(.secondary)
                .lineLimit(2)
                .multilineTextAlignment(.center)
                .padding(.horizontal)

            Spacer()
        }
        .padding()
    }

    // MARK: - Step 5: Results

    private var resultsView: some View {
        VStack(spacing: 0) {
            ScrollView {
                LazyVStack(spacing: 2) {
                    // Summary card
                    resultsSummaryCard

                    ForEach(results) { result in
                        ResultRow(result: result)
                    }
                }
                .padding(.horizontal)
                .padding(.vertical, 8)
            }

            Divider()

            HStack {
                HoverTextButton(label: "돌아가기") {
                    goBack()
                }
                Spacer()
            }
            .padding()
        }
    }

    private var resultsSummaryCard: some View {
        let successCount = results.filter(\.isSuccess).count
        let errorCount = results.filter(\.isError).count

        return Group {
            if successCount > 0 || errorCount > 0 {
                VStack(alignment: .leading, spacing: 6) {
                    Label(
                        "\(successCount)개 파일 재정리 완료",
                        systemImage: "checkmark.circle"
                    )
                    .font(.caption)
                    .fontWeight(.medium)
                    .foregroundColor(.green)

                    if errorCount > 0 {
                        HStack(spacing: 2) {
                            Image(systemName: "xmark.circle")
                                .font(.caption2)
                                .foregroundColor(.red)
                            Text("\(errorCount) 오류")
                                .font(.caption2)
                                .foregroundColor(.secondary)
                        }
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(10)
                .background(
                    RoundedRectangle(cornerRadius: 8)
                        .fill(Color.green.opacity(0.08))
                )
                .padding(.bottom, 6)
            }
        }
    }

    // MARK: - Actions

    private func startScan() {
        phase = .scanning
        isScanning = true
        progress = 0
        progressStatus = "스캔 준비 중..."

        let root = appState.pkmRootPath
        let currentScope = scope

        Task {
            let reorganizer = VaultReorganizer(
                pkmRoot: root,
                scope: currentScope,
                onProgress: { value, status in
                    Task { @MainActor in
                        progress = value
                        progressStatus = status
                    }
                }
            )

            do {
                let result = try await reorganizer.scan()

                await MainActor.run {
                    scanResult = result
                    analyses = result.files
                    isScanning = false

                    if analyses.contains(where: \.needsMove) {
                        phase = .reviewPlan
                    } else {
                        results = []
                        phase = .done
                    }
                }
            } catch {
                await MainActor.run {
                    isScanning = false
                    progressStatus = "오류: \(error.localizedDescription)"
                    phase = .selectScope
                }
            }
        }
    }

    private func executePlan() {
        let selected = analyses.filter { $0.isSelected && $0.needsMove }
        guard !selected.isEmpty else { return }

        phase = .executing
        isExecuting = true
        progress = 0
        progressStatus = "실행 준비 중..."

        let root = appState.pkmRootPath

        Task {
            let reorganizer = VaultReorganizer(
                pkmRoot: root,
                scope: scope,
                onProgress: { value, status in
                    Task { @MainActor in
                        progress = value
                        progressStatus = status
                    }
                }
            )

            do {
                let executionResults = try await reorganizer.execute(plan: selected)

                await MainActor.run {
                    results = executionResults
                    isExecuting = false
                    phase = .done
                }
            } catch {
                await MainActor.run {
                    isExecuting = false
                    progressStatus = "오류: \(error.localizedDescription)"
                    phase = .done
                }
            }
        }
    }

    private func toggleAll(_ selected: Bool) {
        for i in analyses.indices where analyses[i].needsMove {
            analyses[i].isSelected = selected
        }
    }

    private func goBack() {
        switch phase {
        case .reviewPlan:
            phase = .selectScope
            scanResult = nil
            analyses = []
        case .done:
            phase = .selectScope
            scanResult = nil
            analyses = []
            results = []
        default:
            appState.currentScreen = .inbox
        }
    }
}

// MARK: - Plan File Row

private struct PlanFileRow: View {
    @Binding var analysis: VaultReorganizer.FileAnalysis
    @State private var isHovered = false

    var body: some View {
        HStack(spacing: 8) {
            Toggle(isOn: $analysis.isSelected) {
                EmptyView()
            }
            .toggleStyle(.checkbox)
            .labelsHidden()

            VStack(alignment: .leading, spacing: 2) {
                Text(analysis.fileName)
                    .font(.system(.body, design: .monospaced))
                    .lineLimit(1)

                HStack(spacing: 4) {
                    Text(analysis.currentFolder)
                        .font(.caption)
                        .foregroundColor(.secondary)

                    Image(systemName: "arrow.right")
                        .font(.caption2)
                        .foregroundColor(.purple)

                    Image(systemName: analysis.recommended.para.icon)
                        .font(.caption2)
                    Text(analysis.recommended.targetFolder)
                        .font(.caption)
                        .foregroundColor(.purple)
                }
            }

            Spacer()
        }
        .padding(.vertical, 5)
        .padding(.horizontal, 8)
        .background(
            RoundedRectangle(cornerRadius: 6)
                .fill(isHovered ? Color.primary.opacity(0.04) : Color.clear)
        )
        .animation(.easeOut(duration: 0.12), value: isHovered)
        .onHover { isHovered = $0 }
    }
}
