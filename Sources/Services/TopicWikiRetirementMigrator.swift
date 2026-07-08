import Foundation

/// One-time v19 migration. v2.18.0 shipped the `_Wiki/` topic wiki; v19 retired
/// it in favor of the in-PARA synthesis hierarchy, so existing vaults are left
/// with stale `_Wiki/*.md` pages that the companion docs no longer mention.
/// Strips the DotBrain block from each page (a page becomes fully user-authored
/// once its block is gone), deletes pages with nothing user-authored left, and
/// removes the `_Wiki` folder once empty.
///
/// This is a destructive one-shot over user vault content, so it follows the
/// `ReverseLinkRelationMigrator` pattern — its own `.meta` marker, written only
/// when every page succeeded, so a partial failure (locked file, permissions)
/// retries on the next launch. The companion version stamp deliberately writes
/// even on partial generation failure, which is right for regenerable templates
/// but would suppress retries forever here.
struct TopicWikiRetirementMigrator: Sendable {
    let pkmRoot: String

    private static let markerRelPath = ".meta/topic-wiki-retirement-v1"

    func migrateIfNeeded() async {
        let fm = FileManager.default
        let markerPath = (pkmRoot as NSString).appendingPathComponent(Self.markerRelPath)
        guard !fm.fileExists(atPath: markerPath) else { return }
        guard fm.fileExists(atPath: pkmRoot) else { return }

        let (cleaned, failures) = cleanWikiPages()

        if cleaned > 0 {
            VaultLogService(pkmRoot: pkmRoot).append(
                kind: "migration",
                summary: "주제 위키 종료: _Wiki 페이지 \(cleaned)개 정리"
            )
            NSLog("[TopicWikiRetirementMigrator] _Wiki 페이지 %d개 정리", cleaned)
        }

        // A failed page would stay stale forever if the marker suppressed
        // future runs — skip the marker so the next launch retries. Cleaned
        // pages no longer carry the DotBrain block, so the rescan only
        // reprocesses whatever actually failed.
        guard failures == 0 else { return }

        let metaDir = (pkmRoot as NSString).appendingPathComponent(".meta")
        if !fm.fileExists(atPath: metaDir) {
            try? fm.createDirectory(atPath: metaDir, withIntermediateDirectories: true)
        }
        try? "1".write(toFile: markerPath, atomically: true, encoding: .utf8)
    }

    // MARK: - Private

    private func cleanWikiPages() -> (cleaned: Int, failures: Int) {
        let fm = FileManager.default
        let wikiDir = (pkmRoot as NSString).appendingPathComponent("_Wiki")
        guard fm.fileExists(atPath: wikiDir),
              let entries = try? fm.contentsOfDirectory(atPath: wikiDir) else {
            return (0, 0)
        }

        var cleaned = 0
        var failures = 0
        for entry in entries where entry.hasSuffix(".md") {
            let path = (wikiDir as NSString).appendingPathComponent(entry)
            // Topic pages used the same DotBrain markers as folder pages
            guard let existing = try? String(contentsOfFile: path, encoding: .utf8),
                  let stripped = FolderNotePage.strippingSynthesis(from: existing) else {
                continue  // marker-less page is fully user-authored — untouched
            }
            let userBody = Frontmatter.parse(markdown: stripped).body
                .trimmingCharacters(in: .whitespacesAndNewlines)
            do {
                if userBody.isEmpty {
                    try fm.trashItem(at: URL(fileURLWithPath: path), resultingItemURL: nil)
                    NSLog("[TopicWikiRetirementMigrator] _Wiki/%@ 삭제", entry)
                } else {
                    try stripped.write(toFile: path, atomically: true, encoding: .utf8)
                    NSLog("[TopicWikiRetirementMigrator] _Wiki/%@에서 DotBrain 블록 제거", entry)
                }
                cleaned += 1
            } catch {
                NSLog("[TopicWikiRetirementMigrator] _Wiki/%@ 정리 실패: %@",
                      entry, error.localizedDescription)
                failures += 1
            }
        }

        // Remove the _Wiki folder once no visible entries remain
        if failures == 0,
           let remaining = try? fm.contentsOfDirectory(atPath: wikiDir),
           remaining.allSatisfy({ $0.hasPrefix(".") }) {
            try? fm.removeItem(atPath: wikiDir)
        }
        return (cleaned, failures)
    }
}
