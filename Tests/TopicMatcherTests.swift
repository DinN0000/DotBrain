import XCTest
@testable import DotBrain

final class TopicMatcherTests: XCTestCase {

    private func makeEntry(path: String, tags: [String]) -> NoteIndexEntry {
        NoteIndexEntry(path: path, folder: (path as NSString).deletingLastPathComponent,
                       para: "2_Area", tags: tags, summary: "요약",
                       project: nil, status: nil, area: nil)
    }

    private func makeTopic(id: String, keywords: [String]) -> Topic {
        Topic(id: id, name: id, pagePath: "_Wiki/\(id).md", members: [],
              keywords: keywords, summary: "", membersHash: "",
              created: "2026-07-06", lastSynthesized: nil)
    }

    // MARK: slug

    func testSlugNormalizesEnglishKoreanAndSpecials() {
        XCTAssertEqual(TopicMatcher.slug(from: "Swift Concurrency"), "swift-concurrency")
        XCTAssertEqual(TopicMatcher.slug(from: "액터 격리!!"), "액터-격리")
        XCTAssertEqual(TopicMatcher.slug(from: "  A/B  Test  "), "a-b-test")
        XCTAssertEqual(TopicMatcher.slug(from: "!!!"), "topic")
    }

    // MARK: prefilter

    func testCandidateTopicsScoresByKeywordOverlapAndExcludesZero() {
        let topics = [
            makeTopic(id: "swift", keywords: ["swift", "actor"]),
            makeTopic(id: "cooking", keywords: ["recipe"]),
            makeTopic(id: "concurrency", keywords: ["actor", "async", "동시성"]),
        ]
        let entries = [makeEntry(path: "2_Area/dev/actor-async-정리.md", tags: ["동시성", "swift"])]
        let candidates = TopicMatcher.candidateTopics(for: entries, topics: topics)
        XCTAssertEqual(candidates.map(\.id), ["concurrency", "swift"], "높은 중첩 우선, 무중첩 제외")
    }

    // MARK: proposal validation

    func testValidateProposalsDropsHallucinatedMembersAndEnforcesThreshold() {
        let proposals = [
            TopicMatchResponse.Proposal(name: "Real Topic",
                                        members: ["a.md", "b.md", "c.md", "ghost.md"],
                                        keywords: ["k"]),
            TopicMatchResponse.Proposal(name: "Thin Topic",
                                        members: ["a.md", "b.md", "ghost.md"],
                                        keywords: []),
        ]
        let valid = TopicMatcher.validateProposals(
            proposals,
            existingNotePaths: ["a.md", "b.md", "c.md"],
            existingTopicIds: [], deletedTopicIds: []
        )
        XCTAssertEqual(valid.count, 1)
        XCTAssertEqual(valid[0].members, ["a.md", "b.md", "c.md"], "환각 멤버 탈락")
    }

    func testValidateProposalsRejectsTombstonedAndDuplicateIds() {
        let proposal = TopicMatchResponse.Proposal(
            name: "Dead Topic", members: ["a.md", "b.md", "c.md"], keywords: [])
        let notes: Set<String> = ["a.md", "b.md", "c.md"]
        XCTAssertTrue(TopicMatcher.validateProposals(
            [proposal], existingNotePaths: notes,
            existingTopicIds: [], deletedTopicIds: ["dead-topic"]).isEmpty)
        XCTAssertTrue(TopicMatcher.validateProposals(
            [proposal], existingNotePaths: notes,
            existingTopicIds: ["dead-topic"], deletedTopicIds: []).isEmpty)
    }

    func testValidateProposalsDeduplicatesSlugsWithinBatch() {
        let notes: Set<String> = ["a.md", "b.md", "c.md"]
        let proposals = [
            TopicMatchResponse.Proposal(name: "Swift Concurrency", members: Array(notes),
                                        keywords: []),
            TopicMatchResponse.Proposal(name: "Swift-Concurrency", members: Array(notes),
                                        keywords: []),
        ]
        let valid = TopicMatcher.validateProposals(
            proposals, existingNotePaths: notes,
            existingTopicIds: [], deletedTopicIds: [])
        XCTAssertEqual(valid.map(\.name), ["Swift Concurrency"], "동일 슬러그는 첫 제안만 생존")
    }

    // MARK: page name

    func testPageNameFlattensSlashesAndFallsBackToId() {
        let pm = PKMPathManager(root: "/tmp/vault")
        XCTAssertEqual(TopicMatcher.pageName(from: "CI/CD", id: "ci-cd", pathManager: pm),
                       "CI-CD", "슬래시는 단일 파일명 컴포넌트로 평탄화")
        XCTAssertEqual(TopicMatcher.pageName(from: "Swift Concurrency", id: "swift-concurrency",
                                             pathManager: pm), "Swift Concurrency")
        XCTAssertEqual(TopicMatcher.pageName(from: "///", id: "topic", pathManager: pm),
                       "topic", "전부 소거되면 id로 폴백")
        XCTAssertEqual(TopicMatcher.pageName(from: "../..", id: "topic", pathManager: pm), "topic")
    }

    // MARK: response parsing

    func testParseResponseExtractsJsonFromProse() {
        let text = """
        분석 결과입니다:
        {"assignments":[{"note":"a.md","topics":["t1"]}],"proposals":[]}
        이상입니다.
        """
        let parsed = TopicMatcher.parseResponse(text)
        XCTAssertEqual(parsed?.assignments.first?.note, "a.md")
        XCTAssertEqual(parsed?.assignments.first?.topics, ["t1"])
        XCTAssertNil(TopicMatcher.parseResponse("JSON 없음"))
    }

    // MARK: prompt

    func testBuildPromptContainsNotesTopicsAndOutputSchema() {
        let prompt = TopicMatcher.buildPrompt(
            newNotes: [(path: "a.md", summary: "요약A", excerpt: "본문A")],
            candidates: [makeTopic(id: "t1", keywords: ["k"])],
            unassigned: [(path: "b.md", summary: "요약B")]
        )
        XCTAssertTrue(prompt.contains("a.md"))
        XCTAssertTrue(prompt.contains("본문A"))
        XCTAssertTrue(prompt.contains("id: t1"))
        XCTAssertTrue(prompt.contains("b.md"))
        XCTAssertTrue(prompt.contains("\"assignments\""))
    }
}
