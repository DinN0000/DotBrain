import Foundation

/// Pure marker-section logic for category hub pages
/// (`<N_Category>/<N_Category>.md`). A hub page is structurally a folder page —
/// same DotBrain markers, same hash comment — so marker read/write reuses
/// `FolderNotePage`. What is genuinely hub-specific is (1) slicing a *subfolder*
/// page down to its STABLE `## 개요` + `## 핵심 노트` input, and (2) stripping the
/// whole synthesis block when a category drops below 2 subfolders.
struct CategoryHubPage {
    /// Reuse the folder-page markers so a hub page reads identically to a
    /// subfolder page — companion docs and orphan cleanup expect one marker
    /// vocabulary, and Task 6 keys off `DotBrain:start`.
    static var markerStart: String { FolderNotePage.markerStart }
    static var markerEnd: String { FolderNotePage.markerEnd }

    /// Stored inputs hash — used to skip AI calls when the stable slices are
    /// unchanged. Identical format to a folder page, so delegate.
    static func inputsHash(from content: String) -> String? {
        FolderNotePage.inputsHash(from: content)
    }

    /// Replace (or create) the synthesis section. nil content = new file.
    static func replacingSynthesis(
        in content: String?,
        synthesis: String,
        inputsHash: String,
        folderName: String,
        para: PARACategory
    ) -> String {
        FolderNotePage.replacingSynthesis(
            in: content, synthesis: synthesis,
            inputsHash: inputsHash, folderName: folderName, para: para
        )
    }

    /// STABLE, bounded slice of a *subfolder* page: its `## 개요` + `## 핵심 노트`
    /// sections only. Excludes the churny `## 최근 흐름` (and `## 모순`/`## 노후`)
    /// and the hash comment so a subfolder's timeline/timestamp update never
    /// flips the hub hash (feed == gate). Returns nil when neither section is
    /// present.
    static func stableSlice(from content: String) -> String? {
        guard let start = content.range(of: markerStart),
              let end = content.range(of: markerEnd, range: start.upperBound..<content.endIndex) else {
            return nil
        }
        let body = content[start.upperBound..<end.lowerBound]
        let wanted: Set<String> = ["## 개요", "## 핵심 노트"]
        var kept: [String] = []
        var inWanted = false
        for rawLine in body.split(separator: "\n", omittingEmptySubsequences: false).map(String.init) {
            let trimmed = rawLine.trimmingCharacters(in: .whitespaces)
            if trimmed.hasPrefix("## ") {
                inWanted = wanted.contains(trimmed)
                if inWanted { kept.append(rawLine) }
                continue
            }
            guard inWanted else { continue }
            if trimmed.hasPrefix("<!--") { continue }
            kept.append(rawLine)
        }
        let cleaned = kept.joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines)
        return cleaned.isEmpty ? nil : cleaned
    }

    /// Remove the entire DotBrain synthesis block, preserving every byte of user
    /// content outside the markers. Returns nil when the file carries no block.
    /// Used when a category drops below 2 subfolders — the hub has nothing left
    /// to synthesize across.
    static func strippingSynthesis(from content: String) -> String? {
        var result = content
        guard let start = result.range(of: markerStart),
              let end = result.range(of: markerEnd, range: start.upperBound..<result.endIndex) else {
            return nil
        }
        var removeEnd = end.upperBound
        // Absorb the trailing newline(s) the block leaves behind so no gap remains
        while removeEnd < result.endIndex, result[removeEnd] == "\n" {
            removeEnd = result.index(after: removeEnd)
        }
        result.removeSubrange(start.lowerBound..<removeEnd)
        return result
    }
}
