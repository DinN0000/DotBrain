import XCTest
@testable import DotBrain

/// Task 6: after a Finder folder rename/merge, the folder's entity page is left
/// behind under a folder whose name no longer matches (baseName != parentName).
/// Vault check strips that page's DotBrain synthesis block (preserving user
/// prose) or trashes a page with nothing user-authored left.
///
/// GUARDRAIL: the cleanup scans ONLY the four PARA folders. A vault-root
/// CLAUDE.md carries the same DotBrain marker and has baseName != parentName,
/// yet must never be scanned or corrupted.
final class VaultCheckOrphanCleanupTests: XCTestCase {
    var root: String!
    var pm: PKMPathManager!

    override func setUpWithError() throws {
        root = NSTemporaryDirectory() + "pkm-orphan-tests-" + UUID().uuidString
        for sub in ["1_Project", "2_Area", "3_Resource", "4_Archive"] {
            try FileManager.default.createDirectory(
                atPath: (root as NSString).appendingPathComponent(sub),
                withIntermediateDirectories: true
            )
        }
        pm = PKMPathManager(root: root)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(atPath: root)
    }

    // MARK: - Helpers

    private func entityPage(overview: String, extraBody: String = "") -> String {
        var fm = Frontmatter(tags: [])
        fm.para = .resource
        fm.created = Frontmatter.today()
        let section = """
        \(FolderNotePage.markerStart)
        <!-- dotbrain-synthesis-hash: abc123 -->
        ## 개요
        \(overview)
        \(FolderNotePage.markerEnd)
        """
        return fm.stringify() + "\n" + section + "\n" + extraBody
    }

    @discardableResult
    private func makeFolder(_ rel: String) throws -> String {
        let dir = (root as NSString).appendingPathComponent(rel)
        try FileManager.default.createDirectory(atPath: dir, withIntermediateDirectories: true)
        return dir
    }

    // MARK: - Guardrail

    /// A vault-root CLAUDE.md with a DotBrain marker must never be scanned or
    /// modified — it lives outside the four PARA folders.
    func testRootClaudeMdUntouched() throws {
        let claudePath = (root as NSString).appendingPathComponent("CLAUDE.md")
        let original = """
        \(FolderNotePage.markerStart)
        companion body
        \(FolderNotePage.markerEnd)

        user notes below
        """
        try original.write(toFile: claudePath, atomically: true, encoding: .utf8)

        _ = VaultCheckPipeline.cleanOrphanEntityPages(pm: pm)

        let after = try String(contentsOfFile: claudePath, encoding: .utf8)
        XCTAssertEqual(after, original, "root CLAUDE.md must never be scanned or modified")
    }

    // MARK: - Orphan handling

    /// Renamed folder leaves `<newFolder>/<oldName>.md` with user prose below the
    /// block: strip the synthesis block, keep the user prose.
    func testOrphanWithUserContentStripped() throws {
        let dir = try makeFolder("3_Resource/RenamedFolder")
        let orphan = (dir as NSString).appendingPathComponent("OldName.md")
        try entityPage(overview: "synthesis text", extraBody: "## 내 메모\n사용자 작성 본문\n")
            .write(toFile: orphan, atomically: true, encoding: .utf8)

        let count = VaultCheckPipeline.cleanOrphanEntityPages(pm: pm)

        XCTAssertEqual(count, 1)
        let after = try String(contentsOfFile: orphan, encoding: .utf8)
        XCTAssertFalse(after.contains(FolderNotePage.markerStart), "synthesis block removed")
        XCTAssertTrue(after.contains("사용자 작성 본문"), "user prose preserved")
    }

    /// A pure DotBrain orphan (frontmatter + block only, no user prose) is
    /// trashed entirely.
    func testPureOrphanTrashed() throws {
        let dir = try makeFolder("2_Area/WasRenamed")
        let orphan = (dir as NSString).appendingPathComponent("BeforeRename.md")
        try entityPage(overview: "only synthesis")
            .write(toFile: orphan, atomically: true, encoding: .utf8)

        let count = VaultCheckPipeline.cleanOrphanEntityPages(pm: pm)

        XCTAssertEqual(count, 1)
        XCTAssertFalse(FileManager.default.fileExists(atPath: orphan),
                       "pure orphan page removed from its stale path")
    }

    // MARK: - Non-orphans left alone

    /// A valid folder page (baseName == parentName) is never touched.
    func testValidFolderPageUntouched() throws {
        let dir = try makeFolder("3_Resource/DevOps")
        let page = (dir as NSString).appendingPathComponent("DevOps.md")
        let content = entityPage(overview: "valid synthesis")
        try content.write(toFile: page, atomically: true, encoding: .utf8)

        let count = VaultCheckPipeline.cleanOrphanEntityPages(pm: pm)

        XCTAssertEqual(count, 0)
        let after = try String(contentsOfFile: page, encoding: .utf8)
        XCTAssertEqual(after, content, "valid folder page must be untouched")
    }

    /// A category hub page (`<N_Category>/<N_Category>.md`) has baseName ==
    /// parentName, so it is never mistaken for an orphan.
    func testCategoryHubUntouched() throws {
        let page = (pm.resourcePath as NSString).appendingPathComponent("3_Resource.md")
        let content = entityPage(overview: "hub synthesis")
        try content.write(toFile: page, atomically: true, encoding: .utf8)

        let count = VaultCheckPipeline.cleanOrphanEntityPages(pm: pm)

        XCTAssertEqual(count, 0)
        XCTAssertTrue(FileManager.default.fileExists(atPath: page))
    }

    /// A normal note without a DotBrain marker is never treated as an orphan,
    /// even though its baseName differs from its parent folder.
    func testPlainNoteUntouched() throws {
        let dir = try makeFolder("3_Resource/Notes")
        let note = (dir as NSString).appendingPathComponent("random-thought.md")
        let content = "---\npara: resource\n---\n\nplain note body\n"
        try content.write(toFile: note, atomically: true, encoding: .utf8)

        let count = VaultCheckPipeline.cleanOrphanEntityPages(pm: pm)

        XCTAssertEqual(count, 0)
        XCTAssertTrue(FileManager.default.fileExists(atPath: note))
        let after = try String(contentsOfFile: note, encoding: .utf8)
        XCTAssertEqual(after, content)
    }
}
