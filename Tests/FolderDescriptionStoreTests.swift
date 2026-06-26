import XCTest
@testable import DotBrain

final class FolderDescriptionStoreTests: XCTestCase {
    func testUserDescriptionOverridesGeneratedProjectAndAreaSummaries() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("DotBrain-FolderDescriptionStoreTests-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: root) }

        try FolderDescriptionStore.set(
            "사용자가 지정한 프로젝트 범위",
            for: "DotBrain",
            category: .project,
            pkmRoot: root.path
        )
        try FolderDescriptionStore.set(
            "개인 생산성 시스템 운영",
            for: "Productivity",
            category: .area,
            pkmRoot: root.path
        )

        let index = NoteIndex(
            version: 1,
            updated: "2026-06-24T00:00:00Z",
            folders: [
                "1_Project/DotBrain": FolderIndexEntry(
                    path: "1_Project/DotBrain",
                    para: "project",
                    summary: "자동 생성 프로젝트 설명",
                    tags: ["macOS"]
                ),
                "2_Area/Productivity": FolderIndexEntry(
                    path: "2_Area/Productivity",
                    para: "area",
                    summary: "자동 생성 영역 설명",
                    tags: []
                ),
            ],
            notes: [:]
        )
        let builder = ProjectContextBuilder(pkmRoot: root.path, noteIndex: index)

        XCTAssertTrue(builder.buildProjectContext().contains("사용자가 지정한 프로젝트 범위"))
        XCTAssertFalse(builder.buildProjectContext().contains("자동 생성 프로젝트 설명"))
        XCTAssertTrue(builder.buildAreaContext().contains("개인 생산성 시스템 운영"))
    }

    func testDescriptionFollowsFolderRename() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("DotBrain-FolderDescriptionMoveTests-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: root) }

        try FolderDescriptionStore.set(
            "기존 설명",
            for: "Old Name",
            category: .project,
            pkmRoot: root.path
        )
        try FolderDescriptionStore.move(
            name: "Old Name",
            from: .project,
            to: .project,
            newName: "New Name",
            pkmRoot: root.path
        )

        let store = FolderDescriptionStore.load(pkmRoot: root.path)
        XCTAssertNil(store.description(for: "Old Name", category: .project))
        XCTAssertEqual(store.description(for: "New Name", category: .project), "기존 설명")
    }
}
