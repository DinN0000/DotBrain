import XCTest
@testable import DotBrain

final class NoteIndexGeneratorTests: XCTestCase {
    func testPruneStaleRemovesEntriesForDeletedFolders() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("DotBrain-NoteIndexPruneTests-\(UUID().uuidString)")
        let metaDir = root.appendingPathComponent(".meta")
        try FileManager.default.createDirectory(at: metaDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }

        let index = NoteIndex(
            version: 1,
            updated: "2026-06-26T00:00:00Z",
            folders: [
                "1_Project/scope-connect": FolderIndexEntry(
                    path: "1_Project/scope-connect", para: "project", summary: "live", tags: []
                ),
                "1_Project/Connect": FolderIndexEntry(
                    path: "1_Project/Connect", para: "project", summary: "stale", tags: []
                ),
                "1_Project/람다256_Report": FolderIndexEntry(
                    path: "1_Project/람다256_Report", para: "project", summary: "stale", tags: []
                ),
            ],
            notes: [
                "1_Project/scope-connect/plan.md": NoteIndexEntry(
                    path: "1_Project/scope-connect/plan.md", folder: "1_Project/scope-connect",
                    para: "project", tags: [], summary: "", project: nil, status: nil, area: nil
                ),
                "1_Project/Connect/old.md": NoteIndexEntry(
                    path: "1_Project/Connect/old.md", folder: "1_Project/Connect",
                    para: "project", tags: [], summary: "", project: nil, status: nil, area: nil
                ),
                "1_Project/root-note.md": NoteIndexEntry(
                    path: "1_Project/root-note.md", folder: "1_Project",
                    para: "project", tags: [], summary: "", project: nil, status: nil, area: nil
                ),
            ]
        )
        let indexPath = metaDir.appendingPathComponent("note-index.json")
        try JSONEncoder().encode(index).write(to: indexPath)

        NoteIndexGenerator(pkmRoot: root.path).pruneStale(existingFolders: ["1_Project/scope-connect"])

        let pruned = try JSONDecoder().decode(NoteIndex.self, from: Data(contentsOf: indexPath))

        XCTAssertEqual(Set(pruned.folders.keys), ["1_Project/scope-connect"],
                       "stale folder entries (Connect, 람다256_Report) must be removed")
        XCTAssertNotNil(pruned.notes["1_Project/scope-connect/plan.md"], "live note must survive")
        XCTAssertNil(pruned.notes["1_Project/Connect/old.md"], "note under a deleted folder must be pruned")
        XCTAssertNotNil(pruned.notes["1_Project/root-note.md"], "root-level notes must be preserved")
    }
}
