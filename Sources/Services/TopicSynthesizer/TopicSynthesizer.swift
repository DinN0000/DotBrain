import CryptoKit
import Foundation

/// Maintains AI-synthesized topic wiki pages (_Wiki/<name>.md marker section).
/// One sendPrecise call per changed topic; unchanged topics are skipped by
/// comparing the members hash stored inside the marker section.
/// Mirrors FolderSynthesizer.
struct TopicSynthesizer: Sendable {
    let pkmRoot: String

    static let changedBodyBytes = 8192
    static let maxChangedBodies = 5
    static let timelineCap = 20

    /// Resynthesize the given topics. changedNotePaths are vault-relative
    /// paths whose bodies changed this run (fed to the prompt in full).
    /// Returns absolute paths of pages actually written.
    func synthesize(topicIds: [String], changedNotePaths: Set<String>) async -> [String] {
        guard !topicIds.isEmpty else { return [] }
        let store = TopicStore(pkmRoot: pkmRoot)
        let pathManager = PKMPathManager(root: pkmRoot)
        guard let noteIndex = pathManager.loadNoteIndex() else { return [] }
        let fm = FileManager.default
        var written: [String] = []

        for topicId in topicIds.sorted() {
            if Task.isCancelled { break }
            guard var topic = store.topic(id: topicId), !store.isTombstoned(topicId) else { continue }

            let memberEntries = topic.members.compactMap { noteIndex.notes[$0] }
            guard !memberEntries.isEmpty else { continue }

            let pagePath = (pkmRoot as NSString).appendingPathComponent(topic.pagePath)
            guard pathManager.isPathSafe(pagePath) else { continue }

            let existing = try? String(contentsOfFile: pagePath, encoding: .utf8)
            let hash = Self.inputsHash(members: memberEntries)
            if let existing, TopicPage.inputsHash(from: existing) == hash { continue }

            let previous = existing.flatMap { TopicPage.synthesisSection(from: $0) }
            let changed = memberEntries
                .filter { changedNotePaths.contains($0.path) }
                .prefix(Self.maxChangedBodies)
                .compactMap { entry -> (name: String, body: String)? in
                    let abs = (pkmRoot as NSString).appendingPathComponent(entry.path)
                    guard let body = NoteExcerptReader.read(abs, maxBytes: Self.changedBodyBytes) else {
                        return nil
                    }
                    let name = ((entry.path as NSString).lastPathComponent as NSString)
                        .deletingPathExtension
                    return (name: name, body: body)
                }

            let prompt = Self.buildPrompt(
                topic: topic, previousSynthesis: previous,
                changedNotes: Array(changed), members: memberEntries,
                today: Frontmatter.today()
            )

            do {
                let response = try await AIService.shared.sendPreciseWithUsage(
                    maxTokens: 2048, message: prompt)
                if let usage = response.usage {
                    let model = await AIService.shared.preciseModel
                    StatisticsService.logTokenUsage(operation: "topic-synthesis", model: model,
                                                    usage: usage, isEstimated: response.isEstimated)
                }
                let synthesis = Self.stripCodeBlock(response.text)
                // Malformed output would blank the page — keep the previous
                // synthesis instead (never blank)
                guard Self.isValidSynthesis(synthesis) else {
                    NSLog("[TopicSynthesizer] 형식 불량, 이전 합성 유지: %@", topic.id)
                    continue
                }

                let wikiDir = (pkmRoot as NSString).appendingPathComponent("_Wiki")
                if !fm.fileExists(atPath: wikiDir) {
                    try fm.createDirectory(atPath: wikiDir, withIntermediateDirectories: true)
                }
                let updated = TopicPage.replacingSynthesis(
                    in: existing, synthesis: synthesis,
                    inputsHash: hash, topicId: topic.id
                )
                try updated.write(toFile: pagePath, atomically: true, encoding: .utf8)
                written.append(pagePath)

                // Harvest the fresh understanding back into the store — the
                // compounding loop: page feeds the catalog feeds future matching
                topic.membersHash = hash
                topic.summary = TopicPage.currentUnderstanding(from: updated) ?? topic.summary
                topic.lastSynthesized = Frontmatter.today()
                store.upsert(topic)
            } catch {
                // Keep the previous synthesis on any failure; membersHash stays
                // stale so the next run retries automatically
                NSLog("[TopicSynthesizer] 합성 실패: %@ — %@", topic.id, error.localizedDescription)
            }
        }
        return written
    }

