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
        var manuallyProcessedCount = 0

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
        let pm = PKMPathManager(root: pkmRoot)
        let existingFolders = Self.collectExistingFolders(pm: pm)
        FolderRelationStore(pkmRoot: pkmRoot).pruneStale(existingFolders: existingFolders)
        await NoteIndexGenerator(pkmRoot: pkmRoot).pruneStale(existingFolders: existingFolders)

        // Phase 2: Repair (10% -> 20%)
        var repairedFiles: [String] = []
        if report.totalIssues > 0 {
            onProgress(Progress(phase: "자동 복구 중...", fraction: 0.12))
            let repair = auditor.repair(report: report)
            repairCount = repair.linksFixed + repair.frontmatterInjected + repair.paraFixed + repair.nfdRenamed

            repairedFiles = Self.collectRepairedFiles(from: report)
            await cache.updateHashes(repairedFiles)
        }
        if Task.isCancelled { return .empty }
        onProgress(Progress(phase: "자동 복구 중...", fraction: 0.20))

        // Phase 2.5: Manually placed note repair (20% -> 25%)
        if !report.manualPlacementCandidates.isEmpty {
            onProgress(Progress(phase: L10n.VaultInspector.manualRepairing, fraction: 0.21))
            let manualRepairer = ManualPlacementRepairer(pkmRoot: pkmRoot)
            let manualResult = await manualRepairer.process(filePaths: report.manualPlacementCandidates) { progress, status in
                onProgress(Progress(
                    phase: status,
                    fraction: 0.20 + progress * 0.05
                ))
            }
            manuallyProcessedCount = manualResult.processedCount
            enrichCount += manualResult.processedCount
        }
        if Task.isCancelled { return .empty }
        onProgress(Progress(phase: L10n.VaultInspector.manualRepairing, fraction: 0.25))

        // Check all .md files for changes (single batch actor call)
        onProgress(Progress(phase: "변경 파일 확인 중...", fraction: 0.25))
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
                if Task.isCancelled {
                    group.cancelAll()
                    break
                }
                while active < 3 && index < filesToEnrich.count {
                    let path = filesToEnrich[index]
                    index += 1
                    active += 1
                    group.addTask {
                        do {
                            // Body changed since the last check — refresh the
                            // AI-owned tags/summary so folder synthesis
                            // recompounds and metadata stays current.
                            return try await enricher.enrichNote(at: path, refreshExisting: true)
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

        // Phase 4.2: clean orphaned entity pages left by Finder folder
        // renames/merges (a page whose baseName no longer matches its parent
        // folder). Scans ONLY the 4 PARA folders — the vault-root
        // CLAUDE.md/AGENTS.md carry the same DotBrain marker but are never
        // enumerated, so the companion files can never be corrupted.
        let orphansCleaned = Self.cleanOrphanEntityPages(pm: pm)
        if orphansCleaned > 0 {
            NSLog("[VaultCheck] %d orphaned entity pages cleaned", orphansCleaned)
        }

        // Phase 4.5: Link State Diff — detect user link removals BEFORE writing new links
        onProgress(Progress(phase: "링크 변경 감지 중...", fraction: 0.70))
        let linker = SemanticLinker(pkmRoot: pkmRoot)
        let linkDetector = LinkStateDetector(pkmRoot: pkmRoot)
        let allNotesForSnapshot = linker.buildNoteIndex()
        let previousSnapshot = linkDetector.loadSnapshot()
        let currentSnapshot = linkDetector.buildCurrentSnapshot(allNotes: allNotesForSnapshot)

        if let prev = previousSnapshot {
            // uniquingKeysWith: same-named notes in different folders must not trap
            let noteInfoMap = Dictionary(
                allNotesForSnapshot.map { ($0.name, $0) },
                uniquingKeysWith: { first, _ in first }
            )
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

        // Phase 5.2: link diet — Related Notes accumulate across runs with no
        // write-time ceiling; over-cap notes get re-selected down to the best
        // N. Must run BEFORE the final snapshot so pruned links land in it and
        // are never misread as user removals on the next check.
        onProgress(Progress(phase: "링크 재선별 중...", fraction: 0.95))
        // existingRelated dedups names, so a section can exceed the cap in
        // LINES at exactly cap unique names (duplicate lines) — >= closes
        // that gap at the cost of one cheap read for at-cap clean notes
        let pruneCandidates = allNotesForSnapshot
            .filter {
                $0.existingRelated.count >= RelatedNotesPruner.cumulativeCap ||
                linkResult.modifiedFiles.contains($0.filePath)
            }
            .map { RelatedNotesPruner.PruneInput(name: $0.name, filePath: $0.filePath, summary: $0.summary) }
        let pruneResult = await RelatedNotesPruner(pkmRoot: pkmRoot).pruneAll(candidates: pruneCandidates)
        if pruneResult.prunedNotes > 0 {
            NSLog("[VaultCheck] 링크 재선별: %d개 노트에서 %d개 링크 정리",
                  pruneResult.prunedNotes, pruneResult.removedLinks)
        }

        // Save post-link snapshot (reads file content fresh — captures newly written links)
        let finalSnapshot = linkDetector.buildCurrentSnapshot(allNotes: allNotesForSnapshot)
        linkDetector.saveSnapshot(finalSnapshot)

        // Phase 5.5: refresh entity pages for changed folders
        if Task.isCancelled { return .empty }
        onProgress(Progress(phase: "폴더 페이지 갱신 중...", fraction: 0.95))
        let synthesized = await FolderSynthesizer(pkmRoot: pkmRoot).synthesizeFolders(
            dirtyFolders, changedNotePaths: allChangedFiles
        )
        if !synthesized.isEmpty {
            // Written folder notes carry a fresh overview — re-index those
            // folders so the index summary picks it up immediately
            await indexGenerator.updateForFolders(
                Set(synthesized.map { ($0.path as NSString).deletingLastPathComponent })
            )
            // Chronicle each synthesis 요지 so the .meta/log.md timeline records
            // how folder knowledge evolved this run
            let synthesisLog = VaultLogService(pkmRoot: pkmRoot)
            for output in synthesized where !output.gist.isEmpty {
                let scope = ((output.path as NSString).deletingLastPathComponent as NSString).lastPathComponent
                synthesisLog.append(kind: "synthesis", summary: "\(scope): \(output.gist)")
            }
        }

        // Phase 5.6: refresh category hub pages across the affected categories.
        // Hash-gated on each subfolder's STABLE slice (개요+핵심노트), so a hub
        // re-synthesizes only when a subfolder's durable content changed — a
        // subfolder's 최근 흐름/timestamp churn never flips the hub hash.
        let affectedCategories = CategoryHubSynthesizer.categoryRoots(
            for: dirtyFolders, pkmRoot: pkmRoot
        )
        var synthesizedHubs: [CategoryHubSynthesizer.Output] = []
        if !affectedCategories.isEmpty && !Task.isCancelled {
            onProgress(Progress(phase: "카테고리 허브 갱신 중...", fraction: 0.97))
            synthesizedHubs = await CategoryHubSynthesizer(pkmRoot: pkmRoot)
                .synthesizeCategories(affectedCategories)
            // Chronicle each hub 요지 to the same .meta/log.md timeline
            let hubLog = VaultLogService(pkmRoot: pkmRoot)
            for hub in synthesizedHubs where !hub.gist.isEmpty {
                let scope = ((hub.path as NSString).deletingLastPathComponent as NSString).lastPathComponent
                hubLog.append(kind: "synthesis", summary: "\(scope): \(hub.gist)")
            }
        }

        // Update hashes for all changed files plus everything the linker,
        // tag normalizer, pruner, and folder/hub synthesizers wrote — unhashed
        // writes trigger pointless AI re-processing on the next check
        await cache.updateHashes(Array(
            allChangedFiles
                .union(linkResult.modifiedFiles)
                .union(pruneResult.modifiedFiles)
                .union(Set(synthesized.map(\.path)))
                .union(Set(synthesizedHubs.map(\.path)))
        ))
        await cache.save()

        StatisticsService.recordActivity(
            fileName: "볼트 점검",
            category: "system",
            action: "completed",
            detail: "\(report.totalIssues)건 발견, \(repairCount)건 복구, \(enrichCount)개 보완(직접 추가 \(manuallyProcessedCount)개), \(linkResult.linksCreated)개 링크"
        )

        VaultLogService(pkmRoot: pkmRoot).append(
            kind: "vault-check",
            summary: "\(report.totalIssues)건 발견, \(repairCount)건 복구, 링크 +\(linkResult.linksCreated)/−\(pruneResult.removedLinks)"
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
        for nfd in report.nfdFiles {
            files.insert(nfd.nfcPath)
        }
        return Array(files)
    }

    /// Collect all existing folder relative paths (for pruning stale relations).
    /// Recurses into nested subfolders (vault allows depth 3) — a depth-1 scan
    /// would mark live nested folders as stale and prune their index entries.
    private static func collectExistingFolders(pm: PKMPathManager) -> Set<String> {
        let fm = FileManager.default
        let canonicalRoot = URL(fileURLWithPath: pm.root).resolvingSymlinksInPath().path
        let rootPrefix = canonicalRoot.hasSuffix("/") ? canonicalRoot : canonicalRoot + "/"
        var folders = Set<String>()

        for basePath in [pm.projectsPath, pm.areaPath, pm.resourcePath, pm.archivePath] {
            guard let enumerator = fm.enumerator(atPath: basePath) else { continue }
            while let element = enumerator.nextObject() as? String {
                let name = (element as NSString).lastPathComponent
                let folderPath = (basePath as NSString).appendingPathComponent(element)
                var isDir: ObjCBool = false
                guard fm.fileExists(atPath: folderPath, isDirectory: &isDir), isDir.boolValue else { continue }
                if name.hasPrefix(".") || name.hasPrefix("_") {
                    enumerator.skipDescendants()
                    continue
                }
                let canonical = URL(fileURLWithPath: folderPath).resolvingSymlinksInPath().path
                if canonical.hasPrefix(rootPrefix) {
                    folders.insert(String(canonical.dropFirst(rootPrefix.count))
                        .precomposedStringWithCanonicalMapping)
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

    /// Remove orphaned entity pages left behind by a Finder folder rename/merge.
    ///
    /// A folder/hub page lives at `<folder>/<folderName>.md`, so its baseName
    /// always equals its parent folder name. When a user renames or merges the
    /// folder in Finder the page keeps its old baseName, producing
    /// `<newFolder>/<oldName>.md` (baseName != parentName) — a stale synthesis
    /// that no longer describes its folder. Such a page is stripped of its
    /// DotBrain synthesis block (preserving any user prose), or trashed when
    /// nothing user-authored remains.
    ///
    /// Scope guardrail: iterates `collectAllMdFiles`, which enumerates ONLY the
    /// four PARA folders and skips `.`/`_` directories. The vault-root
    /// `CLAUDE.md`/`AGENTS.md` also carry the DotBrain marker and have
    /// baseName != parentName, but they live at the root (never enumerated) so
    /// they are never scanned or modified. Normal notes never carry the marker
    /// (`RelatedNotesWriter` writes plain `## Related Notes`), so they are
    /// filtered out by the `isEntityPage` check. Returns the number of pages
    /// cleaned.
    static func cleanOrphanEntityPages(pm: PKMPathManager) -> Int {
        let fm = FileManager.default
        var cleaned = 0
        for path in collectAllMdFiles(pm: pm) {
            let baseName = ((path as NSString).lastPathComponent as NSString)
                .deletingPathExtension
            let parentName = ((path as NSString).deletingLastPathComponent as NSString)
                .lastPathComponent
            guard baseName != parentName else { continue }
            guard let content = try? String(contentsOfFile: path, encoding: .utf8),
                  FolderNotePage.isEntityPage(content),
                  let stripped = CategoryHubPage.strippingSynthesis(from: content) else { continue }

            // Trash the page when only frontmatter/whitespace remains (a pure
            // DotBrain page); otherwise write back the stripped content so the
            // user's prose below the block survives.
            let userBody = Frontmatter.parse(markdown: stripped).body
                .trimmingCharacters(in: .whitespacesAndNewlines)
            if userBody.isEmpty {
                try? fm.trashItem(at: URL(fileURLWithPath: path), resultingItemURL: nil)
            } else {
                try? stripped.write(toFile: path, atomically: true, encoding: .utf8)
            }
            cleaned += 1
        }
        return cleaned
    }

}
