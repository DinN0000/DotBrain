import XCTest
@testable import DotBrain

final class RelatedNotesPrunerTests: XCTestCase {
    var root: String!

    override func setUpWithError() throws {
        root = NSTemporaryDirectory() + "link-prune-tests-" + UUID().uuidString
        try FileManager.default.createDirectory(atPath: root, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(atPath: root)
    }

    private func entry(_ name: String, relation: String) -> RelatedNotesWriter.Entry {
        (name: name, context: "관련 문서", relation: relation)
    }

    // MARK: - Fallback ranking

    func testFallbackKeepsRelationPriorityThenFileOrder() {
        // 14 entries: 2 prerequisite at the end must survive over early "related"
        var entries: [RelatedNotesWriter.Entry] = (0..<12).map { entry("r\($0)", relation: "related") }
        entries.append(entry("p1", relation: "prerequisite"))
        entries.append(entry("p2", relation: "prerequisite"))

        let kept = RelatedNotesPruner.fallbackKept(entries: entries)
        XCTAssertEqual(kept.count, RelatedNotesPruner.cumulativeCap)
        XCTAssertTrue(kept.contains(12) && kept.contains(13), "prerequisites outrank related")
        XCTAssertFalse(kept.contains(10) || kept.contains(11), "latest related entries dropped first")
    }

    // MARK: - Response parsing

    func testParseResponseUsesKeepIndicesAndFallsBackOnGarbage() {
        let batch = [(
            input: RelatedNotesPruner.PruneInput(name: "n", filePath: "/tmp/n.md", summary: ""),
            entries: (0..<14).map { entry("e\($0)", relation: "related") }
        )]

        let parsed = RelatedNotesPruner.parseResponse(
            #"[{"noteIndex": 0, "keep": [0, 2, 99, -1]}]"#, batch: batch
        )
        XCTAssertEqual(parsed[0], Set([0, 2]), "out-of-range indices dropped")

        let garbage = RelatedNotesPruner.parseResponse("no json here", batch: batch)
        XCTAssertEqual(garbage[0], RelatedNotesPruner.fallbackKept(entries: batch[0].entries))
    }

    // MARK: - replaceEntries

    func testReplaceEntriesRewritesCleanSectionOnly() throws {
        let path = root + "/note.md"
        let content = """
        ---
        para: resource
        ---
        본문

        ## Related Notes

        - [[A]] — 하나
        - [[B]] — 둘
        - [[C]] — 셋
        """
        try content.write(toFile: path, atomically: true, encoding: .utf8)

        let writer = RelatedNotesWriter()
        let kept: [RelatedNotesWriter.Entry] = [
            (name: "A", context: "하나", relation: "related"),
            (name: "C", context: "셋", relation: "related"),
        ]
        XCTAssertTrue(try writer.replaceEntries(filePath: path, entries: kept))

        let updated = try String(contentsOfFile: path, encoding: .utf8)
        XCTAssertTrue(updated.contains("- [[A]] — 하나"))
        XCTAssertFalse(updated.contains("[[B]]"), "pruned entry must be gone")
        XCTAssertTrue(updated.contains("본문"), "body untouched")
    }

    // MARK: - Relation round-trip fidelity

    func testSingleDirectionalTypeSectionKeepsHeaderOnRoundTrip() throws {
        let path = root + "/refs.md"
        try "본문".write(toFile: path, atomically: true, encoding: .utf8)

        let writer = RelatedNotesWriter()
        let links = [
            LinkAIFilter.FilteredLink(name: "A", context: "비교할 때", relation: "reference"),
            LinkAIFilter.FilteredLink(name: "B", context: "참고하려면", relation: "reference"),
        ]
        try writer.writeRelatedNotes(filePath: path, newLinks: links, noteNames: ["A", "B"])

        let content = try String(contentsOfFile: path, encoding: .utf8)
        XCTAssertTrue(content.contains("### 참고 자료"),
                      "single-type directional sections must keep the group header")

        let parsed = writer.parseRelatedNotes(content)
        XCTAssertEqual(parsed?.entries.map { $0.relation }, ["reference", "reference"],
                       "relation must survive the write-parse round-trip")
    }

    func testWriteRelatedNotesDedupsWithinBatch() throws {
        let path = root + "/dup.md"
        try "본문".write(toFile: path, atomically: true, encoding: .utf8)

        let writer = RelatedNotesWriter()
        let links = [
            LinkAIFilter.FilteredLink(name: "Foo", context: "하나", relation: "related"),
            LinkAIFilter.FilteredLink(name: "Foo", context: "둘", relation: "related"),
        ]
        try writer.writeRelatedNotes(filePath: path, newLinks: links, noteNames: ["Foo"])

        let content = try String(contentsOfFile: path, encoding: .utf8)
        let fooLines = content.components(separatedBy: "\n").filter { $0.contains("[[Foo]]") }
        XCTAssertEqual(fooLines.count, 1, "same name in one batch must be written once (first wins)")
        XCTAssertTrue(fooLines[0].contains("하나"))
    }

    func testReplaceEntriesRefusesUserAuthoredSections() throws {
        let path = root + "/user.md"
        let content = """
        본문

        ## Related Notes

        - [[A]] — 하나
        사용자가 직접 쓴 메모
        - [[B]] — 둘
        """
        try content.write(toFile: path, atomically: true, encoding: .utf8)

        let writer = RelatedNotesWriter()
        let kept: [RelatedNotesWriter.Entry] = [(name: "A", context: "하나", relation: "related")]
        XCTAssertFalse(try writer.replaceEntries(filePath: path, entries: kept))
        XCTAssertEqual(try String(contentsOfFile: path, encoding: .utf8), content,
                       "file with user content must be byte-identical")
    }
}
