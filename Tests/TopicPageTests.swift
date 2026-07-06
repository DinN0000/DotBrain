import XCTest
@testable import DotBrain

final class TopicPageTests: XCTestCase {

    private let sampleSynthesis = """
    ## 현재 이해
    Swift 동시성의 actor 격리 모델에 대한 통합 이해.

    ## 모순
    - 감지된 모순 없음

    ## 노후
    - 없음

    ## 타임라인
    - 2026-07-06: [[actor-정리]] 반영

    ## 멤버 노트
    - [[actor-정리]] — 기초 개념
    """

    func testCreatesNewPageWithFrontmatterMarkersAndTopicId() {
        let content = TopicPage.replacingSynthesis(
            in: nil, synthesis: sampleSynthesis,
            inputsHash: "abc123", topicId: "swift-concurrency"
        )
        XCTAssertTrue(content.hasPrefix("---\n"), "new page needs frontmatter")
        XCTAssertTrue(content.contains(TopicPage.markerStart))
        XCTAssertTrue(content.contains(TopicPage.markerEnd))
        XCTAssertTrue(content.contains("dotbrain-topic: swift-concurrency"))
        XCTAssertTrue(content.contains("dotbrain-synthesis-hash: abc123"))
    }

    func testUpdatePreservesUserContentOutsideMarkers() {
        let existing = TopicPage.replacingSynthesis(
            in: nil, synthesis: sampleSynthesis,
            inputsHash: "old", topicId: "t"
        ) + "\n내가 직접 쓴 메모는 남아야 한다.\n"
        let updated = TopicPage.replacingSynthesis(
            in: existing, synthesis: "## 현재 이해\n갱신된 이해.",
            inputsHash: "new", topicId: "t"
        )
        XCTAssertTrue(updated.contains("갱신된 이해."))
        // Old synthesis must be gone from the marker section; the frontmatter
        // summary written at creation is outside the markers and is preserved
        XCTAssertFalse(TopicPage.synthesisSection(from: updated)!.contains("actor 격리 모델"))
        XCTAssertTrue(updated.contains("내가 직접 쓴 메모는 남아야 한다."))
        XCTAssertTrue(updated.contains("dotbrain-synthesis-hash: new"))
    }

    func testExtractsTopicIdAndHash() {
        let content = TopicPage.replacingSynthesis(
            in: nil, synthesis: sampleSynthesis, inputsHash: "xyz", topicId: "my-topic"
        )
        XCTAssertEqual(TopicPage.topicId(from: content), "my-topic")
        XCTAssertEqual(TopicPage.inputsHash(from: content), "xyz")
        XCTAssertNil(TopicPage.topicId(from: "no markers"))
        XCTAssertNil(TopicPage.inputsHash(from: "no markers"))
    }

    func testExtractsCurrentUnderstandingFirstParagraph() {
        let content = TopicPage.replacingSynthesis(
            in: nil, synthesis: sampleSynthesis, inputsHash: "h", topicId: "t"
        )
        XCTAssertEqual(
            TopicPage.currentUnderstanding(from: content),
            "Swift 동시성의 actor 격리 모델에 대한 통합 이해."
        )
    }

    func testExtractsSynthesisSectionWithoutCommentLines() {
        let content = TopicPage.replacingSynthesis(
            in: nil, synthesis: sampleSynthesis, inputsHash: "h", topicId: "t"
        )
        let section = TopicPage.synthesisSection(from: content)
        XCTAssertNotNil(section)
        XCTAssertTrue(section!.contains("## 현재 이해"))
        XCTAssertTrue(section!.contains("## 타임라인"))
        XCTAssertFalse(section!.contains("dotbrain-synthesis-hash"))
        XCTAssertFalse(section!.contains(TopicPage.markerStart))
    }
}
