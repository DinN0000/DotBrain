import XCTest
@testable import DotBrain

final class ReverseLinkRelationMigratorTests: XCTestCase {
    var root: String!

    override func setUpWithError() throws {
        root = NSTemporaryDirectory() + "reverse-migration-tests-" + UUID().uuidString
        try FileManager.default.createDirectory(
            atPath: root + "/3_Resource/DeFi", withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(atPath: root)
    }

    func testMigratesCannedReverseEntriesButKeepsForwardDirectionalLinks() async throws {
        let path = root + "/3_Resource/DeFi/Aave.md"
        let content = """
        본문

        ## Related Notes

        ### 선행 지식

        - [[DeFi基礎]] — 이해하려면 먼저 참고
        - [[Compound분석]] — 이 문서를 선행 지식으로 활용

        ### 참고 자료

        - [[시장리포트]] — 이 문서를 참고 자료로 인용
        """
        try content.write(toFile: path, atomically: true, encoding: .utf8)

        await ReverseLinkRelationMigrator(pkmRoot: root).migrateIfNeeded()

        let migrated = try String(contentsOfFile: path, encoding: .utf8)
        let parsed = RelatedNotesWriter().parseRelatedNotes(migrated)!
        let byName = Dictionary(uniqueKeysWithValues: parsed.entries.map { ($0.name, $0.relation) })
        XCTAssertEqual(byName["DeFi基礎"], "prerequisite",
                       "forward directional link (AI-authored context) must be untouched")
        XCTAssertEqual(byName["Compound분석"], "related",
                       "pre-v18 reverse prerequisite entry must be relabeled")
        XCTAssertEqual(byName["시장리포트"], "related",
                       "pre-v18 reverse reference entry must be relabeled")
    }

    func testMigrationRunsOnceAndSkipsUserAuthoredSections() async throws {
        let userPath = root + "/3_Resource/DeFi/user.md"
        let userContent = """
        본문

        ## Related Notes

        - [[X]] — 이 문서를 선행 지식으로 활용
        사용자 메모
        """
        try userContent.write(toFile: userPath, atomically: true, encoding: .utf8)

        let migrator = ReverseLinkRelationMigrator(pkmRoot: root)
        await migrator.migrateIfNeeded()

        XCTAssertEqual(try String(contentsOfFile: userPath, encoding: .utf8), userContent,
                       "user-authored sections must be byte-identical")
        XCTAssertTrue(FileManager.default.fileExists(
            atPath: root + "/.meta/reverse-link-migration-v1"), "marker must be written")

        // Second run must be a no-op even for newly migratable content
        let latePath = root + "/3_Resource/DeFi/late.md"
        let lateContent = "본문\n\n## Related Notes\n\n### 선행 지식\n\n- [[Y]] — 이 문서를 선행 지식으로 활용\n"
        try lateContent.write(toFile: latePath, atomically: true, encoding: .utf8)
        await migrator.migrateIfNeeded()
        XCTAssertEqual(try String(contentsOfFile: latePath, encoding: .utf8), lateContent,
                       "marker-gated migration must not run twice")
    }
}
