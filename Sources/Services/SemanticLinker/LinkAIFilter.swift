import Foundation

struct LinkAIFilter: Sendable {
    private let aiService = AIService.shared

    struct FilteredLink {
        let name: String
        let context: String
    }

    func filterBatch(
        notes: [(name: String, summary: String, tags: [String], candidates: [LinkCandidateGenerator.Candidate])],
        maxResultsPerNote: Int = 5
    ) async throws -> [[FilteredLink]] {
        guard !notes.isEmpty else { return [] }

        let noteDescriptions = notes.enumerated().map { (i, note) in
            let candidateList = note.candidates.enumerated().map { (j, c) in
                "  [\(j)] \(c.name) — \(c.tags.prefix(3).joined(separator: ", ")) — \(c.summary)"
            }.joined(separator: "\n")

            return """
            ### 노트 \(i): \(note.name)
            태그: \(note.tags.joined(separator: ", "))
            요약: \(note.summary)
            후보:
            \(candidateList)
            """
        }.joined(separator: "\n\n")

        let prompt = """
        각 노트에 대해 가장 관련 깊은 후보를 최대 \(maxResultsPerNote)개씩 선택하세요.

        \(noteDescriptions)

        ## 규칙
        1. 실질적 맥락 연관성 기준 선택 (단순 태그 일치 불충분)
        2. context: "~하려면", "~할 때", "~와 비교할 때" 형식 (한국어, 15자 이내)
        3. 관련 없는 후보 제외

        ## 응답 (순수 JSON, 코드블록 없이)
        [{"noteIndex": 0, "links": [{"index": 0, "context": "~하려면 참고"}]}]
        """

        let response = try await aiService.sendFast(maxTokens: 2048, message: prompt)
        StatisticsService.addApiCost(Double(notes.count) * 0.0005)

        return parseBatchResponse(response, notes: notes, maxResultsPerNote: maxResultsPerNote)
    }

    func filterSingle(
        noteName: String,
        noteSummary: String,
        noteTags: [String],
        candidates: [LinkCandidateGenerator.Candidate],
        maxResults: Int = 5
    ) async throws -> [FilteredLink] {
        guard !candidates.isEmpty else { return [] }

        let candidateList = candidates.enumerated().map { (i, c) in
            "[\(i)] \(c.name) — 태그: \(c.tags.joined(separator: ", ")) — \(c.summary)"
        }.joined(separator: "\n")

        let prompt = """
        다음 노트와 가장 관련이 깊은 후보를 최대 \(maxResults)개 선택하고, 각각 연결 이유를 작성하세요.

        노트: \(noteName)
        태그: \(noteTags.joined(separator: ", "))
        요약: \(noteSummary)

        ## 후보 목록
        \(candidateList)

        ## 규칙
        1. 단순 태그 일치가 아닌 실질적 맥락 연관성 기준
        2. context는 "~하려면", "~할 때", "~와 비교할 때" 형식 (한국어, 15자 이내)
        3. 관련 없는 후보는 제외

        ## 응답 (순수 JSON, 코드블록 없이)
        [{"index": 0, "context": "~하려면 참고"}]
        """

        let response = try await aiService.sendFast(maxTokens: 512, message: prompt)
        StatisticsService.addApiCost(0.0005)

        return parseSingleResponse(response, candidates: candidates, maxResults: maxResults)
    }

    // MARK: - Parsing

    private func parseSingleResponse(
        _ text: String,
        candidates: [LinkCandidateGenerator.Candidate],
        maxResults: Int
    ) -> [FilteredLink] {
        let cleaned = stripCodeBlock(text)

        guard let startBracket = cleaned.firstIndex(of: "["),
              let endBracket = cleaned.lastIndex(of: "]") else { return [] }

        let jsonStr = String(cleaned[startBracket...endBracket])
        guard let data = jsonStr.data(using: .utf8) else { return [] }

        struct Item: Decodable { let index: Int; let context: String? }

        guard let items = try? JSONDecoder().decode([Item].self, from: data) else { return [] }

        return items.prefix(maxResults).compactMap { item in
            guard item.index >= 0, item.index < candidates.count else { return nil }
            return FilteredLink(
                name: candidates[item.index].name,
                context: item.context ?? "관련 문서"
            )
        }
    }

    private func parseBatchResponse(
        _ text: String,
        notes: [(name: String, summary: String, tags: [String], candidates: [LinkCandidateGenerator.Candidate])],
        maxResultsPerNote: Int
    ) -> [[FilteredLink]] {
        let cleaned = stripCodeBlock(text)

        guard let startBracket = cleaned.firstIndex(of: "["),
              let endBracket = cleaned.lastIndex(of: "]") else {
            return Array(repeating: [], count: notes.count)
        }

        let jsonStr = String(cleaned[startBracket...endBracket])
        guard let data = jsonStr.data(using: .utf8) else {
            return Array(repeating: [], count: notes.count)
        }

        struct LinkItem: Decodable { let index: Int; let context: String? }
        struct NoteItem: Decodable { let noteIndex: Int; let links: [LinkItem]? }

        guard let items = try? JSONDecoder().decode([NoteItem].self, from: data) else {
            return Array(repeating: [], count: notes.count)
        }

        var results = Array(repeating: [FilteredLink](), count: notes.count)
        for item in items {
            guard item.noteIndex >= 0, item.noteIndex < notes.count else { continue }
            let candidates = notes[item.noteIndex].candidates
            let links = (item.links ?? []).prefix(maxResultsPerNote).compactMap { link -> FilteredLink? in
                guard link.index >= 0, link.index < candidates.count else { return nil }
                return FilteredLink(
                    name: candidates[link.index].name,
                    context: link.context ?? "관련 문서"
                )
            }
            results[item.noteIndex] = links
        }
        return results
    }

    private func stripCodeBlock(_ text: String) -> String {
        text
            .replacingOccurrences(of: #"^```(?:json)?\s*\n?"#, with: "", options: .regularExpression)
            .replacingOccurrences(of: #"\n?```\s*$"#, with: "", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
