import XCTest
@testable import DotBrain

final class NoteEnricherTests: XCTestCase {
    // 3a: tags/summary are AI-owned metadata that go stale as the body evolves.
    // On a body change (refreshExisting) they are regenerated even when present
    // — never user-curated, never data loss. para/source stay fill-empty.

    func testFillEmptyLeavesPresentTagsAndSummaryUntouched() {
        let fm = Frontmatter(para: .resource, tags: ["swift"], summary: "기존 요약", source: .original)
        let needs = NoteEnricher.fieldsNeeding(fm, refreshExisting: false)
        XCTAssertFalse(needs.tags)
        XCTAssertFalse(needs.summary)
        XCTAssertFalse(needs.para)
        XCTAssertFalse(needs.source)
        XCTAssertFalse(needs.any, "present fields with no refresh means no AI call")
    }

    func testRefreshExistingRegeneratesPresentTagsAndSummary() {
        let fm = Frontmatter(para: .resource, tags: ["swift"], summary: "기존 요약", source: .original)
        let needs = NoteEnricher.fieldsNeeding(fm, refreshExisting: true)
        XCTAssertTrue(needs.tags, "AI-owned tags refresh on body change")
        XCTAssertTrue(needs.summary, "AI-owned summary refresh on body change")
        // para/source are never refreshed — only filled when empty
        XCTAssertFalse(needs.para)
        XCTAssertFalse(needs.source)
        XCTAssertTrue(needs.any)
    }

    func testEmptyFieldsAlwaysNeedFillingRegardlessOfRefreshFlag() {
        let fm = Frontmatter(tags: [], summary: "")
        let needs = NoteEnricher.fieldsNeeding(fm, refreshExisting: false)
        XCTAssertTrue(needs.tags)
        XCTAssertTrue(needs.summary)
        XCTAssertTrue(needs.para, "nil para is filled")
        XCTAssertTrue(needs.source, "nil source is filled")
        XCTAssertTrue(needs.any)
    }

    // The refreshed summary is exactly what flips the folder synthesis hash, so
    // an edited note recompounds into its folder page (the 3a effect chain).
    func testRefreshedSummaryFlipsFolderInputsHash() {
        let before = NoteIndexEntry(path: "3_Resource/X/a.md", folder: "3_Resource/X",
                                    para: "resource", tags: [], summary: "옛 요약",
                                    project: nil, status: "active", area: nil)
        let after = NoteIndexEntry(path: "3_Resource/X/a.md", folder: "3_Resource/X",
                                   para: "resource", tags: [], summary: "갱신된 요약",
                                   project: nil, status: "active", area: nil)
        XCTAssertNotEqual(FolderSynthesizer.inputsHash(members: [before]),
                          FolderSynthesizer.inputsHash(members: [after]),
                          "a refreshed summary must change the folder synthesis input hash")
    }
}
