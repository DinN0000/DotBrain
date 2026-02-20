import Foundation

struct SemanticLinker: Sendable {
    let pkmRoot: String
    private let maxConcurrentAI = 3
    private let batchSize = 5

    private var pathManager: PKMPathManager {
        PKMPathManager(root: pkmRoot)
    }

    struct LinkResult {
        var tagsNormalized: TagNormalizer.Result
        var notesLinked: Int
        var linksCreated: Int
    }

    // MARK: - Public API

    func linkAll(onProgress: ((Double, String) -> Void)? = nil) async -> LinkResult {
        onProgress?(0.0, "태그 정규화 중...")
        let tagResult: TagNormalizer.Result
        do {
            tagResult = try TagNormalizer(pkmRoot: pkmRoot).normalize()
            NSLog("[SemanticLinker] 태그 정규화: %d 파일, %d 태그 추가", tagResult.filesModified, tagResult.tagsAdded)
        } catch {
            NSLog("[SemanticLinker] 태그 정규화 실패: %@", error.localizedDescription)
            tagResult = TagNormalizer.Result()
        }
        onProgress?(0.1, "태그 정규화 완료")

        onProgress?(0.1, "볼트 인덱스 구축 중...")
        let allNotes = buildNoteIndex()
        let contextMap = await ContextMapBuilder(pkmRoot: pkmRoot).build()
        let noteNames = Set(allNotes.map { $0.name })
        let notePathMap = Dictionary(uniqueKeysWithValues: allNotes.map { ($0.name, $0.filePath) })
        onProgress?(0.2, "\(allNotes.count)개 노트 인덱스 완료")

        guard !allNotes.isEmpty else {
            return LinkResult(tagsNormalized: tagResult, notesLinked: 0, linksCreated: 0)
        }

        let writer = RelatedNotesWriter()
        var totalNotesLinked = 0
        var totalLinksCreated = 0

        // STEP 1: Project/Area — same-folder auto-link
        let projectAreaNotes = allNotes.filter { $0.para == .project || $0.para == .area }
        onProgress?(0.25, "Project/Area 자동 연결 중...")

        let autoLinkCounts = await processAutoLinks(
            notes: projectAreaNotes,
            noteNames: noteNames,
            notePathMap: notePathMap,
            writer: writer,
            notesLinked: &totalNotesLinked,
            linksCreated: &totalLinksCreated
        )

        // STEP 2: Project/Area — cross-folder AI-filtered links (remaining slots)
        onProgress?(0.4, "Project/Area 크로스폴더 연결 중...")
        await processAIFilteredLinks(
            notes: projectAreaNotes,
            allNotes: allNotes,
            contextMap: contextMap,
            noteNames: noteNames,
            notePathMap: notePathMap,
            writer: writer,
            folderBonus: 1.0,
            excludeSameFolder: true,
            existingLinkCounts: autoLinkCounts,
            notesLinked: &totalNotesLinked,
            linksCreated: &totalLinksCreated,
            onProgress: { p, msg in onProgress?(0.4 + p * 0.2, msg) }
        )

        // STEP 3: Resource/Archive — standard flow with boosted folder bonus
        let resourceArchiveNotes = allNotes.filter { $0.para == .resource || $0.para == .archive }
        onProgress?(0.6, "Resource/Archive 연결 중...")
        await processAIFilteredLinks(
            notes: resourceArchiveNotes,
            allNotes: allNotes,
            contextMap: contextMap,
            noteNames: noteNames,
            notePathMap: notePathMap,
            writer: writer,
            folderBonus: 2.5,
            excludeSameFolder: false,
            existingLinkCounts: [:],
            notesLinked: &totalNotesLinked,
            linksCreated: &totalLinksCreated,
            onProgress: { p, msg in onProgress?(0.6 + p * 0.35, msg) }
        )

        onProgress?(1.0, "시맨틱 링크 완료: \(totalNotesLinked)개 노트, \(totalLinksCreated)개 링크")
        return LinkResult(tagsNormalized: tagResult, notesLinked: totalNotesLinked, linksCreated: totalLinksCreated)
    }

