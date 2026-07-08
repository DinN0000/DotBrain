import XCTest
@testable import DotBrain

final class VaultLogServiceTests: XCTestCase {
    var root: String!

    override func setUpWithError() throws {
        root = NSTemporaryDirectory() + "vault-log-tests-" + UUID().uuidString
        try FileManager.default.createDirectory(atPath: root, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(atPath: root)
    }

    func testAppendCreatesFileWithHeaderThenAppends() throws {
        let log = VaultLogService(pkmRoot: root)
        log.append(kind: "ingest", summary: "3개 파일")
        log.append(kind: "vault-check", summary: "0건 발견")

        let content = try String(contentsOfFile: log.logPath(), encoding: .utf8)
        XCTAssertTrue(content.hasPrefix("# Vault Log"), "first write must include the header")
        let entries = content.components(separatedBy: "\n").filter { $0.hasPrefix("- [") }
        XCTAssertEqual(entries.count, 2)
        XCTAssertTrue(entries[0].contains("ingest | 3개 파일"))
        XCTAssertTrue(entries[1].contains("vault-check | 0건 발견"))
    }

    func testAppendWritesHeaderIntoPreexistingEmptyFile() throws {
        let log = VaultLogService(pkmRoot: root)
        try FileManager.default.createDirectory(
            atPath: root + "/.meta", withIntermediateDirectories: true)
        FileManager.default.createFile(atPath: log.logPath(), contents: nil)

        log.append(kind: "ingest", summary: "첫 항목")

        let content = try String(contentsOfFile: log.logPath(), encoding: .utf8)
        XCTAssertTrue(content.hasPrefix("# Vault Log"),
                      "empty pre-existing file must still get the header")
    }

    func testAppendSynthesisEntryWritesOneScopedLine() throws {
        // 3b: each folder/hub page write appends one "<scope>: <요지>" line so
        // the chronicle records how synthesis evolved.
        let log = VaultLogService(pkmRoot: root)
        log.append(kind: "synthesis", summary: "MyProject: 프로젝트가 Phase 2로 진입함.")

        let content = try String(contentsOfFile: log.logPath(), encoding: .utf8)
        let entries = content.components(separatedBy: "\n").filter { $0.hasPrefix("- [") }
        XCTAssertEqual(entries.count, 1)
        XCTAssertTrue(entries[0].contains("synthesis | MyProject: 프로젝트가 Phase 2로 진입함."))
    }

    func testAppendSanitizesNewlinesToKeepOneLinePerEntry() throws {
        let log = VaultLogService(pkmRoot: root)
        log.append(kind: "agent", summary: "여러 줄\n요약\n시도")

        let content = try String(contentsOfFile: log.logPath(), encoding: .utf8)
        let entries = content.components(separatedBy: "\n").filter { $0.hasPrefix("- [") }
        XCTAssertEqual(entries.count, 1, "newlines in summary must not split the entry")
        XCTAssertTrue(entries[0].contains("여러 줄 요약 시도"))
    }
}
