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

    /// Link notes semantically using AI filtering.
    /// - Parameter changedFiles: If provided, only generate candidates and AI-filter for
    ///   changed notes and their existing Related Notes neighbors. Pass nil for full scan.
    func linkAll(changedFiles: Set<String>? = nil, onProgress: ((Double, String) -> Void)? = nil) async -> LinkResult {
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
        onProgress?(0.2, "\(allNotes.count)개 노트 인덱스 완료")

        guard !allNotes.isEmpty else {
            return LinkResult(tagsNormalized: tagResult, notesLinked: 0, linksCreated: 0)
        }

        // Determine which notes to process
        let targetNotes: [LinkCandidateGenerator.NoteInfo]
        if let changed = changedFiles {
            let changedNames = Set(changed.map {
                (($0 as NSString).lastPathComponent as NSString).deletingPathExtension
            })
            // Include changed notes + notes that already reference changed notes
            targetNotes = allNotes.filter { note in
                changedNames.contains(note.name) ||
                !note.existingRelated.isDisjoint(with: changedNames)
            }
            NSLog("[SemanticLinker] Incremental: %d/%d notes targeted", targetNotes.count, allNotes.count)
        } else {
            targetNotes = allNotes
        }

        let candidateGen = LinkCandidateGenerator()
        var notesWithCandidates: [(note: LinkCandidateGenerator.NoteInfo, candidates: [LinkCandidateGenerator.Candidate])] = []
        for note in targetNotes {
            let candidates = candidateGen.generateCandidates(
                for: note,
                allNotes: allNotes,
                mocEntries: contextMap.entries
            )
            if !candidates.isEmpty {
                notesWithCandidates.append((note: note, candidates: candidates))
            }
        }

        onProgress?(0.3, "\(notesWithCandidates.count)개 노트에 후보 생성 완료")

        guard !notesWithCandidates.isEmpty else {
            return LinkResult(tagsNormalized: tagResult, notesLinked: 0, linksCreated: 0)
        }

        let aiFilter = LinkAIFilter()
        let batches = stride(from: 0, to: notesWithCandidates.count, by: batchSize).map {
            Array(notesWithCandidates[$0..<min($0 + batchSize, notesWithCandidates.count)])
        }

        var allLinks: [(filePath: String, noteName: String, links: [LinkAIFilter.FilteredLink])] = []
        let totalBatches = batches.count
        var completedBatches = 0

        await withTaskGroup(of: [(filePath: String, noteName: String, links: [LinkAIFilter.FilteredLink])].self) { group in
            var activeTasks = 0

            for batch in batches {
                if activeTasks >= maxConcurrentAI {
                    if let results = await group.next() {
                        allLinks.append(contentsOf: results)
                        activeTasks -= 1
                        completedBatches += 1
                        let progress = 0.3 + Double(completedBatches) / Double(totalBatches) * 0.5
                        onProgress?(progress, "AI 필터링 \(completedBatches)/\(totalBatches) 배치")
                    }
                }

                group.addTask {
                    let batchInput = batch.map { item in
                        (name: item.note.name, summary: item.note.summary, tags: item.note.tags, candidates: item.candidates)
                    }

                    do {
                        let results = try await aiFilter.filterBatch(notes: batchInput)
                        return zip(batch, results).map { (item, links) in
                            (filePath: item.note.filePath, noteName: item.note.name, links: links)
                        }
                    } catch {
                        NSLog("[SemanticLinker] AI 필터 배치 실패: %@", error.localizedDescription)
                        return batch.map { item in
                            (filePath: item.note.filePath, noteName: item.note.name, links: [LinkAIFilter.FilteredLink]())
                        }
                    }
                }
                activeTasks += 1
            }

            for await results in group {
                allLinks.append(contentsOf: results)
                completedBatches += 1
                let progress = 0.3 + Double(completedBatches) / Double(totalBatches) * 0.5
                onProgress?(progress, "AI 필터링 \(completedBatches)/\(totalBatches) 배치")
            }
        }

        onProgress?(0.8, "관련 노트 기록 중...")

        let writer = RelatedNotesWriter()
        let notePathMap = Dictionary(uniqueKeysWithValues: allNotes.map { ($0.name, $0.filePath) })

        var reverseLinks: [String: [(name: String, context: String, relation: String)]] = [:]
        for entry in allLinks {
            for link in entry.links {
                let reverseContext = Self.reverseRelationContext[link.relation] ?? "관련 문서"
                reverseLinks[link.name, default: []].append((name: entry.noteName, context: reverseContext, relation: link.relation))
            }
        }

        var notesLinked = 0
        var linksCreated = 0

        for entry in allLinks where !entry.links.isEmpty {
            do {
                try writer.writeRelatedNotes(filePath: entry.filePath, newLinks: entry.links, noteNames: noteNames)
                notesLinked += 1
                linksCreated += entry.links.count
            } catch {
                NSLog("[SemanticLinker] 링크 기록 실패: %@ — %@", entry.noteName, error.localizedDescription)
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

        onProgress?(1.0, "시맨틱 링크 완료: \(notesLinked)개 노트, \(linksCreated)개 링크")

        return LinkResult(tagsNormalized: tagResult, notesLinked: notesLinked, linksCreated: linksCreated)
    }

    func linkNotes(filePaths: [String], onProgress: ((Double, String) -> Void)? = nil) async -> LinkResult {
        let tagResult = TagNormalizer.Result()

        let allNotes = buildNoteIndex()
        let contextMap = await ContextMapBuilder(pkmRoot: pkmRoot).build()
        let noteNames = Set(allNotes.map { $0.name })

        let targetNames = Set(filePaths.map {
            (($0 as NSString).lastPathComponent as NSString).deletingPathExtension
        })
        let targetNotes = allNotes.filter { targetNames.contains($0.name) }

        guard !targetNotes.isEmpty else {
            return LinkResult(tagsNormalized: tagResult, notesLinked: 0, linksCreated: 0)
        }

        let candidateGen = LinkCandidateGenerator()
        let aiFilter = LinkAIFilter()
        let writer = RelatedNotesWriter()
        let notePathMap = Dictionary(uniqueKeysWithValues: allNotes.map { ($0.name, $0.filePath) })

        // Build candidates for all target notes
        var notesWithCandidates: [(note: LinkCandidateGenerator.NoteInfo, candidates: [LinkCandidateGenerator.Candidate])] = []
        for note in targetNotes {
            let candidates = candidateGen.generateCandidates(
                for: note,
                allNotes: allNotes,
                mocEntries: contextMap.entries
            )
            if !candidates.isEmpty {
                notesWithCandidates.append((note: note, candidates: candidates))
            }
        }

        guard !notesWithCandidates.isEmpty else {
            return LinkResult(tagsNormalized: tagResult, notesLinked: 0, linksCreated: 0)
        }

        // Batch AI filtering (same pattern as linkAll)
        let batches = stride(from: 0, to: notesWithCandidates.count, by: batchSize).map {
            Array(notesWithCandidates[$0..<min($0 + batchSize, notesWithCandidates.count)])
        }

        var allLinks: [(filePath: String, noteName: String, links: [LinkAIFilter.FilteredLink])] = []
        let totalBatches = batches.count
        var completedBatches = 0

        await withTaskGroup(of: [(filePath: String, noteName: String, links: [LinkAIFilter.FilteredLink])].self) { group in
            var activeTasks = 0

            for batch in batches {
                if activeTasks >= maxConcurrentAI {
                    if let results = await group.next() {
                        allLinks.append(contentsOf: results)
                        activeTasks -= 1
                        completedBatches += 1
                        onProgress?(Double(completedBatches) / Double(totalBatches) * 0.8, "AI 필터링 \(completedBatches)/\(totalBatches) 배치")
                    }
                }

                group.addTask {
                    let batchInput = batch.map { item in
                        (name: item.note.name, summary: item.note.summary, tags: item.note.tags, candidates: item.candidates)
                    }

                    do {
                        let results = try await aiFilter.filterBatch(notes: batchInput)
                        return zip(batch, results).map { (item, links) in
                            (filePath: item.note.filePath, noteName: item.note.name, links: links)
                        }
                    } catch {
                        NSLog("[SemanticLinker] AI 필터 배치 실패: %@", error.localizedDescription)
                        return batch.map { item in
                            (filePath: item.note.filePath, noteName: item.note.name, links: [LinkAIFilter.FilteredLink]())
                        }
                    }
                }
                activeTasks += 1
            }

            for await results in group {
                allLinks.append(contentsOf: results)
                completedBatches += 1
                onProgress?(Double(completedBatches) / Double(totalBatches) * 0.8, "AI 필터링 \(completedBatches)/\(totalBatches) 배치")
            }
        }

        // Collect reverse links into a dictionary so each target file is written only once
        var reverseLinks: [String: [(name: String, context: String, relation: String)]] = [:]
        for entry in allLinks {
            for link in entry.links {
                let reverseContext = Self.reverseRelationContext[link.relation] ?? "관련 문서"
                reverseLinks[link.name, default: []].append((name: entry.noteName, context: reverseContext, relation: link.relation))
            }
        }

        // Write forward links
        var notesLinked = 0
        var linksCreated = 0

        for entry in allLinks where !entry.links.isEmpty {
            do {
                try writer.writeRelatedNotes(filePath: entry.filePath, newLinks: entry.links, noteNames: noteNames)
                notesLinked += 1
                linksCreated += entry.links.count
            } catch {
                NSLog("[SemanticLinker] 노트 링크 실패: %@ — %@", entry.noteName, error.localizedDescription)
            }
        }

        // Write reverse links (batched per target file)
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

        onProgress?(1.0, "시맨틱 링크 완료: \(notesLinked)개 노트, \(linksCreated)개 링크")

        return LinkResult(tagsNormalized: tagResult, notesLinked: notesLinked, linksCreated: linksCreated)
    }

    // MARK: - Constants

    private static let reverseRelationContext: [String: String] = [
        "prerequisite": "이 문서를 선행 지식으로 활용",
        "project": "이 자료를 활용하는 프로젝트",
        "reference": "이 문서를 참고 자료로 인용",
        "related": "관련 주제를 다루는 문서",
    ]

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
