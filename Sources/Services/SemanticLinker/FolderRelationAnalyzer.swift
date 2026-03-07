import Foundation

/// Cache model for folder pair candidates
struct FolderPairCache: Codable, Sendable {
    let version: Int  // 1
    let noteIndexUpdated: String
    let relationsUpdated: String
    let candidates: [FolderPairCandidate]
}

/// Candidate for folder relation exploration
struct FolderPairCandidate: Sendable, Codable {
    let sourceFolder: String     // relative path e.g. "2_Area/SwiftUI-패턴"
    let targetFolder: String
    let sourcePara: PARACategory
    let targetPara: PARACategory
    let sourceNoteCount: Int
    let targetNoteCount: Int
    let existingLinkCount: Int
    let sharedTagCount: Int
    let topSharedTags: [String]

    // AI-filled fields
    var hint: String?
    var relationType: String?
    var confidence: Double

    // Existing relation flag — excluded from Codable
    var isExisting: Bool = false

    private enum CodingKeys: String, CodingKey {
        case sourceFolder, targetFolder, sourcePara, targetPara
        case sourceNoteCount, targetNoteCount, existingLinkCount
        case sharedTagCount, topSharedTags, hint, relationType, confidence
    }
}

/// Generates folder pair candidates and requests AI analysis for hints/relation types
struct FolderRelationAnalyzer: Sendable {
    let pkmRoot: String

    /// Generate candidates from vault notes, excluding already-defined relations.
    /// Uses cache when note-index and relations timestamps match.
    func generateCandidates(
        allNotes: [LinkCandidateGenerator.NoteInfo],
        existingRelations: FolderRelations
    ) async -> [FolderPairCandidate] {
        // Derive cache keys internally
        let noteIndexUpdated = readNoteIndexTimestamp() ?? ""
        let relationsUpdated = existingRelations.updated

        // Check cache
        let existingPairKeys = Set(existingRelations.relations.map {
            [$0.source, $0.target].sorted().joined(separator: "|")
        })

        if let cached = loadCache(noteIndexUpdated: noteIndexUpdated, relationsUpdated: relationsUpdated) {
            NSLog("[FolderRelationAnalyzer] Cache hit — returning %d candidates", cached.count)
            // Filter out pairs that now have existing relations (user may have added since cache)
            return cached.filter { c in
                let key = [c.sourceFolder, c.targetFolder].sorted().joined(separator: "|")
                return !existingPairKeys.contains(key)
            }
        }

        NSLog("[FolderRelationAnalyzer] Cache miss — computing candidates")

        // Group notes by folder
        var folderNotes: [String: [LinkCandidateGenerator.NoteInfo]] = [:]
        for note in allNotes {
            folderNotes[note.folderRelPath, default: []].append(note)
        }

        // Pre-compute per-folder tag and name sets
        var folderTagSets: [String: Set<String>] = [:]
        var folderNameSets: [String: Set<String>] = [:]
        for (folder, notes) in folderNotes {
            folderTagSets[folder] = Set(notes.flatMap { $0.tags.map { $0.lowercased() } })
            folderNameSets[folder] = Set(notes.map { $0.name })
        }

        // Enumerate folder pairs and compute scores
        let folders = Array(folderNotes.keys).sorted()

        var rawCandidates: [(pair: (String, String), score: Double, linkCount: Int, sharedTags: [String], sPara: PARACategory, tPara: PARACategory, sCount: Int, tCount: Int)] = []

        for i in 0..<folders.count {
            for j in (i + 1)..<folders.count {
                let a = folders[i]
                let b = folders[j]

                let pairKey = [a, b].sorted().joined(separator: "|")
                guard !existingPairKeys.contains(pairKey) else { continue }

                let aNotes = folderNotes[a] ?? []
                let bNotes = folderNotes[b] ?? []

                // Count existing cross-folder links using pre-computed name sets
                let bNames = folderNameSets[b] ?? []
                let aNames = folderNameSets[a] ?? []
                let linkCount = aNotes.reduce(0) { $0 + $1.existingRelated.intersection(bNames).count }
                    + bNotes.reduce(0) { $0 + $1.existingRelated.intersection(aNames).count }

                // Count shared tags using pre-computed tag sets
                let aTags = folderTagSets[a] ?? []
                let bTags = folderTagSets[b] ?? []
                let shared = aTags.intersection(bTags)

                let score = Double(linkCount) * 3.0 + Double(shared.count)
                guard score > 0 else { continue }

                let topShared = Array(shared.sorted().prefix(3))

                rawCandidates.append((
                    pair: (a, b),
                    score: score,
                    linkCount: linkCount,
                    sharedTags: topShared,
                    sPara: aNotes.first?.para ?? .archive,
                    tPara: bNotes.first?.para ?? .archive,
                    sCount: aNotes.count,
                    tCount: bNotes.count
                ))
            }
        }

        // Take top 20 by score
        let top = rawCandidates.sorted { $0.score > $1.score }.prefix(20)

        var candidates = top.map { item in
            FolderPairCandidate(
                sourceFolder: item.pair.0,
                targetFolder: item.pair.1,
                sourcePara: item.sPara,
                targetPara: item.tPara,
                sourceNoteCount: item.sCount,
                targetNoteCount: item.tCount,
                existingLinkCount: item.linkCount,
                sharedTagCount: item.sharedTags.count,
                topSharedTags: item.sharedTags,
                hint: nil,
                relationType: nil,
                confidence: 0
            )
        }

        guard !candidates.isEmpty else { return [] }

        // AI batch analysis
        candidates = await analyzeWithAI(candidates, folderNotes: folderNotes)

        // Sort by confidence descending, filter out very low confidence
        let result = candidates
            .filter { $0.confidence > 0.1 }
            .sorted { $0.confidence > $1.confidence }

        // Save to cache
        saveCache(candidates: result, noteIndexUpdated: noteIndexUpdated, relationsUpdated: relationsUpdated)

        return result
    }

