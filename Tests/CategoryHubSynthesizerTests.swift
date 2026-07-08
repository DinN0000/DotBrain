import XCTest
@testable import DotBrain

final class CategoryHubSynthesizerTests: XCTestCase {

    // MARK: - Fixtures

    /// A subfolder (FolderNotePage-shaped) page carrying all five sections.
    private func subfolderPage(overview: String, keyNotes: String, recentFlow: String) -> String {
        """
        ---
        para: project
        tags: []
        ---
        \(CategoryHubPage.markerStart)
        <!-- dotbrain-synthesis-hash: h -->
        ## 개요
        \(overview)

        ## 최근 흐름
        \(recentFlow)

        ## 핵심 노트
        \(keyNotes)

        ## 모순
        - 감지된 모순 없음

        ## 노후
        - 없음
        \(CategoryHubPage.markerEnd)
        """
    }

    private func slice(_ name: String, _ text: String) -> CategoryHubSynthesizer.SubfolderSlice {
        .init(name: name, slice: text, modified: .distantPast)
    }

    // MARK: - Stable slice (guardrail: feed == gate, no churn)

    func testStableSliceKeepsOverviewAndKeyNotesDropsChurn() {
        let page = subfolderPage(
            overview: "지형 요약 문단.",
            keyNotes: "- [[a]] — 역할",
            recentFlow: "- 2026-07-08: 최근 변경"
        )
        let sliceText = CategoryHubPage.stableSlice(from: page)
        XCTAssertNotNil(sliceText)
        XCTAssertTrue(sliceText!.contains("## 개요"))
        XCTAssertTrue(sliceText!.contains("지형 요약 문단."))
        XCTAssertTrue(sliceText!.contains("## 핵심 노트"))
        XCTAssertTrue(sliceText!.contains("- [[a]] — 역할"))
        // The churny/derived sections and the hash comment must NOT leak in
        XCTAssertFalse(sliceText!.contains("## 최근 흐름"))
        XCTAssertFalse(sliceText!.contains("2026-07-08"))
        XCTAssertFalse(sliceText!.contains("## 모순"))
        XCTAssertFalse(sliceText!.contains("## 노후"))
        XCTAssertFalse(sliceText!.contains("dotbrain-synthesis-hash"))
    }

    func testStableSliceReturnsNilWhenNoMarkers() {
        XCTAssertNil(CategoryHubPage.stableSlice(from: "## 개요\n마커 없음"))
    }

    /// A subfolder's 최근 흐름 changing every run must NOT flip the hub hash.
    func testStableSliceAndHubHashIgnoreRecentFlowChurn() {
        let v1 = subfolderPage(overview: "동일 개요.", keyNotes: "- [[x]] — 역할",
                               recentFlow: "- 2026-07-01: 초기")
        let v2 = subfolderPage(overview: "동일 개요.", keyNotes: "- [[x]] — 역할",
                               recentFlow: "- 2026-07-08: 갱신\n- 2026-07-01: 초기")
        let s1 = CategoryHubPage.stableSlice(from: v1)
        let s2 = CategoryHubPage.stableSlice(from: v2)
        XCTAssertNotNil(s1)
        XCTAssertEqual(s1, s2, "stable slice must ignore 최근 흐름 churn (feed == gate)")

        let other = slice("Other", "## 개요\n다른 폴더")
        let h1 = CategoryHubSynthesizer.inputsHash(slices: [slice("Sub", s1!), other])
        let h2 = CategoryHubSynthesizer.inputsHash(slices: [slice("Sub", s2!), other])
        XCTAssertEqual(h1, h2, "hub hash must not change when only 최근 흐름 changed")
    }

    // MARK: - inputsHash

    func testInputsHashIsOrderIndependent() {
        let a = slice("A", "## 개요\nA")
        let b = slice("B", "## 개요\nB")
        XCTAssertEqual(CategoryHubSynthesizer.inputsHash(slices: [a, b]),
                       CategoryHubSynthesizer.inputsHash(slices: [b, a]))
    }

    func testInputsHashChangesWhenSubfolderRemoved() {
        let a = slice("A", "## 개요\nA")
        let b = slice("B", "## 개요\nB")
        XCTAssertNotEqual(CategoryHubSynthesizer.inputsHash(slices: [a, b]),
                          CategoryHubSynthesizer.inputsHash(slices: [a]))
    }

    func testInputsHashChangesWhenSliceContentChanges() {
        let a = slice("A", "## 개요\nA")
        let b = slice("B", "## 개요\nB")
        let a2 = slice("A", "## 개요\nA-변경")
        XCTAssertNotEqual(CategoryHubSynthesizer.inputsHash(slices: [a, b]),
                          CategoryHubSynthesizer.inputsHash(slices: [a2, b]))
    }

