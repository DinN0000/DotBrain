import XCTest
@testable import DotBrain

final class TopicWikiRetirementMigratorTests: XCTestCase {
    var root: String!

    override func setUpWithError() throws {
        root = NSTemporaryDirectory() + "topic-wiki-retirement-tests-" + UUID().uuidString
        try FileManager.default.createDirectory(
            atPath: root + "/_Wiki", withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(atPath: root)
    }

    private func topicPage(body: String, userSuffix: String = "") -> String {
        """
        ---
        tags: ["topic"]
        created: 2026-07-01
        ---

        \(FolderNotePage.markerStart)
        <!-- dotbrain-topic: t1 -->
        ## 현재 이해
        \(body)
        \(FolderNotePage.markerEnd)
        \(userSuffix)
        """
    }

    func testStripsBlockKeepsUserProseAndDeletesPurePages() async throws {
        let pure = root + "/_Wiki/PureTopic.md"
        try topicPage(body: "종합 내용").write(toFile: pure, atomically: true, encoding: .utf8)
        let withUser = root + "/_Wiki/Annotated.md"
        try topicPage(body: "종합", userSuffix: "\n## 내 메모\n직접 쓴 내용\n")
            .write(toFile: withUser, atomically: true, encoding: .utf8)
        let userOnly = root + "/_Wiki/HandWritten.md"
        try "마커 없는 사용자 페이지".write(toFile: userOnly, atomically: true, encoding: .utf8)

        await TopicWikiRetirementMigrator(pkmRoot: root).migrateIfNeeded()

        XCTAssertFalse(FileManager.default.fileExists(atPath: pure),
                       "pure DotBrain topic page must be removed")
        let annotated = try String(contentsOfFile: withUser, encoding: .utf8)
        XCTAssertFalse(annotated.contains(FolderNotePage.markerStart), "block stripped")
        XCTAssertTrue(annotated.contains("직접 쓴 내용"), "user prose preserved")
        XCTAssertEqual(try String(contentsOfFile: userOnly, encoding: .utf8),
                       "마커 없는 사용자 페이지", "marker-less page untouched")
        XCTAssertTrue(FileManager.default.fileExists(atPath: root + "/_Wiki"),
                      "_Wiki stays while user pages remain")
        XCTAssertTrue(FileManager.default.fileExists(
            atPath: root + "/.meta/topic-wiki-retirement-v1"), "marker written")
    }

    func testRemovesEmptyWikiDirAndRunsOnce() async throws {
        let pure = root + "/_Wiki/OnlyTopic.md"
        try topicPage(body: "종합").write(toFile: pure, atomically: true, encoding: .utf8)

        let migrator = TopicWikiRetirementMigrator(pkmRoot: root)
        await migrator.migrateIfNeeded()
        XCTAssertFalse(FileManager.default.fileExists(atPath: root + "/_Wiki"),
                       "empty _Wiki removed once all pages are pure-DotBrain")

        // Marker gating: a page created after migration must not be touched
        try FileManager.default.createDirectory(
            atPath: root + "/_Wiki", withIntermediateDirectories: true)
        let late = root + "/_Wiki/Late.md"
        let lateContent = topicPage(body: "늦게 생김")
        try lateContent.write(toFile: late, atomically: true, encoding: .utf8)
        await migrator.migrateIfNeeded()
        XCTAssertEqual(try String(contentsOfFile: late, encoding: .utf8), lateContent,
                       "marker-gated migration must not run twice")
    }
}
