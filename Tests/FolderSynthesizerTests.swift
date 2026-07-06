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
}
