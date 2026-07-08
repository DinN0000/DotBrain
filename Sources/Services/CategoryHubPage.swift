import Foundation

/// Hub-specific page logic. A category hub page (`<N_Category>/<N_Category>.md`)
/// is structurally a folder page — markers, hash comment, and block replacement
/// all live on `FolderNotePage`. The only genuinely hub-specific operation is
/// slicing a *subfolder* page down to its STABLE input for the hub prompt.
enum CategoryHubPage {
    /// STABLE, bounded slice of a *subfolder* page: its `## 개요` + `## 핵심 노트`
    /// sections only. Excludes the churny `## 최근 흐름` (and `## 모순`/`## 노후`)
    /// and comment lines so a subfolder's timeline/timestamp update never flips
    /// the hub hash (feed == gate). Returns nil when neither section is present.
    static func stableSlice(from content: String) -> String? {
        guard let body = FolderNotePage.synthesisSection(from: content) else { return nil }
        let wanted: Set<String> = ["## 개요", "## 핵심 노트"]
        var kept: [String] = []
        var inWanted = false
        for line in body.components(separatedBy: "\n") {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed.hasPrefix("## ") {
                inWanted = wanted.contains(trimmed)
                if inWanted { kept.append(line) }
                continue
            }
            if inWanted { kept.append(line) }
        }
        let cleaned = kept.joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines)
        return cleaned.isEmpty ? nil : cleaned
    }
}
