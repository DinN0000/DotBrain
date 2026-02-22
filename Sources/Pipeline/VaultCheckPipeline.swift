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

        // Prune stale folder relations (folders that no longer exist)
        let existingFolders = Self.collectExistingFolders(pm: PKMPathManager(root: pkmRoot))
        FolderRelationStore(pkmRoot: pkmRoot).pruneStale(existingFolders: existingFolders)

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

        // Phase 2.5: Create missing index notes for folders that lack them
        let createdIndexNotes = Self.createMissingIndexNotes(pkmRoot: pkmRoot)
        repairCount += createdIndexNotes.count
        if !createdIndexNotes.isEmpty {
            await cache.updateHashes(createdIndexNotes)
        }

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

        // Phase 4.5: Link State Diff — detect user link removals BEFORE writing new links
        onProgress(Progress(phase: "링크 변경 감지 중...", fraction: 0.70))
        let linker = SemanticLinker(pkmRoot: pkmRoot)
        let linkDetector = LinkStateDetector(pkmRoot: pkmRoot)
        let allNotesForSnapshot = linker.buildNoteIndex()
        let previousSnapshot = linkDetector.loadSnapshot()
        let currentSnapshot = linkDetector.buildCurrentSnapshot(allNotes: allNotesForSnapshot)

        if let prev = previousSnapshot {
            let noteInfoMap = Dictionary(uniqueKeysWithValues: allNotesForSnapshot.map { ($0.name, $0) })
            let removals = linkDetector.detectRemovals(
                previous: prev, current: currentSnapshot, noteInfoMap: noteInfoMap
            )
            if !removals.isEmpty {
                let feedbackStore = LinkFeedbackStore(pkmRoot: pkmRoot)
                for removal in removals {
                    feedbackStore.recordRemoval(
                        sourceNote: removal.sourceNote,
                        targetNote: removal.targetNote,
                        sourceFolder: removal.sourceFolder,
                        targetFolder: removal.targetFolder
                    )
                }
                NSLog("[VaultCheck] %d link removals detected", removals.count)
            }
        }
        if Task.isCancelled { return .empty }

        // Phase 5: Semantic Link (changed notes only) (72% -> 95%)
        // Reuse allNotesForSnapshot — file paths/names unchanged, avoids redundant vault scan
        onProgress(Progress(phase: "노트 간 시맨틱 연결 중...", fraction: 0.72))
        let linkResult = await linker.linkAll(changedFiles: allChangedFiles, prebuiltIndex: allNotesForSnapshot) { progress, status in
            onProgress(Progress(phase: status, fraction: 0.72 + progress * 0.23))
        }

        // Save post-link snapshot (reads file content fresh — captures newly written links)
        let finalSnapshot = linkDetector.buildCurrentSnapshot(allNotes: allNotesForSnapshot)
        linkDetector.saveSnapshot(finalSnapshot)

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
            mocUpdated: !dirtyFolders.isEmpty,
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

    /// Create missing index notes for subfolders that lack them, returning created file paths
    private static func createMissingIndexNotes(pkmRoot: String) -> [String] {
        let fm = FileManager.default
        let pm = PKMPathManager(root: pkmRoot)
        var created: [String] = []

        let paraPaths: [(String, PARACategory)] = [
            (pm.projectsPath, .project),
            (pm.areaPath, .area),
            (pm.resourcePath, .resource),
            (pm.archivePath, .archive),
        ]

        for (basePath, category) in paraPaths {
            guard let entries = try? fm.contentsOfDirectory(atPath: basePath) else { continue }
            for entry in entries {
                guard !entry.hasPrefix("."), !entry.hasPrefix("_") else { continue }
                let folderPath = (basePath as NSString).appendingPathComponent(entry)
                var isDir: ObjCBool = false
                guard fm.fileExists(atPath: folderPath, isDirectory: &isDir), isDir.boolValue else { continue }

                let indexPath = (folderPath as NSString).appendingPathComponent("\(entry).md")
                guard !fm.fileExists(atPath: indexPath) else { continue }

                let content = FrontmatterWriter.createIndexNote(
                    folderName: entry,
                    para: category,
                    description: "\(entry) 관련 자료"
                )
                do {
                    try content.write(toFile: indexPath, atomically: true, encoding: .utf8)
                    created.append(indexPath)
                    NSLog("[VaultCheck] Created missing index note: %@", (indexPath as NSString).lastPathComponent)
                } catch {
                    NSLog("[VaultCheck] Failed to create index note %@: %@", entry, error.localizedDescription)
                }
            }
        }

        return created
    }

    /// Collect all existing folder relative paths (for pruning stale relations)
    private static func collectExistingFolders(pm: PKMPathManager) -> Set<String> {
        let fm = FileManager.default
        let canonicalRoot = URL(fileURLWithPath: pm.root).resolvingSymlinksInPath().path
        let rootPrefix = canonicalRoot.hasSuffix("/") ? canonicalRoot : canonicalRoot + "/"
        var folders = Set<String>()

        for basePath in [pm.projectsPath, pm.areaPath, pm.resourcePath, pm.archivePath] {
            guard let entries = try? fm.contentsOfDirectory(atPath: basePath) else { continue }
            for entry in entries {
                guard !entry.hasPrefix("."), !entry.hasPrefix("_") else { continue }
                let folderPath = (basePath as NSString).appendingPathComponent(entry)
                var isDir: ObjCBool = false
                guard fm.fileExists(atPath: folderPath, isDirectory: &isDir), isDir.boolValue else { continue }
                let canonical = URL(fileURLWithPath: folderPath).resolvingSymlinksInPath().path
                if canonical.hasPrefix(rootPrefix) {
                    folders.insert(String(canonical.dropFirst(rootPrefix.count)))
                }
            }
        }
        return folders
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
