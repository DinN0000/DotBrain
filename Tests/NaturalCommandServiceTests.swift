import XCTest
@testable import DotBrain

final class NaturalCommandServiceTests: XCTestCase {
    private let folders = [
        NaturalCommandFolder(name: "DotBrain", category: .project),
        NaturalCommandFolder(name: "Swift", category: .resource),
        NaturalCommandFolder(name: "Old Project", category: .archive),
    ]

    func testDecodeAcceptsJSONInsideCodeFence() async throws {
        let raw = """
        ```json
        {"action":"moveFolder","category":null,"sourceCategory":"project","targetCategory":"resource","folderName":"DotBrain","newName":null}
        ```
        """

        let plan = try await NaturalCommandService.shared.decodePlan(raw)

        XCTAssertEqual(plan.action, .moveFolder)
        XCTAssertEqual(plan.folderName, "DotBrain")
        XCTAssertEqual(plan.targetCategory, .resource)
    }

    func testDecodeDropsAmbiguousPipeTypeHintEcho() async throws {
        // A multi-token echo is not a choice — salvaging the first token
        // would fabricate a category the model never picked
        let raw = #"{"action":"processInboxToFolder","category":null,"sourceCategory":null,"targetCategory":"project|area|resource|archive|null","folderName":"DotBrain","newName":null}"#

        let plan = try await NaturalCommandService.shared.decodePlan(raw)

        XCTAssertEqual(plan.action, .processInboxToFolder)
        XCTAssertNil(plan.targetCategory)
    }

    func testDecodeSalvagesUnambiguousPipeEcho() async throws {
        // Exactly one valid token inside the echo — safe to salvage
        let raw = #"{"action":"processInboxToFolder","category":null,"sourceCategory":null,"targetCategory":"project|null","folderName":"DotBrain","newName":null}"#

        let plan = try await NaturalCommandService.shared.decodePlan(raw)

        XCTAssertEqual(plan.targetCategory, .project)
    }

    func testDecodeRecoversFromCapitalizedEnumValue() async throws {
        let raw = #"{"action":"ProcessInboxToFolder","category":null,"sourceCategory":null,"targetCategory":"Project","folderName":"DotBrain","newName":null}"#

        let plan = try await NaturalCommandService.shared.decodePlan(raw)

        XCTAssertEqual(plan.action, .processInboxToFolder)
        XCTAssertEqual(plan.targetCategory, .project)
    }

    func testDecodeFallsBackToUnsupportedForUnknownAction() async throws {
        let raw = #"{"action":"deleteEverything","category":null,"sourceCategory":null,"targetCategory":"project","folderName":"DotBrain","newName":null}"#

        let plan = try await NaturalCommandService.shared.decodePlan(raw)

        XCTAssertEqual(plan.action, .unsupported)
    }

    func testDecodeFailsOnGenuinelyUnparseableResponse() async throws {
        let raw = "죄송하지만 요청을 이해하지 못했습니다."

        do {
            _ = try await NaturalCommandService.shared.decodePlan(raw)
            XCTFail("Expected invalidResponse for non-JSON prose")
        } catch NaturalCommandError.invalidResponse {
            // Expected.
        }
    }

    func testInboxRejectsFolderMutation() async throws {
        let plan = NaturalCommandPlan(
            action: .createFolder,
            category: .project,
            sourceCategory: nil,
            targetCategory: nil,
            folderName: "New Project",
            newName: nil
        )
        let context = NaturalCommandContext(surface: .inbox, inboxCount: 1, folders: [])

        do {
            _ = try await NaturalCommandService.shared.validate(plan, context: context)
            XCTFail("Expected an unsupported command error")
        } catch NaturalCommandError.unsupported {
            // Expected.
        }
    }

    func testMoveUsesCanonicalExistingFolderName() async throws {
        let plan = NaturalCommandPlan(
            action: .moveFolder,
            category: nil,
            sourceCategory: .project,
            targetCategory: .area,
            folderName: "dotbrain",
            newName: nil
        )
        let context = NaturalCommandContext(
            surface: .folderManagement,
            inboxCount: 0,
            folders: folders
        )

        let validated = try await NaturalCommandService.shared.validate(plan, context: context)

        XCTAssertEqual(validated.folderName, "DotBrain")
        XCTAssertEqual(validated.sourceCategory, .project)
        XCTAssertEqual(validated.targetCategory, .area)
    }