    // MARK: - Pure helpers

    /// Order-independent hash over member metadata (same shape as
    /// FolderSynthesizer.inputsHash) — unchanged members skip the AI call
    static func inputsHash(members: [NoteIndexEntry]) -> String {
        let lines = members
            .map { entry in
                let tags = entry.tags.joined(separator: ",")
                return "\(entry.path)|\(entry.summary)|\(entry.status ?? "")|\(tags)"
            }
            .sorted()
            .joined(separator: "\n")
        let digest = SHA256.hash(data: Data(lines.utf8))
        return digest.map { String(format: "%02x", $0) }.joined()
    }

    /// Every section the prompt promises. Each carries a distinct compounding
    /// artifact — 모순 (contradictions), 노후 (superseded claims), 타임라인
    /// (evolution). The prompt tells the AI to emit all of them (with a "없음"
    /// placeholder when empty), so a response missing any header dropped
    /// structure and is rejected — we keep the previous page rather than let
    /// contradictions/timeline silently vanish on the next round-trip.
    static let requiredSections = [
        "## 현재 이해", "## 모순", "## 노후", "## 타임라인", "## 멤버 노트",
    ]

    static func isValidSynthesis(_ text: String) -> Bool {
        requiredSections.allSatisfy { text.contains($0) }
    }

    static func buildPrompt(
        topic: Topic,
        previousSynthesis: String?,
        changedNotes: [(name: String, body: String)],
        members: [NoteIndexEntry],
        today: String
    ) -> String {
        let memberLines = members.map { entry in
            let name = ((entry.path as NSString).lastPathComponent as NSString).deletingPathExtension
            let status = entry.status.map { " [\($0)]" } ?? ""
            let summary = entry.summary.isEmpty ? "요약 없음" : entry.summary
            return "- \(name)\(status) — \(summary)"
        }.joined(separator: "\n")

        let previousSection = previousSynthesis.map {
            "\n## 이전 합성 (기준선 — 이 이해를 새 정보로 갱신)\n\($0)\n"
        } ?? "\n## 이전 합성\n(없음 — 첫 합성)\n"

        let changedSection = changedNotes.isEmpty ? "(없음 — 멤버 목록 변경만 반영)" :
            changedNotes.map { "### \($0.name)\n\($0.body)" }.joined(separator: "\n\n")

        return """
        PKM 볼트의 주제 "\(topic.name)" 위키 페이지 본문을 갱신하세요. 오늘 날짜: \(today)

        ## 멤버 노트 목록
        \(memberLines)
        \(previousSection)
        ## 새로 반영할 노트 본문
        \(changedSection)

        ## 출력 형식 (마크다운, 이 구조 그대로)
        ## 현재 이해
        (멤버 노트 전체를 종합한 최신 이해, 2~6문단. 이전 합성을 새 본문으로 revise)

        ## 모순
        (새 본문이 이전 합성이나 다른 노트와 상충하는 지점. 형식: - [[노트A]] vs [[노트B]]: 상충 내용. 없으면 "- 감지된 모순 없음")

        ## 노후
        (새 정보로 사실상 대체된 노트. 형식: - [[옛노트]]: [[새노트]]에 의해 대체됨 (\(today)). 없으면 "- 없음")

        ## 타임라인
        (이전 합성의 타임라인 항목을 그대로 유지하고, 이번 갱신 항목을 맨 위에 추가. 형식: - \(today): 변경 요지. 최근 \(timelineCap)개까지만)

        ## 멤버 노트
        (형식: - [[정확한 노트명]] — 이 주제에서의 역할)

        ## 규칙
        1. 노트명은 위 멤버 노트 목록의 이름을 글자 그대로 사용 (창작 금지)
        2. 한국어로 작성, 이모지 금지
        3. 출력 형식 외의 다른 섹션이나 설명은 추가하지 않음
        4. 모순·노후는 실제 내용 충돌이 있을 때만 기록 — 억지로 만들지 않음
        """
    }

    static func stripCodeBlock(_ text: String) -> String {
        text
            .replacingOccurrences(of: #"^```(?:markdown|md)?\s*\n?"#, with: "", options: .regularExpression)
            .replacingOccurrences(of: #"\n?```\s*$"#, with: "", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
