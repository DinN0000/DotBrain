import SwiftUI

struct VaultManageView: View {
    @EnvironmentObject var appState: AppState

    @State private var isAuditing = false
    @State private var auditReport: AuditReport?
    @State private var isRepairing = false
    @State private var repairResult: RepairResult?

    @State private var isEnriching = false
    @State private var enrichCount: Int?

    @State private var isMOCRegenerating = false
    @State private var mocDone = false

    var body: some View {
        VStack(spacing: 0) {
            BreadcrumbView(current: .vaultManage)

            Divider()

            ScrollView {
                VStack(spacing: 12) {
                    // MARK: 1. Audit
                    DashboardActionButton(
                        icon: "checkmark.shield",
                        title: "오류 검사",
                        subtitle: "깨진 링크 \u{b7} 누락 태그 \u{b7} 분류 오류 탐지",
                        isDisabled: isAuditing
                    ) {
                        runAudit()
                    }

                    if isAuditing {
                        InlineProgress(message: "볼트 검사 중...")
                    }

                    if let report = auditReport {
                        VStack(spacing: 4) {
                            AuditRow(icon: "link", label: "깨진 링크", count: report.brokenLinks.count)
                            AuditRow(icon: "doc.badge.ellipsis", label: "프론트매터 누락", count: report.missingFrontmatter.count)
                            AuditRow(icon: "tag", label: "태그 없음", count: report.untaggedFiles.count)
                            AuditRow(icon: "folder.badge.questionmark", label: "PARA 누락", count: report.missingPARA.count)
                        }
                        .padding(.horizontal, 12)
                        .padding(.vertical, 8)
                        .background(Color.primary.opacity(0.03))
                        .cornerRadius(8)

                        if report.totalIssues > 0 && repairResult == nil {
                            Button(action: { runRepair(report: report) }) {
                                HStack(spacing: 6) {
                                    Image(systemName: "wand.and.stars")
                                        .font(.caption)
                                    Text("자동 복구")
                                        .font(.caption)
                                        .fontWeight(.medium)
                                }
                            }
                            .buttonStyle(.borderedProminent)
                            .controlSize(.small)
                            .disabled(isRepairing)
                        }

                        if isRepairing {
                            InlineProgress(message: "복구 중...")
                        }

                        if let repair = repairResult {
                            VStack(spacing: 4) {
                                if repair.linksFixed > 0 {
                                    AuditRepairRow(icon: "link.badge.plus", label: "링크 \(repair.linksFixed)건 수정")
                                }
                                if repair.frontmatterInjected > 0 {
                                    AuditRepairRow(icon: "doc.badge.plus", label: "프론트매터 \(repair.frontmatterInjected)건 주입")
                                }
                                if repair.paraFixed > 0 {
                                    AuditRepairRow(icon: "folder.badge.plus", label: "PARA \(repair.paraFixed)건 수정")
                                }
                                if repair.linksFixed == 0 && repair.frontmatterInjected == 0 && repair.paraFixed == 0 {
                                    AuditRepairRow(icon: "checkmark.circle", label: "자동 복구 가능한 항목 없음")
                                }
                            }
                            .padding(.horizontal, 12)
                            .padding(.vertical, 8)
                            .background(Color.green.opacity(0.06))
                            .cornerRadius(8)
                        }
                    }

                    Divider().padding(.vertical, 4)

                    // MARK: 2. Enrich
                    DashboardActionButton(
                        icon: "text.badge.star",
                        title: "태그 \u{b7} 요약 보완",
                        subtitle: "비어있는 메타데이터를 AI로 보완",
                        isDisabled: isEnriching
                    ) {
                        runEnrich()
                    }

                    if isEnriching {
                        InlineProgress(message: "메타데이터 보완 중...")
                    }

                    if let count = enrichCount {
                        InlineResult(
                            icon: "checkmark.circle.fill",
                            message: "\(count)개 노트 메타데이터 보완 완료"
                        ) {
                            enrichCount = nil
                        }
                    }

                    Divider().padding(.vertical, 4)

                    // MARK: 3. MOC Regenerate
                    DashboardActionButton(
                        icon: "doc.text.magnifyingglass",
                        title: "폴더 요약 업데이트",
                        subtitle: "각 폴더의 인덱스 노트를 최신 내용으로 재생성",
                        isDisabled: isMOCRegenerating
                    ) {
                        runMOCRegenerate()
                    }

                    if isMOCRegenerating {
                        InlineProgress(message: "폴더 요약 갱신 중...")
                    }

                    if mocDone {
                        InlineResult(
                            icon: "checkmark.circle.fill",
                            message: "모든 폴더 요약 갱신 완료"
                        ) {
                            mocDone = false
                        }
                    }

                    Divider().padding(.vertical, 4)

                    // MARK: 4. Vault Reorganize (navigate)
                    DashboardActionButton(
                        icon: "arrow.triangle.2.circlepath",
                        title: "전체 재정리",
                        subtitle: "AI가 잘못된 위치의 파일을 찾아 이동 제안"
                    ) {
                        appState.currentScreen = .vaultReorganize
                    }
                }
                .padding()
            }
        }
    }

    // MARK: - Actions

    private func runAudit() {
        auditReport = nil
        repairResult = nil
        isAuditing = true
        let root = appState.pkmRootPath
        Task.detached {
            let auditor = VaultAuditor(pkmRoot: root)
            let report = auditor.audit()
            await MainActor.run {
                auditReport = report
                isAuditing = false
            }
        }
    }

    private func runRepair(report: AuditReport) {
        isRepairing = true
        let root = appState.pkmRootPath
        Task.detached {
            let auditor = VaultAuditor(pkmRoot: root)
            let result = auditor.repair(report: report)
            await MainActor.run {
                repairResult = result
                isRepairing = false
            }
        }
    }

    private func runEnrich() {
        enrichCount = nil
        isEnriching = true
        let root = appState.pkmRootPath
        Task.detached {
            let enricher = NoteEnricher(pkmRoot: root)
            let pm = PKMPathManager(root: root)
            let fm = FileManager.default
            var count = 0
            for basePath in [pm.projectsPath, pm.areaPath, pm.resourcePath] {
                guard let folders = try? fm.contentsOfDirectory(atPath: basePath) else { continue }
                for folder in folders where !folder.hasPrefix(".") && !folder.hasPrefix("_") {
                    let folderPath = (basePath as NSString).appendingPathComponent(folder)
                    let results = await enricher.enrichFolder(at: folderPath)
                    count += results.count
                }
            }
            let finalCount = count
            await MainActor.run {
                enrichCount = finalCount
                isEnriching = false
            }
        }
    }

    private func runMOCRegenerate() {
        mocDone = false
        isMOCRegenerating = true
        let root = appState.pkmRootPath
        Task.detached {
            let generator = MOCGenerator(pkmRoot: root)
            await generator.regenerateAll()
            await MainActor.run {
                mocDone = true
                isMOCRegenerating = false
            }
        }
    }
}
