import XCTest
@testable import DotBrain

final class TopicStoreTests: XCTestCase {
    var root: String!

    override func setUpWithError() throws {
        root = NSTemporaryDirectory() + "topic-store-tests-" + UUID().uuidString
        try FileManager.default.createDirectory(atPath: root, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(atPath: root)
    }

    private func makeTopic(id: String, members: [String] = []) -> Topic {
        Topic(id: id, name: id, pagePath: "_Wiki/\(id).md",
              members: members, keywords: [], summary: "",
              membersHash: "", created: "2026-07-06", lastSynthesized: nil)
    }

    func testLoadReturnsEmptyIndexWhenFileMissing() {
        let store = TopicStore(pkmRoot: root)
        let index = store.load()
        XCTAssertTrue(index.topics.isEmpty)
        XCTAssertTrue(index.deletedTopics.isEmpty)
        XCTAssertTrue(index.unassigned.isEmpty)
    }

    func testUpsertPersistsAndReplacesById() {
        let store = TopicStore(pkmRoot: root)
        store.upsert(makeTopic(id: "swift-concurrency", members: ["a.md"]))
        store.upsert(makeTopic(id: "swift-concurrency", members: ["a.md", "b.md"]))
        let index = store.load()
        XCTAssertEqual(index.topics.count, 1)
        XCTAssertEqual(index.topics[0].members, ["a.md", "b.md"])
    }

    func testTombstoneRemovesTopicAndBlocksRecreation() {
        let store = TopicStore(pkmRoot: root)
        store.upsert(makeTopic(id: "dead-topic"))
        store.tombstone(id: "dead-topic")
        XCTAssertTrue(store.load().topics.isEmpty)
        XCTAssertTrue(store.isTombstoned("dead-topic"))
        // tombstone twice must not duplicate the entry
        store.tombstone(id: "dead-topic")
        XCTAssertEqual(store.load().deletedTopics, ["dead-topic"])
    }

    func testUnassignedPoolDedupesSkipsAssignedAndCaps() {
        let store = TopicStore(pkmRoot: root)
        store.upsert(makeTopic(id: "t", members: ["assigned.md"]))
        store.addUnassigned(["x.md", "x.md", "assigned.md"])
        XCTAssertEqual(store.load().unassigned, ["x.md"])

        let flood = (0..<(TopicStore.unassignedCap + 10)).map { "n\($0).md" }
        store.addUnassigned(flood)
        let pool = store.load().unassigned
        XCTAssertEqual(pool.count, TopicStore.unassignedCap)
        XCTAssertFalse(pool.contains("x.md"), "FIFO: oldest entries dropped first")
    }

    func testRemoveUnassigned() {
        let store = TopicStore(pkmRoot: root)
        store.addUnassigned(["a.md", "b.md"])
        store.removeUnassigned(["a.md"])
        XCTAssertEqual(store.load().unassigned, ["b.md"])
    }

    func testPruneStaleDropsDeadMembersAndPoolEntries() {
        let store = TopicStore(pkmRoot: root)
        store.upsert(makeTopic(id: "t", members: ["live.md", "dead.md"]))
        store.addUnassigned(["pool-dead.md"])
        store.pruneStale(existingNotePaths: ["live.md"])
        let index = store.load()
        XCTAssertEqual(index.topics[0].members, ["live.md"])
        XCTAssertTrue(index.unassigned.isEmpty)
        // emptied topics stay (lint reports them as orphans) — not deleted here
        store.pruneStale(existingNotePaths: [])
        XCTAssertEqual(store.load().topics.count, 1)
    }
}