    func testRejectsPathLikeNewFolderName() async throws {
        let plan = NaturalCommandPlan(
            action: .createFolder,
            category: .resource,
            sourceCategory: nil,
            targetCategory: nil,
            folderName: "../escape",
            newName: nil
        )
        let context = NaturalCommandContext(
            surface: .folderManagement,
            inboxCount: 0,
            folders: folders
        )

        do {
            _ = try await NaturalCommandService.shared.validate(plan, context: context)
            XCTFail("Expected an invalid folder name error")
        } catch NaturalCommandError.invalidFolderName {
            // Expected.
        }
    }

    func testEmptyInboxCannotBeProcessed() async throws {
        let plan = NaturalCommandPlan(
            action: .processInbox,
            category: nil,
            sourceCategory: nil,
            targetCategory: nil,
            folderName: nil,
            newName: nil
        )
        let context = NaturalCommandContext(surface: .inbox, inboxCount: 0, folders: [])

        do {
            _ = try await NaturalCommandService.shared.validate(plan, context: context)
            XCTFail("Expected an unavailable command error")
        } catch NaturalCommandError.unavailable {
            // Expected.
        }
    }

    func testInboxCanTargetAnExistingFolder() async throws {
        let plan = NaturalCommandPlan(
            action: .processInboxToFolder,
            category: nil,
            sourceCategory: nil,
            targetCategory: .project,
            folderName: "dotbrain",
            newName: nil
        )
        let context = NaturalCommandContext(
            surface: .inbox,
            inboxCount: 3,
            folders: folders
        )

        let validated = try await NaturalCommandService.shared.validate(plan, context: context)

        XCTAssertEqual(validated.folderName, "DotBrain")
        XCTAssertEqual(validated.targetCategory, .project)
    }

    // "Inbox에 있는것들 Project에 넣어줘" — category-level destination without
    // a folder name is a valid plan: classification is constrained to the
    // category and the AI picks a folder per file.
    func testInboxCanTargetCategoryOnly() async throws {
        let plan = NaturalCommandPlan(
            action: .processInboxToFolder,
            category: nil,
            sourceCategory: nil,
            targetCategory: .project,
            folderName: nil,
            newName: nil
        )
        let context = NaturalCommandContext(
            surface: .inbox,
            inboxCount: 3,
            folders: folders
        )

        let validated = try await NaturalCommandService.shared.validate(plan, context: context)

        XCTAssertNil(validated.folderName)
        XCTAssertEqual(validated.targetCategory, .project)
        XCTAssertEqual(validated.action, .processInboxToFolder)
    }

    // A named folder that does not exist must still fail loudly — silently
    // scattering files elsewhere would betray the user's explicit target.
    func testInboxNamedFolderStillFailsWhenMissing() async throws {
        let plan = NaturalCommandPlan(
            action: .processInboxToFolder,
            category: nil,
            sourceCategory: nil,
            targetCategory: .project,
            folderName: "없는폴더",
            newName: nil
        )
        let context = NaturalCommandContext(
            surface: .inbox,
            inboxCount: 3,
            folders: folders
        )

        do {
            _ = try await NaturalCommandService.shared.validate(plan, context: context)
            XCTFail("Expected folderNotFound")
        } catch NaturalCommandError.folderNotFound {
            // Expected.
        }
    }

    func testProjectDescriptionCanBeUpdated() async throws {
        let plan = NaturalCommandPlan(
            action: .updateFolderDescription,
            category: .project,
            sourceCategory: nil,
            targetCategory: nil,
            folderName: "dotbrain",
            newName: nil,
            description: "  macOS 지식 관리 앱  "
        )
        let context = NaturalCommandContext(
            surface: .folderManagement,
            inboxCount: 0,
            folders: folders
        )

        let validated = try await NaturalCommandService.shared.validate(plan, context: context)

        XCTAssertEqual(validated.folderName, "DotBrain")
        XCTAssertEqual(validated.category, .project)
        XCTAssertEqual(validated.description, "macOS 지식 관리 앱")
    }

    func testResourceDescriptionUpdateIsRejected() async throws {
        let plan = NaturalCommandPlan(
            action: .updateFolderDescription,
            category: .resource,
            sourceCategory: nil,
            targetCategory: nil,
            folderName: "Swift",
            newName: nil,
            description: "Swift 참고 자료"
        )
        let context = NaturalCommandContext(
            surface: .folderManagement,
            inboxCount: 0,
            folders: folders
        )

        do {
            _ = try await NaturalCommandService.shared.validate(plan, context: context)
            XCTFail("Expected an unsupported command error")
        } catch NaturalCommandError.unsupported {
            // Expected.
        }
    }
}