    // MARK: - Validator / prompt (headings must match byte-for-byte)

    func testIsValidSynthesisRequiresGeographyCrosslinkContradiction() {
        let good = """
        ## 지형
        지형 설명.

        ## 교차연결
        - [[A]] ↔ [[B]]: 연결

        ## 모순
        - 감지된 모순 없음

        요지: 카테고리는 안정적임.
        """
        XCTAssertTrue(CategoryHubSynthesizer.isValidSynthesis(good))
        let missing = good.replacingOccurrences(of: "## 모순", with: "## 끝")
        XCTAssertFalse(CategoryHubSynthesizer.isValidSynthesis(missing))
    }

    func testPromptHeadingsMatchValidatorExactly() {
        let prompt = CategoryHubSynthesizer.buildPrompt(
            categoryName: "1_Project", para: .project,
            slices: [slice("Alpha", "## 개요\n요약 A")], today: "2026-07-08"
        )
        for heading in CategoryHubSynthesizer.requiredSections {
            XCTAssertTrue(prompt.contains(heading), "prompt must emit \(heading)")
        }
        XCTAssertTrue(prompt.contains("### Alpha"), "each subfolder slice is fed under its name")
        XCTAssertTrue(prompt.contains("요약 A"))
    }

    // MARK: - Strip hub section (category drops below 2 subfolders)

    func testStrippingSynthesisRemovesBlockKeepsUserContent() {
        let page = """
        ---
        para: project
        tags: []
        ---
        \(CategoryHubPage.markerStart)
        <!-- dotbrain-synthesis-hash: h -->
        ## 지형
        지형.
        \(CategoryHubPage.markerEnd)

        사용자 메모는 남아야 한다.
        """
        let stripped = CategoryHubPage.strippingSynthesis(from: page)
        XCTAssertNotNil(stripped)
        XCTAssertFalse(stripped!.contains("## 지형"))
        XCTAssertFalse(stripped!.contains(CategoryHubPage.markerStart))
        XCTAssertTrue(stripped!.contains("사용자 메모는 남아야 한다."))
        XCTAssertTrue(stripped!.contains("para: project"))
    }

    func testStrippingSynthesisReturnsNilWhenNoBlock() {
        XCTAssertNil(CategoryHubPage.strippingSynthesis(from: "마커 없는 파일"))
    }

    // MARK: - capToBytes

    func testCapToBytesReturnsUnchangedUnderLimit() {
        XCTAssertEqual(CategoryHubSynthesizer.capToBytes("hello", 100), "hello")
    }

    func testCapToBytesTruncatesOnCharacterBoundary() {
        // Each Hangul syllable is 3 UTF-8 bytes; cap at 7 fits exactly two.
        let capped = CategoryHubSynthesizer.capToBytes("가나다라마", 7)
        XCTAssertEqual(capped, "가나")
        XCTAssertLessThanOrEqual(capped.utf8.count, 7)
    }

    // MARK: - categoryRoots

    func testCategoryRootsMapsSubfoldersAndSkipsArchiveAndNonPARA() {
        let roots = CategoryHubSynthesizer.categoryRoots(
            for: [
                "/vault/1_Project/A", "/vault/1_Project/B",
                "/vault/3_Resource/C", "/vault/4_Archive/D", "/vault/_Inbox",
            ],
            pkmRoot: "/vault"
        )
        XCTAssertEqual(roots, ["/vault/1_Project", "/vault/3_Resource"])
    }

    // MARK: - subfolderPaths (file I/O)

    func testSubfolderPathsSkipsHiddenUnderscoreAndFiles() throws {
        let fm = FileManager.default
        let base = fm.temporaryDirectory
            .appendingPathComponent("hub-test-\(UUID().uuidString)")
        try fm.createDirectory(at: base, withIntermediateDirectories: true)
        defer { try? fm.removeItem(at: base) }

        for dir in ["Alpha", "Beta", "_Skipped", ".hidden"] {
            try fm.createDirectory(at: base.appendingPathComponent(dir), withIntermediateDirectories: true)
        }
        try "not a folder".write(to: base.appendingPathComponent("note.md"), atomically: true, encoding: .utf8)

        let found = CategoryHubSynthesizer.subfolderPaths(in: base.path)
            .map { ($0 as NSString).lastPathComponent }
        XCTAssertEqual(found, ["Alpha", "Beta"])
    }
}
