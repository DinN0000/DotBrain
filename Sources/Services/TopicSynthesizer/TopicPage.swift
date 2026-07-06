import Foundation

/// Pure marker-section logic for topic wiki pages (_Wiki/<name>.md).
/// The synthesis lives between DotBrain markers; every byte outside the
/// markers is user content and must be preserved. Mirrors FolderNotePage.
struct TopicPage {
    static let markerStart = "<!-- DotBrain:start -->"
    static let markerEnd = "<!-- DotBrain:end -->"
    private static let topicCommentPrefix = "<!-- dotbrain-topic: "
    private static let hashCommentPrefix = "<!-- dotbrain-synthesis-hash: "

    static func topicId(from content: String) -> String? {
        commentValue(in: content, prefix: topicCommentPrefix)
    }

    /// Stored inputs hash — used to skip AI calls when members are unchanged
    static func inputsHash(from content: String) -> String? {
        commentValue(in: content, prefix: hashCommentPrefix)
    }

    /// First paragraph under "## 현재 이해" — harvested into Topic.summary
    static func currentUnderstanding(from content: String) -> String? {
        guard let start = content.range(of: markerStart),
              let end = content.range(of: markerEnd, range: start.upperBound..<content.endIndex),
              let heading = content.range(of: "## 현재 이해", range: start.upperBound..<end.lowerBound) else {
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

    /// Previous synthesis body (between markers, comment lines stripped) —
    /// fed into the next synthesis prompt as the baseline understanding
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
        topicId: String
    ) -> String {
        let section = """
        \(markerStart)
        \(topicCommentPrefix)\(topicId) -->
        \(hashCommentPrefix)\(inputsHash) -->
        \(synthesis.trimmingCharacters(in: .whitespacesAndNewlines))
        \(markerEnd)
        """

        guard let existing = content else {
            var fm = Frontmatter(tags: ["topic"])
            fm.created = Frontmatter.today()
            fm.summary = currentUnderstanding(from: section)
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
        if existing.hasPrefix("---") {
            return fm.stringify() + "\n" + section + "\n\n" + body
        }
        return section + "\n\n" + existing
    }

    // MARK: - Private

    private static func commentValue(in content: String, prefix: String) -> String? {
        guard let range = content.range(of: prefix),
              let end = content.range(of: " -->", range: range.upperBound..<content.endIndex) else {
            return nil
        }
        return String(content[range.upperBound..<end.lowerBound])
    }
}
