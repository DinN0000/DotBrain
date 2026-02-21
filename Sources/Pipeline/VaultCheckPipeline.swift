import Foundation

/// 5-phase vault check: Audit -> Repair -> Enrich -> Index -> SemanticLink
struct VaultCheckPipeline {
    let pkmRoot: String

    struct Progress {
        let phase: String
        let fraction: Double
    }

    /// Run the full vault check pipeline, returning a snapshot of results.
    func run(
        onProgress: @escaping @Sendable (Progress) -> Void
    ) async -> VaultCheckResult {
        var repairCount = 0
        var enrichCount = 0

        StatisticsService.recordActivity(
            fileName: "볼트 점검",
            category: "system",
            action: "started",
            detail: "오류 검사 · 메타데이터 보완 · 인덱스 갱신"
        )

        // Load content hash cache for incremental processing
        let cache = ContentHashCache(pkmRoot: pkmRoot)
        await cache.load()

        // Phase 1: Audit (0% -> 10%)
        onProgress(Progress(phase: "오류 검사 중...", fraction: 0.02))
        let auditor = VaultAuditor(pkmRoot: pkmRoot)
        let report = auditor.audit()
        if Task.isCancelled { return .empty }
        onProgress(Progress(phase: "오류 검사 중...", fraction: 0.10))

        // Phase 2: Repair (10% -> 20%)
        var repairedFiles: [String] = []
        if report.totalIssues > 0 {
            onProgress(Progress(phase: "자동 복구 중...", fraction: 0.12))
            let repair = auditor.repair(report: report)
            repairCount = repair.linksFixed + repair.frontmatterInjected + repair.paraFixed

            repairedFiles = Self.collectRepairedFiles(from: report)
            await cache.updateHashes(repairedFiles)
        }
        if Task.isCancelled { return .empty }
        onProgress(Progress(phase: "자동 복구 중...", fraction: 0.20))

        // Check all .md files for changes (single batch actor call)
        onProgress(Progress(phase: "변경 파일 확인 중...", fraction: 0.20))
        let pm = PKMPathManager(root: pkmRoot)
        let allMdFiles = Self.collectAllMdFiles(pm: pm)
        let fileStatuses = await cache.checkFiles(allMdFiles)
        let changedFiles = Set(fileStatuses.filter { $0.value != .unchanged }.map { $0.key })

        NSLog("[VaultCheck] %d/%d files changed", changedFiles.count, allMdFiles.count)

        // Phase 3: Enrich (changed files only, skip archive) (25% -> 60%)
        onProgress(Progress(phase: "메타데이터 보완 중...", fraction: 0.25))
        let enricher = NoteEnricher(pkmRoot: pkmRoot)
        let filesToEnrich = Array(changedFiles.filter { !$0.contains("/4_Archive/") })
        var enrichedFiles: [String] = []
        let enrichTotal = filesToEnrich.count
        var enrichDone = 0

        await withTaskGroup(of: EnrichResult?.self) { group in
            var active = 0
            var index = 0

            while index < filesToEnrich.count || !group.isEmpty {
                while active < 3 && index < filesToEnrich.count {
                    let path = filesToEnrich[index]
                    index += 1
                    active += 1
                    group.addTask {
                        do {
                            return try await enricher.enrichNote(at: path)
                        } catch {
                            NSLog("[NoteEnricher] enrichNote 실패 %@: %@",
                                  (path as NSString).lastPathComponent, error.localizedDescription)
                            return nil
                        }
                    }
                }
                if let result = await group.next() {
                    active -= 1
                    enrichDone += 1
                    if let r = result, r.fieldsUpdated > 0 {
                        enrichedFiles.append(r.filePath)
                        enrichCount += 1
                    }
                    let enrichProgress = enrichTotal > 0
                        ? 0.25 + Double(enrichDone) / Double(enrichTotal) * 0.35
                        : 0.60
                    onProgress(Progress(phase: "메타데이터 보완 중...", fraction: enrichProgress))
                }
            }
        }
        if !enrichedFiles.isEmpty {
            await cache.updateHashes(enrichedFiles)
        }
        if Task.isCancelled { return .empty }

        // Phase 4: Note Index (dirty folders only) (60% -> 70%)
        onProgress(Progress(phase: "노트 인덱스 갱신 중...", fraction: 0.60))
        let allChangedFiles = changedFiles.union(Set(enrichedFiles))
        let dirtyFolders = Set(allChangedFiles.map {
            ($0 as NSString).deletingLastPathComponent
        })
        let indexGenerator = NoteIndexGenerator(pkmRoot: pkmRoot)
        await indexGenerator.updateForFolders(dirtyFolders)
        if Task.isCancelled { return .empty }

        // Phase 5: Semantic Link (changed notes only) (70% -> 95%)
        onProgress(Progress(phase: "노트 간 시맨틱 연결 중...", fraction: 0.70))
        let linker = SemanticLinker(pkmRoot: pkmRoot)
        let linkResult = await linker.linkAll(changedFiles: allChangedFiles) { progress, status in
            onProgress(Progress(phase: status, fraction: 0.70 + progress * 0.25))
        }

        // Update hashes for all changed files (including index/SemanticLinker modifications) and save
        await cache.updateHashes(Array(allChangedFiles))
        await cache.save()

        StatisticsService.recordActivity(
            fileName: "볼트 점검",
            category: "system",
            action: "completed",
            detail: "\(report.totalIssues)건 발견, \(repairCount)건 복구, \(enrichCount)개 보완, \(linkResult.linksCreated)개 링크"
        )

        return VaultCheckResult(
            brokenLinks: report.brokenLinks.count,
            missingFrontmatter: report.missingFrontmatter.count,
            missingPARA: report.missingPARA.count,
            untaggedFiles: report.untaggedFiles.count,
            repairCount: repairCount,
            enrichCount: enrichCount,
            mocUpdated: true,
            linksCreated: linkResult.linksCreated
        )
    }

    // MARK: - Helpers

    /// Collect files that were actually modified by repair
    private static func collectRepairedFiles(from report: AuditReport) -> [String] {
        var files = Set<String>()
        for link in report.brokenLinks where link.suggestion != nil {
            files.insert(link.filePath)
        }
        for path in report.missingFrontmatter {
            files.insert(path)
        }
        for path in report.missingPARA {
            files.insert(path)
        }
        return Array(files)
    }

    /// Collect all .md files across PARA folders
    private static func collectAllMdFiles(pm: PKMPathManager) -> [String] {
        let fm = FileManager.default
        var results: [String] = []
        for basePath in [pm.projectsPath, pm.areaPath, pm.resourcePath, pm.archivePath] {
            guard let enumerator = fm.enumerator(atPath: basePath) else { continue }
            while let element = enumerator.nextObject() as? String {
                let name = (element as NSString).lastPathComponent
                if name.hasPrefix(".") || name.hasPrefix("_") {
                    let full = (basePath as NSString).appendingPathComponent(element)
                    var isDir: ObjCBool = false
                    if fm.fileExists(atPath: full, isDirectory: &isDir), isDir.boolValue {
                        enumerator.skipDescendants()
                    }
                    continue
                }
                guard name.hasSuffix(".md") else { continue }
                let fullPath = (basePath as NSString).appendingPathComponent(element)
                var isDir: ObjCBool = false
                if fm.fileExists(atPath: fullPath, isDirectory: &isDir), !isDir.boolValue {
                    results.append(fullPath)
                }
            }
        }
        return results
    }
}
