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
        do {
            // Throwing FileHandle API: disk-full/unmounted surface as Swift
            // errors instead of uncatchable NSExceptions from the legacy write
            if let handle = FileHandle(forWritingAtPath: path) {
                defer { try? handle.close() }
                let end = try handle.seekToEnd()
                let text = (end == 0 ? Self.header : "") + line
                if let data = text.data(using: .utf8) {
                    try handle.write(contentsOf: data)
                }
            } else {
                try (Self.header + line).write(toFile: path, atomically: true, encoding: .utf8)
            }
        } catch {
            NSLog("[VaultLogService] 로그 기록 실패: %@", error.localizedDescription)
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
