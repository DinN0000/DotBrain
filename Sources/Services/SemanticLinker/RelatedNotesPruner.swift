import Foundation

/// Link diet: Related Notes accumulate across linker runs (forward + reverse
/// + hub writes) with no ceiling, which degrades navigation signal over time.
/// During vault check, notes over the cumulative cap get their DotBrain-owned
/// entries re-selected down to the most valuable `cumulativeCap` via the fast
/// model. Sections containing user-authored content are never touched
/// (RelatedNotesWriter.replaceEntries refuses them).
struct RelatedNotesPruner: Sendable {
    let pkmRoot: String

    static let cumulativeCap = 12
    private let batchSize = 5
    private let maxConcurrentAI = 3
    private let aiService = AIService.shared

    struct PruneInput: Sendable {
        let name: String
        let filePath: String
        let summary: String
    }

    struct Result: Sendable {
        var prunedNotes = 0
        var removedLinks = 0
        var modifiedFiles: Set<String> = []

        mutating func merge(_ other: Result) {
            prunedNotes += other.prunedNotes
            removedLinks += other.removedLinks
            modifiedFiles.formUnion(other.modifiedFiles)
        }
    }

    /// Inspect candidate notes and prune over-cap sections. Candidates that
    /// turn out to be under the cap or user-touched are skipped cheaply.
    func pruneAll(candidates: [PruneInput]) async -> Result {
        var result = Result()
        guard !candidates.isEmpty else { return result }

        let writer = RelatedNotesWriter()

        // Re-read and parse each candidate. Duplicate-name lines (same-named
        // notes in different folders, historical accumulation) are deduped
        // first-wins: dup-only notes get rewritten without an AI call, and
        // only genuinely over-cap sections go to AI re-selection.
        var targets: [(input: PruneInput, entries: [RelatedNotesWriter.Entry])] = []
        for candidate in candidates {
            guard let content = try? String(contentsOfFile: candidate.filePath, encoding: .utf8),
                  let parsed = writer.parseRelatedNotes(content),
                  !parsed.hasUnrecognized else { continue }
            var seen = Set<String>()
            let deduped = parsed.entries.filter { seen.insert($0.name).inserted }
            if deduped.count > Self.cumulativeCap {
                targets.append((input: candidate, entries: deduped))
            } else if deduped.count < parsed.entries.count {
                result.merge(rewrite(candidate, entries: deduped,
                                     originalCount: parsed.entries.count, writer: writer))
            }
        }
        guard !targets.isEmpty else { return result }

        NSLog("[RelatedNotesPruner] %d개 노트가 링크 %d개 상한 초과 — 재선별 시작",
              targets.count, Self.cumulativeCap)

        let batches = stride(from: 0, to: targets.count, by: batchSize).map {
            Array(targets[$0..<min($0 + batchSize, targets.count)])
        }

        // Batch-AI pattern: TaskGroup capped at maxConcurrentAI. Batches
        // partition targets, so concurrent tasks write distinct files.
        await withTaskGroup(of: Result.self) { group in
            var activeTasks = 0
            for batch in batches {
                if activeTasks >= maxConcurrentAI {
                    if let partial = await group.next() {
                        result.merge(partial)
                        activeTasks -= 1
                    }
                }
                group.addTask {
                    await pruneBatch(batch, writer: writer)
                }
                activeTasks += 1
            }
            for await partial in group {
                result.merge(partial)
            }
        }

        return result
    }

    private func pruneBatch(
        _ batch: [(input: PruneInput, entries: [RelatedNotesWriter.Entry])],
        writer: RelatedNotesWriter
    ) async -> Result {
        var result = Result()
        let keptSets = await selectKept(batch: batch)
        for (item, kept) in zip(batch, keptSets) {
            // Preserve original file order among kept entries
            let keptEntries = item.entries.enumerated()
                .filter { kept.contains($0.offset) }
                .map { $0.element }
            result.merge(rewrite(item.input, entries: keptEntries,
                                 originalCount: item.entries.count, writer: writer))
        }
        return result
    }

    /// Rewrite one note's section to exactly `entries`; no-ops (identical
    /// content, empty entries, user-authored sections) are handled by
    /// replaceEntries returning false.
    private func rewrite(
        _ input: PruneInput,
        entries: [RelatedNotesWriter.Entry],
        originalCount: Int,
        writer: RelatedNotesWriter
    ) -> Result {
        var result = Result()
        do {
            if try writer.replaceEntries(filePath: input.filePath, entries: entries) {
                result.prunedNotes += 1
                result.removedLinks += originalCount - entries.count
                result.modifiedFiles.insert(input.filePath)
            }
        } catch {
            NSLog("[RelatedNotesPruner] 재선별 기록 실패: %@ — %@",
                  input.name, error.localizedDescription)
        }
        return result
    }