    func linkNotes(filePaths: [String], onProgress: ((Double, String) -> Void)? = nil) async -> LinkResult {
        let tagResult = TagNormalizer.Result()

        let allNotes = buildNoteIndex()
        let contextMap = await ContextMapBuilder(pkmRoot: pkmRoot).build()
        let noteNames = Set(allNotes.map { $0.name })
        let notePathMap = Dictionary(uniqueKeysWithValues: allNotes.map { ($0.name, $0.filePath) })

        let targetNames = Set(filePaths.map {
            (($0 as NSString).lastPathComponent as NSString).deletingPathExtension
        })
        let targetNotes = allNotes.filter { targetNames.contains($0.name) }

        guard !targetNotes.isEmpty else {
            return LinkResult(tagsNormalized: tagResult, notesLinked: 0, linksCreated: 0)
        }

        let writer = RelatedNotesWriter()
        let aiFilter = LinkAIFilter()
        let candidateGen = LinkCandidateGenerator()
        var notesLinked = 0
        var linksCreated = 0

        for (i, note) in targetNotes.enumerated() {
            let isProjectArea = note.para == .project || note.para == .area
            var autoLinkedCount = 0

            // Project/Area: auto-link same-folder siblings
            if isProjectArea {
                let siblings = allNotes.filter {
                    $0.name != note.name
                    && $0.folderName == note.folderName
                    && !note.existingRelated.contains($0.name)
                }

                if !siblings.isEmpty {
                    let selected = selectTopSiblings(note: note, siblings: siblings, max: 5)
                    let siblingInfos = selected.map {
                        LinkAIFilter.SiblingInfo(name: $0.name, summary: $0.summary, tags: $0.tags)
                    }

                    do {
                        let results = try await aiFilter.generateContextOnly(
                            notes: [(name: note.name, summary: note.summary, tags: note.tags, siblings: siblingInfos)]
                        )
                        let links = results.first ?? []
                        if !links.isEmpty {
                            try writer.writeRelatedNotes(filePath: note.filePath, newLinks: links, noteNames: noteNames)
                            notesLinked += 1
                            linksCreated += links.count
                            autoLinkedCount = links.count

                            for link in links {
                                guard let targetPath = notePathMap[link.name] else { continue }
                                let reverse = LinkAIFilter.FilteredLink(name: note.name, context: "\(note.name)에서 참조", relation: "related")
                                try writer.writeRelatedNotes(filePath: targetPath, newLinks: [reverse], noteNames: noteNames)
                                linksCreated += 1
                            }
                        }
                    } catch {
                        NSLog("[SemanticLinker] 자동 연결 실패: %@ — %@", note.name, error.localizedDescription)
                    }
                }
            }

            // Cross-folder or standard linking
            let remainingSlots = 5 - autoLinkedCount
            guard remainingSlots > 0 else {
                let progress = Double(i + 1) / Double(targetNotes.count)
                onProgress?(progress, "\(note.name) 연결 완료")
                continue
            }

            let folderBonus: Double = isProjectArea ? 1.0 : 2.5
            let excludeFolder = isProjectArea

            let candidates = candidateGen.generateCandidates(
                for: note,
                allNotes: allNotes,
                mocEntries: contextMap.entries,
                maxCandidates: remainingSlots * 2,
                folderBonus: folderBonus,
                excludeSameFolder: excludeFolder
            )

            if !candidates.isEmpty {
                do {
                    let filtered = try await aiFilter.filterSingle(
                        noteName: note.name,
                        noteSummary: note.summary,
                        noteTags: note.tags,
                        candidates: candidates,
                        maxResults: remainingSlots
                    )

                    if !filtered.isEmpty {
                        try writer.writeRelatedNotes(filePath: note.filePath, newLinks: filtered, noteNames: noteNames)
                        if autoLinkedCount == 0 { notesLinked += 1 }
                        linksCreated += filtered.count

                        for link in filtered {
                            guard let targetPath = notePathMap[link.name] else { continue }
                            let reverse = LinkAIFilter.FilteredLink(name: note.name, context: "\(note.name)에서 참조", relation: "related")
                            try writer.writeRelatedNotes(filePath: targetPath, newLinks: [reverse], noteNames: noteNames)
                            linksCreated += 1
                        }
                    }
                } catch {
                    NSLog("[SemanticLinker] 노트 링크 실패: %@ — %@", note.name, error.localizedDescription)
                }
            }

            let progress = Double(i + 1) / Double(targetNotes.count)
            onProgress?(progress, "\(note.name) 연결 완료")
        }

        return LinkResult(tagsNormalized: tagResult, notesLinked: notesLinked, linksCreated: linksCreated)
    }

