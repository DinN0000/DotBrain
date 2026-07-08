import XCTest
@testable import DotBrain

/// R2 new-intake routing: Area/Resource notes with no AI-assigned subfolder land
/// in a `Unsorted` catch-all instead of the bare category root, but ONLY when the
/// caller opts in via `allowCatchAll` (new-intake sites). Reorganizers keep their
/// existing keep-in-place behavior (allowCatchAll defaults to false).
final class PKMPathManagerCatchAllTests: XCTestCase {
    var root: String!
    var pathManager: PKMPathManager!

    override func setUpWithError() throws {
        root = NSTemporaryDirectory() + "pkm-catchall-tests-" + UUID().uuidString
        try FileManager.default.createDirectory(atPath: root, withIntermediateDirectories: true)
        pathManager = PKMPathManager(root: root)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(atPath: root)
    }

    private func result(
        para: PARACategory,
        targetFolder: String,
        project: String? = nil,
        isMediaAsset: Bool = false
    ) -> ClassifyResult {
        ClassifyResult(
            para: para,
            tags: [],
            summary: "",
            targetFolder: targetFolder,
            project: project,
            confidence: 1.0,
            relatedNotes: [],
            isMediaAsset: isMediaAsset
        )
    }

    // MARK: - allowCatchAll = true (new intake)

    func testEmptyResourceRoutesToUnsortedWhenAllowed() {
        let dir = pathManager.targetDirectory(
            for: result(para: .resource, targetFolder: ""),
            allowCatchAll: true
        )
        XCTAssertEqual(dir, pathManager.resourcePath + "/Unsorted")
    }

    func testEmptyAreaRoutesToUnsortedWhenAllowed() {
        let dir = pathManager.targetDirectory(
            for: result(para: .area, targetFolder: ""),
            allowCatchAll: true
        )
        XCTAssertEqual(dir, pathManager.areaPath + "/Unsorted")
    }

    /// A target folder that sanitizes to empty (e.g. the bare category name) is
    /// treated like an empty folder — it also routes to Unsorted.
    func testSanitizedToEmptyResourceRoutesToUnsortedWhenAllowed() {
        let dir = pathManager.targetDirectory(
            for: result(para: .area, targetFolder: "2_Area"),
            allowCatchAll: true
        )
        XCTAssertEqual(dir, pathManager.areaPath + "/Unsorted")
    }

    /// Catch-all folder has NO leading underscore (underscore folders are skipped
    /// across index/link/synthesis/search), so it stays visible to the pipeline.
    func testCatchAllFolderHasNoUnderscore() {
        let dir = pathManager.targetDirectory(
            for: result(para: .resource, targetFolder: ""),
            allowCatchAll: true
        )
        let last = (dir as NSString).lastPathComponent
        XCTAssertFalse(last.hasPrefix("_"), "catch-all folder must not be underscore-prefixed")
    }

    // MARK: - Project excluded

    func testEmptyProjectNotRerouted() {
        let dir = pathManager.targetDirectory(
            for: result(para: .project, targetFolder: "", project: nil),
            allowCatchAll: true
        )
        XCTAssertEqual(dir, pathManager.projectsPath)
    }

    // MARK: - Media unchanged

    func testMediaAssetNotRerouted() {
        let dir = pathManager.targetDirectory(
            for: result(para: .resource, targetFolder: "", isMediaAsset: true),
            allowCatchAll: true
        )
        XCTAssertEqual(dir, pathManager.resourcePath)
    }

    // MARK: - Non-empty target unaffected

    func testNonEmptyTargetUnaffectedByCatchAll() {
        let dir = pathManager.targetDirectory(
            for: result(para: .resource, targetFolder: "DevOps"),
            allowCatchAll: true
        )
        XCTAssertEqual(dir, pathManager.resourcePath + "/DevOps")
    }

    // MARK: - allowCatchAll = false (reorganizers / default)

    func testEmptyResourceKeepsCategoryRootWhenNotAllowed() {
        let dir = pathManager.targetDirectory(
            for: result(para: .resource, targetFolder: "")
        )
        XCTAssertEqual(dir, pathManager.resourcePath)
    }

    func testEmptyAreaKeepsCategoryRootWhenNotAllowed() {
        let dir = pathManager.targetDirectory(
            for: result(para: .area, targetFolder: ""),
            allowCatchAll: false
        )
        XCTAssertEqual(dir, pathManager.areaPath)
    }
}
