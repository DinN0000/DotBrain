import Foundation

struct LinkAIFilter: Sendable {
    private let aiService = AIService.shared

    struct FilteredLink {
        let name: String
        let context: String
        let relation: String  // prerequisite, project, reference, related
    }

    func filterBatch(
        notes: [(name: String, summary: String, tags: [String], candidates: [LinkCandidateGenerator.Candidate])],
        maxResultsPerNote: Int = 15,
        folderHintContext: String = ""
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

        let folderHintSection = folderHintContext.isEmpty ? "" : "\n\(folderHintContext)\n"

        let prompt = """
        각 노트에 대해 진짜 관련있는 후보를 모두 선택하세요.

        \(noteDescriptions)
        \(folderHintSection)
        ## 규칙
        1. 핵심 기준: "이 연결을 따라가면 새로운 인사이트를 얻을 수 있는가?"
        2. 단순히 같은 주제라서가 아니라, 실제로 함께 읽을 가치가 있는 문서만 선택
        3. context: "~하려면", "~할 때", "~와 비교할 때" 형식 (한국어, 15자 이내)
        4. 관련 없는 후보는 반드시 제외
        5. relation: 관계 유형을 하나 선택
           - "prerequisite": 이해하려면 먼저 봐야 하는 문서
           - "project": 같은 프로젝트/업무 관련
           - "reference": 참고/비교할 수 있는 자료
           - "related": 주제가 비슷한 문서

        ## 응답 (순수 JSON, 코드블록 없이)
        [{"noteIndex": 0, "links": [{"index": 0, "context": "~하려면 참고", "relation": "reference"}]}]
        """

        let response = try await aiService.sendFastWithUsage(message: prompt)
        if let usage = response.usage {
            let model = await aiService.fastModel
            StatisticsService.logTokenUsage(operation: "semantic-link", model: model, usage: usage)
        }

        return parseBatchResponse(response.text, notes: notes, maxResultsPerNote: maxResultsPerNote)
    }

    func filterSingle(
        noteName: String,
        noteSummary: String,
        noteTags: [String],
        candidates: [LinkCandidateGenerator.Candidate],
        maxResults: Int = 15
    ) async throws -> [FilteredLink] {
        guard !candidates.isEmpty else { return [] }

        let candidateList = candidates.enumerated().map { (i, c) in
            "[\(i)] \(c.name) — 태그: \(c.tags.joined(separator: ", ")) — \(c.summary)"
        }.joined(separator: "\n")

        let prompt = """
        다음 노트와 진짜 관련있는 후보를 모두 선택하고, 각각 연결 이유를 작성하세요.

        노트: \(noteName)
        태그: \(noteTags.joined(separator: ", "))
        요약: \(noteSummary)

        ## 후보 목록
        \(candidateList)

        ## 규칙
        1. 핵심 기준: "이 연결을 따라가면 새로운 인사이트를 얻을 수 있는가?"
        2. 단순히 같은 주제라서가 아니라, 실제로 함께 읽을 가치가 있는 문서만 선택
        3. context: "~하려면", "~할 때", "~와 비교할 때" 형식 (한국어, 15자 이내)
        4. 관련 없는 후보는 반드시 제외
        5. relation: 관계 유형을 하나 선택
           - "prerequisite": 이해하려면 먼저 봐야 하는 문서
           - "project": 같은 프로젝트/업무 관련
           - "reference": 참고/비교할 수 있는 자료
           - "related": 주제가 비슷한 문서

        ## 응답 (순수 JSON, 코드블록 없이)
        [{"index": 0, "context": "~하려면 참고", "relation": "reference"}]
        """

        let response = try await aiService.sendFastWithUsage(message: prompt)
        if let usage = response.usage {
            let model = await aiService.fastModel
            StatisticsService.logTokenUsage(operation: "semantic-link", model: model, usage: usage)
        }

        return parseSingleResponse(response.text, candidates: candidates, maxResults: maxResults)
    }

    // MARK: - Context-Only Generation (same-folder auto-link)

    struct SiblingInfo {
        let name: String
        let summary: String
        let tags: [String]
    }