    // MARK: - Same-Folder Auto-Link (Project/Area)

    /// Returns a map of noteName -> number of auto-linked siblings
    private func processAutoLinks(
        notes: [LinkCandidateGenerator.NoteInfo],
        noteNames: Set<String>,
        notePathMap: [String: String],
        writer: RelatedNotesWriter,
        notesLinked: inout Int,
        linksCreated: inout Int
    ) async -> [String: Int] {
        guard !notes.isEmpty else { return [:] }

        // Group by folder
        var folderGroups: [String: [LinkCandidateGenerator.NoteInfo]] = [:]
        for note in notes {
            folderGroups[note.folderName, default: []].append(note)
        }

        let aiFilter = LinkAIFilter()
        var linkCounts: [String: Int] = [:]

        // Process each folder group
        for (_, folderNotes) in folderGroups {
            guard folderNotes.count >= 2 else { continue }

            // Build batch input: each note with its siblings
            var batchInput: [(name: String, summary: String, tags: [String], siblings: [LinkAIFilter.SiblingInfo])] = []
            var batchNotes: [LinkCandidateGenerator.NoteInfo] = []

            for note in folderNotes {
                let siblings = folderNotes.filter {
                    $0.name != note.name && !note.existingRelated.contains($0.name)
                }
                guard !siblings.isEmpty else { continue }

                let selected = selectTopSiblings(note: note, siblings: siblings, max: 5)
                let siblingInfos = selected.map {
                    LinkAIFilter.SiblingInfo(name: $0.name, summary: $0.summary, tags: $0.tags)
                }
                batchInput.append((name: note.name, summary: note.summary, tags: note.tags, siblings: siblingInfos))
                batchNotes.append(note)
            }

            guard !batchInput.isEmpty else { continue }

            // Batch AI call for context generation
            let batches = stride(from: 0, to: batchInput.count, by: batchSize).map {
                Array(batchInput[$0..<min($0 + batchSize, batchInput.count)])
            }
            let noteBatches = stride(from: 0, to: batchNotes.count, by: batchSize).map {
                Array(batchNotes[$0..<min($0 + batchSize, batchNotes.count)])
            }

            for (batchIdx, batch) in batches.enumerated() {
                let currentNotes = noteBatches[batchIdx]

                do {
                    let results = try await aiFilter.generateContextOnly(notes: batch)

                    for (noteIdx, links) in results.enumerated() where !links.isEmpty {
                        let note = currentNotes[noteIdx]
                        try writer.writeRelatedNotes(filePath: note.filePath, newLinks: links, noteNames: noteNames)
                        notesLinked += 1
                        linksCreated += links.count
                        linkCounts[note.name] = links.count

                        // Reverse links
                        for link in links {
                            guard let targetPath = notePathMap[link.name] else { continue }
                            let reverse = LinkAIFilter.FilteredLink(name: note.name, context: "\(note.name)에서 참조", relation: "related")
                            try writer.writeRelatedNotes(filePath: targetPath, newLinks: [reverse], noteNames: noteNames)
                            linksCreated += 1
                        }
                    }
                } catch {
                    NSLog("[SemanticLinker] 자동 연결 배치 실패: %@", error.localizedDescription)
                }
            }
        }

        return linkCounts
    }

    // MARK: - AI-Filtered Links (cross-folder or standard)

