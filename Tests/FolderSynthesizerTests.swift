import XCTest
@testable import DotBrain

final class FolderSynthesizerTests: XCTestCase {
    private func entry(_ path: String, folder: String, summary: String) -> NoteIndexEntry {
        NoteIndexEntry(path: path, folder: folder, para: "project", tags: [],
                       summary: summary, project: nil, status: "active", area: nil)
    }

    func testInputsHashIsOrderIndependentAndChangesWithContent() {
        let a = entry("1_Project/X/a.md", folder: "1_Project/X", summary: "A")
        let b = entry("1_Project/X/b.md", folder: "1_Project/X", summary: "B")
        XCTAssertEqual(FolderSynthesizer.inputsHash(members: [a, b]),
                       FolderSynthesizer.inputsHash(members: [b, a]))
        let b2 = entry("1_Project/X/b.md", folder: "1_Project/X", summary: "B-변경")
        XCTAssertNotEqual(FolderSynthesizer.inputsHash(members: [a, b]),
                          FolderSynthesizer.inputsHash(members: [a, b2]))
    }

    func testMembersExcludeTheFolderNoteItself() {
        let hub = entry("1_Project/X/X.md", folder: "1_Project/X", summary: "종합")
        let a = entry("1_Project/X/a.md", folder: "1_Project/X", summary: "A")
        let index = NoteIndex(version: 1, updated: "", folders: [:],
                              notes: [hub.path: hub, a.path: a])
        let members = FolderSynthesizer.members(in: index, folderRelPath: "1_Project/X")
        XCTAssertEqual(members.map(\.path), ["1_Project/X/a.md"])
    }

    // MARK: - Blocker fix #3: validator strings must match prompt (all "##")

    private let goodSynthesis = """
    ## 개요
    폴더 전체 종합.

    ## 최근 흐름
    - 2026-07-08: 시작

    ## 핵심 노트
    - [[a]] — 역할

    ## 모순
    - 감지된 모순 없음

    ## 노후
    - 없음

    요지: 프로젝트가 Phase 2로 진입함.
    """

    func testIsValidSynthesisRequiresAllFiveLevelTwoSections() {
        XCTAssertTrue(FolderSynthesizer.isValidSynthesis(goodSynthesis))
        // Missing any one section is rejected (page keeps previous synthesis)
        let missing = goodSynthesis.replacingOccurrences(of: "## 노후", with: "## 종료")
        XCTAssertFalse(FolderSynthesizer.isValidSynthesis(missing))
    }

    func testPromptHeadingsMatchValidatorExactly() {
        // Blocker fix #3: the prompt emits every section at "##" (never "###")
        // so it matches the validator strings byte-for-byte. A level mismatch
        // would reject every response and freeze the page.
        let m = entry("1_Project/X/a.md", folder: "1_Project/X", summary: "A")
        let prompt = FolderSynthesizer.buildPrompt(
            folderName: "X", para: .project, members: [m],
            userDescription: nil, previousSynthesis: nil,
            changedNotes: [], today: "2026-07-08"
        )
        for heading in FolderSynthesizer.requiredSections {
            XCTAssertTrue(prompt.contains(heading), "prompt must emit \(heading)")
        }
        // No level-3 section headings leak into the output format
        XCTAssertFalse(prompt.contains("### 최근 흐름"))
        XCTAssertFalse(prompt.contains("### 핵심 노트"))
    }

    // MARK: - Changed-body injection

    func testPromptFeedsChangedBodyUnderDedicatedSection() {
        let m = entry("1_Project/X/a.md", folder: "1_Project/X", summary: "A")
        let prompt = FolderSynthesizer.buildPrompt(
            folderName: "X", para: .project, members: [m],
            userDescription: nil, previousSynthesis: nil,
            changedNotes: [(name: "a", body: "새 실험 결과 요약")], today: "2026-07-08"
        )
        XCTAssertTrue(prompt.contains("## 새로 반영할 본문"))
        XCTAssertTrue(prompt.contains("새 실험 결과 요약"))
    }

    // MARK: - Carry-forward flow

    func testPromptCarriesForwardPreviousSynthesis() {
        let m = entry("1_Project/X/a.md", folder: "1_Project/X", summary: "A")
        let previous = "## 개요\n옛 종합.\n\n## 최근 흐름\n- 2026-07-01: 초기 정리"
        let prompt = FolderSynthesizer.buildPrompt(
            folderName: "X", para: .project, members: [m],
            userDescription: nil, previousSynthesis: previous,
            changedNotes: [], today: "2026-07-08"
        )
        XCTAssertTrue(prompt.contains("- 2026-07-01: 초기 정리"),
                      "previous 최근 흐름 must be fed back for carry-forward")
        XCTAssertTrue(prompt.contains("\(FolderSynthesizer.recentFlowCap)개"),
                      "prompt states the carry-forward cap")
    }

    // MARK: - 요지 extraction

    func testExtractGistStripsTrailingLine() {
        let (synthesis, gist) = FolderSynthesizer.extractGist(from: goodSynthesis)
        XCTAssertEqual(gist, "프로젝트가 Phase 2로 진입함.")
        XCTAssertFalse(synthesis.contains("요지:"), "요지 line must not land on the page")
        XCTAssertTrue(synthesis.contains("## 개요"))
        XCTAssertTrue(synthesis.contains("## 노후"))
    }

    func testExtractGistWithNoGistLineReturnsEmpty() {
        let text = "## 개요\n종합 본문."
        let (synthesis, gist) = FolderSynthesizer.extractGist(from: text)
        XCTAssertEqual(gist, "")
        XCTAssertEqual(synthesis, "## 개요\n종합 본문.")
    }
}
