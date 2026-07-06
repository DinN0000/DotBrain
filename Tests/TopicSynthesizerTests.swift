import XCTest
@testable import DotBrain

final class TopicSynthesizerTests: XCTestCase {

    private func makeEntry(path: String, summary: String = "요약",
                           status: String? = nil, tags: [String] = []) -> NoteIndexEntry {
        NoteIndexEntry(path: path, folder: "", para: "2_Area", tags: tags,
                       summary: summary, project: nil, status: status, area: nil)
    }

    private func makeTopic() -> Topic {
        Topic(id: "t", name: "T", pagePath: "_Wiki/T.md", members: ["a.md"],
              keywords: [], summary: "", membersHash: "",
              created: "2026-07-06", lastSynthesized: nil)
    }

    func testInputsHashIsOrderIndependentAndChangeSensitive() {
        let a = makeEntry(path: "a.md"), b = makeEntry(path: "b.md")
        XCTAssertEqual(TopicSynthesizer.inputsHash(members: [a, b]),
                       TopicSynthesizer.inputsHash(members: [b, a]))
        let bChanged = makeEntry(path: "b.md", summary: "다른 요약")
        XCTAssertNotEqual(TopicSynthesizer.inputsHash(members: [a, b]),
                          TopicSynthesizer.inputsHash(members: [a, bChanged]))
    }

    func testBuildPromptCarriesBaselineChangedBodiesAndFormat() {
        let prompt = TopicSynthesizer.buildPrompt(
            topic: makeTopic(),
            previousSynthesis: "## 현재 이해\n기존 이해 본문.",
            changedNotes: [(name: "새노트", body: "새 본문 내용")],
            members: [makeEntry(path: "a.md")],
            today: "2026-07-06"
        )
        XCTAssertTrue(prompt.contains("기존 이해 본문."), "이전 합성이 기준선으로 포함")
        XCTAssertTrue(prompt.contains("새 본문 내용"))
        XCTAssertTrue(prompt.contains("## 현재 이해"))
        XCTAssertTrue(prompt.contains("## 모순"))
        XCTAssertTrue(prompt.contains("## 타임라인"))
        XCTAssertTrue(prompt.contains("2026-07-06"))
    }

    func testIsValidSynthesisRequiresCurrentUnderstanding() {
        XCTAssertTrue(TopicSynthesizer.isValidSynthesis("## 현재 이해\n내용"))
        XCTAssertFalse(TopicSynthesizer.isValidSynthesis("아무 형식 없는 응답"))
        XCTAssertFalse(TopicSynthesizer.isValidSynthesis(""))
    }
}
