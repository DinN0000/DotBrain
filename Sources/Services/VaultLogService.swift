import Foundation

/// Append-only chronological log of vault evolution at .meta/log.md.
/// One line per event with a grep-able prefix so both AI companions and
/// unix tools can read the recent timeline:
///   - [2026-07-07 15:30] ingest | 3개 노트 → 2_Area/SwiftUI-패턴, 링크 +12
/// DotBrain pipelines append here; AI agents are instructed (companion docs)
/// to append their own maintenance entries in the same format.
struct VaultLogService: Sendable {
    let pkmRoot: String

    private static let header = "# Vault Log\n\nDotBrain과 AI 에이전트가 기록하는 볼트 변경 타임라인. 형식: `- [날짜 시각] 종류 | 요약`\n\n"

    func append(kind: String, summary: String) {
        let fm = FileManager.default
        let metaDir = (pkmRoot as NSString).appendingPathComponent(".meta")
        if !fm.fileExists(atPath: metaDir) {
            try? fm.createDirectory(atPath: metaDir, withIntermediateDirectories: true)
        }

        let sanitized = summary
            .replacingOccurrences(of: "\n", with: " ")
            .trimmingCharacters(in: .whitespaces)
        let line = "- [\(Self.timestamp())] \(kind) | \(sanitized)\n"

        let path = logPath()
        if let handle = FileHandle(forWritingAtPath: path) {
            defer { handle.closeFile() }
            handle.seekToEndOfFile()
            if let data = line.data(using: .utf8) {
                handle.write(data)
            }
        } else {
            try? (Self.header + line).write(toFile: path, atomically: true, encoding: .utf8)
        }
    }

    func logPath() -> String {
        (pkmRoot as NSString).appendingPathComponent(".meta/log.md")
    }

    private static func timestamp() -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd HH:mm"
        formatter.locale = Locale(identifier: "en_US_POSIX")
        return formatter.string(from: Date())
    }
}