    private func processAIFilteredLinks(
        notes: [LinkCandidateGenerator.NoteInfo],
        allNotes: [LinkCandidateGenerator.NoteInfo],
        contextMap: VaultContextMap,
        noteNames: Set<String>,
        notePathMap: [String: String],
        writer: RelatedNotesWriter,
        folderBonus: Double,
        excludeSameFolder: Bool,
        existingLinkCounts: [String: Int],
        notesLinked: inout Int,
        linksCreated: inout Int,
        onProgress: ((Double, String) -> Void)?
    ) async {
        let candidateGen = LinkCandidateGenerator()
        let aiFilter = LinkAIFilter()

        var notesWithCandidates: [(note: LinkCandidateGenerator.NoteInfo, candidates: [LinkCandidateGenerator.Candidate])] = []

        for note in notes {
            let remainingSlots = 5 - (existingLinkCounts[note.name] ?? 0)
            guard remainingSlots > 0 else { continue }

            let candidates = candidateGen.generateCandidates(
                for: note,
                allNotes: allNotes,
                mocEntries: contextMap.entries,
                maxCandidates: remainingSlots * 2,
                folderBonus: folderBonus,
                excludeSameFolder: excludeSameFolder
            )
            if !candidates.isEmpty {
                notesWithCandidates.append((note: note, candidates: candidates))
            }
        }

        guard !notesWithCandidates.isEmpty else { return }

        let batches = stride(from: 0, to: notesWithCandidates.count, by: batchSize).map {
            Array(notesWithCandidates[$0..<min($0 + batchSize, notesWithCandidates.count)])
        }

        var allLinks: [(filePath: String, noteName: String, links: [LinkAIFilter.FilteredLink], maxLinks: Int)] = []
        let totalBatches = batches.count
        var completedBatches = 0

        await withTaskGroup(of: [(filePath: String, noteName: String, links: [LinkAIFilter.FilteredLink], maxLinks: Int)].self) { group in
            var activeTasks = 0

            for batch in batches {
                if activeTasks >= maxConcurrentAI {
                    if let results = await group.next() {
                        allLinks.append(contentsOf: results)
                        activeTasks -= 1
                        completedBatches += 1
                        onProgress?(Double(completedBatches) / Double(totalBatches), "AI 필터링 \(completedBatches)/\(totalBatches)")
                    }
                }

                group.addTask { [existingLinkCounts] in
                    let batchInput = batch.map { item in
                        (name: item.note.name, summary: item.note.summary, tags: item.note.tags, candidates: item.candidates)
                    }

                    do {
                        let results = try await aiFilter.filterBatch(notes: batchInput)
                        return zip(batch, results).map { (item, links) in
                            let maxLinks = 5 - (existingLinkCounts[item.note.name] ?? 0)
                            let capped = Array(links.prefix(maxLinks))
                            return (filePath: item.note.filePath, noteName: item.note.name, links: capped, maxLinks: maxLinks)
                        }
                    } catch {
                        NSLog("[SemanticLinker] AI 필터 배치 실패: %@", error.localizedDescription)
                        return batch.map { item in
                            (filePath: item.note.filePath, noteName: item.note.name, links: [LinkAIFilter.FilteredLink](), maxLinks: 0)
                        }
                    }
                }
                activeTasks += 1
            }

            for await results in group {
                allLinks.append(contentsOf: results)
                completedBatches += 1
                onProgress?(Double(completedBatches) / Double(totalBatches), "AI 필터링 \(completedBatches)/\(totalBatches)")
            }
        }

        // Write forward + reverse links
        var reverseLinks: [String: [(name: String, context: String, relation: String)]] = [:]
        for entry in allLinks where !entry.links.isEmpty {
            do {
                try writer.writeRelatedNotes(filePath: entry.filePath, newLinks: entry.links, noteNames: noteNames)
                notesLinked += 1
                linksCreated += entry.links.count
            } catch {
                NSLog("[SemanticLinker] 링크 기록 실패: %@ — %@", entry.noteName, error.localizedDescription)
            }

            for link in entry.links {
                reverseLinks[link.name, default: []].append((name: entry.noteName, context: "\(entry.noteName)에서 참조", relation: "related"))
            }
        }

        for (targetName, sources) in reverseLinks {
            guard let targetPath = notePathMap[targetName] else { continue }
            let reverseFilteredLinks = sources.map { LinkAIFilter.FilteredLink(name: $0.name, context: $0.context, relation: $0.relation) }
            do {
                try writer.writeRelatedNotes(filePath: targetPath, newLinks: reverseFilteredLinks, noteNames: noteNames)
                linksCreated += reverseFilteredLinks.count
            } catch {
                NSLog("[SemanticLinker] 역방향 링크 기록 실패: %@ — %@", targetName, error.localizedDescription)
            }
        }
    }

