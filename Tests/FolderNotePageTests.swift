import XCTest
@testable import DotBrain

final class FolderNotePageTests: XCTestCase {

    func testCreatesNewPageWithFrontmatterAndMarkers() {
        let content = FolderNotePage.replacingSynthesis(
            in: nil,
            synthesis: "## 개요\n지갑 연결 프로젝트.\n\n### 핵심 노트\n- [[Pitch 1]] — 문제 정의",
            inputsHash: "abc123",
            folderName: "scope-connect",
            para: .project
        )
        XCTAssertTrue(content.hasPrefix("---\n"), "new page needs frontmatter")
        XCTAssertTrue(content.contains(FolderNotePage.markerStart))
        XCTAssertTrue(content.contains(FolderNotePage.markerEnd))
        XCTAssertTrue(content.contains("dotbrain-synthesis-hash: abc123"))
    }

    func testUpdatePreservesUserContentOutsideMarkers() {
        let existing = """
        ---
        para: project
        tags: []
        ---
        \(FolderNotePage.markerStart)
        <!-- dotbrain-synthesis-hash: old -->
        ## 개요
        옛 종합.
        \(FolderNotePage.markerEnd)

        내가 직접 쓴 메모는 남아야 한다.
        """
        let updated = FolderNotePage.replacingSynthesis(
            in: existing, synthesis: "## 개요\n새 종합.",
            inputsHash: "new", folderName: "scope-connect", para: .project
        )
        XCTAssertTrue(updated.contains("새 종합."))
        XCTAssertFalse(updated.contains("옛 종합."))
        XCTAssertTrue(updated.contains("내가 직접 쓴 메모는 남아야 한다."))
    }

    func testNoMarkersPrependsSectionAndKeepsBody() {
        let existing = "---\npara: project\ntags: []\n---\n사용자가 만든 폴더 노트."
        let updated = FolderNotePage.replacingSynthesis(
            in: existing, synthesis: "## 개요\n첫 종합.",
            inputsHash: "h1", folderName: "scope-connect", para: .project
        )
        XCTAssertTrue(updated.contains("첫 종합."))
        XCTAssertTrue(updated.contains("사용자가 만든 폴더 노트."))
    }

    func testExtractsOverviewFirstParagraph() {
        let content = """
        \(FolderNotePage.markerStart)
        <!-- dotbrain-synthesis-hash: h -->
        ## 개요
        지갑 연결 Kit 프로젝트. Phase 2 진행 중.

        ### 최근 흐름
        - 어쩌고
        \(FolderNotePage.markerEnd)
        """
        XCTAssertEqual(
            FolderNotePage.overview(from: content),
            "지갑 연결 Kit 프로젝트. Phase 2 진행 중."
        )
    }

    func testExtractsInputsHash() {
        let content = "\(FolderNotePage.markerStart)\n<!-- dotbrain-synthesis-hash: xyz -->\n## 개요\n.\n\(FolderNotePage.markerEnd)"
        XCTAssertEqual(FolderNotePage.inputsHash(from: content), "xyz")
        XCTAssertNil(FolderNotePage.inputsHash(from: "no markers"))
    }
}
