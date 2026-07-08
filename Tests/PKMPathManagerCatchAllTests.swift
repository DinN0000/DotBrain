import XCTest
@testable import DotBrain

/// R2 new-intake routing: Area/Resource notes with no AI-assigned subfolder land
/// in a `Unsorted` catch-all instead of the bare category root. The policy is
/// materialized ONCE into the classification at the intake boundary
/// (`materializedCatchAll`), so the conflict check, pending-confirmation
/// round-trip, and the move all agree by construction. `targetDirectory` itself
/// stays policy-free — reorganizers keep their keep-in-place behavior simply by
/// never materializing.
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

    // MARK: - Materialization (new intake)

    func testEmptyResourceMaterializesToUnsorted() {
        let adjusted = pathManager.materializedCatchAll(
            for: result(para: .resource, targetFolder: "")
        )
        XCTAssertEqual(adjusted.targetFolder, "Unsorted")
        XCTAssertEqual(pathManager.targetDirectory(for: adjusted),
                       pathManager.resourcePath + "/Unsorted")
    }

    func testEmptyAreaMaterializesToUnsorted() {
        let adjusted = pathManager.materializedCatchAll(
            for: result(para: .area, targetFolder: "")
        )
        XCTAssertEqual(pathManager.targetDirectory(for: adjusted),
                       pathManager.areaPath + "/Unsorted")
    }

    /// A target folder that sanitizes to empty (e.g. the bare category name) is
    /// treated like an empty folder — it also materializes to Unsorted. This is
    /// the case a destination-time flag could not cover consistently.
    func testSanitizedToEmptyAreaMaterializesToUnsorted() {
        let adjusted = pathManager.materializedCatchAll(
            for: result(para: .area, targetFolder: "2_Area")
        )
        XCTAssertEqual(pathManager.targetDirectory(for: adjusted),
                       pathManager.areaPath + "/Unsorted")
    }

    /// Catch-all folder has NO leading underscore (underscore folders are skipped
    /// across index/link/synthesis/search), so it stays visible to the pipeline.
    func testCatchAllFolderHasNoUnderscore() {
        XCTAssertFalse(PKMPathManager.catchAllFolderName.hasPrefix("_"),
                       "catch-all folder must not be underscore-prefixed")
    }

    // MARK: - Exclusions

    func testEmptyProjectNotMaterialized() {
        let adjusted = pathManager.materializedCatchAll(
            for: result(para: .project, targetFolder: "", project: nil)
        )
        XCTAssertEqual(adjusted.targetFolder, "",
                       "Project keeps the suggestedProject-confirm flow")
        XCTAssertEqual(pathManager.targetDirectory(for: adjusted), pathManager.projectsPath)
    }

    func testMediaAssetNotMaterialized() {
        let adjusted = pathManager.materializedCatchAll(
            for: result(para: .resource, targetFolder: "", isMediaAsset: true)
        )
        XCTAssertEqual(adjusted.targetFolder, "", "media keeps default asset routing")
    }

    func testNonEmptyTargetNotMaterialized() {
        let adjusted = pathManager.materializedCatchAll(
            for: result(para: .resource, targetFolder: "DevOps")
        )
        XCTAssertEqual(adjusted.targetFolder, "DevOps")
        XCTAssertEqual(pathManager.targetDirectory(for: adjusted),
                       pathManager.resourcePath + "/DevOps")
    }

    // MARK: - targetDirectory stays policy-free (reorganizers)

    func testTargetDirectoryWithoutMaterializationKeepsCategoryRoot() {
        XCTAssertEqual(
            pathManager.targetDirectory(for: result(para: .resource, targetFolder: "")),
            pathManager.resourcePath,
            "reorganizers never materialize, so empty stays at the category root"
        )
        XCTAssertEqual(
            pathManager.targetDirectory(for: result(para: .area, targetFolder: "")),
            pathManager.areaPath
        )
    }

    // MARK: - Idempotence (safe if a path materializes twice)

    func testMaterializationIsIdempotent() {
        let once = pathManager.materializedCatchAll(
            for: result(para: .resource, targetFolder: "")
        )
        let twice = pathManager.materializedCatchAll(for: once)
        XCTAssertEqual(twice.targetFolder, "Unsorted")
    }
}