    // MARK: - AI Analysis

    private func analyzeWithAI(
        _ candidates: [FolderPairCandidate],
        folderNotes: [String: [LinkCandidateGenerator.NoteInfo]]
    ) async -> [FolderPairCandidate] {
        let pairDescriptions = candidates.enumerated().map { (i, c) in
            let srcName = (c.sourceFolder as NSString).lastPathComponent
            let tgtName = (c.targetFolder as NSString).lastPathComponent
            let srcTags = (folderNotes[c.sourceFolder] ?? []).flatMap { $0.tags }
            let tgtTags = (folderNotes[c.targetFolder] ?? []).flatMap { $0.tags }
            let srcTopTags = topTags(srcTags, limit: 5)
            let tgtTopTags = topTags(tgtTags, limit: 5)

            return """
            [\(i)] \(srcName) (\(c.sourcePara.rawValue), \(c.sourceNoteCount) notes, tags: \(srcTopTags.joined(separator: ", ")))
                <> \(tgtName) (\(c.targetPara.rawValue), \(c.targetNoteCount) notes, tags: \(tgtTopTags.joined(separator: ", ")))
                기존 연결 \(c.existingLinkCount)개, 공유 태그: \(c.topSharedTags.joined(separator: ", "))
            """
        }.joined(separator: "\n\n")

        let prompt = """
        다음 폴더 쌍들의 관계를 분석하세요.

        \(pairDescriptions)

        ## 규칙
        1. hint: "~할 때", "~를 비교할 때" 형식, 한국어 20자 이내
        2. relationType: "비교/대조" | "적용" | "확장" | "관련" 중 하나
        3. confidence: 0.0~1.0 (관계 확신도)
        4. 관련 없는 쌍은 confidence 0.0

        ## 응답 (순수 JSON, 코드블록 없이)
        [{"index": 0, "hint": "패턴을 비교할 때", "relationType": "비교/대조", "confidence": 0.85}]
        """

        do {
            let response = try await AIService.shared.sendFastWithUsage(message: prompt)
            if let usage = response.usage {
                let model = await AIService.shared.fastModel
                StatisticsService.logTokenUsage(operation: "folder-relation-analyze", model: model, usage: usage, isEstimated: response.isEstimated)
            }
            return parseAIResponse(response.text, candidates: candidates)
        } catch {
            NSLog("[FolderRelationAnalyzer] AI analysis failed: %@", error.localizedDescription)
            // Return candidates without AI enrichment
            return candidates.map { c in
                var updated = c
                updated.confidence = Double(c.existingLinkCount) * 0.1 + Double(c.sharedTagCount) * 0.05
                return updated
            }
        }
    }

