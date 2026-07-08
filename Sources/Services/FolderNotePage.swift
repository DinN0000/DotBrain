import Foundation

/// Pure marker-section logic for folder entity pages (<folder>.md).
/// The synthesis lives between DotBrain markers; every byte outside the
/// markers is user content and must be preserved.
struct FolderNotePage {
    static let markerStart = "<!-- DotBrain:start -->"
    static let markerEnd = "<!-- DotBrain:end -->"
    private static let hashCommentPrefix = "<!-- dotbrain-synthesis-hash: "

    /// True when the file carries a DotBrain synthesis section
    static func isEntityPage(_ content: String) -> Bool {
        content.contains(markerStart)
    }

    /// Stored inputs hash — used to skip AI calls when members are unchanged
    static func inputsHash(from content: String) -> String? {
        guard let range = content.range(of: hashCommentPrefix),
              let end = content.range(of: " -->", range: range.upperBound..<content.endIndex) else {
            return nil
        }
        return String(content[range.upperBound..<end.lowerBound])
    }

    /// First paragraph under "## 개요" inside the marker section —
    /// NoteIndexGenerator uses this as the folder summary (no AI)
    static func overview(from content: String) -> String? {
        guard let start = content.range(of: markerStart),
              let end = content.range(of: markerEnd, range: start.upperBound..<content.endIndex),
              let heading = content.range(of: "## 개요", range: start.upperBound..<end.lowerBound) else {
            return nil
        }
        let after = content[heading.upperBound..<end.lowerBound]
        let lines = after.split(separator: "\n", omittingEmptySubsequences: false).map(String.init)
        var paragraph: [String] = []
        for line in lines {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed.hasPrefix("#") || trimmed.hasPrefix("<!--") {
                if !paragraph.isEmpty { break }
                continue
            }
            if trimmed.isEmpty {
                if !paragraph.isEmpty { break }
                continue
            }
            paragraph.append(trimmed)
        }
        return paragraph.isEmpty ? nil : paragraph.joined(separator: " ")
    }

    /// Full synthesis body between the markers with comment lines stripped —
    /// fed back into the next prompt so "최근 흐름" items carry forward across
    /// runs instead of being overwritten.
    static func synthesisSection(from content: String) -> String? {
        guard let start = content.range(of: markerStart),
              let end = content.range(of: markerEnd, range: start.upperBound..<content.endIndex) else {
            return nil
        }
        let body = content[start.upperBound..<end.lowerBound]
        let cleaned = body
            .split(separator: "\n", omittingEmptySubsequences: false)
            .filter { !$0.trimmingCharacters(in: .whitespaces).hasPrefix("<!--") }
            .joined(separator: "\n")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return cleaned.isEmpty ? nil : cleaned
    }

    /// Replace (or create) the synthesis section. nil content = new file.
    static func replacingSynthesis(
        in content: String?,
        synthesis: String,
        inputsHash: String,
        folderName: String,
        para: PARACategory
    ) -> String {
        let section = """
        \(markerStart)
        \(hashCommentPrefix)\(inputsHash) -->
        \(synthesis.trimmingCharacters(in: .whitespacesAndNewlines))
        \(markerEnd)
        """

        guard let existing = content else {
            var fm = Frontmatter(tags: [])
            fm.para = para
            fm.created = Frontmatter.today()
            fm.summary = overview(from: section)
            return fm.stringify() + "\n" + section + "\n"
        }

        if let start = existing.range(of: markerStart),
           let end = existing.range(of: markerEnd, range: start.upperBound..<existing.endIndex) {
            var updated = existing
            updated.replaceSubrange(start.lowerBound..<end.upperBound, with: section)
            return updated
        }

        // No markers yet: frontmatter stays first, section goes right after it,
        // existing body is preserved below
        let (fm, body) = Frontmatter.parse(markdown: existing)
        let hasFrontmatter = existing.hasPrefix("---")
        if hasFrontmatter {
            return fm.stringify() + "\n" + section + "\n\n" + body
        }
        return section + "\n\n" + existing
    }
}
