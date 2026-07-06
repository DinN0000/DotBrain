import XCTest
@testable import DotBrain

final class InboxGuidanceTests: XCTestCase {

    // MARK: - Classifier.userDirectiveSection

    func testDirectiveSectionEmptyWithoutGuidanceOrCategory() {
        XCTAssertEqual(Classifier.userDirectiveSection(guidance: nil, forcedCategory: nil), "")
    }

    func testDirectiveSectionCarriesGuidanceVerbatim() {
        let section = Classifier.userDirectiveSection(
            guidance: "회의록은 여신협회로, 나머지는 알아서",
            forcedCategory: nil
        )
        XCTAssertTrue(section.contains("회의록은 여신협회로, 나머지는 알아서"))
        XCTAssertTrue(section.contains("사용자 지시"))
    }

    func testDirectiveSectionStatesCategoryConstraint() {
        let section = Classifier.userDirectiveSection(guidance: nil, forcedCategory: .project)
        XCTAssertTrue(section.contains("project"))
        XCTAssertTrue(section.contains("반드시"))
    }

    // MARK: - InboxProcessor.enforcing(destination:)

    private func result(
        para: PARACategory, folder: String = "X",
        confidence: Double = 0.9, isMedia: Bool = false
    ) -> ClassifyResult {
        ClassifyResult(
            para: para, tags: [], summary: "", targetFolder: folder,
            project: para == .project ? folder : nil,
            confidence: confidence, relatedNotes: [], isMediaAsset: isMedia
        )
    }

    func testNamedFolderDestinationForcesEverything() {
        let destination = InboxDestination(category: .project, folderName: "DotBrain")
        let out = InboxProcessor.enforcing(
            destination: destination,
            on: [result(para: .resource), result(para: .archive)]
        )
        XCTAssertTrue(out.allSatisfy { $0.para == .project && $0.targetFolder == "DotBrain" && $0.confidence == 1.0 })
    }

    // Category-only: files the AI already put in the category are untouched;
    // stragglers are pulled into the category with lowered confidence so the
    // existing confirmation flow catches them instead of a silent guess.
    func testCategoryOnlyDestinationForcesOnlyStragglers() {
        let destination = InboxDestination(category: .project, folderName: nil)
        let out = InboxProcessor.enforcing(
            destination: destination,
            on: [result(para: .project, folder: "DotBrain"), result(para: .resource, folder: "Swift")]
        )
        XCTAssertEqual(out[0].para, .project)
        XCTAssertEqual(out[0].targetFolder, "DotBrain")
        XCTAssertEqual(out[0].confidence, 0.9, "in-category result stays untouched")
        XCTAssertEqual(out[1].para, .project)
        XCTAssertLessThan(
            out[1].confidence, InboxProcessor.confirmationThreshold,
            "straggler must route to confirmation"
        )
    }

    // Media files have no classifiable text; under a category-only constraint
    // they keep their default asset routing instead of becoming confirmations.
    func testCategoryOnlyDestinationSkipsMediaEntries() {
        let destination = InboxDestination(category: .project, folderName: nil)
        let media = result(para: .resource, folder: "", confidence: 1.0, isMedia: true)
        let out = InboxProcessor.enforcing(
            destination: destination,
            on: [media, result(para: .resource, folder: "Swift")]
        )
        XCTAssertEqual(out[0].para, .resource, "media entry keeps default routing")
        XCTAssertEqual(out[0].confidence, 1.0)
        XCTAssertEqual(out[1].para, .project)
    }

    func testNilDestinationLeavesResultsAlone() {
        let input = [result(para: .resource), result(para: .area)]
        let out = InboxProcessor.enforcing(destination: nil, on: input)
        XCTAssertEqual(out.map(\.para), input.map(\.para))
        XCTAssertEqual(out.map(\.confidence), input.map(\.confidence))
    }
}