    func generateContextOnly(
        notes: [(name: String, summary: String, tags: [String], siblings: [SiblingInfo])]
    ) async throws -> [[FilteredLink]] {
        guard !notes.isEmpty else { return [] }

        let noteDescriptions = notes.enumerated().map { (i, note) in
            let siblingList = note.siblings.enumerated().map { (j, s) in
                "  [\(j)] \(s.name) — \(s.tags.prefix(3).joined(separator: ", ")) — \(s.summary)"
            }.joined(separator: "\n")

            return """
            ### 노트 \(i): \(note.name)
            태그: \(note.tags.joined(separator: ", "))
            요약: \(note.summary)
            형제:
            \(siblingList)
            """
        }.joined(separator: "\n\n")

        let prompt = """
        다음 노트들은 같은 폴더에 있는 문서입니다.
        각 노트의 형제 노트에 대해 연결 맥락을 작성하세요.

        \(noteDescriptions)

        ## 규칙
        1. 모든 형제에 대해 반드시 context를 작성 (건너뛰기 불가)
        2. context: "~하려면", "~할 때", "~와 비교할 때" 형식 (한국어, 15자 이내)
        3. relation: prerequisite / project / reference / related 중 하나

        ## 응답 (순수 JSON, 코드블록 없이)
        [{"noteIndex": 0, "links": [{"index": 0, "context": "~할 때 참고", "relation": "project"}]}]
        """

        let response = try await aiService.sendFast(maxTokens: 2048, message: prompt)
        StatisticsService.addApiCost(Double(notes.count) * 0.0003)

        return parseContextOnlyResponse(response, notes: notes)
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

        struct Item: Decodable { let index: Int; let context: String?; let relation: String? }

        guard let items = try? JSONDecoder().decode([Item].self, from: data) else { return [] }

        return items.prefix(maxResults).compactMap { item in
            guard item.index >= 0, item.index < candidates.count else { return nil }
            return FilteredLink(
                name: candidates[item.index].name,
                context: item.context ?? "관련 문서",
                relation: Self.validRelation(item.relation)
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

        struct LinkItem: Decodable { let index: Int; let context: String?; let relation: String? }
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
                    context: link.context ?? "관련 문서",
                    relation: Self.validRelation(link.relation)
                )
            }
            results[item.noteIndex] = links
        }
        return results
    }

    private func parseContextOnlyResponse(
        _ text: String,
        notes: [(name: String, summary: String, tags: [String], siblings: [SiblingInfo])]
    ) -> [[FilteredLink]] {
        let cleaned = stripCodeBlock(text)

        guard let startBracket = cleaned.firstIndex(of: "["),
              let endBracket = cleaned.lastIndex(of: "]") else {
            // Fallback: generate default context for all siblings
            return notes.map { note in
                note.siblings.map { FilteredLink(name: $0.name, context: "같은 폴더 문서", relation: "related") }
            }
        }

        let jsonStr = String(cleaned[startBracket...endBracket])
        guard let data = jsonStr.data(using: .utf8) else {
            return notes.map { note in
                note.siblings.map { FilteredLink(name: $0.name, context: "같은 폴더 문서", relation: "related") }
            }
        }

        struct LinkItem: Decodable { let index: Int; let context: String?; let relation: String? }
        struct NoteItem: Decodable { let noteIndex: Int; let links: [LinkItem]? }

        guard let items = try? JSONDecoder().decode([NoteItem].self, from: data) else {
            return notes.map { note in
                note.siblings.map { FilteredLink(name: $0.name, context: "같은 폴더 문서", relation: "related") }
            }
        }

        var results: [[FilteredLink]] = notes.map { note in
            // Default: all siblings with fallback context
            note.siblings.map { FilteredLink(name: $0.name, context: "같은 폴더 문서", relation: "related") }
        }

        for item in items {
            guard item.noteIndex >= 0, item.noteIndex < notes.count else { continue }
            let siblings = notes[item.noteIndex].siblings
            guard let links = item.links else { continue }

            var merged = results[item.noteIndex]
            for link in links {
                guard link.index >= 0, link.index < siblings.count else { continue }
                // Overwrite fallback with AI-generated context
                merged[link.index] = FilteredLink(
                    name: siblings[link.index].name,
                    context: link.context ?? "같은 폴더 문서",
                    relation: Self.validRelation(link.relation)
                )
            }
            results[item.noteIndex] = merged
        }

        return results
    }

    private static let validRelations: Set<String> = ["prerequisite", "project", "reference", "related"]

    private static func validRelation(_ raw: String?) -> String {
        guard let raw = raw, validRelations.contains(raw) else { return "related" }
        return raw
    }

    private func stripCodeBlock(_ text: String) -> String {
        text
            .replacingOccurrences(of: #"^```(?:json)?\s*\n?"#, with: "", options: .regularExpression)
            .replacingOccurrences(of: #"\n?```\s*$"#, with: "", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
