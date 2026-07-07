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

    func testAppendSanitizesNewlinesToKeepOneLinePerEntry() throws {
        let log = VaultLogService(pkmRoot: root)
        log.append(kind: "agent", summary: "여러 줄\n요약\n시도")

        let content = try String(contentsOfFile: log.logPath(), encoding: .utf8)
        let entries = content.components(separatedBy: "\n").filter { $0.hasPrefix("- [") }
        XCTAssertEqual(entries.count, 1, "newlines in summary must not split the entry")
        XCTAssertTrue(entries[0].contains("여러 줄 요약 시도"))
    }
}
