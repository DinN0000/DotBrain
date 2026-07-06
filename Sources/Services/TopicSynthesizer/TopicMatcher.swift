import Foundation

// MARK: - AI response models

struct TopicMatchResponse: Codable {
    struct Assignment: Codable {
        let note: String       // vault-relative note path (verbatim from prompt)
        let topics: [String]   // existing topic ids
    }
    struct Proposal: Codable {
        let name: String
        let members: [String]
        let keywords: [String]
    }
    let assignments: [Assignment]
    let proposals: [Proposal]
}

struct TopicMatchOutcome: Sendable {
    let affectedTopicIds: [String]   // topics that gained members + newly created
    let createdTopicIds: [String]
}

// MARK: - Matcher

/// Assigns notes to topics: structural prefilter -> one sendFast call ->
/// code-level validation (hallucinated members dropped, member threshold,
/// tombstone check). Unmatched notes park in the unassigned pool.
struct TopicMatcher: Sendable {
    let pkmRoot: String

    static let newTopicMemberThreshold = 3
    static let candidateLimit = 20
    static let bodyExcerptBytes = 4096

    // MARK: - Pure helpers

    /// Lowercased, filename-safe slug. Korean letters are preserved
    /// (CharacterSet.alphanumerics includes Hangul).
    static func slug(from name: String) -> String {
        let lowered = name.precomposedStringWithCanonicalMapping.lowercased()
        var out = ""
        var lastWasDash = false
        for scalar in lowered.unicodeScalars {
            if CharacterSet.alphanumerics.contains(scalar) {
                out.unicodeScalars.append(scalar)
                lastWasDash = false
            } else if !lastWasDash && !out.isEmpty {
                out.append("-")
                lastWasDash = true
            }
        }
        if out.hasSuffix("-") { out.removeLast() }
        return out.isEmpty ? "topic" : out
    }

    /// Cheap structural prefilter: note tags + title tokens vs topic keywords.
    /// Zero-overlap topics are excluded; result capped at candidateLimit.
    static func candidateTopics(for entries: [NoteIndexEntry], topics: [Topic]) -> [Topic] {
        guard !topics.isEmpty, !entries.isEmpty else { return [] }
        var noteTokens = Set<String>()
        for entry in entries {
            for tag in entry.tags { noteTokens.insert(tag.lowercased()) }
            let stem = (((entry.path as NSString).lastPathComponent) as NSString).deletingPathExtension
            for token in stem.split(whereSeparator: { !$0.isLetter && !$0.isNumber }) {
                noteTokens.insert(token.lowercased())
            }
        }
        let scored = topics.compactMap { topic -> (Topic, Int)? in
            let overlap = topic.keywords.filter { noteTokens.contains($0.lowercased()) }.count
            return overlap > 0 ? (topic, overlap) : nil
        }
        return scored.sorted { $0.1 > $1.1 }.prefix(candidateLimit).map { $0.0 }
    }

    /// Code-level guardrails for AI proposals: members must exist in the note
    /// index (hallucination filter), survive the threshold, and the slug must
    /// not collide with a live or tombstoned topic.
    static func validateProposals(
        _ proposals: [TopicMatchResponse.Proposal],
        existingNotePaths: Set<String>,
        existingTopicIds: Set<String>,
        deletedTopicIds: Set<String>
    ) -> [TopicMatchResponse.Proposal] {
        proposals.compactMap { proposal in
            let id = slug(from: proposal.name)
            guard !deletedTopicIds.contains(id), !existingTopicIds.contains(id) else { return nil }
            let realMembers = proposal.members.filter { existingNotePaths.contains($0) }
            guard realMembers.count >= newTopicMemberThreshold else { return nil }
            return TopicMatchResponse.Proposal(
                name: proposal.name, members: realMembers, keywords: proposal.keywords
            )
        }
    }

    static func parseResponse(_ text: String) -> TopicMatchResponse? {
        guard let start = text.firstIndex(of: "{"),
              let end = text.lastIndex(of: "}"), start < end else { return nil }
        return try? JSONDecoder().decode(TopicMatchResponse.self, from: Data(text[start...end].utf8))
    }

    static func buildPrompt(
        newNotes: [(path: String, summary: String, excerpt: String)],
        candidates: [Topic],
        unassigned: [(path: String, summary: String)]
    ) -> String {
        let topicLines = candidates.isEmpty ? "(없음)" : candidates.map {
            "- id: \($0.id) | 이름: \($0.name) | 키워드: \($0.keywords.joined(separator: ", ")) | 요약: \($0.summary)"
        }.joined(separator: "\n")
        let noteBlocks = newNotes.isEmpty ? "(없음)" : newNotes.map {
            "### \($0.path)\n요약: \($0.summary)\n본문 발췌:\n\($0.excerpt)"
        }.joined(separator: "\n\n")
        let poolLines = unassigned.isEmpty ? "(없음)" : unassigned.map {
            "- \($0.path) — \($0.summary)"
        }.joined(separator: "\n")

        return """
        PKM 볼트의 주제(topic) 배정을 수행하세요.

        ## 기존 주제 후보
        \(topicLines)

        ## 새 노트
        \(noteBlocks)

        ## 미배정 노트 풀
        \(poolLines)

        ## 규칙
        1. 새 노트가 기존 주제와 실질적으로 같은 대상을 다루면 그 주제 id에 배정
        2. 기존 주제에 맞지 않아도, 새 노트와 미배정 풀을 합쳐 같은 주제의 노트가 \(newTopicMemberThreshold)개 이상 모이면 신규 주제를 제안
        3. 확신이 없으면 배정하지 않음 — 과잉 배정 금지
        4. 노트 경로와 주제 id는 위 목록의 문자열을 글자 그대로 사용 (창작 금지)
        5. 아래 JSON 형식만 출력 (설명 금지):
        {"assignments":[{"note":"<노트 경로>","topics":["<주제 id>"]}],"proposals":[{"name":"<주제명>","members":["<노트 경로>"],"keywords":["<키워드>"]}]}
        """
    }
}
