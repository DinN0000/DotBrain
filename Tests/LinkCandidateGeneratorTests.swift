import XCTest
@testable import DotBrain

final class LinkCandidateGeneratorTests: XCTestCase {

    private func note(
        _ name: String,
        folder: String,
        folderRel: String,
        tags: [String]
    ) -> LinkCandidateGenerator.NoteInfo {
        LinkCandidateGenerator.NoteInfo(
            name: name,
            filePath: "/vault/\(folderRel)/\(name).md",
            tags: tags,
            summary: "\(name) 요약",
            project: nil,
            folderName: folder,
            folderRelPath: folderRel,
            para: .project,
            existingRelated: []
        )
    }

    func testCrossFolderNoteToNoteNeedsStrongerSignal() {
        let source = note("노트", folder: "X", folderRel: "1_Project/X", tags: ["swift", "ui"])
        let weak = note("약한노트", folder: "Y", folderRel: "1_Project/Y", tags: ["swift"])
        let medium = note("중간노트", folder: "Y", folderRel: "1_Project/Y", tags: ["swift", "ui"])

        let candidates = LinkCandidateGenerator().generateCandidates(
            for: source, allNotes: [source, weak, medium], mocEntries: []
        )
        let names = candidates.map(\.name)
        XCTAssertFalse(names.contains("약한노트"), "1 shared tag (1.5) must miss the cross-folder cut")
        XCTAssertFalse(names.contains("중간노트"), "2 shared tags (3.0) must miss the raised 3.5 cross-folder cut")
    }

    func testHubCandidatePassesWithBonus() {
        let source = note("노트", folder: "X", folderRel: "1_Project/X", tags: ["swift", "ui"])
        let hub = note("Y", folder: "Y", folderRel: "1_Project/Y", tags: ["swift"])

        let candidates = LinkCandidateGenerator().generateCandidates(
            for: source, allNotes: [source, hub], mocEntries: []
        )
        guard let hubCandidate = candidates.first(where: { $0.name == "Y" }) else {
            XCTFail("hub candidate with 1 shared tag + hub bonus must pass")
            return
        }
        XCTAssertTrue(hubCandidate.isHub)
        XCTAssertEqual(hubCandidate.score, 3.0, accuracy: 0.001, "1.5 tag + 1.5 hub bonus")
    }

    func testSameFolderKeepsOriginalThreshold() {
        let source = note("노트", folder: "X", folderRel: "1_Project/X", tags: ["swift", "ui"])
        let sibling = note("같은폴더", folder: "X", folderRel: "1_Project/X", tags: ["swift", "ui"])

        let candidates = LinkCandidateGenerator().generateCandidates(
            for: source, allNotes: [source, sibling], mocEntries: []
        )
        guard let siblingCandidate = candidates.first(where: { $0.name == "같은폴더" }) else {
            XCTFail("same-folder note with 2 shared tags must keep passing at 2.0")
            return
        }
        XCTAssertFalse(siblingCandidate.isHub)
    }
}