    // MARK: - Helpers

    /// Select top siblings by tag overlap score, capped at max
    private func selectTopSiblings(
        note: LinkCandidateGenerator.NoteInfo,
        siblings: [LinkCandidateGenerator.NoteInfo],
        max limit: Int
    ) -> [LinkCandidateGenerator.NoteInfo] {
        guard siblings.count > limit else { return siblings }
        let noteTags = Set(note.tags.map { $0.lowercased() })
        let scored = siblings.map { sibling -> (LinkCandidateGenerator.NoteInfo, Double) in
            let sibTags = Set(sibling.tags.map { $0.lowercased() })
            return (sibling, Double(noteTags.intersection(sibTags).count))
        }
        return scored.sorted { $0.1 > $1.1 }.prefix(limit).map { $0.0 }
    }

    // MARK: - Private

    private func buildNoteIndex() -> [LinkCandidateGenerator.NoteInfo] {
        let fm = FileManager.default
        var notes: [LinkCandidateGenerator.NoteInfo] = []

        let categories: [(PARACategory, String)] = [
            (.project, pathManager.projectsPath),
            (.area, pathManager.areaPath),
            (.resource, pathManager.resourcePath),
            (.archive, pathManager.archivePath),
        ]

        for (para, basePath) in categories {
            guard let folders = try? fm.contentsOfDirectory(atPath: basePath) else { continue }
            for folder in folders {
                guard !folder.hasPrefix("."), !folder.hasPrefix("_") else { continue }
                let folderPath = (basePath as NSString).appendingPathComponent(folder)
                var isDir: ObjCBool = false
                guard fm.fileExists(atPath: folderPath, isDirectory: &isDir), isDir.boolValue else { continue }

                guard let files = try? fm.contentsOfDirectory(atPath: folderPath) else { continue }
                for file in files {
                    guard file.hasSuffix(".md"), !file.hasPrefix("."), !file.hasPrefix("_") else { continue }
                    guard file != "\(folder).md" else { continue }

                    let filePath = (folderPath as NSString).appendingPathComponent(file)
                    guard let content = try? String(contentsOfFile: filePath, encoding: .utf8) else { continue }

                    let (frontmatter, body) = Frontmatter.parse(markdown: content)
                    let baseName = (file as NSString).deletingPathExtension

                    let existingRelated = parseExistingRelatedNames(body)

                    notes.append(LinkCandidateGenerator.NoteInfo(
                        name: baseName,
                        filePath: filePath,
                        tags: frontmatter.tags,
                        summary: frontmatter.summary ?? "",
                        project: frontmatter.project,
                        folderName: folder,
                        para: para,
                        existingRelated: existingRelated
                    ))
                }
            }
        }

        return notes
    }

    private func parseExistingRelatedNames(_ body: String) -> Set<String> {
        var names = Set<String>()
        var inSection = false

        for line in body.components(separatedBy: "\n") {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed.hasPrefix("## Related Notes") {
                inSection = true
                continue
            }
            if trimmed.hasPrefix("## ") && inSection {
                break
            }
            if inSection, trimmed.hasPrefix("- [[") {
                if let start = trimmed.range(of: "[["),
                   let end = trimmed.range(of: "]]") {
                    let name = String(trimmed[start.upperBound..<end.lowerBound])
                    if !name.isEmpty { names.insert(name) }
                }
            }
        }

        return names
    }
}