    private func parseAIResponse(_ text: String, candidates: [FolderPairCandidate]) -> [FolderPairCandidate] {
        let cleaned = text
            .replacingOccurrences(of: #"^```(?:json)?\s*\n?"#, with: "", options: .regularExpression)
            .replacingOccurrences(of: #"\n?```\s*$"#, with: "", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)

        guard let startBracket = cleaned.firstIndex(of: "["),
              let endBracket = cleaned.lastIndex(of: "]") else { return candidates }

        let jsonStr = String(cleaned[startBracket...endBracket])
        guard let data = jsonStr.data(using: .utf8) else { return candidates }

        struct Item: Decodable {
            let index: Int
            let hint: String?
            let relationType: String?
            let confidence: Double?
        }

        guard let items = try? JSONDecoder().decode([Item].self, from: data) else { return candidates }

        var result = candidates
        for item in items {
            guard item.index >= 0, item.index < result.count else { continue }
            result[item.index].hint = item.hint
            result[item.index].relationType = item.relationType
            result[item.index].confidence = item.confidence ?? 0
        }
        return result
    }

    private func topTags(_ tags: [String], limit: Int) -> [String] {
        var counts: [String: Int] = [:]
        for tag in tags { counts[tag.lowercased(), default: 0] += 1 }
        return counts.sorted { $0.value > $1.value }.prefix(limit).map { $0.key }
    }

    // MARK: - Cache

    private static let cacheVersion = 1

    private func cachePath() -> String {
        (pkmRoot as NSString).appendingPathComponent(".meta/folder-pair-cache.json")
    }

    private func readNoteIndexTimestamp() -> String? {
        let path = (pkmRoot as NSString).appendingPathComponent(".meta/note-index.json")
        guard let data = FileManager.default.contents(atPath: path) else { return nil }
        struct Partial: Decodable { let updated: String }
        return (try? JSONDecoder().decode(Partial.self, from: data))?.updated
    }

    private func loadCache(noteIndexUpdated: String, relationsUpdated: String) -> [FolderPairCandidate]? {
        guard let data = FileManager.default.contents(atPath: cachePath()) else { return nil }
        guard let cache = try? JSONDecoder().decode(FolderPairCache.self, from: data) else { return nil }
        guard cache.version == Self.cacheVersion,
              cache.noteIndexUpdated == noteIndexUpdated,
              cache.relationsUpdated == relationsUpdated else { return nil }
        return cache.candidates
    }

    private func saveCache(candidates: [FolderPairCandidate], noteIndexUpdated: String, relationsUpdated: String) {
        let fm = FileManager.default
        let metaDir = (pkmRoot as NSString).appendingPathComponent(".meta")
        if !fm.fileExists(atPath: metaDir) {
            try? fm.createDirectory(atPath: metaDir, withIntermediateDirectories: true)
        }
        let cache = FolderPairCache(
            version: Self.cacheVersion,
            noteIndexUpdated: noteIndexUpdated,
            relationsUpdated: relationsUpdated,
            candidates: candidates
        )
        guard let data = try? JSONEncoder().encode(cache) else { return }
        try? data.write(to: URL(fileURLWithPath: cachePath()), options: .atomic)
    }
}