    // MARK: - Selection

    /// One fast-model call per batch; falls back to deterministic
    /// relation-priority ranking when the call or parsing fails.
    private func selectKept(
        batch: [(input: PruneInput, entries: [RelatedNotesWriter.Entry])]
    ) async -> [Set<Int>] {
        let prompt = Self.buildPrompt(batch: batch)
        do {
            let response = try await aiService.sendFastWithUsage(maxTokens: 2048, message: prompt)
            if let usage = response.usage {
                let model = await aiService.fastModel
                StatisticsService.logTokenUsage(operation: "link-prune", model: model, usage: usage, isEstimated: response.isEstimated)
            }
            return Self.parseResponse(response.text, batch: batch)
        } catch {
            NSLog("[RelatedNotesPruner] AI 재선별 실패, 우선순위 폴백 사용: %@", error.localizedDescription)
            return batch.map { Self.fallbackKept(entries: $0.entries) }
        }
    }

    static func buildPrompt(
        batch: [(input: PruneInput, entries: [RelatedNotesWriter.Entry])]
    ) -> String {
        let noteDescriptions = batch.enumerated().map { (i, item) in
            let entryList = item.entries.enumerated().map { (j, e) in
                "  [\(j)] \(e.name) — \(e.context) (\(RelatedNotesWriter.relationLabels[e.relation] ?? e.relation))"
            }.joined(separator: "\n")
            return """
            ### 노트 \(i): \(item.input.name)
            요약: \(item.input.summary.isEmpty ? "요약 없음" : item.input.summary)
            링크:
            \(entryList)
            """
        }.joined(separator: "\n\n")

        return """
        각 노트의 Related Notes에서 가장 가치 있는 링크만 남기세요. 노트당 최대 \(cumulativeCap)개.

        \(noteDescriptions)

        ## 규칙
        1. 기준: "이 링크를 따라가면 이 노트의 독자가 새로운 인사이트를 얻는가?"
        2. 중복 주제·범용 링크부터 제거, 동률이면 prerequisite > project > reference > related 우선
        3. keep에는 남길 링크의 index만 나열 (노트당 최대 \(cumulativeCap)개)

        ## 응답 (순수 JSON, 코드블록 없이)
        [{"noteIndex": 0, "keep": [0, 1, 3]}]
        """
    }

    static func parseResponse(
        _ text: String,
        batch: [(input: PruneInput, entries: [RelatedNotesWriter.Entry])]
    ) -> [Set<Int>] {
        let cleaned = LinkAIFilter.stripCodeBlock(text)

        var results = batch.map { Self.fallbackKept(entries: $0.entries) }

        guard let startBracket = cleaned.firstIndex(of: "["),
              let endBracket = cleaned.lastIndex(of: "]"),
              let data = String(cleaned[startBracket...endBracket]).data(using: .utf8) else {
            return results
        }

        struct NoteItem: Decodable { let noteIndex: Int; let keep: [Int]? }
        guard let items = try? JSONDecoder().decode([NoteItem].self, from: data) else {
            return results
        }

        for item in items {
            guard item.noteIndex >= 0, item.noteIndex < batch.count,
                  let keep = item.keep else { continue }
            let entryCount = batch[item.noteIndex].entries.count
            let valid = keep.filter { $0 >= 0 && $0 < entryCount }
            guard !valid.isEmpty else { continue }
            results[item.noteIndex] = Set(valid.prefix(cumulativeCap))
        }
        return results
    }

    /// Deterministic fallback: stable sort by relation priority, keep the
    /// first `cumulativeCap` (earlier entries are the more established links)
    static func fallbackKept(entries: [RelatedNotesWriter.Entry]) -> Set<Int> {
        func priority(_ relation: String) -> Int {
            RelatedNotesWriter.relationOrder.firstIndex(of: relation)
                ?? RelatedNotesWriter.relationOrder.count
        }
        let ranked = entries.enumerated().sorted { a, b in
            let pa = priority(a.element.relation)
            let pb = priority(b.element.relation)
            return pa == pb ? a.offset < b.offset : pa < pb
        }
        return Set(ranked.prefix(cumulativeCap).map { $0.offset })
    }
}
