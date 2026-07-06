import XCTest
@testable import DotBrain

final class PARAMoverTests: XCTestCase {
    private var root: String!
    private var mover: PARAMover!

    override func setUpWithError() throws {
        root = (NSTemporaryDirectory() as NSString)
            .appendingPathComponent("PARAMoverTests-\(UUID().uuidString)")
        let fm = FileManager.default
        for dir in ["1_Project", "2_Area", "3_Resource", "4_Archive"] {
            try fm.createDirectory(
                atPath: (root as NSString).appendingPathComponent(dir),
                withIntermediateDirectories: true
            )
        }
        mover = PARAMover(pkmRoot: root)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(atPath: root)
    }

    private func projectPath(_ relative: String) -> String {
        ((root as NSString).appendingPathComponent("1_Project") as NSString)
            .appendingPathComponent(relative)
    }

    private func makeFolder(_ name: String, files: [String: String]) throws {
        let fm = FileManager.default
        let dir = projectPath(name)
        try fm.createDirectory(atPath: dir, withIntermediateDirectories: true)
        for (file, content) in files {
            try content.write(
                toFile: (dir as NSString).appendingPathComponent(file),
                atomically: true, encoding: .utf8
            )
        }
    }

    private func entityPage(folder: String) -> String {
        FolderNotePage.replacingSynthesis(
            in: nil,
            synthesis: "## 개요\n\(folder) 폴더 종합.",
            inputsHash: "hash-\(folder)",
            folderName: folder,
            para: .project
        )
    }

    // Merge: the source folder's entity page is disposable (resynthesized on the
    // next pass), so it must be trashed instead of carried into the target.
    func testMergeTrashesSourceEntityPageAndMovesRegularFiles() throws {
        let fm = FileManager.default
        try makeFolder("Connect", files: [
            "Connect.md": entityPage(folder: "Connect"),
            "note.md": "---\ntags: []\n---\n일반 노트.",
        ])
        try makeFolder("scope-connect", files: [:])

        let moved = try mover.mergeFolder(source: "Connect", into: "scope-connect", category: .project)

        XCTAssertEqual(moved, 1, "only the regular note counts as moved")
        XCTAssertTrue(fm.fileExists(atPath: projectPath("scope-connect/note.md")))
        XCTAssertFalse(
            fm.fileExists(atPath: projectPath("scope-connect/Connect.md")),
            "entity page must not leak into the target"
        )
        XCTAssertFalse(fm.fileExists(atPath: projectPath("Connect")), "source folder is gone")
    }

    // Merge: a same-named folder note WITHOUT markers is user content — keep moving it.
    func testMergeMovesUserAuthoredFolderNote() throws {
        let fm = FileManager.default
        let userNote = "---\ntags: []\n---\n사용자가 직접 쓴 폴더 노트."
        try makeFolder("Connect", files: ["Connect.md": userNote])
        try makeFolder("scope-connect", files: [:])

        let moved = try mover.mergeFolder(source: "Connect", into: "scope-connect", category: .project)

        XCTAssertEqual(moved, 1)
        let movedPath = projectPath("scope-connect/Connect.md")
        XCTAssertTrue(fm.fileExists(atPath: movedPath))
        let content = try String(contentsOfFile: movedPath, encoding: .utf8)
        XCTAssertTrue(content.contains("사용자가 직접 쓴 폴더 노트."))
    }

    // Rename: the entity page follows the folder's new name.
    func testRenameFollowsEntityPageName() throws {
        let fm = FileManager.default
        try makeFolder("Connect", files: [
            "Connect.md": entityPage(folder: "Connect"),
            "note.md": "---\ntags: []\n---\n일반 노트.",
        ])

        _ = try mover.renameFolder(oldName: "Connect", newName: "ConnectX", category: .project)

        XCTAssertTrue(fm.fileExists(atPath: projectPath("ConnectX/ConnectX.md")))
        XCTAssertFalse(fm.fileExists(atPath: projectPath("ConnectX/Connect.md")))
    }

    // Rename: a user-authored folder note (no markers) keeps its old name.
    func testRenameLeavesUserAuthoredFolderNoteAlone() throws {
        let fm = FileManager.default
        try makeFolder("Connect", files: [
            "Connect.md": "---\ntags: []\n---\n사용자가 직접 쓴 폴더 노트.",
        ])

        _ = try mover.renameFolder(oldName: "Connect", newName: "ConnectX", category: .project)

        XCTAssertTrue(fm.fileExists(atPath: projectPath("ConnectX/Connect.md")))
        XCTAssertFalse(fm.fileExists(atPath: projectPath("ConnectX/ConnectX.md")))
    }
}
