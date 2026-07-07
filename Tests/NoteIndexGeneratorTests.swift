import XCTest
@testable import DotBrain

final class NoteIndexGeneratorTests: XCTestCase {

    // MARK: - Folder summary from entity page

    private func makeVault() throws -> URL {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("DotBrain-NoteIndexSummaryTests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(
            at: root.appendingPathComponent("1_Project/X"),
            withIntermediateDirectories: true
        )
        return root
    }

    private func writeMemberNotes(in folder: URL) throws {
        let a = "---\npara: project\ntags: [\"one\"]\nsummary: 노트 A 요약\n---\n본문 A"
        let b = "---\npara: project\ntags: [\"two\"]\nsummary: 노트 B 요약\n---\n본문 B"
        try a.write(to: folder.appendingPathComponent("a.md"), atomically: true, encoding: .utf8)
        try b.write(to: folder.appendingPathComponent("b.md"), atomically: true, encoding: .utf8)
    }

    func testFolderSummaryComesFromEntityPageOverview() async throws {
        let root = try makeVault()
        defer { try? FileManager.default.removeItem(at: root) }
        let folder = root.appendingPathComponent("1_Project/X")
        try writeMemberNotes(in: folder)

        let entityPage = """
        ---
        para: project
        summary: 프론트매터 요약
        ---
        \(FolderNotePage.markerStart)
        <!-- dotbrain-synthesis-hash: h1 -->
        ## 개요
        지갑 연결 Kit 프로젝트. Phase 2 진행 중.

        ### 핵심 노트
        - [[a]] — 문제 정의
        \(FolderNotePage.markerEnd)
        """
        try entityPage.write(to: folder.appendingPathComponent("X.md"), atomically: true, encoding: .utf8)

        await NoteIndexGenerator(pkmRoot: root.path).updateForFolders([folder.path])

        let indexURL = root.appendingPathComponent(".meta/note-index.json")
        let index = try JSONDecoder().decode(NoteIndex.self, from: Data(contentsOf: indexURL))
        XCTAssertEqual(
            index.folders["1_Project/X"]?.summary,
            "지갑 연결 Kit 프로젝트. Phase 2 진행 중.",
            "folder summary must come from the entity page overview"
        )
    }

    func testFolderSummaryFallsBackToNoteSummariesWithoutMarkers() async throws {
        let root = try makeVault()
        defer { try? FileManager.default.removeItem(at: root) }
        let folder = root.appendingPathComponent("1_Project/X")
        try writeMemberNotes(in: folder)

        await NoteIndexGenerator(pkmRoot: root.path).updateForFolders([folder.path])

        let indexURL = root.appendingPathComponent(".meta/note-index.json")
        let index = try JSONDecoder().decode(NoteIndex.self, from: Data(contentsOf: indexURL))
        XCTAssertEqual(
            index.folders["1_Project/X"]?.summary,
            "노트 A 요약; 노트 B 요약",
            "without markers the prefix(3) summary join must be preserved"
        )
    }

    // MARK: - Topics overlay

    func testTopicsOverlayAppliedFromTopicIndexOnSave() async throws {
        let root = try makeVault()
        defer { try? FileManager.default.removeItem(at: root) }
        let folder = root.appendingPathComponent("1_Project/X")
        try writeMemberNotes(in: folder)

        let store = TopicStore(pkmRoot: root.path)
        store.upsert(Topic(
            id: "swift-concurrency", name: "Swift Concurrency",
            pagePath: "_Wiki/Swift Concurrency.md",
            members: ["1_Project/X/a.md"], keywords: [], summary: "",
            membersHash: "", created: "2026-07-07T00:00:00Z", lastSynthesized: nil
        ))

        await NoteIndexGenerator(pkmRoot: root.path).updateForFolders([folder.path])

        let indexURL = root.appendingPathComponent(".meta/note-index.json")
        let index = try JSONDecoder().decode(NoteIndex.self, from: Data(contentsOf: indexURL))
        XCTAssertEqual(index.notes["1_Project/X/a.md"]?.topics, ["Swift Concurrency"],
                       "member note must carry its topic name")
        XCTAssertNil(index.notes["1_Project/X/b.md"]?.topics,
                     "non-member note must have no topics field")
    }

    func testRefreshTopicsPicksUpAssignmentsAfterIndexWrite() async throws {
        let root = try makeVault()
        defer { try? FileManager.default.removeItem(at: root) }
        let folder = root.appendingPathComponent("1_Project/X")
        try writeMemberNotes(in: folder)

        let generator = NoteIndexGenerator(pkmRoot: root.path)
        await generator.updateForFolders([folder.path])

        // Topic assigned after the index was written — refreshTopics must
        // overlay it without a folder rescan
        TopicStore(pkmRoot: root.path).upsert(Topic(
            id: "late-topic", name: "Late Topic",
            pagePath: "_Wiki/Late Topic.md",
            members: ["1_Project/X/b.md"], keywords: [], summary: "",
            membersHash: "", created: "2026-07-07T00:00:00Z", lastSynthesized: nil
        ))
        await generator.refreshTopics()

        let indexURL = root.appendingPathComponent(".meta/note-index.json")
        let index = try JSONDecoder().decode(NoteIndex.self, from: Data(contentsOf: indexURL))
        XCTAssertEqual(index.notes["1_Project/X/b.md"]?.topics, ["Late Topic"])
    }

    func testPruneStaleRemovesEntriesForDeletedFolders() async throws {
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

        await NoteIndexGenerator(pkmRoot: root.path).pruneStale(existingFolders: ["1_Project/scope-connect"])

        let pruned = try JSONDecoder().decode(NoteIndex.self, from: Data(contentsOf: indexPath))

        XCTAssertEqual(Set(pruned.folders.keys), ["1_Project/scope-connect"],
                       "stale folder entries (Connect, 람다256_Report) must be removed")
        XCTAssertNotNil(pruned.notes["1_Project/scope-connect/plan.md"], "live note must survive")
        XCTAssertNil(pruned.notes["1_Project/Connect/old.md"], "note under a deleted folder must be pruned")
        XCTAssertNotNil(pruned.notes["1_Project/root-note.md"], "root-level notes must be preserved")
    }
}
